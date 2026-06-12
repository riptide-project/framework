--!strict
-- Riptide/Network.lua
-- High-performance shared Network Manager.
--
-- DESIGN CONTRACT (v0.9.1):
--   • RemoteFunctions are removed entirely.  Use Async.lua over RemoteEvents
--     for request/response patterns instead.
--   • Middleware chains are resolved with a flat for-loop; no closures or
--     recursive xpcall stacks are created per packet.
--   • Handlers are dispatched synchronously in the event callback thread.
--     Developers must not yield inside handlers; use task.defer if needed.

local task = task
if not task then
	task = require("@lune/task")
end

type Callback = (...any) -> any
type HandlerMap = { [string]: { Callback } }
type GuardFunction = (any) -> (boolean, string?)
type Middleware = (...any) -> any

-- ---------------------------------------------------------------------------
-- Public API types
-- ---------------------------------------------------------------------------

export type NetworkDeps = {
	IsServer: boolean,
	EventDispatcher: any,
	UnreliableEventDispatcher: any,
}

export type NetworkAPI = {
	_init: (deps: NetworkDeps) -> (),
	Register: (funcName: string, callback: Callback) -> (),
	RegisterTyped: (funcName: string, guards: { GuardFunction }, callback: Callback) -> (),
	RegisterTypedUnreliable: (funcName: string, guards: { GuardFunction }, callback: Callback) -> (),
	Unregister: (funcName: string, callback: Callback) -> (),
	UseMiddleware: (scope: "server" | "client", middleware: Middleware) -> (),
	ClearMiddlewares: (scope: ("server" | "client")?) -> (),
	-- Server-side fire APIs (nil on client)
	FireClient: ((player: Player, funcName: string, ...any) -> ())?,
	FireAllClients: ((funcName: string, ...any) -> ())?,
	UnreliableFireClient: ((player: Player, funcName: string, ...any) -> ())?,
	UnreliableFireAllClients: ((funcName: string, ...any) -> ())?,
	-- Client-side fire APIs (nil on server)
	FireServer: ((funcName: string, ...any) -> ())?,
	UnreliableFireServer: ((funcName: string, ...any) -> ())?,
}

-- ---------------------------------------------------------------------------
-- Module state
-- ---------------------------------------------------------------------------

local Handlers: HandlerMap = {}
local TypedWrappers: { [Callback]: Callback } = {}

local EventDispatcher: any = nil
local UnreliableEventDispatcher: any = nil
local IS_SERVER: boolean = false
local EventConnection: any = nil
local UnreliableEventConnection: any = nil

local Middlewares = {
	server = {} :: { Middleware },
	client = {} :: { Middleware },
}

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local function disconnectCurrentEventConnection()
	if EventConnection and type(EventConnection.Disconnect) == "function" then
		EventConnection:Disconnect()
	end
	EventConnection = nil
	if UnreliableEventConnection and type(UnreliableEventConnection.Disconnect) == "function" then
		UnreliableEventConnection:Disconnect()
	end
	UnreliableEventConnection = nil
end

--[[
	runServerMiddlewareChain — flat for-loop, zero closure allocation.

	Each middleware in the server stack receives:
	  (player, funcName, args: {any}) -> boolean
	Returning `false` from a middleware short-circuits the chain and suppresses
	handler dispatch.  Any error inside a middleware is caught, logged, and
	also halts the chain.

	The `args` table is passed by reference so middleware can mutate payload
	in place without additional allocations.
]]
local function runServerMiddlewareChain(
	player: any,
	funcName: string,
	args: { any },
	handlers: { Callback }
)
	local mw = Middlewares.server
	for i = 1, #mw do
		local ok, result = xpcall(mw[i], debug.traceback, player, funcName, args)
		if not ok then
			warn(string.format("[Network] Server middleware[%d] error for '%s': %s", i, funcName, tostring(result)))
			return
		end
		-- Middleware may explicitly return false to abort the chain
		if result == false then
			return
		end
	end

	-- SYNCHRONOUS dispatch — no task.spawn; handlers execute in this thread.
	for _, handler in ipairs(handlers) do
		local ok2, err = xpcall(handler, debug.traceback, player, table.unpack(args))
		if not ok2 then
			warn(string.format("[Network] Handler error for '%s': %s", funcName, tostring(err)))
		end
	end
