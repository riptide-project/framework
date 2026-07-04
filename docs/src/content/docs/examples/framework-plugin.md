---
title: Framework Plugin
description: A framework-layer plugin with PublicAPI, dependency ordering, and bounded Start readiness.
---

Plugins are for framework extensions: data/profile services, ECS bridges, shared component registration, analytics, anti-cheat, or project-wide infrastructure.

```lua
-- ServerScriptService/Plugins/ProfilePlugin.lua
--!strict

local ProfilePlugin = {}

type ProfileAPI = {
	GetCoins: (player: Player) -> number,
	SetCoins: (player: Player, coins: number) -> (),
}

local profiles: { [Player]: { coins: number } } = {}

ProfilePlugin.Descriptor = {
	Name = "ProfilePlugin",
	Version = "0.1.0",
	Side = "Server",
	StartTimeout = 5,
	PublicAPI = nil :: ProfileAPI?,
}

ProfilePlugin.Descriptor.PublicAPI = {
	GetCoins = function(player: Player): number
		local profile = profiles[player]
		return if profile then profile.coins else 0
	end,

	SetCoins = function(player: Player, coins: number)
		local profile = profiles[player]
		if profile then
			profile.coins = coins
		end
	end,
}

ProfilePlugin.Hooks = {
	Init = function(_self, sandbox)
		sandbox:Log("Profile API is available")
	end,

	Start = function(_self, sandbox)
		-- Do bounded setup that must be ready before modules start.
		sandbox:Log("Profile storage is ready")
	end,

	OnPlayerAdded = function(_self, _sandbox, player: Player)
		profiles[player] = { coins = 100 }
	end,

	OnPlayerRemoving = function(_self, _sandbox, player: Player)
		profiles[player] = nil
	end,
}

return ProfilePlugin
```

Launch with plugins before game modules:

```lua
local Riptide = require(ReplicatedStorage.Packages.Riptide).Server

Riptide.Launch({
	PluginsFolder = ServerScriptService.Plugins,
	ModulesFolder = ServerScriptService.Services,
})
```

Consume the plugin from a service:

```lua
function EconomyService:Init(Riptide)
	local entry = Riptide.Plugins:GetPlugin("ProfilePlugin")
	local api = if entry then entry.descriptor.PublicAPI else nil
	assert(api, "ProfilePlugin is required")

	self.Profile = api
end
```

Plugin `Start` is a readiness gate. If a plugin needs a forever loop, spawn it inside `Start`:

```lua
function Plugin.Hooks:Start(sandbox)
	task.spawn(function()
		while true do
			task.wait(60)
			sandbox:Log("Background tick")
		end
	end)
end
```
