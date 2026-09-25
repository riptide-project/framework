---
slug: versions/0.9.0-maelstrom.3/migration/from-maelstrom-2
title: From Maelstrom-2
description: Changes to check when moving a game from Maelstrom-2 to Maelstrom-3.
---

Update your game dependency to `0.9.0-maelstrom.3` and reinstall packages. For Pesde, run `pesde add riptide/core@0.9.0-maelstrom.3 --alias Riptide` and `pesde install`. For Wally, change the version in `wally.toml` and run `wally install`.

## Signals

`Signal:Fire(...)` schedules each listener independently. A listener that yields or errors does not hold up the others. Do not depend on a listener finishing before `Fire` returns, or on listeners completing in connection order. Dispatch starts with the newest connection. `Signal:Wait()` still returns all event arguments, including trailing `nil`; it now errors if `DisconnectAll()` or `Destroy()` cancels the wait. Update call sites that assumed synchronous callbacks or a silent cancellation.

## State sync and networking

The state API is unchanged, but snapshot requests now have IDs, a deadline and bounded retries. Live deltas continue while the snapshot is in flight; newer deltas survive an older snapshot. If you call `RequestSync()`, remember that `true` only means the request was sent, not that sync has completed.

Names starting with `__riptide_` are reserved for internal messages. Rename any game or plugin network events that used this prefix. Public `Network` middleware no longer sees state replication packets, and internal state packets use the reliable transport only. Continue to validate client requests and permissions in your game handlers.

## Lifecycle and cleanup

Player initialization is independent per player, so one yielding player hook does not stall every other player. Plugin dependency failures block dependents; late work from a timed-out plugin cannot register new sandbox resources. Review code that assumed those operations ran as one serial chain.

`Async.Run` no longer cancels arbitrary user work when its timeout expires; it returns the fallback and ignores a later result. A plugin `Start` timeout still cancels the task owned by the plugin startup path. If timed-out work can cause side effects, make the operation itself idempotent or cancellable.

## Verify the upgrade

Start your game in Studio with a server and client. Check initial state sync, a reconnect, a yielding signal listener and plugin startup failures. The [Maelstrom-3 API pages](../../api/network/) describe the behavior.
