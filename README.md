# Wild Ecology

Standalone Gen1Recomp mod scaffold focused on persistent wild Pokemon simulation.

## Status

This repository is currently at **Phase 0** from the handoff plan:

- One hard-coded persistent test entity (Pidgey)
- Minimal save payload via storage adapter
- Avatar spawn seam isolated behind `AvatarFactory` and wired to `mod.world:spawnNpc/removeNpc`
- Route-gated test bootstrap in `main.lua`
- Headless tests for persistence, relationships, population identity, temperament, and avatar seam behavior

## Next Steps

- Verify in-game spawn object tuning (sprite/cell/movement) on the Route 1 phase-0 path
- Add integration tests for map exit/re-entry avatar reconstruction behavior
- Keep `engine_internals` fallback isolated until it is proven unnecessary on all supported targets
