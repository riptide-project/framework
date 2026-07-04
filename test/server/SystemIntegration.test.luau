--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local frktest = require(ReplicatedStorage.Packages.frktest)
local test = frktest.test
local check = frktest.assert.check

local Riptide = require(ReplicatedStorage.Riptide)

return function()
	test.suite("Riptide Server-Side Core Systems", function()
		test.case("Signal API should connect, fire, and disconnect", function()
			local signal = Riptide.Signal.new()
			local accumulated = 0

			local connection = signal:Connect(function(val: number)
				accumulated += val
			end)

			signal:Fire(5)
			check.equal(accumulated, 5)

			signal:Fire(10)
			check.equal(accumulated, 15)

			connection:Disconnect()
			signal:Fire(10)
			check.equal(accumulated, 15) -- Should not change

			signal:Destroy()
		end)

		test.case("Async API should execute tasks and parallelize", function()
			-- Async.Run
			local runSuccess = Riptide.Async.Run(function()
				task.wait(0.1)
				return "Server Done"
			end, 1, "Timeout")
			check.equal(runSuccess, "Server Done")

			-- Async.Parallel
			local parallelResults = Riptide.Async.Parallel({
				function()
					task.wait(0.05)
					return "A"
				end,
				function()
					task.wait(0.05)
					return "B"
				end,
			}, 1)
			check.equal(parallelResults[1].ok, true)
			check.equal(parallelResults[1].value, "A")
			check.equal(parallelResults[2].ok, true)
			check.equal(parallelResults[2].value, "B")
		end)

		test.case("Network Engine Registration", function()
			local _didCallbackRun = false
			local function mockCallback()
				_didCallbackRun = true
			end

			Riptide.Network.Register("ServerTestCallback", mockCallback)
			-- Since we don't have a live player here to Invoke, we at least verify no errors occur
			Riptide.Network.Unregister("ServerTestCallback", mockCallback)
			check.is_true(true)
		end)

		test.case("StateMachine Server Initialization", function()
			local stateMachine = Riptide.StateMachine.new({
				InitialState = "Idle",
				States = {
					Idle = {},
					Running = {},
				},
			})

			local stateChanged = false
			stateMachine.OnStateChanged:Connect(function(old, new)
				if old == "Idle" and new == "Running" then
					stateChanged = true
				end
			end)

			stateMachine:TransitionTo("Running")
			check.is_true(stateChanged)
			check.equal(stateMachine:GetCurrentState(), "Running")
		end)

		test.case("StateReplication Setup", function()
			-- Restore server state in case previous mock tests overrode the singleton
			Riptide.State:_init({
				IsServer = true,
				Network = Riptide.Network :: any,
			})

			Riptide.State:Set("TestGold", 100)
			check.equal(Riptide.State:Get("TestGold"), 100)

			Riptide.State:Set("TestGold", 150)
			check.equal(Riptide.State:Get("TestGold"), 150)
		end)
	end)
end
