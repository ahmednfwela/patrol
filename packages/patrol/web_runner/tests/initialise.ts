import { Page } from "@playwright/test"
import { logger } from "./logger"

// How long to wait for the Flutter/Dart side to call back __patrol__onInitialised.
// Flutter WASM apps can take a long time to fully boot, so this is configurable
// via PATROL_WEB_INIT_TIMEOUT (milliseconds). Defaults to 120 seconds.
const initTimeout = process.env.PATROL_WEB_INIT_TIMEOUT
  ? parseInt(process.env.PATROL_WEB_INIT_TIMEOUT)
  : 120000

export async function initialise(page: Page) {
  // Set the flag on the current JS context as well (belt-and-suspenders with
  // the addInitScript registered by callers before navigation).
  await page.evaluate(() => {
    window.__patrol__isInitialised = true
  })

  logger.info("Waiting for Flutter/Dart to set __patrol__onInitialised (timeout: %dms)...", initTimeout)

  // Log periodic progress so the user knows we are still waiting for WASM.
  const start = Date.now()
  const progressInterval = setInterval(() => {
    const elapsed = ((Date.now() - start) / 1000).toFixed(1)
    logger.info("Still waiting for Flutter app to initialise... (%ss elapsed)", elapsed)
  }, 15000)

  try {
    await page.waitForFunction(
      () => {
        if (!window.__patrol__onInitialised) return false

        window.__patrol__onInitialised()

        return true
      },
      { timeout: initTimeout },
    )
    const elapsed = ((Date.now() - start) / 1000).toFixed(1)
    logger.info("Flutter app initialised successfully (%ss)", elapsed)
  } finally {
    clearInterval(progressInterval)
  }
}
