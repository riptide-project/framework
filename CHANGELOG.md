# Changelog

All notable changes to this project will be documented in this file.

The format is based on Keep a Changelog, and this project adheres to Semantic Versioning.

## [Planned]

### Added
- (New features arriving soon...)

## [0.9.0-maelstrom.1] - 2026-06-12

### Added
- **Plugin System** — complete `PluginManager` + `PluginSandbox` architecture for extending Riptide with isolated, lifecycle-aware plugins.
  - `PluginManager` (`src/shared/PluginManager.lua`): orchestration engine with hybrid loading (local folder scanning + `ExternalPlugins` array), topological dependency resolution via Kahn's algorithm, and full lifecycle dispatch (`OnRegister` → `Init` → `Start` → `Stop` → `Destroy`).
  - `PluginSandbox` (`src/shared/PluginSandbox.lua`): mediator facade injected into each plugin, exposing scoped `Network`, `State`, `Signal`, and `ComponentService` APIs. All resources (connections, handlers, signals) are tracked via a built-in Trove pattern and auto-cleaned on crash or destroy.
  - **Event Bus**: internal pub/sub system (`sandbox:Emit` / `sandbox:On`) with `xpcall`-protected dispatch — a failing listener never breaks the rest of the bus.
  - **Crash isolation**: if a plugin fails during `Init` or `Start`, it is flagged `Errored` and its Trove is cleaned without cascading failures to other plugins or the host framework.
  - **Cycle detection**: circular dependencies between plugins are detected during topological sort; all participants are flagged `Errored` with a descriptive warning.
  - **`PublicAPI` / `GetPluginAPI`**: plugins can expose an API table that other plugins consume by name, enabling safe inter-plugin communication.
  - **Network namespacing**: all plugin network events are automatically prefixed `__plugin:<PluginName>:<event>` to avoid collisions with game remotes.
  - **Duck typing loader**: folder-scanned modules are validated via `pcall(require)` + structural check for `Descriptor` and `Hooks` — invalid modules are skipped with a warning.
  - **`Side` filtering**: plugins declare `"Server"`, `"Client"`, or `"Shared"`; the manager silently skips plugins that don't match the current runtime.
- **Plugin Phase in `ModuleLoader`**: `Launch()` now executes a dedicated plugin phase with **clean separation** — plugins `Load+Init` run **before** module `Init` (so game modules can call `GetPluginAPI()` safely), and plugin `Start` runs asynchronously after module `Start`. Config accepts `PluginsFolder: (Folder | {Folder})?` and `ExternalPlugins: {table}?`.
- **`Riptide.Plugins`**: `PluginManager` instance is now exposed on the top-level Riptide table in `init.lua`, injectable with `Network`, `State`, `Signal`, and `ComponentService` deps.
- **`dev.project.json`**: added `test/plugins` → `ServerScriptService.TestPlugins` mapping for integration test plugin discovery.
- **Trove Utility** (`src/shared/Utilities/Trove.lua`): resource tracking utility based on Sleitnick's Trove, adapted to run safely in Lune headless test environments.
- **EventBus Utility** (`src/shared/Utilities/EventBus.lua`): internal pub/sub event bus with listener isolation using `xpcall`.
- **Guard Utility** (`src/shared/Utilities/Guard.lua`): lightweight, zero-dependency type validation library mirroring `t` API for typesafe network boundary checks.
- **StateMachine Guards**: added support for `CanTransitionTo` whitelist tables and validation callback functions in the `StateDefinition`.
- **Typed Network Events**: implemented `Network.RegisterTyped` and `Network.RegisterTypedUnreliable` in `Network.lua` to validate remote event parameters against `Guard` schema tables.

