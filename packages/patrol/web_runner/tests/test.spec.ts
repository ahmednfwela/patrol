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
let mcr: any = null
if (collectCoverage) {
  import("monocart-coverage-reports").then(mod => {
    mcr = new mod.default({
      outputDir: coverageDir,
      reports: ["lcovonly"],
      name: "patrol_lcov",
    })
  })
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

export const patrolTest = base.extend<object, { sharedContext: BrowserContext }>({
  sharedContext: [async ({ browser }, use) => {
    if (isolationMode === "page") {
      const context = await browser.newContext()
      await use(context)
      await context.close()
    } else {
      await use(null as unknown as BrowserContext)
    }
  }, { scope: "worker" }],

  page: async ({ page: defaultPage, sharedContext }, use) => {
    let page: Page = defaultPage
    let cdpBrowser: Awaited<ReturnType<typeof chromium.connectOverCDP>> | null = null

    if (debuggerPort) {
      // Coverage mode: connect to Flutter's Chrome via CDP so DWDS can
      // collect coverage from the same isolate that runs the tests.
      logger.info("Connecting to Flutter Chrome via CDP on port %s", debuggerPort)
      cdpBrowser = await chromium.connectOverCDP(`http://localhost:${debuggerPort}`)
      const context = cdpBrowser.contexts()[0]
      page = context.pages()[0] ?? await context.newPage()

      // The app is already running and initialized in Flutter's Chrome.
      // Skip init scripts, navigation, and initialise() — they conflict
      // with the live app. But DO expose the platform handler so web
      // tests (dark mode, dialogs, cookies, etc.) can call back.
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

      if (collectCoverage) await page.coverage.startJSCoverage()
      await use(page)
      if (collectCoverage && mcr) {
        const entries = await page.coverage.stopJSCoverage()
        await mcr.add(entries)
      }
      return
    }

    // "page" mode: new page from shared context (shared cookies/storage)
    // "context" mode: use Playwright's default fresh context per test
    if (isolationMode === "page" && sharedContext) {
      page = await sharedContext.newPage()
    }

    await setupPage(page)

    if (collectCoverage) await page.coverage.startJSCoverage()
    await use(page)
    if (collectCoverage && mcr) {
      const entries = await page.coverage.stopJSCoverage()
      await mcr.add(entries)
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

    // Close the page *after* retrieving the result to ensure it gets fully torn
    // down before the next test spins up a new page context.
    // Skip when collecting coverage — stopJSCoverage runs in fixture teardown.
    if (!collectCoverage) await page.close()
  })
}

if (collectCoverage) {
  process.on("beforeExit", async () => {
    if (mcr) {
      await mcr.generate()
      logger.info("Generated LCOV coverage report in %s", coverageDir)
    }
  })
}

