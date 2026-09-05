package.path = package.path .. ";./?.lua;./?/init.lua"

local DormantLifecycle = require("src.dormant.dormant_lifecycle")
local Entity = require("src.entities.entity")
local WorldSemantics = require("src.world.world_semantics")

local entity = Entity.newWildPokemon({ id = "persistent", species = "PIDGEY",
  level = 4, personalitySeed = 9, firstEncounteredTick = 0 })
entity.drives.THIRST.value = 0.4
entity.runtimeState = { state = "TARGET", movementRequest = { direction = "UP" },
  navigation = { route = { actions = { "fictional" } } } }
local state = { populations = { ROUTE_22 = { members = { persistent = entity } } },
  dormantCohorts = {} }
local sample = { source = "REAL_TIME", monotonicEcologyTime = 1000 }
local cohort = DormantLifecycle.capture(state, "ROUTE_22", { entity }, sample, {
  reachableWater = true,
  positions = { persistent = { cellX = 4, cellY = 5 } }
})
assert(cohort.memberIds[1] == "persistent",
  "only actually materialized identities belong to the cohort")
assert(cohort.memberSnapshots.persistent.lastPosition.cellX == 4,
  "exact unload cell is retained only as coarse provenance")
assert(cohort.memberSnapshots.persistent.state == "TARGET",
  "coarse unload state may inform dormant ecology")
assert(cohort.memberSnapshots.persistent.navigation == nil,
  "cohort snapshot must not serialize navigation")
assert(cohort.environment.reachableWater == nil,
  "cohorts should store generalized opportunity evidence, not water fields")
assert(cohort.environment.opportunityEvidence.THIRST.persistent.proven == true,
  "legacy water input should become actor-scoped drive evidence")

entity.runtimeState = nil
local result = DormantLifecycle.catchUpBeforeMaterialization(state, "ROUTE_22",
  { source = "REAL_TIME", monotonicEcologyTime = 1000 + 8 * 3600 })
assert(result and result.elapsed == 8 * 3600,
  "catch-up should run lazily before materialization")
assert(entity.runtimeState == nil,
  "dormant catch-up must not reconstruct stale RuntimeState")
assert(cohort.dormant == false, "one access should consume the dormant interval")
assert(DormantLifecycle.catchUpBeforeMaterialization(state, "ROUTE_22",
  { source = "REAL_TIME", monotonicEcologyTime = 1000 + 8 * 3600 }) == nil,
  "repeated materialization checks must not replay catch-up")

DormantLifecycle.capture(state, "ROUTE_22", { entity },
  { source = "REAL_TIME", monotonicEcologyTime = 50000 }, {})
local switched = DormantLifecycle.catchUpBeforeMaterialization(state, "ROUTE_22",
  { source = "SIMULATION", monotonicEcologyTime = 200 })
assert(switched.elapsed == 0,
  "clock-source switching should rebase dormant timestamps without reversing state")

local forageMap = assert(WorldSemantics.fromOverview({
  mapId = "FORAGE_EVIDENCE", width = 3, height = 1, rows = { "..." }
}, { cells = {
  [WorldSemantics.cellKey(2, 0)] = { terrain = "TALL_GRASS" }
} }))
local pidgey = Entity.newWildPokemon({ id = "forager", species = "PIDGEY",
  level = 4, personalitySeed = 10 })
local goldeen = Entity.newWildPokemon({ id = "aquatic", species = "GOLDEEN",
  level = 4, personalitySeed = 11 })
local foodEvidence = DormantLifecycle.opportunityEvidence(
  pidgey, "HUNGER", forageMap, { cellX = 0, cellY = 0 })
assert(foodEvidence and foodEvidence.opportunityType == "TALL_GRASS_FORAGE",
  "compatible reachable forage should produce conservative unload evidence")
assert(DormantLifecycle.opportunityEvidence(
  goldeen, "HUNGER", forageMap, { cellX = 0, cellY = 0 }) == false,
  "unsupported species must not receive dormant terrestrial food evidence")