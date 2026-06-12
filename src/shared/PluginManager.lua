--!strict
-- Riptide/shared/PluginManager.lua
-- Orchestrator for the plugin system.
-- Responsibilities:
--   • Hybrid loading  : local folder discovery + pre-required external tables
--   • Validation      : unified Duck-Typing pipeline
--   • Dep resolution  : Kahn's algorithm topological sort with cycle detection
--   • Lifecycle       : OnRegister → Init (sync) → Start (async) → Stop → Destroy
--   • Event Bus       : direct-call pub/sub with per-listener xpcall protection
--   • Crash recovery  : CleanupAll via sandbox Trove, no Stop/Destroy on crash

local task = task
if not task then
	task = require("@lune/task")
end

local PluginSandboxModule: any
do
	local ok, result = pcall(function()
		return require(script.Parent.PluginSandbox)
	end)
	if ok then
		PluginSandboxModule = result
	else
		PluginSandboxModule = require("./PluginSandbox")
	end
end

-- ---------------------------------------------------------------------------
-- Structural type aliases (mirrors PluginSandbox.lua — no direct coupling)
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
	new: () -> any,
}

type ComponentServiceLike = {
	UnregisterTag: (self: any, tagName: string) -> (),
	[string]: any,
}

-- ---------------------------------------------------------------------------
-- Public exported types
-- ---------------------------------------------------------------------------

export type PluginDescriptor = {
	Name: string,
	Version: string,
	Description: string?,
	Author: string?,
	Side: "Server" | "Client" | "Shared",
	Dependencies: { string }?,
	PublicAPI: { [string]: any }?,
}

export type PluginHooks = {
	Init: (self: PluginHooks, sandbox: any) -> (),
	Start: (self: PluginHooks, sandbox: any) -> (),
	OnRegister: ((self: PluginHooks, sandbox: any) -> ())?,
	Stop: ((self: PluginHooks, sandbox: any) -> ())?,
	Destroy: ((self: PluginHooks, sandbox: any) -> ())?,
	OnPlayerAdded: ((self: PluginHooks, sandbox: any, player: Player) -> ())?,
	OnPlayerRemoving: ((self: PluginHooks, sandbox: any, player: Player) -> ())?,
	[string]: any,
}

export type PluginStatus =
	"Discovered"
	| "Validated"
	| "Registered"
	| "Initializing"
	| "Running"
	| "Stopping"
	| "Destroyed"
	| "Errored"

export type PluginEntry = {
	descriptor: PluginDescriptor,
	hooks: PluginHooks,
	status: PluginStatus,
	sandbox: any, -- PluginSandboxAPI
}

export type PluginManagerDeps = {
	Network: NetworkLike,
	State: StateLike,
	Signal: SignalLike,
	ComponentService: ComponentServiceLike,
	IsServer: boolean,
	Async: any,
}

export type PluginManagerAPI = {
	_init: (self: PluginManagerAPI, deps: PluginManagerDeps) -> (),
	LoadPlugins: (
		self: PluginManagerAPI,
		pluginsFolders: (Folder | { Folder })?,
		externalPlugins: { { [string]: any } }?
	) -> (),
	InitPlugins: (self: PluginManagerAPI) -> (),
	StartPlugins: (self: PluginManagerAPI) -> (),
	StopPlugins: (self: PluginManagerAPI) -> (),
	DestroyPlugins: (self: PluginManagerAPI) -> (),
	GetPlugin: (self: PluginManagerAPI, name: string) -> PluginEntry?,
	GetStatus: (self: PluginManagerAPI, name: string) -> PluginStatus?,
	GetAllPlugins: (self: PluginManagerAPI) -> { [string]: PluginEntry },
	NotifyPlayerAdded: (self: PluginManagerAPI, player: Player) -> (),
	NotifyPlayerRemoving: (self: PluginManagerAPI, player: Player) -> (),
}

-- ---------------------------------------------------------------------------
-- PluginManager state
-- ---------------------------------------------------------------------------

