--!strict
-- Riptide/shared/PlayerLifecycle.lua
-- Server-side player lifecycle orchestration for module hooks.

type TaskLibrary = typeof(task)
local task = task
if not task then
	local loadTask: (string) -> TaskLibrary = require
	task = loadTask("@lune/task")
end

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
PlayerLifecycle._playerThreads = {} :: { [any]: thread }
PlayerLifecycle._generation = 0

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
	self._generation += 1
	for _, thread in pairs(self._playerThreads) do
		if thread ~= coroutine.running() then
			pcall(task.cancel, thread)
		end
	end
	table.clear(self._playerThreads)
	disconnectAll(self)
	self._players = nil
	self._stateReplication = nil
	self._onPlayerAdded = nil
	self._onPlayerRemoving = nil
	self._started = false
end

function PlayerLifecycle._init(self: any, deps: PlayerLifecycleDeps)
	if not deps or not deps.Players then
		error("[PlayerLifecycle] _init requires deps.Players", 2)
	end

	resetState(self)
	self._players = deps.Players
	self._stateReplication = deps.StateReplication
	self._onPlayerAdded = deps.OnPlayerAdded
	self._onPlayerRemoving = deps.OnPlayerRemoving
end

function PlayerLifecycle.Start(self: any, modules: { { name: string, module: any } }, riptideRef: any)
	if self._started then
		return
	end
	if not self._players then
		error("[PlayerLifecycle] Start called before _init.", 2)
	end

	self._started = true

	local generation = self._generation
	local seen: { [any]: boolean? } = {}
	local scanning = true
	local function onAdded(player: any)
		if seen[player] then
			return
		end
		seen[player] = true
		task.spawn(function()
			local thread = coroutine.running()
			self._playerThreads[player] = thread
			for _, data in ipairs(modules) do
				if self._generation ~= generation or self._playerThreads[player] ~= thread then
					return
				end
				callHook({ data }, "OnPlayerAdded", riptideRef, player)
			end
			if self._generation ~= generation or self._playerThreads[player] ~= thread then
				return
			end
			if self._onPlayerAdded then
				local ok, err = pcall(self._onPlayerAdded, player)
				if not ok then
					warn(tostring(err))
				end
			end
			if self._playerThreads[player] == thread then
				self._playerThreads[player] = nil
			end
		end)
	end

	table.insert(self._connections, self._players.PlayerAdded:Connect(onAdded))

	table.insert(
		self._connections,
		self._players.PlayerRemoving:Connect(function(player: any)
			seen[player] = if scanning then true else nil
			local thread = self._playerThreads[player]
			self._playerThreads[player] = nil
			if thread and thread ~= coroutine.running() then
				pcall(task.cancel, thread)
			end
			callHook(modules, "OnPlayerRemoving", riptideRef, player)
			if self._stateReplication and type(self._stateReplication._onPlayerRemoving) == "function" then
				self._stateReplication:_onPlayerRemoving(player)
			end
			if self._onPlayerRemoving then
				self._onPlayerRemoving(player)
			end
		end)
	)
	-- Connect before GetPlayers or any user hook can yield.
	for _, player in ipairs(self._players:GetPlayers()) do
		onAdded(player)
	end
	scanning = false
	table.clear(seen)
end

export type PlayerLifecycleAPI = {
	_init: (self: any, deps: PlayerLifecycleDeps) -> (),
	Start: (self: any, modules: { { name: string, module: any } }, riptideRef: any) -> (),
}

return PlayerLifecycle :: PlayerLifecycleAPI
