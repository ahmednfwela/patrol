import * as fs from "fs"
import * as path from "path"
import v8toIstanbul from "v8-to-istanbul"
import libCoverage from "istanbul-lib-coverage"
import reports from "istanbul-reports"
import { logger } from "./logger"

interface V8CoverageEntry {
  url: string
  source?: string
  functions: Array<{
    functionName: string
    ranges: Array<{
      startOffset: number
      endOffset: number
      count: number
    }>
    isBlockCoverage: boolean
  }>
}

const coverageDir = process.env.PATROL_WEB_COVERAGE_DIR || "coverage"

export async function processV8Coverage(
  entries: V8CoverageEntry[],
  outputDir?: string,
): Promise<void> {
  const dir = outputDir || coverageDir
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true })
  }

  const coverageMap = libCoverage.createCoverageMap({})

  // Filter to only DDC-generated Dart files (skip dart_sdk, framework code)
  const dartEntries = entries.filter(entry => {
    const url = entry.url
    if (!url || url === "") return false
    // Include DDC-generated Dart library JS files
    if (url.includes(".dart.lib.js")) return true
    if (url.includes(".dart.js") && !url.includes("dart_sdk")) return true
    return false
  })

  logger.info("Processing %d Dart coverage entries (of %d total)", dartEntries.length, entries.length)

  for (const entry of dartEntries) {
    try {
      // v8-to-istanbul needs a file path; for URLs, create a temp mapping
      const converter = v8toIstanbul(entry.url, 0, {
        source: entry.source || "",
        sourceMap: undefined, // v8-to-istanbul will try to find source maps via sourceMappingURL
      })

      await converter.load()
      converter.applyCoverage(entry.functions)
      const data = converter.toIstanbul()

      // Merge into the coverage map
      for (const [filePath, fileCoverage] of Object.entries(data)) {
        coverageMap.addFileCoverage(fileCoverage as libCoverage.FileCoverageData)
      }

      converter.destroy()
    } catch (err) {
      logger.warn("Failed to process coverage for %s: %s", entry.url, err)
    }
  }

  // Generate LCOV report
  const context = reports.create("lcovonly", {
    dir,
    file: "patrol_web_lcov.info",
  })

  const reportContext = {
    dir,
    coverageMap,
    defaultSummarizer: "nested" as const,
    watermarks: {} as Record<string, [number, number]>,
    sourceFinder: (filePath: string) => {
      try {
        return fs.readFileSync(filePath, "utf8")
      } catch {
        return ""
      }
    },
    getTree: (name: string) => coverageMap,
  }

  try {
    // @ts-expect-error - istanbul-reports types are complex
    context.execute(reportContext)
    logger.info("Web coverage report written to %s/patrol_web_lcov.info", dir)
  } catch (err) {
    logger.warn("Failed to generate LCOV report: %s", err)
    // Fallback: dump raw coverage map as JSON
    const jsonPath = path.join(dir, "patrol_web_coverage.json")
    fs.writeFileSync(jsonPath, JSON.stringify(coverageMap.toJSON(), null, 2))
    logger.info("Raw coverage data saved to %s", jsonPath)
  }
}
