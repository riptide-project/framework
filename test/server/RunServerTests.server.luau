--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local frktest = require(Packages:WaitForChild("frktest"))
local console_reporter = frktest.reporters.console_reporter

-- Initialize Riptide immediately so Remotes are created and start replicating to Client
local _Riptide = require(ReplicatedStorage:WaitForChild("Riptide"))

-- Yield server for 1 second to allow ReplicatedStorage dynamic instances to reach Client
-- before we freeze the server thread with intensive synchronous tests.
task.wait(1)

console_reporter.init()

local loadFailures: { string } = {}

local function loadTests(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("ModuleScript") then
			if string.match(child.Name, "%.test$") or string.match(child.Name, "%.spec$") then
				print("[Server QA] Loading: " .. child:GetFullName())
				local ok, err = pcall(function()
					local suite = require(child)
					if type(suite) == "function" then
						suite()
					end
				end)

				if not ok then
					local message =
						string.format("[Server QA] Failed to load %s: %s", child:GetFullName(), tostring(err))
					table.insert(loadFailures, message)
					warn(message)
				end
			end
		end

		if child:IsA("Folder") or child:IsA("ModuleScript") then
			loadTests(child)
		end
	end
end

print("========================================")
print("     [Server] QA Test Runner Started    ")
print("========================================")

-- Load Shared Tests
local sharedTests = ReplicatedStorage:FindFirstChild("SharedTests")
if sharedTests then
	loadTests(sharedTests)
end

-- Load Server Tests
loadTests(script.Parent)

print("----------------------------------------")
print("[Server] Running loaded test suites...")
print("----------------------------------------")

local testSuccess = frktest.run()
local success = testSuccess and #loadFailures == 0

print("========================================")
if success then
	print("✅ [Server] All tests passed!")
else
	for _, failure in ipairs(loadFailures) do
		warn(failure)
	end
	warn("❌ [Server] Some tests failed!")
end
print("========================================")
