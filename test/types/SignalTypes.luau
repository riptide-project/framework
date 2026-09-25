--!strict
-- Static-only fixture; the Studio test runner ignores modules without .test/.spec.
local SignalModule = require(script.Parent.Parent.Riptide.shared.Utilities.Signal)
local TroveModule = require(script.Parent.Parent.Riptide.shared.Utilities.Trove)

type Signal<T...> = SignalModule.Signal<T...>
type Event<T...> = SignalModule.Event<T...>

local changed: Signal<number, string?> = SignalModule.new()
local observed: Event<number, string?> = changed
local empty: Signal<> = SignalModule.new()
empty:Fire()
local dynamic = SignalModule.new()
dynamic:Fire(1, "allowed without a type annotation")

observed:Connect(function(amount, label)
	local numberValue: number = amount
	local optionalLabel: string? = label
	return numberValue, optionalLabel
end)

changed:Fire(1, nil)
local value: number, label: string? = observed:Wait()
local _unusedValue, _unusedLabel = value, label

local trove = TroveModule.new()
trove:Connect(observed, function(amount, receivedLabel)
	local numberValue: number = amount
	local optionalLabel: string? = receivedLabel
	print(numberValue, optionalLabel)
end)

return changed
