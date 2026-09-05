local BehaviorDebugPreset = require("src.behavior.debug_preset")
local ThreatAssessment = require("src.behavior.threat_assessment")
local Fear = require("src.behavior.fear")
local Controller = require("src.behavior.controller")

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local function scoreText(runtime)
  local scores = runtime.behaviorScores or {}
  return string.format(
    "FLEE=%.2f APPROACH=%.2f INVESTIGATE=%.2f SEEK_FLOCK=%.2f TARGET=%.2f IDLE=%.2f selected=%s reason=%s",
    scores.FLEE or 0, scores.APPROACH or 0, scores.INVESTIGATE or 0,
    scores.SEEK_FLOCK or 0, scores.TARGET or 0, scores.IDLE or 0,
    tostring(runtime.state), tostring(runtime.selectionReason))
end

local function evaluate(presetName, options)
  local settings = options or {}
  local relationship = settings.relationship or {
    familiarity = 0, trust = 0, affinity = 0,
    threatMemory = 0, directThreatMemory = 0, hostility = 0
  }
  local actor = {
    id = "preset-actor",
    species = "PIDGEY",
    personalitySeed = 7,
    ecology = { archetype = "flocking_bird" },
    temperament = { curiosity = 0.4, boldness = 0.3, sociability = 0.6 },
    rawStats = { independence = 0.4 },
    relationships = { trainer = relationship },
    runtimeState = {
      fearCurrent = settings.fearCurrent or 0,
      fearDirect = settings.fearDirect or 0,
      fearSocial = settings.fearSocial or 0
    }
  }
  local candidate = {
    id = "trainer", kind = "trainer", distance = settings.distance or 2,
    motion = settings.motion or "APPROACHING", relationship = relationship,
    directThreatSeverity = settings.directThreatSeverity
  }
  local model = BehaviorDebugPreset.apply(presetName, actor, candidate, relationship)
  assertTrue(model.forceState == nil, "debug presets must never own the selected state")
  local assessment = ThreatAssessment.assess(model.entity, { model.candidate }, 100)
  Fear.update(actor, {
    threatAssessment = assessment,
    threatDistance = assessment.primaryThreatDistance,
    relationship = model.relationship,
    socialSources = model.socialSources
  }, 100)
  actor.runtimeState.fearCurrent = model.fearCurrent ~= nil and model.fearCurrent or actor.runtimeState.fearCurrent
  actor.runtimeState.fearDirect = model.fearDirect ~= nil and model.fearDirect or actor.runtimeState.fearDirect
  actor.runtimeState.fearSocial = model.fearSocial ~= nil and model.fearSocial or actor.runtimeState.fearSocial
  local state = Controller.tick(actor, model.relationship, model.candidate.distance, {
    behaviorEntity = model.entity,
    debugPreset = model.name,
    threatAssessment = assessment,
    targetEntityId = "trainer",
    candidates = { { id = "trainer", distance = model.candidate.distance, novelty = model.novelty } },
    targetPositions = { trainer = { cellX = 2, cellY = 2 } },
    position = { cellX = 4, cellY = 2 },
    hasTarget = model.hasTarget,
    purposefulTarget = model.purposefulTarget,
    currentFear = actor.runtimeState.fearCurrent,
    socialAlarmTargetPosition = model.socialAlarmTargetPosition,
    allowTargeting = model.allowTargeting,
    debugIdleElapsed = model.idleElapsed,
    debugSettledElapsed = model.settledElapsed,
    idleElapsed = 0,
    targetElapsed = 0,
    approachSatisfiedElapsed = 0
  }, 100)
  return state, actor, assessment, model
end

local approachState, approachActor, approachThreat, approachModel = evaluate("APPROACH")
assertTrue(approachState == "APPROACH", "APPROACH preset should win normal scoring: " .. scoreText(approachActor.runtimeState))
assertTrue(approachThreat.primaryThreatId == nil and approachModel.relationship.trust >= 80,
  "APPROACH should synthesize calm trusted production inputs, not disable FLEE")
assertTrue(approachModel.originalInputs.trust == 0 and approachModel.adjustedInputs.trust == 90,
  "preset diagnostics should expose original and adjusted model inputs")

local unchangedRelationship = { trust = 37, affinity = 22 }
local unchanged = BehaviorDebugPreset.apply(nil,
  { temperament = { curiosity = 0.4 }, rawStats = {} },
  { id = "trainer", motion = "STABLE" }, unchangedRelationship)
assertTrue(unchanged.name == nil and unchanged.relationship.trust == 37
    and unchanged.adjustedInputs.trust == unchanged.originalInputs.trust,
  "no preset should preserve model values")

local fleeState, fleeActor, fleeThreat = evaluate("FLEE")
assertTrue(fleeState == "FLEE", "FLEE preset should win normal scoring: " .. scoreText(fleeActor.runtimeState))
assertTrue(fleeThreat.primaryThreatId == "trainer" and fleeThreat.primaryThreatReason == "TRAINER_WARINESS",
  "FLEE preset must pass through legitimate threat assessment")

local investigateState, investigateActor = evaluate("INVESTIGATE")
assertTrue(investigateState == "INVESTIGATE",
  "INVESTIGATE preset should win normal scoring: " .. scoreText(investigateActor.runtimeState))
local idleState, idleActor = evaluate("IDLE")
assertTrue(idleState == "SETTLED", "IDLE preset should demonstrate passive equilibrium: " .. scoreText(idleActor.runtimeState))
local targetState, targetActor = evaluate("TARGET")
assertTrue(targetState == "TARGET", "TARGET preset should win from controlled restlessness: " .. scoreText(targetActor.runtimeState))

local lowState = evaluate(nil, { relationship = {
  familiarity = 0, trust = 0, affinity = 0, threatMemory = 0, directThreatMemory = 0, hostility = 0
} })
local mediumState = evaluate(nil, { relationship = {
  familiarity = 55, trust = 45, affinity = 30, threatMemory = 0, directThreatMemory = 0, hostility = 0
}, motion = "STABLE", distance = 3 })
local highState = evaluate(nil, { relationship = {
  familiarity = 95, trust = 90, affinity = 85, threatMemory = 0, directThreatMemory = 0, hostility = 0
}, motion = "STABLE", distance = 2 })
assertTrue(lowState == "FLEE", "low trainer comfort should favor FLEE")
assertTrue(mediumState == "INVESTIGATE" or mediumState == "APPROACH",
  "medium comfort should move toward uncertainty/interest")
assertTrue(highState == "APPROACH", "high comfort should favor APPROACH")

local calmState = evaluate("APPROACH")
local moderateState, moderateActor = evaluate(nil, { relationship = {
  familiarity = 95, trust = 90, affinity = 85, threatMemory = 0, directThreatMemory = 0, hostility = 0
}, fearCurrent = 0.45, fearSocial = 0.45, motion = "STABLE" })
local emergencyState, emergencyActor, emergencyThreat = evaluate("APPROACH", { directThreatSeverity = 2 })
assertTrue(calmState == "APPROACH", "calm high comfort should approach")
assertTrue(moderateState == "APPROACH" and moderateActor.runtimeState.emergencyFlee == false,
  "moderate social alarm with high trust should compete through utility")
assertTrue(emergencyState == "FLEE" and emergencyThreat.primaryThreatReason == "HIGH_SEVERITY_EVENT",
  "severe attack evidence must override the controlled APPROACH counterfactual")

return true