# Cross-Route Scheduler Provenance

## Scope

This investigation explains why `cross_route_lifecycle_spec.lua` expected three Route 2 decisions while current production produced two. No Fear coefficient, Fear cadence, scheduler cadence, Controller behavior, FLEE utility, or navigation ownership logic was changed.

1. **Failing assertion and scenario**

   After Route 2 materialization and 15 off-screen lifecycle ticks, the selected ordinary entity has completed `INITIAL` and `CADENCE` deliberations (`behaviorDecisionCount == 2`). The fixture then sets the player relationship's trust to 0 and both threat-memory fields to 80, moves the player onto the entity's home cell, advances one lifecycle tick, and expected the count to become 3.

2. **Original expectation versus observation**

   Original expected count: 3. Current observed count: 2. The assertion described the condition as “already urgent,” but the entity entered the tick with `fearCurrent == 0.0004`; durable threat memory was high, current Fear was not.

3. **Counter semantics**

   `behaviorDecisionCount` has one production writer: `recordBehaviorDecision` in `main.lua`. It increments once after a completed high-level `evaluateVisibleEntity` call. It does not count perception, Fear integration, reactive checks, or `Controller.executeCurrentIntent` calls.

4. **Related counters**

   `behaviorDecisionTicks` is the map-level count of the same completed deliberations. `schedulerMetrics.highLevelDeliberations` increments alongside it. `emergencyInterrupts` increments only when the recorded reason is `EMERGENCY_THREAT` or `SEVERE_EVENT`.

5. **Exact call chain**

   `OverworldController.update` hook -> `WildEcology.sync` -> `observeActivePopulation` -> `updateActivePopulationBehavior` -> `updateVisibleFear` -> `Controller.reconsiderationReason`. A reason calls `evaluateVisibleEntity` -> `Controller.tick` -> `Controller.chooseState` -> `recordBehaviorDecision`. No reason calls `executeVisibleEntity` -> `Controller.executeCurrentIntent`; only a terminal execution result then requests `evaluateVisibleEntity`.

6. **Missed-increment owner**

   `recordBehaviorDecision` owns the increment, but it was correctly not reached on current tick 37 because neither `Controller.reconsiderationReason` nor current-intent execution produced a qualifying reason. The scheduler branch deciding this is `updateActivePopulationBehavior`.

7. **Route 2 timeline: entry**

   Tick 21, Route 2: Fear integrates (`lastFearTick=21`) and remains 0. `lastDecisionTick` is absent, so reason is `INITIAL`; `Controller.tick` runs; count becomes 1; resulting state is INVESTIGATE.

8. **Route 2 timeline: ordinary cadence**

   Ticks 22-35: Fear integrates on ticks 24, 27, 30, 33 and remains approximately 0; other ticks are execution-only. No high-level reason occurs. Tick 36 integrates Fear to 0.0004, reason is `CADENCE`, `Controller.tick` runs, count becomes 2, state remains INVESTIGATE, and `nextDecisionTick` becomes 51.

9. **Route 2 timeline: first contact**

   Tick 37: player distance changes to 0, forcing Fear integration. Fear changes from 0.0004 to 0.5903; `fearDirect` is 0.8432; assessment identifies player at distance 0 but is not severe. Emergency requires severe assessment or current Fear at least 0.85. Therefore reason is `NOT_DUE`, no `Controller.tick` occurs, and count remains 2.

10. **Controller boundary proof**

    Temporary test-only instrumentation recorded 15 `chooseState` calls on tick 37, all from execution-only updates for the visible population, and exactly zero `Controller.tick` calls. The missing high-level count therefore occurs before deliberative `Controller.chooseState`; ordinary execution still runs.

11. **Current behavioral response**

    Tick 40 is the next due Fear integration. Fear reaches 0.8778, `EMERGENCY_THREAT` is emitted, `Controller.tick` runs, and the actor enters FLEE with `selectionReason == EMERGENCY_FLEE`. There is no one-integration response delay: the actor reacts on the first integration that actually crosses emergency urgency.

