--!strict
-- Riptide/Utilities/Signal.lua
-- High-performance Signal implementation with zero-allocation hot paths.
--
-- DESIGN CONTRACT (v0.9.1):
--   :Fire() executes all connected callbacks SYNCHRONOUSLY in the calling
--   thread.  This eliminates per-connection task.spawn overhead in hot paths
--   (e.g. 60 Hz Heartbeat loops).  The framework no longer isolates
--   connections from each other via thread scheduling — the developer is
--   responsible for not yielding inside a :Connect callback.
--
--   :Wait() remains safe: it yields the CALLER's thread and resumes it via
--   task.spawn once the signal fires, which is the only allocation that
--   occurs in that code-path.

local task = task
if not task then
	task = require("@lune/task")
end

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
	_signal: Signal?,
	_fn: ((...any) -> ())?,
	_next: Connection?,
	_thread: thread?,
}

export type Signal = {
	_head: Connection?,
	Connect: (self: Signal, fn: (...any) -> ()) -> Connection,
	Once: (self: Signal, fn: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	Wait: (self: Signal) -> ...any,
	DisconnectAll: (self: Signal) -> (),
	Destroy: (self: Signal) -> (),
}

local Connection = {}
Connection.__index = Connection

function Connection.new(signal: Signal, fn: (...any) -> ()): Connection
	local self = setmetatable({
		Connected = true,
		_signal = signal,
		_fn = fn,
		_next = nil :: Connection?,
		_thread = nil :: thread?,
	}, Connection)
	return (self :: any) :: Connection
end

function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false

	local signal = self._signal
	if signal then
		if signal._head == self then
			signal._head = self._next
		else
			local curr = signal._head
			while curr and curr._next ~= self do
				curr = curr._next
			end
			if curr then
				curr._next = self._next
			end
		end
	end

	-- Prevent memory leaks: clear all references on disconnect
	self._signal = nil
	self._fn = nil
	self._next = nil
end

-- ---------------------------------------------------------------------------

local Signal = {}
Signal.__index = Signal

function Signal.new(): Signal
	local self = setmetatable({
		_head = nil,
	}, Signal)
	return (self :: any) :: Signal
end

function Signal:Connect(fn: (...any) -> ()): Connection
	local connection = Connection.new(self, fn)
	if self._head then
		connection._next = self._head
	end
	self._head = connection
	return connection
end

function Signal:Once(fn: (...any) -> ()): Connection
	local connection: Connection
	connection = self:Connect(function(...)
		connection:Disconnect()
		fn(...)
	end)
	return connection
end

--[[
	:Fire() — ZERO-ALLOCATION HOT PATH.

	Iterates the linked list and calls each connected function directly in the
	current thread.  No closures are created, no tasks are spawned.

	⚠ Do NOT yield inside a :Connect callback.  If you need deferred/async
	  execution, wrap the body of your callback in task.defer/task.spawn
	  yourself, or use the Async module.
]]
function Signal:Fire(...: any)
	local curr = self._head
	while curr do
		-- Read _next BEFORE calling _fn: the callback may Disconnect() `curr`,
		-- which would nil out curr._next and cause the traversal to stop early.
		local nextConn = curr._next
		if curr.Connected and curr._fn then
			curr._fn(...)
		end
		curr = nextConn
	end
end

--[[
	:Wait() — yields the calling coroutine until the signal next fires.
	The single task.spawn here is intentional: it resumes the suspended
	thread from within the signal's synchronous Fire pass without blocking
	the remaining connection callbacks.
]]
function Signal:Wait(): ...any
	local thread = coroutine.running()
	local connection: Connection

	connection = self:Connect(function(...: any)
		connection:Disconnect()
		task.spawn(thread, ...)
	end)
	connection._thread = thread

	return coroutine.yield()
end

function Signal:DisconnectAll()
	local curr = self._head
	while curr do
		local nextConn = curr._next
		-- Resume any threads that are blocked in :Wait()
		if curr._thread then
			task.spawn(curr._thread)
		end
		curr.Connected = false
		curr._signal = nil
		curr._fn = nil
		curr._next = nil
		curr._thread = nil
		curr = nextConn
	end
	(self :: any)._head = nil
end

function Signal:Destroy()
	self:DisconnectAll()
	setmetatable(self :: any, nil)
end

return Signal
