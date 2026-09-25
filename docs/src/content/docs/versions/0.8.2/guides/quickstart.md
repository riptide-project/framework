---
slug: versions/0.8.2/guides/quickstart
title: Your first 10 minutes
description: Put Riptide 0.8.2 in Roblox Studio and run a tiny server service.
---

This walkthrough uses **Riptide 0.8.2**, the latest stable release. You only need Roblox Studio and a new place. No package manager or Rojo setup is required for this first run.

## 1. Add Riptide to your place

Download `Riptide.rbxm` from the [0.8.2 release](https://github.com/riptide-project/framework/releases/tag/v0.8.2). In Studio, add a `Packages` folder under `ReplicatedStorage`, then insert the model there and name it `Riptide`.

Your Explorer should contain:

```text
ReplicatedStorage
└── Packages
    └── Riptide
```

If you already use Pesde or Rojo, follow the [full setup guide](../getting-started/) instead.

## 2. Create one service

Add a `Services` folder under `ServerScriptService`. Inside it, add a `ModuleScript` named `HelloService` with this code:

```lua
local HelloService = {}

function HelloService:Init(Riptide)
    print("HelloService initialized")
end

function HelloService:Start(Riptide)
    print("HelloService started")
end

return HelloService
```

A **service** is a module that runs on the server. Riptide loads it and calls its lifecycle methods for you.

## 3. Launch the server

Add a `Script` named `main` directly under `ServerScriptService`:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local Riptide = require(ReplicatedStorage.Packages.Riptide)

Riptide.Server.Launch({
    ModulesFolder = ServerScriptService.Services,
})
```

Press **Play**. The Studio Output window should include `HelloService initialized` followed by `HelloService started`. Riptide does not launch by itself; this script is the entry point.

## What just happened?

1. Riptide loaded every module in `Services`.
2. It called each module's `Init` method.
3. After initialization, it dispatched each module's `Start` method.

This separation lets one service look up another during `Init`, then use it during `Start`.

## Next steps

- [Build the full server and client setup](../getting-started/) when you need controllers or networking.
- [Understand the module lifecycle](../module-lifecycle/) before adding dependencies between services.
- [Browse the stable API](../../api/network/) when you need to send an event.

:::tip[If nothing prints]
Check the three names in Explorer: `Packages/Riptide`, `Services/HelloService`, and `main`. Confirm that `main` is a **Script** and `HelloService` is a **ModuleScript**. Open Studio's Output window to see errors.
:::
