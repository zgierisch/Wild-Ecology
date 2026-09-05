package.path = package.path .. ";./?.lua;./?/init.lua"

local Controller = require("src.behavior.controller")
local Drives = require("src.needs.drives")
local Entity = require("src.entities.entity")
local FoodOpportunities = require("src.needs.food_opportunities")
local NeedStrategy = require("src.needs.need_strategy")
local TraversalEvaluator = require("src.navigation.traversal_evaluator")
local WorldSemantics = require("src.world.world_semantics")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local function forageMap(mapId)
  return assert(WorldSemantics.fromOverview({
    mapId = mapId, width = 6, height = 2,
    rows = { "......", "......" }
  }, { cells = {
    [WorldSemantics.cellKey(4, 0)] = { terrain = "TALL_GRASS" },
    [WorldSemantics.cellKey(5, 1)] = { terrain = "TALL_GRASS" }
  } }))
end

local function actor(id, species)
  local result = Entity.newWildPokemon({ id = id, species = species or "PIDGEY",
    level = 4, personalitySeed = 17, firstEncounteredTick = 0 })
  result.runtimeState = { state = "SETTLED", stateEnteredTick = -100,
    motion = { active = false }, rejectedMoves = {} }
  return result
end

local function context(world, position)
  return {
    position = position, mapId = world.mapId, worldSemantics = world,
    targetPositions = {}, candidates = {}, occupiedCells = {},
    currentOccupiedCells = {}, occupancyDetails = {}, hasTarget = false,
    allowTargeting = false, needSearchRadius = 12
  }
end

local function setDrive(entity, id, value, tick)
  entity.drives[id].value = value
  entity.drives[id].lastUpdatedTick = tick or 0
end

local function advance(entity, world, position, firstTick, lastTick)
  for tick = firstTick, lastTick do
    Controller.chooseState(entity, {}, nil, context(world, position), tick)
    local request = entity.runtimeState.movementRequest
    if request and request.direction ~= "STAY" then
      local destination = { cellX = request.destinationX, cellY = request.destinationY }
      local traversal = TraversalEvaluator.evaluateAdjacent(
        entity, world, position, destination, { allowedModes = { WALK = true } })
      assertEquals(traversal.legal, true,
        "foraging navigation must remain ordinary legal WALK traversal")
      position = destination
      entity.runtimeState.motion = { active = false, justCompleted = true }
    else
      entity.runtimeState.motion = { active = false }
    end
  end
  return position
end

FoodOpportunities.reset()
local world = forageMap("FORAGE_ROUTE")

local satiated = actor("satiated")
setDrive(satiated, "HUNGER", 0.15, 0)
Controller.chooseState(satiated, {}, nil, context(world, { cellX = 0, cellY = 0 }), 1)
assertEquals(satiated.runtimeState.state, "SETTLED",
  "nearby food must not motivate a satiated actor")

local hungry = actor("hungry")
setDrive(hungry, "HUNGER", 0.9, 0)
local position = { cellX = 0, cellY = 0 }
Controller.chooseState(hungry, {}, nil, context(world, position), 0)
assertEquals(hungry.runtimeState.state, "SATISFY_NEED",
  "high hunger plus compatible forage should select the generic need behavior")
assertEquals(hungry.runtimeState.needOpportunity.driveId, "HUNGER",
  "the selected generic need opportunity should retain its drive")
assertEquals(hungry.runtimeState.needOpportunity.opportunity.opportunityType,
  "TALL_GRASS_FORAGE", "tall grass should become only the normalized forage fact")
assertEquals(hungry.runtimeState.needOpportunity.opportunity.provenance,
  "WORLD_SEMANTIC", "food opportunities should retain semantic provenance")

position = advance(hungry, world, position, 1, 5)
assertEquals(hungry.runtimeState.state, "SATISFY_NEED",
  "arrival should begin bounded stationary feeding rather than instant satisfaction")
assert(hungry.runtimeState.feedingAction,
  "arrival should expose transient feeding progress")
local feedingPosition = { cellX = position.cellX, cellY = position.cellY }
position = advance(hungry, world, position, 6, 25)
assertEquals(position.cellX, feedingPosition.cellX,
  "feeding should remain stationary")
assertEquals(position.cellY, feedingPosition.cellY,
  "feeding should remain stationary")
assertEquals(hungry.runtimeState.state, "SETTLED",
  "completed feeding should release the purposeful intent to equilibrium")
assert(Drives.status(hungry, "HUNGER", 25).value <= 0.2,
  "feeding should discharge hunger below its release threshold")
assertEquals(hungry.runtimeState.recentSatisfiedDrive, "HUNGER",
  "generic satisfaction diagnostics should identify hunger")

local goldeen = actor("goldeen", "GOLDEEN")
setDrive(goldeen, "HUNGER", 0.95, 0)
Controller.chooseState(goldeen, {}, nil, context(world, { cellX = 0, cellY = 0 }), 0)
assertEquals(goldeen.runtimeState.state, "SETTLED",
  "unsupported aquatic feeding must not consume terrestrial forage")
assertEquals(goldeen.runtimeState.needOpportunity, nil,
  "unsupported species should expose no fake food destination")

