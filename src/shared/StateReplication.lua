--!strict
-- Riptide/shared/StateReplication.lua
-- Minimal server-authoritative state replication (global + per-player)
--
-- DESIGN CONTRACT (v0.9.0):
--   • Snapshot sync: fire-and-respond handshake over RemoteEvents.
--     Client fires EVENT_SNAPSHOT (request id) → server echoes it in the snapshot.
--     No InvokeServer / RemoteFunction required.
--   • notify() is synchronous — subscriber callbacks must not yield.
--   • Delta packets use flat RemoteEvent args (scope, key, value, version)
--     to avoid one table allocation per Set() call.

type TaskLibrary = typeof(task)
local task = task
if not task then
	local loadTask: (string) -> TaskLibrary = require
	task = loadTask("@lune/task")
end

type Callback = (value: any) -> ()

type NetworkLike = {
	_registerInternal: (funcName: string, callback: (...any) -> ...any) -> (),
	_unregisterInternal: (funcName: string, callback: (...any) -> ...any) -> (),
	_fireInternalAllClients: ((funcName: string, ...any) -> ())?,
	_fireInternalClient: ((player: any, funcName: string, ...any) -> ())?,
	_fireInternalServer: ((funcName: string, ...any) -> ())?,
}

export type StateReplicationDeps = {
	IsServer: boolean,
	Network: NetworkLike,
	SyncTimeout: number?,
}

export type StateReplicationEvents = {
	Delta: string,
	Snapshot: string,
}

export type StateReplicationCommonAPI = {
	Events: StateReplicationEvents,
	_init: (self: any, deps: StateReplicationDeps) -> (),
	Get: (self: any, key: string, player: any?) -> any,
}

export type ServerKey<T> = {
	Get: (self: ServerKey<T>, player: any?) -> T?,
	Set: (self: ServerKey<T>, value: T) -> (),
	SetForPlayer: (self: ServerKey<T>, player: any, value: T) -> (),
	UpdateForPlayer: (self: ServerKey<T>, player: any, updater: (oldValue: T?) -> T) -> T,
}

export type ClientKey<T> = {
	Get: (self: ClientKey<T>) -> T?,
	Subscribe: (self: ClientKey<T>, callback: (value: T?) -> ()) -> () -> (),
}

export type StateReplicationServerBaseAPI = StateReplicationCommonAPI & {
	Set: (self: StateReplicationServerBaseAPI, key: string, value: any) -> (),
	SetForPlayer: (self: StateReplicationServerBaseAPI, player: any, key: string, value: any) -> (),
	UpdateForPlayer: (
		self: StateReplicationServerBaseAPI,
		player: any,
		key: string,
		updater: (oldValue: any) -> any
	) -> any,
	_onPlayerRemoving: (self: StateReplicationServerBaseAPI, player: any) -> (),
}

export type StateReplicationClientBaseAPI = StateReplicationCommonAPI & {
	Subscribe: (self: StateReplicationClientBaseAPI, key: string, callback: Callback) -> () -> (),
	RequestSync: (self: StateReplicationClientBaseAPI) -> boolean,
}

export type TypedServer<TSchema> = StateReplicationServerBaseAPI & TSchema
export type TypedClient<TSchema> = StateReplicationClientBaseAPI & TSchema

export type StateReplicationServerAPI = StateReplicationServerBaseAPI & {
	TypedServer: <TSchema>() -> TypedServer<TSchema>,
	TypedClient: nil,
}

export type StateReplicationClientAPI = StateReplicationClientBaseAPI & {
	TypedServer: nil,
	TypedClient: <TSchema>() -> TypedClient<TSchema>,
}

export type StateReplicationAPI = {
	Events: StateReplicationEvents,
	_init: (self: StateReplicationAPI, deps: StateReplicationDeps) -> (),
	Set: (self: StateReplicationAPI, key: string, value: any) -> (),
	SetForPlayer: (self: StateReplicationAPI, player: any, key: string, value: any) -> (),
	UpdateForPlayer: (self: StateReplicationAPI, player: any, key: string, updater: (oldValue: any) -> any) -> any,
	Get: (self: StateReplicationAPI, key: string, player: any?) -> any,
	Subscribe: (self: StateReplicationAPI, key: string, callback: Callback) -> () -> (),
	RequestSync: (self: StateReplicationAPI) -> boolean,
	_onPlayerRemoving: (self: StateReplicationAPI, player: any) -> (),
	TypedServer: (<TSchema>() -> TypedServer<TSchema>)?,
	TypedClient: (<TSchema>() -> TypedClient<TSchema>)?,
}