end

--[[
	runClientMiddlewareChain — flat for-loop, zero closure allocation.

	Each middleware receives:
	  (funcName, args: {any}) -> boolean
]]
local function runClientMiddlewareChain(
	funcName: string,
	args: { any },
	handlers: { Callback }
)
	local mw = Middlewares.client
	for i = 1, #mw do
		local ok, result = xpcall(mw[i], debug.traceback, funcName, args)
		if not ok then
			warn(string.format("[Network] Client middleware[%d] error for '%s': %s", i, funcName, tostring(result)))
			return
		end
		if result == false then
			return
		end
	end

	for _, handler in ipairs(handlers) do
		local ok2, err = xpcall(handler, debug.traceback, table.unpack(args))
		if not ok2 then
			warn(string.format("[Network] Handler error for '%s': %s", funcName, tostring(err)))
		end
	end
end

-- ---------------------------------------------------------------------------
-- Network module
-- ---------------------------------------------------------------------------

local Network = {} :: NetworkAPI

function Network._init(deps: NetworkDeps)
	if not deps then
		error("[Network] _init requires a deps table.")
	end

	if type(deps.IsServer) ~= "boolean" then
		error("[Network] _init requires deps.IsServer as boolean.")
	end

	if not deps.EventDispatcher then
		error("[Network] _init requires deps.EventDispatcher.")
	end

	if not deps.UnreliableEventDispatcher then
		error("[Network] _init requires deps.UnreliableEventDispatcher.")
	end

	disconnectCurrentEventConnection()

	IS_SERVER = deps.IsServer
	EventDispatcher = deps.EventDispatcher
	UnreliableEventDispatcher = deps.UnreliableEventDispatcher

	table.clear(Handlers)
	table.clear(TypedWrappers)
	table.clear(Middlewares.server)
	table.clear(Middlewares.client)

	if IS_SERVER then
		EventConnection = EventDispatcher.OnServerEvent:Connect(function(player: Player, funcName: string, ...: any)
			local handlers = Handlers[funcName]
			if handlers then
				if #Middlewares.server == 0 then
					for _, handler in ipairs(handlers) do
						local ok2, err = xpcall(handler, debug.traceback, player, ...)
						if not ok2 then
							warn(string.format("[Network] Handler error for '%s': %s", funcName, tostring(err)))
						end
					end
				else
					runServerMiddlewareChain(player, funcName, { ... }, handlers)
				end
			end
		end)

		if UnreliableEventDispatcher ~= EventDispatcher then
			UnreliableEventConnection = UnreliableEventDispatcher.OnServerEvent:Connect(
				function(player: Player, funcName: string, ...: any)
					local handlers = Handlers[funcName]
					if handlers then
						if #Middlewares.server == 0 then
							for _, handler in ipairs(handlers) do
								local ok2, err = xpcall(handler, debug.traceback, player, ...)
								if not ok2 then
									warn(string.format("[Network] Handler error for '%s': %s", funcName, tostring(err)))
								end
							end
						else
							runServerMiddlewareChain(player, funcName, { ... }, handlers)
						end
					end
				end
			)
		else
			UnreliableEventConnection = nil
		end

		Network.FireClient = function(_player: Player, funcName: string, ...: any)
			EventDispatcher:FireClient(_player, funcName, ...)
		end

		Network.FireAllClients = function(funcName: string, ...: any)
			EventDispatcher:FireAllClients(funcName, ...)
		end

		Network.UnreliableFireClient = function(_player: Player, funcName: string, ...: any)
			UnreliableEventDispatcher:FireClient(_player, funcName, ...)
		end

		Network.UnreliableFireAllClients = function(funcName: string, ...: any)
			UnreliableEventDispatcher:FireAllClients(funcName, ...)
		end

		-- Clear client-side APIs to prevent cross-side leakage
		Network.FireServer = nil
		Network.UnreliableFireServer = nil
	else
		EventConnection = EventDispatcher.OnClientEvent:Connect(function(funcName: string, ...: any)
			local handlers = Handlers[funcName]
			if handlers then
				if #Middlewares.client == 0 then
					for _, handler in ipairs(handlers) do
						local ok2, err = xpcall(handler, debug.traceback, ...)
						if not ok2 then
							warn(string.format("[Network] Handler error for '%s': %s", funcName, tostring(err)))
						end
					end
				else
					runClientMiddlewareChain(funcName, { ... }, handlers)
				end
			end
		end)

		if UnreliableEventDispatcher ~= EventDispatcher then
			UnreliableEventConnection = UnreliableEventDispatcher.OnClientEvent:Connect(
				function(funcName: string, ...: any)
					local handlers = Handlers[funcName]
					if handlers then
						if #Middlewares.client == 0 then
							for _, handler in ipairs(handlers) do
								local ok2, err = xpcall(handler, debug.traceback, ...)
								if not ok2 then
									warn(string.format("[Network] Handler error for '%s': %s", funcName, tostring(err)))
								end
							end
						else
							runClientMiddlewareChain(funcName, { ... }, handlers)
						end
					end
				end
			)
		else
			UnreliableEventConnection = nil
		end

		Network.FireServer = function(funcName: string, ...: any)
			EventDispatcher:FireServer(funcName, ...)
		end

		Network.UnreliableFireServer = function(funcName: string, ...: any)
			UnreliableEventDispatcher:FireServer(funcName, ...)
		end

		-- Clear server-side APIs to prevent cross-side leakage
		Network.FireClient = nil
		Network.FireAllClients = nil
		Network.UnreliableFireClient = nil
		Network.UnreliableFireAllClients = nil
	end
