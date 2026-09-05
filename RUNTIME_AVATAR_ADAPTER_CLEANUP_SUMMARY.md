# RuntimeAvatarAdapter: Final Cleanup Summary (2026-08-25)

## Objective

Resolve architectural inconsistency between declared contract and production call paths.

## Issue Identified

RuntimeAvatarAdapter declared `requestMovement(...)` in its contract, but production code still called `AvatarFactory.applyMovementRequest()` directly. This weakened the portability claim that "replacing the runtime backend requires only implementing RuntimeAvatarAdapter."

## Changes Made

### 1. RuntimeAvatarAdapter Movement Contract (Clarified)

**File:** `src/world/runtime_avatar_adapter.lua` (lines 84-90)

Changed from:
```lua
function RuntimeAvatarAdapter.requestMovement(mod, avatar, direction)
  -- Simple wrapper that tried to construct movementRequest
end
```

To:
```lua
function RuntimeAvatarAdapter.requestMovement(mod, avatar, entity)
  local AvatarFactory = require("src.world.avatar_factory")
  if not AvatarFactory or not AvatarFactory.applyMovementRequest then
    return false
  end
  return AvatarFactory.applyMovementRequest(mod, avatar, entity) or false
end
```

**Rationale:** Now accepts the full entity (which already has runtimeState.movementRequest populated), correctly delegates to AvatarFactory, and serves as the proper boundary for runtime-specific movement handling.

### 2. Production Movement Routing (Wired to Adapter)

**File:** `main.lua` (line 2936, 3001)

Changed from:
```lua
applyMovementRequestToAvatar = function(mod, avatar, entity)
  if not AvatarFactory or not AvatarFactory.applyMovementRequest then
    return false
  end
  -- ... movement claim validation ...
  local applied = AvatarFactory.applyMovementRequest(mod, avatar, entity)
end
```

To:
```lua
applyMovementRequestToAvatar = function(mod, avatar, entity)
  if not RuntimeAvatarAdapter or not RuntimeAvatarAdapter.requestMovement then
    return false
  end
  -- ... movement claim validation ...
  local applied = RuntimeAvatarAdapter.requestMovement(mod, avatar, entity)
end
```

**Rationale:** All movement requests now flow through RuntimeAvatarAdapter, establishing it as the true boundary between portable ecology and Gen1-specific movement handling.

### 3. Documentation Updates

**Files Updated:**
- `RUNTIME_AVATAR_ADAPTER.md` (added Movement Request Flow section, clarified contract)
- `RUNTIME_AVATAR_ADAPTER_COMPLETION_REPORT.md` (updated data flow diagrams, removed "out of scope" statements)
- `PORTABILITY_ADAPTER_AUDIT.md` (updated conclusion, fixed hypothetical port sections, clarified regression invariants)

**Key Changes:**
- Audit conclusion now correctly reflects RuntimeAvatarAdapter completion
- Hypothetical port sections updated to show files that need adapter implementations
- Regression invariants now include movement routing requirement
- Priority plan clarifies P0 RuntimeAvatarAdapter is complete, next P0 is PersistenceAdapter

## Architectural Outcome

### Current Production Call Paths

**Materialization:**
```
main.lua (spawn)
    → RuntimeAvatarAdapter.materialize()
    → AvatarFactory.spawn() [fallback: direct spawn]
    → mod.world.spawnNpc()
```

**Despawn:**
```
main.lua (shutdown)
    → RuntimeAvatarAdapter.destroy()
    → AvatarFactory.despawn() [fallback: direct despawn]
    → mod.world.removeNpc()
```

**Movement:**
```
main.lua (applyMovementRequestToAvatar)
    → RuntimeAvatarAdapter.requestMovement()
    → AvatarFactory.applyMovementRequest()
    → Collision.canMove()
    → NPC motion fields
```

**Position Read:**
```
Behavior / Perception systems
    → RuntimeAvatarAdapter.readPosition()
    → normalizes to { cellX, cellY }
```

### Portability Claim (Now Consistent)

**Claim:** Replacing the runtime backend (Gen1Recomp NPC objects → array pool, different ID scheme, etc.) requires implementing **only** the RuntimeAvatarAdapter contract.

