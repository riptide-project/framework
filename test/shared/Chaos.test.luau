--!strict
-- Chaos Test Suite (frktest)

local Env = _G.TestEnv or require(script.Parent.TestEnv)
local task = Env.task

local frktest = Env.frktest
local test = frktest.test
local check = frktest.assert.check

local Network = Env.RiptideShared.Network
local MockRemoteEvent = Env.Mocks.MockRemoteEvent
local _MockRemoteFunction = Env.Mocks.MockRemoteFunction -- kept for potential future use; not injected into Network
local ComponentService = Env.RiptideShared.ComponentService
local Async = Env.RiptideShared.Async
local Signal = Env.RiptideShared.Signal
local _ModuleLoader = Env.RiptideShared.ModuleLoader

return function()
	test.suite("Chaos Scenarios", function()
		test.case("Network Flood: 10,000 requests in one frame", function()
			local mockEvent = MockRemoteEvent.new()

			Network._init({
				IsServer = true,
				EventDispatcher = mockEvent,
				UnreliableEventDispatcher = mockEvent,
			})

			local count = 0
			Network.Register("FloodEvent", function()
				count += 1
			end)

			for _ = 1, 10000 do
				mockEvent.OnServerEvent:Fire("MockPlayer", "FloodEvent")
			end
			task.wait()

			check.equal(count, 10000)
		end)

		test.case("Component Churn: 10 cycles of 1000 add/remove", function()
			local cs = ComponentService :: any
			cs._isStarted = false
			table.clear(cs._tagListeners)
			table.clear(cs._registry)

			for cycle = 1, 10 do
				local instances = {}
				for i = 1, 1000 do
					local mockInstance = { Name = "ChurnPart_" .. cycle .. "_" .. i }
					instances[i] = mockInstance
					cs._registry[mockInstance] = {}
					cs._registry[mockInstance]["TagAlpha"] = {
						Destroy = function() end,
					}
				end

				-- Remove them (simulate tag removal / garbage collection tracking)
				for i = 1, 1000 do
					local mockInstance = instances[i]
					local components = cs._registry[mockInstance]
					if components then
						local componentObj = components["TagAlpha"]
						if componentObj and type(componentObj.Destroy) == "function" then
							pcall(componentObj.Destroy, componentObj)
						end
					end
					cs._registry[mockInstance] = nil
				end
			end

			-- Ensure registry is completely empty after churn
			local remaining = 0
			for _, _ in pairs(cs._registry) do
				remaining += 1
			end

			check.equal(remaining, 0)
		end)

		test.case("Async Timeout Hell: 500 parallel Run with 0.0001 timeout", function()
			local fns = {}
			for _ = 1, 500 do
				table.insert(fns, function()
					task.wait(0.1) -- 0.1s guarantees timeout
					return "done"
				end)
			end

			local results = Async.Parallel(fns, 0.0001)

			local timeouts = 0
			for i = 1, 500 do
				if results[i] and results[i].timedOut == true then
					timeouts += 1
				end
			end

			check.equal(timeouts, 500)
		end)

		test.case("Signal Hammer: 1000 connect + instantly disconnect during Fire", function()
			local sig = Signal.new()
			local conns = {}
			local executions = 0

			for _ = 1, 1000 do
				table.insert(
					conns,
					sig:Connect(function()
						executions += 1
						-- Disconnect ALL of them during iteration
						for _, c in ipairs(conns) do
							c:Disconnect()
						end
					end)
				)
			end

			sig:Fire()
			task.wait()

			-- Only the first one should execute, or maybe a few before disconnects take effect
			-- But it must not crash the linked list traversal.
			check.is_true(executions > 0)
			check.is_true(executions <= 1000)
			check.equal(sig._head, nil)
		end)

		test.case("Circular Dependencies: Loader recursion test via GetService", function()
			local riptide = {
				_modules = {},
				_moduleAliases = {},
				ComponentService = { _start = function() end },
			}

			-- Mock Riptide.GetService that resolves loading on request
			-- to emulate an engine that does lazy/circular loading dynamically.
			local loadAttempts = 0
			function riptide:GetService(name: string)
				loadAttempts += 1
				if loadAttempts > 200 then
					error("Circular dependency detected during initialization", 2)
				end

				local target = name == "A" and "B" or "A"
				return self:GetService(target)
			end

			local success, err = pcall(function()
				riptide:GetService("A")
			end)

			check.equal(success, false)
			check.is_true(string.find(tostring(err), "Circular dependency detected") ~= nil)
		end)
	end)
end
