# FLEE Non-Interference Audit

Date: 2026-08-23

## Verdict

FLEE remains a high-priority behavior within the shared behavior architecture. It does not bypass utility selection except for the documented emergency/continuing-FLEE rules, does not create a player-specific relationship path, does not persist runtime objects, and does not replace stock collision or WALK movement.

One concrete cross-system contamination defect was found and fixed: FLEE route-cycle history (`recentCommittedCells`) survived a normal FLEE exit and could be consumed by a later ordinary navigation episode. FLEE exit now clears that shared history.

No FLEE feature, planner capability, score, threshold, route depth, cadence, collision rule, or movement API was added or tuned.

## Ownership Contract

| Data | Owner | Lifetime | Exit/reset rule |
|---|---|---|---|
| `relationships`, long-term memory, population/home identity | Persistent entity | Durable | Preserve |
| `fearCurrent`, `fearDirect`, `fearSocial`, alarm/social evidence | Fear integration | Runtime, cross-behavior | Decay through Fear; do not erase merely because FLEE exits |
| `escapeHeading`, `escapeSeparationMomentum` | Active FLEE steering | FLEE episode | Clear on FLEE exit/reset |
| `fleeThreatPosition`, tick, entity ID, `escapeReference` | Active FLEE reference resolution | FLEE episode | Clear on FLEE exit/reset |
| `fleeExecution`, route, planner dirtiness, rejected route state | Active FLEE execution | FLEE episode | Clear on FLEE exit/reset |
| `targetEntityId` | Current entity-directed behavior | Current intent | Transfer to assessed threat on FLEE entry; clear/reassign on exit |
| `movementRequest` | Current intent execution | Queued step only | Replace on transition; active stock motion may finish |
| `recentCommittedCells` | Current route-cycle detector | Current navigation episode | Clear on FLEE exit (fixed) |
| `rejectedMoves` | Generic actuator/map-local collision knowledge | Avatar runtime | Preserve across behavior transitions; clear on runtime reset |
| `movementClaims` | Shared movement arbitration | Current request or active motion | Validate and clear after cancellation, completion, rejection, map reset, or staleness |
| `lastFleeEndTick`, calm/reassembly progress | Post-FLEE recovery | Runtime | Intentionally retain until recovery logic supersedes it |

## 30-Point Result

1. **PASS: Shared state machine.** FLEE is selected and executed by `Controller`; it is not a parallel AI controller.
2. **PASS: Utility participation.** Ordinary FLEE competes through utility and intent commitment. Only severe/emergency danger and continuing-FLEE commitment force retention.
3. **PASS: Deliberation cadence.** Existing scheduler coverage proves execution-only FLEE updates do not rerun the utility table every tick.
4. **PASS: Fear cadence separation.** Fear remains independently integrated and is not owned by FLEE transition cleanup.
5. **PASS: APPROACH to FLEE.** Severe danger interrupts APPROACH, replaces target/request ownership, and starts a FLEE episode.
6. **PASS: INVESTIGATE to FLEE.** Severe danger interrupts INVESTIGATE without losing persistent relationships.
7. **PASS: SEEK_FLOCK to FLEE.** The ordinary navigation route and search destination are released before FLEE execution.
8. **PASS: TARGET to FLEE.** Synthetic wander destinations do not become FLEE threat identity; queued movement is replaced.
9. **PASS: IDLE to FLEE.** Emergency entry establishes only FLEE-owned target/reference/request state.
10. **PASS: REST to FLEE.** Purposeful REST can be interrupted through the same generic transition path.
11. **PASS: Direct player threat ownership.** CURRENT threat geometry, episode target, and movement provenance agree on `player`.
12. **PASS: Direct wild threat ownership.** A hostile wild entity follows the same identity and provenance rules as a trainer/player threat.
13. **PASS: Lost direct threat.** LAST_KNOWN geometry retains source provenance but does not claim a live entity target.
14. **PASS: Social-only FLEE.** SOCIAL_ESCAPE_VECTOR remains targetless and does not fabricate direct threat identity or relationships.
15. **PASS: Heading-only continuation.** HEADING_INERTIA remains targetless after last-known and social references expire.
16. **PASS: Intent episodes.** FLEE interrupts the prior episode and owns its own active episode; changing authoritative threat updates that episode target.
17. **PASS: Ordinary target cleanup.** Non-entity-directed states do not inherit the FLEE threat ID after exit.
18. **PASS: Request cleanup.** FLEE WALK and trapped STAY requests are absent after ordinary exit.
19. **PASS: Active stock motion exception.** A motion already accepted by the stock engine may finish; a stale queued request may not survive.
20. **PASS: Movement claims.** A claim whose FLEE request is canceled is removed by shared claim validation; arbitration does not mutate threat identity.
21. **FIXED: Route-cycle history.** `recentCommittedCells` previously survived FLEE exit. It is now cleared before ordinary navigation can consume it.
22. **PASS: Generic rejection knowledge.** `rejectedMoves` remains shared map-local collision knowledge rather than being erased by a behavior transition.
23. **PASS: Static rejection isolation.** Existing regressions prove a static rejection replans the active FLEE route without using dynamic blocker wait semantics.
24. **PASS: Trapped recovery.** A `NO_ESCAPE_ROUTE` STAY request does not prevent safe emotional recovery or retain movement ownership after exit.
25. **PASS: Repeated episodes.** Fifty alternating trainer/wild FLEE episodes enter, retarget, recover, and exit without planner, request, target, or route-history residue.
26. **PASS: Runtime reset.** Avatar destruction/reconstruction replaces the complete runtime table, including FLEE, Fear, target, navigation, and claim-adjacent state.
27. **PASS: Save/load boundary.** Runtime state is stripped from save snapshots and legacy loads; recent FLEE state cannot become durable entity data.
28. **PASS: Post-FLEE reassembly.** `lastFleeEndTick` and delayed reassembly pressure are documented recovery state, not leaks; renewed direct danger interrupts reassembly.
29. **PASS: Persistent data integrity.** Relationship table identity and durable threat memory survive transitions and repeated episodes.
30. **PASS: Mixed long run.** A deterministic 1,000-tick run completed 10 FLEE entries and 10 exits, ending in IDLE with no threat target or FLEE planner state.

