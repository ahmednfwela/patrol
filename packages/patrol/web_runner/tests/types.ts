declare global {
  interface Window {
    __patrol__getTests?: () => { group: DartTestEntry }
    __patrol__runTest?: (name: string) => Promise<PatrolTestResult>
    __patrol__onInitialised?: () => void
    __patrol__isInitialised?: boolean

    // DWDS (Dart Web Debug Service) globals — set by DDC bootstrap in debug mode.
    // $dartRunMain starts the Dart entrypoint; DWDS normally calls it after
    // connecting, but it may not fire for subsequent browser sessions.
    $dartRunMain?: () => void
    $dartMainExecuted?: boolean
  }
}

export type PatrolTestEntry = {
  name: string
  skip: boolean
  tags: string[]
}

export type PatrolTestResult = {
  result: "failure" | "success"
  details: string | null
}

export type DartTestEntry = {
  type: "group" | "test"
  name: string
  entries: DartTestEntry[]
  skip: boolean
  tags: string[]
}