end

function Network.UseMiddleware(scope: "server" | "client", middleware: Middleware)
	if scope ~= "server" and scope ~= "client" then
		error("[Network] UseMiddleware scope must be 'server' or 'client'.", 2)
	end
	if type(middleware) ~= "function" then
		error("[Network] UseMiddleware requires a middleware function.", 2)
	end
	if scope == "server" then
		table.insert(Middlewares.server, middleware)
	else
		table.insert(Middlewares.client, middleware)
	end
end

function Network.ClearMiddlewares(scope: ("server" | "client")?)
	if scope == nil then
		table.clear(Middlewares.server)
		table.clear(Middlewares.client)
		return
	end

	if scope ~= "server" and scope ~= "client" then
		error("[Network] ClearMiddlewares scope must be 'server' or 'client'.", 2)
	end

	if scope == "server" then
		table.clear(Middlewares.server)
	else
		table.clear(Middlewares.client)
	end
end

function Network.Register(funcName: string, callback: Callback)
	if not Handlers[funcName] then
		Handlers[funcName] = {}
	end
	table.insert(Handlers[funcName], callback)
end

function Network.RegisterTyped(funcName: string, guards: { GuardFunction }, callback: Callback)
	local function wrappedCallback(playerOrFirstArg: any, ...)
		local args: { any }
		if IS_SERVER then
			args = { ... }
		else
			args = { playerOrFirstArg, ... }
		end

		for i, guard in ipairs(guards) do
			local val = args[i]
			local ok, err = guard(val)
			if not ok then
				warn(string.format("[Network] Validation failed for event '%s' parameter %d: %s", funcName, i, tostring(err)))
				return
			end
		end

		callback(playerOrFirstArg, ...)
	end

	TypedWrappers[callback] = wrappedCallback
	Network.Register(funcName, wrappedCallback)
end

function Network.RegisterTypedUnreliable(funcName: string, guards: { GuardFunction }, callback: Callback)
	Network.RegisterTyped(funcName, guards, callback)
end

function Network.Unregister(funcName: string, callback: Callback)
	local target = TypedWrappers[callback] or callback
	local handlers = Handlers[funcName]
	if handlers then
		for i, handler in ipairs(handlers) do
			if handler == target then
				table.remove(handlers, i)
				break
			end
		end
		if #handlers == 0 then
			Handlers[funcName] = nil
		end
	end
	if TypedWrappers[callback] then
		TypedWrappers[callback] = nil
	end
end

function Network._clearHandlersForTests()
	table.clear(Handlers)
	table.clear(TypedWrappers)
end

return Network :: NetworkAPI
