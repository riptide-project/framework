--!strict

type TaskLibrary = typeof(task)
local task = task
if not task then
	local loadTask: (string) -> TaskLibrary = require
	task = loadTask("@lune/task")
end

type Callback = (...any) -> ...any
type HandlerMap = { [string]: { Callback } }
type TypedWrapperMap = { [string]: { [Callback]: { Callback } } }
type GuardFunction = (any) -> (boolean, string?)
type Middleware = (...any) -> any

export type NetworkDeps = {
	IsServer: boolean,
	EventDispatcher: any,
	UnreliableEventDispatcher: any,
}

export type NetworkBaseAPI = {
	_init: (deps: NetworkDeps) -> (),
	Register: (funcName: string, callback: Callback) -> (),
	RegisterTyped: (funcName: string, guards: { GuardFunction }, callback: Callback) -> (),
	RegisterTypedUnreliable: (funcName: string, guards: { GuardFunction }, callback: Callback) -> (),
	Unregister: (funcName: string, callback: Callback) -> (),
	UseMiddleware: (scope: "server" | "client", middleware: Middleware) -> (),
	ClearMiddlewares: (scope: ("server" | "client")?) -> (),
}

export type NetworkServerFireAPI = NetworkBaseAPI & {
	FireClient: (player: Player, funcName: string, ...any) -> (),
	FireAllClients: (funcName: string, ...any) -> (),
	UnreliableFireClient: (player: Player, funcName: string, ...any) -> (),
	UnreliableFireAllClients: (funcName: string, ...any) -> (),
	FireServer: nil,
	UnreliableFireServer: nil,
}

export type NetworkClientFireAPI = NetworkBaseAPI & {
	FireClient: nil,
	FireAllClients: nil,
	UnreliableFireClient: nil,
	UnreliableFireAllClients: nil,
	FireServer: (funcName: string, ...any) -> (),
	UnreliableFireServer: (funcName: string, ...any) -> (),
}

export type TypedServer<TEvents> = NetworkServerFireAPI & TEvents
export type TypedClient<TEvents> = NetworkClientFireAPI & TEvents

export type NetworkServerAPI = NetworkServerFireAPI & {
	TypedServer: <TEvents>() -> TypedServer<TEvents>,
	TypedClient: nil,
}

export type NetworkClientAPI = NetworkClientFireAPI & {
	TypedServer: nil,
	TypedClient: <TEvents>() -> TypedClient<TEvents>,
}

export type NetworkAPI = NetworkBaseAPI & {
	FireClient: ((player: Player, funcName: string, ...any) -> ())?,
	FireAllClients: ((funcName: string, ...any) -> ())?,
	UnreliableFireClient: ((player: Player, funcName: string, ...any) -> ())?,
	UnreliableFireAllClients: ((funcName: string, ...any) -> ())?,
	FireServer: ((funcName: string, ...any) -> ())?,
	UnreliableFireServer: ((funcName: string, ...any) -> ())?,
	TypedServer: (<TEvents>() -> TypedServer<TEvents>)?,
	TypedClient: (<TEvents>() -> TypedClient<TEvents>)?,
}

local Handlers: HandlerMap = {}
local InternalHandlers: HandlerMap = {}
local TypedWrappers: TypedWrapperMap = {}

local EventDispatcher: any = nil
local UnreliableEventDispatcher: any = nil
local IS_SERVER: boolean = false
local EventConnection: any = nil
local UnreliableEventConnection: any = nil

local Middlewares = {
	server = {} :: { Middleware },
	client = {} :: { Middleware },
}

local function isInternalName(funcName: any): boolean
	return type(funcName) == "string" and string.sub(funcName, 1, 10) == "__riptide_"
end

local function assertPublicName(funcName: string)
	if type(funcName) ~= "string" or isInternalName(funcName) then
		error("[Network] Public event name must be a string outside the '__riptide_' namespace.", 3)
	end
end

local function assertInternalName(funcName: string)
	if not isInternalName(funcName) then
		error("[Network] Internal event name must start with '__riptide_'.", 3)
	end
end

local function addHandler(handlersByName: HandlerMap, funcName: string, callback: Callback)
	local handlers = table.clone(handlersByName[funcName] or {})
	table.insert(handlers, callback)
	handlersByName[funcName] = handlers
end

