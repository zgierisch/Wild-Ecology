local EscapeHeading = require("src.behavior.escape_heading")
local Controller = require("src.behavior.controller")

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local entity = {
  id = "recovering-heading",
  personalitySeed = 19,
  temperament = { sociability = 0.7 },
  rawStats = { independence = 0.3 },
  runtimeState = { fearCurrent = 0.9 }
}
local position = { cellX = 5, cellY = 0 }
local threat = { cellX = 0, cellY = 0 }
local peak = EscapeHeading.update(entity, position, threat, {
  threatPositionConfidence = 1,
  recoveryProgress = 0,
  openSpace = { dx = 0, dy = 1 }
}, 1)
local late = EscapeHeading.update(entity, position, threat, {
  threatPositionConfidence = 0.25,
  recoveryProgress = 0.8,
  openSpace = { dx = 0, dy = 1 },
  completedDirection = "RIGHT"
}, 2)
assertTrue(late.radialWeight < peak.radialWeight,
  "radial certainty should decline during sustained safe recovery after threat loss")
assertTrue(late.openSpaceWeight > peak.openSpaceWeight,
  "open-space steering should gain relative influence as panic recedes")

local reacquired = EscapeHeading.update(entity, position, threat, {
  threatPositionConfidence = 1,
  recoveryProgress = 0,
  openSpace = { dx = 0, dy = 1 },
  completedDirection = "RIGHT"
}, 3)
assertTrue(reacquired.radialWeight > late.radialWeight,
  "legitimate threat reacquisition should immediately restore radial dominance")
assertTrue(reacquired.threatPositionConfidence == 1,
  "reacquisition should restore exact current-position confidence")

local runner = {
  id = "remembered-runner",
  personalitySeed = 21,
  temperament = { sociability = 0.4 },
  rawStats = { independence = 0.6 },
  runtimeState = { state = "FLEE", stateEnteredTick = 1, fearCurrent = 0.6, fearDirect = 0.5 }
}
local playerPosition = { cellX = 0, cellY = 0 }
local runnerPosition = { cellX = 3, cellY = 0 }
Controller.tick(runner, { hostility = 100 }, 3, {
  threatAssessment = { primaryThreatId = "player" },
  targetPositions = { player = playerPosition },
  position = runnerPosition,
  currentFear = 0.6
}, 1)
runner.runtimeState.motion = { active = false, justCompleted = true }
local continued = Controller.tick(runner, {}, nil, {
  threatAssessment = { primaryThreatId = nil },
  targetPositions = {},
  position = { cellX = 4, cellY = 0 },
  currentFear = 0.5
}, 20)
assertTrue(continued == "FLEE" and runner.runtimeState.movementRequest
    and runner.runtimeState.movementRequest.traversalMode == "WALK",
  "threat loss should preserve short-lived evasive movement from a last-known position")
assertTrue(runner.runtimeState.escapeHeading.threatPositionConfidence < 1,
  "last-known threat geometry must lose confidence without hidden position updates")

return true