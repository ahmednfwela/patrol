import { chromium, test as base } from "@playwright/test"
import { initialise } from "./initialise"
import { logger } from "./logger"
import { exposePatrolPlatformHandler } from "./patrolPlatformHandler"
import { PatrolTestEntry } from "./types"
import type { CoverageEntry } from "playwright"

const tests: PatrolTestEntry[] = process.env.PATROL_TESTS ? JSON.parse(process.env.PATROL_TESTS) : []
if (tests.length === 0) {
  logger.error("PATROL_TESTS env is empty")
}

const debuggerPort = process.env.PATROL_DEBUGGER_PORT
const collectCoverage = !!process.env.PATROL_WEB_COVERAGE
const allCoverageEntries: CoverageEntry[] = []

export const patrolTest = base.extend({
  page: async ({ page: defaultPage }, use) => {
    let page = defaultPage
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
        error.message = `Page error during test: ${error.message}`
        // eslint-disable-next-line no-console
        console.error(error.stack ?? error.message)
      })

      if (collectCoverage) await page.coverage.startJSCoverage()
      await use(page)
      if (collectCoverage) {
        const entries = await page.coverage.stopJSCoverage()
        allCoverageEntries.push(...entries)
      }
      return
    }

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
      error.message = `Page error during test: ${error.message}`
      // eslint-disable-next-line no-console
      console.error(error.stack ?? error.message)
    })

    // Register an init script that runs at the very start of every page load,
    // BEFORE any Flutter / WASM code executes.  This guarantees that
    // __patrol__isInitialised is true even if the page reloads during WASM
    // bootstrapping (service-worker activation, Flutter engine reinit, etc.).
    await page.addInitScript(() => {
      window.__patrol__isInitialised = true
    })

    await exposePatrolPlatformHandler(page)

    // Standard mode: navigate to the web-server URL
    await page.goto("/", { waitUntil: "domcontentloaded" })

    // Inject immediately upon load just to ensure tests have it right now
    await page.evaluate(() => {
      window.__patrol__isInitialised = true
    })

    await initialise(page)

    if (collectCoverage) await page.coverage.startJSCoverage()
    await use(page)
    if (collectCoverage) {
      const entries = await page.coverage.stopJSCoverage()
      allCoverageEntries.push(...entries)
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
    await page.close()
  })
}

if (collectCoverage) {
  patrolTest.afterAll(async () => {
    if (allCoverageEntries.length === 0) {
      logger.info("No V8 coverage entries collected")
      return
    }

    logger.info("Processing %d V8 coverage entries...", allCoverageEntries.length)
    const { processV8Coverage } = await import("./v8-coverage")
    await processV8Coverage(allCoverageEntries)
  })
}
