---
slug: versions/0.9.0-maelstrom.3/api/utilities
title: Utilities
description: Trove, Signal, Async, EventBus, and Guard — bundled with Riptide.
---


Riptide bundles five essential utility modules so you don't need separate dependencies for the most common patterns:

| Utility | Access | Purpose |
|---|---|---|
| `Async` | `Riptide.Async` | Timeouts, retries, parallel execution |
| `Signal` | `Riptide.Signal` | Typed events with independent listeners |
| `Trove` | `Riptide.Trove` | Resource cleanup tracking |
| `EventBus` | `Riptide.EventBus` | Pub/sub messaging between modules |
| `Guard` | `Riptide.Guard` | Runtime type validation |

---


## Async

A coroutine orchestration utility for timeouts, retries, and parallel execution.

### Types

```lua
type AsyncModule = {
    Run: (fn: (...any) -> ...any, timeout: number, ...any) -> ...any,
    Retry: (fn: (...any) -> ...any, maxAttempts: number, delay: number?, ...any) -> ...any,
    Parallel: (fns: { () -> any }, timeout: number?) -> { AsyncResult<any> },
}
```

---

### `Async.Run`

```lua
Riptide.Async.Run(fn, timeout, ...fallback) -> ...any
```

Executes a (potentially yielding) function with a timeout. If the function does not complete within `timeout` seconds, the fallback values are returned instead.

```lua
-- Wait up to 5 seconds for data, return nil on timeout
local data = Riptide.Async.Run(function()
    return DataStoreService:GetAsync("key")
end, 5, nil)
```

If the function throws an error (before timeout), the error is re-thrown.

When the timeout expires, `Run` returns the fallback and ignores any eventual result. The user function may continue running; a timeout does not cancel its side effects.

---

### `Async.Retry`

```lua
Riptide.Async.Retry(fn, maxAttempts, delay?, ...args) -> ...any
```

Retries a function up to `maxAttempts` times. If an attempt throws, it waits `delay` seconds (default `0`) before the next attempt. Returns the result on the first success; re-throws the last error if all attempts fail.

| Parameter      | Type     | Description                              |
|---------------|----------|------------------------------------------|
| `fn`          | function | The function to retry.                   |
| `maxAttempts` | integer  | Maximum attempts (must be ≥ 1).          |
| `delay`       | number?  | Seconds between retries (default `0`).   |
| `...`         | any      | Arguments passed to `fn` on each call.   |

```lua
local data = Riptide.Async.Retry(function()
    return DataStoreService:GetAsync("player_123")
end, 3, 1)  -- up to 3 attempts, 1 second between retries
```

:::note
Input validation: `maxAttempts` must be an integer ≥ 1, and `delay` must be non-negative. Invalid values throw immediately.
:::

---

### `Async.Parallel`

```lua
Riptide.Async.Parallel(fns, timeout?) -> { AsyncResult<any> }
```

Runs an array of zero-argument functions in parallel via `task.spawn` and waits for all to complete. Returns explicit result objects in the same order as `fns`.

```lua
type AsyncResult<T> = {
    ok: boolean,
    value: T?,
    error: string?,
    timedOut: boolean?,
}
```

| Parameter  | Type        | Description                                         |
|-----------|-------------|-----------------------------------------------------|
| `fns`     | `{ () -> any }` | Array of functions to run.                       |
| `timeout` | `number?`   | Max wait time in seconds. Defaults to **30**.       |

If timeout expires before all functions complete, unfinished entries return `{ ok = false, timedOut = true, error = "..." }`.

```lua
local results = Riptide.Async.Parallel({
    function() return fetchPlayerData() end,
    function() return fetchInventory() end,
    function() return fetchFriendsList() end,
}, 10)

if results[1].ok then
    local data = results[1].value
end
```

:::caution
Maelstrom-3 changes the old `{ any }` return shape. Failed tasks and timed-out tasks no longer return `nil`; they return `{ ok = false, error = "..." }`. Successful `nil` is represented as `{ ok = true, value = nil }`.
:::

