package.path = package.path .. ";./?.lua;./?/init.lua"

local CircadianSystem = require("src.circadian.circadian_system")
local Controller = require("src.behavior.controller")
local Drives = require("src.needs.drives")
local Entity = require("src.entities.entity")
local FoodOpportunities = require("src.needs.food_opportunities")
local Harness = require("tests.support.daily_rhythm_harness")
local HomeReturn = require("src.behavior.home_return")
local NeedStrategy = require("src.needs.need_strategy")
local WorldSemantics = require("src.world.world_semantics")

local function assertTrue(value, message)
  if not value then error(message or "expected truthy value") end
end

local TICKS_PER_DAY = 7200
local cells = {
  [WorldSemantics.cellKey(2, 1)] = {
    terrain = "TALL_GRASS", grass = true, walkable = true,
    validLanding = true, cover = "HIGH"
  },
  [WorldSemantics.cellKey(8, 1)] = {
    terrain = "TALL_GRASS", grass = true, walkable = true,
    validLanding = true, cover = "HIGH"
  }
}
local semantics = assert(WorldSemantics.fromOverview({
  mapId = "RHYTHM_VARIANTS", width = 14, height = 3,
  rows = {
    "..............",
    "............~.",
    ".............."
  }
}, { cells = cells }))

local function actor(id, species, seed, withHome)
  local entity = Entity.newWildPokemon({
    id = id, species = species, level = 4, personalitySeed = seed,
    firstEncounteredTick = 0,
    home = withHome == false and { mapId = semantics.mapId }
      or {
        mapId = semantics.mapId, spawnX = 2, spawnY = 1,
        area = {
          mapId = semantics.mapId,
          anchorCell = { cellX = 2, cellY = 1 },
          radius = 2, establishedTick = 0, provenance = "TEST"
        }
      }
  })
  entity.runtimeState = { state = "SETTLED", stateEnteredTick = 0,
    motion = { active = false }, rejectedMoves = {} }
  return entity
end

local function baseContext(position, phase)
  return {
    ecologyPhase = phase or 0.5,
    position = { cellX = position.cellX, cellY = position.cellY },
    mapId = semantics.mapId,
    worldSemantics = semantics,
    locomotionPacing = true,
    needSearchRadius = 14,
    occupiedCells = {}, occupancyDetails = {}, currentOccupiedCells = {},
    targetPositions = {}, candidates = {}, hasTarget = false,
    purposefulTarget = false, allowTargeting = true
  }
end

local pidgeyPhase = actor("phase-pidgey", "PIDGEY", 31)
local rattataPhase = actor("phase-rattata", "RATTATA", 31)
local pidgeyDay = CircadianSystem.evaluate(pidgeyPhase, 0.5)
local pidgeyNight = CircadianSystem.evaluate(pidgeyPhase, 0.0)
local rattataDay = CircadianSystem.evaluate(rattataPhase, 0.5)
local rattataNight = CircadianSystem.evaluate(rattataPhase, 0.0)
assertTrue(pidgeyDay.activityBias > pidgeyNight.activityBias,
  "Pidgey should retain broad diurnal activity pressure")
assertTrue(rattataNight.activityBias > rattataDay.activityBias,
  "Rattata should retain broad nocturnal activity pressure")

FoodOpportunities.reset()
local nocturnal = actor("daily-rattata", "RATTATA", 32)
nocturnal.drives.FATIGUE.value = 0.5
nocturnal.drives.FATIGUE.lastUpdatedTick = 0
local nocturnalRun = Harness.new({
  entity = nocturnal,
  position = { cellX = 9, cellY = 1 },
  semantics = semantics,
  ticksPerDay = TICKS_PER_DAY,
  decisionCadence = 15,
  timelineLimit = 12,
  context = function(_, context) context.needSearchRadius = 14 end
})
local nocturnalMetrics = nocturnalRun:run(TICKS_PER_DAY)
local nocturnalOccupancy = Harness.occupancy(nocturnalMetrics, TICKS_PER_DAY)
assertTrue((nocturnalMetrics.satisfactions.HUNGER or 0) >= 1
  and (nocturnalMetrics.satisfactions.THIRST or 0) >= 1,
  "nocturnal generic ecology should complete multiple need types")
