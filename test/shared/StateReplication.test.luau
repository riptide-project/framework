--!strict
-- StateReplication Test Suite (frktest)
-- Updated for Riptide v0.9.0:
--   • Snapshot handshake: client FireServer(EVENT_SNAPSHOT) → server FireClient(snapshot)
--     No InvokeServer. Mock auto-responds when FireServer is called.
--   • Delta packets are flat args: (scope, key, value, version) — no payload table.
--   • notify() is synchronous — no task.wait() needed after delta triggers.

local Env = _G.TestEnv or require(script.Parent.TestEnv)
local task = Env.task

local frktest = Env.frktest
local test = frktest.test
local check = frktest.assert.check

local StateReplication = Env.RiptideShared.StateReplication

--[[
	createNetworkMock()

	Server mock: when FireClient is called for EVENT_SNAPSHOT, records it.
	Client mock: when FireServer is called for EVENT_SNAPSHOT, immediately
	triggers all registered EVENT_SNAPSHOT handlers with `_snapshotResponse`
	(simulating a synchronous server round-trip in tests).

	Delta triggers use flat args: (scope, key, value, version).
]]
local function createNetworkMock(isServer: boolean, snapshotResponse: any?)
	local handlers = {} :: { [string]: { (...any) -> any } }
	local SNAPSHOT = StateReplication.Events.Snapshot

	local network = {
		_firedAll = {} :: { { name: string, args: { any } } },
		_firedClient = {} :: { { player: any, name: string, args: { any } } },
		_firedServer = {} :: { { name: string, args: { any } } },
	}

	function network.Register(name: string, callback: (...any) -> any)
		if not handlers[name] then
			handlers[name] = {}
		end
		table.insert(handlers[name], callback)
	end

	function network.Unregister(name: string, callback: (...any) -> any)
		local list = handlers[name]
		if not list then return end
		for i, current in ipairs(list) do
			if current == callback then
				table.remove(list, i)
				break
			end
		end
		if list and #list == 0 then
			handlers[name] = nil
		end
	end

	-- Server fires delta to all clients: flat args (scope, key, value, version)
	function network.FireAllClients(name: string, ...: any)
		table.insert(network._firedAll, { name = name, args = { ... } })
	end

	-- Server fires to a specific client (snapshot response or player delta)
	function network.FireClient(player: any, name: string, ...: any)
		table.insert(network._firedClient, { player = player, name = name, args = { ... } })
	end

	-- Client fires to server: if it's a snapshot request, auto-respond synchronously
	-- by triggering registered EVENT_SNAPSHOT handlers with the mock snapshot.
	function network.FireServer(name: string, ...: any)
		table.insert(network._firedServer, { name = name, args = { ... } })
		if name == SNAPSHOT and snapshotResponse ~= nil then
			local list = handlers[SNAPSHOT]
			if list then
				-- Copy list: handlers may unregister themselves during iteration
				local copy = table.clone(list)
				for _, cb in ipairs(copy) do
					cb(snapshotResponse)
				end
			end
		end
	end

	-- Helper: manually trigger registered handlers for a given event name.
	-- Use flat args for delta: network.Trigger(Delta, "global", "key", value, version)
	function network.Trigger(name: string, ...: any)
		local list = handlers[name]
		if not list then return end
		local copy = table.clone(list)
		for _, cb in ipairs(copy) do
			cb(...)
		end
	end

	return network
end