local PluginManager = {} :: PluginManagerAPI
PluginManager._plugins = {} :: { [string]: PluginEntry }
PluginManager._loadOrder = {} :: { string }      -- final sorted order
PluginManager._eventBus = {} :: { [string]: { Callback } }
PluginManager._deps = nil :: PluginManagerDeps?
PluginManager._isStarted = false

-- ---------------------------------------------------------------------------
-- Section 1: _init
-- ---------------------------------------------------------------------------

function PluginManager:_init(deps: PluginManagerDeps)
	assert(type(deps) == "table", "[PluginManager] _init requires a deps table.")
	assert(deps.Network ~= nil, "[PluginManager] _init: deps.Network is required.")
	assert(deps.State ~= nil, "[PluginManager] _init: deps.State is required.")
	assert(deps.Signal ~= nil, "[PluginManager] _init: deps.Signal is required.")
	assert(deps.ComponentService ~= nil, "[PluginManager] _init: deps.ComponentService is required.")
	assert(deps.Async ~= nil, "[PluginManager] _init: deps.Async is required.")
	assert(type(deps.IsServer) == "boolean", "[PluginManager] _init: deps.IsServer must be a boolean.")

	self._deps = deps
	self._plugins = {}
	self._loadOrder = {}
	self._eventBus = {}
	self._isStarted = false
end

-- ---------------------------------------------------------------------------
-- Section 2: Event Bus (used internally and exposed via sandbox closures)
-- ---------------------------------------------------------------------------

--- Emits an event on the internal bus.
--- Direct-call pattern: each listener wrapped in its own xpcall.
--- No task.spawn to avoid scheduler pressure at high frequency.
local function emitBusEvent(self: any, eventName: string, ...: any)
	local listeners: { Callback }? = self._eventBus[eventName]
	if not listeners then
		return
	end
	-- Snapshot to handle mid-iteration unsubscribes safely
	local snapshot = table.clone(listeners)
	local args = { ... }
	for i = 1, #snapshot do
		local listener = snapshot[i]
		local ok, err = xpcall(function()
			listener(table.unpack(args))
		end, debug.traceback)
		if not ok then
			warn(string.format(
				"🔌 [PluginEventBus] Error in listener for '%s': %s",
				eventName,
				tostring(err)
			))
		end
	end
end

--- Subscribes to a bus event. Returns an unsubscribe function.
local function onBusEvent(self: any, eventName: string, callback: Callback): UnsubscribeFn
	if not self._eventBus[eventName] then
		self._eventBus[eventName] = {}
	end
	table.insert(self._eventBus[eventName], callback)

	return function()
		local listeners: { Callback }? = self._eventBus[eventName]
		if not listeners then
			return
		end
		for i = #listeners, 1, -1 do
			if listeners[i] == callback then
				table.remove(listeners, i)
				break
			end
		end
		if #listeners == 0 then
			self._eventBus[eventName] = nil
		end
	end
end

-- ---------------------------------------------------------------------------
-- Section 3: Sandbox factory — one sandbox per plugin
-- ---------------------------------------------------------------------------

local function createSandbox(self: any, pluginName: string): any
	local deps = self._deps :: PluginManagerDeps
	return PluginSandboxModule.new({
		Network = deps.Network,
		State = deps.State,
		Signal = deps.Signal,
		ComponentService = deps.ComponentService,
		IsServer = deps.IsServer,
		Async = deps.Async,
		PluginName = pluginName,
		GetPluginAPI = function(name: string): { [string]: any }?
			local entry: PluginEntry? = self._plugins[name]
			if entry and entry.status ~= "Errored" then
				return entry.descriptor.PublicAPI
			end
			return nil
		end,
		EmitBusEvent = function(eventName: string, ...: any)
			emitBusEvent(self, eventName, ...)
		end,
		OnBusEvent = function(eventName: string, callback: Callback): UnsubscribeFn
			return onBusEvent(self, eventName, callback)
		end,
	})
end

-- ---------------------------------------------------------------------------
-- Section 4: Validation pipeline
-- ---------------------------------------------------------------------------