**Evidence:**
- ✅ All production calls (materialize, destroy, requestMovement, readPosition) route through adapter
- ✅ Position reads normalized, never raw NPC objects exposed
- ✅ FakeRuntimeAvatarAdapter (test-only, deliberately different implementation) works unchanged for all portable operations
- ✅ Portable ecology modules (controller, perception, navigation, behavior) have zero knowledge of Gen1 NPC structure
- ✅ All 77 tests pass including portability proof

**Constraint:** Movement orchestration (claim validation, API negotiation) stays in main.lua. AvatarFactory remains the Gen1-specific implementation layer. This split is intentional: the adapter owns the boundary, not the choreography.

## Test Results

**All 77 tests passing:**
- runtime_avatar_adapter_spec.lua: 18/18 ✓
- portability_proof_spec.lua: 5/5 ✓
- avatar_factory_spec.lua: includes adapter integration ✓
- lifecycle_spec.lua: rematerialization cycle ✓
- All other ecology tests: 49/49 ✓

**No regressions:** Full test suite passes with movement routing through adapter.

## Portability Assessment

A future port to a different Pokémon runtime would need to implement:

```lua
local CustomRuntimeAdapter = {}

function CustomRuntimeAdapter.materialize(mod, entity, spawnCell, mapId)
  -- Custom spawn logic
  -- Return avatar { id, entityId, mapId, runtimeAdapter, handle }
end

function CustomRuntimeAdapter.destroy(mod, avatar)
  -- Custom despawn logic
end

function CustomRuntimeAdapter.resolve(mod, avatar)
  -- Custom handle resolution
end

function CustomRuntimeAdapter.readPosition(mod, avatar)
  -- Custom position read → normalized { cellX, cellY }
end

function CustomRuntimeAdapter.requestMovement(mod, avatar, entity)
  -- Custom movement execution
end
```

**No changes required to:**
- Controller, perception, navigation, behavior systems
- Relationships, fear, drives, needs
- Dormant simulation, population logic
- Species ecology, mechanics adapters
- Any portable state machine

## Known Limits (Appropriate)

These remain intentionally outside the RuntimeAvatarAdapter contract:

1. **Movement Claim Orchestration:** Conflict resolution, rejection logging, claim publishing
   - Belongs in main.lua lifecycle layer
   - Gen1-agnostic coordination logic

2. **NPC Field Mutation:** wanders, roamDirs, facing, kind, progress
   - Appropriate to AvatarFactory (Gen1-specific layer)
   - Not exported through adapter

3. **Collision Authority:** Collision.canMove() call site
   - Remains in AvatarFactory
   - Different runtimes may have different collision libraries

4. **Engine Bootstrap:** mod.world, mod.game, mod.hooks setup
   - Remains in main.lua composition root
   - Not an adapter responsibility

## Files Changed (Final Cleanup)

| File | Changes | Status |
|---|---|---|
| src/world/runtime_avatar_adapter.lua | Updated requestMovement contract (7 lines) | ✓ |
| main.lua | Wired applyMovementRequestToAvatar to use adapter (1 line) | ✓ |
| RUNTIME_AVATAR_ADAPTER.md | Added Movement Request Flow section | ✓ |
| RUNTIME_AVATAR_ADAPTER_COMPLETION_REPORT.md | Updated data flows, clarified scope | ✓ |
| PORTABILITY_ADAPTER_AUDIT.md | Updated conclusion, fixed contradictions | ✓ |

## Verification Checklist

✅ RuntimeAvatarAdapter.requestMovement receives production calls
✅ main.lua routes all movement through adapter
✅ AvatarFactory.applyMovementRequest only called via adapter (or fallback)
✅ Collision.canMove remains isolated to Gen1 implementation
✅ No portable modules import AvatarFactory or access NPC fields
✅ All 77 tests pass (no regressions)
✅ Audit document consistent with implementation
✅ Architecture documentation updated
✅ Portability claim now architecturally sound

## Result

RuntimeAvatarAdapter is now a **complete, first-class boundary** where:

1. **Contract matches implementation** - All declared methods are production-routed
2. **Portability is achievable** - Only adapter needs reimplementation for different runtime
3. **Portable ecology is preserved** - Core behavior systems work unchanged
4. **Architecture is consistent** - No contradictions between documented design and actual code

---

**Status:** ✅ COMPLETE AND VERIFIED
**Date:** 2026-08-25
**Tests:** 77/77 passing
**Next:** PersistenceAdapter (P0)
