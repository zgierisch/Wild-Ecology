# Needs and Motivational Drives Audit

## Scope

This is the Phase 8 drive foundation, not completion of Phase 8. It proves the
reusable architecture with THIRST, HUNGER/foraging, and motivation-gated
rest-site/concealed REST. Local RETURN_HOME now competes through the same
utility/hysteresis architecture without becoming a drive or schedule.
Deterministic long-horizon composition is proven in
`COMPOSED_DAILY_RHYTHM_AUDIT.md`; live tuning, richer food ecology, dynamic home
relocation, and cross-map return remain open.

## Ownership

- `src/needs/drive_definitions.lua` owns normalized drive policy and thresholds.
- `src/needs/drives.lua` owns persistent deficit evolution and satisfaction.
- `src/needs/need_strategy.lua` maps a motivating drive to reachable semantic
  opportunities without owning terrain classification or route execution.
- `src/behavior/utility.lua` decides whether an available need opportunity is
  worth disturbing `SETTLED` equilibrium.
- `src/behavior/intent_episode.lua` owns purposeful completion and applies the
  satisfaction event only after arrival.
- `src/world/world_semantics.lua` owns `WATER_ADJACENT` meaning.
- `src/navigation/navigation_execution.lua` and the existing planner own routes.
- Fear and directed relationships remain independent systems.

## State Model

Drive values are normalized to `[0, 1]`. Persistent records contain only the
value plus `lastUpdatedTick` and `lastSatisfiedTick`. Runtime motivation latches,
bands, failed-goal cooldowns, destinations, routes, and intent episodes are not
serialized. Updates use elapsed simulation ticks, so repeated reads at one tick
do not accelerate biology and rematerialized actors catch up deterministically.

THIRST starts at a deterministic calm value in `[0.12, 0.20]`, accumulates at
`0.0005` per simulation tick, activates at `0.65`, and releases at `0.20`.
Separate thresholds prevent oscillation. Drinking reduces thirst by `0.70`;
the generic API also supports smaller partial reductions.

## Opportunity and Failure Rules

THIRST queries only `WATER_ADJACENT` land cells. Candidates are sorted by the
WorldSemantics query and accepted only when the stock planner proves a WALK
route. Goal identity includes drive, semantic, map, traversal mode, and cell.
Identical failed preflight plans are suppressed for 180 ticks; actor movement,
map changes, or a different candidate naturally produce a different signature.
No water and unreachable water produce no fabricated behavior objective.

## Diagnostics

`Drives.inspect(entity, tick)` reports compact per-drive value, urgency, band,
motivation state, and last satisfaction. A diagnostic sink receives only
threshold-crossing and satisfaction events. Aggregate counters report updates,
elapsed ticks, crossings, satisfactions, semantic planner calls, suppressed
plans, and accepted opportunities without per-tick logging.

## Verification

Deterministic tests prove calm initialization, elapsed-time correctness,
activation/release hysteresis, partial satisfaction, persistence migration,
runtime reset safety, multi-actor independence, 10,000-tick bounds, unreachable
goal suppression, FLEE interruption, and the full autonomous lifecycle:
`SETTLED -> SATISFY_NEED -> WATER_ADJACENT -> drink -> SETTLED`.