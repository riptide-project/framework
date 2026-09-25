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
		for _, cancellation in ipairs({ "unregister", "stop", "reset" }) do
			test.case("yielding registration stops its replay after " .. cancellation, function()
				local cs = MockCollectionService.new()
				ComponentService:_init({ CollectionService = cs })
				local first = createMockInstance("first")
				local second = createMockInstance("second")
				cs:AddTag(first, "Audit")
				cs:AddTag(second, "Audit")
				local created, destroyed = 0, 0
				local registered = nil
				local worker = coroutine.create(function()
					registered = ComponentService:_registerTagManually("Audit", {
						new = function()
							created += 1
							if created == 1 then
								coroutine.yield()
							end
							return {
								Destroy = function()
									destroyed += 1
								end,
							}
						end,
					})
				end)
				assert(coroutine.resume(worker))
				check.equal(created, 1)
				if cancellation == "unregister" then
					ComponentService:UnregisterTag("Audit")
				elseif cancellation == "stop" then
					ComponentService:_stop()
				else
					ComponentService:_init({ CollectionService = MockCollectionService.new() })
				end
				assert(coroutine.resume(worker))
				check.equal(coroutine.status(worker), "dead")
				check.equal(registered, false)
				check.equal(created, 1)
				check.equal(destroyed, 1)
				check.equal(ComponentService:Get(first, "Audit"), nil)
				check.equal(ComponentService:Get(second, "Audit"), nil)
				check.equal(next(ComponentService._destroyingConns), nil)
				ComponentService:_stop()
			end)
		end

		test.case("cancelled registration cannot claim a replacement with the same tag", function()
			local cs = MockCollectionService.new()
			ComponentService:_init({ CollectionService = cs })
			local instance = createMockInstance("replaced")
			cs:AddTag(instance, "Audit")
			local destroyedOld, destroyedNew = 0, 0
			local registered = nil
			local replacement = {
				Destroy = function()
					destroyedNew += 1
				end,
			}
			local worker = coroutine.create(function()
				registered = ComponentService:_registerTagManually("Audit", {
					new = function()
						coroutine.yield()
						return {
							Destroy = function()
								destroyedOld += 1
							end,
						}
					end,
				})
			end)
			assert(coroutine.resume(worker))
			ComponentService:UnregisterTag("Audit")
			check.equal(
				ComponentService:_registerTagManually("Audit", {
					new = function()
						return replacement
					end,
				}),
				true
			)
			assert(coroutine.resume(worker))
			check.equal(registered, false)
			check.equal(ComponentService:Get(instance, "Audit"), replacement)
			check.equal(destroyedOld, 1)
			check.equal(destroyedNew, 0)
			ComponentService:_stop()
			check.equal(destroyedNew, 1)
		end)

		test.case("tag replay skips instances removed while another constructor yields", function()
			local cs = MockCollectionService.new()
			ComponentService:_init({ CollectionService = cs })
			local first = createMockInstance("first")
			local removed = createMockInstance("removed")
			cs:AddTag(first, "Audit")
			cs:AddTag(removed, "Audit")
			local created = 0
			local registered = nil
			local worker = coroutine.create(function()
				registered = ComponentService:_registerTagManually("Audit", {
					new = function()
						created += 1
						if created == 1 then
							coroutine.yield()
						end
						return {}
					end,
				})
			end)
			assert(coroutine.resume(worker))
			cs:RemoveTag(removed, "Audit")
			assert(coroutine.resume(worker))
			check.equal(registered, true)
			check.equal(created, 1)
			check.equal(ComponentService:Get(removed, "Audit"), nil)
			ComponentService:_stop()
		end)

		test.case("reinitialization disconnects manually registered tags", function()
			local cs = MockCollectionService.new()
			ComponentService:_init({ CollectionService = cs })
			local count = 0
			ComponentService:_registerTagManually("Audit", {
				new = function()
					count += 1
					return {}
				end,
			})
			ComponentService:_init({ CollectionService = MockCollectionService.new() })
			cs:AddTag(createMockInstance("late"), "Audit")
			check.equal(count, 0)
			ComponentService:_stop()
		end)

		test.case("tag removal during constructor does not resurrect a component", function()
			local cs = MockCollectionService.new()
			ComponentService:_init({ CollectionService = cs })
			local instance = createMockInstance("removed")
			local destroyed = 0
			ComponentService:_registerTagManually("Audit", {
				new = function()
					cs:RemoveTag(instance, "Audit")
					return {
						Destroy = function()
							destroyed += 1
						end,
					}
				end,
			})
			cs:AddTag(instance, "Audit")
			check.equal(ComponentService:Get(instance, "Audit"), nil)
			check.equal(destroyed, 1)
			ComponentService:_stop()
		end)

		test.case("Destroy may re-add a tag without losing the replacement cleanup", function()
			local cs = MockCollectionService.new()
			ComponentService:_init({ CollectionService = cs })
			local instance = createMockInstance("reentrant")
			local created, destroyed = 0, 0
			ComponentService:_registerTagManually("Audit", {
				new = function()
					created += 1
					return {
						Destroy = function()
							destroyed += 1
							if destroyed == 1 then
								cs:AddTag(instance, "Audit")
							end
						end,
					}
				end,
			})
			cs:AddTag(instance, "Audit")
			cs:RemoveTag(instance, "Audit")
			check.equal(created, 2)
			instance.Destroying:Fire()
			check.equal(destroyed, 2)
			ComponentService:_stop()
		end)

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
