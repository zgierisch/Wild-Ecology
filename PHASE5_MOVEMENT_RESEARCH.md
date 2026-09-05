# Phase 5 Movement Execution Research

Date: 2026-08-20
Source: `bryanthaboi/gen1recomp` `dev` branch, cloned to a temporary checkout and indexed with this repository's `quedonde.py`.

## Result

The public NPC handle does not provide a collision-aware single-step movement API. The temporary Gen1Recomp checkout is source research only and is not a runtime dependency.

`WorldAPI:npc(mapId, indexOrName)` returns a public handle with:

- `handle:scriptMove(dir, tiles, onDone)`
- `handle:marchInPlace(onDone)`
- `handle:face(dir)`
- `handle:position()`

`scriptMove` is unsafe for Wild Ecology movement validation. It forwards to the scripted movement queue, whose execution path does not call `Collision.canMove` and participates in global scripted state. Wild Ecology therefore uses a narrow, mod-local `engine_internals` adapter against stock `src.world.Collision` and the existing NPC movement fields.

No physical Wild Ecology movement was implemented as part of this research spike.

## Exact Call Paths

### Public scripted movement path

```text
mod.world:npc(mapId, npcId)
    -> WorldAPI:npc(...)
    -> public Handle

handle:scriptMove(dir, tiles, onDone)
    -> self.ow:scriptMove(self.npc, dir, tiles, onDone)
    -> OverworldState:scriptMove(...)
    -> append to overworld.scriptMoves
    -> OverworldState:updateScriptMoves()
    -> assign facing/targetX/targetY/moving
    -> NPC:update() animates and commits the destination
```

Relevant upstream source locations:

- `src/world/WorldAPI.lua`: public Handle and `Handle:scriptMove`
- `src/world/OverworldController.lua`: `OverworldState:scriptMove` and `updateScriptMoves`
- `src/world/NPC.lua`: normal NPC update and ambient wandering

The scripted queue does not call `Collision.canMove` before assigning `targetX`, `targetY`, and `moving`.

### Mod-local stock-runtime autonomous single-step path

```text
AvatarFactory movement adapter
    -> handle.npc / handle.ow (isolated engine_internals access)
    -> Collision.canMove(ow.map, ow.entities, npc, direction)
    -> reject with false/reason, or:
       assign facing/targetX/targetY/moving/progress immediately
    -> stock NPC:update() animates and commits the destination
    -> Wild Ecology polls npc position/moving state and clears motion
```

Autonomous movement does not append to `overworld.scriptMoves`, so it does not enter global scripted/cutscene state.

### Normal NPC movement path

```text
NPC:update(map, entities)
    -> choose direction
    -> Collision.target(cellX, cellY, direction)
    -> Collision.canMove(map, entities, mover, direction)
    -> optional movement.collision hook
    -> assign targetX/targetY/moving
    -> NPC:update() animates and commits the destination
```

On the current `dev` source, `src/world/NPC.lua` defines `STEP_FRAMES = 32`.
`NPC:update` increments `progress` once per engine update and commits the
target cell when `progress >= stepFrames`. Wild Ecology's `simulationTick` is
different: `Save.nextTick` advances once only when the update-hook sync passes
the ecology, semantics, and save gates and reaches `WildEcology.init`; startup
also performs a separate sync. The domains therefore are not treated as
interchangeable. Occupancy waits use observed blocker movement/claim lifecycle,
with simulation age only as a stale-state watchdog.

`Collision.canMove` checks, at minimum:

- map bounds
- destination tile walkability
- tile-pair/elevation collision
- occupied destination entities
- `movement.collision` hook middleware

Relevant upstream source locations:

- `src/world/NPC.lua`: ambient NPC movement calls `Collision.canMove`
- `src/world/Player.lua`: player movement calls `Collision.canMove`
- `src/world/Collision.lua`: canonical Gen 1 collision verdict and hook
- `src/world/OverworldController.lua`: normal overworld update order

### Collision hook path

```text
Player movement or normal NPC movement
    -> Collision.canMove(...)
    -> vanilla verdict
    -> Runtime.call("movement.collision", passthrough, allowed, ctx)
    -> final allowed/rejected result
```

The hook context includes:

```lua
{
    map = map,
    mover = mover,
    dir = dir,
    fromX = mover.cellX,
    fromY = mover.cellY,
    toX = tx,
    toY = ty,
    reason = why
}
```

This is a mod hook around the collision decision, not a public `mod.world` method that a mod can directly invoke for an arbitrary runtime NPC.

## Public / Supported Status

### Public and supported

- `mod.world:spawnNpc(...)`
- `mod.world:npc(...)`
- `mod.world:removeNpc(...)`
- `handle:scriptMove(...)`
- `handle:face(...)`
- `handle:position(...)`

The upstream public API tests verify that a live NPC handle can be resolved and that `handle:scriptMove` queues a scripted movement.

### Not established as a public mod API

- `world.isWalkable(...)`
- `world.tryMove(...)`
- `handle:canMove(...)`
- a public collision query accepting actor/from/to/direction

The `movement.collision` hook is public as an extension point, but it does not expose the vanilla collision verdict as a callable query to another mod.

## Important Behavioral Difference

`scriptMove` is designed for cutscenes and scripted walks. The upstream source and tests describe it as a scripted movement queue, and its execution path does not perform the normal `Collision.canMove` check. Calling it for Wild Ecology would therefore risk walking through walls, entities, tile-pair barriers, and other collision constraints.

The current Wild Ecology code must not call `scriptMove` for autonomous movement. It applies structured ordinary `WALK` requests through the isolated stock-runtime adapter.

## Smallest Upstream API Proposal

Add a public collision-aware single-step method, preferably:

```lua
local success, reason = handle:tryMove(direction, onDone)
```

Recommended behavior:

1. Resolve the live NPC handle and current actor state.
2. Call the same canonical collision path used by normal NPC movement.
3. Run the existing `movement.collision` hook with the normal context.
4. If rejected, return `false, reason` and do not enqueue animation.
5. If allowed, enqueue exactly one ordinary step and return `true`.
6. Invoke `onDone` after the animation commits, matching scripted movement callback timing.
7. Refuse or report a reason when another movement is already in progress.

A lower-level public query could also be useful:

```lua
local result = mod.world:evaluateTraversal(actorId, fromX, fromY, toX, toY, direction)
```

but `handle:tryMove` is the smaller seam for the current need and keeps collision ownership inside the engine.

## Decision

Keep Wild Ecology's current architecture:

```text
target selector
    -> spatial goal
    -> steering
    -> traversal request
    -> avatar adapter
```

Use `engine_internals` only inside the movement adapter because stock public APIs do not expose the required collision-aware single-step operation. Do not call `scriptMove` for autonomous Wild Ecology movement. Do not modify or require a custom Gen1Recomp build.
