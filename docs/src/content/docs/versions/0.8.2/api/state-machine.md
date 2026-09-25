---
slug: versions/0.8.2/api/state-machine
title: State Machine
description: Robust workflow and state orchestration.
---


The `StateMachine` module provides a strictly-typed utility for orchestrating states, perfect for managing game phases (Lobby → Playing → Ending), NPC AI logic, or complex UI screens.

Access via `Riptide.StateMachine`.

## Types

```lua
type StateDefinition = {
    OnEnter: ((self: any, ...any) -> ())?,
    OnUpdate: ((self: any, dt: number) -> ())?,
    OnExit: ((self: any) -> ())?,
}

type StateMachineConfig = {
    InitialState: string,
    States: { [string]: StateDefinition },
}

type StateMachineAPI = {
    new: (config: StateMachineConfig) -> StateMachine,
}
```

---

## Creating a Machine

Initialize a new finite state machine using `StateMachine.new()`. The `InitialState` is entered immediately and its `OnEnter` method runs synchronously.

```lua
local matchFSM = Riptide.StateMachine.new({
    InitialState = "Intermission",
    States = {
        Intermission = {
            OnEnter = function(self)
                print("Intermission started!")
            end,
            OnExit = function(self)
                print("Intermission ended!")
            end,
        },
        Playing = {
            OnEnter = function(self)
                print("Game started!")
            end,
        }
    }
})
```

---

## Methods

### `TransitionTo`

```lua
StateMachine:TransitionTo(newStateName: string, ...any) -> ()
```

Transitions the machine to a new state. If the target state is the same as the current state, this is ignored.
Any variadic arguments passed are routed directly to the new state's `OnEnter` hook.

```lua
matchFSM:TransitionTo("GameOver", "Team Blue")

-- Inside the GameOver state definition:
-- OnEnter = function(self, winner)
--     print("Winner is:", winner)
-- end
```

1. **`OnExit`** of the current state is called (if defined).
2. The current state name is updated internally.
3. **`OnEnter`** of the new state is called with the provided arguments.
4. **`OnStateChanged`** signal fires.

---

### `Update`

```lua
StateMachine:Update(dt: number) -> ()
```

Manually pumps the `OnUpdate` hook of the current state. Useful if you want the state machine to be driven by a specific loop (e.g., `RunService.Heartbeat`).

```lua
RunService.Heartbeat:Connect(function(dt)
    matchFSM:Update(dt)
end)
```

---

### `GetCurrentState`

```lua
StateMachine:GetCurrentState() -> string
```

Returns the string identifier of the currently active state.

```lua
print(matchFSM:GetCurrentState()) -- "GameOver"
```

---

### `Destroy`

```lua
StateMachine:Destroy() -> ()
```

Safely destroys the state machine. Calls the `OnExit` hook for the current state, destroys the `OnStateChanged` internal signal, and clears all internal state definitions to prevent memory leaks.

---

## Signals

### `OnStateChanged`

A built-in [Signal](../utilities#signal) that fires whenever a successful transition occurs.

**Callback payload:** `(oldStateName: string, newStateName: string)`

```lua
matchFSM.OnStateChanged:Connect(function(oldState, newState)
    print(string.format("Transitioned: %s -> %s", oldState, newState))
end)
```
