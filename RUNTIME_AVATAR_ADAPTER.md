# RuntimeAvatarAdapter: Architecture & Implementation

## Overview

The RuntimeAvatarAdapter is a formal boundary that separates portable Wild Ecology logic from Gen1Recomp-specific runtime actor management.

## Contract

```lua
function RuntimeAvatarAdapter.materialize(mod, entity, spawnCell, requestedMapId)
  -- Takes a persistent entity and materialization context
  -- Returns an avatar object with id, entityId, mapId, runtimeAdapter="RuntimeAvatarAdapter"
  -- Or nil on failure
end

function RuntimeAvatarAdapter.destroy(mod, avatar)
  -- Despawns a runtime avatar
  -- Clears entity -> avatar mapping
  -- Returns boolean success
end

function RuntimeAvatarAdapter.resolve(mod, avatar)
  -- Retrieves the live runtime handle/actor object
  -- Returns the runtime representation or nil if stale
end

function RuntimeAvatarAdapter.readPosition(mod, avatar)
  -- Normalized position read: { cellX, cellY }
  -- Works regardless of internal handle structure
  -- Returns position or nil if avatar not resolvable
end

function RuntimeAvatarAdapter.requestMovement(mod, avatar, entity)
  -- Issues a movement command to runtime
  -- Takes entity with runtimeState.movementRequest already populated
  -- Delegates to Gen1-specific implementation (AvatarFactory.applyMovementRequest)
  -- Returns boolean (movement accepted or rejected)
  -- Caller polls readPosition() to observe position changes
end
```

## Internal Structure

### RuntimeAvatarAdapter (Portable)
- Pure Lua adapter
- Resolves Gen1Recomp runtime handles
- Maps persistent entity ID ↔ runtime avatar ID
- Normalizes position reads

### AvatarFactory (Gen1Recomp-specific)
- Owns runtime NPC mutation (wanders, facing, motion fields)
- Wraps mod.world.spawnNpc and mod.engine_internals
- Handles movement requests through Collision.canMove
- Manages NPC-specific behavior application (WALK/STAY/range)

### Portable Ecology (avatar_factory.lua consumers)
- Main.lua: materialization lifecycle (spawn/despawn)
- Controller: decision engine (no runtime access)
- Perception: entity tracking (through positions)
- Navigation: path planning (through semantics, not runtime)
- Behavior: action execution (through movement requests)

## Ownership Model

| Responsibility | Owner | Boundary |
|---|---|---|
| Persistent entity ID ↔ runtime avatar ID mapping | RuntimeAvatarAdapter | formal |
| Materialization / despawn lifecycle | RuntimeAvatarAdapter + AvatarFactory | adapter wrapped |
| Runtime NPC field mutation | AvatarFactory only | file-scoped |
| Position normalization | RuntimeAvatarAdapter | contract method |
| Movement request routing | AvatarFactory (internal) | not adapter-facing |
| Collision checking | AvatarFactory (Collision API) | engine boundary |
| Behavior application | AvatarFactory (NPC state) | runtime-specific |
| Perception tracking | Perception + RuntimeAvatarAdapter.resolve | adapter read |
| Navigation planning | Navigation (semantic only) | no runtime access |
| Decision engine | Controller + Behavior states | pure Lua |

## Materialization Flow

```
Entity + spawn cell
       ↓
RuntimeAvatarAdapter.materialize()
       ↓
AvatarFactory.spawn() → runtime NPC/actor
       ↓
Avatar { id, entityId, mapId, runtimeAdapter, requestedCell }
       ↓
Main.lua stores in WildEcology.activeAvatars[entity.id]
```

## Position Read Flow (Portable)

```
Any portable system with an avatar
       ↓
RuntimeAvatarAdapter.readPosition(mod, avatar)
       ↓
resolveHandle(mod, avatar) → live runtime actor
       ↓
normalize { cellX, cellY }
       ↓
{ cellX, cellY } (never raw NPC object)
```

