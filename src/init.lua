--!strict
-- Riptide Framework Entry Point
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local AsyncModule = require(script.shared.Utilities.Async)
local ComponentServiceModule = require(script.shared.ComponentService)
local EventBusModule = require(script.shared.Utilities.EventBus)
local GuardModule = require(script.shared.Utilities.Guard)
local ModuleLoader = require(script.shared.ModuleLoader)
local NetworkModule = require(script.shared.Network)
local PlayerLifecycleModule = require(script.shared.PlayerLifecycle)
local PluginManagerModule = require(script.shared.PluginManager)
local SignalModule = require(script.shared.Utilities.Signal)
local StateMachineModule = require(script.shared.StateMachine)
local StateReplicationModule = require(script.shared.StateReplication)
local TroveModule = require(script.shared.Utilities.Trove)

local IS_SERVER = RunService:IsServer()
local REMOTE_WAIT_TIMEOUT = 10

export type RiptideCore = {
	Network: NetworkModule.NetworkAPI,
	Signal: typeof(SignalModule),
	Async: typeof(AsyncModule),
	ComponentService: ComponentServiceModule.ComponentServiceAPI,
	State: StateReplicationModule.StateReplicationAPI,
	StateMachine: typeof(StateMachineModule),
	PlayerLifecycle: PlayerLifecycleModule.PlayerLifecycleAPI,
	Plugins: PluginManagerModule.PluginManagerAPI,
	Trove: typeof(TroveModule),
	EventBus: typeof(EventBusModule),
	Guard: typeof(GuardModule),
	GetModule: (name: string) -> any,
	_modules: { [string]: any },
	_moduleAliases: { [string]: string | false },
}

export type RiptideServer = {
	Network: NetworkModule.NetworkServerAPI,
	Signal: typeof(SignalModule),
	Async: typeof(AsyncModule),
	ComponentService: ComponentServiceModule.ComponentServiceAPI,
	State: StateReplicationModule.StateReplicationServerAPI,
	StateMachine: typeof(StateMachineModule),
	PlayerLifecycle: PlayerLifecycleModule.PlayerLifecycleAPI,
	Plugins: PluginManagerModule.PluginManagerAPI,
	Trove: typeof(TroveModule),
	EventBus: typeof(EventBusModule),
	Guard: typeof(GuardModule),
	GetModule: (name: string) -> any,
	GetService: (name: string) -> any,
	Launch: (config: ModuleLoader.Config) -> (),
}

export type RiptideClient = {
	Network: NetworkModule.NetworkClientAPI,
	Signal: typeof(SignalModule),
	Async: typeof(AsyncModule),
	ComponentService: ComponentServiceModule.ComponentServiceAPI,
	State: StateReplicationModule.StateReplicationClientAPI,
	StateMachine: typeof(StateMachineModule),
	Plugins: PluginManagerModule.PluginManagerAPI,
	Trove: typeof(TroveModule),
	EventBus: typeof(EventBusModule),
	Guard: typeof(GuardModule),
	GetModule: (name: string) -> any,
	GetController: (name: string) -> any,
	Launch: (config: ModuleLoader.Config) -> (),
}

export type Riptide = RiptideCore & {
	Server: RiptideServer?,
	Client: RiptideClient?,
	GetService: ((name: string) -> any)?,
	GetController: ((name: string) -> any)?,
}

local Riptide = {} :: Riptide
local isLaunched = false

Riptide._modules = {} :: { [string]: any }
Riptide._moduleAliases = {} :: { [string]: string | false }
Riptide.Signal = SignalModule
Riptide.Async = AsyncModule
Riptide.ComponentService = ComponentServiceModule
Riptide.State = StateReplicationModule
Riptide.StateMachine = StateMachineModule
Riptide.PlayerLifecycle = PlayerLifecycleModule
Riptide.Trove = TroveModule
Riptide.EventBus = EventBusModule
Riptide.Guard = GuardModule

function Riptide.GetModule(name: string): any
	local module = Riptide._modules[name]
	if module then
		return module
	end

	local aliasValue = Riptide._moduleAliases[name]
	if aliasValue == false then
		warn(
			string.format(
				"🌊 [Riptide] Ambiguous module alias '%s'. Use canonical path id (example: 'Folder/%s').",
				name,
				name
			)
		)
		return nil
	end

	if type(aliasValue) == "string" then
		module = Riptide._modules[aliasValue]
		if module then
			return module
		end
	end

	if not module then
		warn(string.format("🌊 [Riptide] Failed to get module: '%s' is not registered!", name))
	end
	return module
end

-- Initialize ComponentService with real CollectionService
ComponentServiceModule:_init({
	CollectionService = CollectionService,
})

-- Initialize Network with real Remotes
local Shared = script.shared
local Remotes: Folder
local EventDispatcher: RemoteEvent
local UnreliableEventDispatcher: UnreliableRemoteEvent

