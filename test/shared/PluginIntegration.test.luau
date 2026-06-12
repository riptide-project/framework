--!strict
-- test/shared/PluginIntegration.test.luau
-- Integration tests for the PluginManager system.
-- Runs under both Lune (headless) and Roblox DataModel.
--
-- Test scenarios:
--   Suite 1 — HealthyPlugin lifecycle (Init → Start ordering, status transitions)
--   Suite 2 — Crash isolation (Start throws, status = Errored, framework survives)
--   Suite 3 — ExternalPlugins ingestion (pre-required table, no folder scanning)
--   Suite 4 — Dependency ordering (B depends on A → A.Init before B.Init)
--   Suite 5 — Cycle detection (A←→B → both Errored, rest of plugins load fine)
--   Suite 6 — Event Bus delivery and cleanup
--   Suite 7 — Side filtering (Client-side plugin skipped on server)

local Env = _G.TestEnv or require(script.Parent.TestEnv)
local task = Env.task

local frktest = Env.frktest
local test = frktest.test
local check = frktest.assert.check

-- ---------------------------------------------------------------------------
-- Resolve module paths (Roblox vs Lune)
-- ---------------------------------------------------------------------------

local isRoblox = typeof(game) ~= "nil"

local PluginManager: any
local PluginSandbox: any
local Signal: any
local Network: any
local MockRemoteEvent: any
local MockRemoteFunction: any
local Async: any

if isRoblox then
	local RS = game:GetService("ReplicatedStorage")
	local SharedFolder = RS:WaitForChild("Riptide"):WaitForChild("shared")
	PluginManager = require(SharedFolder:WaitForChild("PluginManager"))
	PluginSandbox = require(SharedFolder:WaitForChild("PluginSandbox"))
	Signal = require(SharedFolder:WaitForChild("Utilities"):WaitForChild("Signal"))
	Network = require(SharedFolder:WaitForChild("Network"))
	Async = require(SharedFolder:WaitForChild("Utilities"):WaitForChild("Async"))
	MockRemoteEvent = Env.Mocks.MockRemoteEvent
	MockRemoteFunction = Env.Mocks.MockRemoteFunction
else
	PluginManager = require("../../src/shared/PluginManager")
	PluginSandbox = require("../../src/shared/PluginSandbox")
	Signal = require("../../src/shared/Utilities/Signal")
	Network = require("../../src/shared/Network")
	Async = require("../../src/shared/Utilities/Async")
	MockRemoteEvent = require("./mocks/MockRemoteEvent")
	MockRemoteFunction = require("./mocks/MockRemoteFunction")
end

-- ---------------------------------------------------------------------------
-- Test helpers
-- ---------------------------------------------------------------------------

--- Returns a minimal Network mock that satisfies NetworkLike.
local function makeMockNetwork()
	local handlers: { [string]: { (...any) -> any } } = {}
	return {
		Register = function(name: string, cb: (...any) -> any)
			if not handlers[name] then
				handlers[name] = {}
			end
			table.insert(handlers[name], cb)
		end,
		Unregister = function(name: string, cb: (...any) -> any)
			local list = handlers[name]
			if not list then return end
			for i = #list, 1, -1 do
				if list[i] == cb then
					table.remove(list, i)
					break
				end
			end
		end,
		FireClient = nil :: ((...any) -> ())?,
		FireAllClients = nil :: ((...any) -> ())?,
		FireServer = nil :: ((...any) -> ())?,
		_handlers = handlers,
	}
end

--- Returns a minimal State mock.
local function makeMockState()
	local store: { [string]: any } = {}
	return {
		Get = function(_self: any, key: string, _player: any?): any
			return store[key]
		end,
		Set = function(_self: any, key: string, value: any)
			store[key] = value
		end,
		SetForPlayer = function(_self: any, _player: any, key: string, value: any)
			store[key] = value
		end,
		Subscribe = function(_self: any, _key: string, _cb: (any) -> ()): () -> ()
			return function() end
		end,
		_store = store,
	}
end

