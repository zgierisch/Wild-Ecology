package.path = package.path .. ";./?.lua;./?/init.lua"

local Controller = require("src.behavior.controller")
local Drives = require("src.needs.drives")
local Entity = require("src.entities.entity")
local Utility = require("src.behavior.utility")

local function actor(id)
  local entity = Entity.newWildPokemon({ id = id, species = "PIDGEY",
    level = 4, personalitySeed = 42, firstEncounteredTick = 0 })
  entity.runtimeState = { state = "SETTLED", stateEnteredTick = 0,
    motion = { active = false } }
  return entity
end

local function baseContext(phase)
  return { ecologyPhase = phase, hasTarget = false, allowTargeting = false,
    targetPositions = {}, candidates = {}, occupiedCells = {},
    currentOccupiedCells = {}, occupancyDetails = {} }
end

local low = Utility.scoreBehaviors({}, {}, {
  fatigue = 0.1, circadianRestBias = 1, allowTargeting = false
})
assert(low.REST < low.SETTLED,
  "low fatigue should remain SETTLED even in a rest-favored phase")

local moderateActive = Utility.scoreBehaviors({}, {}, {
  fatigue = 0.5, circadianRestBias = 0.1, allowTargeting = false
})
local moderateRest = Utility.scoreBehaviors({}, {}, {
  fatigue = 0.5, circadianRestBias = 0.9, allowTargeting = false
})
assert(moderateActive.REST < moderateActive.SETTLED,
  "moderate fatigue need not dominate during active phase")
assert(moderateRest.REST > moderateRest.SETTLED,
  "the same fatigue should be more competitive in rest phase")

local extreme = Utility.scoreBehaviors({}, {}, {
  fatigue = 0.9, circadianRestBias = 0.05, allowTargeting = false
})
assert(extreme.REST > extreme.SETTLED,
  "extreme fatigue may demand rest during active phase")

local resting = actor("resting")
resting.drives.FATIGUE.value = 0.8
resting.drives.FATIGUE.lastUpdatedTick = 0
local selected = Controller.tick(resting, {}, nil, baseContext(0.0), 31)
assert(selected == "REST", "fatigue plus circadian rest bias should select REST")
local beforeRecovery = resting.drives.FATIGUE.value
local completed
for tick = 61, 500, 30 do
  completed = Controller.tick(resting, {}, nil, baseContext(0.0), tick)
  if completed == "SETTLED" then break end
end
assert(resting.drives.FATIGUE.value < beforeRecovery,
  "REST should reduce persistent fatigue by elapsed time")
assert(completed == "SETTLED", "recovery should complete into SETTLED")

local interrupted = actor("interrupted-rest")
interrupted.drives.FATIGUE.value = 0.8
interrupted.drives.FATIGUE.lastUpdatedTick = 0
assert(Controller.tick(interrupted, {}, nil, baseContext(0.0), 31) == "REST",
  "interruption fixture should enter REST")
local fatigueBeforeThreat = interrupted.drives.FATIGUE.value
local threat = baseContext(0.0)
threat.hasTarget = true
threat.targetPositions.threat = { cellX = 1, cellY = 0 }
threat.position = { cellX = 0, cellY = 0 }
threat.threatAssessment = { primaryThreatId = "threat",
  primaryThreatReason = "HIGH_SEVERITY_EVENT", primaryThreatScore = 200,
  primaryThreatDistance = 1, primaryThreatSevere = true }
threat.currentFear = 0.9
assert(Controller.tick(interrupted, {}, 1, threat, 32) == "FLEE",
  "severe threat should immediately interrupt REST")
assert(interrupted.drives.FATIGUE.value <= fatigueBeforeThreat,
  "REST interruption should preserve the fatigue reached so far")