local function removeHandler(handlersByName: HandlerMap, funcName: string, callback: Callback)
	local handlers = handlersByName[funcName]
	if not handlers then
		return
	end
	handlers = table.clone(handlers)
	for i, handler in ipairs(handlers) do
		if handler == callback then
			table.remove(handlers, i)
			break
		end
	end
	if #handlers == 0 then
		handlersByName[funcName] = nil
	else
		handlersByName[funcName] = handlers
	end
end

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

local function getHandlersForIncomingEvent(funcName: any): { Callback }?
	if type(funcName) ~= "string" then
		warn(string.format("[Network] Ignoring packet with non-string event name: %s", typeof(funcName)))
		return nil
	end

	return Handlers[funcName]
end

local function setTypedWrapper(funcName: string, callback: Callback, wrappedCallback: Callback)
	local wrappersForEvent = TypedWrappers[funcName]
	if not wrappersForEvent then
		wrappersForEvent = {}
		TypedWrappers[funcName] = wrappersForEvent
	end
	local wrappers = wrappersForEvent[callback]
	if not wrappers then
		wrappers = {}
		wrappersForEvent[callback] = wrappers
	end
	table.insert(wrappers, wrappedCallback)
end

local function getTypedWrapper(funcName: string, callback: Callback): Callback?
	local wrappersForEvent = TypedWrappers[funcName]
	if not wrappersForEvent then
		return nil
	end
	local wrappers = wrappersForEvent[callback]
	return if wrappers then wrappers[#wrappers] else nil
end

local function clearTypedWrapper(funcName: string, callback: Callback)
	local wrappersForEvent = TypedWrappers[funcName]
	if not wrappersForEvent then
		return
	end
	local wrappers = wrappersForEvent[callback]
	if wrappers then
		table.remove(wrappers)
		if #wrappers == 0 then
			wrappersForEvent[callback] = nil
		end
	end
	if next(wrappersForEvent) == nil then
		TypedWrappers[funcName] = nil
	end
end
local function runServerMiddlewareChain(player: any, funcName: string, args: { [any]: any }, handlers: { Callback })
	local mw = Middlewares.server
	for i = 1, #mw do
		local ok, result = xpcall(mw[i], debug.traceback, player, funcName, args)
		if not ok then
			warn(string.format("[Network] Server middleware[%d] error for '%s': %s", i, funcName, tostring(result)))
			return
		end
		if result == false then
			return
		end
	end

	for _, handler in ipairs(handlers) do
		local ok2, err = xpcall(handler, debug.traceback, player, table.unpack(args, 1, args.n))
		if not ok2 then
			warn(string.format("[Network] Handler error for '%s': %s", funcName, tostring(err)))
		end
	end
end
local function runClientMiddlewareChain(funcName: string, args: { [any]: any }, handlers: { Callback })
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
		local ok2, err = xpcall(handler, debug.traceback, table.unpack(args, 1, args.n))
		if not ok2 then
			warn(string.format("[Network] Handler error for '%s': %s", funcName, tostring(err)))
		end
	end
end

export type NetworkInternalAPI = NetworkAPI & {
	_registerInternal: (funcName: string, callback: Callback) -> (),
	_unregisterInternal: (funcName: string, callback: Callback) -> (),
	_fireInternalClient: ((player: Player, funcName: string, ...any) -> ())?,
	_fireInternalAllClients: ((funcName: string, ...any) -> ())?,
	_fireInternalServer: ((funcName: string, ...any) -> ())?,
	_clearHandlersForTests: () -> (),
}

local Network = {} :: NetworkInternalAPI
local TypedServerProxy: any = nil
local TypedClientProxy: any = nil

local function createTypedServerProxy(): any
	local eventCache: { [string]: Callback } = {}

	return setmetatable({}, {
		__index = function(_self, key: any)
			local networkMember = (Network :: any)[key]
			if networkMember ~= nil then
				return networkMember
			end

			if type(key) ~= "string" then
				return nil
			end

			local eventFn = eventCache[key]
			if eventFn then
				return eventFn
			end

			eventFn = function(player: Player, ...: any)
				local fireClient = Network.FireClient
				if not fireClient then
					error("[Network.TypedServer] FireClient is not available outside server mode.", 2)
				end
				fireClient(player, key, ...)
			end
			eventCache[key] = eventFn
			return eventFn
		end,
	})
end

local function createTypedClientProxy(): any
	local eventCache: { [string]: Callback } = {}

	return setmetatable({}, {
		__index = function(_self, key: any)
			local networkMember = (Network :: any)[key]
			if networkMember ~= nil then
				return networkMember
			end

			if type(key) ~= "string" then
				return nil
			end

			local eventFn = eventCache[key]
			if eventFn then
				return eventFn
			end

			eventFn = function(...: any)
				local fireServer = Network.FireServer
				if not fireServer then
					error("[Network.TypedClient] FireServer is not available outside client mode.", 2)
				end
				fireServer(key, ...)
			end
			eventCache[key] = eventFn
			return eventFn
		end,
	})
end

local function typedServer<TEvents>(): TypedServer<TEvents>
	if not TypedServerProxy then
		TypedServerProxy = createTypedServerProxy()
	end
	return (TypedServerProxy :: any) :: TypedServer<TEvents>
end

local function typedClient<TEvents>(): TypedClient<TEvents>
	if not TypedClientProxy then
		TypedClientProxy = createTypedClientProxy()
	end
	return (TypedClientProxy :: any) :: TypedClient<TEvents>
end

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
	table.clear(InternalHandlers)
	table.clear(TypedWrappers)
	Middlewares.server = {}
	Middlewares.client = {}
	TypedServerProxy = nil
	TypedClientProxy = nil

	if IS_SERVER then
		Network.TypedServer = typedServer :: any
		Network.TypedClient = nil

		EventConnection = EventDispatcher.OnServerEvent:Connect(function(player: Player, funcName: any, ...: any)
			if isInternalName(funcName) then
				local internalHandlers = InternalHandlers[funcName]
				if internalHandlers then
					for _, handler in ipairs(internalHandlers) do
						local ok, err = xpcall(handler, debug.traceback, player, ...)
						if not ok then
							warn(
								string.format("[Network] Internal handler error for '%s': %s", funcName, tostring(err))
							)
						end
					end
				end
				return
			end
			local handlers = getHandlersForIncomingEvent(funcName)
			if not handlers then
				return
			end

			if #Middlewares.server == 0 then
				for _, handler in ipairs(handlers) do
					local ok2, err = xpcall(handler, debug.traceback, player, ...)
					if not ok2 then
						warn(string.format("[Network] Handler error for '%s': %s", funcName, tostring(err)))
					end
				end
			else
				runServerMiddlewareChain(player, funcName, table.pack(...), handlers)
			end
		end)

		if UnreliableEventDispatcher ~= EventDispatcher then
			UnreliableEventConnection = UnreliableEventDispatcher.OnServerEvent:Connect(
				function(player: Player, funcName: any, ...: any)
					if isInternalName(funcName) then
						return
					end
					local handlers = getHandlersForIncomingEvent(funcName)
					if not handlers then
						return
					end

					if #Middlewares.server == 0 then
						for _, handler in ipairs(handlers) do
							local ok2, err = xpcall(handler, debug.traceback, player, ...)
							if not ok2 then
								warn(string.format("[Network] Handler error for '%s': %s", funcName, tostring(err)))
							end
						end
					else
						runServerMiddlewareChain(player, funcName, table.pack(...), handlers)
					end
				end
			)
		else
			UnreliableEventConnection = nil
		end

		Network.FireClient = function(_player: Player, funcName: string, ...: any)
			assertPublicName(funcName)
			EventDispatcher:FireClient(_player, funcName, ...)
		end

		Network.FireAllClients = function(funcName: string, ...: any)
			assertPublicName(funcName)
			EventDispatcher:FireAllClients(funcName, ...)
		end

		Network.UnreliableFireClient = function(_player: Player, funcName: string, ...: any)
			assertPublicName(funcName)
			UnreliableEventDispatcher:FireClient(_player, funcName, ...)
		end

		Network.UnreliableFireAllClients = function(funcName: string, ...: any)
			assertPublicName(funcName)
			UnreliableEventDispatcher:FireAllClients(funcName, ...)
		end

		Network._fireInternalClient = function(player: Player, funcName: string, ...: any)
			assertInternalName(funcName)
			EventDispatcher:FireClient(player, funcName, ...)
		end

		Network._fireInternalAllClients = function(funcName: string, ...: any)
			assertInternalName(funcName)
			EventDispatcher:FireAllClients(funcName, ...)
		end
		Network._fireInternalServer = nil

		Network.FireServer = nil
		Network.UnreliableFireServer = nil
	else
		Network.TypedServer = nil
		Network.TypedClient = typedClient :: any

		EventConnection = EventDispatcher.OnClientEvent:Connect(function(funcName: any, ...: any)
			if isInternalName(funcName) then
				local internalHandlers = InternalHandlers[funcName]
				if internalHandlers then
					for _, handler in ipairs(internalHandlers) do
						local ok, err = xpcall(handler, debug.traceback, ...)
						if not ok then
							warn(
								string.format("[Network] Internal handler error for '%s': %s", funcName, tostring(err))
							)
						end
					end
				end
				return
			end
			local handlers = getHandlersForIncomingEvent(funcName)
			if not handlers then
				return
			end

			if #Middlewares.client == 0 then
				for _, handler in ipairs(handlers) do
					local ok2, err = xpcall(handler, debug.traceback, ...)
					if not ok2 then
						warn(string.format("[Network] Handler error for '%s': %s", funcName, tostring(err)))
					end
				end
			else
				runClientMiddlewareChain(funcName, table.pack(...), handlers)
			end
		end)

		if UnreliableEventDispatcher ~= EventDispatcher then
			UnreliableEventConnection = UnreliableEventDispatcher.OnClientEvent:Connect(
				function(funcName: any, ...: any)
					if isInternalName(funcName) then
						return
					end
					local handlers = getHandlersForIncomingEvent(funcName)
					if not handlers then
						return
					end

					if #Middlewares.client == 0 then
						for _, handler in ipairs(handlers) do
							local ok2, err = xpcall(handler, debug.traceback, ...)
							if not ok2 then
								warn(string.format("[Network] Handler error for '%s': %s", funcName, tostring(err)))
							end
						end
					else
						runClientMiddlewareChain(funcName, table.pack(...), handlers)
					end
				end
			)
		else
			UnreliableEventConnection = nil
		end

		Network.FireServer = function(funcName: string, ...: any)
			assertPublicName(funcName)
			EventDispatcher:FireServer(funcName, ...)
		end

		Network.UnreliableFireServer = function(funcName: string, ...: any)
			assertPublicName(funcName)
			UnreliableEventDispatcher:FireServer(funcName, ...)
		end

		Network._fireInternalServer = function(funcName: string, ...: any)
			assertInternalName(funcName)
			EventDispatcher:FireServer(funcName, ...)
		end
		Network._fireInternalClient = nil
		Network._fireInternalAllClients = nil

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
		local updated = table.clone(Middlewares.server)
		table.insert(updated, middleware)
		Middlewares.server = updated
	else
		local updated = table.clone(Middlewares.client)
		table.insert(updated, middleware)
		Middlewares.client = updated
	end
end

function Network.ClearMiddlewares(scope: ("server" | "client")?)
	if scope == nil then
		Middlewares.server = {}
		Middlewares.client = {}
		return
	end

	if scope ~= "server" and scope ~= "client" then
		error("[Network] ClearMiddlewares scope must be 'server' or 'client'.", 2)
	end

	if scope == "server" then
		Middlewares.server = {}
	else
		Middlewares.client = {}
	end
end

function Network.Register(funcName: string, callback: Callback)
	assertPublicName(funcName)
	addHandler(Handlers, funcName, callback)
end

function Network.RegisterTyped(funcName: string, guards: { GuardFunction }, callback: Callback)
	assertPublicName(funcName)
	local function wrappedCallback(...)
		local args = table.pack(...)
		local offset = if IS_SERVER then 1 else 0

		for i, guard in ipairs(guards) do
			local val = args[i + offset]
			local ok, err = guard(val)
			if not ok then
				warn(
					string.format(
						"[Network] Validation failed for event '%s' parameter %d: %s",
						funcName,
						i,
						tostring(err)
					)
				)
				return
			end
		end

		callback(...)
	end

	setTypedWrapper(funcName, callback, wrappedCallback)
	Network.Register(funcName, wrappedCallback)
end

function Network.RegisterTypedUnreliable(funcName: string, guards: { GuardFunction }, callback: Callback)
	Network.RegisterTyped(funcName, guards, callback)
end

function Network.Unregister(funcName: string, callback: Callback)
	assertPublicName(funcName)
	local target = getTypedWrapper(funcName, callback) or callback
	removeHandler(Handlers, funcName, target)
	clearTypedWrapper(funcName, callback)
end

function Network._registerInternal(funcName: string, callback: Callback)
	assertInternalName(funcName)
	addHandler(InternalHandlers, funcName, callback)
end

function Network._unregisterInternal(funcName: string, callback: Callback)
	assertInternalName(funcName)
	removeHandler(InternalHandlers, funcName, callback)
end

function Network._clearHandlersForTests()
	table.clear(Handlers)
	table.clear(InternalHandlers)
	table.clear(TypedWrappers)
end

return Network :: NetworkInternalAPI
