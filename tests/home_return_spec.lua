package.path = package.path .. ";./?.lua;./?/init.lua"

local CircadianSystem = require("src.circadian.circadian_system")
local Controller = require("src.behavior.controller")
local Entity = require("src.entities.entity")
local HomeArea = require("src.world.home_area")
local HomeReturn = require("src.behavior.home_return")
local Utility = require("src.behavior.utility")
local WorldSemantics = require("src.world.world_semantics")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "assertEquals failed") .. ": expected "
      .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function assertTrue(value, message)
  if not value then error(message or "expected truthy value") end
end

local semantics = WorldSemantics.fromOverview({
  mapId = "HOME_ROUTE", width = 12, height = 1,
  rows = { "............" }
})
if not semantics then error("home-return semantics should resolve") end

local function actor(id, species, seed)
  local entity = Entity.newWildPokemon({
    id = id, species = species or "RATTATA", level = 4,
    personalitySeed = seed or 1, firstEncounteredTick = 0,
    home = {
      mapId = "HOME_ROUTE", spawnX = 2, spawnY = 0,
      area = {
        mapId = "HOME_ROUTE", anchorCell = { cellX = 2, cellY = 0 },
        radius = 2, establishedTick = 0, provenance = "TEST"
      }
    }
  })
  entity.runtimeState = {
    state = "SETTLED", stateEnteredTick = 0,
    motion = { active = false }, rejectedMoves = {}
  }
  entity.drives.THIRST.value = 0.05
  entity.drives.HUNGER.value = 0.05
  entity.drives.FATIGUE.value = 0.3
  for _, drive in pairs(entity.drives) do drive.lastUpdatedTick = 0 end
  return entity
end

local function context(position, phase)
  return {
    ecologyPhase = phase or 0.5,
    hasTarget = false,
    allowTargeting = false,
    position = { cellX = position.cellX, cellY = position.cellY },
    mapId = semantics.mapId,
    targetPositions = {}, candidates = {}, occupiedCells = {},
    currentOccupiedCells = {}, occupancyDetails = {},
    worldSemantics = semantics, locomotionPacing = true
  }
end

local nearby = actor("nearby", "RATTATA", 10)
assertEquals(Controller.tick(nearby, {}, nil,
  context({ cellX = 5, cellY = 0 }), 31), "SETTLED",
  "slightly outside home must not automatically dominate calm equilibrium")
assertEquals(nearby.runtimeState.behaviorScores.RETURN_HOME, 0,
  "home opportunity alone must not create return pressure")

local returning = actor("returning", "RATTATA", 11)
assertEquals(Controller.tick(returning, {}, nil,
  context({ cellX = 10, cellY = 0 }), 31), "RETURN_HOME",
  "distance plus low-activity context should motivate home return")
assertTrue(returning.runtimeState.behaviorScores.RETURN_HOME
  > returning.runtimeState.behaviorScores.SETTLED,
  "RETURN_HOME must win through generic utility")
assertEquals(returning.runtimeState.homeReturnDestination.cellX, 4,
  "destination should be nearest acceptable home-area boundary")
assertEquals(returning.runtimeState.navigation.ownerBehavior, "RETURN_HOME",
  "home travel must use generic NavigationExecution ownership")
assertEquals(returning.runtimeState.spatialGoal.source, "HOME_AREA",
  "home behavior should select WHERE through SpatialGoal")

returning.runtimeState.motion.justCompleted = true
Controller.tick(returning, {}, nil, context({ cellX = 5, cellY = 0 }), 46)
assertEquals(returning.runtimeState.state, "RETURN_HOME",
  "active return intent must not chatter just outside satisfaction radius")
returning.runtimeState.motion.justCompleted = true
Controller.tick(returning, {}, nil, context({ cellX = 4, cellY = 0 }), 61)
Controller.tick(returning, {}, nil, context({ cellX = 4, cellY = 0 }), 76)
assertEquals(returning.runtimeState.state, "SETTLED",
  "entering any acceptable home-area cell should satisfy return intent")
assertEquals(returning.runtimeState.homeReturnDestination, nil,
  "satisfied return destination must remain transient")

