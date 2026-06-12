--!strict
-- Riptide/shared/StateReplication.lua
-- Minimal server-authoritative state replication (global + per-player)
--
-- DESIGN CONTRACT (v0.9.0):
--   • Snapshot sync: fire-and-respond handshake over RemoteEvents.
--     Client fires EVENT_SNAPSHOT (request) → server fires back snapshot payload.
--     No InvokeServer / RemoteFunction required.
--   • notify() is synchronous — subscriber callbacks must not yield.
--   • Delta packets use flat RemoteEvent args (scope, key, value, version)
--     to avoid one table allocation per Set() call.

type Callback = (value: any) -> ()

type NetworkLike = {
	Register: (funcName: string, callback: (...any) -> any) -> (),
	Unregister: (funcName: string, callback: (...any) -> any) -> (),
	FireAllClients: ((funcName: string, ...any) -> ())?,
	FireClient: ((player: any, funcName: string, ...any) -> ())?,
	FireServer: ((funcName: string, ...any) -> ())?,
}

export type StateReplicationDeps = {
	IsServer: boolean,
	Network: NetworkLike,
}

export type StateReplicationAPI = {
	Events: {
		Delta: string,
		Snapshot: string,
	},
	_init: (self: StateReplicationAPI, deps: StateReplicationDeps) -> (),
	Set: (self: StateReplicationAPI, key: string, value: any) -> (),
	SetForPlayer: (self: StateReplicationAPI, player: any, key: string, value: any) -> (),
	UpdateForPlayer: (self: StateReplicationAPI, player: any, key: string, updater: (oldValue: any) -> any) -> any,
	Get: (self: StateReplicationAPI, key: string, player: any?) -> any,
	Subscribe: (self: StateReplicationAPI, key: string, callback: Callback) -> () -> (),
	RequestSync: (self: StateReplicationAPI) -> boolean,
	_onPlayerRemoving: (self: StateReplicationAPI, player: any) -> (),
}

local EVENT_DELTA = "__riptide_state_delta"
local EVENT_SNAPSHOT = "__riptide_state_snapshot"

local function shallowCopy(source: { [string]: any }): { [string]: any }
	return table.clone(source)
end

local function ensureServer(self: any)
	if not self._isServer then
		error("[StateReplication] This method is server-only.", 3)
	end
end

-- ZERO-ALLOCATION HOT PATH — synchronous, no task.spawn.
-- Subscriber callbacks must not yield; use task.defer internally if needed.
local function notify(self: any, key: string, value: any)
	local subscribers = self._subscribers[key]
	if not subscribers then
		return
	end
	for _, callback in ipairs(subscribers) do
		local ok, err = xpcall(callback, debug.traceback, value)
		if not ok then
			warn(string.format("[StateReplication] Subscriber callback error for key '%s': %s", key, tostring(err)))
		end
	end
end

local function getClientResolvedValue(self: any, key: string): any
	local pv = self._clientPlayerState[key]
	if pv ~= nil then
		return pv
	end
	return self._clientGlobalState[key]
end

local function snapshotResolvedState(self: any): { [string]: any }
	local resolved = shallowCopy(self._clientGlobalState)
	for k, v in pairs(self._clientPlayerState) do
		resolved[k] = v
	end
	return resolved
end

-- Flat args: (scope, key, value, version) — no payload table allocation.
local function applyClientDelta(self: any, scope: string, key: string, value: any, version: number)
	local versions: { [string]: number }
	local values: { [string]: any }

	if scope == "player" then
		versions = self._clientPlayerVersions
		values = self._clientPlayerState
	else
		versions = self._clientGlobalVersions
		values = self._clientGlobalState
	end

	local currentVersion: number = versions[key] or 0
	if version <= currentVersion then
		return
	end

	local oldResolved = getClientResolvedValue(self, key)
	versions[key] = version
	values[key] = value
	local newResolved = getClientResolvedValue(self, key)

	if oldResolved ~= newResolved then
		notify(self, key, newResolved)
	end
end

-- ---------------------------------------------------------------------------

local StateReplication = {} :: StateReplicationAPI

StateReplication.Events = {
	Delta = EVENT_DELTA,
	Snapshot = EVENT_SNAPSHOT,
}

StateReplication._initialized = false
StateReplication._isServer = false
StateReplication._network = nil :: NetworkLike?

StateReplication._globalState = {} :: { [string]: any }
StateReplication._globalVersions = {} :: { [string]: number }
StateReplication._playerState = {} :: { [any]: { [string]: any } }
StateReplication._playerVersions = {} :: { [any]: { [string]: number } }

