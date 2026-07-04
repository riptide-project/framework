--!strict
-- Riptide/shared/PluginManager.lua
-- Orchestrator for the plugin system.
-- Responsibilities:
--   • Hybrid loading  : local folder discovery + pre-required external tables
--   • Validation      : unified Duck-Typing pipeline
--   • Dep resolution  : Kahn's algorithm topological sort with cycle detection
--   • Lifecycle       : OnRegister → Init (sync) → Start readiness → Stop → Destroy
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

local EventBusModule: any
do
	local ok, result = pcall(function()
		return require(script.Parent.Utilities.EventBus)
	end)
	if ok then
		EventBusModule = result
	else
		EventBusModule = require("./Utilities/EventBus")
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

type PluginSandboxAPI = {
	PluginName: string,
	CleanupAll: (self: PluginSandboxAPI) -> (),
	[string]: unknown,
}

-- ---------------------------------------------------------------------------
-- Public exported types
-- ---------------------------------------------------------------------------

export type PluginPublicAPI = { [string]: unknown }

export type PluginDescriptor<TPublicAPI> = {
	Name: string,
	Version: string,
	Description: string?,
	Author: string?,
	Side: "Server" | "Client" | "Shared",
	Dependencies: { string }?,
	StartTimeout: number?,
	PublicAPI: TPublicAPI?,
}

export type PluginHooks<TSandbox> = {
	Init: (self: PluginHooks<TSandbox>, sandbox: TSandbox) -> (),
	Start: (self: PluginHooks<TSandbox>, sandbox: TSandbox) -> (),
	OnRegister: ((self: PluginHooks<TSandbox>, sandbox: TSandbox) -> ())?,
	Stop: ((self: PluginHooks<TSandbox>, sandbox: TSandbox) -> ())?,
	Destroy: ((self: PluginHooks<TSandbox>, sandbox: TSandbox) -> ())?,
	OnPlayerAdded: ((self: PluginHooks<TSandbox>, sandbox: TSandbox, player: Player) -> ())?,
	OnPlayerRemoving: ((self: PluginHooks<TSandbox>, sandbox: TSandbox, player: Player) -> ())?,
	[string]: any,
}

