# Navigation Episode Ownership Audit

## Scope

This audit traces navigation-history and navigation-owned transient state across all high-level behavior transitions. It does not change behavior scores, FLEE policy, movement cadence, stock collision, claim arbitration, relationships, persistence, or logging.

1. **Ownership conclusion**

   Navigation state is stored on the actor runtime for convenience, but most of it belongs to one logical navigation episode. The owning identity is behavior plus target for APPROACH and INVESTIGATE, behavior plus `NavigationGoal.signature` and map for SEEK_FLOCK, the ambient destination for TARGET, and the FLEE escape execution/reference for FLEE.

2. **Episode boundary definition**

   A new episode begins when the high-level behavior changes, when APPROACH or INVESTIGATE replaces its target, when SEEK_FLOCK materially changes goal signature, or when SEEK_FLOCK changes maps. A route replan for the same SEEK_FLOCK goal on the same map is not a new episode.

3. **Non-navigation states**

   IDLE and REST own no route, target, resolved spatial goal, cycle history, or queued movement request. Entering either state releases those fields while preserving actuator state and durable entity data.

4. **Shared cycle-history defect**

   `recentCommittedCells` recorded `targetEntityId`, but `detectShortOscillation` ignored that identity. State-specific cleanup protected TARGET and FLEE exits, but SEEK_FLOCK could hand stale ABAB evidence to a later ordinary behavior.

5. **Observed behavioral consequence**

   A production SEEK_FLOCK to APPROACH transition followed by one completed APPROACH step was misclassified as an ABAB cycle. It set `navigationAvoidTargetId` for the new friend and changed the actor from APPROACH to IDLE.

6. **Cycle-history repair**

   The common post-selection boundary now clears `recentCommittedCells` whenever behavior ownership changes or APPROACH, INVESTIGATE, SEEK_FLOCK, or FLEE changes target identity.

7. **True-cycle control**

   Same-state, same-target APPROACH deliberation retains history. A genuine four-step ABAB pattern within that episode still triggers the existing cooldown and IDLE recovery behavior.

8. **Same-state target replacement**

   APPROACH and INVESTIGATE target replacement clears cycle history and resolved-goal metadata even when the high-level state name does not change.

9. **Target-specific intent defect**

   Before this audit, same-state APPROACH retargeting changed `runtimeState.targetEntityId` but left `intentEpisode.targetId`, progress, commitment, rejection count, and satisfaction attached to the prior target.

10. **Target-specific intent repair**

    `IntentEpisode.afterSelection` now ends and restarts APPROACH or INVESTIGATE when its selected target changes. FLEE and SEEK_FLOCK retain their existing explicit in-place target-update semantics.

11. **SEEK_FLOCK goal identity**

    `NavigationGoal.signature` already provides sufficient goal identity. No new navigation framework or persistent schema was introduced.

12. **Same-goal replan semantics**

    Route completion, source mismatch, execution rejection, motion recovery, and occupancy release may replace a route inside the same goal. They preserve cycle history and static blocked-edge evidence unless existing route logic intentionally changes that evidence.

13. **Goal replacement semantics**

    A material SEEK_FLOCK goal-signature change clears the route, blocked edges, dynamic blocked edges, replan bookkeeping through replacement, and shared cycle history.

14. **Map replacement semantics**

    A map change clears SEEK_FLOCK route-local state and coordinate-scoped cycle history even if the logical goal signature happens to be identical.

15. **Route ownership**

    `runtimeState.navigation.route`, waypoint, route index, planner output, and current goal metadata belong to the active SEEK_FLOCK goal. Leaving SEEK_FLOCK releases the entire `navigation` object.

16. **Blocked-edge ownership**

    `navigation.blockedEdges` belongs to one SEEK_FLOCK goal on one map. It survives same-goal replans so a rejected edge is not retried immediately, and is discarded on goal or map replacement.

17. **Dynamic occupancy ownership**

    `dynamicBlockedEdges`, blocked cell, blocker identity, reservation identity, route suspension, and release diagnostics belong to the active SEEK_FLOCK navigation object. They cannot survive leaving SEEK_FLOCK because that object is released.