## Despawn Flow

```
Avatar in activeAvatars
       ↓
RuntimeAvatarAdapter.destroy(mod, avatar)
       ↓
AvatarFactory.despawn()
       ↓
mod.world.removeNpc() or mod.engine_internals.removeNpc()
       ↓
Runtime actor deleted
       ↓
Main.lua clears activeAvatars[entity.id]
```

## Movement Request Flow (Portable)

```
Navigation/steering produce movement request
       ↓
main.lua: applyMovementRequestToAvatar()
       ↓
RuntimeAvatarAdapter.requestMovement(mod, avatar, entity)
       ↓
AvatarFactory.applyMovementRequest() (Gen1-specific)
       ↓
Collision.canMove() (stock movement validation)
       ↓
NPC motion fields updated (async)
       ↓
Behavior polls position via adapter.readPosition()
```

This flow ensures movement routing goes through the adapter boundary, allowing any runtime backend to provide its own movement implementation.


A portable ecology system (with a different runtime backend) only needs to:

1. Implement the RuntimeAvatarAdapter contract with the same interface
2. Materialize/despawn runtime actors
3. Return normalized positions

The entire portable ecology stack (controller, perception, navigation, fear, behavior, relationships, dormant systems) works **unchanged** through any adapter implementation.

**Proof:** See `tests/portability_proof_spec.lua` which runs portable operations through `FakeRuntimeAvatarAdapter` (array pool, different ID scheme, flat structure) with no changes to calling code.

## Leak Prevention

Portable ecology modules are protected from runtime leaks by:

1. **Import isolation**: Controller, perception, navigation import only portable modules (no avatar_factory)
2. **Position normalization**: All position reads go through adapter.readPosition, not raw NPC.cellX
3. **Handle resolution**: resolve() encapsulated in adapter; portable code never touches handles
4. **NPC field mutations**: All in avatar_factory.lua (file-scoped, 37 lines of controlled changes)
5. **Engine APIs**: Collision.canMove, mod.world, engine_internals only in avatar_factory + adapter

## Performance

- **resolve()**: O(1) handle lookup with caching
- **readPosition()**: O(1) field read
- **materialize()**: Single spawn call to runtime
- **destroy()**: Single remove call to runtime
- No full-NPC-pool scans; all operations are targeted

## Testing

- `runtime_avatar_adapter_spec.lua`: 18 focused adapter boundary tests
  - Materialization, resolution, position reads
  - Stale avatar handling
  - Multiple concurrent avatars
  - Rematerialization
  - Position normalization

- `portability_proof_spec.lua`: 5 portable operation proofs
  - Spawn + position read
  - Movement request + position poll
  - Actor resolution + position read
  - Despawn loop
  - Multiple avatars on same map

- Full test suite: 77/77 tests pass (including lifecycle_spec with rematerialization)

## Integration Points

- **main.lua**: Calls RuntimeAvatarAdapter.materialize/destroy for lifecycle
- **avatar_factory.lua**: Implements actual spawn/despawn; used by adapter
- **world/**: Defines adapter interface in runtime_avatar_adapter.lua
- **No portable modules changed**: Controller, perception, navigation, behavior all unchanged

## Related Boundaries

- **EcologyClockAdapter**: Host time boundary (os.time/date)
- **WorldSemantics**: Raw map → ecology semantics
- **PokemonMechanics**: Generation-specific stat normalization (next target)
- **PersistenceAdapter**: Storage backend (next target)

## Next Portability Targets

This completion enables the next refactors:

1. **PersistenceAdapter (P0)**: Decouple save schema from storage backend
2. **WorldTopologySource (P1)**: Formalize map/connection reading
3. **EnvironmentAdapter (P1)**: Normalize encounter/environment data
4. **Battle/Capture Bridge (P3)**: When ownership API exists
