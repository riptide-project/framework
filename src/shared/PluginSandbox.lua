--!strict
-- Riptide/shared/PluginSandbox.lua
-- Mediator facade between a plugin and core framework modules.
-- Each plugin receives its own PluginSandbox instance.
-- All resources registered through the sandbox are tracked in a Trove
-- and can be force-cleaned on crash without calling Stop/Destroy.

-- ---------------------------------------------------------------------------
-- Type imports (structural subtypes — no direct require to avoid coupling)
-- ---------------------------------------------------------------------------

type Callback = (...any) -> any
type UnsubscribeFn = () -> ()

type NetworkLike = {
	Register: (funcName: string, callback: Callback) -> (),
	Unregister: (funcName: string, callback: Callback) -> (),
	FireClient: ((player: Player, funcName: string, ...any) -> ())?,
	FireAllClients: ((funcName: string, ...any) -> ())?,
	FireServer: ((funcName: string, ...any) -> ())?,
}

type StateLike = {
	Get: (self: any, key: string, player: any?) -> any,
	Set: (self: any, key: string, value: any) -> (),
	SetForPlayer: (self: any, player: any, key: string, value: any) -> (),
	Subscribe: (self: any, key: string, callback: (value: any) -> ()) -> UnsubscribeFn,
}

type SignalLike = {
	new: () -> SignalInstance,
}

type SignalInstance = {
	Destroy: (self: SignalInstance) -> (),
	Connect: (self: SignalInstance, fn: (...any) -> ()) -> any,
	Fire: (self: SignalInstance, ...any) -> (),
	[string]: any,
}

type ComponentServiceLike = {
	_start: (self: any, componentsFolder: Folder) -> (),
	UnregisterTag: (self: any, tagName: string) -> (),
	[string]: any,
}

type ComponentClass = {
	new: (instance: Instance) -> any,
	Destroy: ((self: any) -> ())?,
}

-- ---------------------------------------------------------------------------
-- Trove entry types
-- ---------------------------------------------------------------------------

type TroveEntrySignal = {
	kind: "signal",
	signal: SignalInstance,
}

type TroveEntryNetworkHandler = {
	kind: "networkHandler",
	name: string,
	callback: Callback,
}

type TroveEntryStateSubscription = {
	kind: "stateSubscription",
	unsubscribe: UnsubscribeFn,
}

type TroveEntryEventBus = {
	kind: "eventBus",
	unsubscribe: UnsubscribeFn,
}

type TroveEntryComponentTag = {
	kind: "componentTag",
	tagName: string,
}

type TroveEntry =
	TroveEntrySignal
	| TroveEntryNetworkHandler
	| TroveEntryStateSubscription
	| TroveEntryEventBus
	| TroveEntryComponentTag

-- ---------------------------------------------------------------------------
-- Public API type (re-exported for PluginManager and plugin authors)
-- ---------------------------------------------------------------------------

export type SandboxDeps = {
	Network: NetworkLike,
	State: StateLike,
	Signal: SignalLike,
	ComponentService: ComponentServiceLike,
	IsServer: boolean,
	Async: any,
	-- Injected by PluginManager after construction:
	PluginName: string,
	GetPluginAPI: (pluginName: string) -> { [string]: any }?,
	EmitBusEvent: (eventName: string, ...any) -> (),
	OnBusEvent: (eventName: string, callback: Callback) -> UnsubscribeFn,
}