export type PluginDefinition<TPublicAPI> = {
	Descriptor: PluginDescriptor<TPublicAPI>,
	Hooks: PluginHooks<PluginSandboxAPI>,
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
	descriptor: PluginDescriptor<PluginPublicAPI>,
	hooks: PluginHooks<PluginSandboxAPI>,
	status: PluginStatus,
	sandbox: PluginSandboxAPI,
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
PluginManager._loadOrder = {} :: { string } -- final sorted order
PluginManager._eventBus = EventBusModule.new("🔌 [PluginEventBus]") :: any
PluginManager._deps = nil :: PluginManagerDeps?
PluginManager._isStarted = false
PluginManager._generation = 0
PluginManager._knownPlayers = {} :: { Player }

local DEFAULT_PLUGIN_START_TIMEOUT = 5

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
	self._eventBus = EventBusModule.new("🔌 [PluginEventBus]")
	self._knownPlayers = {}
	self._isStarted = false
	self._generation += 1
end

-- ---------------------------------------------------------------------------
-- Section 2: Event Bus (used internally and exposed via sandbox closures)
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Section 3: Sandbox factory — one sandbox per plugin
-- ---------------------------------------------------------------------------

local function createSandbox(self: any, pluginName: string): PluginSandboxAPI
	local deps = self._deps :: PluginManagerDeps
	return PluginSandboxModule.new({
		Network = deps.Network,
		State = deps.State,
		Signal = deps.Signal,
		ComponentService = deps.ComponentService,
		IsServer = deps.IsServer,
		Async = deps.Async,
		PluginName = pluginName,
		GetPluginAPI = function(name: string): PluginPublicAPI?
			local entry: PluginEntry? = self._plugins[name]
			if entry and entry.status ~= "Errored" then
				return entry.descriptor.PublicAPI
			end
			return nil
		end,
		EmitBusEvent = function(eventName: string, ...: any)
			self._eventBus:Emit(eventName, ...)
		end,
		OnBusEvent = function(eventName: string, callback: Callback): UnsubscribeFn
			return self._eventBus:On(eventName, callback)
		end,
		OnceBusEvent = function(eventName: string, callback: Callback): UnsubscribeFn
			return self._eventBus:Once(eventName, callback)
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
): (PluginDescriptor<PluginPublicAPI>?, PluginHooks<PluginSandboxAPI>?, string?)
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
		return nil,
			nil,
			string.format(
				"'%s': Descriptor.Side must be 'Server', 'Client', or 'Shared'. Got: %s",
				name,
				tostring(side)
			)
	end

	-- 6. Side filter — silent skip when side doesn't match runtime
	if side == "Server" and not isServer then
		return nil, nil, nil -- silent skip
	end
	if side == "Client" and isServer then
		return nil, nil, nil -- silent skip
	end

	-- 7. Hooks field
	local hooks = rawTable.Hooks
	if type(hooks) ~= "table" then
		return nil, nil, string.format("'%s': missing or invalid 'Hooks' table.", name)
	end

	-- 8. Optional readiness timeout
	if descriptor.StartTimeout ~= nil then
		if type(descriptor.StartTimeout) ~= "number" or descriptor.StartTimeout <= 0 then
			return nil, nil, string.format("'%s': Descriptor.StartTimeout must be a positive number.", name)
		end
	end

	-- 9. Required hooks
	if type(hooks.Init) ~= "function" then
		return nil, nil, string.format("'%s': Hooks.Init must be a function.", name)
	end
	if type(hooks.Start) ~= "function" then
		return nil, nil, string.format("'%s': Hooks.Start must be a function.", name)
	end

	return (descriptor :: any) :: PluginDescriptor<PluginPublicAPI>,
		(hooks :: any) :: PluginHooks<PluginSandboxAPI>,
		nil
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
	local dependents: { [string]: { string } } = {} -- dependents[B] = {A, C, ...}

	for name in pairs(plugins) do
		inDegree[name] = 0
		dependents[name] = {}
	end

	for name, entry in pairs(plugins) do
		local deps = entry.descriptor.Dependencies or {}
		for _, depName in ipairs(deps) do
			if plugins[depName] == nil then
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

local function findMissingDependencyBlocks(plugins: { [string]: PluginEntry }): { [string]: string }
	local blockedByDependency: { [string]: string } = {}
	local changed = true

	while changed do
		changed = false
		for name, entry in pairs(plugins) do
			if blockedByDependency[name] ~= nil then
				continue
			end

			for _, depName in ipairs(entry.descriptor.Dependencies or {}) do
				if plugins[depName] == nil or blockedByDependency[depName] ~= nil then
					blockedByDependency[name] = depName
					changed = true
					break
				end
			end
		end
	end

	return blockedByDependency
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
	warn(string.format("🔌 [Plugin:%s] ❌ Error in %s phase:\n%s", pluginName, phase, tostring(err)))
	-- Force-clean all tracked resources. Do NOT call Stop/Destroy.
	local ok, cleanErr = pcall(function()
		entry.sandbox:CleanupAll()
	end)
	if not ok then
		warn(string.format("🔌 [Plugin:%s] CleanupAll itself failed: %s", pluginName, tostring(cleanErr)))
	end
end

local function rememberPlayer(self: any, player: Player)
	for _, knownPlayer in ipairs(self._knownPlayers) do
		if knownPlayer == player then
			return
		end
	end
	table.insert(self._knownPlayers, player)
end

local function forgetPlayer(self: any, player: Player)
	for index, knownPlayer in ipairs(self._knownPlayers) do
		if knownPlayer == player then
			table.remove(self._knownPlayers, index)
			return
		end
	end
end

local function isCurrentEntry(self: any, pluginName: string, entry: PluginEntry, generation: number): boolean
	return self._generation == generation and self._plugins[pluginName] == entry
end

local function dispatchPlayerHook(
	self: any,
	entry: PluginEntry,
	pluginName: string,
	hookName: "OnPlayerAdded" | "OnPlayerRemoving",
	player: Player,
	generation: number
)
	local hook = entry.hooks[hookName]
	if type(hook) ~= "function" then
		return
	end

	task.spawn(function()
		if not isCurrentEntry(self, pluginName, entry, generation) or entry.status ~= "Running" then
			return
		end

		local ok, err = xpcall(hook, debug.traceback, entry.hooks, entry.sandbox, player)
		if not isCurrentEntry(self, pluginName, entry, generation) then
			return
		end
		if not ok then
			handleError(self, pluginName, hookName, tostring(err))
		end
	end)
end

local function getStartTimeout(entry: PluginEntry): number
	local timeout = entry.descriptor.StartTimeout
	if timeout == nil then
		return DEFAULT_PLUGIN_START_TIMEOUT
	end
	return timeout
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
				warn(string.format("🌊 [PluginManager] Failed to require '%s': %s", child.Name, tostring(value)))
			end
		end
	end
	return results
end

--- Core LoadPlugins implementation.
function PluginManager:LoadPlugins(pluginsFolders: (Folder | { Folder })?, externalPlugins: { { [string]: any } }?)
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
		local desc = descriptor :: PluginDescriptor<PluginPublicAPI>
		local hks = hooks :: PluginHooks<PluginSandboxAPI>
		local pluginName = desc.Name

		-- 7d. Duplicate check (both pending and already registered)
		if pending[pluginName] or self._plugins[pluginName] then
			warn(string.format("🌊 [PluginManager] Duplicate plugin name '%s' — skipping.", pluginName))
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

	-- 7e. Missing dependencies block the plugin before ordering.
	local missingDependencyBlocks = findMissingDependencyBlocks(pending)
	local blockedNames: { string } = {}
	for name in pairs(missingDependencyBlocks) do
		table.insert(blockedNames, name)
	end
	table.sort(blockedNames)

	for _, name in ipairs(blockedNames) do
		local missingDepName = missingDependencyBlocks[name]
		warn(
			string.format(
				"🌊 [PluginManager] Plugin '%s' depends on missing dependency '%s' and will not be loaded.",
				name,
				missingDepName
			)
		)

		local entry = pending[name]
		entry.status = "Errored"
		self._plugins[name] = entry
		pending[name] = nil
	end

	-- 7f. Dependency resolution (topological sort)
	local sorted, cycleNames = topoSort(pending)

	-- Mark cyclic plugins as Errored and drop them
	for _, name in ipairs(cycleNames) do
		warn(
			string.format("🌊 [PluginManager] Circular dependency detected — plugin '%s' will not be loaded.", name)
		)
		-- Register with Errored status so GetStatus() is informative
		local entry = pending[name]
		entry.status = "Errored"
		self._plugins[name] = entry
	end

	-- 7g. OnRegister phase (sequential, before Init)
	for _, name in ipairs(sorted) do
		local entry = pending[name]
		entry.status = "Validated"
		self._plugins[name] = entry
		table.insert(self._loadOrder, name)

		if type(entry.hooks.OnRegister) == "function" then
			local ok, err = xpcall(entry.hooks.OnRegister, debug.traceback, entry.hooks, entry.sandbox)
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

	print(
		string.format(
			"🌊 [PluginManager] Loaded %d plugin(s): %s",
			#self._loadOrder,
			table.concat(self._loadOrder, ", ")
		)
	)
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

		local ok, err = xpcall(entry.hooks.Init, debug.traceback, entry.hooks, entry.sandbox)

		if not ok then
			handleError(self, name, "Init", tostring(err))
		end
		-- Note: we intentionally leave status as "Initializing" on error;
		-- handleError sets it to "Errored".
		-- On success we leave it as "Initializing" — Running is set by StartPlugins.
	end
end

-- ---------------------------------------------------------------------------
-- Section 9: StartPlugins — readiness barrier
-- ---------------------------------------------------------------------------

function PluginManager:StartPlugins()
	assert(self._deps ~= nil, "[PluginManager] StartPlugins called before _init.")

	self._isStarted = true
	self._generation += 1
	local generation = self._generation

	for _, name in ipairs(self._loadOrder) do
		local entry = self._plugins[name]
		if not entry or entry.status == "Errored" then
			continue
		end

		if not isCurrentEntry(self, name, entry, generation) then
			continue
		end

		local waitingThread = coroutine.running()
		local completed = false
		local timedOut = false
		local waiting = false
		local startOk = false
		local startErr: any = nil
		local timeoutSeconds = getStartTimeout(entry)

		local function resumeWaitingThread()
			if waiting then
				task.spawn(waitingThread)
			end
		end

		task.spawn(function()
			local ok, err = xpcall(entry.hooks.Start, debug.traceback, entry.hooks, entry.sandbox)

			if completed then
				return
			end

			completed = true
			startOk = ok
			startErr = err
			resumeWaitingThread()
		end)

		task.delay(timeoutSeconds, function()
			if completed then
				return
			end

			completed = true
			timedOut = true
			resumeWaitingThread()
		end)

		if not completed then
			waiting = true
			coroutine.yield()
			waiting = false
		end

		if not isCurrentEntry(self, name, entry, generation) then
			continue
		end

		if timedOut then
			handleError(self, name, "Start", string.format("Start timed out after %.2f seconds.", timeoutSeconds))
		elseif not startOk then
			handleError(self, name, "Start", tostring(startErr))
		else
			entry.status = "Running"
			for _, player in ipairs(self._knownPlayers) do
				dispatchPlayerHook(self, entry, name, "OnPlayerAdded", player, generation)
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Section 10: StopPlugins — sequential, reverse order
-- ---------------------------------------------------------------------------

function PluginManager:StopPlugins()
	self._generation += 1
	self._isStarted = false

	local order = self._loadOrder
	for i = #order, 1, -1 do
		local name = order[i]
		local entry = self._plugins[name]
		if not entry or entry.status == "Errored" or entry.status == "Destroyed" then
			continue
		end

		entry.status = "Stopping"

		if type(entry.hooks.Stop) == "function" then
			local ok, err = xpcall(entry.hooks.Stop, debug.traceback, entry.hooks, entry.sandbox)
			if not ok then
				warn(string.format("🔌 [Plugin:%s] ❌ Error in Stop phase:\n%s", name, tostring(err)))
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Section 11: DestroyPlugins — sequential, reverse order; clears registry
-- ---------------------------------------------------------------------------

function PluginManager:DestroyPlugins()
	self._generation += 1

	local order = self._loadOrder
	for i = #order, 1, -1 do
		local name = order[i]
		local entry = self._plugins[name]
		if not entry or entry.status == "Destroyed" then
			continue
		end

		if entry.status ~= "Errored" and type(entry.hooks.Destroy) == "function" then
			local ok, err = xpcall(entry.hooks.Destroy, debug.traceback, entry.hooks, entry.sandbox)
			if not ok then
				warn(string.format("🔌 [Plugin:%s] ❌ Error in Destroy phase:\n%s", name, tostring(err)))
			end
		end

		-- Always force-clean sandbox resources, even if Destroy succeeded,
		-- in case the plugin forgot to release something.
		local ok, cleanErr = pcall(function()
			entry.sandbox:CleanupAll()
		end)
		if not ok then
			warn(string.format("🔌 [Plugin:%s] CleanupAll in Destroy failed: %s", name, tostring(cleanErr)))
		end

		entry.status = "Destroyed"
	end

	-- Clear event bus
	self._eventBus:Destroy()

	-- Clear registry
	table.clear(self._plugins)
	table.clear(self._loadOrder)
	table.clear(self._knownPlayers)
	self._isStarted = false
end

-- ---------------------------------------------------------------------------
-- Section 12: Player lifecycle forwarding
-- ---------------------------------------------------------------------------

function PluginManager:NotifyPlayerAdded(player: Player)
	rememberPlayer(self, player)

	local generation = self._generation
	for _, name in ipairs(self._loadOrder) do
		local entry = self._plugins[name]
		if not entry or entry.status ~= "Running" then
			continue
		end
		dispatchPlayerHook(self, entry, name, "OnPlayerAdded", player, generation)
	end
end

function PluginManager:NotifyPlayerRemoving(player: Player)
	forgetPlayer(self, player)

	local generation = self._generation
	-- Reverse order: last-registered plugins clean up first
	local order = self._loadOrder
	for i = #order, 1, -1 do
		local name = order[i]
		local entry = self._plugins[name]
		if not entry or entry.status ~= "Running" then
			continue
		end
		dispatchPlayerHook(self, entry, name, "OnPlayerRemoving", player, generation)
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
	return table.clone(self._plugins)
end

-- ---------------------------------------------------------------------------

return PluginManager
