--!strict
-- Riptide/Utilities/Guard.lua
-- Minimal, lightweight validator module inspired by t.lua.

type Validator = (value: any) -> (boolean, string?)

local Guard = {}

function Guard.Number(min: number?, max: number?): Validator
	return function(value: any)
		if type(value) ~= "number" then
			return false, string.format("Expected number, got %s", typeof(value))
		end
		if value ~= value then
			return false, "unexpected NaN number value"
		end
		if min and value < min then
			return false, string.format("Expected number >= %d, got %d", min, value)
		end
		if max and value > max then
			return false, string.format("Expected number <= %d, got %d", max, value)
		end
		return true
	end
end

function Guard.String(maxLen: number?): Validator
	return function(value: any)
		if type(value) ~= "string" then
			return false, string.format("Expected string, got %s", typeof(value))
		end
		if maxLen and #value > maxLen then
			return false, string.format("Expected string with length <= %d, got length %d", maxLen, #value)
		end
		return true
	end
end

function Guard.Boolean(): Validator
	return function(value: any)
		if type(value) ~= "boolean" then
			return false, string.format("Expected boolean, got %s", typeof(value))
		end
		return true
	end
end

function Guard.Instance(className: string?): Validator
	return function(value: any)
		if typeof(value) ~= "Instance" then
			return false, string.format("Expected Instance, got %s", typeof(value))
		end
		if className and not value:IsA(className) then
			return false, string.format("Expected Instance of class %s, got %s", className, value.ClassName)
		end
		return true
	end
end

function Guard.Table(schema: { [any]: Validator }): Validator
	return function(value: any)
		if type(value) ~= "table" then
			return false, string.format("Expected table, got %s", typeof(value))
		end
		for key, validator in pairs(schema) do
			local ok, err = validator(value[key])
			if not ok then
				return false, string.format("[%s]: %s", tostring(key), err or "validation failed")
			end
		end
		return true
	end
end

function Guard.Optional(validator: Validator): Validator
	return function(value: any)
		if value == nil then
			return true
		end
		return validator(value)
	end
end

function Guard.Enum(values: { any }): Validator
	local set = {}
	for _, val in ipairs(values) do
		set[val] = true
	end
	return function(value: any)
		if not set[value] then
			return false, string.format("Expected one of enum values, got %s", tostring(value))
		end
		return true
	end
end

return Guard
