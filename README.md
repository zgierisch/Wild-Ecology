# Wild Ecology

Wild Ecology is a standalone Gen1Recomp ecology mod for persistent wild
Pokemon, visible overworld populations, naturalistic behavior, generic
entity-to-entity relationships, social learning, and future voluntary joining.

## Current Status

The mod currently provides persistent population identity, disposable runtime
avatars, generic perception and directed relationships, utility-scored
behavior, social fear/reassurance, collision-authoritative WALK navigation,
world semantics, persistent needs, drinking and compatible tall-grass forage,
REST and compatible concealment, local home return, ecology clocks, bounded
dormant catch-up, and validated species ecology profiles.

The player participates in the same relationship graph as other entities.
Runtime engine objects and in-progress commands are not persistent state.
Gen1Recomp remains an immutable runtime dependency, and reference mods are not
dependencies.

See [ARCHITECTURE.md](ARCHITECTURE.md) for current contracts:

- [World semantics](ARCHITECTURE.md#7-world-semantics)
- [Needs, feeding, rest, and home](ARCHITECTURE.md#8-needs-feeding-rest-and-home)
- [Clock and dormancy](ARCHITECTURE.md#9-clock-and-dormancy)
- [Species authoring](ARCHITECTURE.md#10-species-authoring)
- [Diagnostics](ARCHITECTURE.md#11-diagnostics)
- [Validation and limits](ARCHITECTURE.md#12-validation-and-limits)

Incomplete work and release direction are tracked in
[WILD_ECOLOGY_ROADMAP.md](WILD_ECOLOGY_ROADMAP.md).

## Local Setup and Validation

Wild Ecology does not redistribute Pokemon overworld artwork. Follow
[ASSETS.md](ASSETS.md) to import compatible local sprite sheets into the
ignored `generated-assets/ow_sprites/` directory.

Run deterministic specs in separate Lua processes. On the inspected Windows
environment, the validation entry point is:

```powershell
$luaExe = 'C:\Program Files\Lua\lua55.exe'
Get-ChildItem tests -Filter '*_spec.lua' | Sort-Object Name | ForEach-Object {
  & $luaExe $_.FullName
  if ($LASTEXITCODE -ne 0) { throw "Failed: $($_.Name)" }
}
```

The ROM-derived world-semantics spec uses `GEN1RECOMP_RED_CACHE` when set and
skips cleanly when generated map, tileset, or field fixtures are unavailable.

## Relationship Audit Log

The compact relationship audit is off by default. Open the in-game Start menu,
select `WILD ECOLOGY LOGS`, and set `REL AUDIT` to `ON`. The change applies
immediately and is retained in the mod save settings. Turning it off flushes
pending records and stops collection without requiring a restart.

Audit files are written under the LOVE save directory, beginning with
`relationship_audit.bin`. Each file is limited to 196 KiB; overflow continues
in `relationship_audit_2.bin`, `relationship_audit_3.bin`, and later files.
This file is the directed semantic journal: it records relationship creation,
meaningful threshold crossings, and atomic direct-threat or hostility changes.
Routine fractional growth does not create journal records.

For root-cause capture, enable `AGENT AUDIT` in the same menu. This separate,
default-off flight recorder writes `agent_audit.bin`, then
`agent_audit_2.bin`, `agent_audit_3.bin`, and later continuation files. It
normally records one start and one end for each unordered physical encounter,
plus investigation completion and rare relationship anomalies. Each encounter
contains separate A-to-B and B-to-A directed relationship summaries. Routine
proximity produces neither periodic samples nor full-state mutation records.
To capture expensive mutation/PRE/EVENT/POST context and periodic samples,
explicitly enable both `AGENT AUDIT` and `BEHAVIOR TRACE`. Turning agent audit
off flushes the active file and releases all transient recorder state.