local utilityEntity = actor("utility", "RATTATA", 12)
local thirstScores = Utility.scoreBehaviors(utilityEntity, {}, {
  homeReturn = { score = 52 }, needOpportunity = { score = 82 },
  fatigue = 0.3
})
assertEquals(Utility.highestBehavior(thirstScores), "SATISFY_NEED",
  "strong THIRST opportunity must beat moderate return desire generically")
local hungerScores = Utility.scoreBehaviors(utilityEntity, {}, {
  homeReturn = { score = 52 }, needOpportunity = { score = 78 },
  fatigue = 0.3
})
assertEquals(Utility.highestBehavior(hungerScores), "SATISFY_NEED",
  "strong HUNGER opportunity must beat moderate return desire generically")

local exhausted = actor("exhausted", "RATTATA", 13)
exhausted.drives.FATIGUE.value = 0.96
assertEquals(Controller.tick(exhausted, {}, nil,
  context({ cellX = 10, cellY = 0 }), 31), "REST",
  "extreme fatigue must permit local REST instead of forced travel")

local threatened = actor("threatened", "RATTATA", 14)
Controller.tick(threatened, {}, nil, context({ cellX = 10, cellY = 0 }), 31)
local threatContext = context({ cellX = 10, cellY = 0 })
threatContext.currentFear = 1
threatContext.targetPositions.player = { cellX = 9, cellY = 0 }
threatContext.threatAssessment = {
  primaryThreatId = "player", primaryThreatDistance = 1,
  primaryThreatSevere = true, primaryThreatReason = "HIGH_SEVERITY_EVENT"
}
assertEquals(Controller.tick(threatened,
  { threatMemory = 100, hostility = 20 }, 1, threatContext, 32), "FLEE",
  "severe threat must interrupt RETURN_HOME through ordinary FLEE")
assertEquals(threatened.runtimeState.homeReturnDestination, nil,
  "interrupted return route must lose authority")

local phaseActor = actor("phase", "RATTATA", 15)
local activeCircadian = CircadianSystem.evaluate(phaseActor, 0)
local restCircadian = CircadianSystem.evaluate(phaseActor, 0.5)
local activeReturn = HomeReturn.evaluate(phaseActor,
  { cellX = 10, cellY = 0 }, "HOME_ROUTE", {
    fatigue = 0.3, circadianRestBias = activeCircadian.restBias
  })
local restReturn = HomeReturn.evaluate(phaseActor,
  { cellX = 10, cellY = 0 }, "HOME_ROUTE", {
    fatigue = 0.3, circadianRestBias = restCircadian.restBias
  })
assertTrue(restReturn.score > activeReturn.score,
  "existing circadian output should change return attractiveness without a schedule")

local pidgey = actor("pidgey", "PIDGEY", 16)
local rattata = actor("rattata", "RATTATA", 16)
local pidgeyReturn = HomeReturn.evaluate(pidgey,
  { cellX = 10, cellY = 0 }, "HOME_ROUTE", {
    fatigue = 0.3, circadianRestBias = 0.5
  })
local rattataReturn = HomeReturn.evaluate(rattata,
  { cellX = 10, cellY = 0 }, "HOME_ROUTE", {
    fatigue = 0.3, circadianRestBias = 0.5
  })
assertTrue(rattataReturn.score > pidgeyReturn.score,
  "species home tendency must flow from archetype data without species branches")

local hidden = actor("hidden", "RATTATA", 17)
hidden.locationState = {
  kind = "CONCEALED", mapId = "HOME_ROUTE",
  anchorCell = { cellX = 3, cellY = 0 }
}
local hiddenPosition, hiddenMapId = HomeArea.position(hidden, nil)
assertEquals(HomeArea.isInside(hidden, hiddenPosition, hiddenMapId), true,
  "concealed actor should count as home without rematerialization")
assertEquals(next(hidden.relationships), nil,
  "home membership must not allocate relationships")
local overlap = actor("overlap", "RATTATA", 18)
overlap.home.area = hidden.home.area
assertEquals(next(overlap.relationships), nil,
  "overlapping home areas must preserve sparse social state")

print("All home-return ecology tests passed")