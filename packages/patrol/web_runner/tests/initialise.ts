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

  // In DDC debug mode (Flutter 3.41+ / Dart 3.11+, DWDS 26.x), the bootstrap
  // creates window.$dartRunMain() and waits for DWDS to call it. DWDS only
  // does this for the first browser connection; subsequent page loads (e.g. the
  // test phase after setup closes) never get the "run main" signal.
  //
  // Detect this and call $dartRunMain ourselves if DWDS hasn't.
  try {
    logger.info("Waiting for DDC module loading to complete...")
    await page.waitForFunction(
      () => typeof window.$dartRunMain === "function",
      { timeout: initTimeout },
    )

    // Give DWDS 2s to call $dartRunMain itself (avoids double-init race)
    await page.waitForFunction(() => !!window.$dartMainExecuted, { timeout: 2000 }).catch(() => {
      // DWDS didn't call it within 2s — we need to do it manually
    })

    const dartMainAlreadyRan = await page.evaluate(() => !!window.$dartMainExecuted)
    if (!dartMainAlreadyRan) {
      logger.info("DWDS did not call $dartRunMain — invoking it manually")
      await page.evaluate(() => window.$dartRunMain!())
    }
  } catch {
    // $dartRunMain may not exist in release/profile builds or WASM — that's fine,
    // the Dart entrypoint runs automatically in those modes.
    logger.info("No $dartRunMain found (non-DDC build?) — continuing")
  }

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