18. **Replan-reason ownership**

    `navigation.replanReason` is diagnostic state for the current SEEK_FLOCK goal. Same-goal replans update it; behavior, goal, map, or runtime replacement prevents it from describing an unrelated later problem.

19. **No-progress ownership**

    Ordinary repeated execution failures are carried by the active `intentEpisode`; target-specific APPROACH and INVESTIGATE episodes now restart on retarget. SEEK_FLOCK failure state remains with its active purposeful episode and is discarded when the episode is replaced.

20. **FLEE route ownership**

    `fleeExecution`, escape route, FLEE recent cells, no-progress counters, commitment, blocker state, and planner diagnostics remain FLEE-owned. Leaving FLEE releases `fleeExecution`; entering FLEE releases prior ordinary navigation through the generic transition boundary.

21. **FLEE history symmetry**

    The generic boundary now covers ordinary to FLEE and FLEE to APPROACH, INVESTIGATE, SEEK_FLOCK, TARGET, IDLE, or REST. The prior FLEE-only cycle-history clear is no longer required because ownership cleanup is centralized.

22. **TARGET destination ownership**

    `targetDestination` is one ambient wandering episode's synthetic destination. Completion, rejection, cycle detection, or TARGET exit releases it. Its synthetic ID never becomes `targetEntityId`.

23. **SEEK_FLOCK fallback destination ownership**

    `flockSearchDestination` is transient fallback steering state. Completed/rejected steps and SEEK_FLOCK exit release it; runtime reset also removes it.

24. **Resolved spatial-goal ownership**

    `spatialGoal`, satisfaction state/timing, self and target positions, and distance diagnostics belong to the current behavior/target episode. A centralized reset now clears them at every owner change, including transitions while stock motion is active.

25. **Queued movement-request ownership**

    `movementRequest` is a proposal from the current decision owner. TARGET and SEEK_FLOCK exits clear their queued requests, new behavior execution replaces them, and any active accepted motion clears queued future requests before returning.

26. **Accepted physical-motion ownership**

    `motion` is actuator state, not navigation-episode planning state. A high-level handoff does not cancel accepted stock WALK motion; it may complete normally. The audit regression proves the new owner is selected while `motion.active` remains true and stale route/goal/request state is absent.

27. **Movement-claim ownership**

    Claims belong to a matching queued WALK request or active physical motion. `MovementClaims.validateActor` releases claims on completion, recovery, rejection, destination arrival, cancellation, or staleness. No arbitration behavior changed.

28. **Static collision-memory ownership**

    `rejectedMoves` is actuator-owned, map/source-cell/direction-qualified collision knowledge. It intentionally survives high-level behavior changes, is consulted only when its map and source match, is cleared after successful movement, and is hard-cleared with runtime reconstruction.

29. **Transition matrix result**

    The common owner-change condition covers APPROACH to TARGET/INVESTIGATE/SEEK_FLOCK, INVESTIGATE to APPROACH/TARGET, SEEK_FLOCK to APPROACH/TARGET/INVESTIGATE, TARGET to APPROACH/INVESTIGATE/SEEK_FLOCK, every ordinary state to FLEE, every FLEE exit, and IDLE/REST movement-ending boundaries. State-specific route and destination cleanup remains only where the state owns additional structures.

30. **Validation and residual risk**

    `tests/navigation_episode_ownership_spec.lua` proves TARGET to APPROACH isolation, the previously failing SEEK_FLOCK to APPROACH false-cycle case, true same-episode ABAB detection, same-target preservation, same-state retarget reset, same-goal SEEK_FLOCK preservation, goal/map replacement, 100 repeated goal replacements, and active-motion handoff semantics. Existing intent, navigation, and FLEE ownership suites pass. Scheduler provenance established that the former cross-route failure depended on an obsolete stale-target invalidation rather than a missed emergency; its corrected regression now passes. The isolated full run passes all 50 specs. Runtime reconstruction remains the hard boundary for all transient state; persistence continues to exclude `runtimeState`.

## Answer

One completed navigation problem could previously make a later unrelated problem look cyclic or already in progress. The demonstrated paths were SEEK_FLOCK history contaminating APPROACH cycle detection and APPROACH retargeting retaining the prior target's intent episode. Those paths are now isolated at their logical ownership boundaries, while same-goal replans retain useful anti-oscillation and blocked-edge evidence.