## Defect and Fix

Before the fix, the FLEE exit block cleared heading, separation momentum, threat position/reference, and `fleeExecution`, but retained `recentCommittedCells`. `updateCompletedStepNavigation` uses that same field for short-oscillation detection across ordinary navigation. A later ordinary episode could therefore compare its path against cells committed during escape and create a false cycle/avoidance response.

The fix is deliberately limited to the existing FLEE exit boundary:

```lua
runtimeState.escapeReference = nil
runtimeState.recentCommittedCells = {}
runtimeState.firstOrdinaryDecisionTick = tick
```

This changes no FLEE planning or movement behavior while FLEE is active.

## Regression Evidence

`tests/flee_non_interference_spec.lua` covers:

- the six-state entry matrix;
- old route and request replacement;
- FLEE exit field ownership;
- preservation of Fear-owned evidence and persistent relationships;
- generic collision rejection preservation;
- movement-claim cancellation;
- trapped STAY recovery;
- 50 alternating trainer/wild episodes;
- a 1,000-tick mixed ownership run.

Existing focused evidence remains in:

- `tests/flee_escape_spec.lua` for route planning, wall-backed escape, static/dynamic rejection, crowding, and planner cadence;
- `tests/flee_target_ownership_spec.lua` for CURRENT, LAST_KNOWN, SOCIAL_ESCAPE_VECTOR, HEADING_INERTIA, player, and wild threat provenance;
- `tests/flee_recovery_spec.lua` and `tests/flee_recovery_gradient_spec.lua` for emotional recovery and threat-loss continuation;
- `tests/intent_episode_spec.lua` for purposeful interruption semantics;
- `tests/movement_claims_spec.lua` for claim publication, conflict, cancellation, completion, and reset;
- `tests/runtime_state_spec.lua`, `tests/lifecycle_spec.lua`, and `tests/persistence_spec.lua` for reset and persistence boundaries;
- `tests/post_flee_reassembly_spec.lua` and `tests/normal_intent_simulation_spec.lua` for normal post-FLEE behavior.

## Validation

- 49 of 49 Lua specs pass in isolated Lua 5.5 processes.
- `git diff --check` reports no whitespace errors; it emits only the existing CRLF-to-LF warning for `controller.lua`.
- The new audit spec has no editor diagnostics.
- `controller.lua` retains pre-existing nil-flow diagnostics in unrelated target/navigation code.
- LuaJIT is not installed locally, so a true LuaJIT execution smoke test was not available. The production edit is Lua 5.1-compatible assignment syntax.

## Residual Runtime Risk

Headless tests can prove controller, claim-registry, reset, and persistence ownership, but cannot fully observe an accepted stock NPC step during a real Gen1Recomp map transition. The intended contract is explicit: accepted stock motion may complete, while queued requests and claims are revalidated against current runtime state. No engine seam was changed during this audit.
