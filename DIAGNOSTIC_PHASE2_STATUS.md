# Phase 2: Live Spawn Materialization Diagnosis
## Summary of Instrumentation & Testing

### Problem Statement
In live ROUTE_22 game:
- persistent = 30, eligible = 30, selected = 15 ✓
- BUT mat ok = 0, mat fail = 0 ✗ (expected ~14-15)
- SPAWN reason = NOT_RUN (expected SPAWNED or FAILED)
- cohort counter = 1159 (wrong, should be ~14)

In test environment:
- selected = 15, dispatch = 14, mat ok = 14 ✓
- Test passes; live game fails

### Root Cause Hypothesis
The dispatch loop (`for _, entity in ipairs(visiblePopulation)...`) either:
1. **Never enters** (phase3LoopEntered=0)
2. **Enters but skips all** (phase3DispatchAttempts=0) due to blocking condition
3. **Enters and processes** but dispatch calls return error (phase3LastBlocker != "SUCCESS")

### Instrumentation Completed
Added 4 diagnostic counters to spawnDiagnostics (displayed in HUD):
- `phase3Entered` - increments once when spawnPhase3Avatars() is called
- `phase3LoopEntered` - increments once when loop starts iterating
- `phase3DispatchAttempts` - increments for each entity passed to materialize()
- `phase3LastBlocker` - reason code for each entity dispatch:
  - `"SUCCESS"` - materialization succeeded
  - `"INVALID_ENTITY"` - entity is nil/invalid
  - `"IS_ANCHOR"` - entity is anchor (skipped intentionally)
  - `"ALREADY_ACTIVE"` - entity already has active avatar
  - `"CONCEALED"` - entity is concealed (hidden)
  - `"NO_AVATARFACTORY"` - RuntimeAvatarAdapter unavailable
  - `"ATTEMPT_NOT_ALLOWED"` - avatar check failed
  - `"MISSING_POSITION"` - no position data
  - `"SEMANTICS_MISMATCH"` - environment check failed
  - `"MATERIALIZE_FAILED"` - actual materialization call failed
  - (error details if exception)

### Test Results (Validated in Test Harness)
✅ **anchor_disabled_spawn_spec.lua**: Non-anchor maps
- phase3Entered=1, phase3LoopEntered=1, dispatch=15, mat ok=15, anchor calls=0
- Result: Cohort spawns independently of anchor on non-anchor maps

✅ **selected_dispatch_regression_spec.lua**: Loop and dispatch execution
- selected=15, dispatch=15, mat ok=15
- Result: All selected entities attempt dispatch and succeed

Both tests confirm the dispatch mechanism works in test environment.

## What You Need to Do Now

### Step 1: Capture Live HUD Snapshot
1. Load the instrumented code into the game mod
2. Travel to ROUTE_22 or any non-anchor ecology map
3. Take a screenshot of the debug HUD with DISPATCH section visible
4. Report these exact values:
   - `phase3Entered` (should be 1 if working)
   - `phase3LoopEntered` (should be 1 if loop enters)
   - `phase3DispatchAttempts` (should match or be close to selected count)
   - `phase3LastBlocker` (reason for last entity processed)

### Step 2: Diagnostic Interpretation
**If phase3Entered=0**: spawnPhase3Avatars() is never called
- Indicates: WildEcology.init() has early return or module loading issue

**If phase3LoopEntered=0**: Loop doesn't enter even though phase3Entered=1
- Indicates: visiblePopulation is nil/empty or loop condition fails

**If phase3DispatchAttempts=0**: Loop enters but no entities reach dispatch
- Indicates: All entities filtered by IS_ANCHOR or other condition
- Check: Does selected=15 include 15 anchors? Should only have 1 anchor

**If phase3DispatchAttempts > 0 but phase3LastBlocker != "SUCCESS"**:
- Indicates: Specific blocking condition (see codes above)
- Examples: ALREADY_ACTIVE (avatar persists), NO_AVATARFACTORY (adapter missing), CONCEALED

**If phase3DispatchAttempts matches selected and phase3LastBlocker="SUCCESS"**:
- Indicates: Everything works and test harness is accurate
- Question: Why does game show mat ok=0?

### Step 3: Next Actions Based on Findings
After providing the HUD snapshot, we will:
1. Compare with test results to identify the exact divergence
2. Trace the cause (initialization, adapter loading, state flags)
3. Fix the root cause
4. Validate with new regression test

## Key Files Modified
- `main.lua`: Added 4 diagnostic counters, instrument dispatch loop with blocker codes
- `tests/anchor_disabled_spawn_spec.lua`: New - validates non-anchor map cohort spawn
- `tests/selected_dispatch_regression_spec.lua`: New - validates dispatch loop execution
- `tests/dispatch_hud_spec.lua`: New - validates HUD rendering of diagnostics

## Files NOT Modified (Still Valid)
- `src/population/manager.lua` - getVisibleRoutePopulation works
- `src/population/selection.lua` - pickVisibleSubsetWithAnchor works
- `src/world/avatar_factory.lua` - RuntimeAvatarAdapter interface exists
