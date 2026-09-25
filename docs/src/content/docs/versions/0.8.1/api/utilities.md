---
slug: versions/0.8.1/api/utilities
title: Utilities
description: Async and Signal primitives bundled with Riptide.
---


Riptide bundles two essential utility modules — **Async** and **Signal** — so you don't need external dependencies like `Promise` or `GoodSignal`.

Access via `Riptide.Async` and `Riptide.Signal`.

---

## Async

A coroutine orchestration utility for timeouts, retries, and parallel execution.

### Types

```lua
type AsyncModule = {
    Run: (fn: (...any) -> ...any, timeout: number, ...any) -> ...any,
    Retry: (fn: (...any) -> ...any, maxAttempts: number, delay: number?, ...any) -> ...any,
    Parallel: (fns: { () -> any }, timeout: number?) -> { any },
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
Riptide.Async.Parallel(fns, timeout?) -> { any }
```

Runs an array of zero-argument functions in parallel via `task.spawn` and waits for all to complete. Returns results in the same order as `fns`.

| Parameter  | Type        | Description                                         |
|-----------|-------------|-----------------------------------------------------|
| `fns`     | `{ () -> any }` | Array of functions to run.                       |
| `timeout` | `number?`   | Max wait time in seconds. Defaults to **30**.       |

If timeout expires before all functions complete, unfinished entries are `nil`.

```lua
local results = Riptide.Async.Parallel({
    function() return fetchPlayerData() end,
    function() return fetchInventory() end,
    function() return fetchFriendsList() end,
}, 10)

local data, inventory, friends = results[1], results[2], results[3]
```

:::caution
If a function in the array throws an error, its result slot is `nil` — other functions continue executing normally.
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

type Signal = {
    Connect: (self: Signal, fn: (...any) -> ()) -> Connection,
    Once: (self: Signal, fn: (...any) -> ()) -> Connection,
    Fire: (self: Signal, ...any) -> (),
    Wait: (self: Signal) -> ...any,
    DisconnectAll: (self: Signal) -> (),
    Destroy: (self: Signal) -> (),
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

Connects a callback to the signal. The callback is invoked via `task.spawn` whenever `Fire` is called.

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

Fires the signal, calling all connected callbacks with the provided arguments. Each callback runs in its own coroutine via `task.spawn`, so one yielding callback does not block others.

```lua
onScoreChanged:Fire(150)
```

---

### `Signal:Wait`

```lua
Signal:Wait() -> ...any
```

Yields the current thread until the signal is fired. Returns the arguments passed to `Fire`.

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

Disconnects all connections and invalidates the signal by removing its metatable. After `Destroy`, the signal should not be used.

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

After disconnecting, all internal references (`_signal`, `_fn`, `_next`) are cleared to prevent memory leaks.