local EVENT_DELTA = "__riptide_state_delta"
local EVENT_SNAPSHOT = "__riptide_state_snapshot"
local SNAPSHOT_REQUEST_COOLDOWN_SECONDS = 1
local DEFAULT_SYNC_TIMEOUT = 10

local function validVersion(value: any): boolean
	return type(value) == "number" and value > 0 and value < math.huge and value % 1 == 0
end

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

local function isValidDelta(scope: any, key: any, version: any): boolean
	if scope ~= "global" and scope ~= "player" then
		warn(string.format("[StateReplication] Ignoring malformed delta with invalid scope: %s", tostring(scope)))
		return false
	end
	if type(key) ~= "string" then
		warn(string.format("[StateReplication] Ignoring malformed delta with non-string key: %s", typeof(key)))
		return false
	end
	if not validVersion(version) then
		warn(string.format("[StateReplication] Ignoring malformed delta with invalid version: %s", tostring(version)))
		return false
	end
	return true
end

local function getSnapshotMap(snapshot: any, fieldName: string): { [any]: any }
	local value = snapshot[fieldName]
	if value == nil then
		return {}
	end
	if type(value) ~= "table" then
		warn(string.format("[StateReplication] Ignoring malformed snapshot field '%s'.", fieldName))
		return {}
	end
	return value
end

local function applySnapshotValues(target: { [string]: any }, source: { [any]: any })
	for k, v in pairs(source) do
		if type(k) == "string" then
			target[k] = v
		else
			warn("[StateReplication] Ignoring snapshot value with non-string key.")
		end
	end
end

local function applySnapshotVersions(target: { [string]: number }, source: { [any]: any })
	for k, v in pairs(source) do
		if type(k) == "string" and validVersion(v) then
			target[k] = v
		else
			warn("[StateReplication] Ignoring malformed snapshot version entry.")
		end
	end
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

type StateReplicationInternal = {
	Events: StateReplicationEvents,
	_init: (self: StateReplicationInternal, deps: StateReplicationDeps) -> (),
	Set: (self: StateReplicationInternal, key: string, value: any) -> (),
	SetForPlayer: (self: StateReplicationInternal, player: any, key: string, value: any) -> (),
	UpdateForPlayer: (self: StateReplicationInternal, player: any, key: string, updater: (oldValue: any) -> any) -> any,
	Get: (self: StateReplicationInternal, key: string, player: any?) -> any,
	Subscribe: (self: StateReplicationInternal, key: string, callback: Callback) -> () -> (),
	RequestSync: (self: StateReplicationInternal) -> boolean,
	_onPlayerRemoving: (self: StateReplicationInternal, player: any) -> (),
	TypedServer: (<TSchema>() -> TypedServer<TSchema>)?,
	TypedClient: (<TSchema>() -> TypedClient<TSchema>)?,

	_initialized: boolean,
	_isServer: boolean,
	_network: NetworkLike?,
	_globalState: { [string]: any },
	_globalVersions: { [string]: number },
	_playerState: { [any]: { [string]: any } },
	_playerVersions: { [any]: { [string]: number } },
	_clientGlobalState: { [string]: any },
	_clientGlobalVersions: { [string]: number },
	_clientPlayerState: { [string]: any },
	_clientPlayerVersions: { [string]: number },
	_syncYielding: boolean,
	_syncBuffer: { { any } },
	_syncTimer: thread?,
	_syncTimeout: number,
	_nextRequestId: number?,
	_subscribers: { [string]: { Callback }? },
	_deltaHandler: ((...any) -> ...any)?,
	_snapshotHandler: ((...any) -> ...any)?,
	_snapshotRequestTimes: { [any]: number },
	_snapshotRetryResponseTimes: { [any]: number },
}

local StateReplication = {} :: StateReplicationInternal
local TypedServerProxy: any = nil
local TypedClientProxy: any = nil

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
-- Kept empty for diagnostics; deltas now apply immediately, even during sync.
StateReplication._syncBuffer = {} :: { { any } }

StateReplication._subscribers = {} :: { [string]: { Callback } }
StateReplication._deltaHandler = nil :: ((...any) -> ...any)?
StateReplication._snapshotHandler = nil :: ((...any) -> ...any)?
StateReplication._snapshotRequestTimes = {} :: { [any]: number }
StateReplication._snapshotRetryResponseTimes = {} :: { [any]: number }