return function()
	test.suite("StateReplication (Server)", function()
		test.case("should set global state and broadcast flat-arg delta", function()
			local network = createNetworkMock(true)

			StateReplication:_init({
				IsServer = true,
				Network = network :: any,
			})

			StateReplication:Set("dayCycle", "night")

			check.equal(StateReplication:Get("dayCycle"), "night")
			check.equal(#network._firedAll, 1)

			local fired = network._firedAll[1]
			check.equal(fired.name, StateReplication.Events.Delta)
			-- flat args: { scope, key, value, version }
			check.equal(fired.args[1], "global")
			check.equal(fired.args[2], "dayCycle")
			check.equal(fired.args[3], "night")
			check.is_true((fired.args[4] :: number) >= 1)
		end)

		test.case("should set per-player state and only target that player", function()
			local network = createNetworkMock(true)
			local mockPlayer = { UserId = 1, Name = "Player1" }

			StateReplication:_init({
				IsServer = true,
				Network = network :: any,
			})

			StateReplication:SetForPlayer(mockPlayer, "coins", 125)

			check.equal(StateReplication:Get("coins", mockPlayer), 125)
			check.equal(#network._firedClient, 1)

			local fired = network._firedClient[1]
			check.equal(fired.player, mockPlayer)
			check.equal(fired.name, StateReplication.Events.Delta)
			-- flat args: { scope, key, value, version }
			check.equal(fired.args[1], "player")
			check.equal(fired.args[2], "coins")
			check.equal(fired.args[3], 125)
			check.equal(#network._firedAll, 0)
		end)

		test.case("should update per-player state via updater callback", function()
			local network = createNetworkMock(true)
			local mockPlayer = { UserId = 1, Name = "Player1" }

			StateReplication:_init({
				IsServer = true,
				Network = network :: any,
			})

			StateReplication:SetForPlayer(mockPlayer, "coins", 100)
			local result = StateReplication:UpdateForPlayer(mockPlayer, "coins", function(oldValue)
				return (oldValue or 0) + 10
			end)

			check.equal(result, 110)
			check.equal(StateReplication:Get("coins", mockPlayer), 110)
			check.equal(#network._firedClient, 2)
			check.equal(network._firedClient[2].args[3], 110) -- flat args[3] = value
		end)

		test.case("should respond to snapshot request with FireClient", function()
			local network = createNetworkMock(true)
			local mockPlayer = { UserId = 1, Name = "Player1" }

			StateReplication:_init({
				IsServer = true,
				Network = network :: any,
			})

			StateReplication:Set("mapName", "Canyon")
			StateReplication:SetForPlayer(mockPlayer, "coins", 999)

			-- Simulate client requesting a snapshot (fires EVENT_SNAPSHOT with player arg)
			network.Trigger(StateReplication.Events.Snapshot, mockPlayer)

			-- Server must have fired snapshot back to that player
			check.equal(#network._firedClient >= 2, true) -- 1 SetForPlayer + 1 snapshot
			local snapshotFire = network._firedClient[#network._firedClient]
			check.equal(snapshotFire.player, mockPlayer)
			check.equal(snapshotFire.name, StateReplication.Events.Snapshot)
			local snapshot = snapshotFire.args[1] :: any
			check.equal(snapshot.global.mapName, "Canyon")
			check.equal(snapshot.player.coins, 999)
		end)

		test.case("should cleanup per-player state when player leaves", function()
			local network = createNetworkMock(true)
			local mockPlayer = { UserId = 1, Name = "Player1" }

			StateReplication:_init({
				IsServer = true,
				Network = network :: any,
			})

			StateReplication:Set("coins", 50)
			StateReplication:SetForPlayer(mockPlayer, "coins", 200)
			check.equal(StateReplication:Get("coins", mockPlayer), 200)

			StateReplication:_onPlayerRemoving(mockPlayer)
			check.equal(StateReplication:Get("coins", mockPlayer), 50)
		end)
	end)

	test.suite("StateReplication (Client)", function()
		test.case("should request snapshot on init and merge global + player state", function()
			local snapshot = {
				global = { dayCycle = "day", coins = 10 },
				globalVersions = { dayCycle = 1, coins = 1 },
				player = { coins = 250 },
				playerVersions = { coins = 5 },
			}
			local network = createNetworkMock(false, snapshot)

			StateReplication:_init({
				IsServer = false,
				Network = network :: any,
			})

			-- FireServer(EVENT_SNAPSHOT) must have been called by RequestSync
			check.equal(#network._firedServer, 1)
			check.equal(network._firedServer[1].name, StateReplication.Events.Snapshot)

			-- Player override wins over global
			check.equal(StateReplication:Get("dayCycle"), "day")
			check.equal(StateReplication:Get("coins"), 250)
		end)

		test.case("should notify subscribers on flat-arg delta updates", function()
			local snapshot = {
				global = { coins = 100 },
				globalVersions = { coins = 1 },
				player = {},
				playerVersions = {},
			}
			local network = createNetworkMock(false, snapshot)

			StateReplication:_init({
				IsServer = false,
				Network = network :: any,
			})

			local updates = {}
			local unsubscribe = StateReplication:Subscribe("coins", function(value)
				table.insert(updates, value)
			end)

			-- Flat args: (scope, key, value, version)
			network.Trigger(StateReplication.Events.Delta, "global", "coins", 500, 2)
			-- notify() is synchronous — no task.wait() needed

			check.equal(StateReplication:Get("coins"), 500)
			check.equal(updates[1], 100) -- initial Subscribe callback
			check.equal(updates[2], 500) -- delta update

			unsubscribe()
		end)

		test.case("should apply per-player delta and override global", function()
			local snapshot = {
				global = { coins = 0 },
				globalVersions = { coins = 1 },
				player = { coins = 100 },
				playerVersions = { coins = 1 },
			}
			local network = createNetworkMock(false, snapshot)

			StateReplication:_init({
				IsServer = false,
				Network = network :: any,
			})

			network.Trigger(StateReplication.Events.Delta, "global", "coins", 50, 2)
			network.Trigger(StateReplication.Events.Delta, "player", "coins", 200, 2)

			check.equal(StateReplication:Get("coins"), 200)
		end)

		test.case("should fall back to global when player override is nil'd", function()
			local snapshot = {
				global = { theme = "dark" },
				globalVersions = { theme = 1 },
				player = { theme = "custom" },
				playerVersions = { theme = 1 },
			}
			local network = createNetworkMock(false, snapshot)

			StateReplication:_init({
				IsServer = false,
				Network = network :: any,
			})

			-- nil player override → resolved value falls back to global
			network.Trigger(StateReplication.Events.Delta, "player", "theme", nil, 2)

			check.equal(StateReplication:Get("theme"), "dark")
		end)

		test.case("should ignore stale deltas with old version numbers", function()
			local snapshot = {
				global = { coins = 100 },
				globalVersions = { coins = 5 },
				player = {},
				playerVersions = {},
			}
			local network = createNetworkMock(false, snapshot)

			StateReplication:_init({
				IsServer = false,
				Network = network :: any,
			})

			-- version 3 < current 5 → must be ignored
			network.Trigger(StateReplication.Events.Delta, "global", "coins", 1, 3)

			check.equal(StateReplication:Get("coins"), 100)
		end)

		test.case("should invoke initial Subscribe callback synchronously with current value", function()
			local snapshot = {
				global = { coins = 77 },
				globalVersions = { coins = 1 },
				player = {},
				playerVersions = {},
			}
			local network = createNetworkMock(false, snapshot)

			StateReplication:_init({
				IsServer = false,
				Network = network :: any,
			})

			local current = nil
			local unsubscribe = StateReplication:Subscribe("coins", function(value)
				current = value
			end)

			-- Must fire synchronously — no task.wait() needed
			check.equal(current, 77)
			unsubscribe()
		end)

		test.case("should not send duplicate snapshot requests when syncYielding", function()
			-- Create a mock that does NOT auto-respond (snapshotResponse = nil)
			-- so _syncYielding stays true after first RequestSync
			local network = createNetworkMock(false, nil)

			StateReplication:_init({
				IsServer = false,
				Network = network :: any,
			})

			-- _init already called RequestSync (1 fire). A second call while yielding must be a no-op.
			local result = StateReplication:RequestSync()
			check.equal(result, false)
			check.equal(#network._firedServer, 1) -- still only 1
		end)
	end)
end
