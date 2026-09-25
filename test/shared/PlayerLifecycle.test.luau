--!strict
-- PlayerLifecycle Test Suite (frktest)

local Env = _G.TestEnv or require(script.Parent.TestEnv)
local task = Env.task

local frktest = Env.frktest
local test = frktest.test
local check = frktest.assert.check

local MockPlayers = Env.Mocks.MockPlayers
local PlayerLifecycle = Env.RiptideShared.PlayerLifecycle

return function()
	test.suite("PlayerLifecycle", function()
		test.case("leaving cancels a yielding initialization before it can create late state", function()
			local players = MockPlayers.new()
			local player = {}
			players._players = { player }
			local late, removed = false, false
			PlayerLifecycle:_init({ Players = players })
			PlayerLifecycle:Start({
				{
					name = "Audit",
					module = {
						OnPlayerAdded = function()
							task.wait(0.03)
							late = true
						end,
						OnPlayerRemoving = function()
							removed = true
						end,
					},
				},
			}, {})
			players:RemovePlayer(player)
			task.wait(0.05)
			check.equal(late, false)
			check.equal(removed, true)
		end)

		test.case("players joining during startup snapshot are handled exactly once", function()
			local players = MockPlayers.new()
			local existing, joined = {}, {}
			players._players = { existing }
			local original = players.GetPlayers
			players.GetPlayers = function(self)
				local snapshot = table.clone(original(self))
				self:AddPlayer(joined)
				return snapshot
			end
			local seen = {}
			PlayerLifecycle:_init({ Players = players })
			PlayerLifecycle:Start({
				{
					name = "Audit",
					module = {
						OnPlayerAdded = function(_self, _ref, player)
							seen[player] = (seen[player] or 0) + 1
						end,
					},
				},
			}, {})
			check.equal(seen[existing], 1)
			check.equal(seen[joined], 1)
		end)

		test.case("should call player hooks for existing and joining players", function()
			local players = MockPlayers.new()
			local existing = { UserId = 1 }
			table.insert(players._players, existing)

			PlayerLifecycle:_init({
				Players = players,
			})

			local added = {}
			local loadedModules = {
				{
					name = "PlayerService",
					module = {
						OnPlayerAdded = function(_self: any, _riptide: any, player: any)
							table.insert(added, player)
						end,
					},
				},
			}

			PlayerLifecycle:Start(loadedModules, {})

			local joined = { UserId = 2 }
			players:AddPlayer(joined)

			check.equal(#added, 2)
			check.equal(added[1], existing)
			check.equal(added[2], joined)
		end)

		test.case("should cleanup state on player removing", function()
			local players = MockPlayers.new()
			local player = { UserId = 1 }
			table.insert(players._players, player)

			local removed = nil
			local state = {
				_onPlayerRemoving = function(_self: any, leavingPlayer: any)
					removed = leavingPlayer
				end,
			}

			PlayerLifecycle:_init({
				Players = players,
				StateReplication = state,
			})

			PlayerLifecycle:Start({}, {})
			players:RemovePlayer(player)

			check.equal(removed, player)
		end)

		test.case("should trigger custom OnPlayerAdded and OnPlayerRemoving callbacks passed in deps", function()
			local players = MockPlayers.new()
			local player = { UserId = 1 }
			table.insert(players._players, player)

			local addedTriggered = nil
			local removedTriggered = nil

			PlayerLifecycle:_init({
				Players = players,
				OnPlayerAdded = function(p)
					addedTriggered = p
				end,
				OnPlayerRemoving = function(p)
					removedTriggered = p
				end,
			})

			PlayerLifecycle:Start({}, {})
			check.equal(addedTriggered, player)

			players:RemovePlayer(player)
			check.equal(removedTriggered, player)
		end)
	end)
end
