# Wild Ecology

Standalone Gen1Recomp mod scaffold focused on persistent wild Pokemon simulation.

## Status

This repository is currently at **Phase 0** from the handoff plan:

- One hard-coded persistent test entity (Pidgey)
- Minimal save payload via storage adapter
- Avatar spawn seam isolated behind `AvatarFactory`
- Route-gated test bootstrap in `main.lua`

## Next Steps

- Replace placeholder world hooks with confirmed Gen1Recomp public API calls
- Fall back to `engine_internals` only if public spawn API is unavailable
- Add tests for persistence and relationship updates
