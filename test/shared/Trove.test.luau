--!strict
-- Trove Test Suite (frktest)

local Env = _G.TestEnv or require(script.Parent.TestEnv)

local frktest = Env.frktest
local test = frktest.test
local check = frktest.assert.check

local Signal = Env.RiptideShared.Signal
local Trove = Env.RiptideShared.Trove

return function()
	test.suite("Trove", function()
		test.case("should continue cleaning after one object throws", function()
			local trove = Trove.new()
			local cleanedAfterError = false

			trove:Add({
				Destroy = function()
					error("intentional cleanup failure")
				end,
			})

			trove:Add({
				Destroy = function()
					cleanedAfterError = true
				end,
			})

			trove:Clean()

			check.equal(cleanedAfterError, true)
		end)

		test.case("should connect once through Trove.Once", function()
			local trove = Trove.new()
			local signal = Signal.new()
			local callCount = 0

			trove:Once(signal, function()
				callCount += 1
			end)

			signal:Fire()
			signal:Fire()

			check.equal(callCount, 1)

			trove:Clean()
			signal:Destroy()
		end)
	end)
end