local function waitForChildOrError(parent: Instance, childName: string, timeoutSeconds: number): Instance
	local child = parent:WaitForChild(childName, timeoutSeconds)
	if child then
		return child
	end

	error(
		string.format(
			"🌊 [Riptide] Timed out after %.1fs waiting for '%s' under '%s'.",
			timeoutSeconds,
			childName,
			parent:GetFullName()
		)
	)
end

if IS_SERVER then
	local existingRemotes = Shared:FindFirstChild("Remotes")
	if not existingRemotes then
		Remotes = Instance.new("Folder")
		Remotes.Name = "Remotes"
		Remotes.Parent = Shared

		EventDispatcher = Instance.new("RemoteEvent")
		EventDispatcher.Name = "EventDispatcher"
		EventDispatcher.Parent = Remotes

		UnreliableEventDispatcher = Instance.new("UnreliableRemoteEvent")
		UnreliableEventDispatcher.Name = "UnreliableEventDispatcher"
		UnreliableEventDispatcher.Parent = Remotes
	else
		Remotes = existingRemotes :: Folder
		EventDispatcher = waitForChildOrError(Remotes, "EventDispatcher", REMOTE_WAIT_TIMEOUT) :: RemoteEvent
		UnreliableEventDispatcher =
			waitForChildOrError(Remotes, "UnreliableEventDispatcher", REMOTE_WAIT_TIMEOUT) :: UnreliableRemoteEvent
	end
else
	Remotes = waitForChildOrError(Shared, "Remotes", REMOTE_WAIT_TIMEOUT) :: Folder
	EventDispatcher = waitForChildOrError(Remotes, "EventDispatcher", REMOTE_WAIT_TIMEOUT) :: RemoteEvent
	UnreliableEventDispatcher =
		waitForChildOrError(Remotes, "UnreliableEventDispatcher", REMOTE_WAIT_TIMEOUT) :: UnreliableRemoteEvent
end

NetworkModule._init({
	IsServer = IS_SERVER,
	EventDispatcher = EventDispatcher,
	UnreliableEventDispatcher = UnreliableEventDispatcher,
})

StateReplicationModule:_init({
	IsServer = IS_SERVER,
	Network = NetworkModule,
})

if IS_SERVER then
	PlayerLifecycleModule:_init({
		Players = Players,
		StateReplication = StateReplicationModule,
		OnPlayerAdded = function(player)
			PluginManagerModule:NotifyPlayerAdded(player)
		end,
		OnPlayerRemoving = function(player)
			PluginManagerModule:NotifyPlayerRemoving(player)
		end,
	})
end

-- Initialize PluginManager with all core dependencies
PluginManagerModule:_init({
	Network = NetworkModule,
	State = StateReplicationModule,
	Signal = SignalModule,
	ComponentService = ComponentServiceModule,
	IsServer = IS_SERVER,
	Async = AsyncModule,
})

Riptide.Network = NetworkModule
Riptide.Plugins = PluginManagerModule

-- Wire up side-specific initializers and lookup guards
local function launch(sideName: "Server" | "Client", config: ModuleLoader.Config)
	if isLaunched then
		warn(string.format("🌊 [Riptide] %s framework already launched!", sideName))
		return
	end

	isLaunched = true
	ModuleLoader.Launch(sideName, Riptide, config)
end

if IS_SERVER then
	Riptide.Server = {
		Network = (NetworkModule :: any) :: NetworkModule.NetworkServerAPI,
		Signal = SignalModule,
		Async = AsyncModule,
		ComponentService = ComponentServiceModule,
		State = (StateReplicationModule :: any) :: StateReplicationModule.StateReplicationServerAPI,
		StateMachine = StateMachineModule,
		PlayerLifecycle = PlayerLifecycleModule,
		Plugins = PluginManagerModule,
		Trove = TroveModule,
		EventBus = EventBusModule,
		Guard = GuardModule,
		GetModule = Riptide.GetModule,
		GetService = Riptide.GetModule,
		Launch = function(config: ModuleLoader.Config)
			launch("Server", config)
		end,
	}
	Riptide.GetService = Riptide.GetModule
	Riptide.GetController = function(_name: string)
		error("🌊 [Riptide] GetController is not available on the server. Use GetService instead.")
	end
else
	Riptide.Client = {
		Network = (NetworkModule :: any) :: NetworkModule.NetworkClientAPI,
		Signal = SignalModule,
		Async = AsyncModule,
		ComponentService = ComponentServiceModule,
		State = (StateReplicationModule :: any) :: StateReplicationModule.StateReplicationClientAPI,
		StateMachine = StateMachineModule,
		Plugins = PluginManagerModule,
		Trove = TroveModule,
		EventBus = EventBusModule,
		Guard = GuardModule,
		GetModule = Riptide.GetModule,
		GetController = Riptide.GetModule,
		Launch = function(config: ModuleLoader.Config)
			launch("Client", config)
		end,
	}
	Riptide.GetController = Riptide.GetModule
	Riptide.GetService = function(_name: string)
		error("🌊 [Riptide] GetService is not available on the client. Use GetController instead.")
	end
end

return Riptide