local function createServerKeyProxy(key: string): any
	return {
		Get = function(_self: any, player: any?)
			return StateReplication:Get(key, player)
		end,
		Set = function(_self: any, value: any)
			StateReplication:Set(key, value)
		end,
		SetForPlayer = function(_self: any, player: any, value: any)
			StateReplication:SetForPlayer(player, key, value)
		end,
		UpdateForPlayer = function(_self: any, player: any, updater: (oldValue: any) -> any): any
			return StateReplication:UpdateForPlayer(player, key, updater)
		end,
	}
end

local function createClientKeyProxy(key: string): any
	return {
		Get = function(_self: any)
			return StateReplication:Get(key)
		end,
		Subscribe = function(_self: any, callback: Callback): () -> ()
			return StateReplication:Subscribe(key, callback)
		end,
	}
end

local function createTypedServerProxy(): any
	local keyCache: { [string]: any } = {}

	return setmetatable({}, {
		__index = function(_self, key: any)
			local stateMember = (StateReplication :: any)[key]
			if stateMember ~= nil then
				return stateMember
			end

			if type(key) ~= "string" then
				return nil
			end

			local keyProxy = keyCache[key]
			if keyProxy then
				return keyProxy
			end

			keyProxy = createServerKeyProxy(key)
			keyCache[key] = keyProxy
			return keyProxy
		end,
	})
end

local function createTypedClientProxy(): any
	local keyCache: { [string]: any } = {}

	return setmetatable({}, {
		__index = function(_self, key: any)
			local stateMember = (StateReplication :: any)[key]
			if stateMember ~= nil then
				return stateMember
			end

			if type(key) ~= "string" then
				return nil
			end

			local keyProxy = keyCache[key]
			if keyProxy then
				return keyProxy
			end

			keyProxy = createClientKeyProxy(key)
			keyCache[key] = keyProxy
			return keyProxy
		end,
	})
end

local function typedServer<TSchema>(): TypedServer<TSchema>
	if not TypedServerProxy then
		TypedServerProxy = createTypedServerProxy()
	end
	return (TypedServerProxy :: any) :: TypedServer<TSchema>
end

local function typedClient<TSchema>(): TypedClient<TSchema>
	if not TypedClientProxy then
		TypedClientProxy = createTypedClientProxy()
	end
	return (TypedClientProxy :: any) :: TypedClient<TSchema>
end

local function resetState(self: any)
	if self._syncTimer then
		task.cancel(self._syncTimer)
		self._syncTimer = nil
	end
	if self._network and self._deltaHandler then
		self._network._unregisterInternal(EVENT_DELTA, self._deltaHandler)
	end
	if self._network and self._snapshotHandler then
		self._network._unregisterInternal(EVENT_SNAPSHOT, self._snapshotHandler)
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
	table.clear(self._snapshotRequestTimes)
	table.clear(self._snapshotRetryResponseTimes)
	self._syncYielding = false
	TypedServerProxy = nil
	TypedClientProxy = nil
	self.TypedServer = nil
	self.TypedClient = nil

	self._playerState = {}
	self._playerVersions = {}
end