### Fixed
- **`PlayerLifecycle` — PluginManager not notified on player events (critical bug)**: `PlayerLifecycle:Start()` was dispatching `OnPlayerAdded` / `OnPlayerRemoving` hooks to user modules but never calling `PluginManager:NotifyPlayerAdded` / `NotifyPlayerRemoving`. Plugins depending on player join/leave events were silently never triggered. Fixed by adding nil-safe PluginManager notification calls in all three dispatch sites (retroactive existing players + `PlayerAdded` connection + `PlayerRemoving` connection).
- **`PlayerLifecycle` — Decoupled dependencies**: refactored `PlayerLifecycle` to receive its dependencies (such as player addition/removal handlers) via Dependency Injection, removing tight coupling with the global framework state.
- **`ModuleLoader` — Plugin lifecycle ordering (critical)**: Plugin `Load+Init` now runs **before** module `Init`. Game modules can safely call `Riptide.Plugins:GetPlugin()` / `GetPluginAPI()` inside their own `Init()` hooks. Previously plugins were loaded only after module `Start`, making this impossible.
- **`ModuleLoader` — `PlayerLifecycle:Start()` moved after Module/Plugin Init**: Retroactive `OnPlayerAdded` now fires when both modules and plugins are already initialized. Previously the hook fired before the Init phase, so modules' `self.*` fields were not yet populated.
- **`ComponentService` — Removed `__mode = "k"` weak tables**: `_registry` and `_destroyingConns` are now strong tables. Same class of GC bug as `StateReplication` v0.8.2. Explicit cleanup via `Destroying` connections + `CleanupComponent` / `UnregisterTag` is sufficient.
- **`ComponentService` — Added `_registerTagManually()`**: Plugins can now register components via `sandbox:RegisterComponent(tag, ComponentClass)` without a `ComponentsFolder`. Previously `PluginSandbox:RegisterComponent()` silently warned and did nothing because the backing method didn't exist.
- **`StateMachine` — Added `xpcall` error boundaries**: All lifecycle hooks (`OnEnter`, `OnExit`, `OnUpdate`) are now wrapped in `xpcall`. A throwing hook warns instead of corrupting the machine's internal state.
- **`ComponentService` — Registry reference leaks**: empty tables inside `_registry` and `_destroyingConns` are pruned from memory in `CleanupComponent` when all tags are removed from an instance.
- **`PluginSandbox` — RunAsync code duplication**: delegated `RunAsync` directly to the core `Async.Run` utility, removing 56 lines of duplicate async invocation code.
- **`Network` — Handler clear on re-init**: handlers are cleared in `Network._init` to ensure clean hot-reload and test execution.

### Performance

- **`Signal` — Synchronous `Fire()` (zero-allocation hot path)**: `task.spawn` per connected callback has been removed. `:Fire()` now executes all listeners directly in the calling thread via a plain linked-list walk — no coroutine allocation, no scheduler pressure. At 60 Hz with multiple connections this eliminates hundreds of thread spawns per second. `:Wait()` is unaffected and continues to resume the suspended caller via a single `task.spawn`.
- **`Network` — Flat middleware chains**: `runServerMiddlewareChain` and `runClientMiddlewareChain` rewritten from a recursive closure-per-packet pattern into a flat `for`-loop. The previous design allocated N closures + N xpcall frames per incoming packet; the new design creates zero closures and iterates the middleware array in-place. Middleware receives an `args: {any}` table by reference and returns `false` to abort.
- **`Network` — Synchronous handler dispatch**: `DispatchHandlers` and its per-handler `task.spawn` removed. Handlers are now called directly inside the event callback thread via `xpcall`, eliminating a thread allocation on every received packet.
- **`StateReplication` — Async snapshot handshake (critical bugfix + perf)**: `RequestSync()` previously called `InvokeServer` which was removed in 0.9.0, silently breaking initial state sync on every client. Replaced with a fire-and-respond protocol over `RemoteEvent`: client fires `EVENT_SNAPSHOT` (request) → server fires back a structured snapshot table to that specific client. Deltas arriving during the round-trip are buffered and replayed after the snapshot is applied. No `RemoteFunction` or blocking yield required.
- **`StateReplication:notify()` — Synchronous subscriber dispatch**: `task.spawn` per subscriber removed. Subscriber callbacks now execute directly in the calling thread, consistent with `Signal:Fire()`. Callbacks must not yield.
- **`StateReplication:Set()` / `SetForPlayer()` — Flat RemoteEvent args**: Delta packets now pass `(scope, key, value, version)` as flat args instead of allocating a payload table per call. At 60 Hz this eliminates one GC-tracked table allocation and one serialization indirection per state update.
- **`ComponentService:SetupComponent()` — Eliminated closure in `pcall`**: `pcall(function() return ComponentClass.new(instance) end)` replaced with `pcall(ComponentClass.new, instance)`. Removes an anonymous closure allocation on every tagged instance creation.
- **`Network` — Vararg boxing bypass**: client/server event handlers bypass `{ ... }` packing when no middleware is active.
- **`PluginManager` — Kahn's cycle check optimization**: Kahn cycle verification optimized to $O(N)$ by checking remaining non-zero in-degrees and removing the counting IIFE closure.

