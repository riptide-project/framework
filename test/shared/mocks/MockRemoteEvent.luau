--!strict
-- Mock RemoteEvent for Lune testing
-- Simulates Roblox RemoteEvent using Signal
local isRoblox = typeof(game) ~= "nil"
local task = task
if not isRoblox then
	pcall(function()
		task = require("@lune/task")
	end)
end
local Signal = isRoblox and require(game.ReplicatedStorage.Riptide.shared.Utilities.Signal)
	or require("../../../src/shared/Utilities/Signal")

export type MockRemoteEvent = {
	OnServerEvent: any,
	OnClientEvent: any,
	FireClient: (self: MockRemoteEvent, player: any, ...any) -> (),
	FireAllClients: (self: MockRemoteEvent, ...any) -> (),
	FireServer: (self: MockRemoteEvent, ...any) -> (),
}

local MockRemoteEvent = {}
MockRemoteEvent.__index = MockRemoteEvent

function MockRemoteEvent.new(): MockRemoteEvent
	local self = setmetatable({
		OnServerEvent = Signal.new(),
		OnClientEvent = Signal.new(),
		_firedClient = {} :: { any },
		_firedAllClients = {} :: { any },
		_firedServer = {} :: { any },
	}, MockRemoteEvent)
	return (self :: any) :: MockRemoteEvent
end

function MockRemoteEvent:FireClient(player: any, ...: any)
	table.insert(self._firedClient, { player = player, args = { ... } })
	self.OnClientEvent:Fire(...)
end

function MockRemoteEvent:FireAllClients(...: any)
	table.insert(self._firedAllClients, { ... })
	self.OnClientEvent:Fire(...)
end

function MockRemoteEvent:FireServer(...: any)
	table.insert(self._firedServer, { ... })
	self.OnServerEvent:Fire(nil, ...) -- nil as mock player
end

return MockRemoteEvent