--- Validates a raw required value as a PluginDefinition (Duck Typing).
--- Returns (descriptor, hooks) on success, or (nil, errorMessage) on failure.
local function validatePlugin(
	rawTable: { [string]: any },
	sourceName: string,
	isServer: boolean
): (PluginDescriptor?, PluginHooks?, string?)
	-- 1. Must be a table
	if type(rawTable) ~= "table" then
		return nil, nil, string.format("'%s': return value is not a table.", sourceName)
	end

	-- 2. Descriptor field
	local descriptor = rawTable.Descriptor
	if type(descriptor) ~= "table" then
		return nil, nil, string.format("'%s': missing or invalid 'Descriptor' table.", sourceName)
	end

	-- 3. Descriptor.Name
	local name = descriptor.Name
	if type(name) ~= "string" or #name == 0 then
		-- Fallback: use the source (ModuleScript) name
		name = sourceName
		descriptor.Name = name
	end

	-- 4. Descriptor.Version
	if type(descriptor.Version) ~= "string" or #descriptor.Version == 0 then
		return nil, nil, string.format("'%s': Descriptor.Version must be a non-empty string.", name)
	end

	-- 5. Descriptor.Side
	local side = descriptor.Side
	if side ~= "Server" and side ~= "Client" and side ~= "Shared" then
		return nil, nil, string.format(
			"'%s': Descriptor.Side must be 'Server', 'Client', or 'Shared'. Got: %s",
			name,
			tostring(side)
		)
	end

	-- 6. Side filter — silent skip when side doesn't match runtime
	if side == "Server" and not isServer then
		return nil, nil, nil  -- silent skip
	end
	if side == "Client" and isServer then
		return nil, nil, nil  -- silent skip
	end

	-- 7. Hooks field
	local hooks = rawTable.Hooks
	if type(hooks) ~= "table" then
		return nil, nil, string.format("'%s': missing or invalid 'Hooks' table.", name)
	end

	-- 8. Required hooks
	if type(hooks.Init) ~= "function" then
		return nil, nil, string.format("'%s': Hooks.Init must be a function.", name)
	end
	if type(hooks.Start) ~= "function" then
		return nil, nil, string.format("'%s': Hooks.Start must be a function.", name)
	end

	return (descriptor :: any) :: PluginDescriptor, (hooks :: any) :: PluginHooks, nil
end

-- ---------------------------------------------------------------------------
-- Section 5: Dependency resolution — Kahn's algorithm
-- ---------------------------------------------------------------------------

--- Returns a topologically sorted list of plugin names.
--- Plugins involved in a cycle are returned separately as cycleNames.
local function topoSort(plugins: { [string]: PluginEntry }): ({ string }, { string })
	-- Build adjacency and in-degree maps.
	-- Edge: A → B means A depends on B (B must come before A).
	local inDegree: { [string]: number } = {}
	local dependents: { [string]: { string } } = {}  -- dependents[B] = {A, C, ...}

	for name in pairs(plugins) do
		inDegree[name] = 0
		dependents[name] = {}
	end

	for name, entry in pairs(plugins) do
		local deps = entry.descriptor.Dependencies or {}
		for _, depName in ipairs(deps) do
			if plugins[depName] == nil then
				-- Dependency not registered — warn but don't block
				warn(string.format(
					"🌊 [PluginManager] Plugin '%s' depends on '%s' which is not registered. "
						.. "Dependency will be ignored.",
					name,
					depName
				))
				continue
			end
			-- depName must come before name → depName is a prerequisite of name
			-- In Kahn's terms: edge depName → name means depName must precede name
			-- in_degree[name] += 1, dependents[depName] adds name
			inDegree[name] = (inDegree[name] or 0) + 1
			table.insert(dependents[depName], name)
		end
	end

	-- Queue all nodes with no incoming edges (no unmet dependencies)
	local queue: { string } = {}
	for name, deg in pairs(inDegree) do
		if deg == 0 then
			table.insert(queue, name)
		end
	end

	-- Sort queue deterministically (alphabetical) for reproducible ordering
	table.sort(queue)

	local sorted: { string } = {}
	local head = 1

	while head <= #queue do
		local current = queue[head]
		head += 1
		table.insert(sorted, current)

		-- Reduce in-degree for all plugins that depend on current
		local deps = dependents[current]
		table.sort(deps) -- deterministic
		for _, dependent in ipairs(deps) do
			inDegree[dependent] -= 1
			if inDegree[dependent] == 0 then
				table.insert(queue, dependent)
			end
		end
	end

	-- Any plugin not in sorted is part of a cycle.
	-- Kahn's algorithm leaves cycles with inDegree > 0.
	local totalPlugins = 0
	for _ in pairs(plugins) do
		totalPlugins += 1
	end

	local cycleNames: { string } = {}
	if #sorted ~= totalPlugins then
		for name, deg in pairs(inDegree) do
			if deg > 0 then
				table.insert(cycleNames, name)
			end
		end
	end

	return sorted, cycleNames
