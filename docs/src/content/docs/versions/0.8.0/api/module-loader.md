---
slug: versions/0.8.0/api/module-loader
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
Riptide.GetService(name: string) -> any        -- server only
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
Riptide.GetController(name: string) -> any      -- client only
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

1. **Shared modules** (`SharedModulesFolder`) are loaded first.
2. **Side-specific modules** (`ModulesFolder`) are loaded second.
3. **Deduplication** — if a `ModuleScript` appears in multiple folders (e.g., via linked instances), it is only loaded once.

This guarantees shared utilities are available before services or controllers that depend on them.

---

## Entry Point Types

The framework exports clean types for use in your modules:

```lua
export type RiptideServer = {
    Network: NetworkAPI,
    Signal: typeof(Signal),
    Async: typeof(Async),
    ComponentService: ComponentServiceAPI,
    State: StateReplicationAPI,
    PlayerLifecycle: any,
    GetModule: (name: string) -> any,
    GetService: (name: string) -> any,
    Server: { Launch: (config: Config) -> () },
}

export type RiptideClient = {
    Network: NetworkAPI,
    Signal: typeof(Signal),
    Async: typeof(Async),
    ComponentService: ComponentServiceAPI,
    State: StateReplicationAPI,
    GetModule: (name: string) -> any,
    GetController: (name: string) -> any,
    Client: { Launch: (config: Config) -> () },
}

export type Riptide = RiptideServer & RiptideClient
```

Use in your modules for full autocomplete:

```lua
local RiptidePkg = require(ReplicatedStorage.Packages.Riptide)
type Riptide = RiptidePkg.Riptide
```
