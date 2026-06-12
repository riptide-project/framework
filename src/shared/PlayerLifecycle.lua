--!strict
-- Riptide/shared/PlayerLifecycle.lua
-- Server-side player lifecycle orchestration for module hooks.

export type PlayerLifecycleDeps = {
	Players: any,
	StateReplication: any?,
	OnPlayerAdded: ((player: any) -> ())?,
	OnPlayerRemoving: ((player: any) -> ())?,
}

local PlayerLifecycle = {}

PlayerLifecycle._players = nil :: any
PlayerLifecycle._stateReplication = nil :: any
PlayerLifecycle._onPlayerAdded = nil :: any
PlayerLifecycle._onPlayerRemoving = nil :: any
PlayerLifecycle._started = false
PlayerLifecycle._connections = {} :: { any }

local function disconnectAll(self: any)
	for _, connection in ipairs(self._connections) do
		if connection and type(connection.Disconnect) == "function" then
			connection:Disconnect()
		end
	end
	table.clear(self._connections)
end

local function callHook(modules: { { name: string, module: any } }, hookName: string, riptideRef: any, player: any)
	for _, data in ipairs(modules) do
		local hook = data.module[hookName]
		if type(hook) == "function" then
			local ok, err = xpcall(hook, debug.traceback, data.module, riptideRef, player)
			if not ok then
				warn(string.format("[PlayerLifecycle] Error in %s for %s:\n%s", hookName, data.name, tostring(err)))
			end
		end
	end
end

local function resetState(self: any)
	disconnectAll(self)
	self._players = nil
	self._stateReplication = nil
	self._onPlayerAdded = nil
	self._onPlayerRemoving = nil
	self._started = false
end

function PlayerLifecycle:_init(deps: PlayerLifecycleDeps)
	if not deps or not deps.Players then
		error("[PlayerLifecycle] _init requires deps.Players", 2)
	end

	resetState(self)
	self._players = deps.Players
	self._stateReplication = deps.StateReplication
	self._onPlayerAdded = deps.OnPlayerAdded
	self._onPlayerRemoving = deps.OnPlayerRemoving
end

function PlayerLifecycle:Start(modules: { { name: string, module: any } }, riptideRef: any)
	if self._started then
		return
	end
	if not self._players then
		error("[PlayerLifecycle] Start called before _init.", 2)
	end

	self._started = true

	for _, player in ipairs(self._players:GetPlayers()) do
		callHook(modules, "OnPlayerAdded", riptideRef, player)
		if self._onPlayerAdded then
			self._onPlayerAdded(player)
		end
	end

	table.insert(
		self._connections,
		self._players.PlayerAdded:Connect(function(player: any)
			callHook(modules, "OnPlayerAdded", riptideRef, player)
			if self._onPlayerAdded then
				self._onPlayerAdded(player)
			end
		end)
	)

	table.insert(
		self._connections,
		self._players.PlayerRemoving:Connect(function(player: any)
			callHook(modules, "OnPlayerRemoving", riptideRef, player)
			if self._stateReplication and type(self._stateReplication._onPlayerRemoving) == "function" then
				self._stateReplication:_onPlayerRemoving(player)
			end
			if self._onPlayerRemoving then
				self._onPlayerRemoving(player)
			end
		end)
	)
end

export type PlayerLifecycleAPI = {
	_init: (self: any, deps: PlayerLifecycleDeps) -> (),
	Start: (self: any, modules: { { name: string, module: any } }, riptideRef: any) -> (),
}

return PlayerLifecycle :: PlayerLifecycleAPI
