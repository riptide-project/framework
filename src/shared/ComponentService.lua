--!strict
-- Riptide/ComponentService.lua
-- A unified manager for Roblox CollectionService component objects (Server & Client)
-- Supports Dependency Injection for testability.

export type ComponentClass = {
	new: (instance: Instance) -> any,
	Destroy: ((self: any) -> ())?,
}

export type ComponentServiceDeps = {
	CollectionService: any,
}

export type ComponentServiceAPI = {
	_registry: { [Instance]: { [string]: any } },
	_destroyingConns: { [Instance]: { [string]: RBXScriptConnection } },
	_tagListeners: { [string]: { added: RBXScriptConnection, removed: RBXScriptConnection } },
	_isStarted: boolean,
	_collectionService: any?,
	Get: (self: ComponentServiceAPI, instance: Instance, tagName: string?) -> any?,
	_init: (self: ComponentServiceAPI, deps: ComponentServiceDeps) -> (),
	_start: (self: ComponentServiceAPI, componentsFolder: Folder) -> (),
	_registerTagManually: (self: ComponentServiceAPI, tagName: string, componentClass: ComponentClass) -> boolean,
	_stop: (self: ComponentServiceAPI) -> (),
	UnregisterTag: (self: ComponentServiceAPI, tagName: string) -> (),
}

local ComponentService = {} :: ComponentServiceAPI

-- Strong tables: explicit cleanup is handled via Destroying connections and
-- CleanupComponent / UnregisterTag — no weak-key GC needed.
ComponentService._registry = {} :: { [Instance]: { [string]: any } }
ComponentService._destroyingConns = {} :: { [Instance]: { [string]: RBXScriptConnection } }
ComponentService._tagListeners = {} :: { [string]: { added: RBXScriptConnection, removed: RBXScriptConnection } }
ComponentService._isStarted = false
ComponentService._collectionService = nil

local CleanupComponent: (self: ComponentServiceAPI, instance: Instance, tagName: string) -> ()

function ComponentService:_init(deps: ComponentServiceDeps)
	self:_stop()

	local cleanupEntries = {}
	for instance, components in pairs(self._registry) do
		for tagName in pairs(components) do
			table.insert(cleanupEntries, {
				instance = instance,
				tagName = tagName,
			})
		end
	end
	for _, entry in ipairs(cleanupEntries) do
		CleanupComponent(self, entry.instance, entry.tagName)
	end

	table.clear(self._registry)
	table.clear(self._destroyingConns)
	table.clear(self._tagListeners)
	self._isStarted = false
	self._collectionService = deps.CollectionService
end

function ComponentService:Get(instance: Instance, tagName: string?): any?
	local components = self._registry[instance]
	if not components then
		return nil
	end

	if tagName then
		return components[tagName]
	end

	local selectedComponent = nil
	local count = 0

	for _, componentObj in pairs(components) do
		count += 1
		if count == 1 then
			selectedComponent = componentObj
		end
	end

	if count == 0 then
		return nil
	end

	if count == 1 then
		return selectedComponent
	end

	warn(
		string.format(
			"[ComponentService] Get(instance) is ambiguous (%d components found). Pass an explicit tagName.",
			count
		)
	)

	return nil
end

-- Internal cleanup helper
CleanupComponent = function(self: ComponentServiceAPI, instance: Instance, tagName: string)
	local components = self._registry[instance]
	local componentObj = if components then components[tagName] else nil
	if components then
		components[tagName] = nil
		if next(components) == nil then
			self._registry[instance] = nil
		end
	end
	-- Detach all ownership before user Destroy can re-register the same tag.
	local conns = self._destroyingConns[instance]
	if conns then
		local conn = conns[tagName]
		conns[tagName] = nil
		if next(conns) == nil then
			self._destroyingConns[instance] = nil
		end
		if conn then
			conn:Disconnect()
		end
	end
	if componentObj and type(componentObj.Destroy) == "function" then
		local ok, err = pcall(componentObj.Destroy, componentObj)
		if not ok then
			warn(string.format("[ComponentService] Destroy failed for '%s': %s", tagName, tostring(err)))
		end
	end
end

