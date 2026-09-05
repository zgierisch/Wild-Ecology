local Controller = require("src.behavior.controller")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local function actor(id)
  return {
    id = id,
    species = "PIDGEY",
    personalitySeed = 41,
    temperament = { boldness = 0.1, sociability = 0.8 },
    rawStats = { independence = 0.2 },
    relationships = {},
    runtimeState = {
      state = "FLEE",
      stateEnteredTick = 0,
      fearCurrent = 0.6,
      fearDirect = 0.6,
      fearSocial = 0,
      targetEntityId = "unrelated-wild"
    }
  }
end

local function context(position, assessment, targetPositions, socialPosition)
  return {
    executionOnly = true,
    position = position,
    threatAssessment = assessment,
    targetPositions = targetPositions or {},
    socialAlarmTargetPosition = socialPosition,
    currentFear = 0.6,
    fleeSafetyDistance = 7,
    fleeNeighbors = {}
  }
end

local direct = actor("direct-player")
local playerPosition = { cellX = 2, cellY = 2 }
Controller.executeCurrentIntent(direct, context({ cellX = 4, cellY = 2 }, {
  primaryThreatId = "player",
  primaryThreatReason = "HOSTILITY",
  primaryThreatScore = 80,
  primaryThreatDistance = 2
}, { player = playerPosition }), 1)
assertEquals(direct.runtimeState.targetEntityId, "player",
  "direct FLEE identity should come from ThreatAssessment")
assertEquals(direct.runtimeState.escapeReference.kind, "CURRENT_THREAT_POSITION",
  "a perceived direct threat should use current geometry")
assertEquals(direct.runtimeState.escapeReference.entityId, "player",
  "current geometry entity must equal the primary threat")
assertEquals(direct.runtimeState.movementRequest.targetEntityId, "player",
  "direct movement provenance should name the primary threat")
assertTrue(Controller.validateFleeProvenance(direct.runtimeState,
  direct.runtimeState.movementRequest), "direct player provenance should validate")

local frozenX, frozenY = direct.runtimeState.fleeThreatPosition.cellX,
  direct.runtimeState.fleeThreatPosition.cellY
Controller.executeCurrentIntent(direct, context({ cellX = 5, cellY = 2 }, {
  primaryThreatId = nil,
  primaryThreatReason = "NONE",
  primaryThreatScore = 0
}, {
  player = { cellX = 9, cellY = 9 },
  ["wild:route22:0007"] = { cellX = 4, cellY = 2 }
}), 2)
assertEquals(direct.runtimeState.targetEntityId, nil,
  "lost threat must clear authoritative entity identity")
assertEquals(direct.runtimeState.escapeReference.kind, "LAST_KNOWN_THREAT_POSITION",
  "recently lost direct threat should use frozen memory")
assertEquals(direct.runtimeState.escapeReference.entityId, nil,
  "last-known geometry is not a live entity target")
assertEquals(direct.runtimeState.escapeReference.sourceThreatId, "player",
  "last-known geometry should retain provenance of the prior threat")
assertEquals(direct.runtimeState.escapeReference.position.cellX, frozenX,
  "last-known X must not receive unseen live updates")
assertEquals(direct.runtimeState.escapeReference.position.cellY, frozenY,
  "last-known Y must not receive unseen live updates")
assertEquals(direct.runtimeState.movementRequest.targetEntityId, nil,
  "0014-style unrelated visible Pokemon must not replace a lost player threat")

Controller.executeCurrentIntent(direct, context({ cellX = 6, cellY = 2 }, {
  primaryThreatId = nil
}, { ["wild:route22:0007"] = { cellX = 5, cellY = 2 } }), 92)
assertEquals(direct.runtimeState.escapeReference.kind, "HEADING_INERTIA",
  "expired last-known confidence should transition to targetless continuation")
assertEquals(direct.runtimeState.escapeReference.entityId, nil,
  "heading continuation must remain targetless")
assertEquals(direct.runtimeState.movementRequest.targetEntityId, nil,
  "expired memory must not trigger generic visible-entity fallback")

