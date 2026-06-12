---
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

---

## Full Examples

### Match Phase Manager

A typical server-side game loop using a state machine:

```lua
-- ServerScriptService/Services/MatchService.lua
--!strict
local MatchService = {}

function MatchService:Start(Riptide)
    local fsm = Riptide.StateMachine.new({
        InitialState = "Intermission",
        States = {
            Intermission = {
                OnEnter = function(self)
                    Riptide.State:Set("matchPhase", "Intermission")
                    Riptide.Network.FireAllClients("ShowCountdown", 15)
                    task.wait(15)
                    fsm:TransitionTo("Playing")
                end,
            },
            Playing = {
                OnEnter = function(self)
                    Riptide.State:Set("matchPhase", "Playing")
                    task.wait(120)  -- 2 minute round
                    fsm:TransitionTo("GameOver", "Time's up!")
                end,
            },
            GameOver = {
                OnEnter = function(self, reason)
                    Riptide.State:Set("matchPhase", "GameOver")
                    Riptide.Network.FireAllClients("ShowGameOver", reason)
                    task.wait(5)
                    fsm:TransitionTo("Intermission")
                end,
            },
        },
    })

    -- Log all transitions for debugging
    fsm.OnStateChanged:Connect(function(old, new)
        print(string.format("[Match] %s → %s", old, new))
    end)
end

return MatchService
```

### Character State Controller (Client)

```lua
-- StarterPlayerScripts/Controllers/CharacterController.lua
--!strict
local CharacterController = {}

function CharacterController:Start(Riptide)
    local character = game.Players.LocalPlayer.Character
        or game.Players.LocalPlayer.CharacterAdded:Wait()

    local humanoid = character:WaitForChild("Humanoid") :: Humanoid
    local rootPart  = character:WaitForChild("HumanoidRootPart") :: BasePart

    local fsm = Riptide.StateMachine.new({
        InitialState = "Idle",
        States = {
            Idle = {
                OnEnter  = function() humanoid.WalkSpeed = 0  end,
                OnUpdate = function(self, dt)
                    if humanoid.MoveDirection.Magnitude > 0 then
                        fsm:TransitionTo("Run")
                    end
                end,
            },
            Run = {
                OnEnter  = function() humanoid.WalkSpeed = 16 end,
                OnUpdate = function(self, dt)
                    if humanoid.MoveDirection.Magnitude == 0 then
                        fsm:TransitionTo("Idle")
                    elseif humanoid:GetState() == Enum.HumanoidStateType.Jumping then
                        fsm:TransitionTo("Jump")
                    end
                end,
            },
            Jump = {
                OnEnter = function() print("Jumped!") end,
                OnUpdate = function(self, dt)
                    if humanoid:GetState() == Enum.HumanoidStateType.Freefall then
                        fsm:TransitionTo("Fall")
                    end
                end,
            },
            Fall = {
                OnEnter = function() print("Falling!") end,
                OnUpdate = function(self, dt)
                    if humanoid:GetState() == Enum.HumanoidStateType.Landed then
                        fsm:TransitionTo("Idle")
                    end
                end,
            },
        },
    })

    -- Drive the FSM every frame
    game:GetService("RunService").Heartbeat:Connect(function(dt)
        fsm:Update(dt)
    end)
end

return CharacterController
```
