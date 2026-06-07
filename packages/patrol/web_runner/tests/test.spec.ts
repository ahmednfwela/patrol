import { type BrowserContext, type Page, chromium, test as base } from "@playwright/test"
import { initialise } from "./initialise"
import { logger } from "./logger"
import { exposePatrolPlatformHandler } from "./patrolPlatformHandler"
import { PatrolTestEntry } from "./types"
const tests: PatrolTestEntry[] = process.env.PATROL_TESTS ? JSON.parse(process.env.PATROL_TESTS) : []
if (tests.length === 0) {
  logger.error("PATROL_TESTS env is empty")
}

const debuggerPort = process.env.PATROL_DEBUGGER_PORT
const collectCoverage = !!process.env.PATROL_WEB_COVERAGE
const coverageDir = process.env.PATROL_WEB_COVERAGE_DIR || "coverage"
// "context" = fresh BrowserContext per test (strongest isolation, default)
// "page" = same context, new page per test (shared cookies/storage)
const isolationMode = process.env.PATROL_WEB_ISOLATION || "context"

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type CoverageReporter = { add: (entries: any[]) => Promise<void>; generate: () => Promise<void> }

import * as fs from "fs"
import * as path from "path"

function buildPackageResolver(projectRoot: string) {
  const configPath = path.join(projectRoot, ".dart_tool", "package_config.json")
  if (!fs.existsSync(configPath)) {
    return () => null
  }
  const config = JSON.parse(fs.readFileSync(configPath, "utf8"))
  const packages: Record<string, string> = {}
  for (const pkg of config.packages ?? []) {
    const rootUri = (pkg.rootUri as string).replace(/\/$/, "")
    const absRoot = path.resolve(path.dirname(configPath), rootUri)
    packages[pkg.name] = path.join(absRoot, pkg.packageUri ?? "lib/")
  }
  return (uri: string): string | null => {
    const match = uri.match(/^package:([^/]+)\/(.+)$/)
    if (!match) {
      return null
    }
    const [, pkgName, relPath] = match
    const pkgLibDir = packages[pkgName]
    if (!pkgLibDir) {
      return null
    }
    const filePath = path.join(pkgLibDir, relPath)
    if (fs.existsSync(filePath)) {
      return fs.readFileSync(filePath, "utf8")
    }
    return null
  }
}

/**
 * Walks [dir] recursively and yields absolute paths for every `.dart` file.
 */
function* walkDartFiles(dir: string): Generator<string> {
  if (!fs.existsSync(dir)) return
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) {
      yield* walkDartFiles(full)
    } else if (entry.isFile() && entry.name.endsWith(".dart")) {
      yield full
    }
  }
}

/**
 * Parses the SF: lines from an LCOV file and returns a Set of absolute paths
 * that are already present in the report.
 */
function parseLcovFiles(lcovPath: string): Set<string> {
  const covered = new Set<string>()
  if (!fs.existsSync(lcovPath)) return covered
  for (const line of fs.readFileSync(lcovPath, "utf8").split("\n")) {
    if (line.startsWith("SF:")) {
      covered.add(path.resolve(line.slice(3).trim()))
    }
  }
  return covered
}

/**
 * Counts the lines in [source] that are likely executable (non-blank,
 * not pure-comment lines).  This is a conservative approximation — good
 * enough for LF/LH accuracy without a full Dart parser.
 */
function countExecutableLines(source: string): number[] {
  const lines = source.split("\n")
  const lineNumbers: number[] = []
  let inBlockComment = false
  for (let i = 0; i < lines.length; i++) {
    const trimmed = lines[i].trim()
    if (inBlockComment) {
      if (trimmed.includes("*/")) inBlockComment = false
      continue
    }
    if (trimmed.startsWith("/*")) {
      inBlockComment = !trimmed.includes("*/")
      continue
    }
    if (trimmed === "" || trimmed.startsWith("//") || trimmed === "{" || trimmed === "}") {
      continue
    }
    lineNumbers.push(i + 1) // 1-based
  }
  return lineNumbers
}

/**
 * Appends zero-fill LCOV stanzas to [lcovPath] for every `.dart` file found
 * under the `lib/` directory of each package in `package_config.json` that:
 *   - is not already present in [lcovPath], and
 *   - matches [packageFilter] when applied to `package:<name>/…` URIs
 *     (when [packageFilter] is null, all packages are included).
 *
 * Files whose absolute path is inside `node_modules` or `.dart_tool` are
 * always skipped.
 */
