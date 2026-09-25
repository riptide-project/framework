--!strict
local Env = _G.TestEnv or require(script.Parent.TestEnv)
local test = Env.frktest.test
local check = Env.frktest.assert.check
local task = Env.task
local M = Env.RiptideShared

local function network(isServer)
	local remote = Env.Mocks.MockRemoteEvent.new()
	M.Network._init({ IsServer = isServer, EventDispatcher = remote, UnreliableEventDispatcher = remote })
	return remote
end

return function()
	test.suite("Core regressions", function()
		test.case("Signal nested Fire and new connections have deterministic traversal", function()
			local signal = M.Signal.new()
			local calls = {}
			local nested = false
			signal:Connect(function()
				table.insert(calls, "tail")
			end)
			signal:Connect(function()
				table.insert(calls, "head")
				if not nested then
					nested = true
					signal:Connect(function()
						table.insert(calls, "new")
					end)
					signal:Fire()
				end
			end)
			signal:Fire()
			check.equal(table.concat(calls, ","), "head,new,head,tail,tail")
			signal:Destroy()
		end)

		test.case("Signal callback errors release traversal bookkeeping", function()
			local signal = M.Signal.new()
			local tail = signal:Connect(function() end)
			local head = signal:Connect(function()
				tail:Disconnect()
				error("intentional")
			end)
			check.equal(pcall(signal.Fire, signal), true)
			check.equal(tail.Connected, false)
			head:Disconnect()
			local count = 0
			signal:Connect(function()
				count += 1
				signal:Destroy()
			end)
			signal:Fire()
			check.equal(count, 1)
		end)

		test.case("duplicate typed registrations can all be unregistered", function()
			local remote = network(false)
			local count = 0
			local callback = function()
				count += 1
			end
			M.Network.RegisterTyped("x", {}, callback)
			M.Network.RegisterTyped("x", {}, callback)
			M.Network.Unregister("x", callback)
			M.Network.Unregister("x", callback)
			remote.OnClientEvent:Fire("x")
			check.equal(count, 0)
		end)

		test.case("reliable and unreliable middleware keep nils and reject blocked packets", function()
			for _, server in ipairs({ false, true }) do
				local reliable = Env.Mocks.MockRemoteEvent.new()
				local unreliable = Env.Mocks.MockRemoteEvent.new()
				M.Network._init({
					IsServer = server,
					EventDispatcher = reliable,
					UnreliableEventDispatcher = unreliable,
				})
				local calls = 0
				M.Network.UseMiddleware(if server then "server" else "client", function(...)
					local name = select(if server then 2 else 1, ...)
					return name ~= "blocked"
				end)
				local function handler(...)
					check.equal(select("#", ...), if server then 5 else 4)
					calls += 1
				end
				M.Network.Register("x", handler)
				M.Network.Register("blocked", handler)
				for _, remote in ipairs({ reliable, unreliable }) do
					if server then
						remote.OnServerEvent:Fire({}, "x", 1, nil, 3, nil)
						remote.OnServerEvent:Fire({}, "blocked", 1, nil, 3, nil)
					else
						remote.OnClientEvent:Fire("x", 1, nil, 3, nil)
						remote.OnClientEvent:Fire("blocked", 1, nil, 3, nil)
					end
				end
				check.equal(calls, 2)
			end
		end)

		test.case("Async rejects nonfinite deadlines before launching work", function()
			for _, timeout in ipairs({ math.huge, 0 / 0, -1 }) do
				local called = false
				local ok = pcall(M.Async.Run, function()
					called = true
				end, timeout)
				check.equal(ok, false)
				check.equal(called, false)
				check.equal(pcall(M.Async.Parallel, {}, timeout), false)
			end
		end)

		test.case("Async preserves trailing nil results, fallbacks and retry arguments", function()
			for _, yielding in ipairs({ false, true }) do
				local result = table.pack(M.Async.Run(function()
					if yielding then
						task.wait()
					end
					return 1, nil, 3, nil
				end, 1))
				check.equal(result.n, 4)
			end
			local fallback = table.pack(M.Async.Run(function()
				task.wait(0.02)
			end, 0.001, 1, nil))
			check.equal(fallback.n, 2)
			local result = table.pack(M.Async.Retry(function(...)
				check.equal(select("#", ...), 2)
				return 1, nil
			end, 1, 0, 1, nil))
			check.equal(result.n, 2)
		end)

		test.case("Signal continues past a disconnected next listener", function()
			local signal = M.Signal.new()
			local calls = 0
			signal:Connect(function()
				calls += 1
			end)
			local nextConnection = signal:Connect(function()
				error("disconnected listener ran")
			end)
			signal:Connect(function()
				nextConnection:Disconnect()
			end)
			signal:Fire()
			check.equal(calls, 1)
			check.equal(nextConnection.Connected, false)
			signal:Destroy()
		end)

		test.case("Signal DisconnectAll detaches waiters before resuming them", function()
			local signal = M.Signal.new()
			local count = 0
			local cancelled = false
			task.spawn(function()
				local ok = pcall(function()
					signal:Wait()
				end)
				cancelled = not ok
				signal:Connect(function()
					count += 1
				end)
			end)
			signal:DisconnectAll()
			signal:Fire()
			check.equal(count, 1)
			check.equal(cancelled, true)
			signal:Destroy()
		end)

		test.case("EventBus preserves nil arguments", function()
			local bus = M.EventBus.new()
			local count = 0
			bus:On("x", function(...)
				count = select("#", ...)
			end)
			bus:Emit("x", 1, nil)
			check.equal(count, 2)
		end)

		test.case("EventBus Once stays once across nested emissions", function()
			local bus = M.EventBus.new()
			local nested = false
			local count = 0
			bus:On("x", function()
				if not nested then
					nested = true
					bus:Emit("x")
				end
			end)
			bus:Once("x", function()
				count += 1
			end)
			bus:Emit("x")
			check.equal(count, 1)
		end)

		test.case("EventBus unsubscribe is idempotent for duplicate callbacks", function()
			local bus = M.EventBus.new()
			local count = 0
			local function callback()
				count += 1
			end
			local off = bus:On("x", callback)
			bus:On("x", callback)
			off()
			off()
			bus:Emit("x")
			check.equal(count, 1)
		end)

		test.case("Network middleware preserves nil payloads on both sides", function()
			for _, server in ipairs({ false, true }) do
				local remote = network(server)
				M.Network.UseMiddleware(if server then "server" else "client", function()
					return true
				end)
				local count = 0
				M.Network.Register("x", function(...)
					count = select("#", ...)
				end)
				if server then
					remote.OnServerEvent:Fire({}, "x", 1, nil)
				else
					remote.OnClientEvent:Fire("x", 1, nil)
				end
				check.equal(count, if server then 3 else 2)
			end
		end)

		test.case("Network self-unregister does not skip the next handler", function()
			local remote = network(false)
			local count = 0
			local first
			first = function()
				M.Network.Unregister("x", first)
			end
			M.Network.Register("x", first)
			M.Network.Register("x", function()
				count += 1
			end)
			remote.OnClientEvent:Fire("x")
			check.equal(count, 1)
		end)

		test.case("Typed client callbacks receive zero arguments for empty payloads", function()
			local remote = network(false)
			local count = -1
			M.Network.RegisterTyped("x", {}, function(...)
				count = select("#", ...)
			end)
			remote.OnClientEvent:Fire("x")
			check.equal(count, 0)
		end)

		test.case("Destroying one StateMachine does not erase another machine's configuration", function()
			local config = { InitialState = "A", States = { A = {}, B = {} } }
			local first = M.StateMachine.new(config)
			local second = M.StateMachine.new(config)
			first:Destroy()
			second:TransitionTo("B")
			check.equal(second:GetCurrentState(), "B")
			check.not_nil(config.States.A)
			second:Destroy()
		end)

		test.case("Trove Once releases its connection even when callback throws", function()
			local signal = M.Signal.new()
			local trove = M.Trove.new()
			local connection = trove:Once(signal, function()
				error("intentional")
			end)
			pcall(signal.Fire, signal)
			check.equal(trove:Pop(connection), false)
			trove:Destroy()
			signal:Destroy()
		end)
	end)
end
