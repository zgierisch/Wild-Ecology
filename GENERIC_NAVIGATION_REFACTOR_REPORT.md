# Generic Navigation Refactor Report

## Scope

This refactor makes bounded, traversal-aware navigation the default capability for movement behaviors while preserving behavior policy, stock movement execution, collision authority, scheduler cadence, relationships, Fear, claims, and persistence.

1. **Architectural rule**

   Behavior decides where it wants to be. Generic navigation decides how to get there. World semantics and traversal evaluation decide what is physically possible. The stock avatar movement adapter remains the only authority that attempts a WALK step.

2. **Pre-refactor ownership split**

   TARGET, APPROACH, and INVESTIGATE used local greedy steering. SEEK_FLOCK had a private route wrapper in the controller. FLEE had the only robust bounded search, endpoint selection, failed-plan suppression, and committed-route lifecycle.

3. **Demonstrated ordinary failure**

   In the deterministic wall case, TARGET issued 17 requests and completed 14 steps with zero planner calls, abandoned the requested destination, and did not reach it. Against a transient blocker, ordinary movement made 24 identical attempts and remained stationary.

4. **Shared graph primitive**

   `src/navigation/bounded_search.lua` now owns deterministic bounded expansion and path reconstruction. It knows nothing about Pokemon, FLEE, spatial goals, traversal modes, or engine collision.

5. **FLEE equivalence gate**

   FLEE was migrated to `BoundedSearch` before ordinary behavior integration. Its focused escape, recovery, target-ownership, and non-interference specs passed before further migration.

6. **FLEE policy retained**

   Threat distance, endpoint safety, mobility, congestion, temporary regression debt, social escape vector, heading preference, recent-cell penalties, commitment, and dirty-cause policy remain FLEE-owned.

7. **Generic planner**

   `src/navigation/navigation_planner.lua` uses the shared search engine and `TraversalEvaluator`. It supports exact positions, proximity regions, directional regions, custom satisfaction, endpoint scoring, bounded depth, bounded expansions, static blocked edges, dynamic blocked cells, and movement-claim costs.

8. **Spatial goal contract**

   `SpatialGoal` carries kind, target position, radius/range, alignment, overlap policy, objective, map, traversal mode, source, and a stable signature. Behaviors provide this desired-state contract rather than a hardcoded step.

9. **Generic execution owner**

   `src/navigation/navigation_execution.lua` owns ordinary route establishment, route following, source validation, rejection feedback, blocked-edge evidence, failed-plan suppression, and counters.

10. **Shared episode mechanics**

   `src/navigation/navigation_episode.lua` now supplies route advancement, current-action lookup, source validation, request construction, rejection qualification, and static edge extraction to ordinary navigation and FLEE/controller execution.

11. **TARGET integration**

   TARGET retains its synthetic ambient destination across successful route steps. It uses local steering when the direct adjacent step is valid and bounded planning when topology or occupancy defeats that step.

12. **APPROACH integration**

   APPROACH supplies its existing target and satisfaction radius to generic navigation. Relationship selection, utility, intent commitment, and completion policy are unchanged.

13. **INVESTIGATE integration**

   INVESTIGATE supplies its existing target and investigation region to generic navigation. Investigation timing and canonical observer-to-completed-target relationship mutation are unchanged.

14. **SEEK_FLOCK integration**

   SEEK_FLOCK now uses `NavigationExecution` for goal ownership, source validation, bounded planning, route representation, and movement request construction.

15. **SEEK_FLOCK policy retained**

   Perceived, last-seen, social-direction, and blind-search cue selection remains behavior-owned. Moving-away occupant waits, reservation waits, stale-occupancy watchdog release, and purposeful intent failure remain in the controller as flock-search congestion policy.

16. **Legacy owner adoption**

   Existing SEEK_FLOCK runtime owners identified by `goalSignature` and implicit WALK mode are adopted in place. Same-goal blocked edges and cycle evidence survive migration; goal or map replacement still discards them.

17. **FLEE integration boundary**

   FLEE shares graph expansion and route episode primitives but retains a separate execution owner because its escape commitment, dirty-cause model, safety regression rules, and planner suppression are safety policy rather than generic navigation.

18. **Local-first behavior**

   A legal direct adjacent WALK remains the cheap path. Planning is invoked only when direct steering cannot produce a legal step, route ownership already exists, or new static/source evidence requires a replan.