### Breaking Changes

- **`Signal:Fire()` is now synchronous** — callbacks connected via `:Connect()` must not yield (`task.wait`, `coroutine.yield`). If a callback needs deferred execution, wrap its body in `task.defer` or `task.spawn` internally.
- **`Network` — `RemoteFunction` removed** — `FunctionDispatcher`, `InvokeClient`, and `InvokeServer` have been completely removed. `RemoteFunction:InvokeClient` can block the server thread indefinitely if a client crashes; use `Async.lua` over `RemoteEvent` pairs for request/response patterns instead. `NetworkDeps` no longer requires `FunctionDispatcher`.
- **`Network` — Middleware signature changed** — Old: `(player, funcName, next, ...)`. New server: `(player, funcName, args: {any}) -> boolean?`. New client: `(funcName, args: {any}) -> boolean?`. Return `false` to abort the chain; mutate `args` in-place to transform the payload.

### Tests
- Added `PluginIntegration.test.luau` integration suite (7 suites, 14 test cases) covering:
  - Healthy plugin lifecycle (`OnRegister` → `Init` → `Start` ordering, sandbox `PluginName`, status flags).
  - Crash isolation: `Start` crash → `Errored` status, sibling plugins unaffected; `Init` crash → `Start` never called; Trove cleans up Network handlers on crash.
  - `ExternalPlugins` ingestion: valid external loaded; malformed external rejected; `Client`-side plugin silently skipped on server; `Shared` plugin accepted.
  - Dependency ordering: plugin B depending on A gets A's `Init` called first; `GetPluginAPI` returns data at `Init` time.
  - Cycle detection: mutual A↔B dependency flags both `Errored`; independent plugin alongside a cycle loads normally.
  - Event Bus resilience: `Emit` → `On` delivers payload; crashing listener does not block subsequent listeners.
  - `Stop`/`Destroy` sequencing: `Stop` dispatched in reverse dependency order; `DestroyPlugins` clears the registry.
- Registered `PluginIntegration.test` in `RunLuneTests.luau`.
- Extended `TestEnv.luau` to expose `PluginManager` and `PluginSandbox` in both Roblox and Lune test paths.
- `Network.test.luau` — updated all `_init` calls (removed `FunctionDispatcher`), removed `InvokeClient`/`InvokeServer` test cases, rewrote middleware tests for the new `args`-table signature.
- `Chaos.test.luau` — removed `FunctionDispatcher` injection from the Network flood test.
- Added new temporary `test/dev_suites/` containing 7 test files (29 tests) verifying `Trove`, `EventBus`, `Guard`, `Network` fast-path, `ComponentService` cleanup, `StateMachine` guards, and `PlayerLifecycle` ordering, along with the `test/lune/RunDevTests.luau` runner.
- Configured `DevSuites` sync in `dev.project.json` to sync dev suites to Roblox Studio.

### Docs

- `docs/api/network.md` — full rewrite: removed `InvokeClient`/`InvokeServer`/`FunctionDispatcher` references, documented new flat middleware API, updated architecture diagram to two remotes.
- `docs/api/utilities.md` — `Signal:Connect` and `Signal:Fire` updated to reflect synchronous dispatch contract.



## [0.8.2] - 2026-04-22

