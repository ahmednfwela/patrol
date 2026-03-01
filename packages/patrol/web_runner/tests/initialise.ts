import { Page } from "@playwright/test"

// How long to wait for the Flutter/Dart side to call back __patrol__onInitialised.
// Flutter WASM apps can take a long time to fully boot, so this is configurable
// via PATROL_WEB_INIT_TIMEOUT (milliseconds). Defaults to 120 seconds.
const initTimeout = process.env.PATROL_WEB_INIT_TIMEOUT
  ? parseInt(process.env.PATROL_WEB_INIT_TIMEOUT)
  : 120000

export async function initialise(page: Page) {
  await page.evaluate(() => {
    window.__patrol__isInitialised = true
  })

  await page.waitForFunction(
    () => {
      if (!window.__patrol__onInitialised) return false

      window.__patrol__onInitialised()

      return true
    },
    { timeout: initTimeout },
  )
}
