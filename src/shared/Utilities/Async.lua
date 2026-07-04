--!strict
-- Riptide/Utilities/Async.lua
-- Wrapper for yielding functions with timeout constraints, retries, and parallel execution

local task = task
if not task then
	task = require("@lune/task")
end
export type AsyncResult<T> = {
	ok: boolean,
	value: T?,
	error: string?,
	timedOut: boolean?,
}

export type AsyncModule = {
	Run: (fn: (...any) -> ...any, timeout: number, ...any) -> ...any,
	Retry: (fn: (...any) -> ...any, maxAttempts: number, delay: number?, ...any) -> ...any,
	Parallel: (fns: { () -> any }, timeout: number?) -> { AsyncResult<any> },
}

local Async = {}
local DEFAULT_PARALLEL_TIMEOUT = 30

--[[
	Executes a function and waits for it to finish. 
	If `timeout` seconds pass before the function finishes, it returns `fallback`.
	
	@param fn The yielding function to execute.
	@param timeout The maximum duration to wait (in seconds).
	@param ... The fallback value(s) to return if the execution times out.
]]
function Async.Run(fn: (...any) -> ...any, timeout: number, ...: any): ...any
	local isYielding = false
	local thread = coroutine.running()
	local isFinished = false
	local isTimedOut = false

	local fallbackArgs = { ... }
	local finalResults = nil

	-- Run the target function asynchronously
	task.spawn(function()
		local results = { pcall(fn) }

		-- If already timed out, discard results silently
		if isTimedOut then
			return
		end

		isFinished = true

		if isYielding then
			local success = table.remove(results, 1)
			if success then
				task.spawn(thread, true, table.unpack(results))
			else
				task.spawn(thread, false, results[1])
			end
		else
			finalResults = results
		end
	end)

	if isFinished then
		local success = table.remove(finalResults, 1)
		if not success then
			error(tostring(finalResults[1]), 2)
		end
		return table.unpack(finalResults)
	end

	isYielding = true

	-- Run the timeout watcher
	task.delay(timeout, function()
		if not isFinished then
			isTimedOut = true
			isFinished = true
			task.spawn(thread, true, table.unpack(fallbackArgs))
		end
	end)

	local yieldedResults = { coroutine.yield() }
	local ok = table.remove(yieldedResults, 1)
	if not ok then
		-- Only throw underlying errors if the function failed before timing out
		error(tostring(yieldedResults[1]), 2)
	end

	return table.unpack(yieldedResults)
end

--[[
	Retries a function up to `maxAttempts` times. If the function throws an error,
	it waits `delay` seconds before the next attempt. Returns the result on success,
	or re-throws the last error if all attempts fail.

	@param fn The function to retry.
	@param maxAttempts Maximum number of attempts (must be >= 1).
	@param delay Optional delay in seconds between retries (default 0).
	@param ... Arguments to pass to fn on each attempt.
]]
function Async.Retry(fn: (...any) -> ...any, maxAttempts: number, delay: number?, ...: any): ...any
	if type(maxAttempts) ~= "number" or maxAttempts < 1 or maxAttempts % 1 ~= 0 then
		error("[Async.Retry] maxAttempts must be an integer >= 1.", 2)
	end

	if delay ~= nil and (type(delay) ~= "number" or delay < 0) then
		error("[Async.Retry] delay must be a non-negative number when provided.", 2)
	end

	local lastError: string = ""
	local args = { ... }

	for attempt = 1, maxAttempts do
		local results = { pcall(fn, table.unpack(args)) }
		local success = table.remove(results, 1)

		if success then
			return table.unpack(results)
		end

		lastError = tostring(results[1])

		if attempt < maxAttempts then
			local waitTime = delay or 0
			if waitTime > 0 then
				task.wait(waitTime)
			end
		end
	end

	error(string.format("[Async.Retry] All %d attempts failed. Last error: %s", maxAttempts, lastError), 2)
end

--[[
		Runs an array of functions in parallel and waits for all to complete.
		If `timeout` is reached, unfinished tasks return an explicit timeout result.

		@param fns Array of zero-argument functions to execute.
		@param timeout Optional maximum duration to wait for all results (in seconds).
		@return Array of explicit result objects in the same order as `fns`.
	]]
function Async.Parallel(fns: { () -> any }, timeout: number?): { AsyncResult<any> }
	local count = #fns
	local results: { AsyncResult<any> } = table.create(count)
	local completed: { boolean } = table.create(count)
	local remaining = count
	local thread = coroutine.running()
	local isYielding = false
	local isDone = false
	local timeoutSeconds = timeout

	if timeoutSeconds == nil then
		timeoutSeconds = DEFAULT_PARALLEL_TIMEOUT
	end

	if timeoutSeconds < 0 then
		error("[Async.Parallel] timeout must be a non-negative number.", 2)
	end

	for i, fn in ipairs(fns) do
		task.spawn(function()
			local ok, result = pcall(fn)
			if isDone then
				return
			end

			completed[i] = true
			if ok then
				results[i] = {
					ok = true,
					value = result,
				}
			else
				results[i] = {
					ok = false,
					error = tostring(result),
				}
			end

			remaining -= 1
			if remaining == 0 and isYielding and not isDone then
				isDone = true
				task.spawn(thread)
			end
		end)
	end

	-- If all finished synchronously before we yielded
	if remaining == 0 then
		return results
	end

	isYielding = true

	-- Timeout safety (defaulted when omitted)
	task.delay(timeoutSeconds, function()
		if not isDone then
			for i = 1, count do
				if not completed[i] then
					results[i] = {
						ok = false,
						error = "[Async.Parallel] Task timed out.",
						timedOut = true,
					}
				end
			end
			isDone = true
			task.spawn(thread)
		end
	end)

	coroutine.yield()
	return results
end

return Async :: AsyncModule
