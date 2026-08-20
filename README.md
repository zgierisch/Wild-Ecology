# Wild Ecology

Standalone Gen1Recomp mod scaffold focused on persistent wild Pokemon simulation.

## Status

This repository is currently at **Phase 0** from the handoff plan:

- One hard-coded persistent test entity (Pidgey)
- Minimal save payload via storage adapter
- Avatar spawn seam isolated behind `AvatarFactory` and wired to `mod.world:spawnNpc/removeNpc`
- Route-gated test bootstrap in `main.lua`
- `PHASE0 LOG` mod option toggle for rendering a reusable in-game development log overlay
- `PHASE0 BEHAVIOR` option for forcing `NORMAL`, `FORCE IDLE`, or `FORCE FLEE` during in-game verification
- Category toggles and `LOG VIEW` options for filtering lifecycle, behavior, and relationship events during development
- Headless tests for persistence, relationships, population identity, temperament, avatar seam behavior, and route exit/re-entry lifecycle

## Next Steps

- Verify in-game spawn object tuning (sprite/cell/movement) on the Route 1 phase-0 path
- Keep `engine_internals` fallback isolated until it is proven unnecessary on all supported targets
