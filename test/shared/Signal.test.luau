--!strict
-- Signal Test Suite (frktest)

local Env = _G.TestEnv or require(script.Parent.TestEnv)
local task = Env.task

local frktest = Env.frktest
local test = frktest.test
local check = frktest.assert.check
local req = frktest.assert.require

local Signal = Env.RiptideShared.Signal

return function()
	test.suite("Signal", function()
		test.case("should create a new signal", function()
			local sig = Signal.new()
			req.not_nil(sig)
		end)

		test.case("should connect to a function and fire", function()
			local sig = Signal.new()
			local fired = false
			local value = 0

			local conn = sig:Connect(function(v)
				fired = true
				value = v
			end)

			req.not_nil(conn)
			check.equal(conn.Connected, true)

			sig:Fire(42)
			task.wait()

			check.equal(fired, true)
			check.equal(value, 42)
		end)

		test.case("should disconnect correctly and clear references", function()
			local sig = Signal.new()
			local count = 0

			local conn = sig:Connect(function()
				count += 1
			end)

			sig:Fire()
			task.wait()
			check.equal(count, 1)

			conn:Disconnect()
			check.equal(conn.Connected, false)

			-- Verify references are cleared (memory leak prevention)
			check.equal((conn :: any)._signal, nil)
			check.equal((conn :: any)._node, nil)

			sig:Fire()
			task.wait()
			check.equal(count, 1) -- Should not trigger again
		end)

		test.case("should support Once (auto-disconnect after first fire)", function()
			local sig = Signal.new()
			local count = 0

			local conn = sig:Once(function()
				count += 1
			end)

			check.equal(conn.Connected, true)

			sig:Fire()
			task.wait()
			check.equal(count, 1)
			check.equal(conn.Connected, false)

			sig:Fire()
			task.wait()
			check.equal(count, 1) -- No second trigger
		end)

		test.case("should wait and yield correctly", function()
			local sig = Signal.new()
			local value1, value2

			task.spawn(function()
				value1, value2 = sig:Wait()
			end)

			sig:Fire("Hello", "World")
			task.wait()

			check.equal(value1, "Hello")
			check.equal(value2, "World")
		end)

		test.case("should disconnect all connections and clear references", function()
			local sig = Signal.new()
			local count1 = 0
			local count2 = 0

			local conn1 = sig:Connect(function()
				count1 += 1
			end)

			local conn2 = sig:Connect(function()
				count2 += 1
			end)

			check.equal(conn1.Connected, true)
			check.equal(conn2.Connected, true)

			sig:DisconnectAll()

			check.equal(conn1.Connected, false)
			check.equal(conn2.Connected, false)
			check.equal((conn1 :: any)._node, nil)
			check.equal((conn2 :: any)._node, nil)

			sig:Fire()
			task.wait()

			check.equal(count1, 0)
			check.equal(count2, 0)
		end)

		test.case("should support Destroy and prevent further use", function()
			local sig = Signal.new()
			local conn = sig:Connect(function() end)
			check.equal(conn.Connected, true)

			sig:Destroy()

			check.equal(conn.Connected, false)
			check.equal(
				pcall(function()
					sig:Connect(function() end)
				end),
				false
			)
			check.equal(
				pcall(function()
					sig:Wait()
				end),
				false
			)
		end)

		test.case("skips several removed listeners without skipping a live one", function()
			local sig = Signal.new()
			local calls = {}
			sig:Connect(function()
				table.insert(calls, "oldest")
			end)
			local first = sig:Connect(function()
				error("removed listener ran")
			end)
			local second = sig:Connect(function()
				error("removed listener ran")
			end)
			sig:Connect(function()
				first:Disconnect()
				second:Disconnect()
			end)
			sig:Fire()
			check.equal(table.concat(calls, ","), "oldest")
		end)

		test.case("Once disconnects before nested Fire", function()
			local sig = Signal.new()
			local count = 0
			local conn = sig:Once(function()
				count += 1
				sig:Fire()
			end)
			sig:Fire()
			check.equal(count, 1)
			check.equal(conn.Connected, false)
		end)

		test.case("Once stays disconnected when its callback errors", function()
			local sig = Signal.new()
			local count = 0
			local conn = sig:Once(function()
				count += 1
				error("intentional Once callback error")
			end)
			check.equal(pcall(sig.Fire, sig), true)
			check.equal(conn.Connected, false)
			sig:Fire()
			task.wait()
			check.equal(count, 1)
		end)

		test.case("Wait keeps trailing nil and reports cancellation", function()
			local sig = Signal.new()
			local values
			task.spawn(function()
				values = table.pack(sig:Wait())
			end)
			sig:Fire("value", nil)
			task.wait()
			check.equal(values.n, 2)
			check.equal(values[1], "value")
			check.equal(values[2], nil)

			local cancelled = false
			task.spawn(function()
				local ok, message = pcall(function()
					sig:Wait()
				end)
				cancelled = not ok and string.find(tostring(message), "Wait cancelled", 1, true) ~= nil
			end)
			sig:DisconnectAll()
			task.wait()
			check.equal(cancelled, true)
		end)

		test.case("new listeners join nested Fire but not the outer dispatch", function()
			local sig = Signal.new()
			local calls = {}
			local nested = false
			sig:Connect(function()
				table.insert(calls, "old")
			end)
			sig:Connect(function()
				table.insert(calls, "new")
				if not nested then
					nested = true
					sig:Connect(function()
						table.insert(calls, "added")
					end)
					sig:Fire()
				end
			end)
			sig:Fire()
			check.equal(table.concat(calls, ","), "new,added,new,old,old")
		end)

		test.case("callback errors do not block other listeners", function()
			local sig = Signal.new()
			local count = 0
			sig:Connect(function()
				count += 1
			end)
			local broken = sig:Connect(function()
				error("intentional Signal callback error")
			end)
			check.equal(pcall(sig.Fire, sig), true)
			task.wait()
			check.equal(count, 1)
			broken:Disconnect()
			sig:Fire()
			task.wait()
			check.equal(count, 2)
		end)

		test.case("yielding callback does not block Fire or other listeners", function()
			local sig = Signal.new()
			local finished = false
			local otherRan = false
			sig:Connect(function()
				otherRan = true
			end)
			sig:Connect(function()
				task.wait(0.05)
				finished = true
			end)
			sig:Fire()
			check.equal(finished, false)
			task.wait()
			check.equal(otherRan, true)
			task.wait(0.06)
			check.equal(finished, true)
		end)

		test.case("DisconnectAll can be followed by a new subscription", function()
			local sig = Signal.new()
			local count = 0
			sig:Connect(function()
				sig:DisconnectAll()
				sig:Connect(function()
					count += 1
				end)
			end)
			sig:Fire()
			check.equal(count, 0)
			sig:Fire()
			check.equal(count, 1)
		end)

		test.case("Destroy is idempotent and Fire stays safe", function()
			local sig = Signal.new()
			sig:Destroy()
			sig:Destroy()
			sig:Fire()
			check.equal(
				pcall(function()
					sig:Once(function() end)
				end),
				false
			)
		end)
	end)
end
