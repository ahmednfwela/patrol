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