-- Internal setup helper for a new component instance
local function SetupComponent(
	self: ComponentServiceAPI,
	instance: Instance,
	tagName: string,
	ComponentClass: ComponentClass
)
	local componentsForInstance = self._registry[instance]
	local conns = self._destroyingConns[instance]
	if (componentsForInstance and componentsForInstance[tagName] ~= nil) or (conns and conns[tagName]) then
		return
	end

	-- This connection also acts as a construction token while new() yields.
	if not conns then
		conns = {}
		self._destroyingConns[instance] = conns
	end
	local connection = instance.Destroying:Connect(function()
		CleanupComponent(self, instance, tagName)
	end)
	assert(conns, "[ComponentService] Missing construction connections.")
	conns[tagName] = connection
	local success, result = pcall(ComponentClass.new, instance)
	local currentConns = self._destroyingConns[instance]
	local stillOwned = currentConns and currentConns[tagName] == connection

	if success and type(result) == "table" then
		if not stillOwned then
			if type(result.Destroy) == "function" then
				pcall(result.Destroy, result)
			end
			return
		end
		if not self._registry[instance] then
			self._registry[instance] = {}
		end
		self._registry[instance][tagName] = result
	else
		if stillOwned then
			CleanupComponent(self, instance, tagName)
		end
		warn(string.format("[ComponentService] Failed to initialize instance of '%s':\n%s", tagName, tostring(result)))
	end
end

local function getCollectionService(self: ComponentServiceAPI): any
	local cs = self._collectionService
	if not cs then
		cs = game:GetService("CollectionService")
		self._collectionService = cs
	end
	return cs
end

local function RegisterTag(self: ComponentServiceAPI, tagName: string, ComponentClass: ComponentClass): boolean
	if self._tagListeners[tagName] then
		warn(string.format("[ComponentService] Tag '%s' is already registered — skipping.", tagName))
		return false
	end

	local cs = getCollectionService(self)

	local addedConn = cs:GetInstanceAddedSignal(tagName):Connect(function(instance: Instance)
		SetupComponent(self, instance, tagName, ComponentClass)
	end)

	local removedConn = cs:GetInstanceRemovedSignal(tagName):Connect(function(instance: Instance)
		CleanupComponent(self, instance, tagName)
	end)

	local registration = {
		added = addedConn,
		removed = removedConn,
	}
	self._tagListeners[tagName] = registration

	for _, instance in ipairs(cs:GetTagged(tagName)) do
		-- A constructor can yield while this registration is removed or replaced.
		if self._tagListeners[tagName] ~= registration then
			return false
		end
		if cs:HasTag(instance, tagName) then
			SetupComponent(self, instance, tagName, ComponentClass)
		end
	end

	-- The last constructor can also invalidate ownership before returning.
	return self._tagListeners[tagName] == registration
end

function ComponentService:_start(componentsFolder: Folder)
	if self._isStarted then
		warn("[ComponentService] _start called more than once. Ignoring duplicate start.")
		return
	end

	self._isStarted = true

	for _, moduleScript in ipairs(componentsFolder:GetDescendants()) do
		if moduleScript:IsA("ModuleScript") then
			local tagName = moduleScript.Name
			local ok, ComponentClass = pcall(require, moduleScript)

			if not ok or type(ComponentClass) ~= "table" then
				warn(
					string.format(
						"[ComponentService] Failed to load component '%s':\n%s",
						tagName,
						tostring(ComponentClass)
					)
				)
				continue
			end

			if type(ComponentClass.new) ~= "function" then
				warn(
					string.format(
						"[ComponentService] Skipping component '%s': missing 'new(instance)' constructor.",
						tagName
					)
				)
				continue
			end

			RegisterTag(self, tagName, ComponentClass)
		end
	end
end

--- Registers a single tag and its ComponentClass directly, without a folder scan.
--- Used by PluginSandbox:RegisterComponent() so plugins don't need ComponentsFolder.
function ComponentService:_registerTagManually(tagName: string, ComponentClass: ComponentClass)
	return RegisterTag(self, tagName, ComponentClass)
end

function ComponentService:UnregisterTag(tagName: string)
	local listeners = self._tagListeners[tagName]
	if listeners then
		listeners.added:Disconnect()
		listeners.removed:Disconnect()
		self._tagListeners[tagName] = nil
	end

	local instancesToCleanup = {}
	for instance, conns in pairs(self._destroyingConns) do
		if conns[tagName] then
			table.insert(instancesToCleanup, instance)
		end
	end

	for _, instance in ipairs(instancesToCleanup) do
		CleanupComponent(self, instance, tagName)
	end
end

function ComponentService:_stop()
	for tagName in pairs(self._tagListeners) do
		self:UnregisterTag(tagName)
	end
	self._isStarted = false
end

return ComponentService
