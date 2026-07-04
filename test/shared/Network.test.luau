--!strict
-- Network Test Suite (frktest)
-- Updated for Riptide v0.9.1:
--   • FunctionDispatcher removed from NetworkDeps
--   • InvokeClient / InvokeServer removed
--   • Middleware signature: (player?, funcName, args: {any}) -> boolean?
--   • Dispatch is synchronous — task.wait() after Fire is no longer required,
--     but kept where MockRemoteEvent fires deferred (implementation detail).

local Env = _G.TestEnv or require(script.Parent.TestEnv)
local task = Env.task

local frktest = Env.frktest
local test = frktest.test
local check = frktest.assert.check

local MockRemoteEvent = Env.Mocks.MockRemoteEvent
local Network = Env.RiptideShared.Network

return function()
	test.suite("Network (Server Mode)", function()
		test.case("should initialize in server mode and expose server API", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = true,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			local api = Network :: any
			check.not_nil(api.FireClient)
			check.not_nil(api.FireAllClients)
			check.not_nil(api.UnreliableFireClient)
			check.not_nil(api.UnreliableFireAllClients)
			check.not_nil(api.TypedServer)
			-- Removed APIs must be nil
			check.equal(api.InvokeClient, nil)
			check.equal(api.FireServer, nil)
			check.equal(api.UnreliableFireServer, nil)
			check.equal(api.TypedClient, nil)
		end)

		test.case("should register and unregister handlers", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = true,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			local called = false
			local function handler()
				called = true
			end

			Network.Register("TestEvent", handler)
			Network.Unregister("TestEvent", handler)

			-- Should not throw
			check.equal(called, false)
		end)

		test.case("should dispatch events to registered handlers", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = true,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			local receivedPlayer = nil
			local receivedData = nil

			Network.Register("PlayerAction", function(player, data)
				receivedPlayer = player
				receivedData = data
			end)

			-- Simulate client sending event to server
			mockEvent.OnServerEvent:Fire("MockPlayer", "PlayerAction", "jump")
			task.wait()

			check.equal(receivedPlayer, "MockPlayer")
			check.equal(receivedData, "jump")
		end)

		test.case("should fire events to clients", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = true,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			local api = Network :: any
			api.FireClient("Player1", "Reward", 100)

			check.equal(#mockEvent._firedClient, 1)
			check.equal(mockEvent._firedClient[1].player, "Player1")
		end)

		test.case("should expose typed server proxy event fields", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = true,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			local typedNetwork = (Network :: any).TypedServer()
			typedNetwork.RewardPlayer("Player1" :: any, 100, "Quest")

			check.equal(#mockEvent._firedClient, 1)
			check.equal(mockEvent._firedClient[1].player, "Player1")
			check.equal(mockEvent._firedClient[1].args[1], "RewardPlayer")
			check.equal(mockEvent._firedClient[1].args[2], 100)
			check.equal(mockEvent._firedClient[1].args[3], "Quest")
		end)

		test.case("should clean up empty handler entries after unregister", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = true,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			local function handler() end
			Network.Register("CleanupTest", handler)
			Network.Unregister("CleanupTest", handler)

			-- Re-register should work without issues
			Network.Register("CleanupTest", handler)
			Network.Unregister("CleanupTest", handler)
		end)

		test.case("should not duplicate event dispatch after re-init", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = true,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			Network._init({
				IsServer = true,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			local callCount = 0
			Network.Register("ReinitEvent", function()
				callCount += 1
			end)

			mockEvent.OnServerEvent:Fire("MockPlayer", "ReinitEvent")
			task.wait()

			check.equal(callCount, 1)
		end)

		test.case("should apply server middleware to incoming events", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = true,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			-- New middleware signature: (player, funcName, args: {any}) -> boolean?
			-- Mutate args in-place to transform payload.
			Network.UseMiddleware("server", function(_player, _funcName, args)
				args[1] = string.upper(args[1])
				-- no return = continue chain
			end)

			local received = nil
			Network.Register("MiddlewareEvent", function(_player, value)
				received = value
			end)

			mockEvent.OnServerEvent:Fire("MockPlayer", "MiddlewareEvent", "hello")
			task.wait()

			check.equal(received, "HELLO")
		end)

		test.case("should allow server middleware to block dispatch by returning false", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = true,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			-- Return false to abort the chain — handler must NOT run
			Network.UseMiddleware("server", function(_player, _funcName, _args)
				return false
			end)

			local handlerRan = false
			Network.Register("GuardedEvent", function()
				handlerRan = true
			end)

			mockEvent.OnServerEvent:Fire("MockPlayer", "GuardedEvent", "score")
			task.wait()

			check.equal(handlerRan, false)
		end)

		test.case("should validate arguments using RegisterTyped in server mode", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = true,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			local function isNumber(val)
				if type(val) == "number" then
					return true
				else
					return false, "Expected number"
				end
			end

			local function isString(val)
				if type(val) == "string" then
					return true
				else
					return false, "Expected string"
				end
			end

			local calledCount = 0
			local lastPlayer, lastNum, lastStr

			local function callback(player, num, str)
				calledCount += 1
				lastPlayer = player
				lastNum = num
				lastStr = str
			end

			Network.RegisterTyped("TypedEvent", { isNumber, isString }, callback)

			-- Test 1: Valid payload
			mockEvent.OnServerEvent:Fire("Player1", "TypedEvent", 42, "hello")
			task.wait()
			check.equal(calledCount, 1)
			check.equal(lastPlayer, "Player1")
			check.equal(lastNum, 42)
			check.equal(lastStr, "hello")

			-- Test 2: Invalid payload
			mockEvent.OnServerEvent:Fire("Player1", "TypedEvent", 42, 999)
			task.wait()
			check.equal(calledCount, 1)

			-- Test 3: Unregister
			Network.Unregister("TypedEvent", callback)
			mockEvent.OnServerEvent:Fire("Player1", "TypedEvent", 42, "hello")
			task.wait()
			check.equal(calledCount, 1)
		end)

		test.case("should unregister typed callbacks per event name", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = true,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			local function isNumber(val)
				return type(val) == "number", "Expected number"
			end

			local function isString(val)
				return type(val) == "string", "Expected string"
			end

			local calledCount = 0
			local function callback(_player, _value)
				calledCount += 1
			end

			Network.RegisterTyped("TypedNumberEvent", { isNumber }, callback)
			Network.RegisterTyped("TypedStringEvent", { isString }, callback)

			mockEvent.OnServerEvent:Fire("Player1", "TypedNumberEvent", 10)
			mockEvent.OnServerEvent:Fire("Player1", "TypedStringEvent", "ok")
			task.wait()
			check.equal(calledCount, 2)

			Network.Unregister("TypedNumberEvent", callback)

			mockEvent.OnServerEvent:Fire("Player1", "TypedNumberEvent", 20)
			mockEvent.OnServerEvent:Fire("Player1", "TypedStringEvent", "still registered")
			task.wait()
			check.equal(calledCount, 3)

			Network.Unregister("TypedStringEvent", callback)
			mockEvent.OnServerEvent:Fire("Player1", "TypedStringEvent", "removed")
			task.wait()
			check.equal(calledCount, 3)
		end)

		test.case("should ignore non-string server event names", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = true,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			local called = false
			(Network :: any).Register(123, function()
				called = true
			end)

			mockEvent.OnServerEvent:Fire("Player1", 123, "payload")
			task.wait()

			check.equal(called, false)
		end)

		test.case("should dispatch unreliable server events", function()
			local reliableEvent = MockRemoteEvent.new()
			local unreliableEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = true,
				EventDispatcher = reliableEvent,
				UnreliableEventDispatcher = unreliableEvent,
			})

			local received = nil
			Network.Register("UnreliableServerEvent", function(_player, value)
				received = value
			end)

			unreliableEvent.OnServerEvent:Fire("Player1", "UnreliableServerEvent", "fast")
			task.wait()

			check.equal(received, "fast")
		end)

		test.case("should validate typed unreliable server events", function()
			local reliableEvent = MockRemoteEvent.new()
			local unreliableEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = true,
				EventDispatcher = reliableEvent,
				UnreliableEventDispatcher = unreliableEvent,
			})

			local function isNumber(val)
				return type(val) == "number", "Expected number"
			end

			local calledCount = 0
			Network.RegisterTypedUnreliable("TypedUnreliableServerEvent", { isNumber }, function(_player, _value)
				calledCount += 1
			end)

			unreliableEvent.OnServerEvent:Fire("Player1", "TypedUnreliableServerEvent", 1)
			unreliableEvent.OnServerEvent:Fire("Player1", "TypedUnreliableServerEvent", "bad")
			task.wait()

			check.equal(calledCount, 1)
		end)

		test.case("should clear only selected middleware scope", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = true,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			Network.UseMiddleware("server", function()
				return false
			end)
			Network.UseMiddleware("client", function()
				return false
			end)
			Network.ClearMiddlewares("client")

			local callCount = 0
			Network.Register("ClearMiddlewareScopeEvent", function()
				callCount += 1
			end)

			mockEvent.OnServerEvent:Fire("Player1", "ClearMiddlewareScopeEvent")
			task.wait()
			check.equal(callCount, 0)

			Network.ClearMiddlewares("server")
			mockEvent.OnServerEvent:Fire("Player1", "ClearMiddlewareScopeEvent")
			task.wait()
			check.equal(callCount, 1)
		end)
	end)

	test.suite("Network (Client Mode)", function()
		test.case("should initialize in client mode and expose client API", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = false,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			local api = Network :: any
			check.not_nil(api.FireServer)
			check.not_nil(api.UnreliableFireServer)
			check.not_nil(api.TypedClient)
			-- Removed APIs must be nil
			check.equal(api.InvokeServer, nil)
			-- Server-only methods must not exist on client
			check.equal(api.FireClient, nil)
			check.equal(api.FireAllClients, nil)
			check.equal(api.UnreliableFireClient, nil)
			check.equal(api.UnreliableFireAllClients, nil)
			check.equal(api.TypedServer, nil)
		end)

		test.case("should dispatch events from server to client handler", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = false,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			local receivedValue = nil
			Network.Register("ServerMessage", function(value)
				receivedValue = value
			end)

			-- Simulate server sending event to client
			mockEvent.OnClientEvent:Fire("ServerMessage", "hello")
			task.wait()

			check.equal(receivedValue, "hello")
		end)

		test.case("should fire events to server", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = false,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			local api = Network :: any
			api.FireServer("JumpEvent", 42)

			check.equal(#mockEvent._firedServer, 1)
		end)

		test.case("should expose typed client proxy event fields", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = false,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			local typedNetwork = (Network :: any).TypedClient()
			typedNetwork.PurchaseItem("sword", 2)

			check.equal(#mockEvent._firedServer, 1)
			check.equal(mockEvent._firedServer[1][1], "PurchaseItem")
			check.equal(mockEvent._firedServer[1][2], "sword")
			check.equal(mockEvent._firedServer[1][3], 2)
		end)

		test.case("should apply client middleware to incoming events", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = false,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			-- New middleware signature: (funcName, args: {any}) -> boolean?
			Network.UseMiddleware("client", function(_funcName, args)
				args[1] = args[1] .. "_processed"
			end)

			local received = nil
			Network.Register("FromServer", function(value)
				received = value
			end)

			mockEvent.OnClientEvent:Fire("FromServer", "payload")
			task.wait()

			check.equal(received, "payload_processed")
		end)

		test.case("should validate arguments using RegisterTyped in client mode", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = false,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			local function isNumber(val)
				if type(val) == "number" then
					return true
				else
					return false, "Expected number"
				end
			end

			local calledCount = 0
			local lastNum

			local function callback(num)
				calledCount += 1
				lastNum = num
			end

			Network.RegisterTyped("ClientTypedEvent", { isNumber }, callback)

			-- Test 1: Valid payload
			mockEvent.OnClientEvent:Fire("ClientTypedEvent", 123)
			task.wait()
			check.equal(calledCount, 1)
			check.equal(lastNum, 123)

			-- Test 2: Invalid payload
			mockEvent.OnClientEvent:Fire("ClientTypedEvent", "not a number")
			task.wait()
			check.equal(calledCount, 1)
		end)

		test.case("should ignore non-string client event names", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = false,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			local called = false
			(Network :: any).Register(123, function()
				called = true
			end)

			mockEvent.OnClientEvent:Fire(123, "payload")
			task.wait()

			check.equal(called, false)
		end)

		test.case("should dispatch unreliable client events", function()
			local reliableEvent = MockRemoteEvent.new()
			local unreliableEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = false,
				EventDispatcher = reliableEvent,
				UnreliableEventDispatcher = unreliableEvent,
			})

			local received = nil
			Network.Register("UnreliableClientEvent", function(value)
				received = value
			end)

			unreliableEvent.OnClientEvent:Fire("UnreliableClientEvent", "fast")
			task.wait()

			check.equal(received, "fast")
		end)
	end)
end
