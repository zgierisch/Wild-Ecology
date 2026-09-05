# Investigation Relationship Ownership Audit

## Conclusion

`INVESTIGATION_COMPLETED` had a real event-ownership bug. The controller changed behavior and intent ownership before emitting the completion, then labeled the event with the newly selected target while mutating the relationship table passed into the deliberation. That table was often the observer's canonical player relationship. The completed subject's canonical table was not replaced; an unrelated canonical table was temporarily reported as the completed pair and received the reward.

1. **Exact production call chain**

   On a deliberation tick, `Controller.chooseState` captures the prior state/target, builds the newly selected entity target, computes `investigateElapsed`, calls `IntentEpisode.observe`, scores behavior, selects the next state, writes `runtimeState.state`, calls `IntentEpisode.afterSelection`, emits and applies `INVESTIGATION_COMPLETED`, assigns the next `runtimeState.targetEntityId`, clears owner-specific navigation state, and returns. `Controller.tick` then runs the selected state handler.

2. **Completed identity establishment**

   `IntentEpisode.observe` owns the interaction target in `intentEpisode.targetId`. While A is investigating B, `episodeTarget` resolves B from the active runtime/episode, and the returned episode retains `targetId = B`. This is the authoritative completed target.

3. **Behavior/intent replacement point**

   `runtimeState.state` changes before completion emission. `IntentEpisode.afterSelection` then interrupts/replaces the old INVESTIGATE episode and may create FLEE, APPROACH, or SEEK_FLOCK ownership for C/player before the relationship reward executes.

4. **Target values at the boundary**

   Before selection, `runtimeState.targetEntityId = B`, active `intentEpisode.targetId = B`, and the resolved spatial goal belongs to B. During selection, `selectedEntityTargetId = C` (or player), while the observed old episode still exposes B. After `afterSelection`, the new intent episode may own C, but `runtimeState.targetEntityId` remains B until its later assignment. The behavior state is already the next state. After the function, runtime target and spatial/navigation ownership belong to the next behavior.

5. **Previous mutation target ID**

   Production previously passed `selectedEntityTargetId` to `Relationships.recordMutation`. This was the target proposed for the next deliberation, not the completed episode target.

6. **Table that received +30**

   Production mutated the local `rel = playerRelationship or {}` argument. Main normally supplies the relationship chosen for current threat/social scoring. In the reproduced B-to-C FLEE transition, canonical A-to-C received B's +30 while A-to-B remained unchanged. In the live pattern, the recurring table was commonly canonical A-to-player.

7. **Why one token recurred per observer**

   Each observer has one stable canonical player relationship. Reusing that table for several completion mutations while labeling each mutation with a different selected subject made one token appear to be an observer-owned investigation scratch object. It was not scratch state; it was a real relationship under the wrong event identity.

8. **Was canonical A-to-B replaced?**

   No. The only production assignment to `entity.relationships[targetId]` is the canonical constructor in `Relationships.getOrCreate`. Perception's similarly named local result map does not replace entity state. A-to-B remained intact while another table was mislabeled and mutated.

9. **Defect classification**

   The defect combined event-payload ownership, wrong-target lookup, and ordering. It was not persistence corruption, random logger noise, a relationship reset, or a cached scratch relationship.

10. **Structural fix**

    Immediately after `IntentEpisode.observe`, the controller captures `episode.targetId` when the episode is INVESTIGATE. If that state is actually left, it resolves `Relationships.getOrCreate(entity, completedTargetId)` and uses that ID/table for diagnostics, mutation, and the post-event snapshot.

11. **Why the fix is canonical**

    The reward mutates `entity.relationships[completedTargetId]` directly through the sole canonical constructor/accessor. No values are copied from the wrong table and no post-hoc repair occurs.

12. **Single-subject result**

    A investigating B with no subject change retains the same canonical A-to-B object and applies the capped familiarity reward there.

13. **B/C/D result**

    Seeded A-to-B = 1/2 familiarity/affinity, A-to-C = 11/12, and A-to-D = 21/22. Sequential completions produce 31/2, 41/12, and 51/22 respectively; after each step only the completed target changes.

14. **Retarget-to-C result**

    A completes B and normally transitions to APPROACH C after existing hysteresis permits it. B receives +30; C receives none of B's reward.

15. **FLEE result**

    A completes B while a severe C/player threat legitimately selects FLEE. B receives +30. The threat relationship and FLEE target remain independent.

16. **SEEK_FLOCK result**

    A completes B and selects SEEK_FLOCK toward C. B receives +30; C's relationship remains unchanged.

17. **Directionality result**

    Completion mutates only A-to-B. It does not construct or mutate B-to-A. Direct-threat controls remain directed as well.

