--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")

local frktest = require(Packages:WaitForChild("frktest"))
local console_reporter = frktest.reporters.console_reporter

console_reporter.init()

local loadFailures: { string } = {}

local function loadTests(parent: Instance)
	for _, child in parent:GetChildren() do
		if child:IsA("ModuleScript") then
			if string.match(child.Name, "%.test$") or string.match(child.Name, "%.spec$") then
				print("[Client QA] Loading: " .. child:GetFullName())
				local ok, err = pcall(function()
					local suite = require(child)
					if type(suite) == "function" then
						suite()
					end
				end)

				if not ok then
					local message =
						string.format("[Client QA] Failed to load %s: %s", child:GetFullName(), tostring(err))
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

-- Optional: Wait a brief moment to ensure client state is fully initialized before spamming output
task.wait(1)

print("========================================")
print("     [Client] QA Test Runner Started    ")
print("========================================")

-- Load Shared Tests
local sharedTests = ReplicatedStorage:FindFirstChild("SharedTests")
if sharedTests then
	loadTests(sharedTests)
end

-- Load Client Tests
loadTests(script.Parent)

print("----------------------------------------")
print("[Client] Running loaded test suites...")
print("----------------------------------------")

local testSuccess = frktest.run()
local success = testSuccess and #loadFailures == 0

print("========================================")
if success then
	print("✅ [Client] All tests passed!")
else
	for _, failure in ipairs(loadFailures) do
		warn(failure)
	end
	warn("❌ [Client] Some tests failed!")
end
print("========================================")