StateReplication._clientGlobalState = {} :: { [string]: any }
StateReplication._clientGlobalVersions = {} :: { [string]: number }
StateReplication._clientPlayerState = {} :: { [string]: any }
StateReplication._clientPlayerVersions = {} :: { [string]: number }

StateReplication._syncYielding = false
-- Each entry: { scope, key, value, version } — buffered during initial sync.
StateReplication._syncBuffer = {} :: { { any } }

StateReplication._subscribers = {} :: { [string]: { Callback } }
StateReplication._deltaHandler = nil :: ((...any) -> any)?
StateReplication._snapshotHandler = nil :: ((...any) -> any)?

local function resetState(self: any)
	if self._network and self._deltaHandler then
		self._network.Unregister(EVENT_DELTA, self._deltaHandler)
	end
	if self._network and self._snapshotHandler then
		self._network.Unregister(EVENT_SNAPSHOT, self._snapshotHandler)
	end

	self._initialized = false
	self._network = nil
	self._deltaHandler = nil
	self._snapshotHandler = nil
	self._isServer = false

	table.clear(self._globalState)
	table.clear(self._globalVersions)
	table.clear(self._clientGlobalState)
	table.clear(self._clientGlobalVersions)
	table.clear(self._clientPlayerState)
	table.clear(self._clientPlayerVersions)
	table.clear(self._subscribers)
	table.clear(self._syncBuffer)
	self._syncYielding = false

	self._playerState = {}
	self._playerVersions = {}
end

function StateReplication:_init(deps: StateReplicationDeps)
	if not deps then
		error("[StateReplication] _init requires a deps table.", 2)
	end
	if type(deps.IsServer) ~= "boolean" then
		error("[StateReplication] _init requires deps.IsServer as boolean.", 2)
	end
	if not deps.Network then
		error("[StateReplication] _init requires deps.Network.", 2)
	end

	if self._initialized then
		resetState(self)
	end

	self._isServer = deps.IsServer
	self._network = deps.Network
	self._initialized = true

	if self._isServer then
		-- SERVER: respond to client snapshot requests.
		-- Protocol: client fires EVENT_SNAPSHOT (no args) → server fires back
		--           one structured snapshot table to that specific client.
		self._snapshotHandler = function(player: any)
			local net = self._network
			if not (net and net.FireClient) then
				return
			end
			local playerState = self._playerState[player] or {}
			local playerVersions = self._playerVersions[player] or {};
			(net.FireClient :: any)(player, EVENT_SNAPSHOT, {
				global = shallowCopy(self._globalState),
				globalVersions = shallowCopy(self._globalVersions),
				player = shallowCopy(playerState),
				playerVersions = shallowCopy(playerVersions),
			})
		end
		self._network.Register(EVENT_SNAPSHOT, self._snapshotHandler)
	else
		-- CLIENT: receive flat-arg delta packets and buffer them during sync.
		self._deltaHandler = function(scope: string, key: string, value: any, version: number)
			if self._syncYielding then
				table.insert(self._syncBuffer, { scope, key, value, version })
			else
				applyClientDelta(self, scope, key, value, version)
			end
		end
		self._network.Register(EVENT_DELTA, self._deltaHandler)
		self:RequestSync()
	end
end

function StateReplication:Set(key: string, value: any)
	ensureServer(self)
	if type(key) ~= "string" then
		error("[StateReplication] Set requires key as string.", 2)
	end

	local nextVersion = (self._globalVersions[key] or 0) + 1
	self._globalVersions[key] = nextVersion
	self._globalState[key] = value

	-- FLAT ARGS: no table allocation per call.
	if self._network and self._network.FireAllClients then
		self._network.FireAllClients(EVENT_DELTA, "global", key, value, nextVersion)
	end
end

function StateReplication:SetForPlayer(player: any, key: string, value: any)
	ensureServer(self)
	if player == nil then
		error("[StateReplication] SetForPlayer requires player.", 2)
	end
	if type(key) ~= "string" then
		error("[StateReplication] SetForPlayer requires key as string.", 2)
	end

	if not self._playerState[player] then
		self._playerState[player] = {}
	end
	if not self._playerVersions[player] then
		self._playerVersions[player] = {}
	end

	local playerVersions = self._playerVersions[player] :: any
	local playerState = self._playerState[player] :: any

	local nextVersion = (playerVersions[key] or 0) + 1
	playerVersions[key] = nextVersion
	playerState[key] = value

	-- FLAT ARGS: no table allocation per call.
	if self._network and self._network.FireClient then
		(self._network.FireClient :: any)(player, EVENT_DELTA, "player", key, value, nextVersion)
	end
end

