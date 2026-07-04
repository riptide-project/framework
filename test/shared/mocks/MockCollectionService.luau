--!strict
-- Mock CollectionService for Lune testing
-- Simulates tag-based instance tracking
local isRoblox = typeof(game) ~= "nil"
local task = task
if not isRoblox then
	pcall(function()
		task = require("@lune/task")
	end)
end
local Signal = isRoblox and require(game.ReplicatedStorage.Riptide.shared.Utilities.Signal)
	or require("../../../src/shared/Utilities/Signal")

export type MockCollectionService = {
	_tags: { [string]: { any } },
	_addedSignals: { [string]: any },
	_removedSignals: { [string]: any },
	AddTag: (self: MockCollectionService, instance: any, tag: string) -> (),
	RemoveTag: (self: MockCollectionService, instance: any, tag: string) -> (),
	GetTagged: (self: MockCollectionService, tag: string) -> { any },
	GetInstanceAddedSignal: (self: MockCollectionService, tag: string) -> any,
	GetInstanceRemovedSignal: (self: MockCollectionService, tag: string) -> any,
	HasTag: (self: MockCollectionService, instance: any, tag: string) -> boolean,
}

local MockCollectionService = {}
MockCollectionService.__index = MockCollectionService

function MockCollectionService.new(): MockCollectionService
	local self = setmetatable({
		_tags = {} :: { [string]: { any } },
		_addedSignals = {} :: { [string]: any },
		_removedSignals = {} :: { [string]: any },
	}, MockCollectionService)
	return (self :: any) :: MockCollectionService
end

function MockCollectionService:_ensureTag(tag: string)
	if not self._tags[tag] then
		self._tags[tag] = {}
	end
	if not self._addedSignals[tag] then
		self._addedSignals[tag] = Signal.new()
	end
	if not self._removedSignals[tag] then
		self._removedSignals[tag] = Signal.new()
	end
end

function MockCollectionService:AddTag(instance: any, tag: string)
	self:_ensureTag(tag)
	for _, inst in ipairs(self._tags[tag]) do
		if inst == instance then
			return
		end
	end
	table.insert(self._tags[tag], instance)
	self._addedSignals[tag]:Fire(instance)
end

function MockCollectionService:RemoveTag(instance: any, tag: string)
	self:_ensureTag(tag)
	local tagged = self._tags[tag]
	for i, inst in ipairs(tagged) do
		if inst == instance then
			table.remove(tagged, i)
			self._removedSignals[tag]:Fire(instance)
			return
		end
	end
end

function MockCollectionService:GetTagged(tag: string): { any }
	self:_ensureTag(tag)
	return table.clone(self._tags[tag])
end

function MockCollectionService:GetInstanceAddedSignal(tag: string): any
	self:_ensureTag(tag)
	return self._addedSignals[tag]
end

function MockCollectionService:GetInstanceRemovedSignal(tag: string): any
	self:_ensureTag(tag)
	return self._removedSignals[tag]
end

function MockCollectionService:HasTag(instance: any, tag: string): boolean
	self:_ensureTag(tag)
	for _, inst in ipairs(self._tags[tag]) do
		if inst == instance then
			return true
		end
	end
	return false
end

return MockCollectionService