function appendZeroFillLcov(projectRoot: string, lcovPath: string, packageFilter: RegExp | null): void {
  const configPath = path.join(projectRoot, ".dart_tool", "package_config.json")
  if (!fs.existsSync(configPath)) {
    logger.warn("package_config.json not found at %s — skipping zero-fill", configPath)
    return
  }

  const config: { packages?: Array<{ name: string; rootUri: string; packageUri?: string }> } =
    JSON.parse(fs.readFileSync(configPath, "utf8"))

  const coveredFiles = parseLcovFiles(lcovPath)
  const stanzas: string[] = []

  for (const pkg of config.packages ?? []) {
    // Apply the same coverage filter that entryFilter uses, but against the
    // package URI scheme so the user's regex is meaningful.
    if (packageFilter && !packageFilter.test(`package:${pkg.name}/`)) {
      continue
    }

    const rootUri = (pkg.rootUri as string).replace(/\/$/, "")
    const absRoot = path.resolve(path.dirname(configPath), rootUri)
    const libDir = path.join(absRoot, (pkg.packageUri ?? "lib/").replace(/\/$/, ""))

    for (const dartFile of walkDartFiles(libDir)) {
      // Skip generated files and hidden directories
      if (dartFile.includes("node_modules") || dartFile.includes(".dart_tool")) continue

      const absFile = path.resolve(dartFile)
      if (coveredFiles.has(absFile)) continue

      const source = fs.readFileSync(absFile, "utf8")
      const executableLines = countExecutableLines(source)
      if (executableLines.length === 0) continue

      const daLines = executableLines.map(n => `DA:${n},0`).join("\n")
      stanzas.push(`SF:${absFile}\n${daLines}\nLH:0\nLF:${executableLines.length}\nend_of_record`)
    }
  }

  if (stanzas.length === 0) {
    logger.info("Zero-fill: all Dart files already present in LCOV (or no packages matched filter)")
    return
  }

  fs.appendFileSync(lcovPath, "\n" + stanzas.join("\n") + "\n")
  logger.info("Zero-fill: appended %d uncovered Dart file(s) to %s", stanzas.length, lcovPath)
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
async function resolveSourceMaps(entries: any[], projectRoot: string | null) {
  const resolve = projectRoot ? buildPackageResolver(projectRoot) : () => null
  for (const entry of entries) {
    if (entry.source && !entry.sourceMap) {
      const match = entry.source.match(/\/\/[#@]\s*sourceMappingURL=(\S+)/)
      if (match) {
        const mapUrl = new URL(match[1], entry.url).toString()
        try {
          const res = await fetch(mapUrl)
          if (res.ok) {
            const data = await res.json()
            if (data.sources && !data.sourcesContent) {
              data.sourcesContent = data.sources.map((s: string) => resolve(s) ?? "")
            }
            entry.sourceMap = data
          }
        } catch {
          // Source map fetch failed — coverage will use JS paths
        }
      }
    }
  }
}

async function setupPage(page: Page) {
  page.on("console", message => {
    const text = message.text()
    if (text.startsWith("PATROL_LOG")) {
      // eslint-disable-next-line no-console
      console.log(text)
      return
    }
    // eslint-disable-next-line no-console
    console.log(`Playwright: ${text}`)
  })

  page.on("pageerror", error => {
    if (error.message.includes("initializeEngineServices")) {
      logger.warn("Ignoring cosmetic engine re-init error")
      return
    }
    error.message = `Page error during test: ${error.message}`
    // eslint-disable-next-line no-console
    console.error(error.stack ?? error.message)
  })

  await page.addInitScript(() => {
    window.__patrol__isInitialised = true
  })

  await exposePatrolPlatformHandler(page)
  await page.goto("/", { waitUntil: "domcontentloaded" })

  await page.evaluate(() => {
    window.__patrol__isInitialised = true
  })

  await initialise(page)
}

export const patrolTest = base.extend<
  // eslint-disable-next-line @typescript-eslint/no-empty-object-type
  {},
  { sharedContext: BrowserContext; coverageReporter: CoverageReporter | null }
>({
  coverageReporter: [async ({}, use) => {
    if (!collectCoverage) {
      await use(null)
      return
    }
    const mod = await import("monocart-coverage-reports")
    const defaultEntryExcludes = /\/(dart_sdk|canvaskit|ddc_module_loader|dwds)\//
    const customFilter = process.env.PATROL_WEB_COVERAGE_FILTER
    // eslint-disable-next-line @typescript-eslint/no-unsafe-call
    const reporter: CoverageReporter = new (mod.default as any)({
      outputDir: coverageDir,
      reports: ["v8", "lcovonly"],
      name: "patrol_lcov",
      entryFilter: (entry: { url: string }) => {
        if (defaultEntryExcludes.test(entry.url)) return false
        if (customFilter) return new RegExp(customFilter).test(entry.url)
        return true
      },
    })
    await use(reporter)
    await reporter.generate()
    logger.info("Generated LCOV coverage report in %s", coverageDir)

    // Append zero-fill stanzas for Dart files that V8 never loaded.
    // This gives accurate LF (total lines) and LH (hit lines) counts,
    // matching what `flutter test --coverage` produces via getSourceReport.
    const projectRoot = coverageDir ? path.dirname(coverageDir) : process.cwd()
    const lcovFile = path.join(coverageDir, "lcov.info")
    const zeroFillFilter = customFilter ? new RegExp(customFilter) : null
    appendZeroFillLcov(projectRoot, lcovFile, zeroFillFilter)
  }, { scope: "worker" }],

  sharedContext: [async ({ browser }, use) => {
    if (isolationMode === "page") {
      const context = await browser.newContext()
      await use(context)
      await context.close()
    } else {
      await use(null as unknown as BrowserContext)
    }
  }, { scope: "worker" }],

  page: async ({ page: defaultPage, sharedContext, coverageReporter }, use) => {
    let page: Page = defaultPage

    if (debuggerPort) {
      logger.info("Connecting to Flutter Chrome via CDP on port %s", debuggerPort)
      const cdpBrowser = await chromium.connectOverCDP(`http://localhost:${debuggerPort}`)
      const context = cdpBrowser.contexts()[0]
      page = context.pages()[0] ?? await context.newPage()

      await exposePatrolPlatformHandler(page)

      page.on("console", message => {
        const text = message.text()
        if (text.startsWith("PATROL_LOG")) {
          // eslint-disable-next-line no-console
          console.log(text)
          return
        }
        // eslint-disable-next-line no-console
        console.log(`Playwright: ${text}`)
      })

      page.on("pageerror", error => {
        if (error.message.includes("initializeEngineServices")) {
          logger.warn("Ignoring cosmetic engine re-init error")
          return
        }
        error.message = `Page error during test: ${error.message}`
        // eslint-disable-next-line no-console
        console.error(error.stack ?? error.message)
      })

      if (coverageReporter) await page.coverage.startJSCoverage()
      await use(page)
      if (coverageReporter) {
        const entries = await page.coverage.stopJSCoverage()
        await resolveSourceMaps(entries, coverageDir ? path.dirname(coverageDir) : null)
        await coverageReporter.add(entries)
      }
      return
    }

    if (isolationMode === "page" && sharedContext) {
      page = await sharedContext.newPage()
    }

    await setupPage(page)

    if (coverageReporter) await page.coverage.startJSCoverage()
    await use(page)
    if (coverageReporter) {
      const entries = await page.coverage.stopJSCoverage()
      await resolveSourceMaps(entries, coverageDir ? path.dirname(coverageDir) : null)
      await coverageReporter.add(entries)
    }

    if (isolationMode === "page") {
      await page.close()
    }
  },
})

for (const { name, skip, tags } of tests) {
  patrolTest(name, { tag: tags }, async ({ page }) => {
    patrolTest.skip(skip)

    await page.waitForFunction(() => window.__patrol__runTest, {
      timeout: 300000,
    })

    // eslint-disable-next-line @typescript-eslint/no-non-null-assertion
    const result = await page.evaluate(async name => await window.__patrol__runTest!(name), name)
    if (result?.result === "failure") {
      throw new Error(result.details ?? `Test "${name}" failed`)
    }

    if (!collectCoverage) await page.close()
  })
}