function StateReplication:UpdateForPlayer(player: any, key: string, updater: (oldValue: any) -> any): any
	ensureServer(self)
	if player == nil then
		error("[StateReplication] UpdateForPlayer requires player.", 2)
	end
	if type(key) ~= "string" then
		error("[StateReplication] UpdateForPlayer requires key as string.", 2)
	end
	if type(updater) ~= "function" then
		error("[StateReplication] UpdateForPlayer requires updater function.", 2)
	end

	local oldValue = self:Get(key, player)
	local newValue = updater(oldValue)
	self:SetForPlayer(player, key, newValue)
	return newValue
end

function StateReplication:Get(key: string, player: any?): any
	if type(key) ~= "string" then
		error("[StateReplication] Get requires key as string.", 2)
	end

	if self._isServer then
		if player ~= nil then
			local playerState = self._playerState[player]
			if playerState and playerState[key] ~= nil then
				return playerState[key]
			end
		end
		return self._globalState[key]
	end

	return getClientResolvedValue(self, key)
end

function StateReplication:Subscribe(key: string, callback: Callback): () -> ()
	if self._isServer then
		error("[StateReplication] Subscribe is a client-only method.", 2)
	end
	if type(key) ~= "string" then
		error("[StateReplication] Subscribe requires key as string.", 2)
	end
	if type(callback) ~= "function" then
		error("[StateReplication] Subscribe requires callback function.", 2)
	end

	if not self._subscribers[key] then
		self._subscribers[key] = {}
	end

	local subscribers = self._subscribers[key]
	table.insert(subscribers, callback)
	callback(self:Get(key))

	return function()
		local list = self._subscribers[key]
		if not list then
			return
		end
		for index, current in ipairs(list) do
			if current == callback then
				table.remove(list, index)
				break
			end
		end
		if #list == 0 then
			self._subscribers[key] = nil
		end
	end
end

--[[
	RequestSync — async fire-and-respond handshake.

	Fires EVENT_SNAPSHOT to the server (no args = "please send me a snapshot").
	Registers a one-shot handler on EVENT_SNAPSHOT to receive the response.
	Deltas arriving during the round-trip are buffered and replayed after the
	snapshot is applied.

	Returns true if the request was dispatched, false if Network is unavailable.
]]
function StateReplication:RequestSync(): boolean
	if self._isServer then
		return false
	end

	local net = self._network
	if not net then
		return false
	end

	-- Guard: don't send a second request if one is already in flight.
	if self._syncYielding then
		return false
	end

	self._syncYielding = true

	-- One-shot handler: fires once when the server replies with a snapshot.
	local onSnapshot: (...any) -> ()
	onSnapshot = function(snapshot: any)
		-- Unregister ourselves immediately.
		net.Unregister(EVENT_SNAPSHOT, onSnapshot)
		self._snapshotHandler = nil
		self._syncYielding = false

		if type(snapshot) ~= "table" then
			table.clear(self._syncBuffer)
			return
		end

		local previousResolved = snapshotResolvedState(self)

		-- Apply the snapshot wholesale.
		table.clear(self._clientGlobalState)
		table.clear(self._clientGlobalVersions)
		table.clear(self._clientPlayerState)
		table.clear(self._clientPlayerVersions)

		for k, v in pairs(snapshot.global or {}) do
			self._clientGlobalState[k] = v
		end
		for k, v in pairs(snapshot.globalVersions or {}) do
			self._clientGlobalVersions[k] = v
		end
		for k, v in pairs(snapshot.player or {}) do
			self._clientPlayerState[k] = v
		end
		for k, v in pairs(snapshot.playerVersions or {}) do
			self._clientPlayerVersions[k] = v
		end

		local currentResolved = snapshotResolvedState(self)

		-- Notify subscribers whose resolved value changed.
		for k, v in pairs(currentResolved) do
			if previousResolved[k] ~= v then
				notify(self, k, v)
			end
		end
		for k in pairs(previousResolved) do
			if currentResolved[k] == nil then
				notify(self, k, nil)
			end
		end

		-- Drain buffered deltas that arrived during the round-trip.
		for _, buffered in ipairs(self._syncBuffer) do
			applyClientDelta(self, buffered[1] :: string, buffered[2] :: string, buffered[3], buffered[4] :: number)
		end
		table.clear(self._syncBuffer)
	end

	-- Store reference so resetState() can unregister it if needed.
	self._snapshotHandler = onSnapshot
	net.Register(EVENT_SNAPSHOT, onSnapshot)

	-- Fire the request to the server.
	if net.FireServer then
		net.FireServer(EVENT_SNAPSHOT)
	end

	return true
end

function StateReplication:_onPlayerRemoving(player: any)
	if player == nil then
		return
	end
	self._playerState[player] = nil
	self._playerVersions[player] = nil
end

return StateReplication
