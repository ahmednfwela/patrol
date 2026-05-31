# Bdaya-Dev/patrol fork changes vs upstream (leancodepl/patrol)

**Branch:** fixed
**Upstream ref:** 41fe088e6
**Generated:** 2026-05-31
**Total commits ahead:** 39 (excluding merges: ~30 unique changes)

## This Session (Desktop Support - 7 commits)

| Hash | Description |
|------|-------------|
| dca7685d3 | fix: add linux/windows cases to DevelopService switch statements |
| 9485f09f0 | feat: add reusable patrol-test workflow for 6-platform CI matrix |
| fb65967b7 | fix: harden CI workflow to catch native code issues |
| 2a1f9563f | fix: address code review findings across desktop backend |
| db691aedc | fix: ensure desktop app window closes after test completes |
| b26f2a44e | feat: add Linux and Windows desktop backend support |
| b8164574e | fix(patrol/web): wait for non-empty test tree in web globalSetup |

## Prior Fork Changes (pre-existing)

### patrol_mcp enhancements
| Hash | Description |
|------|-------------|
| 87ca0ed92 | fix(patrol_mcp): connect CDP earlier to capture browser startup errors |
| 959ac86d4 | fix(patrol_mcp): use Platform.isWindows instead of try-catch for SIGTERM |
| f7366e1b6 | fix(patrol_mcp): handle SIGTERM not supported on Windows |
| 5bc0e8a3b | fix(patrol_mcp): capture test failure messages from console.log |
| b591a3906 | feat(patrol_mcp): capture browser console errors via CDP |
| f5bccbe70 | feat(patrol_mcp): add savePath parameter to stop-recording |
| ed28b5463 | fix(patrol_mcp): remove recording time/frame limits, fix web develop filesystem root |
| f26306f60 | feat(patrol_mcp): web screenshot + video recording via CDP |

### Web testing fixes
| Hash | Description |
|------|-------------|
| 50b8ab3db | fix(web): remove duplicate Platform.environment spread that clobbers env vars |
| 1dcebfb26 | fix(web): handle StdinException in non-terminal MCP environments |
| 47cd1f529 | fix: filter cosmetic Flutter engine re-init errors in setup.ts |
| ca200b8e9 | fix: enhance DDC debug mode handling |
| 46a9fc222 | fix: add initTimeout option for web tests |
| 8c1f63280 | fix: handle test failures and ensure proper page teardown |
| 9b17b237b | feat: ensure __patrol__isInitialised set immediately during page load |
| 48728f1a6 | feat: add configurable initialization timeout for Playwright tests |
| 1e8fc3a02 | feat: add support for Playwright trace recording options |
| 4d9094a35 | fix: disable Chrome throttling options in Playwright configuration |
| 13d44cdcd | feat: introduce --web-server-timeout for Flutter web server start |

### CLI fixes
| Hash | Description |
|------|-------------|
| f9f76c9f7 | fix(patrol_cli): use Platform.isWindows for SIGTERM in develop_service |
| df4d44852 | Update import for current_platform in binding.dart |
