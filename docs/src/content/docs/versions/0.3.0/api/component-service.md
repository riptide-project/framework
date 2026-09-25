---
slug: versions/0.3.0/api/component-service
title: Tagged components
description: Build CollectionService components in Riptide 0.3.0.
---

`Riptide.ComponentService` binds component modules to Roblox instances using `CollectionService` tags. Give the component `ModuleScript` the same name as its tag, and pass its folder as `ComponentsFolder` when launching Riptide.

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Riptide = require(ReplicatedStorage.Packages.Riptide)

Riptide.Server.Launch({
    ModulesFolder = ServerScriptService:WaitForChild("ServerModules"),
    ComponentsFolder = ReplicatedStorage:WaitForChild("Components"),
})
```

For a tag named `Sparkle`, place `Sparkle.lua` in `ComponentsFolder`:

```lua
local Sparkle = {}
Sparkle.__index = Sparkle

function Sparkle.new(instance)
    local self = setmetatable({ instance = instance }, Sparkle)
    print("Attached to", instance.Name)
    return self
end

function Sparkle:Destroy()
    print("Removed from", self.instance.Name)
end

return Sparkle
```

When an instance receives the `Sparkle` tag, Riptide constructs a component for it. When the tag or instance goes away, `Destroy` is the place to clean up event connections and other resources.

Look up a component with `Riptide.ComponentService:Get(instance, "Sparkle")`. Use `Get(instance, tagName)` when you want a particular tagged component.

On a client, pass the component folder to `Riptide.Client.Launch` to create client-side components as well. Keep side-specific behavior inside the modules launched on that side.

**Next:** [Read the original component example](../../readme/#example-component-lavalua).

---

This page describes **Riptide 0.3.0**. Check the [original release guide](../../readme/) and [tagged source](https://github.com/riptide-project/framework/tree/v0.3.0) for release-specific details.
