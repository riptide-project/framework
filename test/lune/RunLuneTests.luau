--!strict

local test_files = {
	"../shared/Async.test",
	"../shared/Chaos.test",
	"../shared/ComponentService.test",
	"../shared/DirectivePolicy.test",
	"../shared/EventBus.test",
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
else
	warn("❌ [Lune] Some tests failed!")
end