export type PluginSandboxAPI = {
	PluginName: string,

	-- State
	GetState: (self: PluginSandboxAPI, key: string, player: Player?) -> any,
	SetState: (self: PluginSandboxAPI, key: string, value: any) -> (),
	SetPlayerState: (self: PluginSandboxAPI, player: Player, key: string, value: any) -> (),
	SubscribeState: (self: PluginSandboxAPI, key: string, callback: (value: any) -> ()) -> UnsubscribeFn,

	-- Network (namespaced)
	OnNetworkEvent: (self: PluginSandboxAPI, name: string, callback: Callback) -> (),
	OffNetworkEvent: (self: PluginSandboxAPI, name: string, callback: Callback) -> (),
	FireClient: (self: PluginSandboxAPI, player: Player, name: string, ...any) -> (),
	FireAllClients: (self: PluginSandboxAPI, name: string, ...any) -> (),
	FireServer: (self: PluginSandboxAPI, name: string, ...any) -> (),

	-- Network (core escape hatch — no namespacing)
	OnCoreEvent: (self: PluginSandboxAPI, name: string, callback: Callback) -> (),

	-- Signals
	CreateSignal: (self: PluginSandboxAPI) -> SignalInstance,

	-- Components
	RegisterComponent: (self: PluginSandboxAPI, tag: string, componentClass: ComponentClass) -> (),

	-- Event Bus (inter-plugin)
	Emit: (self: PluginSandboxAPI, eventName: string, ...any) -> (),
	On: (self: PluginSandboxAPI, eventName: string, callback: Callback) -> UnsubscribeFn,

	-- Logging
	Log: (self: PluginSandboxAPI, message: string) -> (),
	Warn: (self: PluginSandboxAPI, message: string) -> (),

	-- Inter-plugin
	GetPluginAPI: (self: PluginSandboxAPI, pluginName: string) -> { [string]: any }?,

	-- Async
	RunAsync: (self: PluginSandboxAPI, fn: Callback, timeout: number, ...any) -> any,

	-- Internal: called by PluginManager on crash — NOT for plugin use
	CleanupAll: (self: PluginSandboxAPI) -> (),
}

-- ---------------------------------------------------------------------------
-- Implementation
-- ---------------------------------------------------------------------------

local PluginSandbox = {}
PluginSandbox.__index = PluginSandbox

-- Builds the namespaced network event name for this plugin.
local function ns(pluginName: string, eventName: string): string
	return "__plugin:" .. pluginName .. ":" .. eventName
end

-- Appends an entry to the sandbox Trove.
local function track(self: any, entry: TroveEntry)
	table.insert(self._trove, entry)
end

-- Removes a network handler entry from the Trove (used by OffNetworkEvent).
local function untrackNetworkHandler(self: any, namespacedName: string, callback: Callback)
	local trove = self._trove :: { TroveEntry }
	for i = #trove, 1, -1 do
		local entry = trove[i]
		if
			entry.kind == "networkHandler"
			and (entry :: TroveEntryNetworkHandler).name == namespacedName
			and (entry :: TroveEntryNetworkHandler).callback == callback
		then
			table.remove(trove, i)
			return
		end
	end
end

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