### Fixed
- **Critical**: `StateReplication` per-player state data loss caused by Luau garbage-collecting weak-key table (`__mode = "k"`) entries for Player userdata. Replaced `_playerState` and `_playerVersions` with strong tables; explicit cleanup in `_onPlayerRemoving` already handles memory management. This bug caused `State:Get(key, player)` to intermittently return `nil` for previously set per-player values.

### Documentation
- **Getting Started**: Fixed Rojo project config — removed intermediate `Server`/`Client` container folders that caused path mismatches with code examples. Renamed `Shared` to `SharedModules` for consistency. Added `SharedModulesFolder` to both server and client launch examples.
- **Getting Started**: Fixed client entry point path from `Players.LocalPlayer.PlayerScripts` to `Players.LocalPlayer.PlayerScripts.Controllers`. Fixed duplicate section numbering. Updated expected output to match real framework logs.
- **Module Lifecycle**: Added explicit documentation for `self` vs `Riptide` arguments in lifecycle methods. Added callout clarifying that `GetService`/`GetController`/`GetModule` use **dot** `.` syntax (functions, not methods). Added `Syntax` column to Module Getters table.
- **Player Lifecycle**: Documented that retroactive `OnPlayerAdded` hooks fire **before** the Init phase. Added full execution order diagram. Added safety guidance to use the `Riptide` argument directly (not `self.*` fields) inside lifecycle hooks.
- **State Replication**: Added note that `Subscribe` immediate callback may receive `nil` if state hasn't been replicated yet, with defensive coding pattern.
- **Module Loader**: Added caution callout about dot `.` vs colon `:` syntax for module getter functions.
- **Project Structure**: Added tip noting that `SharedModulesFolder` and `ComponentsFolder` are optional config fields.

## [0.8.1] - 2026-04-18

### Changed
- QA Testing Framework upgraded to a **Hybrid Testing Architecture**: maintaining `Lune` CLI compatability for instant CI unit testing, while now seamlessly integrating into the `Roblox DataModel` for live client/server testing.
- Segmented test environments: created independent test runners for Server (`RunServerTests.server.luau`) and Client (`RunClientTests.client.luau`), alongside the Lune runner.
- `dev.project.json` reinstated to support distinct `ClientTests`, `ServerTests`, and `SharedTests` workspace hierarchies for Pesde dependencies.

### Fixed
- Fixed a core architecture bug in `Network._init` where re-initializing the Network module on the Server would trigger restricted environment errors while referencing `OnClientInvoke`.
- Eliminated a native Engine *Replication Thread Starvation* issue during automated test runs: the server runner now actively yields before heavy test execution, guaranteeing that `Remotes` properly replicate to the client context.
- Fixed an obsolete API assertion inside the System Integration client test targeting `ComponentService.Register`.

### Tests
- Expanded integration coverage directly inside the Roblox DataModel.
- Added comprehensive Client and Server System Integration suites covering cross-boundary modules: `Signal`, `Async`, `StateMachine`, `ComponentService`, and `StateReplication`.

## [0.8.0] - 2026-04-05

### Added
- StateMachine module (`Riptide.StateMachine`) for robust state orchestration and lifecycle transitions.
- Unreliable networking support via `UnreliableRemoteEvent` (`UnreliableFireClient`, `UnreliableFireAllClients`, `UnreliableFireServer`).
- Network middleware pipeline (`Network.UseMiddleware`) for centralized validation/logging/rate-limit flows.
- Player Lifecycle Manager with module hooks (`OnPlayerAdded`, `OnPlayerRemoving`) and server-side lifecycle orchestration.

### Documentation
- Introduced a professional Astro Starlight-based documentation site inside the `docs/` workspace.
- Deployed a highly polished deep-black theme (`custom.css`) with specific typographic improvements for API syntax highlighting.
- Added comprehensive Markdown API references for `Network`, `ComponentService`, `ModuleLoader`, `StateReplication`, `PlayerLifecycle`, and `Utilities`.
- Published extensive user guides including `Getting Started`, `Project Structure`, and `Module Lifecycle` with proper Rojo (`default.project.json`) setups.

