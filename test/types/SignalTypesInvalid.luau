--!strict
-- Static-only negative fixture. Each bad use must produce a type error.
local SignalModule = require(script.Parent.Parent.Riptide.shared.Utilities.Signal)
local TroveModule = require(script.Parent.Parent.Riptide.shared.Utilities.Trove)

local changed: SignalModule.Signal<number, string?> = SignalModule.new()
local observed: SignalModule.Event<number, string?> = changed

changed:Fire("wrong", nil)
observed:Fire(1, nil)
observed:Connect(function(amount: string, _label: string?)
	print(amount)
end)
local wrongResult: string = observed:Wait()
print(wrongResult)
TroveModule.new():Connect(observed, function(amount: string)
	print(amount)
end)

return changed