12. **Pre-audit production result**

    A disposable workspace copy reversed only the navigation-audit production edits. The original spec passed: expected 3, observed 3. This proves the suite failure was exposed by the navigation ownership work rather than being pre-existing.

13. **Current production result before test correction**

    The original spec failed deterministically in five fresh Lua processes: expected 3, observed 2 every time. No module cache, persistent storage, test order, or random population selection changed the result.

14. **One-file isolation**

    Current controller + prior `intent_episode.lua`: pass, 3 observed. Prior controller + current `intent_episode.lua`: fail, 2 observed. The target-specific intent restart is the exact coupling; recent-cell cleanup, spatial-goal cleanup, and SEEK_FLOCK goal/map cleanup are not involved.

15. **Why the prior version passed**

    The prior INVESTIGATE episode still owned target `wild:route02:0044`. On tick 37 execution invalidated that stale target and returned `INTENT_INVALIDATED`, causing an immediate second-stage deliberation. That deliberation changed the episode target to `wild:route02:0039` and incremented the count to 3.

16. **Why the prior pass was semantically wrong**

    The recorded reason was `INTENT_INVALIDATED`, not `EMERGENCY_THREAT`. Fear was still 0.5903 and non-severe. The candidate was FLEE, but hysteresis retained INVESTIGATE. The old test therefore mislabeled an unrelated stale-target cleanup as an immediate urgent-Fear response.

17. **INITIAL and route-transition semantics**

    Route entry requires one `INITIAL` deliberation. `INITIAL` has precedence because no prior decision exists. A threat that becomes severe on entry and already-urgent Fear carried into entry are both consumed by that one deliberation; INITIAL plus emergency is not double-counted as two high-level decisions.

18. **Comparison with scheduler regression contract**

    `deliberation_scheduler_spec.lua` requires a new severe event to interrupt ordinary behavior, sustained severe danger not to repeatedly interrupt active FLEE, terminal intents to reconsider immediately, and normal cadence at 15 ticks. New controls explicitly verify INITIAL precedence for no-threat, newly severe, and already-urgent route entry, plus execution-only sustained-FLEE ticks followed by cadence.

19. **Cases A-F**

    | Case | Fear integrations | High-level deliberations | Reason | Count effect | Result |
    | --- | --- | --- | --- | --- | --- |
    | A. Route entry, no threat | Initial integration | 1 | INITIAL | 0 -> 1 | Ordinary selected behavior |
    | B. Route entry, threat becomes urgent on entry | Initial integration | 1 | INITIAL | 0 -> 1 | Same decision observes emergency and selects FLEE |
    | C. Route entry, Fear already urgent | Initial integration | 1 | INITIAL | 0 -> 1 | Same decision observes emergency; no double count |
    | D. Active FLEE, sustained urgent threat | Every 3 ticks or qualifying update | Cadence only | CADENCE | +1 per cadence | FLEE retained; execution continues between decisions |
    | E. Active non-FLEE, new severe threat | Immediate qualifying integration | 1 | SEVERE_EVENT or EMERGENCY_THREAT | +1 | Immediate FLEE |
    | F. Same urgent condition over several ticks | Every 3 ticks | First crossing plus cadence | EMERGENCY_THREAT, then CADENCE | No per-tick increments | Active FLEE executes without utility hot loop |

20. **Change made**

    `cross_route_lifecycle_spec.lua` now asserts that first contact integrates Fear immediately but remains below 0.85 and does not borrow an unrelated intent invalidation. It then advances through the next Fear integration and requires immediate FLEE with `EMERGENCY_THREAT` and `EMERGENCY_FLEE`. The assertion was corrected because its old count depended on the ownership defect that this audit intentionally fixed.

21. **Conclusion**

    Production scheduler behavior is correct; the test expectation was stale. Navigation ownership did indirectly expose the failure by removing a stale intent invalidation, but did not suppress a real emergency event. Event-driven FLEE scheduling remains intact: perception is frequent, Fear integrates independently, emergency crossing interrupts immediately, sustained FLEE executes without per-tick deliberation, and cadence remains authoritative. The six required focused suites pass, and the final isolated run passes all 50 specs.