function StateReplication._init(self: StateReplicationInternal, deps: StateReplicationDeps)
	if not deps then
		error("[StateReplication] _init requires a deps table.", 2)
	end
	if type(deps.IsServer) ~= "boolean" then
		error("[StateReplication] _init requires deps.IsServer as boolean.", 2)
	end
	if not deps.Network then
		error("[StateReplication] _init requires deps.Network.", 2)
	end

	local syncTimeout = deps.SyncTimeout or DEFAULT_SYNC_TIMEOUT
	if type(syncTimeout) ~= "number" or syncTimeout <= 0 or syncTimeout >= math.huge or syncTimeout ~= syncTimeout then
		error("[StateReplication] SyncTimeout must be a finite positive number.", 2)
	end
	if self._initialized then
		resetState(self)
	end

	self._syncTimeout = syncTimeout
	self._isServer = deps.IsServer
	self._network = deps.Network
	self._initialized = true

	if self._isServer then
		-- Preserve the generic factory at the optional API boundary.
		self.TypedServer = typedServer :: any
		self.TypedClient = nil

		self._snapshotHandler = function(player: any, requestId: any)
			if player == nil then
				warn("[StateReplication] Ignoring snapshot request without a player.")
				return
			end
			if requestId ~= nil and not validVersion(requestId) then
				return
			end
			local net = self._network
			if not (net and net._fireInternalClient) then
				return
			end

			local now = os.clock()
			local lastRequestTime = self._snapshotRequestTimes[player]
			if lastRequestTime ~= nil and now - lastRequestTime < SNAPSHOT_REQUEST_COOLDOWN_SECONDS then
				local lastRetryResponseTime = self._snapshotRetryResponseTimes[player]
				if
					requestId ~= nil
					and (
						lastRetryResponseTime == nil
						or now - lastRetryResponseTime >= SNAPSHOT_REQUEST_COOLDOWN_SECONDS
					)
				then
					self._snapshotRetryResponseTimes[player] = now
					local fireClient = net._fireInternalClient :: any
					fireClient(player, EVENT_SNAPSHOT, {
						requestId = requestId,
						retryAfter = SNAPSHOT_REQUEST_COOLDOWN_SECONDS - (now - lastRequestTime),
					})
				end
				return
			end
			self._snapshotRequestTimes[player] = now
			self._snapshotRetryResponseTimes[player] = nil

			local playerState = self._playerState[player] or {}
			local playerVersions = self._playerVersions[player] or {}
			(net._fireInternalClient :: any)(player, EVENT_SNAPSHOT, {
				requestId = requestId,
				global = shallowCopy(self._globalState),
				globalVersions = shallowCopy(self._globalVersions),
				player = shallowCopy(playerState),
				playerVersions = shallowCopy(playerVersions),
			})
		end
		deps.Network._registerInternal(EVENT_SNAPSHOT, self._snapshotHandler :: (...any) -> ...any)
	else
		self.TypedServer = nil
		-- Preserve the generic factory at the optional API boundary.
		self.TypedClient = typedClient :: any

		-- CLIENT: apply live deltas during sync; snapshot versions prevent rollback.
		self._deltaHandler = function(scope: any, key: any, value: any, version: any)
			if not isValidDelta(scope, key, version) then
				return
			end
			applyClientDelta(self, scope, key, value, version)
		end
		deps.Network._registerInternal(EVENT_DELTA, self._deltaHandler :: (...any) -> ...any)
		self:RequestSync()
	end
end

function StateReplication.Set(self: StateReplicationInternal, key: string, value: any)
	ensureServer(self)
	if type(key) ~= "string" then
		error("[StateReplication] Set requires key as string.", 2)
	end

	local nextVersion = (self._globalVersions[key] or 0) + 1
	self._globalVersions[key] = nextVersion
	self._globalState[key] = value

	-- FLAT ARGS: no table allocation per call.
	if self._network and self._network._fireInternalAllClients then
		self._network._fireInternalAllClients(EVENT_DELTA, "global", key, value, nextVersion)
	end
end

function StateReplication.SetForPlayer(self: StateReplicationInternal, player: any, key: string, value: any)
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
	if self._network and self._network._fireInternalClient then
		(self._network._fireInternalClient :: any)(player, EVENT_DELTA, "player", key, value, nextVersion)
	end
end

function StateReplication.UpdateForPlayer(
	self: StateReplicationInternal,
	player: any,
	key: string,
	updater: (oldValue: any) -> any
): any
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

function StateReplication.Get(self: StateReplicationInternal, key: string, player: any?): any
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

function StateReplication.Subscribe(self: StateReplicationInternal, key: string, callback: Callback): () -> ()
	if self._isServer then
		error("[StateReplication] Subscribe is a client-only method.", 2)
	end
	if type(key) ~= "string" then
		error("[StateReplication] Subscribe requires key as string.", 2)
	end
	if type(callback) ~= "function" then
		error("[StateReplication] Subscribe requires callback function.", 2)
	end

	local active = true
	local function listener(value: any)
		if active then
			callback(value)
		end
	end
	local subscribers = table.clone(self._subscribers[key] or {})
	table.insert(subscribers, listener)
	self._subscribers[key] = subscribers
	local function unsubscribe()
		if not active then
			return
		end
		active = false
		local list = self._subscribers[key]
		if not list then
			return
		end
		local updated = table.clone(list)
		local index = table.find(updated, listener)
		if index then
			table.remove(updated, index)
		end
		self._subscribers[key] = if #updated > 0 then updated else nil
	end
	local protectedResult = table.pack(pcall(callback, self:Get(key)))
	local ok, err = protectedResult[1], protectedResult[2]
	if not ok then
		unsubscribe()
		error(err, 0)
	end
	return unsubscribe
end