end

-- ---------------------------------------------------------------------------
-- Section 6: Crash recovery helper
-- ---------------------------------------------------------------------------

local function handleError(self: any, pluginName: string, phase: string, err: string)
	local entry: PluginEntry? = self._plugins[pluginName]
	if not entry then
		return
	end
	entry.status = "Errored"
	warn(string.format(
		"🔌 [Plugin:%s] ❌ Error in %s phase:\n%s",
		pluginName,
		phase,
		tostring(err)
	))
	-- Force-clean all tracked resources. Do NOT call Stop/Destroy.
	local ok, cleanErr = pcall(function()
		entry.sandbox:CleanupAll()
	end)
	if not ok then
		warn(string.format(
			"🔌 [Plugin:%s] CleanupAll itself failed: %s",
			pluginName,
			tostring(cleanErr)
		))
	end
end

-- ---------------------------------------------------------------------------
-- Section 7: LoadPlugins
-- ---------------------------------------------------------------------------

--- Normalises the pluginsFolders argument to { Folder }.
local function normaliseFolders(input: (Folder | { Folder })?): { Folder }
	if input == nil then
		return {}
	end
	if typeof(input) == "Instance" then
		return { input :: Folder }
	end
	return input :: { Folder }
end

--- Discovers plugin tables from a single folder (GetChildren scan).
local function gatherFromFolder(folder: Folder): { { [string]: any } }
	local results: { { [string]: any } } = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			local ok, value = pcall(require, child :: ModuleScript)
			if ok and type(value) == "table" then
				-- Attach source name for better error messages
				local valueAny = value :: any
				valueAny._sourceName = child.Name
				table.insert(results, value :: { [string]: any })
			else
				warn(string.format(
					"🌊 [PluginManager] Failed to require '%s': %s",
					child.Name,
					tostring(value)
				))
			end
		end
	end
	return results
end

