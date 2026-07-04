--!strict
-- ComponentService Test Suite (frktest)

local Env = _G.TestEnv or require(script.Parent.TestEnv)
local task = Env.task

local frktest = Env.frktest
local test = frktest.test
local check = frktest.assert.check

local ComponentService = Env.RiptideShared.ComponentService
local MockCollectionService = Env.Mocks.MockCollectionService
local Signal = Env.RiptideShared.Signal

local function createMockInstance(name: string): any
	return {
		Name = name,
		Destroying = Signal.new(),
	}
end

return function()
	test.suite("ComponentService", function()
		test.case("should link tags to component wrappers via Get", function()
			-- Reset state
			local cs = ComponentService :: any
			cs._isStarted = false
			table.clear(cs._tagListeners)

			local mockInstance = { Name = "TestPart" }
			local TestTag = "TestTagComponent"
			local testWrapper = { Destroy = function() end }

			-- Manually register a component
			cs._registry[mockInstance] = {}
			cs._registry[mockInstance][TestTag] = testWrapper

			local fetched = ComponentService:Get(mockInstance :: any, nil)
			check.equal(fetched, testWrapper)

			-- Cleanup
			cs._registry[mockInstance] = nil
		end)

		test.case("should support tag-specific Get lookup", function()
			local cs = ComponentService :: any
			cs._isStarted = false
			table.clear(cs._tagListeners)

			local mockInstance = { Name = "MultiTagPart" }
			local Tag1 = "TagAlpha"
			local Tag2 = "TagBeta"

			local wrapper1 = { name = "alpha" }
			local wrapper2 = { name = "beta" }

			cs._registry[mockInstance] = {}
			cs._registry[mockInstance][Tag1] = wrapper1
			cs._registry[mockInstance][Tag2] = wrapper2

			check.equal(ComponentService:Get(mockInstance :: any, Tag1), wrapper1)
			check.equal(ComponentService:Get(mockInstance :: any, Tag2), wrapper2)

			-- Cleanup
			cs._registry[mockInstance] = nil
		end)

		test.case("should return nil for ambiguous Get without tag", function()
			local cs = ComponentService :: any
			local previousSuppress = cs._suppressWarnings
			cs._suppressWarnings = true
			cs._isStarted = false
			table.clear(cs._tagListeners)

			local mockInstance = { Name = "AmbiguousPart" }
			cs._registry[mockInstance] = {
				TagAlpha = { name = "alpha" },
				TagBeta = { name = "beta" },
			}

			check.equal(ComponentService:Get(mockInstance :: any, nil), nil)

			cs._registry[mockInstance] = nil
			cs._suppressWarnings = previousSuppress
		end)

		test.case("should return nil for unregistered instance", function()
			local mockInstance = { Name = "UnknownPart" }
			local fetched = ComponentService:Get(mockInstance :: any, nil)
			check.equal(fetched, nil)
		end)

		test.case("should cleanup component when tag is removed", function()
			local cs = ComponentService :: any
			local mockInstance = { Name = "CleanupPart" }
			local TestTag = "MemoryLeakComponent"

			local destroyedCalled = false
			local testWrapper = {
				Destroy = function()
					destroyedCalled = true
				end,
			}

			cs._registry[mockInstance] = {}
			cs._registry[mockInstance][TestTag] = testWrapper

			-- Simulate cleanup (what happens on tag removal)
			local components = cs._registry[mockInstance]
			if components then
				local componentObj = components[TestTag]
				if componentObj then
					if type(componentObj.Destroy) == "function" then
						pcall(componentObj.Destroy, componentObj)
					end
					components[TestTag] = nil
				end
			end

			check.equal(destroyedCalled, true)
			check.equal(ComponentService:Get(mockInstance :: any, nil), nil)

			-- Cleanup
			cs._registry[mockInstance] = nil
		end)

		test.case("should prevent duplicate _start calls", function()
			local cs = ComponentService :: any
			local previousSuppress = cs._suppressWarnings
			cs._suppressWarnings = true
			cs._isStarted = true

			-- Second _start should be silently ignored
			-- We can't easily test the warn output, but we verify it doesn't error
			local ok = pcall(function()
				-- Create an empty mock folder-like object
				-- Since _start checks _isStarted first, it should return before using the folder
				ComponentService:_start({} :: any)
			end)
			check.equal(ok, true)

			-- Reset for other tests
			cs._isStarted = false
			cs._suppressWarnings = previousSuppress
		end)

		test.case("should create and cleanup manual components through CollectionService signals", function()
			local mockCollectionService = MockCollectionService.new()
			ComponentService:_init({
				CollectionService = mockCollectionService,
			})

			local destroyedCount = 0
			local ComponentClass = {
				new = function(instance)
					return {
						instance = instance,
						Destroy = function()
							destroyedCount += 1
						end,
					}
				end,
			}

			local instance = createMockInstance("TaggedPart")
			ComponentService:_registerTagManually("TestComponent", ComponentClass)
			mockCollectionService:AddTag(instance, "TestComponent")

			local component = ComponentService:Get(instance, "TestComponent") :: any
			check.not_nil(component)
			check.equal(component.instance, instance)

			mockCollectionService:RemoveTag(instance, "TestComponent")

			check.equal(destroyedCount, 1)
			check.equal(ComponentService:Get(instance, "TestComponent"), nil)
		end)

		test.case("should reset registered components and listeners on init", function()
			local mockCollectionService = MockCollectionService.new()
			ComponentService:_init({
				CollectionService = mockCollectionService,
			})

			local destroyedCount = 0
			local ComponentClass = {
				new = function(_instance)
					return {
						Destroy = function()
							destroyedCount += 1
						end,
					}
				end,
			}

			local instance = createMockInstance("ResetPart")
			ComponentService:_registerTagManually("ResetComponent", ComponentClass)
			mockCollectionService:AddTag(instance, "ResetComponent")
			check.not_nil(ComponentService:Get(instance, "ResetComponent"))

			ComponentService:_init({
				CollectionService = MockCollectionService.new(),
			})

			check.equal(destroyedCount, 1)
			check.equal(ComponentService:Get(instance, "ResetComponent"), nil)
			check.equal(next((ComponentService :: any)._tagListeners), nil)
		end)

		test.case("should unregister a tag for multiple instances without skipped cleanup", function()
			local mockCollectionService = MockCollectionService.new()
			ComponentService:_init({
				CollectionService = mockCollectionService,
			})

			local destroyedCount = 0
			local ComponentClass = {
				new = function(_instance)
					return {
						Destroy = function()
							destroyedCount += 1
						end,
					}
				end,
			}

			local first = createMockInstance("FirstPart")
			local second = createMockInstance("SecondPart")
			ComponentService:_registerTagManually("MultiInstanceComponent", ComponentClass)
			mockCollectionService:AddTag(first, "MultiInstanceComponent")
			mockCollectionService:AddTag(second, "MultiInstanceComponent")

			check.not_nil(ComponentService:Get(first, "MultiInstanceComponent"))
			check.not_nil(ComponentService:Get(second, "MultiInstanceComponent"))

			ComponentService:UnregisterTag("MultiInstanceComponent")

			check.equal(destroyedCount, 2)
			check.equal(ComponentService:Get(first, "MultiInstanceComponent"), nil)
			check.equal(ComponentService:Get(second, "MultiInstanceComponent"), nil)
		end)
	end)
end
