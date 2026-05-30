import { chromium, type FullConfig, type Page } from "@playwright/test"
import { initialise } from "./initialise"
import { exposePatrolPlatformHandler } from "./patrolPlatformHandler"
import { DartTestEntry, PatrolTestEntry } from "./types"

async function setup(config: FullConfig) {
  const { baseURL } = config.projects[0].use
  const browserArgs: string[] | undefined = process.env.PATROL_WEB_BROWSER_ARGS
    ? JSON.parse(process.env.PATROL_WEB_BROWSER_ARGS)
    : undefined

  const locale = process.env.PATROL_WEB_LOCALE || undefined

  const browser = await chromium.launch({
    args: browserArgs,
  })

  const page = await browser.newPage({ locale })

  if (!baseURL) {
    throw new Error("baseURL is not set")
  }

  const setupPageErrorPromise = new Promise<never>((_, reject) => {
    page.on("pageerror", error => {
      // Filter out cosmetic Flutter engine re-initialization errors.
      // In debug mode, the engine's initializeEngineServices() throws a StateError
      // inside assert() when called twice. This is harmless — the engine is already
      // initialized and the assert is stripped in release/profile mode.
      if (error.message.includes("initializeEngineServices")) {
        // eslint-disable-next-line no-console
        console.warn(`[patrol] Ignoring cosmetic engine error: ${error.message}`)
        return
      }

      error.message = `Page error during setup: ${error.message}`
      // eslint-disable-next-line no-console
      console.error(error.stack ?? error.message)
      reject(error)
    })
  })

  // Register an init script so __patrol__isInitialised is set before any
  // page script runs, surviving any page reload during WASM bootstrapping.
  await page.addInitScript(() => {
    window.__patrol__isInitialised = true
  })

  // Expose platform handler bindings before navigation to prevent race condition
  // during Flutter booting/initialization logic
  await exposePatrolPlatformHandler(page)

  // We want to initialize the platform handler and things *before* we potentially miss the boat
  // during load.
  await page.goto(baseURL, { waitUntil: "domcontentloaded" })

  // Inject a small script to guarantee the variable is set *right now* in case domcontentloaded
  // already cleared the context or something.
  await page.evaluate(() => {
    window.__patrol__isInitialised = true
  })

  await initialise(page)

  try {
    const testEntriesResponse = await discoverTestTree(page, setupPageErrorPromise)

    const patrolTests = mapEntry(testEntriesResponse.group)
    process.env.PATROL_TESTS = JSON.stringify(patrolTests)
  } finally {
    await browser.close()
  }
}

/**
 * Reads the Dart test tree exposed on the page, waiting until at least one test
 * has been registered.
 *
 * `window.__patrol__getTests()` becomes callable as soon as the patrol app
 * service boots, but on a slow/cold WASM boot it can briefly return a
 * truthy-but-empty group (`{ entries: [] }`) while the `patrolTest()`/`group()`
 * declarations are still executing. The previous implementation resolved on the
 * first truthy value, so it occasionally captured that empty snapshot, set
 * `PATROL_TESTS=[]`, and produced 0 Playwright tests — a flaky "no tests found"
 * (exit 1) that poisoned the entire shard. We therefore poll until the tree is
 * non-empty (bounded by the same 120s timeout). If the timeout elapses we fall
 * back to a single direct read so a *genuinely* empty suite still resolves to
 * `[]` instead of surfacing the timeout.
 */
async function discoverTestTree(page: Page, setupPageErrorPromise: Promise<never>): Promise<{ group: DartTestEntry }> {
  try {
    return (await Promise.race([
      page
        .waitForFunction(
          () => {
            const response = window.__patrol__getTests?.()
            if (!response) return false

            // Count registered test leaves; only resolve once at least one exists.
            const countTests = (entry: DartTestEntry): number =>
              (entry.type === "test" ? 1 : 0) + entry.entries.reduce((sum, child) => sum + countTests(child), 0)

            return countTests(response.group) > 0 ? response : false
          },
          { timeout: 120000 },
        )
        .then(v => v.jsonValue()),
      setupPageErrorPromise,
    ])) as { group: DartTestEntry }
  } catch (error) {
    if (error instanceof Error && /Timeout.*exceeded/i.test(error.message)) {
      const fallback = (await page.evaluate(() => window.__patrol__getTests?.() ?? null)) as {
        group: DartTestEntry
      } | null
      if (fallback) {
        return fallback
      }
    }
    throw error
  }
}

function mapEntry(entry: DartTestEntry, parentName?: string, skip = false, tags = new Set<string>()) {
  const fullEntryName = parentName ? `${parentName} ${entry.name}` : entry.name
  const fullEntrySkip = skip || entry.skip
  const fullEntryTags = new Set([...tags, ...entry.tags.map(tag => `@${tag}`)])

  const tests: PatrolTestEntry[] = []

  if (entry.type === "test") {
    tests.push({
      name: fullEntryName,
      skip: fullEntrySkip,
      tags: [...fullEntryTags],
    })
  }

  tests.push(...entry.entries.flatMap(e => mapEntry(e, fullEntryName, fullEntrySkip, fullEntryTags)))

  return tests
}

export default setup