--- Returns a minimal ComponentService mock.
local function makeMockComponentService()
	local unregistered: { string } = {}
	return {
		UnregisterTag = function(_self: any, tag: string)
			table.insert(unregistered, tag)
		end,
		_registerTagManually = nil,  -- not exposed by default
		_unregistered = unregistered,
	}
end

--- Builds a fresh PluginManager with injected mocks.
--- Returns (manager, network, state, componentService).
local function buildManager()
	-- PluginManager is a singleton module — reset between tests by
	-- re-calling _init, which clears the registry.
	local net = makeMockNetwork()
	local state = makeMockState()
	local cs = makeMockComponentService()

	local mgr = PluginManager

	mgr:_init({
		Network = net,
		State = state,
		Signal = Signal,
		ComponentService = cs,
		IsServer = true,
		Async = Async,
	})

	return mgr, net, state, cs
end

--- Builds a minimal plugin definition table inline (no file IO).
local function makePlugin(name: string, side: string, hooks: { [string]: any }, deps: { string }?): { [string]: any }
	return {
		Descriptor = {
			Name = name,
			Version = "0.0.1",
			Side = side,
			Dependencies = deps or {},
		},
		Hooks = hooks,
	}
end

-- ---------------------------------------------------------------------------
-- Suite 1: HealthyPlugin lifecycle
-- ---------------------------------------------------------------------------

