--!strict
-- test/plugins/HealthyPlugin.luau
-- Fixture plugin for PluginIntegration tests.
-- Tracks lifecycle calls in a module-level table so tests can inspect them.

local HealthyPlugin = {}

-- Public lifecycle call log — readable by tests via PublicAPI
HealthyPlugin._log = {} :: { string }

HealthyPlugin.Descriptor = {
	Name = "HealthyPlugin",
	Version = "1.0.0",
	Description = "Fixture plugin for integration tests.",
	Side = "Server" :: "Server" | "Client" | "Shared",
	Dependencies = {},
	PublicAPI = {
		GetLog = function(): { string }
			return HealthyPlugin._log
		end,
	},
}

function HealthyPlugin:Init(sandbox: any)
	table.insert(self._log, "Init")
	-- Verify sandbox API is present
	assert(type(sandbox.Log) == "function", "sandbox.Log must be a function")
	assert(sandbox.PluginName == "HealthyPlugin", "sandbox.PluginName must match descriptor")
	sandbox:Log("Init complete")
end

function HealthyPlugin:Start(sandbox: any)
	table.insert(self._log, "Start")
	sandbox:Log("Start complete")
end

function HealthyPlugin:Stop(sandbox: any)
	table.insert(self._log, "Stop")
	sandbox:Log("Stop called")
end

function HealthyPlugin:Destroy(sandbox: any)
	table.insert(self._log, "Destroy")
	sandbox:Log("Destroy called")
end

return {
	Descriptor = HealthyPlugin.Descriptor,
	Hooks = HealthyPlugin,
}
