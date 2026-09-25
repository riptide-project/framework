--!strict
-- Malicious-client packets sent directly to the transport, bypassing client API types.
local Env = _G.TestEnv or require(script.Parent.TestEnv)
local test = Env.frktest.test
local check = Env.frktest.assert.check
local Network = Env.RiptideShared.Network
local State = Env.RiptideShared.StateReplication
local MockRemoteEvent = Env.Mocks.MockRemoteEvent

local function serverTransport()
	local reliable = MockRemoteEvent.new()
	local unreliable = MockRemoteEvent.new()
	Network._init({ IsServer = true, EventDispatcher = reliable, UnreliableEventDispatcher = unreliable })
	return reliable, unreliable
end

return function()
	test.suite("Network security regressions", function()
		test.case("client delta spoof and snapshot payload cannot change server state", function()
			local reliable = serverTransport()
			State:_init({ IsServer = true, Network = Network })
			local player = { UserId = 1 }
			local victim = { UserId = 2 }
			State:Set("coins", 10)
			State:SetForPlayer(player, "private", "own")
			State:SetForPlayer(victim, "private", "victim")
			reliable.OnServerEvent:Fire(player, State.Events.Delta, "global", "coins", 999999, 99)
			reliable.OnServerEvent:Fire(player, State.Events.Snapshot, 1, { player = victim })
			check.equal(State:Get("coins"), 10)
			check.equal(State:Get("private", victim), "victim")
			local response = reliable._firedClient[#reliable._firedClient]
			check.equal(response.player, player)
			check.equal(response.args[2].player.private, "own")
		end)

		test.case("typed guard rejects forged payload and later valid packet works", function()
			local reliable, unreliable = serverTransport()
			local calls = 0
			Network.RegisterTyped("buy", {
				function(value)
					return type(value) == "number" and value >= 1 and value <= 10, "invalid quantity"
				end,
			}, function()
				calls += 1
			end)
			local player = { UserId = 1 }
			reliable.OnServerEvent:Fire(player, "buy", "10")
			reliable.OnServerEvent:Fire(player, "buy", math.huge)
			unreliable.OnServerEvent:Fire(player, "buy", -1)
			reliable.OnServerEvent:Fire(player, "buy", 2)
			check.equal(calls, 1)
		end)

		test.case("snapshot request flood has bounded responses per player", function()
			local reliable, unreliable = serverTransport()
			State:_init({ IsServer = true, Network = Network })
			local player = { UserId = 1 }
			for id = 1, 32 do
				local remote = if id % 2 == 0 then unreliable else reliable
				remote.OnServerEvent:Fire(player, State.Events.Snapshot, id)
			end
			check.equal(#reliable._firedClient, 2)
			check.equal(reliable._firedClient[1].args[2].global ~= nil, true)
			check.equal(reliable._firedClient[2].args[2].retryAfter ~= nil, true)
		end)

		test.case("two clients cannot read each other's private state through raw requests", function()
			local reliable, unreliable = serverTransport()
			State:_init({ IsServer = true, Network = Network })
			local alice = { UserId = 1 }
			local bob = { UserId = 2 }
			State:Set("public", "shared")
			State:SetForPlayer(alice, "secret_1", "alice-only")
			State:SetForPlayer(bob, "secret_2", "bob-only")

			-- Only reliable transport accepts snapshot requests, and identity comes from OnServerEvent.
			reliable.OnServerEvent:Fire(alice, State.Events.Snapshot, 101, bob)
			for id = 102, 133 do
				local remote = if id % 2 == 0 then reliable else unreliable
				remote.OnServerEvent:Fire(alice, State.Events.Snapshot, id, bob)
			end
			-- Alice's burst must not consume Bob's independent response budget.
			reliable.OnServerEvent:Fire(bob, State.Events.Snapshot, 201, alice)
			check.equal(#reliable._firedClient, 5) -- two deltas, Alice's full/retry, Bob's full
			local aliceResponse = reliable._firedClient[3]
			local bobResponse = reliable._firedClient[5]
			check.equal(aliceResponse.player, alice)
			check.equal(aliceResponse.args[2].global.public, "shared")
			check.equal(aliceResponse.args[2].player.secret_1, "alice-only")
			check.equal(aliceResponse.args[2].player.secret_2, nil)
			check.equal(bobResponse.player, bob)
			check.equal(bobResponse.args[2].player.secret_2, "bob-only")
			check.equal(bobResponse.args[2].player.secret_1, nil)

			check.equal(#reliable._firedClient, 5)
			check.equal(reliable._firedClient[4].player, alice)
			check.equal(reliable._firedClient[4].args[2].retryAfter ~= nil, true)
			check.equal(State:Get("secret_1", alice), "alice-only")
			check.equal(State:Get("secret_2", bob), "bob-only")
		end)
	end)
end