---

## Signal

A fast, strictly typed, custom event implementation using a linked-list of connections.

### Types

```lua
type Connection = {
    Connected: boolean,
    Disconnect: (self: Connection) -> (),
}

type Event<T...> = {
    Connect: (self: Event<T...>, fn: (T...) -> ()) -> Connection,
    Once: (self: Event<T...>, fn: (T...) -> ()) -> Connection,
    Wait: (self: Event<T...>) -> T...,
}

type Signal<T...> = Event<T...> & {
    Fire: (self: Signal<T...>, T...) -> (),
    DisconnectAll: (self: Signal<T...>) -> (),
    Destroy: (self: Signal<T...>) -> (),
}
```

---

### `Signal.new`

```lua
Riptide.Signal.new() -> Signal
```

Creates a new signal instance.

```lua
local onScoreChanged = Riptide.Signal.new()
```

---

### `Signal:Connect`

```lua
Signal:Connect(fn: (...any) -> ()) -> Connection
```

Connects a callback to the signal. `Fire` schedules listeners independently through reusable threads. A listener may yield or error without blocking the other listeners. A callback is not guaranteed to finish before `Fire` returns.

Returns a `Connection` object.

```lua
local connection = onScoreChanged:Connect(function(newScore)
    print("Score is now:", newScore)
end)
```

---

### `Signal:Once`

```lua
Signal:Once(fn: (...any) -> ()) -> Connection
```

Like `Connect`, but the callback fires only **once** and then automatically disconnects.

```lua
onScoreChanged:Once(function(newScore)
    print("First score change:", newScore)
end)
```

---

### `Signal:Fire`

```lua
Signal:Fire(...any) -> ()
```

Fires the signal with the provided arguments. Dispatch begins with the newest connection. Listener completion order is not guaranteed, and `Fire` does not wait for a yielding listener.

```lua
onScoreChanged:Fire(150)
```

---

### `Signal:Wait`

```lua
Signal:Wait() -> ...any
```

Yields the current thread until the signal is fired. Returns all arguments passed to `Fire`, including trailing `nil` values. If `DisconnectAll` or `Destroy` cancels the wait, it raises an error.

```lua
local score = onScoreChanged:Wait()
print("Received score:", score)
```

:::note
`Wait` creates a one-shot connection internally that auto-disconnects after firing, so it does not leak.
:::

---

### `Signal:DisconnectAll`

```lua
Signal:DisconnectAll() -> ()
```

Disconnects all active connections immediately. Clears all internal references.

```lua
onScoreChanged:DisconnectAll()
```

---

### `Signal:Destroy`

```lua
Signal:Destroy() -> ()
```

Disconnects all connections and marks the signal destroyed. New connections are rejected after `Destroy`.

```lua
onScoreChanged:Destroy()
```

---

### `Connection:Disconnect`

```lua
Connection:Disconnect() -> ()
```

Disconnects a single connection from its signal. Safe to call multiple times.

```lua
local conn = signal:Connect(function() end)
conn:Disconnect()

print(conn.Connected)  -- false
```

After disconnecting, the connection releases its references to the signal and listener node.

---

## Trove

A resource cleanup tracking helper based on Sleitnick's Trove pattern. Exposes scoped tracking for signals, connections, instances, and generic functions.

Access via `Riptide.Trove`.

### `Trove.new`

```lua
Riptide.Trove.new() -> Trove
```

Creates a new resource tracking Trove instance.

```lua
local trove = Riptide.Trove.new()
```

### `Trove:Add`

```lua
trove:Add(object: any, cleanupMethod: string?) -> any
```

Tracks any cleanable object. Automatically infers the cleanup method (checks for `:Destroy()`, `:Disconnect()`, or if the object is a function, executes it). A custom cleanup method name can optionally be passed.

