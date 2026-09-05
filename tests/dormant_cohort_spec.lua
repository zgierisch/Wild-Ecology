package.path = package.path .. ";./?.lua;./?/init.lua"

local DormantCohort = require("src.dormant.dormant_cohort")
local Simulator = require("src.dormant.dormant_cohort_simulator")
local Entity = require("src.entities.entity")
local Drives = require("src.needs.drives")
local EcologyPhysiology = require("src.species.ecology_physiology")

local HOUR = 3600
local DAY = 24 * HOUR

local function actor(id, seed, profile)
  local entity = Entity.newWildPokemon({ id = id, species = "PIDGEY",
    level = 4, personalitySeed = seed, firstEncounteredTick = 0 })
  entity.ecology.activityProfile = profile or "DIURNAL"
  entity.relationships = {}
  return entity
end

local wet = actor("wet", 1)
local dry = actor("dry", 2)
wet.drives.THIRST.value, dry.drives.THIRST.value = 0.3, 0.3
local wetCohort = DormantCohort.capture("WET", { wet }, 0,
  { reachableWater = true, positions = { wet = { cellX = 1, cellY = 1 } } })
local dryCohort = DormantCohort.capture("DRY", { dry }, 0,
  { reachableWater = false, positions = { dry = { cellX = 1, cellY = 1 } } })
Simulator.advance(wetCohort, { wet = wet }, 8 * HOUR)
Simulator.advance(dryCohort, { dry = dry }, 8 * HOUR)
assert(wet.drives.THIRST.value < 0.65,
  "reachable dormant water should prevent thirst from simply maxing")
assert(dry.drives.THIRST.value > wet.drives.THIRST.value,
  "no-water dormancy should permit substantially greater thirst")

local fed = actor("fed", 20)
local unfed = actor("unfed", 21)
fed.drives.HUNGER.value, unfed.drives.HUNGER.value = 0.3, 0.3
local fedCohort = DormantCohort.capture("FED", { fed }, 0, {
  opportunityEvidence = { HUNGER = { fed = { proven = true,
    opportunityType = "TALL_GRASS_FORAGE", provenance = "WORLD_SEMANTIC" } } }
})
local unfedCohort = DormantCohort.capture("UNFED", { unfed }, 0, {})
Simulator.advance(fedCohort, { fed = fed }, 8 * HOUR)
Simulator.advance(unfedCohort, { unfed = unfed }, 8 * HOUR)
assert(fed.drives.HUNGER.value < 0.65,
  "proven dormant forage should permit conservative coarse satisfaction")
assert(unfed.drives.HUNGER.value > fed.drives.HUNGER.value,
  "dormant hunger must not be satisfied without captured evidence")

local live = actor("live-hunger", 22)
local dormant = actor("dormant-hunger", 22)
live.drives.HUNGER.value, dormant.drives.HUNGER.value = 0, 0
local physiology = EcologyPhysiology.forEntity(live)
Drives.update(live, 100, { driveRateMultipliers = {
  HUNGER = physiology.hungerRate, THIRST = 0, FATIGUE = 0
} })
local consistencyCohort = DormantCohort.capture("CONSISTENCY", { dormant }, 0, {})
local dormantPhysiology = EcologyPhysiology.forEntity(dormant)
Simulator.advance(consistencyCohort, { [dormant.id] = dormant }, HOUR)
assert(math.abs(live.drives.HUNGER.value - 100 * 0.00035 * physiology.hungerRate)
  < 0.000001, "live hunger should use resolved hunger physiology")
assert(math.abs(dormant.drives.HUNGER.value - 0.06 * dormantPhysiology.hungerRate)
  < 0.000001, "dormant hunger should use the shared resolved hunger physiology: "
    .. tostring(dormant.drives.HUNGER.value) .. " vs "
    .. tostring(0.06 * dormantPhysiology.hungerRate))

local rested = actor("rested", 3, "DIURNAL")
rested.drives.FATIGUE.value = 0.7
local restCohort = DormantCohort.capture("REST", { rested }, 18 * HOUR,
  { positions = { rested = { cellX = 0, cellY = 0 } } })
Simulator.advance(restCohort, { rested = rested }, 26 * HOUR)
assert(rested.drives.FATIGUE.value < 0.7,
  "a rest-heavy dormant interval should recover fatigue")

local farA, farB = actor("far-a", 4), actor("far-b", 5)
local far = DormantCohort.capture("FAR", { farA, farB }, 0, { positions = {
  [farA.id] = { cellX = 0, cellY = 0 }, [farB.id] = { cellX = 10, cellY = 10 }
} })
local farResult = Simulator.advance(far, { [farA.id] = farA, [farB.id] = farB }, 30 * DAY)
assert(next(farA.relationships) == nil and next(farB.relationships) == nil,
  "same cohort alone must not allocate relationships")
assert(farResult.pairCandidates == 0, "unrelated distant members produce no pair work")

local closeA, closeB = actor("close-a", 6), actor("close-b", 7)
local close = DormantCohort.capture("CLOSE", { closeA, closeB }, 0, { positions = {
  [closeA.id] = { cellX = 1, cellY = 1 }, [closeB.id] = { cellX = 2, cellY = 1 }
} })
Simulator.advance(close, { [closeA.id] = closeA, [closeB.id] = closeB }, 30 * DAY)
assert(closeA.relationships[closeB.id].familiarity > 0,
  "active contact at unload should produce bounded directed exposure")
assert(closeA.relationships[closeB.id].familiarity < 20,
  "thirty-day catch-up should saturate conservatively")

local dayA, dayB = actor("day-a", 8, "DIURNAL"), actor("day-b", 9, "DIURNAL")
local nightB = actor("night-b", 9, "NOCTURNAL")
local function contactResult(left, right, mapId)
  local cohort = DormantCohort.capture(mapId, { left, right }, 0, { positions = {
    [left.id] = { cellX = 0, cellY = 0 }, [right.id] = { cellX = 1, cellY = 0 }
  } })
  Simulator.advance(cohort, { [left.id] = left, [right.id] = right }, DAY)
  return left.relationships[right.id].familiarity
end
assert(contactResult(dayA, dayB, "SAME")
  > contactResult(actor("day-c", 8, "DIURNAL"), nightB, "OPPOSITE"),
  "matching activity cycles should produce more active social exposure")

local long = actor("long", 11)
local longCohort = DormantCohort.capture("LONG", { long }, 0, {})
local started = os.clock()
local longResult = Simulator.advance(longCohort, { long = long }, 180 * DAY)
local runtime = os.clock() - started
assert(longResult.segments <= Simulator.MAX_SEGMENTS,
  "six-month catch-up must remain bounded by coarse segments")
assert(runtime < 1, "six-month single-actor catch-up should remain constant-time")
assert(long.drives.THIRST.value >= 0 and long.drives.THIRST.value <= 1,
  "long-gap drive state must remain valid")