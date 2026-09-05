# Relationship Telemetry Audit

## Scope

`relationship_audit.bin` is a compact semantic journal for sparse directed relationships. This telemetry-only implementation does not change relationship mutation frequency, gains, contact cadence, behavior, threat handling, movement, perception, scheduling, or persistence.

## Journal Policy

- `RELATIONSHIP_CREATED` records the first meaningful allocation and its cause.
- `FAMILIARITY_MILESTONE` records crossings at 10, 25, 50, 60, 75, and 100.
- `TRUST_MILESTONE` records crossings at 20, 25, 40, 50, 75, and 100.
- `AFFINITY_MILESTONE` records crossings at 10, 20, 25, 50, 75, and 100.
- `THREAT_MILESTONE` records threat-memory crossings at 10, 25, 50, 75, and 100.
- `DIRECT_THREAT_LEARNED`, `DIRECT_THREAT_MEMORY_CHANGED`, and `HOSTILITY_CHANGED` preserve atomic changes because their zero/nonzero state changes production threat classification.

Crossings are detected from each real mutation's `before` values to its canonical current relationship values. A record includes the crossing direction and full current six-field snapshot. One mutation crossing several boundaries emits one line with all thresholds. The journal does not coalesce unrelated mutations into a synthetic old-to-new mutation.

`lastSeenTick` and `importance` do not trigger records by themselves. Smooth changes between semantic boundaries are suppressed. A-to-B and B-to-A remain independent journal identities.

## Storage

Records use version 2 and a monotonic sequence number. Files are capped at 196 KiB and rotate at complete-record boundaries from `relationship_audit.bin` to `_2.bin`, `_3.bin`, and later numbered files. Oversized records are dropped rather than split. Existing segments are retained.

Dirty segments flush at existing lifecycle flush points, no more frequently than once per 30 simulation ticks, and force-flush when collection ends. Storage calls are protected by `pcall`; failed dirty data remains available for retry. Successfully written completed segments release their text.

The snapshot reports observed mutations, emitted/suppressed records, record categories, buffered bytes, actual writer calls, actual bytes passed to the writer, files, rotations, drops, and failures. All journal state is transient and is never serialized.

## Measured Workload

The deterministic 20-Pokemon, 10,000-tick soak produced:

| Metric | Result |
|---|---:|
| Contact calls | 26,640 |
| Consequential mutations | 3,840 |
| Semantic journal records | 520 |
| Suppressed routine mutations | 3,520 |
| Actual bytes written | 135,812 |
| Writer calls | 1 |
| Files | 1 |

The prior generic five-point accumulated-delta policy is estimated to have emitted about 1,640 records for the same monotonic histories. The semantic policy emits 520 while preserving production-relevant boundaries and canonical current state.

Rollover tests recover every record exactly once with monotonic sequence numbers and no split records. The full isolated suite passes all 54 Lua specs.
