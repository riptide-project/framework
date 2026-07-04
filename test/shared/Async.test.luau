--!strict
-- Async Test Suite (frktest)

local Env = _G.TestEnv or require(script.Parent.TestEnv)
local task = Env.task

local frktest = Env.frktest
local test = frktest.test
local check = frktest.assert.check

local Async = Env.RiptideShared.Async

return function()
	test.suite("Async.Run", function()
		test.case("should run a synchronous function successfully", function()
			local result = Async.Run(function()
				return "success"
			end, 1, "timeout")

			check.equal(result, "success")
		end)

		test.case("should run an asynchronous function successfully", function()
			local result = Async.Run(function()
				task.wait(0.1)
				return "async success"
			end, 1, "timeout")

			check.equal(result, "async success")
		end)

		test.case("should timeout and return fallback value", function()
			local result = Async.Run(function()
				task.wait(0.5)
				return "too late"
			end, 0.1, "fallback")

			check.equal(result, "fallback")
		end)

		test.case("should handle multiple return values on success", function()
			local val1, val2 = Async.Run(function()
				return 1, 2
			end, 1, false, false)

			check.equal(val1, 1)
			check.equal(val2, 2)
		end)

		test.case("should handle multiple fallback return values on timeout", function()
			local val1, val2 = Async.Run(function()
				task.wait(0.5)
				return 99, 99
			end, 0.1, 1, 2)

			check.equal(val1, 1)
			check.equal(val2, 2)
		end)

		test.case("should catch and propagate errors from the underlying function", function()
			local success, result = pcall(function()
				Async.Run(function()
					error("internal error")
				end, 1)
			end)

			check.equal(success, false)
			check.is_true(string.find(tostring(result), "internal error") ~= nil)
		end)
	end)

	test.suite("Async.Retry", function()
		test.case("should return on first successful attempt", function()
			local attempts = 0
			local result = Async.Retry(function()
				attempts += 1
				return "ok"
			end, 3)

			check.equal(result, "ok")
			check.equal(attempts, 1)
		end)

		test.case("should retry on failure and succeed eventually", function()
			local attempts = 0
			local result = Async.Retry(function()
				attempts += 1
				if attempts < 3 then
					error("not yet")
				end
				return "recovered"
			end, 5, 0)

			check.equal(result, "recovered")
			check.equal(attempts, 3)
		end)

		test.case("should throw after all attempts are exhausted", function()
			local attempts = 0
			local success, err = pcall(function()
				Async.Retry(function()
					attempts += 1
					error("always fails")
				end, 3, 0)
			end)

			check.equal(success, false)
			check.equal(attempts, 3)
			check.is_true(string.find(tostring(err), "always fails") ~= nil)
		end)

		test.case("should pass arguments to the function on each attempt", function()
			local received = ""
			Async.Retry(function(a: string, b: string)
				received = a .. b
				return true
			end, 1, 0, "hello", "world")

			check.equal(received, "helloworld")
		end)

		test.case("should handle multiple return values", function()
			local a, b = Async.Retry(function()
				return 10, 20
			end, 1)

			check.equal(a, 10)
			check.equal(b, 20)
		end)

		test.case("should error when maxAttempts is less than 1", function()
			local ok, err = pcall(function()
				Async.Retry(function()
					return true
				end, 0)
			end)

			check.equal(ok, false)
			check.is_true(string.find(tostring(err), "maxAttempts must be an integer >= 1") ~= nil)
		end)

		test.case("should error when delay is negative", function()
			local ok, err = pcall(function()
				Async.Retry(function()
					return true
				end, 1, -0.1)
			end)

			check.equal(ok, false)
			check.is_true(string.find(tostring(err), "delay must be a non%-negative number") ~= nil)
		end)
	end)

	test.suite("Async.Parallel", function()
		test.case("should run multiple functions and return all results", function()
			local results = Async.Parallel({
				function()
					return "a"
				end,
				function()
					return "b"
				end,
				function()
					return "c"
				end,
			})

			check.equal(results[1].ok, true)
			check.equal(results[1].value, "a")
			check.equal(results[2].ok, true)
			check.equal(results[2].value, "b")
			check.equal(results[3].ok, true)
			check.equal(results[3].value, "c")
		end)

		test.case("should handle yielding functions", function()
			local results = Async.Parallel({
				function()
					task.wait(0.05)
					return 1
				end,
				function()
					task.wait(0.05)
					return 2
				end,
			}, 1)

			check.equal(results[1].ok, true)
			check.equal(results[1].value, 1)
			check.equal(results[2].ok, true)
			check.equal(results[2].value, 2)
		end)

		test.case("should return explicit error result for failed tasks without crashing", function()
			local results = Async.Parallel({
				function()
					return "ok"
				end,
				function()
					error("boom")
				end,
				function()
					return "also ok"
				end,
			})

			task.wait()

			check.equal(results[1].ok, true)
			check.equal(results[1].value, "ok")
			check.equal(results[2].ok, false)
			check.is_true(string.find(tostring(results[2].error), "boom") ~= nil)
			check.equal(results[3].ok, true)
			check.equal(results[3].value, "also ok")
		end)

		test.case("should distinguish successful nil from failed tasks", function()
			local results = Async.Parallel({
				function()
					return nil
				end,
				function()
					error("boom")
				end,
			})

			task.wait()

			check.equal(results[1].ok, true)
			check.equal(results[1].value, nil)
			check.equal(results[1].error, nil)
			check.equal(results[2].ok, false)
			check.is_true(string.find(tostring(results[2].error), "boom") ~= nil)
		end)

		test.case("should timeout and return partial results", function()
			local results = Async.Parallel({
				function()
					return "fast"
				end,
				function()
					task.wait(0.2)
					return "slow"
				end,
			}, 0.1)

			check.equal(results[1].ok, true)
			check.equal(results[1].value, "fast")
			check.equal(results[2].ok, false)
			check.equal(results[2].timedOut, true)
		end)

		test.case("should error on negative timeout", function()
			local ok, err = pcall(function()
				Async.Parallel({
					function()
						return true
					end,
				}, -1)
			end)

			check.equal(ok, false)
			check.is_true(string.find(tostring(err), "timeout must be a non%-negative number") ~= nil)
		end)
	end)
end
