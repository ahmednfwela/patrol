import { test as base } from "@playwright/test"
import { initialise } from "./initialise"
import { logger } from "./logger"
import { exposePatrolPlatformHandler } from "./patrolPlatformHandler"
import { PatrolTestEntry } from "./types"

const tests: PatrolTestEntry[] = process.env.PATROL_TESTS ? JSON.parse(process.env.PATROL_TESTS) : []
if (tests.length === 0) {
  logger.error("PATROL_TESTS env is empty")
}

export const patrolTest = base.extend({
  page: async ({ page }, use) => {
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

    // Go to the page and wait for domcontentloaded before we start injecting things
    await page.goto("/", { waitUntil: "domcontentloaded" })

    // Inject immediately upon load just to ensure tests have it right now
    await page.evaluate(() => {
      window.__patrol__isInitialised = true
    })

    await initialise(page)

    await use(page)
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
