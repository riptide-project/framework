--!strict
-- EventBus Test Suite (frktest)

local Env = _G.TestEnv or require(script.Parent.TestEnv)

local frktest = Env.frktest
local test = frktest.test
local check = frktest.assert.check

local EventBus = Env.RiptideShared.EventBus

return function()
	test.suite("EventBus", function()
		test.case("On receives emitted payloads and unsubscribe removes listener", function()
			local bus = EventBus.new()
			local count = 0
			local received = ""

			local unsubscribe = bus:On("score", function(playerName: string, score: number)
				count += 1
				received = playerName .. ":" .. tostring(score)
			end)

			bus:Emit("score", "Ada", 42)
			check.equal(count, 1)
			check.equal(received, "Ada:42")

			unsubscribe()
			bus:Emit("score", "Ada", 100)
			check.equal(count, 1)
		end)

		test.case("Once receives only the first emission", function()
			local bus = EventBus.new()
			local count = 0

			local unsubscribe = bus:Once("ready", function()
				count += 1
			end)

			bus:Emit("ready")
			bus:Emit("ready")
			unsubscribe()

			check.equal(count, 1)
		end)

		test.case("Once can be cancelled before first emission", function()
			local bus = EventBus.new()
			local count = 0

			local unsubscribe = bus:Once("ready", function()
				count += 1
			end)

			unsubscribe()
			bus:Emit("ready")

			check.equal(count, 0)
		end)

		test.case("listener errors do not stop later listeners", function()
			local bus = EventBus.new()
			local goodListenerRan = false

			bus:On("event", function()
				error("intentional listener failure")
			end)
			bus:On("event", function()
				goodListenerRan = true
			end)

			bus:Emit("event")

			check.equal(goodListenerRan, true)
		end)

		test.case("Clear removes listeners", function()
			local bus = EventBus.new()
			local count = 0

			bus:On("event", function()
				count += 1
			end)

			bus:Clear()
			bus:Emit("event")

			check.equal(count, 0)
		end)

		test.case("Destroy is a cleanup-compatible alias for Clear", function()
			local bus = EventBus.new()
			local count = 0

			bus:On("event", function()
				count += 1
			end)

			bus:Destroy()
			bus:Emit("event")

			check.equal(count, 0)
		end)
	end)
end
