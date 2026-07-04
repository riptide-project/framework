---
title: Module System
description: How Riptide registers, resolves, and provides access to modules.
---


The Module System is the core of Riptide's dependency injection. It automatically `require()`s all `ModuleScript` descendants in your configured folders, registers them under canonical IDs, and provides type-safe lookup methods.

## Types

```lua
type Config = {
    ModulesFolder: Folder | { Folder },
    SharedModulesFolder: (Folder | { Folder })?,
    ComponentsFolder: Folder?,
}
```

The internal registry types:

```lua
-- Internal module entry
{ name: string, module: any }

-- Registry (not directly accessible)
_modules: { [string]: any }        -- canonicalId → module table
_moduleAliases: { [string]: string | false }  -- shortName → canonicalId | false
```

---

## Module Lookup Methods

:::caution
All module getters use **dot `.` syntax** — they are standalone functions, not methods. Using colon `:` syntax will produce unexpected results:
```lua
-- ✅ Correct
local svc = Riptide.GetService("DataService")

-- ❌ Wrong — passes Riptide table as the `name` argument
local svc = Riptide:GetService("DataService")
```
:::

Lifecycle hooks receive the side-specific API directly. Server services get `Riptide.Server`; client controllers get `Riptide.Client`. Entry scripts can still import the side explicitly with `require(...).Server` or `require(...).Client`.

### `GetModule`

```lua
Riptide.GetModule(name: string) -> any
```

Universal module lookup. Works on both server and client. Resolves in this order:

1. Exact match against canonical ID (e.g., `"Economy/PlayerData"`)
2. Alias match against short name (e.g., `"PlayerData"`)
3. Returns `nil` + warning if not found or ambiguous

```lua
local data = Riptide.GetModule("Economy/PlayerData")
```

---

### `GetService`

```lua
Riptide.GetService(name: string) -> any
```

Server-side alias for `GetModule`. **Throws an error** if called on the client.

```lua
-- In a server service Init:
function MyService:Init(Riptide)
    self.DataService = Riptide.GetService("DataService")
end
```

---

### `GetController`

```lua
Riptide.GetController(name: string) -> any
```

Client-side alias for `GetModule`. **Throws an error** if called on the server.

```lua
-- In a client controller Init:
function UIController:Init(Riptide)
    self.InputController = Riptide.GetController("InputController")
end
```

---

## Canonical Module IDs

Modules are identified by their **relative path** from the modules folder, using `/` as separator:

```
ModulesFolder/
├── Economy/
│   └── PlayerData.lua    → "Economy/PlayerData"
├── Combat/
│   └── DamageService.lua → "Combat/DamageService"
└── MatchService.lua      → "MatchService"
```

### Alias Resolution

Short names (the `ModuleScript.Name`) are automatically created as aliases:

| Scenario | Result |
|----------|--------|
| Name is unique across all folders | Alias works. `GetModule("PlayerData")` → ✅ |
| Name collides with another module | Alias is **disabled** (marked `false`). A warning is emitted. Use canonical ID. |
| Canonical ID is the same as name  | No alias needed. Direct match. |

:::caution
When two modules share the same short name (e.g., `Economy/Utils` and `Combat/Utils`), the alias `"Utils"` is disabled. You must use canonical IDs like `"Economy/Utils"`.
:::

---

## Loading Order

When `Launch` is called:

1. **Plugins** (`PluginsFolder` / `ExternalPlugins`) are loaded and initialized first. Plugins are framework extensions, so their `PublicAPI` and sandbox registrations are available before game modules load.
2. **Shared modules** (`SharedModulesFolder`) are loaded.
3. **Side-specific modules** (`ModulesFolder`) are loaded.
4. **ComponentService** starts if `ComponentsFolder` is configured.
5. **Module Init** runs synchronously.
6. **Plugin Start readiness** completes before player lifecycle replay and game module `Start`.
7. **PlayerLifecycle** starts on the server and replays existing players.
8. **Module Start** is dispatched asynchronously.

If a `ModuleScript` appears in multiple module folders (for example through linked instances), it is only loaded once.

---

## Entry Point Types

The framework exports clean types for use in your modules:

```lua
export type RiptideServer = {
    Network: NetworkServerAPI,
    Signal: typeof(Signal),
    Async: typeof(Async),
    ComponentService: ComponentServiceAPI,
    State: StateReplicationServerAPI,
    PlayerLifecycle: any,
    GetModule: (name: string) -> any,
    GetService: (name: string) -> any,
    Launch: (config: Config) -> (),
}

export type RiptideClient = {
    Network: NetworkClientAPI,
    Signal: typeof(Signal),
    Async: typeof(Async),
    ComponentService: ComponentServiceAPI,
    State: StateReplicationClientAPI,
    GetModule: (name: string) -> any,
    GetController: (name: string) -> any,
    Launch: (config: Config) -> (),
}

export type Riptide = {
    Server: RiptideServer?,
    Client: RiptideClient?,
}
```

Use in your modules for full autocomplete:

```lua
local RiptidePkg = require(ReplicatedStorage.Packages.Riptide)
type RiptideServer = RiptidePkg.RiptideServer
type RiptideClient = RiptidePkg.RiptideClient
```

The root package still exposes compatibility aliases, but new entry scripts should prefer `require(...).Server` or `require(...).Client`. Lifecycle hooks receive that same side-specific API directly, so module code can use `Riptide.Network`, `Riptide.State`, and `Riptide.GetService` / `Riptide.GetController` without repeating `.Server` or `.Client`.