-- Snapshot requests have an id, a deadline, and at most three attempts.
-- Legacy servers may omit the id; per-key versions still prevent rollback.
-- Deltas remain live while waiting, so unavailable servers cannot grow a queue.
function StateReplication.RequestSync(self: StateReplicationInternal): boolean
	if self._isServer then
		return false
	end

	local net = self._network
	if not net or not net._fireInternalServer then
		return false
	end

	-- Guard: don't send a second request if one is already in flight.
	if self._syncYielding then
		return false
	end

	self._syncYielding = true

	local attempts = 0
	local requestId = 0
	local retryPending = false
	local sendRequest: () -> boolean
	local onSnapshot: (...any) -> ()
	local function cancelTimer()
		if self._syncTimer then
			task.cancel(self._syncTimer)
			self._syncTimer = nil
		end
	end
	local function finish()
		cancelTimer()
		net._unregisterInternal(EVENT_SNAPSHOT, onSnapshot)
		self._snapshotHandler = nil
		self._syncYielding = false
	end
	local function retryAfter(delaySeconds: number)
		cancelTimer()
		if attempts >= 3 then
			finish()
			warn(
				"[StateReplication] Snapshot retries exhausted; live deltas remain enabled. RequestSync may be retried."
			)
			return
		end
		retryPending = true
		self._syncTimer = task.delay(delaySeconds, function()
			self._syncTimer = nil
			if self._snapshotHandler == onSnapshot then
				sendRequest()
			end
		end)
	end

	onSnapshot = function(snapshot: any)
		if self._snapshotHandler ~= onSnapshot or type(snapshot) ~= "table" then
			return
		end
		if snapshot.requestId ~= nil and snapshot.requestId ~= requestId then
			return
		end
		if snapshot.retryAfter ~= nil then
			if
				not retryPending
				and type(snapshot.retryAfter) == "number"
				and snapshot.retryAfter >= 0
				and snapshot.retryAfter < math.huge
			then
				retryAfter(math.max(SNAPSHOT_REQUEST_COOLDOWN_SECONDS, snapshot.retryAfter))
			end
			return
		end
		finish()

		local previousResolved = snapshotResolvedState(self)

		local oldGlobal = table.clone(self._clientGlobalState)
		local oldGlobalVersions = table.clone(self._clientGlobalVersions)
		local oldPlayer = table.clone(self._clientPlayerState)
		local oldPlayerVersions = table.clone(self._clientPlayerVersions)

		-- Apply the snapshot, retaining any newer values (including deletions).
		table.clear(self._clientGlobalState)
		table.clear(self._clientGlobalVersions)
		table.clear(self._clientPlayerState)
		table.clear(self._clientPlayerVersions)

		applySnapshotValues(self._clientGlobalState, getSnapshotMap(snapshot, "global"))
		applySnapshotVersions(self._clientGlobalVersions, getSnapshotMap(snapshot, "globalVersions"))
		applySnapshotValues(self._clientPlayerState, getSnapshotMap(snapshot, "player"))
		applySnapshotVersions(self._clientPlayerVersions, getSnapshotMap(snapshot, "playerVersions"))

		for key, version in pairs(oldGlobalVersions) do
			if version >= (self._clientGlobalVersions[key] or 0) then
				self._clientGlobalVersions[key] = version
				self._clientGlobalState[key] = oldGlobal[key]
			end
		end
		for key, version in pairs(oldPlayerVersions) do
			if version >= (self._clientPlayerVersions[key] or 0) then
				self._clientPlayerVersions[key] = version
				self._clientPlayerState[key] = oldPlayer[key]
			end
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
	end

	-- Store reference so resetState() can unregister it if needed.
	self._snapshotHandler = onSnapshot
	net._registerInternal(EVENT_SNAPSHOT, onSnapshot)

	sendRequest = function(): boolean
		attempts += 1
		retryPending = false
		self._nextRequestId = (self._nextRequestId or 0) + 1
		requestId = self._nextRequestId :: number
		self._syncTimer = task.delay(self._syncTimeout, function()
			self._syncTimer = nil
			if self._snapshotHandler == onSnapshot then
				retryAfter(SNAPSHOT_REQUEST_COOLDOWN_SECONDS)
			end
		end)
		local protectedResult = table.pack(pcall(net._fireInternalServer, EVENT_SNAPSHOT, requestId))
		local ok, err = protectedResult[1], protectedResult[2]
		if not ok then
			finish()
			warn(string.format("[StateReplication] Snapshot request failed: %s", tostring(err)))
			return false
		end
		return true
	end
	return sendRequest()
end

function StateReplication._onPlayerRemoving(self: StateReplicationInternal, player: any)
	if player == nil then
		return
	end
	self._playerState[player] = nil
	self._playerVersions[player] = nil
	self._snapshotRequestTimes[player] = nil
	self._snapshotRetryResponseTimes[player] = nil
end

return (StateReplication :: any) :: StateReplicationAPI