local social = actor("social-only")
social.runtimeState.fearDirect = 0
social.runtimeState.fearSocial = 0.7
social.runtimeState.socialEscapeBias = { dx = 1, dy = 0 }
social.runtimeState.socialEscapeBiasConfidence = 0.8
social.runtimeState.strongestFearSource = "alarm-a"
Controller.executeCurrentIntent(social, context({ cellX = 3, cellY = 3 }, {
  primaryThreatId = nil
}, {
  ["alarm-a"] = { cellX = 2, cellY = 3 },
  ["alarm-c"] = { cellX = 4, cellY = 3 },
  ["alarm-d"] = { cellX = 3, cellY = 4 }
}, { cellX = 0, cellY = 3 }), 1)
assertEquals(social.runtimeState.escapeReference.kind, "SOCIAL_ESCAPE_VECTOR",
  "social-only panic should use advisory vector geometry")
assertEquals(social.runtimeState.targetEntityId, nil,
  "social alarm source must not become primary threat")
assertEquals(social.runtimeState.escapeReference.entityId, nil,
  "social vector must not carry source identity as threat geometry")
assertEquals(social.runtimeState.intentEpisode.targetId, nil,
  "social-only FLEE episode must be targetless")

for _, sourceId in ipairs({ "alarm-c", "alarm-d", "alarm-a" }) do
  social.runtimeState.strongestFearSource = sourceId
  Controller.executeCurrentIntent(social, context({ cellX = 3, cellY = 3 }, {
    primaryThreatId = nil
  }, { [sourceId] = { cellX = 2, cellY = 3 } }, { cellX = 0, cellY = 3 }), 2)
  assertEquals(social.runtimeState.targetEntityId, nil,
    "strongest social source changes must not change threat identity")
  assertEquals(social.runtimeState.movementRequest.targetEntityId, nil,
    "strongest social source changes must not change movement threat identity")
end

social.runtimeState.fearCurrent = 0
social.runtimeState.fearSocial = 0
social.runtimeState.socialEscapeBias = nil
social.runtimeState.socialEscapeBiasConfidence = 0
social.runtimeState.strongestFearSource = nil
Controller.executeCurrentIntent(social, context({ cellX = 4, cellY = 3 }, {
  primaryThreatId = nil
}, {
  ["wild:route22:0003"] = { cellX = 5, cellY = 3 },
  ["wild:route22:0027"] = { cellX = 4, cellY = 4 }
}), 3)
assertEquals(social.runtimeState.state, "FLEE",
  "0027-style recovery may remain in FLEE while hysteresis completes")
assertEquals(social.runtimeState.escapeReference.kind, "HEADING_INERTIA",
  "zero-social recovery should continue without entity geometry")
assertEquals(social.runtimeState.movementRequest.targetEntityId, nil,
  "0027-style recovery must not select a nearby Pokemon")

local hostileWild = actor("hostile-wild-case")
Controller.executeCurrentIntent(hostileWild, context({ cellX = 5, cellY = 5 }, {
  primaryThreatId = "hostile-wild",
  primaryThreatReason = "DIRECT_THREAT_MEMORY",
  primaryThreatScore = 90,
  primaryThreatDistance = 1
}, { ["hostile-wild"] = { cellX = 4, cellY = 5 } }), 1)
assertEquals(hostileWild.runtimeState.targetEntityId, "hostile-wild",
  "legitimate hostile Pokemon should remain valid direct threats")
assertEquals(hostileWild.runtimeState.escapeReference.kind, "CURRENT_THREAT_POSITION",
  "hostile Pokemon should provide current direct-threat geometry")
assertEquals(hostileWild.runtimeState.movementRequest.targetEntityId, "hostile-wild",
  "hostile Pokemon identity should reach movement provenance")

local invalidRuntime = {
  threatAssessment = { primaryThreatId = nil },
  escapeReference = { kind = "CURRENT_THREAT_POSITION", entityId = "random-wild" }
}
local valid, reason = Controller.validateFleeProvenance(invalidRuntime, {
  primaryThreatId = nil,
  targetEntityId = "random-wild",
  escapeReferenceKind = "CURRENT_THREAT_POSITION",
  escapeReferenceEntityId = "random-wild"
})
assertEquals(valid, false, "movement boundary should reject current geometry without a primary threat")
assertEquals(reason, "CURRENT_REFERENCE_WITHOUT_PRIMARY_THREAT",
  "movement boundary should identify the ownership violation")

return true