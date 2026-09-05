local ThreatAssessment = require("src.behavior.threat_assessment")
local Controller = require("src.behavior.controller")
local Relationships = require("src.entities.relationships")

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local function assess(candidate, relationship)
  local actor = {
    id = "wild",
    temperament = { boldness = 0.2 },
    rawStats = { independence = 0.3 },
    relationships = {}, runtimeState = { fearCurrent = 0.25 }
  }
  candidate.relationship = relationship or {}
  return actor, ThreatAssessment.assess(actor, { candidate }, 10)
end

local unfamiliar, approaching = assess({
  id = "trainer-a", kind = "trainer", distance = 2, motion = "APPROACHING"
}, { familiarity = 0, trust = 0, affinity = 0 })
assertTrue(approaching.primaryThreatId == "trainer-a"
    and approaching.primaryThreatReason == "TRAINER_WARINESS",
  "an unfamiliar nearby approaching trainer should be a transient current threat")

local _, far = assess({ id = "trainer-a", kind = "trainer", distance = 8, motion = "APPROACHING" })
assertTrue(far.primaryThreatId == nil, "trainer existence at comfortable distance must not cause immediate FLEE")

local _, retreating = assess({ id = "trainer-a", kind = "trainer", distance = 4, motion = "RETREATING" })
local _, stationaryClose = assess({ id = "trainer-a", kind = "trainer", distance = 2, motion = "STABLE" })
assertTrue(retreating.primaryThreatScore < approaching.primaryThreatScore,
  "retreat should diminish trainer pressure")
assertTrue(stationaryClose.primaryThreatId == "trainer-a",
  "close trainer proximity should remain meaningful without a fresh approach event")

local _, trusted = assess({ id = "trainer-a", kind = "trainer", distance = 2, motion = "APPROACHING" }, {
  familiarity = 90, trust = 90, affinity = 70
})
assertTrue(trusted.primaryThreatScore < approaching.primaryThreatScore * 0.35,
  "generic directed familiarity and trust should substantially reduce trainer wariness")

local _, peacefulPokemon = assess({ id = "peer", kind = "pokemon", distance = 2, motion = "APPROACHING" })
assertTrue(peacefulPokemon.primaryThreatId == nil,
  "ordinary peaceful Pokemon must not receive trainer-wariness provenance")
local _, hostilePokemon = assess({ id = "aggressor", kind = "pokemon", distance = 2 }, { hostility = 20 })
assertTrue(hostilePokemon.primaryThreatId == "aggressor"
    and hostilePokemon.primaryThreatReason == "HOSTILITY",
  "existing hostile Pokemon provenance should remain authoritative")

local relationship = { familiarity = 0, trust = 0, affinity = 0, directThreatMemory = 0, threatMemory = 0 }
local naturalActor, natural = assess({
  id = "trainer-b", kind = "trainer", distance = 2, motion = "APPROACHING"
}, relationship)
naturalActor.personalitySeed = 2
Controller.tick(naturalActor, relationship, 2, {
  threatAssessment = natural,
  targetPositions = { ["trainer-b"] = { cellX = 2, cellY = 2 } },
  position = { cellX = 4, cellY = 2 },
  currentFear = 0.25
}, 10)
assertTrue(naturalActor.runtimeState.state == "FLEE"
    and naturalActor.runtimeState.movementRequest
    and naturalActor.runtimeState.movementRequest.traversalMode == "WALK",
  "natural trainer wariness should select FLEE and produce WALK movement")
assertTrue(relationship.directThreatMemory == 0 and relationship.threatMemory == 0,
  "mere trainer proximity/approach must not write persistent threat memory")

local attacked = { relationships = {}, runtimeState = {} }
Relationships.applyPerceptionEvent(attacked, "trainer-b", "ENTITY_ATTACKED", { threatDelta = 3 }, 11)
assertTrue(attacked.relationships["trainer-b"].directThreatMemory == 3,
  "actual attack provenance should retain existing persistent direct-threat behavior")

return true