--!strict
-- Riptide/Utilities/EventBus.lua
-- General purpose EventBus for inter-module pub/sub.

type Callback = (...any) -> any
type UnsubscribeFn = () -> ()

export type EventBus = {
	Emit: <T...>(self: EventBus, name: string, T...) -> (),
	On: <T...>(self: EventBus, name: string, callback: (T...) -> any) -> UnsubscribeFn,
	Once: <T...>(self: EventBus, name: string, callback: (T...) -> any) -> UnsubscribeFn,
	Clear: (self: EventBus) -> (),
	Destroy: (self: EventBus) -> (),
}

type EventBusInternal = EventBus & {
	_listeners: { [string]: { Callback } },
	_label: string,
}

local EventBus = {}
EventBus.__index = EventBus

function EventBus.new(label: string?): EventBus
	local self = setmetatable({
		_listeners = {} :: { [string]: { Callback } },
		_label = label or "[EventBus]",
	}, EventBus)
	return (self :: any) :: EventBus
end

function EventBus:Emit(name: string, ...: any)
	local list = self._listeners[name]
	if not list then
		return
	end

	-- Snapshot to handle mid-iteration unsubscribes safely
	local snapshot = table.clone(list)
	local args = { ... }
	for i = 1, #snapshot do
		local listener = snapshot[i]
		local ok, err = xpcall(function()
			listener(table.unpack(args))
		end, debug.traceback)
		if not ok then
			warn(string.format("%s Error in listener for '%s': %s", self._label, name, tostring(err)))
		end
	end
end

function EventBus:On(name: string, callback: Callback): UnsubscribeFn
	if not self._listeners[name] then
		self._listeners[name] = {}
	end
	table.insert(self._listeners[name], callback)

	return function()
		local list = self._listeners[name]
		if not list then
			return
		end
		for i = #list, 1, -1 do
			if list[i] == callback then
				table.remove(list, i)
				break
			end
		end
		if #list == 0 then
			self._listeners[name] = nil
		end
	end
end

function EventBus:Once(name: string, callback: Callback): UnsubscribeFn
	local unsubscribe: UnsubscribeFn? = nil
	unsubscribe = self:On(name, function(...: any)
		local currentUnsubscribe = unsubscribe
		if currentUnsubscribe then
			currentUnsubscribe()
			unsubscribe = nil
		end
		callback(...)
	end)

	return function()
		local currentUnsubscribe = unsubscribe
		if currentUnsubscribe then
			currentUnsubscribe()
			unsubscribe = nil
		end
	end
end

function EventBus:Clear()
	table.clear(self._listeners)
end

function EventBus:Destroy()
	self:Clear()
end

return {
	new = EventBus.new,
}