local magnemite = actor("magnemite", "MAGNEMITE")
setDrive(magnemite, "HUNGER", 0.95, 0)
Controller.chooseState(magnemite, {}, nil, context(world, { cellX = 0, cellY = 0 }), 0)
assertEquals(magnemite.runtimeState.state, "SETTLED",
  "unusual species must not be forced into conventional food compatibility")

FoodOpportunities.reset()
NeedStrategy.resetCounters()
local sealed = assert(WorldSemantics.fromOverview({
  mapId = "SEALED_FORAGE", width = 5, height = 3,
  rows = { ".....", ".   .", "....." }
}, { cells = {
  [WorldSemantics.cellKey(2, 1)] = { terrain = "TALL_GRASS" }
} }))
local blocked = actor("blocked")
setDrive(blocked, "HUNGER", 0.95, 0)
Controller.chooseState(blocked, {}, nil,
  context(sealed, { cellX = 0, cellY = 0 }), 0)
local callsAfterFailure = NeedStrategy.getCounters().plannerCalls
Controller.chooseState(blocked, {}, nil,
  context(sealed, { cellX = 0, cellY = 0 }), 1)
assertEquals(NeedStrategy.getCounters().plannerCalls, callsAfterFailure,
  "unreachable forage should reuse generic failed-goal suppression")
assert(NeedStrategy.getCounters().suppressedPlans > 0,
  "suppressed food plans should remain observable in aggregate")

FoodOpportunities.reset()
local caterpie = actor("caterpie", "CATERPIE")
setDrive(caterpie, "HUNGER", 0.9, 0)
Controller.chooseState(caterpie, {}, nil, context(world, { cellX = 3, cellY = 0 }), 0)
assertEquals(caterpie.runtimeState.needOpportunity.opportunity.opportunityType,
  "TALL_GRASS_FORAGE", "Caterpie should use the same abstract opportunity category")

FoodOpportunities.reset()
local interrupted = actor("interrupted")
setDrive(interrupted, "HUNGER", 0.9, 0)
local grassPosition = { cellX = 4, cellY = 0 }
Controller.chooseState(interrupted, {}, nil, context(world, grassPosition), 0)
Controller.chooseState(interrupted, {}, nil, context(world, grassPosition), 1)
assert(interrupted.runtimeState.feedingAction, "threat fixture should begin feeding")
local hungerBeforeThreat = interrupted.drives.HUNGER.value
local threatContext = context(world, grassPosition)
threatContext.hasTarget = true
threatContext.purposefulTarget = true
threatContext.targetPositions.threat = { cellX = 4, cellY = 1 }
threatContext.threatAssessment = { primaryThreatId = "threat",
  primaryThreatReason = "HIGH_SEVERITY_EVENT", primaryThreatScore = 200,
  primaryThreatDistance = 1, primaryThreatSevere = true }
threatContext.currentFear = 0.9
Controller.chooseState(interrupted, {}, 1, threatContext, 2)
assertEquals(interrupted.runtimeState.state, "FLEE",
  "existing emergency behavior must interrupt feeding")
assert(interrupted.drives.HUNGER.value >= hungerBeforeThreat,
  "interruption must not falsely satisfy hunger")

FoodOpportunities.reset()
local first, second = actor("first"), actor("second")
setDrive(first, "HUNGER", 0.9, 0)
setDrive(second, "HUNGER", 0.9, 0)
local sharedPosition = { cellX = 4, cellY = 0 }
Controller.chooseState(first, {}, nil, context(world, sharedPosition), 0)
Controller.chooseState(second, {}, nil, context(world, sharedPosition), 0)
for tick = 1, 13 do
  Controller.chooseState(first, {}, nil, context(world, sharedPosition), tick)
end
Controller.chooseState(second, {}, nil, context(world, sharedPosition), 13)
assertEquals(second.runtimeState.lastIntentEpisodeOutcome, "INVALIDATED",
  "another actor consuming an opportunity should invalidate the stale goal")
assert(second.drives.HUNGER.value > 0.8,
  "multi-actor invalidation must not fabricate satisfaction")
assert(next(first.relationships) == nil and next(second.relationships) == nil,
  "shared foraging must not allocate relationships")

FoodOpportunities.reset()
local competing = actor("competing")
setDrive(competing, "HUNGER", 0.72, 0)
setDrive(competing, "THIRST", 0.98, 0)
local mixed = forageMap("MIXED_NEEDS")
mixed.rows[1] = "....~."
mixed.cellCache = {}
Controller.chooseState(competing, {}, nil, context(mixed, { cellX = 3, cellY = 0 }), 0)
assertEquals(competing.runtimeState.needOpportunity.driveId, "THIRST",
  "stronger thirst should win through generic need utility competition")

FoodOpportunities.reset()
local exhausted = actor("exhausted")
setDrive(exhausted, "HUNGER", 0.72, 0)
setDrive(exhausted, "FATIGUE", 0.99, 0)
Controller.chooseState(exhausted, {}, nil,
  context(world, { cellX = 3, cellY = 0 }), 0)
assertEquals(exhausted.runtimeState.state, "REST",
  "high fatigue should compete with hunger through ordinary utility")

return true