### Changed
- Server launch flow now initializes and starts `Riptide.PlayerLifecycle` automatically.
- Module loading on server now triggers lifecycle hooks for already loaded modules (`OnPlayerAdded` / `OnPlayerRemoving`).
- Toolchain migrated from `aftman` to `mise`.
- **Type Safety**: Properly isolated `RiptideServer` and `RiptideClient` typing in `init.lua` to fix autocompletion conflicts.
- Framework testing functions (`_resetForTests`, `_suppressWarnings`) removed from production API for improved security and code cleanliness.
- `ComponentService` now supports connection cleanup via `_stop()` and `UnregisterTag()` to resolve memory leaks during testing/hot-reload.
- Ensured tests and test utilities are fully excluded from `pesde` and generic Roblox production targets.

### Fixed
- Server-side `StateReplication` now performs automatic per-player state cleanup on player removal.

### Tests
- Added `StateMachine` test suite covering state transitions, lifecycle hooks, and signal integration.
- Added lifecycle coverage with a dedicated `MockPlayers` service and `PlayerLifecycle` test suite.
- Added `Network` middleware coverage for server/client event and invoke flows.
- Verified all unit tests pass in Lune environment with zero memory side effects.

## [0.7.1] - 2026-04-03

### Fixed
- `StateReplication` now tracks client versions per scope (`global` and `player`) to prevent dropped per-player deltas when keys overlap.
- `StateReplication` snapshot sync now keeps player override + proper fallback to global value when player override is removed.
- `State:Subscribe` now invokes initial callback synchronously to avoid race conditions immediately after subscription.
- `Async.Parallel` now has a default timeout safety when timeout is omitted, preventing indefinite hangs by default.
- `Network._init` now warns before clearing active handlers on re-init.

### Tests
- Added regression coverage for scope-aware state deltas and player->global fallback behavior.
- Added explicit scoped delta test (`scope = "global"`) and a dedicated legacy no-scope compatibility test.
- Added Async.Parallel negative-timeout validation test.

## [0.7.0] - 2026-04-03

### Added
- `StateReplication` module (`Riptide.State`) with server-authoritative global and per-player state sync.
- `State:UpdateForPlayer(player, key, updater)` for atomic callback-based per-player state updates.
- Client subscriptions for state keys via `State:Subscribe(key, callback)` with immediate callback and unsubscribe handle.
- Automatic client snapshot sync (`State:RequestSync()`) plus delta updates over the unified network layer.
- Public `Riptide.State` API exposed from framework entrypoint.
- New test suite for StateReplication (`test/lune/StateReplication.test.luau`).

### Changed
- Launch wiring is centralized in `src/init.lua` via a unified side-aware launcher.
- `ClientInitializer`/`ServerInitializer` wrapper behavior is now handled directly by `Riptide.Server.Launch` and `Riptide.Client.Launch` in `init.lua`.
- CI and Release lint/format checks now include `src/`, `test/`, and `.lune/`.
- Bootstrap remote lookup in `src/init.lua` now fails fast with timeout diagnostics instead of waiting indefinitely.
- `ComponentService:Get(instance)` is deterministic: when multiple components are attached and no `tagName` is provided, it returns `nil` and warns.
- `ModuleLoader` now includes Lune task fallback for cross-runtime test stability.
- Test coverage expanded from 44 to 54 tests (including integration coverage for `ModuleLoader.Launch`, Network re-init behavior, Async input guards, and StateReplication).

### Fixed
- `Network._init` is now idempotent for re-initialization scenarios: previous event connections are disconnected before rebind.
- `Network._init` now clears stale invoke handlers during re-init and validates required deps inputs.
- `StateReplication` no longer mixes global/player version namespaces on client; version tracking is now scope-aware to prevent dropped per-player updates.
- `StateReplication` client snapshot now preserves proper player-over-global precedence with correct fallback semantics.
- `State:Subscribe` now invokes the initial callback synchronously to avoid race conditions right after subscription.
- `Async.Parallel` now applies a default timeout safety when timeout is omitted, preventing indefinite hangs by default.
- `Network._init` now warns when re-init clears active handlers.
- Release workflow no longer runs stale cleanup step for `*.spec.lua` files.
- Test output warning noise is reduced for expected warning scenarios while preserving runtime warnings in production code paths.