19. **Static rejection semantics**

   A stock actuator `tile` or `bounds` rejection records the exact source-to-destination edge and forces one bounded replan. This prevents a newly learned topology fact from being silently bypassed by another local step.

20. **Dynamic blocker semantics**

   Ordinary movement plans around currently occupied cells. SEEK_FLOCK may instead suspend its committed route when provenance says the blocker is moving away or a reservation should clear.

21. **Source mismatch semantics**

   If the avatar is no longer at the route action's source, the stale route is discarded and one bounded replan occurs from the observed position.

22. **Unreachable suppression**

   Failed planning is keyed by position, map, learned blocked edges, and occupancy. An unchanged failed problem returns a stable non-moving result without repeating bounded search each tick.

23. **Topology authority**

   Planner expansion uses `WorldSemantics` and `TraversalEvaluator`. It does not call stock `Collision.canMove` speculatively and does not mutate runtime NPC objects.

24. **Actuator authority**

   WALK execution still goes through the existing stock movement adapter and stock collision. A planned edge is a proposal, not proof that the engine will execute it.

25. **Traversal capability**

   WALK is the only executable mode in this refactor. The planner's capability structure remains extensible, but no unsupported traversal mode is emitted.

26. **Map connection metadata**

   Gen1 map connections are directional records containing a destination map and offset. Warps contain source coordinates plus destination map/warp identifiers. These are topology metadata, not executable cross-map avatar commands.

27. **Known boundary distinction**

   `src/world/world_topology.lua` distinguishes a known map connection from a hard map boundary. The Route 1 to Pallet connection is recognized as known topology; a non-connection edge is a hard boundary.

28. **Cross-map execution limit**

   Persistent wild-avatar cross-map traversal is intentionally unsupported. A known connection is reported but not executed; ordinary roaming remains map-local and no runtime avatar is serialized across it.

29. **Runtime ownership**

   Routes, indexes, blocked edges, failed signatures, waypoints, source positions, and planner diagnostics are transient runtime state. Runtime reset discards them.

30. **Persistence result**

   No save schema, migration, persistent entity shape, or serialization behavior changed. Runtime NPCs, routes, and engine userdata remain outside persistence.

31. **Protected systems**

   No relationship formula, Fear coefficient, utility score, scheduler cadence, perception rule, movement-claim arbitration rule, stock collision rule, or logging policy was changed.

32. **Case A: TARGET wall**

   Before: 17 requests, 14 completed steps, zero planner calls, requested goal not reached. After: 8 requests, 8 steps, one planner call, eight route steps, zero static/dynamic/repeated rejection, goal reached.

33. **Cases B-D: INVESTIGATE, APPROACH, SEEK_FLOCK**

   INVESTIGATE after: 6 requests/steps, one planner call, six route steps, zero rejection, goal reached. APPROACH after: 7 requests/steps, one planner call, seven route steps, zero rejection, goal reached. SEEK_FLOCK retains deterministic wall detouring, rejection replanning, and occupancy lifecycle behavior under the generic executor.

34. **Case E: FLEE**

   Wall-backed endpoint choices remain unchanged (`LEFT`, `RIGHT`, `LEFT`, `STAY` in the focused matrix). In the 300-tick hot loop FLEE makes 2 planner calls, suppresses 298 unchanged calls, and records 0.67 planner calls per 100 ticks.

35. **Cases F-I: blocker, enclosure, hard boundary, known connection**

   Dynamic blocker: 4 requests/steps, one planner call, five route actions, zero rejection, reached. Sealed goal: one local step then one failed plan; unchanged failures are suppressed and the goal remains unreachable. Hard boundary: non-traversable. Known Route 1 connection: classified as known but non-executable for wild avatars.

36. **Aggregate performance evidence**

   The representative ordinary matrix plus learned static rejection produced 6 planner calls, 22 suppressed calls, 2 local steps, 26 route-following steps, 1 replan, and 250 bounded node expansions. Planning remains bounded by the existing default horizon (10) and expansion budget (128) per call.

37. **Validation and residual risk**

   All 57 Lua specs pass in isolated processes under Lua 5.5. LuaJIT was unavailable on the machine, so no actual JIT run was possible; changed code uses Lua 5.1-compatible constructs. Remaining risk is engine-runtime validation of map metadata and stock rejection behavior in live Gen1Recomp. Cross-map execution remains deliberately out of scope.
