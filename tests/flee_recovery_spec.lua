local Fear = require("src.behavior.fear")
local Controller = require("src.behavior.controller")

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local actor = {
  id = "recovering",
  species = "TEST",
  personalitySeed = 101,
  ecology = { archetype = "flocking_bird" },
  temperament = { sociability = 0.8 },
  rawStats = { independence = 0.2 },
  relationships = { threat = { threatMemory = 70, directThreatMemory = 70, hostility = 10, trust = 0 } },
  runtimeState = { state = "FLEE", stateEnteredTick = 1 }
}
local activeAssessment = {
  primaryThreatId = "threat",
  primaryThreatDistance = 1,
  primaryThreatRelationship = actor.relationships.threat
}
Fear.update(actor, {
  threatAssessment = activeAssessment,
  relationship = actor.relationships.threat,
  threatDistance = 1,
  socialSources = {}
}, 1)
local peakDirect = actor.runtimeState.fearDirect
assertTrue(peakDirect > 0.5, "active direct danger should raise direct fear quickly")
actor.runtimeState.fleeExecution = { escapeMode = true, noProgressSteps = 4, staticRejections = 3 }

local exited = false
for tick = 2, 180 do
  Fear.update(actor, {
    threatAssessment = { primaryThreatId = nil },
    relationship = {},
    socialSources = {}
  }, tick)
  local state = Controller.tick(actor, {}, nil, {
    threatAssessment = { primaryThreatId = nil },
    currentFear = actor.runtimeState.fearCurrent,
    hasTarget = false,
    purposefulTarget = false,
    position = { cellX = 8, cellY = 8 },
    targetPositions = {}
  }, tick)
  if state ~= "FLEE" then exited = true break end
end
assertTrue(actor.runtimeState.fearDirect < peakDirect, "direct fear should decay after the threat is lost")
assertTrue(exited, "sustained safety should eventually terminate FLEE")
assertTrue(actor.runtimeState.lastFleeEndTick ~= nil, "ending FLEE should record a transient recovery timestamp")
assertTrue(actor.relationships.threat.threatMemory == 70, "persistent threat memory should survive emotional recovery")
assertTrue(actor.runtimeState.fleeExitBlockedReason == "EXITED", "diagnostics should report successful exit")

return true