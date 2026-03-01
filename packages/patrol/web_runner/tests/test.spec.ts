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

    // Use "domcontentloaded" instead of "load" — Flutter WASM initialization
    // can delay the "load" event by many minutes on large apps. By the time
    // domcontentloaded fires, Playwright can set __patrol__isInitialised before
    // Flutter's Dart code even starts, avoiding the race condition entirely.
    await page.goto("/", { waitUntil: "domcontentloaded" })

    await exposePatrolPlatformHandler(page)

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
    await page.evaluate(async name => await window.__patrol__runTest!(name), name)
  })
}