assertTrue((nocturnalOccupancy.SETTLED or 0) > 0.4,
  "nocturnal ecology should retain substantial calm equilibrium")
assertTrue((nocturnalOccupancy.REST or 0) > 0,
  "nocturnal ecology should include fatigue recovery")

FoodOpportunities.reset()
local homeless = actor("homeless", "PIDGEY", 33, false)
local homelessRun = Harness.new({ entity = homeless,
  position = { cellX = 9, cellY = 1 }, semantics = semantics,
  ticksPerDay = TICKS_PER_DAY, decisionCadence = 15,
  context = function(_, context) context.needSearchRadius = 14 end })
local homelessMetrics = homelessRun:run(3600)
assertTrue((homelessMetrics.behaviorTicks.RETURN_HOME or 0) == 0,
  "an actor without an established home must never select RETURN_HOME")
assertTrue((homelessMetrics.satisfactions.THIRST or 0) >= 1,
  "no-home ecology should retain ordinary need satisfaction")

local zubat = actor("unsupported-zubat", "ZUBAT", 34)
zubat.drives.FATIGUE.value = 0.95
zubat.drives.FATIGUE.lastUpdatedTick = 0
Controller.tick(zubat, {}, nil, baseContext({ cellX = 6, cellY = 1 }, 0.5), 31)
assertTrue(zubat.runtimeState.state == "REST",
  "Zubat should still REST without executable cave/ceiling semantics")
assertTrue(zubat.runtimeState.concealmentRequest == nil
  and zubat.runtimeState.restSiteSelection
  and zubat.runtimeState.restSiteSelection.selected == nil,
  "unsupported rest habitat must fall back to visible in-place REST")
for tick = 32, 630 do
  Controller.executeCurrentIntent(zubat,
    baseContext({ cellX = 6, cellY = 1 }, 0.5), tick)
  if tick % 15 == 0 then
    Controller.tick(zubat, {}, nil,
      baseContext({ cellX = 6, cellY = 1 }, 0.5), tick)
  end
  if zubat.runtimeState.state == "SETTLED" then break end
end
assertTrue(zubat.runtimeState.state == "SETTLED",
  "visible fallback REST should recover and release normally")

NeedStrategy.resetCounters()
local scarce = actor("scarce-magnemite", "MAGNEMITE", 35, false)
scarce.drives.HUNGER.value = 0.95
scarce.drives.HUNGER.lastUpdatedTick = 0
local scarcityRun = Harness.new({ entity = scarce,
  position = { cellX = 5, cellY = 1 }, semantics = semantics,
  ticksPerDay = TICKS_PER_DAY, decisionCadence = 15 })
local scarcityMetrics = scarcityRun:run(1800)
assertTrue(Drives.status(scarce, "HUNGER", 1800).value >= 0.95,
  "unsupported food scarcity must preserve the unmet drive")
assertTrue((scarcityMetrics.behaviorTicks.SATISFY_NEED or 0) < 1800,
  "scarcity must not fabricate continuous feeding")
assertTrue(NeedStrategy.getCounters().plannerCalls < 200,
  "scarcity must not create an expensive per-tick planning loop")

local first = actor("individual-a", "RATTATA", 41)
local second = actor("individual-b", "RATTATA", 99)
local firstCircadian = CircadianSystem.evaluate(first, 0)
local secondCircadian = CircadianSystem.evaluate(second, 0)
assertTrue(firstCircadian.profile == secondCircadian.profile
  and firstCircadian.phaseOffset ~= secondCircadian.phaseOffset,
  "same-species individuals should share biology with stable phase variation")
local firstReturn = HomeReturn.evaluate(first, { cellX = 10, cellY = 1 },
  semantics.mapId, { fatigue = 0.3, circadianRestBias = 0.6 })