return function()
	test.suite("PluginIntegration: Healthy lifecycle", function()
		test.case("Init is called before Start, status transitions to Running", function()
			local mgr = buildManager()

			local log: { string } = {}

			local plugin = makePlugin("LCTest", "Server", {
				Init = function(_self, _sandbox)
					table.insert(log, "Init")
				end,
				Start = function(_self, _sandbox)
					table.insert(log, "Start")
				end,
			})

			mgr:LoadPlugins(nil, { plugin })
			check.equal(mgr:GetStatus("LCTest"), "Registered")

			mgr:InitPlugins()
			check.equal(log[1], "Init")
			-- Status after Init but before Start is "Initializing"
			check.equal(mgr:GetStatus("LCTest"), "Initializing")

			mgr:StartPlugins()
			-- Wait one frame for task.spawn to complete
			task.wait()
			check.equal(log[2], "Start")
			check.equal(mgr:GetStatus("LCTest"), "Running")
		end)

		test.case("sandbox.PluginName equals Descriptor.Name", function()
			local mgr = buildManager()
			local capturedName: string = ""

			local plugin = makePlugin("NameCheck", "Server", {
				Init = function(_self, sandbox)
					capturedName = sandbox.PluginName
				end,
				Start = function(_self, _sandbox) end,
			})

			mgr:LoadPlugins(nil, { plugin })
			mgr:InitPlugins()
			check.equal(capturedName, "NameCheck")
		end)

		test.case("OnRegister is called before Init", function()
			local mgr = buildManager()
			local log: { string } = {}

			local plugin = makePlugin("OrderTest", "Server", {
				OnRegister = function(_self, _sandbox)
					table.insert(log, "OnRegister")
				end,
				Init = function(_self, _sandbox)
					table.insert(log, "Init")
				end,
				Start = function(_self, _sandbox) end,
			})

			mgr:LoadPlugins(nil, { plugin })
			check.equal(log[1], "OnRegister")
			mgr:InitPlugins()
			check.equal(log[2], "Init")
		end)
	end)

	-- ---------------------------------------------------------------------------
	-- Suite 2: Crash isolation
	-- ---------------------------------------------------------------------------

	test.suite("PluginIntegration: Crash isolation", function()
		test.case("plugin that crashes in Start is marked Errored, framework survives", function()
			local mgr = buildManager()
			local survivorRan = false

			-- Crasher
			local crasher = makePlugin("Crasher", "Server", {
				Init = function(_self, _sandbox) end,
				Start = function(_self, _sandbox)
					error("intentional crash in Start")
				end,
			})

			-- Survivor — depends on nothing, should still run
			local survivor = makePlugin("Survivor", "Server", {
				Init = function(_self, _sandbox) end,
				Start = function(_self, _sandbox)
					survivorRan = true
				end,
			})

			mgr:LoadPlugins(nil, { crasher, survivor })
			mgr:InitPlugins()
			mgr:StartPlugins()
			task.wait()

			check.equal(mgr:GetStatus("Crasher"), "Errored")
			check.equal(survivorRan, true)
			check.equal(mgr:GetStatus("Survivor"), "Running")
		end)

		test.case("plugin that crashes in Init is marked Errored and skipped in Start", function()
			local mgr = buildManager()
			local startCalled = false

			local plugin = makePlugin("InitCrasher", "Server", {
				Init = function(_self, _sandbox)
					error("intentional crash in Init")
				end,
				Start = function(_self, _sandbox)
					startCalled = true
				end,
			})

			mgr:LoadPlugins(nil, { plugin })
			mgr:InitPlugins()
			check.equal(mgr:GetStatus("InitCrasher"), "Errored")

			mgr:StartPlugins()
			task.wait()
			-- Start must NOT have been called — plugin was already Errored
			check.equal(startCalled, false)
		end)

		test.case("crashed plugin's Trove cleans up network handlers", function()
			local mgr, net = buildManager()

			local namespacedName = "__plugin:TrackTest:Greet"

			local plugin = makePlugin("TrackTest", "Server", {
				Init = function(_self, sandbox)
					-- Register a handler → should be tracked in Trove
					sandbox:OnNetworkEvent("Greet", function() end)
					error("crash after registering handler")
				end,
				Start = function(_self, _sandbox) end,
			})

			mgr:LoadPlugins(nil, { plugin })
			mgr:InitPlugins()

			check.equal(mgr:GetStatus("TrackTest"), "Errored")
			-- After crash, Trove.CleanupAll must have unregistered the handler
			local handlers = (net :: any)._handlers[namespacedName]
			local count = 0
			if handlers then
				count = #handlers
			end
			check.equal(count, 0)
		end)
	end)

	-- ---------------------------------------------------------------------------
	-- Suite 3: ExternalPlugins ingestion
	-- ---------------------------------------------------------------------------

	test.suite("PluginIntegration: ExternalPlugins", function()
		test.case("pre-required external plugin is validated and loaded", function()
			local mgr = buildManager()
			local initRan = false

			local externalPlugin = makePlugin("ExternalOne", "Server", {
				Init = function(_self, _sandbox)
					initRan = true
				end,
				Start = function(_self, _sandbox) end,
			})

			-- Pass nil for folders, only external
			mgr:LoadPlugins(nil, { externalPlugin })
			mgr:InitPlugins()

			check.equal(initRan, true)
			check.equal(mgr:GetStatus("ExternalOne"), "Initializing")
		end)

		test.case("malformed external plugin is rejected with warning", function()
			local mgr = buildManager()

			-- Missing Hooks.Start → should fail validation
			local bad = {
				Descriptor = { Name = "Bad", Version = "1.0.0", Side = "Server" },
				Hooks = { Init = function() end }, -- no Start
			}

			mgr:LoadPlugins(nil, { bad })
			-- Should not be registered at all
			check.equal(mgr:GetStatus("Bad"), nil)
		end)

		test.case("client-side plugin is silently skipped on server (IsServer=true)", function()
			local mgr = buildManager()

			local clientPlugin = makePlugin("ClientOnly", "Client", {
				Init = function(_self, _sandbox) end,
				Start = function(_self, _sandbox) end,
			})

			mgr:LoadPlugins(nil, { clientPlugin })
			check.equal(mgr:GetStatus("ClientOnly"), nil)
		end)

		test.case("Shared plugin is accepted on server", function()
			local mgr = buildManager()

			local sharedPlugin = makePlugin("SharedPlugin", "Shared", {
				Init = function(_self, _sandbox) end,
				Start = function(_self, _sandbox) end,
			})

			mgr:LoadPlugins(nil, { sharedPlugin })
			check.truthy(mgr:GetStatus("SharedPlugin") ~= nil)
		end)
	end)

	-- ---------------------------------------------------------------------------
	-- Suite 4: Dependency ordering
	-- ---------------------------------------------------------------------------

	test.suite("PluginIntegration: Dependency ordering", function()
		test.case("B depends on A → A.Init runs before B.Init", function()
			local mgr = buildManager()
			local initOrder: { string } = {}

			local pluginA = makePlugin("DepA", "Server", {
				Init = function(_self, _sandbox)
					table.insert(initOrder, "DepA")
				end,
				Start = function(_self, _sandbox) end,
			})

			local pluginB = makePlugin("DepB", "Server", {
				Init = function(_self, _sandbox)
					table.insert(initOrder, "DepB")
				end,
				Start = function(_self, _sandbox) end,
			}, { "DepA" })  -- DepB depends on DepA

			-- Note: LoadPlugins order doesn't matter — topo sort handles it
			mgr:LoadPlugins(nil, { pluginB, pluginA })
			mgr:InitPlugins()

			check.equal(initOrder[1], "DepA")
			check.equal(initOrder[2], "DepB")
		end)

		test.case("B can read A's PublicAPI during Init (dependency guaranteed initialized)", function()
			local mgr = buildManager()
			local apiValue: string? = nil

			local pluginA = makePlugin("ApiProvider", "Server", {
				Init = function(_self, _sandbox) end,
				Start = function(_self, _sandbox) end,
			})
			pluginA.Descriptor.PublicAPI = {
				GetValue = function(): string return "hello_from_A" end,
			}

			local pluginB = makePlugin("ApiConsumer", "Server", {
				Init = function(_self, sandbox)
					local api = sandbox:GetPluginAPI("ApiProvider")
					if api then
						apiValue = api.GetValue()
					end
				end,
				Start = function(_self, _sandbox) end,
			}, { "ApiProvider" })

			mgr:LoadPlugins(nil, { pluginA, pluginB })
			mgr:InitPlugins()

			check.equal(apiValue, "hello_from_A")
		end)
	end)

	-- ---------------------------------------------------------------------------
	-- Suite 5: Cycle detection
	-- ---------------------------------------------------------------------------

	test.suite("PluginIntegration: Cycle detection", function()
		test.case("circular dependency A←→B marks both Errored", function()
			local mgr = buildManager()

			local cycleA = makePlugin("CycleA", "Server", {
				Init = function(_self, _sandbox) end,
				Start = function(_self, _sandbox) end,
			}, { "CycleB" })

			local cycleB = makePlugin("CycleB", "Server", {
				Init = function(_self, _sandbox) end,
				Start = function(_self, _sandbox) end,
			}, { "CycleA" })

			mgr:LoadPlugins(nil, { cycleA, cycleB })

			check.equal(mgr:GetStatus("CycleA"), "Errored")
			check.equal(mgr:GetStatus("CycleB"), "Errored")
		end)

		test.case("non-cyclic plugin loads successfully alongside cyclic ones", function()
			local mgr = buildManager()
			local goodRan = false

			local cycleA = makePlugin("CA2", "Server", {
				Init = function(_self, _sandbox) end,
				Start = function(_self, _sandbox) end,
			}, { "CB2" })

			local cycleB = makePlugin("CB2", "Server", {
				Init = function(_self, _sandbox) end,
				Start = function(_self, _sandbox) end,
			}, { "CA2" })

			local good = makePlugin("GoodPlugin", "Server", {
				Init = function(_self, _sandbox)
					goodRan = true
				end,
				Start = function(_self, _sandbox) end,
			})

			mgr:LoadPlugins(nil, { cycleA, cycleB, good })
			mgr:InitPlugins()

			check.equal(mgr:GetStatus("CA2"), "Errored")
			check.equal(mgr:GetStatus("CB2"), "Errored")
			check.equal(goodRan, true)
		end)
	end)

	-- ---------------------------------------------------------------------------
	-- Suite 6: Event Bus
	-- ---------------------------------------------------------------------------

	test.suite("PluginIntegration: Event Bus", function()
		test.case("sandbox:Emit delivers payload to sandbox:On subscriber", function()
			local mgr = buildManager()
			local received: string? = nil

			local publisher = makePlugin("BusPub", "Server", {
				Init = function(_self, _sandbox) end,
				Start = function(_self, sandbox)
					sandbox:Emit("test:ping", "hello")
				end,
			})

			local subscriber = makePlugin("BusSub", "Server", {
				OnRegister = function(_self, sandbox)
					sandbox:On("test:ping", function(payload: string)
						received = payload
					end)
				end,
				Init = function(_self, _sandbox) end,
				Start = function(_self, _sandbox) end,
			})

			mgr:LoadPlugins(nil, { subscriber, publisher })
			mgr:InitPlugins()
			mgr:StartPlugins()
			task.wait()

			check.equal(received, "hello")
		end)

		test.case("failing bus listener does not prevent other listeners from firing", function()
			local mgr = buildManager()
			local goodListenerFired = false

			local emitter = makePlugin("BusEmitter", "Server", {
				Init = function(_self, _sandbox) end,
				Start = function(_self, sandbox)
					sandbox:Emit("resilience:test")
				end,
			})

			local badSub = makePlugin("BadSub", "Server", {
				OnRegister = function(_self, sandbox)
					sandbox:On("resilience:test", function()
						error("intentional bus listener crash")
					end)
				end,
				Init = function(_self, _sandbox) end,
				Start = function(_self, _sandbox) end,
			})

			local goodSub = makePlugin("GoodSub", "Server", {
				OnRegister = function(_self, sandbox)
					sandbox:On("resilience:test", function()
						goodListenerFired = true
					end)
				end,
				Init = function(_self, _sandbox) end,
				Start = function(_self, _sandbox) end,
			})

			mgr:LoadPlugins(nil, { badSub, goodSub, emitter })
			mgr:InitPlugins()
			mgr:StartPlugins()
			task.wait()

			check.equal(goodListenerFired, true)
		end)
	end)

	-- ---------------------------------------------------------------------------
	-- Suite 7: StopPlugins / DestroyPlugins
	-- ---------------------------------------------------------------------------

	test.suite("PluginIntegration: Stop and Destroy", function()
		test.case("StopPlugins calls Stop hook in reverse order", function()
			local mgr = buildManager()
			local stopOrder: { string } = {}

			local pluginA = makePlugin("StopA", "Server", {
				Init = function(_self, _sandbox) end,
				Start = function(_self, _sandbox) end,
				Stop = function(_self, _sandbox)
					table.insert(stopOrder, "StopA")
				end,
			})

			local pluginB = makePlugin("StopB", "Server", {
				Init = function(_self, _sandbox) end,
				Start = function(_self, _sandbox) end,
				Stop = function(_self, _sandbox)
					table.insert(stopOrder, "StopB")
				end,
			}, { "StopA" })  -- B loads after A (A is B's dependency)

			mgr:LoadPlugins(nil, { pluginA, pluginB })
			mgr:InitPlugins()
			mgr:StartPlugins()
			task.wait()

			mgr:StopPlugins()

			-- Reverse dependency order: B was added to loadOrder after A,
			-- so Stop should visit B first, then A.
			check.equal(stopOrder[1], "StopB")
			check.equal(stopOrder[2], "StopA")
		end)

		test.case("DestroyPlugins clears registry", function()
			local mgr = buildManager()

			local plugin = makePlugin("ToDestroy", "Server", {
				Init = function(_self, _sandbox) end,
				Start = function(_self, _sandbox) end,
			})

			mgr:LoadPlugins(nil, { plugin })
			mgr:InitPlugins()
			mgr:StartPlugins()
			task.wait()

			check.truthy(mgr:GetStatus("ToDestroy") ~= nil)

			mgr:StopPlugins()
			mgr:DestroyPlugins()

			check.equal(mgr:GetStatus("ToDestroy"), nil)
		end)
	end)
end