--- Creates a new PluginSandbox for a single plugin.
--- @param deps SandboxDeps — all core module references plus plugin-specific callbacks.
function PluginSandbox.new(deps: SandboxDeps): PluginSandboxAPI
	assert(type(deps) == "table", "[PluginSandbox] deps must be a table.")
	assert(type(deps.PluginName) == "string" and #deps.PluginName > 0, "[PluginSandbox] deps.PluginName must be a non-empty string.")
	assert(deps.Network ~= nil, "[PluginSandbox] deps.Network is required.")
	assert(deps.State ~= nil, "[PluginSandbox] deps.State is required.")
	assert(deps.Signal ~= nil, "[PluginSandbox] deps.Signal is required.")
	assert(deps.ComponentService ~= nil, "[PluginSandbox] deps.ComponentService is required.")
	assert(deps.Async ~= nil, "[PluginSandbox] deps.Async is required.")
	assert(type(deps.GetPluginAPI) == "function", "[PluginSandbox] deps.GetPluginAPI must be a function.")
	assert(type(deps.EmitBusEvent) == "function", "[PluginSandbox] deps.EmitBusEvent must be a function.")
	assert(type(deps.OnBusEvent) == "function", "[PluginSandbox] deps.OnBusEvent must be a function.")

	local self = setmetatable({
		PluginName = deps.PluginName,
		_deps = deps,
		_trove = {} :: { TroveEntry },
	}, PluginSandbox)

	return (self :: any) :: PluginSandboxAPI
end

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

function PluginSandbox:GetState(key: string, player: Player?): any
	return self._deps.State:Get(key, player)
end

function PluginSandbox:SetState(key: string, value: any)
	if not self._deps.IsServer then
		self:Warn("SetState is a server-only method.")
		return
	end
	self._deps.State:Set(key, value)
end

function PluginSandbox:SetPlayerState(player: Player, key: string, value: any)
	if not self._deps.IsServer then
		self:Warn("SetPlayerState is a server-only method.")
		return
	end
	self._deps.State:SetForPlayer(player, key, value)
end

function PluginSandbox:SubscribeState(key: string, callback: (value: any) -> ()): UnsubscribeFn
	local unsubscribe = self._deps.State:Subscribe(key, callback)
	local entry: TroveEntryStateSubscription = {
		kind = "stateSubscription",
		unsubscribe = unsubscribe,
	}
	track(self, entry)
	return unsubscribe
end

-- ---------------------------------------------------------------------------
-- Network (namespaced)
-- ---------------------------------------------------------------------------

function PluginSandbox:OnNetworkEvent(name: string, callback: Callback)
	assert(type(name) == "string" and #name > 0, "[PluginSandbox] OnNetworkEvent: name must be a non-empty string.")
	assert(type(callback) == "function", "[PluginSandbox] OnNetworkEvent: callback must be a function.")

	local namespacedName = ns(self.PluginName, name)
	self._deps.Network.Register(namespacedName, callback)

	local entry: TroveEntryNetworkHandler = {
		kind = "networkHandler",
		name = namespacedName,
		callback = callback,
	}
	track(self, entry)
end

function PluginSandbox:OffNetworkEvent(name: string, callback: Callback)
	assert(type(name) == "string" and #name > 0, "[PluginSandbox] OffNetworkEvent: name must be a non-empty string.")
	assert(type(callback) == "function", "[PluginSandbox] OffNetworkEvent: callback must be a function.")

	local namespacedName = ns(self.PluginName, name)
	self._deps.Network.Unregister(namespacedName, callback)
	untrackNetworkHandler(self, namespacedName, callback)
end

function PluginSandbox:FireClient(player: Player, name: string, ...: any)
	if not self._deps.IsServer then
		self:Warn("FireClient is a server-only method.")
		return
	end
	local fireClient = self._deps.Network.FireClient
	if fireClient then
		fireClient(player, ns(self.PluginName, name), ...)
	else
		self:Warn("FireClient is not available (Network not initialized as server).")
	end
end

function PluginSandbox:FireAllClients(name: string, ...: any)
	if not self._deps.IsServer then
		self:Warn("FireAllClients is a server-only method.")
		return
	end
	local fireAllClients = self._deps.Network.FireAllClients
	if fireAllClients then
		fireAllClients(ns(self.PluginName, name), ...)
	else
		self:Warn("FireAllClients is not available (Network not initialized as server).")
	end
end

function PluginSandbox:FireServer(name: string, ...: any)
	if self._deps.IsServer then
		self:Warn("FireServer is a client-only method.")
		return
	end
	local fireServer = self._deps.Network.FireServer
	if fireServer then
		fireServer(ns(self.PluginName, name), ...)
	else
		self:Warn("FireServer is not available (Network not initialized as client).")
	end
end

-- ---------------------------------------------------------------------------
-- Network (core escape hatch — raw event name, no namespacing)
-- ---------------------------------------------------------------------------

--- Registers a handler on a raw core network event name.
--- WARNING: Bypasses plugin namespacing. Use only for intentional core integration.
function PluginSandbox:OnCoreEvent(name: string, callback: Callback)
	assert(type(name) == "string" and #name > 0, "[PluginSandbox] OnCoreEvent: name must be a non-empty string.")
	assert(type(callback) == "function", "[PluginSandbox] OnCoreEvent: callback must be a function.")

	self._deps.Network.Register(name, callback)

	local entry: TroveEntryNetworkHandler = {
		kind = "networkHandler",
		name = name,
		callback = callback,
	}
	track(self, entry)
end

-- ---------------------------------------------------------------------------
-- Signals
-- ---------------------------------------------------------------------------

function PluginSandbox:CreateSignal(): SignalInstance
	local signal = self._deps.Signal.new()
	local entry: TroveEntrySignal = {
		kind = "signal",
		signal = signal,
	}
	track(self, entry)
	return signal
end

-- ---------------------------------------------------------------------------
-- Components
-- ---------------------------------------------------------------------------

function PluginSandbox:RegisterComponent(tag: string, componentClass: ComponentClass)
	assert(type(tag) == "string" and #tag > 0, "[PluginSandbox] RegisterComponent: tag must be a non-empty string.")
	assert(type(componentClass) == "table", "[PluginSandbox] RegisterComponent: componentClass must be a table.")
	assert(type(componentClass.new) == "function", "[PluginSandbox] RegisterComponent: componentClass must have a 'new' constructor.")

	-- ComponentService._start auto-discovers from a folder; here we register
	-- a single tag directly via the CollectionService listeners on the CS itself.
	-- We call an internal _registerTag helper if available, or warn if not.
	-- This allows ComponentService to remain the source of truth.
	local cs = self._deps.ComponentService :: any
	if type(cs._registerTagManually) == "function" then
		cs:_registerTagManually(tag, componentClass)
	else
		-- Fallback: warn rather than crash — ComponentService may not yet expose
		-- this method until the integration PR lands.
		self:Warn(
			string.format(
				"RegisterComponent('%s'): ComponentService does not expose '_registerTagManually'. "
					.. "Register this tag via config.ComponentsFolder instead.",
				tag
			)
		)
		return
	end

	local entry: TroveEntryComponentTag = {
		kind = "componentTag",
		tagName = tag,
	}
	track(self, entry)
end

-- ---------------------------------------------------------------------------
-- Event Bus (inter-plugin)
-- ---------------------------------------------------------------------------

function PluginSandbox:Emit(eventName: string, ...: any)
	assert(type(eventName) == "string" and #eventName > 0, "[PluginSandbox] Emit: eventName must be a non-empty string.")
	self._deps.EmitBusEvent(eventName, ...)
end

function PluginSandbox:On(eventName: string, callback: Callback): UnsubscribeFn
	assert(type(eventName) == "string" and #eventName > 0, "[PluginSandbox] On: eventName must be a non-empty string.")
	assert(type(callback) == "function", "[PluginSandbox] On: callback must be a function.")

	local unsubscribe = self._deps.OnBusEvent(eventName, callback)
	local entry: TroveEntryEventBus = {
		kind = "eventBus",
		unsubscribe = unsubscribe,
	}
	track(self, entry)
	return unsubscribe
end

-- ---------------------------------------------------------------------------
-- Logging
-- ---------------------------------------------------------------------------

function PluginSandbox:Log(message: string)
	print(string.format("🔌 [Plugin:%s] %s", self.PluginName, tostring(message)))
end

function PluginSandbox:Warn(message: string)
	warn(string.format("🔌 [Plugin:%s] %s", self.PluginName, tostring(message)))
end

-- ---------------------------------------------------------------------------
-- Inter-plugin API access
-- ---------------------------------------------------------------------------

function PluginSandbox:GetPluginAPI(pluginName: string): { [string]: any }?
	assert(type(pluginName) == "string" and #pluginName > 0, "[PluginSandbox] GetPluginAPI: pluginName must be a non-empty string.")
	return self._deps.GetPluginAPI(pluginName)
end

-- ---------------------------------------------------------------------------
-- Async
-- ---------------------------------------------------------------------------

function PluginSandbox:RunAsync(fn: Callback, timeout: number, ...: any): any
	assert(type(fn) == "function", "[PluginSandbox] RunAsync: fn must be a function.")
	assert(type(timeout) == "number" and timeout > 0, "[PluginSandbox] RunAsync: timeout must be a positive number.")

	local args = { ... }
	return self._deps.Async.Run(function()
		return fn(table.unpack(args))
	end, timeout)
end

-- ---------------------------------------------------------------------------
-- Trove: CleanupAll
-- Called by PluginManager on crash — NOT a public plugin API.
-- ---------------------------------------------------------------------------

--- Force-cleans every resource tracked by this sandbox.
--- Called by PluginManager on plugin error. Does NOT call Stop/Destroy.
function PluginSandbox:CleanupAll()
	local trove = self._trove :: { TroveEntry }

	for i = #trove, 1, -1 do
		local entry = trove[i]
		local ok, err = pcall(function()
			if entry.kind == "signal" then
				local e = entry :: TroveEntrySignal
				e.signal:Destroy()

			elseif entry.kind == "networkHandler" then
				local e = entry :: TroveEntryNetworkHandler
				self._deps.Network.Unregister(e.name, e.callback)

			elseif entry.kind == "stateSubscription" then
				local e = entry :: TroveEntryStateSubscription
				e.unsubscribe()

			elseif entry.kind == "eventBus" then
				local e = entry :: TroveEntryEventBus
				e.unsubscribe()

			elseif entry.kind == "componentTag" then
				local e = entry :: TroveEntryComponentTag
				local cs = self._deps.ComponentService :: any
				if type(cs.UnregisterTag) == "function" then
					cs:UnregisterTag(e.tagName)
				end
			end
		end)

		if not ok then
			warn(string.format(
				"🔌 [Plugin:%s] CleanupAll error (entry.kind=%s): %s",
				self.PluginName,
				tostring(entry.kind),
				tostring(err)
			))
		end
	end

	table.clear(self._trove)
end

-- ---------------------------------------------------------------------------

return PluginSandbox
