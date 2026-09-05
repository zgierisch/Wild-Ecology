local Controller = require("src.behavior.controller")
local Drives = require("src.needs.drives")
local Entity = require("src.entities.entity")
local NeedStrategy = require("src.needs.need_strategy")
local TraversalEvaluator = require("src.navigation.traversal_evaluator")
local WorldSemantics = require("src.world.world_semantics")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local function map(mapId, rows)
  return WorldSemantics.fromOverview({
    mapId = mapId, width = #rows[1], height = #rows, rows = rows
  })
end

local function actor(id)
  local result = Entity.newWildPokemon({
    id = id, species = "PIDGEY", level = 4, personalitySeed = 17,
    firstEncounteredTick = 0
  })
  result.runtimeState = {
    state = "SETTLED", stateEnteredTick = 0,
    motion = { active = false }, rejectedMoves = {}
  }
  return result
end

local function context(world, position)
  return {
    position = position,
    mapId = world.mapId,
    worldSemantics = world,
    targetPositions = {},
    candidates = {},
    occupiedCells = {},
    currentOccupiedCells = {},
    occupancyDetails = {},
    hasTarget = false,
    allowTargeting = false,
    needSearchRadius = 12
  }
end

local waterMap = map("THIRST_ROUTE", {
  ".....~",
  ".   ..",
  "......"
})
local thirsty = actor("thirst-proof")
local position = { cellX = 0, cellY = 1 }
local initial = Drives.status(thirsty, "THIRST", 0).value
assertEquals(thirsty.runtimeState.state, "SETTLED",
  "a calm actor should begin settled")
assertEquals(initial < 0.25, true, "initial thirst should be calm")

Controller.chooseState(thirsty, {}, nil, context(waterMap, position), 1200)
assertEquals(thirsty.runtimeState.state, "SATISFY_NEED",
  "elapsed thirst should deliberately disturb settled equilibrium")
assertEquals(thirsty.runtimeState.needOpportunity.semantic, "WATER_ADJACENT",
  "thirst should seek only water-adjacent land")
local goalSignature = thirsty.runtimeState.needOpportunity.goalSignature

for tick = 1201, 1260 do
  local currentContext = context(waterMap, position)
  Controller.chooseState(thirsty, {}, nil, currentContext, tick)
  local request = thirsty.runtimeState.movementRequest
  if request and request.direction ~= "STAY" then
    local destination = { cellX = request.destinationX, cellY = request.destinationY }
    local traversal = TraversalEvaluator.evaluateAdjacent(
      thirsty, waterMap, position, destination, { allowedModes = { WALK = true } })
    assertEquals(traversal.legal, true, "need navigation must remain legal WALK traversal")
    position = destination
    thirsty.runtimeState.motion = { active = false, justCompleted = true }
  else
    thirsty.runtimeState.motion = { active = false }
  end
  if thirsty.runtimeState.state == "SETTLED" then break end
end

assertEquals(thirsty.runtimeState.state, "SETTLED",
  "drinking should release the purposeful intent back to settled")
assertEquals(Drives.status(thirsty, "THIRST", 1260).value < 0.2, true,
  "drinking should materially lower thirst below its release threshold")
assertEquals(thirsty.runtimeState.recentSatisfiedDrive, "THIRST",
  "completion should identify the generic drive that was satisfied")
assertEquals(goalSignature:find("THIRST", 1, true) ~= nil, true,
  "environmental goal identity should include the drive and semantics")

local interrupted = actor("thirst-interrupted")
interrupted.drives.THIRST.value = 0.9
interrupted.drives.THIRST.lastUpdatedTick = 1200
local interruptedPosition = { cellX = 0, cellY = 1 }
Controller.chooseState(interrupted, {}, nil,
  context(waterMap, interruptedPosition), 1200)
assertEquals(interrupted.runtimeState.state, "SATISFY_NEED",
  "the interruption fixture should own an active thirst journey")
local thirstBeforeThreat = interrupted.drives.THIRST.value
local threatContext = context(waterMap, interruptedPosition)
threatContext.hasTarget = true
threatContext.purposefulTarget = true
threatContext.targetPositions.threat = { cellX = 0, cellY = 2 }
threatContext.threatAssessment = {
  primaryThreatId = "threat",
  primaryThreatReason = "HIGH_SEVERITY_EVENT",
  primaryThreatScore = 200,
  primaryThreatDistance = 1,
  primaryThreatSevere = true
}
threatContext.currentFear = 0.9
Controller.chooseState(interrupted, {}, 1, threatContext, 1201)
assertEquals(interrupted.runtimeState.state, "FLEE",
  "severe threat must immediately preempt need satisfaction")
assertEquals(interrupted.drives.THIRST.value >= thirstBeforeThreat, true,
  "interruption must not falsely satisfy the persistent deficit")

local noWater = actor("no-water")
Controller.chooseState(noWater, {}, nil,
  context(map("NO_WATER", { "....." }), { cellX = 2, cellY = 0 }), 2000)
assertEquals(noWater.runtimeState.state, "SETTLED",
  "a motivating drive without an opportunity should not create a fake destination")
assertEquals(noWater.runtimeState.needOpportunity, nil,
  "no-water maps should expose no need opportunity")

local sealedWater = actor("sealed-water")
local sealed = map("SEALED_WATER", {
  ".....",
  ".   .",
  ". ~ .",
  ".   .",
  "....."
})
Controller.chooseState(sealedWater, {}, nil,
  context(sealed, { cellX = 0, cellY = 0 }), 2000)
assertEquals(sealedWater.runtimeState.state, "SETTLED",
  "unreachable water-adjacent terrain should not activate need navigation")
local callsAfterFailure = NeedStrategy.getCounters().plannerCalls
Controller.chooseState(sealedWater, {}, nil,
  context(sealed, { cellX = 0, cellY = 0 }), 2001)
assertEquals(NeedStrategy.getCounters().plannerCalls, callsAfterFailure,
  "an identical unreachable semantic goal should not hot-loop the planner")
assertEquals(NeedStrategy.getCounters().suppressedPlans > 0, true,
  "failed semantic goal suppression should be observable in aggregate")

local soak = actor("drive-soak")
for tick = 1, 10000 do Drives.update(soak, tick) end
local soaked = Drives.status(soak, "THIRST", 10000)
assertEquals(soaked.value, 1, "long-running deficits should remain bounded")
assertEquals(soaked.lastUpdatedTick, 10000,
  "long-running updates should retain exact elapsed-time provenance")

local independentA, independentB = actor("multi-a"), actor("multi-b")
local aStart = Drives.status(independentA, "THIRST", 0).value
Drives.update(independentA, 1000)
Drives.update(independentB, 100)
assertEquals(Drives.status(independentA, "THIRST", 1000).value >
  Drives.status(independentB, "THIRST", 100).value, true,
  "multiple actors should retain independent elapsed-time deficits")
assertEquals(Drives.status(independentA, "THIRST", 1000).value > aStart, true,
  "multi-actor updates should accumulate rather than replace actor state")
assertEquals(Drives.getCounters().updates > 0, true,
  "drive updates should be available as compact aggregate telemetry")

return true