--- Core LoadPlugins implementation.
function PluginManager:LoadPlugins(
	pluginsFolders: (Folder | { Folder })?,
	externalPlugins: { { [string]: any } }?
)
	assert(self._deps ~= nil, "[PluginManager] LoadPlugins called before _init.")

	local deps = self._deps :: PluginManagerDeps
	local candidates: { { [string]: any } } = {}

	-- 7a. Local folder discovery
	for _, folder in ipairs(normaliseFolders(pluginsFolders)) do
		for _, raw in ipairs(gatherFromFolder(folder)) do
			table.insert(candidates, raw)
		end
	end

	-- 7b. External pre-required plugins
	if externalPlugins then
		for _, raw in ipairs(externalPlugins) do
			if type(raw) == "table" then
				table.insert(candidates, raw)
			else
				warn("[PluginManager] ExternalPlugins entry is not a table — skipping.")
			end
		end
	end

	-- 7c. Unified validation pipeline
	-- We collect validated plugins first, then check for duplicates.
	local pending: { [string]: PluginEntry } = {}

	for _, raw in ipairs(candidates) do
		local sourceName: string = tostring((raw :: any)._sourceName or "unknown")
		local descriptor, hooks, errMsg = validatePlugin(raw, sourceName, deps.IsServer)

		if descriptor == nil and hooks == nil and errMsg == nil then
			-- Silent side-filter skip
			continue
		end

		if errMsg then
			warn(string.format("🌊 [PluginManager] Validation failed — %s", errMsg))
			continue
		end

		-- descriptor and hooks are guaranteed non-nil here
		local desc = descriptor :: PluginDescriptor
		local hks = hooks :: PluginHooks
		local pluginName = desc.Name

		-- 7d. Duplicate check (both pending and already registered)
		if pending[pluginName] or self._plugins[pluginName] then
			warn(string.format(
				"🌊 [PluginManager] Duplicate plugin name '%s' — skipping.",
				pluginName
			))
			continue
		end

		local sandbox = createSandbox(self, pluginName)

		pending[pluginName] = {
			descriptor = desc,
			hooks = hks,
			status = "Discovered",
			sandbox = sandbox,
		}
	end

	-- 7e. Dependency resolution (topological sort)
	local sorted, cycleNames = topoSort(pending)

	-- Mark cyclic plugins as Errored and drop them
	for _, name in ipairs(cycleNames) do
		warn(string.format(
			"🌊 [PluginManager] Circular dependency detected — plugin '%s' will not be loaded.",
			name
		))
		-- Register with Errored status so GetStatus() is informative
		local entry = pending[name]
		entry.status = "Errored"
		self._plugins[name] = entry
	end

	-- 7f. OnRegister phase (sequential, before Init)
	for _, name in ipairs(sorted) do
		local entry = pending[name]
		entry.status = "Validated"
		self._plugins[name] = entry
		table.insert(self._loadOrder, name)

		if type(entry.hooks.OnRegister) == "function" then
			local ok, err = xpcall(
				entry.hooks.OnRegister,
				debug.traceback,
				entry.hooks,
				entry.sandbox
			)
			if not ok then
				handleError(self, name, "OnRegister", tostring(err))
				-- Remove from load order so it won't Init/Start
				self._loadOrder[#self._loadOrder] = nil
			else
				entry.status = "Registered"
			end
		else
			entry.status = "Registered"
		end
	end

	print(string.format(
		"🌊 [PluginManager] Loaded %d plugin(s): %s",
		#self._loadOrder,
		table.concat(self._loadOrder, ", ")
	))
end

-- ---------------------------------------------------------------------------
-- Section 8: InitPlugins — strictly synchronous, no yield allowed
-- ---------------------------------------------------------------------------

function PluginManager:InitPlugins()
	assert(self._deps ~= nil, "[PluginManager] InitPlugins called before _init.")

	for _, name in ipairs(self._loadOrder) do
		local entry = self._plugins[name]
		if not entry or entry.status == "Errored" then
			continue
		end

		entry.status = "Initializing"

		local ok, err = xpcall(
			entry.hooks.Init,
			debug.traceback,
			entry.hooks,
			entry.sandbox
		)

		if not ok then
			handleError(self, name, "Init", tostring(err))
		end
		-- Note: we intentionally leave status as "Initializing" on error;
		-- handleError sets it to "Errored".
		-- On success we leave it as "Initializing" — Running is set by StartPlugins.
	end
end

-- ---------------------------------------------------------------------------
-- Section 9: StartPlugins — async via task.spawn
-- ---------------------------------------------------------------------------

function PluginManager:StartPlugins()
	assert(self._deps ~= nil, "[PluginManager] StartPlugins called before _init.")

	self._isStarted = true

	for _, name in ipairs(self._loadOrder) do
		local entry = self._plugins[name]
		if not entry or entry.status == "Errored" then
			continue
		end

		-- Capture for closure
		local capturedEntry = entry
		local capturedName = name

		task.spawn(function()
			local ok, err = xpcall(
				capturedEntry.hooks.Start,
				debug.traceback,
				capturedEntry.hooks,
				capturedEntry.sandbox
			)
			if not ok then
				handleError(self, capturedName, "Start", tostring(err))
			else
				capturedEntry.status = "Running"
			end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Section 10: StopPlugins — sequential, reverse order
-- ---------------------------------------------------------------------------

function PluginManager:StopPlugins()
	local order = self._loadOrder
	for i = #order, 1, -1 do
		local name = order[i]
		local entry = self._plugins[name]
		if not entry or entry.status == "Errored" or entry.status == "Destroyed" then
			continue
		end

		entry.status = "Stopping"

		if type(entry.hooks.Stop) == "function" then
			local ok, err = xpcall(
				entry.hooks.Stop,
				debug.traceback,
				entry.hooks,
				entry.sandbox
			)
			if not ok then
				warn(string.format(
					"🔌 [Plugin:%s] ❌ Error in Stop phase:\n%s",
					name,
					tostring(err)
				))
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Section 11: DestroyPlugins — sequential, reverse order; clears registry
-- ---------------------------------------------------------------------------

function PluginManager:DestroyPlugins()
	local order = self._loadOrder
	for i = #order, 1, -1 do
		local name = order[i]
		local entry = self._plugins[name]
		if not entry or entry.status == "Destroyed" then
			continue
		end

		if type(entry.hooks.Destroy) == "function" then
			local ok, err = xpcall(
				entry.hooks.Destroy,
				debug.traceback,
				entry.hooks,
				entry.sandbox
			)
			if not ok then
				warn(string.format(
					"🔌 [Plugin:%s] ❌ Error in Destroy phase:\n%s",
					name,
					tostring(err)
				))
			end
		end

		-- Always force-clean sandbox resources, even if Destroy succeeded,
		-- in case the plugin forgot to release something.
		local ok, cleanErr = pcall(function()
			entry.sandbox:CleanupAll()
		end)
		if not ok then
			warn(string.format(
				"🔌 [Plugin:%s] CleanupAll in Destroy failed: %s",
				name,
				tostring(cleanErr)
			))
		end

		entry.status = "Destroyed"
	end

	-- Clear event bus
	table.clear(self._eventBus)

	-- Clear registry
	table.clear(self._plugins)
	table.clear(self._loadOrder)
	self._isStarted = false
end

-- ---------------------------------------------------------------------------
-- Section 12: Player lifecycle forwarding
-- ---------------------------------------------------------------------------

function PluginManager:NotifyPlayerAdded(player: Player)
	for _, name in ipairs(self._loadOrder) do
		local entry = self._plugins[name]
		if not entry or entry.status ~= "Running" then
			continue
		end
		if type(entry.hooks.OnPlayerAdded) ~= "function" then
			continue
		end

		local capturedEntry = entry
		local capturedName = name

		task.spawn(function()
			local ok, err = xpcall(
				capturedEntry.hooks.OnPlayerAdded,
				debug.traceback,
				capturedEntry.hooks,
				capturedEntry.sandbox,
				player
			)
			if not ok then
				warn(string.format(
					"🔌 [Plugin:%s] ❌ Error in OnPlayerAdded:\n%s",
					capturedName,
					tostring(err)
				))
			end
		end)
	end
end

function PluginManager:NotifyPlayerRemoving(player: Player)
	-- Reverse order: last-registered plugins clean up first
	local order = self._loadOrder
	for i = #order, 1, -1 do
		local name = order[i]
		local entry = self._plugins[name]
		if not entry or entry.status ~= "Running" then
			continue
		end
		if type(entry.hooks.OnPlayerRemoving) ~= "function" then
			continue
		end

		local capturedEntry = entry
		local capturedName = name

		task.spawn(function()
			local ok, err = xpcall(
				capturedEntry.hooks.OnPlayerRemoving,
				debug.traceback,
				capturedEntry.hooks,
				capturedEntry.sandbox,
				player
			)
			if not ok then
				warn(string.format(
					"🔌 [Plugin:%s] ❌ Error in OnPlayerRemoving:\n%s",
					capturedName,
					tostring(err)
				))
			end
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Section 13: Query API
-- ---------------------------------------------------------------------------

function PluginManager:GetPlugin(name: string): PluginEntry?
	return self._plugins[name]
end

function PluginManager:GetStatus(name: string): PluginStatus?
	local entry = self._plugins[name]
	return if entry then entry.status else nil
end

function PluginManager:GetAllPlugins(): { [string]: PluginEntry }
	-- Return a shallow copy so callers can't mutate the registry
	local copy: { [string]: PluginEntry } = {}
	for name, entry in pairs(self._plugins) do
		copy[name] = entry
	end
	return copy
end

-- ---------------------------------------------------------------------------

return PluginManager
