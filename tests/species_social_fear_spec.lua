local Fear = require("src.behavior.fear")

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local function entity(id, species, archetype)
  return {
    id = id,
    species = species,
    ecology = { archetype = archetype, family = "A" },
    temperament = { sociability = 0.7 },
    rawStats = { independence = 0.3 },
    relationships = {},
    runtimeState = { state = "FLEE" }
  }
end

local function source(id, species, archetype, alarmOutput, groundedness, directComponent, relayedComponent)
  return {
    id = id,
    species = species,
    ecology = { archetype = archetype, family = "A" },
    alarmOutput = alarmOutput,
    alarmGroundedness = groundedness,
    alarmDirectComponent = directComponent or 0,
    alarmRelayedComponent = relayedComponent or 0,
    state = "FLEE",
    distance = 1,
    relationship = {}
  }
end

local sameObserver = entity("same", "SPECIES_A", "flocking_bird")
local otherObserver = entity("other", "SPECIES_B", "flocking_bird")
local groundedSource = source("source", "SPECIES_A", "flocking_bird", 0.9, 1, 0.9, 0)
local sameFear, sameDetails = Fear.socialInput(sameObserver, { groundedSource }, 5)
local otherFear, otherDetails = Fear.socialInput(otherObserver, { groundedSource }, 5)
assertTrue(sameFear > otherFear and otherFear > 0,
  "same-species alarm should exceed nonzero heterospecific alarm under otherwise equal conditions")
assertTrue(sameDetails.contributionDetails[1].speciesAlarmCompatibility
    > otherDetails.contributionDetails[1].speciesAlarmCompatibility,
  "diagnostics should expose the species compatibility difference")
assertTrue(sameDetails.escapeBiasConfidence >= otherDetails.escapeBiasConfidence,
  "heterospecific compatibility must not strengthen directional authority")

local relayA = entity("relay-a", "SPECIES_A", "flocking_bird")
Fear.update(relayA, { socialSources = { groundedSource }, perceptionRadius = 5 }, 1)
local boundarySource = source(
  relayA.id, relayA.species, relayA.ecology.archetype,
  relayA.runtimeState.alarmOutput, relayA.runtimeState.alarmGroundedness,
  relayA.runtimeState.alarmDirectComponent, relayA.runtimeState.alarmRelayedComponent
)
local relayB = entity("relay-b", "SPECIES_B", "flocking_bird")
Fear.update(relayB, { socialSources = { boundarySource }, perceptionRadius = 5 }, 2)
assertTrue(relayB.runtimeState.alarmOutput < relayA.runtimeState.alarmOutput,
  "crossing a species boundary should further attenuate relayed alarm")

local relayBSource = source(
  relayB.id, relayB.species, relayB.ecology.archetype,
  relayB.runtimeState.alarmOutput, relayB.runtimeState.alarmGroundedness,
  relayB.runtimeState.alarmDirectComponent, relayB.runtimeState.alarmRelayedComponent
)
local relayB2 = entity("relay-b-2", "SPECIES_B", "flocking_bird")
Fear.update(relayB2, { socialSources = { relayBSource }, perceptionRadius = 5 }, 3)
local inheritedB2Alarm = relayB2.runtimeState.alarmOutput
assertTrue(relayB2.runtimeState.alarmOutput < relayB.runtimeState.alarmOutput,
  "A1 to A2 to B1 to B2 should continue losing alarm after the species boundary")

local beforeGrounding = relayB.runtimeState.alarmOutput
Fear.update(relayB, {
  relationship = { hostility = 100 },
  threatDistance = 1,
  socialSources = {},
  perceptionRadius = 5
}, 4)
assertTrue(relayB.runtimeState.alarmDirectComponent > relayB.runtimeState.alarmRelayedComponent,
  "direct evidence should re-ground a previously social receiver")
assertTrue(relayB.runtimeState.alarmOutput > beforeGrounding,
  "direct re-grounding should restore strong outgoing alarm")
local regroundedSource = source(
  relayB.id, relayB.species, relayB.ecology.archetype,
  relayB.runtimeState.alarmOutput, relayB.runtimeState.alarmGroundedness,
  relayB.runtimeState.alarmDirectComponent, relayB.runtimeState.alarmRelayedComponent
)
local regroundedB2 = entity("regrounded-b-2", "SPECIES_B", "flocking_bird")
Fear.update(regroundedB2, { socialSources = { regroundedSource }, perceptionRadius = 5 }, 5)
assertTrue(regroundedB2.runtimeState.alarmOutput > inheritedB2Alarm,
  "directly re-grounded B1 should emit a stronger conspecific warning to B2")

local mixedSame = entity("mixed-same", "SPECIES_A", "flocking_bird")
local mixedSame2 = entity("mixed-same-2", "SPECIES_A", "flocking_bird")
local mixedOther = entity("mixed-other", "SPECIES_B", "flocking_bird")
local mixedOther2 = entity("mixed-other-2", "SPECIES_B", "flocking_bird")
Fear.update(mixedSame, { socialSources = { groundedSource }, perceptionRadius = 5 }, 10)
Fear.update(mixedSame2, { socialSources = { groundedSource }, perceptionRadius = 5 }, 10)
Fear.update(mixedOther, { socialSources = { groundedSource }, perceptionRadius = 5 }, 10)
Fear.update(mixedOther2, { socialSources = { groundedSource }, perceptionRadius = 5 }, 10)
assertTrue(mixedSame.runtimeState.fearSocial > mixedOther.runtimeState.fearSocial
    and mixedOther.runtimeState.fearSocial > 0,
  "a mixed crowd should respond unequally without suppressing heterospecific fear")
assertTrue((mixedSame.runtimeState.fearSocial + mixedSame2.runtimeState.fearSocial) / 2
    > (mixedOther.runtimeState.fearSocial + mixedOther2.runtimeState.fearSocial) / 2,
  "direct-grounded panic should remain strongest within its species in a mixed local crowd")
assertTrue(mixedOther.runtimeState.fearSocial >= 0.22,
  "a strong nearby direct-grounded heterospecific alarm may still recruit flight")

local directTrigger, directSafety = Fear.escapeDistances(4, 0.9, 0.9, 0, 0)
local socialTrigger, socialSafety = Fear.escapeDistances(4, 0.9, 0, 0.9, 0.4)
assertTrue(directTrigger > socialTrigger and directSafety > socialSafety,
  "equal internal fear should expand flee distance more when directly grounded")

return true