18. **Object identity result**

    Canonical A-to-B compares equal before completion, immediately after completion, after `SOCIAL_NEARBY`, after `ENTITY_RETREATING`, and after runtime reconstruction followed by a new investigation.

19. **Replacement anomalies**

    The live baseline contained approximately 36 paired `RELATIONSHIP_OBJECT_REPLACED` records. Fixed canonical completion plus follow-up events produces zero replacement anomalies, including the 30-completion stress run. The detector remains unchanged and still catches deliberate replacement in its existing regression.

20. **Wrong-subject mutation count**

    The deterministic pre-fix B-to-C reproduction produced one wrong-subject mutation out of one completion. The fixed live-like run produced zero wrong-subject mutations across 30 completions.

21. **Reset-like sequence**

    A high A-to-B relationship at familiarity/trust/affinity 90/7/95 becomes 100/7/95 after completion, then continues on the same object through social proximity. There is no 90-to-30-to-95 object-switch pattern.

22. **Relationship journal correctness**

    The relationship audit receives subject B, canonical A-to-B `relationshipRef`, and canonical current values. Its semantic journal remains enabled and unchanged.

23. **Agent audit correctness**

    Agent audit sees the same canonical table for completion and later A-to-B events. Legitimate execution emits no replacement anomaly; no logger special case was added.

24. **Reward formula**

    On leaving INVESTIGATE after positive elapsed time, familiarity gain is `min(30, investigateElapsed * 3)`, then familiarity is clamped to 0..100. Trust, affinity, threat memory, direct-threat memory, hostility, and metadata receive no completion delta.

25. **Coefficient confirmation**

    The +3-per-tick and +30 cap are unchanged. Social exposure interval remains 100 ticks, contact separation remains 30 ticks, and all peaceful-contact coefficients are unchanged.

26. **CALM_PROXIMITY root cause**

    `observeCalmProximity` previously called `getOrCreate` before computing whether distance produced a nonzero signal. At distance greater than 8, it changed only `lastSeenTick` and emitted a zero-valued creation. `PopulationManager.updatePhase0Relationship` then raised trust to the legacy default outside the mutation envelope, explaining zero-valued creation records followed by a retained relationship.

27. **Sparsity measurement**

    Twenty unrelated materialized Pokemon receiving only out-of-range calm player observation previously allocated 20 persistent player relationships and emitted 20 zero-valued CALM_PROXIMITY creations. After the fix, both counts are zero.

28. **Sparse allocation change**

    Sparse allocation was changed only for a new relationship with zero distance multiplier. Existing relationships still receive metadata updates, and meaningful near calm contact still allocates normally.

29. **Exact creation rule**

    CALM_PROXIMITY creates a relationship when its distance multiplier is positive. If multiplier is zero, it mutates metadata only when a canonical relationship already exists; otherwise it returns transiently without allocation. ENTITY_SEEN, SOCIAL_NEARBY, and direct threat retain their existing constructors and semantics.

30. **Generic player architecture**

    The rule is keyed by generic target entity ID. Player remains the ordinary trainer entity in the directed relationship graph; no player-specific field, reciprocal update, or schema change was introduced.

31. **General log findings**

    The current normal synthetic workload emitted 634 records/106,048 bytes: Fear 310 records (48.83%), movement requests 80 (13.20%), FLEE provenance 43 (6.22%), and FLEE route 19 (4.46%). FLEE provenance already dedupes by threat/reference identity. FLEE route already aggregates unchanged semantic state. Fear emits source/provenance, activation bands, direct/social balance, FLEE transitions, and changes of at least 0.05 while suppressing calm bookkeeping.

32. **Logging change decision**

    No additional telemetry dedupe was implemented. Movement remains the clearest future target: its signature includes changing `noProgressSteps`, so equivalent blocked-cell failures can re-emit. A future telemetry-only policy should key actor/intent/source cell/direction/reason/goal, emit first and changed conditions, then summarize repeats when the condition changes or ends.

33. **Mechanics preservation**

    Fear, FLEE, navigation, movement, scheduler cadence, target-selection weights, utility, persistence schema, relationship coefficients, contact cadence, and logging thresholds are unchanged. No telemetry anomaly was suppressed.

34. **Validation**

    All 56 Lua specs pass in fresh Lua 5.5 processes. The focused ownership/sparsity/audit/navigation/telemetry set passes, exact 500-tick contact output remains familiarity 10.375 and affinity 9.375, and modified production modules outside the controller have no diagnostics. The controller retains unrelated pre-existing nullable navigation warnings; the ownership change introduces no new diagnostic location.

## Primary Invariant

A completed interaction now carries the completed episode's target identity. If A leaves INVESTIGATE after acting against B, every relationship consequence and diagnostic uses canonical `A.relationships[B.id]`, regardless of the next state, next target, FLEE threat, SEEK_FLOCK goal, runtime target assignment, or intent replacement.
