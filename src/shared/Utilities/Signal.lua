--!strict
type TaskLibrary = typeof(task)
local task = task
if not task then
	local loadTask: (string) -> TaskLibrary = require
	task = loadTask("@lune/task")
end

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Event<T... = ...any> = {
	Connect: (self: Event<T...>, fn: (T...) -> ()) -> Connection,
	Once: (self: Event<T...>, fn: (T...) -> ()) -> Connection,
	Wait: (self: Event<T...>) -> T...,
}

export type Signal<T... = ...any> = Event<T...> & {
	Fire: (self: Signal<T...>, T...) -> (),
	DisconnectAll: (self: Signal<T...>) -> (),
	Destroy: (self: Signal<T...>) -> (),
}

type Node = {
	older: Node?,
	newer: Node?,
	callback: ((...any) -> ())?,
	handle: ConnectionInternal?,
	waiter: thread?,
	once: boolean,
}

type SignalInternal = {
	_head: Node?,
	_tail: Node?,
	_destroyed: boolean,
}

type ConnectionInternal = Connection & { _node: Node?, _signal: SignalInternal? }

local freeRunner: thread? = nil

local function runHandler(callback: (...any) -> (), ...: any)
	callback(...)
	freeRunner = coroutine.running() :: thread
end

local function runner()
	while true do
		runHandler(coroutine.yield())
	end
end

local function dispatch(callback: (...any) -> (), ...: any)
	local available = freeRunner
	local thread: thread
	if available then
		thread = available
		freeRunner = nil
	else
		thread = coroutine.create(runner)
		assert(coroutine.resume(thread))
	end
	task.spawn(thread, callback, ...)
end

local Connection = {}
Connection.__index = Connection

function Connection.Disconnect(self: ConnectionInternal)
	if not self.Connected then
		return
	end
	self.Connected = false
	local signal = self._signal
	local node = self._node
	self._signal = nil
	self._node = nil
	if not (signal and node) then
		return
	end

	local newer = node.newer
	local older = node.older
	if newer then
		newer.older = older
	else
		signal._head = older
	end
	if older then
		older.newer = newer
	else
		signal._tail = newer
	end
	node.callback = nil
	node.handle = nil
	node.waiter = nil
end

local Signal = {}
Signal.__index = Signal

function Signal.new(): Signal<...any>
	return setmetatable({ _head = nil, _tail = nil, _destroyed = false }, Signal) :: any
end

function Signal.Connect(self: SignalInternal, fn: (...any) -> ()): Connection
	assert(not self._destroyed, "[Signal] Cannot connect to a destroyed signal.")
	assert(type(fn) == "function", "[Signal] Connect requires a function.")
	local handle: ConnectionInternal =
		setmetatable({ Connected = true, _node = nil, _signal = self }, Connection) :: any
	local head = self._head
	local node: Node = { older = head, newer = nil, callback = fn, handle = handle, waiter = nil, once = false }
	handle._node = node
	if head then
		head.newer = node
	else
		self._tail = node
	end
	self._head = node
	return handle
end

function Signal.Once(self: SignalInternal, fn: (...any) -> ()): Connection
	assert(type(fn) == "function", "[Signal] Once requires a function.")
	local connection = Signal.Connect(self, fn)
	local node = (connection :: ConnectionInternal)._node
	if node then
		node.once = true
	end
	return connection
end

function Signal.Fire(self: SignalInternal, ...: any)
	local node = self._head
	while node do
		local nextNode = node.older
		local callback = node.callback
		if callback then
			local waiter = node.waiter
			if node.once or waiter then
				local handle = node.handle
				if handle then
					handle:Disconnect()
				end
			end
			if waiter then
				task.spawn(waiter, true, ...)
			else
				dispatch(callback, ...)
			end
		end
		node = nextNode
	end
end

local function waitResult(ok: boolean, ...: any): ...any
	if not ok then
		error("[Signal] Wait cancelled by DisconnectAll or Destroy.", 2)
	end
	return ...
end

function Signal.Wait(self: SignalInternal): ...any
	local thread = coroutine.running()
	local connection = Signal.Connect(self, function() end)
	local node = (connection :: ConnectionInternal)._node
	if node then
		node.waiter = thread
	end
	return waitResult(coroutine.yield())
end

function Signal.DisconnectAll(self: SignalInternal)
	local head = self._head
	self._head = nil
	self._tail = nil
	local node = head
	while node do
		local handle = node.handle
		if handle then
			handle.Connected = false
			handle._signal = nil
			handle._node = nil
		end
		node.handle = nil
		node.callback = nil
		node = node.older
	end
	node = head
	while node do
		local waiter = node.waiter
		node.waiter = nil
		if waiter and coroutine.status(waiter) == "suspended" then
			task.spawn(waiter, false)
		end
		node = node.older
	end
end

function Signal.Destroy(self: SignalInternal)
	self._destroyed = true
	Signal.DisconnectAll(self)
end

return Signal
