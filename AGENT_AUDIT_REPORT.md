# Telemetry Cleanup Report

## Conclusion

Telemetry now has three distinct responsibilities. `relationship_audit.bin` is a low-volume semantic journal for directed relationship development. `agent_audit.bin` is a low-volume history of unordered physical encounters plus anomalies. Rich internal reconstruction remains available only when both `AGENT AUDIT` and `BEHAVIOR TRACE` are enabled.

1. **Task boundary**

   This pass changes telemetry only. Relationship gains, contact cadence, event ownership, threat behavior, movement, scheduling, target selection, and persistence are unchanged.

2. **Mechanics baseline**

   The deterministic 500-tick contact regression remains 500 social observations, five bounded social exposures, familiarity 10.375, affinity 9.375, trust 0, and one production contact episode.

3. **Relationship journal ownership**

   `relationship_audit.bin` answers how a directed relationship meaningfully developed. It owns creation, semantic milestones, direct-threat changes, and hostility changes.

4. **Agent history ownership**

   `agent_audit.bin` answers which individuals physically encountered each other. Light mode owns encounter starts, encounter ends, investigation completion, and anomalies.

5. **Forensic ownership**

   Forensic mode answers exactly what happened internally. It retains full mutation records, PRE/EVENT/POST context, rolling history, actor snapshots, and periodic contact samples.

6. **Removed policy**

   The generic five-point accumulated-delta policy has been removed. Smooth fractional growth no longer emits a journal record every five accumulated points.

7. **No synthetic mutation history**

   The journal no longer displays a previous emitted snapshot and a later canonical value as if that span were one atomic mutation.

8. **Atomic threshold detection**

   Threshold crossings are computed from the actual mutation envelope's `before` values and canonical current relationship values.

9. **Canonical snapshots**

   Every semantic milestone contains the complete current six-field relationship snapshot: familiarity, trust, affinity, threat memory, direct-threat memory, and hostility.

10. **Familiarity thresholds**

    Familiarity milestones are 10, 25, 50, 60, 75, and 100. The 60 boundary matches the existing voluntary-join profile requirement.

11. **Trust thresholds**

    Trust milestones are 20, 25, 40, 50, 75, and 100. Existing social-source, following, and voluntary-join logic use boundaries in this set.

12. **Affinity thresholds**

    Affinity milestones are 10, 20, 25, 50, 75, and 100. Existing following and voluntary-join logic use affinity 20.

13. **Threat thresholds**

    Threat-memory milestones are 10, 25, 50, 75, and 100. Direct-threat and hostility changes remain atomic because zero/nonzero changes alter threat classification.

14. **Multi-threshold jumps**

    One atomic mutation crossing several thresholds emits one record with all crossed thresholds, such as `thresholds=10,25`.

15. **Direction changes**

    Milestones identify `crossedUp` or `crossedDown`; downward crossings are not hidden by a growth-only policy.

16. **Creation records**

    The first meaningful allocation emits one `RELATIONSHIP_CREATED` record. Repeated contact does not duplicate creation history.

17. **Direct-threat fidelity**

    `DIRECT_THREAT_LEARNED` and `DIRECT_THREAT_MEMORY_CHANGED` retain literal before/after values for the field changed by that atomic mutation.

18. **Hostility fidelity**

    `HOSTILITY_CHANGED` retains literal before/after hostility values. Social Fear does not fabricate direct-threat identity.

19. **Directed identity**

    Relationship journal keys remain directed. A-to-B and B-to-A are independent sparse records and are never merged.

20. **Physical identity**

    Agent encounter keys are canonical unordered pairs. Bidirectional observations of A and B contribute to one physical episode.

21. **Directed summaries inside encounters**

    Each physical episode stores separate A-to-B and B-to-A start/end values, creation flags, relationship mutation counts, and social-exposure mutation counts.

22. **Encounter lifecycle**

    Light mode emits one `CONTACT_EPISODE_START` and one `CONTACT_EPISODE_END`. End records contain start tick, last contact tick, end-detection tick, duration, observation counts, distance range, and both directed summaries.

23. **No light heartbeat**

    `CONTACT_EPISODE_SAMPLE` is absent when `BEHAVIOR TRACE` is off. Long uninterrupted contact therefore does not create a record every 100 ticks.

24. **No duplicated journal events**

    Light agent audit no longer repeats relationship creation, semantic threshold, or ordinary direct-threat records owned by relationship audit.

25. **Anomalies remain loud**

    Relationship object replacement, unexpected peaceful decreases, audit mismatches, provenance problems, and other anomaly paths remain available in light mode.

26. **Early forensic gate**

    Rolling actor histories and expensive mutation/context payloads are constructed only after forensic mode is confirmed. Light mode does not pay for data it will not write.

27. **I/O accounting**

    Both audits report writer-call counts and actual bytes passed to the storage writer, in addition to record and buffered-byte counters.

28. **Relationship soak**

    The 20-Pokemon, 10,000-tick journal soak observed 26,640 contact calls and 3,840 consequential mutations. It emitted 520 semantic records, suppressed 3,520 routine mutations, wrote 135,812 bytes in one writer call, and used one file. The old monotonic five-point policy is estimated at about 1,640 records for the same histories.

29. **Agent soak**

    The 10,000-tick light encounter soak used ten bidirectionally observed physical pairs. It emitted 10 starts and 10 ends: 20 records, 23,415 actual I/O bytes, two writer calls, one file, 2 records per 1,000 ticks, and 2,341.5 bytes per 1,000 ticks. It emitted no samples or anomaly records.

30. **Dense and asymmetric validation**

    Six densely connected agents produced 15 unordered physical episodes, 30 directed relationships, and 30 light records. A separate asymmetric pair emitted one start/end while retaining A-to-B familiarity/affinity 50/40 and B-to-A 10/5.

31. **Mode-cost measurement**

    A fixed 2,000-tick single-pair run measured approximately 0.001 seconds OFF, 0.008 seconds LIGHT, and 0.011 seconds FORENSIC on this machine. Light agent audit emitted two records and 2,358 bytes; forensic emitted 45 records and 965,023 bytes. Timings are directional, but record and byte differences demonstrate the intended gate.

32. **Validation and rollover**

    Semantic journal rollover preserves complete records exactly once with monotonic sequence numbers. Forensic agent rollover remains intact. All 54 Lua specs pass in fresh Lua 5.5 processes, and both focused telemetry suites pass after dead directed-episode code removal.

## Storage Behavior

Both audit families retain record-aware 196 KiB numbered rollover. Normal gameplay with `REL AUDIT = ON`, `AGENT AUDIT = ON`, and `BEHAVIOR TRACE = OFF` uses buffered semantic milestones and encounter boundaries; it does not emit routine proximity samples or full forensic mutation payloads. Audit buffers, physical episodes, histories, and counters are runtime-only and never enter save data.
