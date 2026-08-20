# Wild Ecology

Standalone Gen1Recomp mod scaffold focused on persistent wild Pokemon simulation.

## Status

This repository is currently at **Phase 1** from the handoff plan:

- One hard-coded persistent test entity (Pidgey)
- Minimal save payload via storage adapter
- Avatar spawn seam isolated behind `AvatarFactory` and wired to `mod.world:spawnNpc/removeNpc`
- Route-gated test bootstrap in `main.lua`
- `PHASE0 LOG` mod option toggle for rendering a reusable in-game development log overlay
- `PHASE0 BEHAVIOR` option for forcing `NORMAL`, `FORCE IDLE`, or `FORCE FLEE` during in-game verification
- Category toggles and `LOG VIEW` options for filtering lifecycle, behavior, and relationship events during development
- Headless tests for persistence, relationships, population identity, temperament, avatar seam behavior, route exit/re-entry lifecycle, and explicit Phase 1 identity reconstruction

## Next Steps

- Begin Phase 2 relationship behavior expansion (explicit Pokemon->Pokemon demonstration and stronger flee/idle relationship differentials)
- Keep `engine_internals` fallback isolated until it is proven unnecessary on all supported targets
