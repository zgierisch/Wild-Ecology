local ThreatAssessment = require("src.behavior.threat_assessment")
local Controller = require("src.behavior.controller")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local actor = { id = "actor", relationships = {}, runtimeState = {} }
local first = ThreatAssessment.assess(actor, {
  { id = "x", kind = "pokemon", distance = 2, relationship = { hostility = 12 } },
  { id = "y", kind = "pokemon", distance = 2, relationship = { hostility = 10 } }
}, 10)
assertEquals(first.primaryThreatId, "x", "strongest legitimate threat should become primary")
assertEquals(first.primaryThreatReason, "HOSTILITY", "direct threat should expose provenance")

local marginal = ThreatAssessment.assess(actor, {
  { id = "x", kind = "pokemon", distance = 2, relationship = { hostility = 12 } },
  { id = "y", kind = "pokemon", distance = 2, relationship = { hostility = 13 } }
}, 11)
assertEquals(marginal.primaryThreatId, "x", "marginal score changes must not switch primary threat")
assertEquals(marginal.challengerThreatId, "y", "diagnostics should expose the rejected challenger")
assertEquals(marginal.threatSwitch, false, "marginal challenger should not report a switch")

actor.runtimeState.fearCurrent = 0.8
Controller.tick(actor, { hostility = 12 }, 2, {
  threatAssessment = marginal,
  targetEntityId = "y",
  candidates = {
    { id = "x", distance = 2, novelty = 0 },
    { id = "y", distance = 1, novelty = 100 }
  }
}, 11)
assertEquals(actor.runtimeState.targetEntityId, "x", "generic target ranking must not own the FLEE target")

local severe = ThreatAssessment.assess(actor, {
  { id = "x", kind = "pokemon", distance = 2, relationship = { hostility = 12 } },
  { id = "y", kind = "pokemon", distance = 2, relationship = { hostility = 13 }, directThreatSeverity = 1 }
}, 12)
assertEquals(severe.primaryThreatId, "y", "a severe direct event should override threat commitment")
assertEquals(severe.threatSwitch, true, "severe event should report a threat switch")
assertEquals(severe.threatSwitchReason, "HIGH_SEVERITY_EVENT", "switch diagnostics should explain the override")

local mutualA = { id = "a", relationships = {}, runtimeState = { fearSocial = 0.8 } }
local mutualB = { id = "b", relationships = {}, runtimeState = { fearSocial = 0.8 } }
local aAssessment = ThreatAssessment.assess(mutualA, {
  { id = "b", kind = "pokemon", distance = 1, relationship = {}, perceivedFear = 8, approaching = true }
}, 20)
local bAssessment = ThreatAssessment.assess(mutualB, {
  { id = "a", kind = "pokemon", distance = 1, relationship = {}, perceivedFear = 8, approaching = true }
}, 20)
assertEquals(aAssessment.primaryThreatId, nil, "a frightened approaching conspecific is not inherently a direct threat")
assertEquals(bAssessment.primaryThreatId, nil, "mutual social fear must not create reciprocal direct threats")

local source = { id = "source", runtimeState = { state = "FLEE", fearCurrent = 0.9, targetEntityId = "external" } }
local observer = { id = "observer", relationships = {}, runtimeState = { fearSocial = 0.7 } }
local socialOnly = ThreatAssessment.assess(observer, {
  { id = source.id, kind = "pokemon", distance = 1, relationship = {}, socialFearSource = true }
}, 30)
assertEquals(socialOnly.primaryThreatId, nil, "panic source must not become the observer's direct threat")
assertEquals(observer.relationships.external, nil, "hidden external threat identity must not cross the social boundary")

local hostile = ThreatAssessment.assess({ id = "prey", runtimeState = {} }, {
  { id = "aggressor", kind = "pokemon", distance = 2, relationship = { hostility = 20 } }
}, 40)
assertEquals(hostile.primaryThreatId, "aggressor", "genuinely hostile Pokemon should remain valid threats")
assertTrue(hostile.primaryThreatScore > 0, "legitimate threat should have a positive score")
assertEquals(hostile.identifiedThreatCount, 1, "identified threat count should include only legitimate threats")

return true