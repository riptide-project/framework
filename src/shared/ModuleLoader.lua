--!strict
-- Riptide/shared/ModuleLoader.lua
-- Unified module loading logic for both Client and Server initializers.

local task = task
if not task then
	task = require("@lune/task")
end

local ModuleLoader = {}

type ModuleFolders = Folder | { Folder }

export type Config = {
	ModulesFolder: ModuleFolders,
	SharedModulesFolder: ModuleFolders?,
	ComponentsFolder: Folder?,
	PluginsFolder: (Folder | { Folder })?,
	ExternalPlugins: { { [string]: any } }?,
}

function ModuleLoader.GetCanonicalModuleId(modulesFolder: Folder, moduleScript: ModuleScript): string
	local parts = { moduleScript.Name }
	local current: Instance? = moduleScript.Parent

	while current and current ~= modulesFolder do
		table.insert(parts, 1, current.Name)
		current = current.Parent
	end

	if current ~= modulesFolder then
		return moduleScript.Name
	end

	return table.concat(parts, "/")
end

function ModuleLoader.NormalizeFolders(input: ModuleFolders?, fieldName: string): { Folder }
	if input == nil then
		return {}
	end

	if typeof(input) == "Instance" then
		local instanceInput = input :: Instance
		if instanceInput:IsA("Folder") then
			return { instanceInput }
		end

		error(string.format("[Riptide] %s must be a Folder or array of Folder values.", fieldName))
	end

	if type(input) ~= "table" then
		error(string.format("[Riptide] %s must be a Folder or array of Folder values.", fieldName))
	end

	local folders = {} :: { Folder }
	for i, folder in ipairs(input :: { any }) do
		if typeof(folder) ~= "Instance" or not (folder :: Instance):IsA("Folder") then
			error(string.format("[Riptide] %s[%d] must be a Folder.", fieldName, i))
		end
		table.insert(folders, folder :: Folder)
	end

	return folders
end

function ModuleLoader.LoadModules(
	folder: Folder,
	seenModuleScripts: { [ModuleScript]: boolean },
	riptide: any,
	loadedModules: { { name: string, module: any } },
	sideName: string
)
	for _, instance in ipairs(folder:GetDescendants()) do
		if instance:IsA("ModuleScript") then
			if seenModuleScripts[instance] then
				continue
			end
			seenModuleScripts[instance] = true

			local ok, module = xpcall(require, debug.traceback, instance)
			if ok and type(module) == "table" then
				local canonicalId = ModuleLoader.GetCanonicalModuleId(folder, instance)
				if riptide._modules[canonicalId] ~= nil then
					warn(
						string.format(
							"[%s] Duplicate canonical module id '%s'. Skipping '%s'.",
							sideName,
							canonicalId,
							instance:GetFullName()
						)
					)
					continue
				end

				riptide._modules[canonicalId] = module

				local aliasName = instance.Name
				if aliasName ~= canonicalId then
					local aliasState = riptide._moduleAliases[aliasName]
					if aliasState == nil then
						riptide._moduleAliases[aliasName] = canonicalId
					elseif aliasState ~= canonicalId and aliasState ~= false then
						riptide._moduleAliases[aliasName] = false
						warn(
							string.format(
								"[%s] Module alias conflict for '%s'. Use canonical module id (example: '%s').",
								sideName,
								aliasName,
								canonicalId
							)
						)
					end
				end

				table.insert(loadedModules, {
					name = canonicalId,
					module = module,
				})
			else
				warn("[" .. sideName .. "] Failed to load module: " .. instance.Name .. "\n" .. tostring(module))
			end
		end
	end
end

function ModuleLoader.Launch(sideName: string, riptideRef: any, config: Config)
	if not config or not config.ModulesFolder then
		error("[Riptide] " .. sideName .. "Initializer.Launch requires a config table with a ModulesFolder.")
	end

	if not riptideRef then
		error("[Riptide] " .. sideName .. " launcher missing Riptide reference.")
	end

	print("🌊 [Riptide] " .. sideName .. " Initialization Started...")

	local loadedModules = {} :: { { name: string, module: any } }

	-- 1. LOAD PHASE — discover and require all module scripts
	local seenModuleScripts = {} :: { [ModuleScript]: boolean }
	for _, sharedFolder in ipairs(ModuleLoader.NormalizeFolders(config.SharedModulesFolder, "SharedModulesFolder")) do
		ModuleLoader.LoadModules(sharedFolder, seenModuleScripts, riptideRef, loadedModules, sideName)
	end

	for _, modulesFolder in ipairs(ModuleLoader.NormalizeFolders(config.ModulesFolder, "ModulesFolder")) do
		ModuleLoader.LoadModules(modulesFolder, seenModuleScripts, riptideRef, loadedModules, sideName)
	end

	if config.ComponentsFolder then
		riptideRef.ComponentService:_start(config.ComponentsFolder)
	end

	-- 2. PLUGIN LOAD + INIT PHASE — runs BEFORE module Init so modules can call
	--    GetPluginAPI() / GetPlugin() safely inside their own Init hooks.
	--    Plugin Start is deferred until after Module Start (see step 4 below).
	local pluginManager: any = nil
	if config.PluginsFolder ~= nil or config.ExternalPlugins ~= nil then
		pluginManager = riptideRef.Plugins
		if pluginManager and type(pluginManager.LoadPlugins) == "function" then
			pluginManager:LoadPlugins(config.PluginsFolder, config.ExternalPlugins)
			pluginManager:InitPlugins()
		else
			warn("[Riptide] PluginsFolder/ExternalPlugins provided but Riptide.Plugins is not initialised. Call _init first.")
			pluginManager = nil
		end
	end

	-- 3. MODULE INIT PHASE — synchronous, sequential.
	--    Plugin PublicAPIs are now available.
	for _, data in ipairs(loadedModules) do
		if type(data.module.Init) == "function" then
			local ok, err = xpcall(data.module.Init, debug.traceback, data.module, riptideRef)
			if not ok then
				warn(string.format("[%s] ❌ Error initializing %s:\n%s", sideName, data.name, tostring(err)))
			end
		end
	end

	-- 3.5. PLAYER LIFECYCLE START — runs AFTER module Init so self properties are populated.
	if sideName == "Server" and riptideRef.PlayerLifecycle and type(riptideRef.PlayerLifecycle.Start) == "function" then
		riptideRef.PlayerLifecycle:Start(loadedModules, riptideRef)
	end

	-- 4. MODULE START PHASE — async via task.spawn (non-blocking).
	for _, data in ipairs(loadedModules) do
		if type(data.module.Start) == "function" then
			task.spawn(function()
				local ok, err = xpcall(data.module.Start, debug.traceback, data.module, riptideRef)
				if not ok then
					warn(string.format("[%s] ❌ Error starting %s:\n%s", sideName, data.name, tostring(err)))
				end
			end)
		end
	end

	print("🌊 [Riptide] ✅ " .. sideName .. " Start Phase Dispatched.")

	-- 5. PLUGIN START PHASE — async, after all modules have been initialized.
	--    Plugins can now safely interact with fully-initialized game modules.
	if pluginManager then
		pluginManager:StartPlugins()
		print("🌊 [Riptide] ✅ " .. sideName .. " Plugin Phase Dispatched.")
	end
end

return ModuleLoader