second.rawStats.independence = 1
local secondReturn = HomeReturn.evaluate(second, { cellX = 10, cellY = 1 },
  semantics.mapId, { fatigue = 0.3, circadianRestBias = 0.6 })
assertTrue(firstReturn.score ~= secondReturn.score,
  "existing individual variation may modestly alter home-return pressure")

FoodOpportunities.reset()
local social = actor("social-interruption", "PIDGEY", 36)
social.relationships.friend = { trust = 90, affinity = 80,
  familiarity = 100, threatMemory = 0, hostility = 0 }
local socialContext = baseContext({ cellX = 2, cellY = 1 }, 0.5)
socialContext.hasTarget = true
socialContext.purposefulTarget = true
socialContext.targetEntityId = "friend"
socialContext.targetPositions.friend = { cellX = 7, cellY = 1 }
socialContext.candidates = { { id = "friend", distance = 5, novelty = 0 } }
assertTrue(Controller.tick(social, social.relationships.friend, 5,
  socialContext, 31) == "APPROACH",
  "relationship-driven social behavior should alter a calm period")
socialContext.targetPositions.friend = { cellX = 3, cellY = 1 }
socialContext.candidates[1].distance = 1
Controller.tick(social, social.relationships.friend, 1, socialContext, 40)
social.drives.THIRST.value = 1
social.drives.THIRST.lastUpdatedTick = 40
assertTrue(Controller.tick(social, social.relationships.friend, 5,
  socialContext, 71) == "SATISFY_NEED",
  "a severe need should prevent sociality from monopolizing ecology")

FoodOpportunities.reset()
local interrupted = actor("interrupted-day", "PIDGEY", 37)
interrupted.drives.HUNGER.value = 0.9
interrupted.drives.HUNGER.lastUpdatedTick = 0
local calmContext = baseContext({ cellX = 2, cellY = 1 }, 0.5)
assertTrue(Controller.tick(interrupted, {}, nil, calmContext, 31)
  == "SATISFY_NEED", "interruption fixture should begin from real hunger")
local threatContext = baseContext({ cellX = 2, cellY = 1 }, 0.5)
threatContext.targetPositions.threat = { cellX = 2, cellY = 2 }
threatContext.threatAssessment = { primaryThreatId = "threat",
  primaryThreatReason = "HIGH_SEVERITY_EVENT", primaryThreatScore = 200,
  primaryThreatDistance = 1, primaryThreatSevere = true }
threatContext.currentFear = 0.9
assertTrue(Controller.tick(interrupted,
  { trust = 0, threatMemory = 100, hostility = 20 }, 1,
  threatContext, 32) == "FLEE", "severe threat should interrupt the day")
interrupted.runtimeState.fearCurrent = 0
interrupted.runtimeState.fearDirect = 0
interrupted.runtimeState.fearSocial = 0
interrupted.runtimeState.threatAssessment = nil
local postThreatState
for tick = 33, 120 do
  postThreatState = Controller.tick(interrupted, {}, nil, calmContext, tick)
end
assertTrue(interrupted.runtimeState.firstOrdinaryState == "SATISFY_NEED"
  or interrupted.runtimeState.recentSatisfiedDrive == "HUNGER",
  "post-threat utility should rediscover persistent hunger from current reality")
for _, forbidden in ipairs({ "previousActivity", "queuedActivity",
  "dailyAgenda", "nextRoutineTask", "routinePhase" }) do
  assertTrue(interrupted.runtimeState[forbidden] == nil,
    "interruption must not create queued routine state: " .. forbidden)
end

print(string.format(
  "RHYTHM_VARIANTS nocturnalSettled=%.3f nocturnalRest=%.3f homelessTransitions=%d scarcityPlans=%d postThreat=%s",
  nocturnalOccupancy.SETTLED or 0, nocturnalOccupancy.REST or 0,
  homelessMetrics.transitions, NeedStrategy.getCounters().plannerCalls,
  tostring(postThreatState)))

return true