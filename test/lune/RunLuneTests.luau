--!strict
local process = require("@lune/process")

local test_files = {
	"../shared/Regression.test",
	"../shared/Async.test",
	"../shared/ComponentService.test",
	"../shared/DirectivePolicy.test",
	"../shared/EventBus.test",
	"../shared/SecurityRegression.test",
	"../shared/ModuleLoader.test",
	"../shared/Network.test",
	"../shared/PlayerLifecycle.test",
	"../shared/PluginIntegration.test",
	"../shared/Riptide.test",
	"../shared/Signal.test",
	"../shared/StateMachine.test",
	"../shared/StateReplication.test",
	"../shared/Trove.test",
}

_G.TestEnv = require("../shared/TestEnv")
local frktest = _G.TestEnv.frktest
local console_reporter = frktest.reporters.console_reporter

console_reporter.init()

for _, file in ipairs(test_files) do
	print("[Lune] Loading: " .. file)
	local suite = require(file)
	if type(suite) == "function" then
		suite()
	end
end

print("----------------------------------------")
print("[Lune] Running loaded test suites...")
print("----------------------------------------")
local success = frktest.run()

if success then
	print("✅ [Lune] All tests passed!")
	-- Suites own their async assertions; parked mock waiters must not keep CI alive.
	process.exit(0)
else
	warn("❌ [Lune] Some tests failed!")
	process.exit(1)
end
