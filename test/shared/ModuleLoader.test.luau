--!strict
-- ModuleLoader Test Suite (frktest)
-- Tests the shared module loading logic extracted from Initializers.

local Env = _G.TestEnv or require(script.Parent.TestEnv)
local task = Env.task

local frktest = Env.frktest
local test = frktest.test
local check = frktest.assert.check

local ModuleLoader = Env.RiptideShared.ModuleLoader

return function()
	test.suite("ModuleLoader.GetCanonicalModuleId", function()
		-- We use plain table mocks since Lune does not have Roblox Instance hierarchy.
		-- GetCanonicalModuleId walks .Parent up to the folder, so we mock that chain.

		test.case("should return short name when module is direct child", function()
			local folder = { Name = "Modules" }
			local moduleScript = { Name = "PlayerService", Parent = folder }
			-- Since our mock doesn't use IsA/GetFullName, we test the path logic directly
			-- The function walks Parent until it finds modulesFolder.
			-- With mock: moduleScript.Parent == folder, so it returns "PlayerService"
			local id = ModuleLoader.GetCanonicalModuleId(folder :: any, moduleScript :: any)
			check.equal(id, "PlayerService")
		end)

		test.case("should return nested path for sub-folder modules", function()
			local folder = { Name = "Modules" }
			local subFolder = { Name = "Economy", Parent = folder }
			local moduleScript = { Name = "PlayerData", Parent = subFolder }

			local id = ModuleLoader.GetCanonicalModuleId(folder :: any, moduleScript :: any)
			check.equal(id, "Economy/PlayerData")
		end)

		test.case("should return short name when parent chain does not reach folder", function()
			local folder = { Name = "Modules" }
			local otherParent = { Name = "Other", Parent = nil }
			local moduleScript = { Name = "Orphan", Parent = otherParent }

			local id = ModuleLoader.GetCanonicalModuleId(folder :: any, moduleScript :: any)
			check.equal(id, "Orphan")
		end)
	end)

	test.suite("ModuleLoader.NormalizeFolders", function()
		test.case("should return empty table for nil input", function()
			local result = ModuleLoader.NormalizeFolders(nil, "TestField")
			check.equal(#result, 0)
		end)

		test.case("should error for non-Folder input", function()
			local ok = pcall(function()
				ModuleLoader.NormalizeFolders("not a folder" :: any, "TestField")
			end)
			check.equal(ok, false)
		end)
	end)

	test.suite("ModuleLoader.Launch", function()
		test.case("should run Init before Start", function()
			local lifecycle = {}
			local riptide = {
				_modules = {},
				_moduleAliases = {},
				ComponentService = {
					_start = function() end,
				},
			}

			local originalLoadModules = ModuleLoader.LoadModules
			local originalNormalizeFolders = ModuleLoader.NormalizeFolders
			ModuleLoader.NormalizeFolders = function(_input: any, fieldName: string)
				if fieldName == "ModulesFolder" then
					return { {} :: any }
				end
				return {}
			end
			ModuleLoader.LoadModules = function(
				_folder: Folder,
				_seenModuleScripts: { [ModuleScript]: boolean },
				_loadedRiptide: any,
				loadedModules: { { name: string, module: any } },
				_sideName: string
			)
				table.insert(loadedModules, {
					name = "Core/Foo",
					module = {
						Init = function(_self: any, _riptideRef: any)
							table.insert(lifecycle, "Init")
						end,
						Start = function(_self: any, _riptideRef: any)
							table.insert(lifecycle, "Start")
						end,
					},
				})
			end

			ModuleLoader.Launch("Server", riptide, {
				ModulesFolder = {} :: any,
			})

			task.wait()
			ModuleLoader.LoadModules = originalLoadModules
			ModuleLoader.NormalizeFolders = originalNormalizeFolders

			check.equal(lifecycle[1], "Init")
			check.equal(lifecycle[2], "Start")
		end)

		test.case("should call ComponentService start when ComponentsFolder is provided", function()
			local startedWith = nil
			local riptide = {
				_modules = {},
				_moduleAliases = {},
				ComponentService = {
					_start = function(_self: any, folder: any)
						startedWith = folder
					end,
				},
			}

			local componentsFolder = { Name = "Components" }

			local originalLoadModules = ModuleLoader.LoadModules
			local originalNormalizeFolders = ModuleLoader.NormalizeFolders
			ModuleLoader.NormalizeFolders = function()
				return {}
			end
			ModuleLoader.LoadModules = function() end

			ModuleLoader.Launch("Client", riptide, {
				ModulesFolder = {} :: any,
				ComponentsFolder = componentsFolder :: any,
			})

			ModuleLoader.LoadModules = originalLoadModules
			ModuleLoader.NormalizeFolders = originalNormalizeFolders
			check.equal(startedWith, componentsFolder)
		end)

		test.case("should inject side-specific API into module lifecycle hooks", function()
			local injectedInitRef = nil
			local injectedStartRef = nil
			local injectedPlayerLifecycleRef = nil
			local serverRef = {
				ComponentService = {
					_start = function() end,
				},
				PlayerLifecycle = {
					Start = function(_self: any, _modules: any, riptideRef: any)
						injectedPlayerLifecycleRef = riptideRef
					end,
				},
			}
			local riptide = {
				_modules = {},
				_moduleAliases = {},
				ComponentService = {
					_start = function() end,
				},
				Server = serverRef,
			}

			local originalLoadModules = ModuleLoader.LoadModules
			local originalNormalizeFolders = ModuleLoader.NormalizeFolders
			ModuleLoader.NormalizeFolders = function(_input: any, fieldName: string)
				if fieldName == "ModulesFolder" then
					return { {} :: any }
				end
				return {}
			end
			ModuleLoader.LoadModules = function(
				_folder: Folder,
				_seenModuleScripts: { [ModuleScript]: boolean },
				_loadedRiptide: any,
				loadedModules: { { name: string, module: any } },
				_sideName: string
			)
				table.insert(loadedModules, {
					name = "SideAwareService",
					module = {
						Init = function(_self: any, riptideRef: any)
							injectedInitRef = riptideRef
						end,
						Start = function(_self: any, riptideRef: any)
							injectedStartRef = riptideRef
						end,
					},
				})
			end

			ModuleLoader.Launch("Server", riptide, {
				ModulesFolder = {} :: any,
			})

			task.wait()
			ModuleLoader.LoadModules = originalLoadModules
			ModuleLoader.NormalizeFolders = originalNormalizeFolders

			check.equal(injectedInitRef, serverRef)
			check.equal(injectedStartRef, serverRef)
			check.equal(injectedPlayerLifecycleRef, serverRef)
		end)

		test.case("should load and start plugins before game module Start", function()
			local lifecycle = {}
			local riptide = {
				_modules = {},
				_moduleAliases = {},
				ComponentService = {
					_start = function(_self: any, _folder: any)
						table.insert(lifecycle, "ComponentStart")
					end,
				},
				PlayerLifecycle = {
					Start = function(_self: any, _modules: any, _riptideRef: any)
						table.insert(lifecycle, "PlayerLifecycleStart")
					end,
				},
				Plugins = {
					LoadPlugins = function(_self: any, _pluginsFolder: any, _externalPlugins: any)
						table.insert(lifecycle, "PluginLoad")
					end,
					InitPlugins = function(_self: any)
						table.insert(lifecycle, "PluginInit")
					end,
					StartPlugins = function(_self: any)
						table.insert(lifecycle, "PluginStart")
					end,
				},
			}

			local originalLoadModules = ModuleLoader.LoadModules
			local originalNormalizeFolders = ModuleLoader.NormalizeFolders
			ModuleLoader.NormalizeFolders = function(_input: any, fieldName: string)
				if fieldName == "ModulesFolder" then
					return { {} :: any }
				end
				return {}
			end
			ModuleLoader.LoadModules = function(
				_folder: Folder,
				_seenModuleScripts: { [ModuleScript]: boolean },
				_loadedRiptide: any,
				loadedModules: { { name: string, module: any } },
				_sideName: string
			)
				table.insert(lifecycle, "ModuleLoad")
				table.insert(loadedModules, {
					name = "GameService",
					module = {
						Init = function(_self: any, _riptideRef: any)
							table.insert(lifecycle, "ModuleInit")
						end,
						Start = function(_self: any, _riptideRef: any)
							table.insert(lifecycle, "ModuleStart")
						end,
					},
				})
			end

			ModuleLoader.Launch("Server", riptide, {
				ModulesFolder = {} :: any,
				ComponentsFolder = {} :: any,
				ExternalPlugins = {},
			})

			task.wait()
			ModuleLoader.LoadModules = originalLoadModules
			ModuleLoader.NormalizeFolders = originalNormalizeFolders

			check.equal(lifecycle[1], "PluginLoad")
			check.equal(lifecycle[2], "PluginInit")
			check.equal(lifecycle[3], "ModuleLoad")
			check.equal(lifecycle[4], "ComponentStart")
			check.equal(lifecycle[5], "ModuleInit")
			check.equal(lifecycle[6], "PluginStart")
			check.equal(lifecycle[7], "PlayerLifecycleStart")
			check.equal(lifecycle[8], "ModuleStart")
		end)
	end)
end
