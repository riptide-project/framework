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
	_registerTagManually: (self: ComponentServiceAPI, tagName: string, componentClass: ComponentClass) -> (),
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

function ComponentService:_init(deps: ComponentServiceDeps)
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
local function CleanupComponent(self: ComponentServiceAPI, instance: Instance, tagName: string)
	local components = self._registry[instance]
	if components then
		local componentObj = components[tagName]
		if componentObj then
			components[tagName] = nil
			if type(componentObj.Destroy) == "function" then
				pcall(componentObj.Destroy, componentObj)
			end
		end
		if next(components) == nil then
			self._registry[instance] = nil
		end
	end

	local conns = self._destroyingConns[instance]
	if conns then
		local conn = conns[tagName]
		if conn then
			conn:Disconnect()
			conns[tagName] = nil
		end
		if next(conns) == nil then
			self._destroyingConns[instance] = nil
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
	if componentsForInstance and componentsForInstance[tagName] ~= nil then
		return
	end

	local success, result = pcall(ComponentClass.new, instance)

	if success and result then
		if not self._registry[instance] then
			self._registry[instance] = {}
		end
		self._registry[instance][tagName] = result

		if not self._destroyingConns[instance] then
			self._destroyingConns[instance] = {}
		end
		self._destroyingConns[instance][tagName] = instance.Destroying:Connect(function()
			CleanupComponent(self, instance, tagName)
		end)
	else
		warn(string.format("[ComponentService] Failed to initialize instance of '%s':\n%s", tagName, tostring(result)))
	end
end

function ComponentService:_start(componentsFolder: Folder)
	if self._isStarted then
		warn("[ComponentService] _start called more than once. Ignoring duplicate start.")
		return
	end

	self._isStarted = true

	-- Use injected CollectionService, falling back to game:GetService for backward compat
	local cs = self._collectionService
	if not cs then
		cs = game:GetService("CollectionService")
		self._collectionService = cs
	end

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

			local addedConn = cs:GetInstanceAddedSignal(tagName):Connect(function(instance: Instance)
				SetupComponent(self, instance, tagName, ComponentClass)
			end)

			local removedConn = cs:GetInstanceRemovedSignal(tagName):Connect(function(instance: Instance)
				CleanupComponent(self, instance, tagName)
			end)

			self._tagListeners[tagName] = {
				added = addedConn,
				removed = removedConn,
			}

			for _, instance in ipairs(cs:GetTagged(tagName)) do
				SetupComponent(self, instance, tagName, ComponentClass)
			end
		end
	end
end

--- Registers a single tag and its ComponentClass directly, without a folder scan.
--- Used by PluginSandbox:RegisterComponent() so plugins don't need ComponentsFolder.
function ComponentService:_registerTagManually(tagName: string, ComponentClass: ComponentClass)
	if self._tagListeners[tagName] then
		warn(string.format("[ComponentService] Tag '%s' is already registered — skipping.", tagName))
		return
	end

	local cs = self._collectionService
	if not cs then
		cs = game:GetService("CollectionService")
		self._collectionService = cs
	end

	local addedConn = cs:GetInstanceAddedSignal(tagName):Connect(function(instance: Instance)
		SetupComponent(self, instance, tagName, ComponentClass)
	end)

	local removedConn = cs:GetInstanceRemovedSignal(tagName):Connect(function(instance: Instance)
		CleanupComponent(self, instance, tagName)
	end)

	self._tagListeners[tagName] = {
		added = addedConn,
		removed = removedConn,
	}

	for _, instance in ipairs(cs:GetTagged(tagName)) do
		SetupComponent(self, instance, tagName, ComponentClass)
	end
end

function ComponentService:UnregisterTag(tagName: string)
	local listeners = self._tagListeners[tagName]
	if listeners then
		listeners.added:Disconnect()
		listeners.removed:Disconnect()
		self._tagListeners[tagName] = nil
	end

	for instance, components in pairs(self._registry) do
		if components[tagName] then
			CleanupComponent(self, instance, tagName)
		end
	end
end

function ComponentService:_stop()
	for tagName in pairs(self._tagListeners) do
		self:UnregisterTag(tagName)
	end
	self._isStarted = false
end

return ComponentService
