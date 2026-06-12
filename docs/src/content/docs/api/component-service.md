---
title: Component Service
description: Manage instance lifecycle via CollectionService tags.
---


The `ComponentService` binds Roblox `CollectionService` tags to Luau component classes. When a tagged instance appears, a component object is created; when the tag is removed or the instance is destroyed, the component is cleaned up.

:::note[What is CollectionService?]
CollectionService is a Roblox engine service that lets you **tag** any `Instance` with an arbitrary string label. Riptide watches for those tags and automatically creates or destroys your component objects as tagged parts appear and disappear in the game world. This is great for hazards, interactive props, pickup items — anything that maps to a physical object.
:::

Access via `Riptide.ComponentService`.

## Types

```lua
type ComponentClass = {
    new: (instance: Instance) -> any,
    Destroy: ((self: any) -> ())?,
}

type ComponentServiceAPI = {
    Get: (self, instance: Instance, tagName: string?) -> any?,
    UnregisterTag: (self, tagName: string) -> (),
}
```

---

## Component Contract

A **component** is a `ModuleScript` placed inside the `ComponentsFolder`. Its filename must match the `CollectionService` tag name.

Every component **must** return a table with:

| Field      | Required | Signature                        | Description                          |
|-----------|----------|-----------------------------------|--------------------------------------|
| `new`     | ✅       | `(instance: Instance) -> self`   | Constructor. Called when a tagged instance is detected. |
| `Destroy` | ❌       | `(self) -> ()`                   | Cleanup. Called when tag is removed or instance is destroyed. |

### Example — `Lava.lua`

```lua
local Lava = {}
Lava.__index = Lava

function Lava.new(instance: BasePart)
    local self = setmetatable({
        _instance = instance,
        _connection = nil :: RBXScriptConnection?,
    }, Lava)

    self._connection = instance.Touched:Connect(function(hit)
        local humanoid = hit.Parent and hit.Parent:FindFirstChild("Humanoid")
        if humanoid then
            (humanoid :: Humanoid):TakeDamage(10)
        end
    end)

    return self
end

function Lava:Destroy()
    if self._connection then
        self._connection:Disconnect()
        self._connection = nil
    end
end

return Lava
```

Tag any `BasePart` with `"Lava"` in Studio or via `CollectionService:AddTag()` — the component will be instantiated automatically.

---

## Methods

### `Get`

```lua
ComponentService:Get(instance: Instance, tagName: string?) -> any?
```

Retrieves the component object attached to an instance.

**With tag name** — returns the specific component:

```lua
local lava = Riptide.ComponentService:Get(part, "Lava")
if lava then
    print("This part has a Lava component")
end
```

**Without tag name** — returns the component only when exactly **one** is attached:

```lua
local component = Riptide.ComponentService:Get(part)
```

:::caution
If multiple components are attached to the same instance and no `tagName` is provided, `Get` returns `nil` and emits a warning. Always pass `tagName` in ambiguous cases.
:::

---

### `UnregisterTag`

```lua
ComponentService:UnregisterTag(tagName: string) -> ()
```

Disconnects all `CollectionService` listeners for a specific tag and destroys all active component instances of that tag.

```lua
Riptide.ComponentService:UnregisterTag("Lava")
```

This is useful for hot-reload or test teardown scenarios.

---

## Setup

ComponentService is started automatically when you pass `ComponentsFolder` in your Launch config:

```lua
Riptide.Server.Launch({
    ModulesFolder = ServerScriptService.Services,
    ComponentsFolder = ReplicatedStorage.Components,  -- ← enables ComponentService
})
```

The service scans all `ModuleScript` descendants in the folder, requires each one, and:

1. Validates the component has a `new` constructor.
2. Connects to `CollectionService:GetInstanceAddedSignal(tagName)` and `GetInstanceRemovedSignal(tagName)`.
3. Processes all **already-tagged** instances immediately.

:::note
Startup is **idempotent** — calling `_start()` multiple times is safely ignored. This prevents duplicate listeners during hot-reload.
:::

---

## Memory Management

ComponentService uses **weak-key tables** (`__mode = "k"`) for its internal registry. This means:

- When an instance is garbage collected, its registry entry is automatically freed.
- On `Instance.Destroying`, the component's `Destroy()` method is called and all connections are cleaned up.
- On tag removal, `CleanupComponent` is triggered to tear down the component and disconnect the `Destroying` listener.

This ensures zero memory leaks even under heavy instance churn.