```lua
-- Track a function
trove:Add(function()
    print("Cleaned up function!")
end)

-- Track a custom object
trove:Add(myCustomObject, "CustomCleanup")
```

### `Trove:Connect`

```lua
trove:Connect(signal: any, callback: (...any) -> ()) -> Connection
```

Connects a callback to a signal and tracks the resulting connection within the trove.

```lua
trove:Connect(game.Players.PlayerAdded, function(player)
    print("Player added:", player.Name)
end)
```

### `Trove:Clean`

```lua
trove:Clean() -> ()
```

Cleans up all tracked resources in the reverse order that they were added (LIFO) and clears the trove container.

```lua
trove:Clean()
```

---

## EventBus

A lightweight, isolated pub/sub messenger for inter-module communication. Wrapped in error boundaries so crashing listeners do not block others.

Access via `Riptide.EventBus`.

### `EventBus.new`

```lua
Riptide.EventBus.new(label: string?) -> EventBus
```

Creates a new EventBus instance. `label` is optional and is used in listener error warnings.

```lua
local bus = Riptide.EventBus.new("RoundBus")
```

### `EventBus:On`

```lua
bus:On(eventName: string, callback: (...any) -> ()) -> () -> ()
```

Registers a callback for `eventName`. Returns an unsubscribe function that disconnects the listener when invoked.

```lua
local unsub = bus:On("ScoreUpdated", function(score)
    print("New score:", score)
end)

-- Unsubscribe later:
unsub()
```

### `EventBus:Once`

```lua
bus:Once(eventName: string, callback: (...any) -> ()) -> () -> ()
```

Registers a callback that runs only on the next emission for `eventName`, then unsubscribes itself. Returns an unsubscribe function so the one-shot listener can be cancelled before it fires.

```lua
local cancel = bus:Once("RoundStarted", function(roundId)
    print("First round observed:", roundId)
end)

-- Optional cancellation before the event fires:
cancel()
```

### `EventBus:Emit`

```lua
bus:Emit(eventName: string, ...: any) -> ()
```

Fires the event, calling all registered listeners synchronously with the provided arguments. Uses `xpcall` to isolate crashing listeners.

```lua
bus:Emit("ScoreUpdated", 1500)
```

### `EventBus:Clear`

```lua
bus:Clear() -> ()
```

Removes all registered listeners from the EventBus instance.

```lua
bus:Clear()
```

### `EventBus:Destroy`

```lua
bus:Destroy() -> ()
```

Cleanup-compatible alias for `Clear`. This lets an `EventBus` instance be passed to cleanup utilities that look for `Destroy`.

```lua
trove:Add(bus)
```

---

## Guard

A lightweight, zero-dependency type verification utility library for securing network boundaries and runtime argument validation.

Access via `Riptide.Guard`.

### Validators

- **`Guard.Number(min: number?, max: number?)`**: Validates a number, supporting optional boundaries (e.g. `Guard.Number(0, 100)`). Rejects `NaN`.
- **`Guard.String(maxLength: number?)`**: Validates a string, supporting an optional length boundary.
- **`Guard.Boolean()`**: Validates a boolean value (`true` or `false`).
- **`Guard.Enum(values: { any })`**: Validates that a value is contained in the whitelist array.
- **`Guard.Table(schema: { [string]: Validator })`**: Validates structured tables against schema mapping rules.
- **`Guard.Optional(validator: Validator)`**: Allows the value to be `nil` or match the nested validator.
- **`Guard.Instance(className: string)`**: Validates that the instance matches the Roblox engine class name.

### Example Usage

```lua
-- Validate a table payload
local isUserSchema = Guard.Table({
    name = Guard.String(50),
    age = Guard.Number(0, 150),
    isAdmin = Guard.Optional(Guard.Boolean()),
})

local ok, err = isUserSchema({ name = "Bob", age = 25 })
if not ok then
    warn("Validation error: " .. tostring(err))
end
```