### Removed
- Legacy wrapper modules `src/client/Core/ClientInitializer.lua` and `src/server/Core/ServerInitializer.lua`.

### Breaking
- Internal initializer module files were removed; any direct requires of `ClientInitializer`/`ServerInitializer` must migrate to `Riptide.Server.Launch` / `Riptide.Client.Launch` from `init.lua`.
- `ComponentService:Get(instance)` no longer returns an arbitrary component when multiple tags are attached; callers must pass explicit `tagName` in ambiguous cases.

### Internal
- Release workflow includes warning-only version preflight for tag, `pesde.toml`, and `CHANGELOG.md` consistency.
- `Async.Retry` now validates input arguments (`maxAttempts >= 1`, integer attempts, non-negative `delay`).

## [0.6.0] - 2026-03-28

### Added
- Dependency Injection for `Network` (`_init(deps)`) and `ComponentService` (`_init(deps)`), enabling mock-based testing outside Roblox.
- `ModuleLoader` module (`src/shared/ModuleLoader.lua`) — unified loading logic extracted from `ClientInitializer` and `ServerInitializer`.
- Full test suite using Lune + frktest (`test/lune/`), with mocks for `RemoteEvent`, `RemoteFunction`, and `CollectionService`.
- Lune added to the project toolchain.
- `.luaurc` with alias for `@src`.
- CI now runs automated tests via `lune run` on every push/PR.
- Guard stubs: `GetController` on server and `GetService` on client now throw clear errors instead of returning `nil`.

### Changed
- `ClientInitializer` and `ServerInitializer` refactored to thin wrappers (~20 lines each) over `ModuleLoader`.
- Package management fully migrated to Pesde. Wally is no longer supported.
- Tests migrated from TestEZ (Roblox-only) to frktest (Lune-native).

### Removed
- `wally.toml`, `wally.lock`, `.wallyignore` — Wally support is fully dropped.
- `DevPackages/` (TestEZ dependency).
- `dev.project.json` (was used for TestEZ in Roblox Studio).
- All `.spec.lua` files replaced by `test/lune/*.test.luau`.

### Breaking
- **Wally users must migrate to Pesde or manual `.rbxm` installation.**
- Internal `Network` module no longer self-initializes at require-time. This is transparent to end users (handled by `init.lua`), but affects anyone directly requiring `Network.lua` outside of Riptide.

## [0.5.0] - 2026-03-26

### Added
- `SharedModulesFolder` support for both `Server.Launch` and `Client.Launch`.
- `ModulesFolder` now accepts either a single `Folder` or an array of `Folder` values.
- Initializer test coverage for both client and server multi-folder/shared-folder loading paths.

### Changed
- Module loading phase now normalizes folder inputs and processes shared folders before side-specific folders.
- README launch examples updated to document `SharedModulesFolder` and multi-folder module config.
- Package manager guidance now documents dual usage (`Pesde` + `Wally`) with Pesde as the recommended path.

### Fixed
- Duplicate `ModuleScript` loads across configured folders are prevented.
- Duplicate canonical module IDs are now skipped deterministically with warning output.

### Notes
- Release target: dual publish for Wally and Pesde.
- `v0.5.0` is the last release with first-class Wally support; migration target is Pesde-first.

## [0.4.0] - 2026-03-26

### Changed
- Module registry now stores canonical module IDs based on relative path (example: `Economy/PlayerData`) instead of short name only.
- `GetModule` now resolves both canonical IDs and short aliases; ambiguous aliases require canonical path usage.
- Client and Server initializers now detect alias collisions and emit deterministic warnings.

### Fixed
- `ComponentService` startup is now idempotent: duplicate `_start` calls are ignored.
- Duplicate component construction for same `(instance, tag)` is prevented.

### Performance
- Network dispatch hot-path no longer allocates per-handler closures in `DispatchHandlers`; uses a reusable trampoline function.

### Notes
- Short-name module access remains supported as alias behavior.
- For duplicate module names in different folders, use canonical path IDs.
