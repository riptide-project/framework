--!strict
local isRoblox = typeof(game) ~= "nil"
local Env: any = {}

if isRoblox then
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	Env.frktest = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("frktest"))

	local RiptideFolder = ReplicatedStorage:WaitForChild("Riptide")
	local SharedFolder = RiptideFolder:WaitForChild("shared")
	local UtilitiesFolder = SharedFolder:WaitForChild("Utilities")

	Env.RiptideInit = require(RiptideFolder)

	-- Roblox DataModel paths mapped directly to Instances
	Env.RiptideShared = {
		Network = require(SharedFolder:WaitForChild("Network")),
		StateMachine = require(SharedFolder:WaitForChild("StateMachine")),
		StateReplication = require(SharedFolder:WaitForChild("StateReplication")),
		ComponentService = require(SharedFolder:WaitForChild("ComponentService")),
		ModuleLoader = require(SharedFolder:WaitForChild("ModuleLoader")),
		PlayerLifecycle = require(SharedFolder:WaitForChild("PlayerLifecycle")),
		PluginManager = require(SharedFolder:WaitForChild("PluginManager")),
		PluginSandbox = require(SharedFolder:WaitForChild("PluginSandbox")),
		Signal = require(UtilitiesFolder:WaitForChild("Signal")),
		Async = require(UtilitiesFolder:WaitForChild("Async")),
		EventBus = require(UtilitiesFolder:WaitForChild("EventBus")),
		Trove = require(UtilitiesFolder:WaitForChild("Trove")),
	}

	Env.Mocks = {
		MockRemoteEvent = require(script.Parent:WaitForChild("mocks"):WaitForChild("MockRemoteEvent")),
		MockRemoteFunction = require(script.Parent:WaitForChild("mocks"):WaitForChild("MockRemoteFunction")),
		MockPlayers = require(script.Parent:WaitForChild("mocks"):WaitForChild("MockPlayers")),
		MockCollectionService = require(script.Parent:WaitForChild("mocks"):WaitForChild("MockCollectionService")),
	}

	Env.task = task
else
	Env.frktest = require("../../luau_packages/frktest")
	Env.RiptideInit = nil -- init.lua requires game instance, tested via DataModel or mock

	-- Lune raw paths mapped to file requires
	Env.RiptideShared = {
		Network = require("../../src/shared/Network"),
		StateMachine = require("../../src/shared/StateMachine"),
		StateReplication = require("../../src/shared/StateReplication"),
		ComponentService = require("../../src/shared/ComponentService"),
		ModuleLoader = require("../../src/shared/ModuleLoader"),
		PlayerLifecycle = require("../../src/shared/PlayerLifecycle"),
		PluginManager = require("../../src/shared/PluginManager"),
		PluginSandbox = require("../../src/shared/PluginSandbox"),
		Signal = require("../../src/shared/Utilities/Signal"),
		Async = require("../../src/shared/Utilities/Async"),
		EventBus = require("../../src/shared/Utilities/EventBus"),
		Trove = require("../../src/shared/Utilities/Trove"),
	}

	Env.Mocks = {
		MockRemoteEvent = require("./mocks/MockRemoteEvent"),
		MockRemoteFunction = require("./mocks/MockRemoteFunction"),
		MockPlayers = require("./mocks/MockPlayers"),
		MockCollectionService = require("./mocks/MockCollectionService"),
	}

	local ok, luneTask = pcall(function()
		return require("@lune/task")
	end)
	Env.task = ok and luneTask or task
end

return Env
