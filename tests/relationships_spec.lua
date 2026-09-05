local Relationships = require("src.entities.relationships")
local PopulationManager = require("src.population.manager")
local Social = require("src.behavior.social")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local wildA = { id = "wild:a", relationships = {} }
local wildB = { id = "wild:b", relationships = {} }
local cappedEntity = { id = "wild:capped", relationships = {}, memory = { debug = { respawnCount = 1 } } }

local genericShapeObserver = {
	id = "wild:shape-observer",
	species = "PIDGEY",
	ecology = { socialModifier = 0.25, family = "A", familySocialModifier = 1.25 },
	relationships = {}
}
local pokemonContact = Social.observeNearby(genericShapeObserver, "wild:shape-target", 2, 1, {
	id = "wild:shape-target", species = "PIDGEY", ecology = { family = "A" }
})
local playerContact = Relationships.getOrCreate(genericShapeObserver, "player")
for _, field in ipairs({
	"familiarity", "trust", "affinity", "threatMemory", "directThreatMemory",
	"hostility", "lastSeenTick", "lastCalmTick", "lastVisitSerial",
	"calmWarmupThisVisit", "importance"
}) do
	assertEquals(type(pokemonContact[field]), type(playerContact[field]),
		"Pokemon and player first contact should use the same generic relationship field: " .. field)
end

local rel, applied = Relationships.observeCalmProximity(wildA, "player", 10, 3)
assertEquals(applied, true, "first calm proximity should apply")
assertEquals(rel.familiarity, 1, "familiarity should increase on first calm proximity")

local rel2, applied2 = Relationships.observeCalmProximity(wildA, "player", 11, 3)
assertEquals(applied2, false, "cooldown should block rapid trust farming")
assertEquals(rel2.familiarity, 1, "familiarity should not increase during cooldown")

local rel3, applied3 = Relationships.observeCalmProximity(wildA, "player", 14, 3)
assertEquals(applied3, true, "calm proximity should apply after cooldown")
assertEquals(rel3.familiarity, 2, "familiarity should increase after cooldown")

local relB = Relationships.getOrCreate(wildB, "player")
assertEquals(relB.familiarity, 0, "relationships are directional and sparse per entity")

local capFirst, capAppliedFirst = Relationships.observeCalmProximity(cappedEntity, "player", 50, 1, 2)
assertEquals(capAppliedFirst, true, "first warmup tick should apply before the visit cap")
local capSecond, capAppliedSecond = Relationships.observeCalmProximity(cappedEntity, "player", 51, 1, 2)
assertEquals(capAppliedSecond, true, "second warmup tick should still apply before the visit cap")
local capSecondTrust = capSecond.trust
local capSecondFamiliarity = capSecond.familiarity
local capThird, capAppliedThird = Relationships.observeCalmProximity(cappedEntity, "player", 52, 1, 2)
assertEquals(capAppliedThird, false, "third warmup tick should stop once the per-visit cap is reached")
assertEquals(capThird.calmWarmupThisVisit, 2, "warmup count should stop at the configured cap")
assertEquals(capThird.trust > capSecondTrust, false, "trust should stop increasing after the per-visit cap")
assertEquals(capThird.familiarity > capSecondFamiliarity, true, "familiarity should still reflect continued exposure")

cappedEntity.memory.debug.respawnCount = 2
local resetRel, resetApplied = Relationships.observeCalmProximity(cappedEntity, "player", 60, 1, 2)
assertEquals(resetApplied, true, "a new visit should reset the warmup cap")
assertEquals(resetRel.calmWarmupThisVisit, 1, "new visit should restart the warmup counter")

local managerCappedEntity = {
	id = "wild:manager-capped",
	relationships = {},
	relationshipWarmupCap = 1,
	memory = { debug = { respawnCount = 1 } }
}
local _, managerFirstGain = PopulationManager.updatePhase0Relationship(managerCappedEntity, { id = "player" }, 100, 2)
local _, managerCappedGain = PopulationManager.updatePhase0Relationship(managerCappedEntity, { id = "player" }, 200, 2)
assertEquals(managerFirstGain, true, "population relationship update should report a real trust gain")
assertEquals(managerCappedGain, false, "population relationship update should not report trust gain after the visit cap")

local nearCalmRel, nearCalmApplied = Relationships.observeCalmProximity(wildB, "player", 20, 3, 2)
assertEquals(nearCalmApplied, true, "near calm proximity should still apply")
assertEquals(nearCalmRel.trust > 0, true, "near calm proximity should raise trust")

local farCalmRel, farCalmApplied = Relationships.observeCalmProximity(wildB, "player", 30, 3, 8)
assertEquals(farCalmApplied, true, "far calm proximity should still apply as a tiny signal")
assertEquals(farCalmRel.trust <= nearCalmRel.trust, true, "far calm proximity should be weaker than near calm proximity")

local socialSource = Relationships.getOrCreate(wildA, "wild:associate")
socialSource.trust = 80

local playerRel = Relationships.getOrCreate(wildA, "player")
playerRel.trust = 20
playerRel.threatMemory = 0

local updatedRel, threatDelta = Relationships.applySocialFear(
	wildA,
	"wild:associate",
	"player",
	21,
	5,
	0,
	2
)
assertEquals(threatDelta > 0, true, "trusted associate fear should add threat memory")
assertEquals(updatedRel.threatMemory > 0, true, "player threat memory should increase from social fear")
assertEquals(updatedRel.trust < 20, true, "player trust should reduce slightly from social fear")

local fartherRel, fartherDelta = Relationships.applySocialFear(
	wildA,
	"wild:associate",
	"player",
	40,
	5,
	0,
	8
)
assertEquals(fartherDelta < threatDelta, true, "farther social fear should have a smaller effect")
assertEquals(fartherRel.threatMemory >= updatedRel.threatMemory, true, "threat memory should still accumulate")

local reassuringRel = Relationships.getOrCreate(wildA, "player")
reassuringRel.threatMemory = 12
reassuringRel.trust = 10

local calmDeltaRel, calmDelta, calmApplied = Relationships.applySocialReassurance(
	wildA,
	"wild:associate",
	"player",
	41,
	5,
	0,
	2
)
assertEquals(calmApplied, true, "trusted associate reassurance should apply")
assertEquals(calmDelta > 0, true, "trusted associate reassurance should reduce threat memory")
assertEquals(calmDeltaRel.threatMemory < 12, true, "reassurance should lower player threat memory")
assertEquals(calmDeltaRel.trust > 10, true, "reassurance should raise trust slightly")

local phase2Entity = { id = "wild:phase2", relationships = {} }
local weakAssociate = { id = "wild:weak_associate", runtimeState = { state = "FLEE", targetEntityId = "player" } }
local weakRel = Relationships.getOrCreate(phase2Entity, weakAssociate.id)
weakRel.trust = 10
weakRel.affinity = 0

local blockedPlayerRel, blockedDelta = PopulationManager.propagateAssociateSocialSignal(
	phase2Entity,
	weakAssociate,
	31,
	2
)
assertEquals(blockedDelta, 0, "untrusted associates should not propagate social fear")
assertEquals(blockedPlayerRel, nil, "untrusted associate propagation should return no relationship")

local trustedAssociate = { id = "wild:trusted_associate", runtimeState = { state = "FLEE", targetEntityId = "player" } }
local trustedRel = Relationships.getOrCreate(phase2Entity, trustedAssociate.id)
trustedRel.trust = 80
trustedRel.affinity = 50

local phase2PlayerRel = Relationships.getOrCreate(phase2Entity, "player")
phase2PlayerRel.trust = 10
phase2PlayerRel.threatMemory = 0

local updatedPhase2PlayerRel, phase2Delta, phase2Kind = PopulationManager.propagateAssociateSocialSignal(
	phase2Entity,
	trustedAssociate,
	76,
	2
)
assertEquals(phase2Kind, "fear", "a fleeing trusted associate should propagate fear, not reassurance")
assertEquals(phase2Delta > 0, true, "a trusted fleeing associate should apply a social fear signal")
local threatMemoryAfterFear = updatedPhase2PlayerRel and updatedPhase2PlayerRel.threatMemory or 0
assertEquals(threatMemoryAfterFear > 0, true, "propagated fear should raise threat memory toward whatever the associate fled from")

local calmAssociate = { id = "wild:calm_associate", runtimeState = { state = "APPROACH", targetEntityId = "player" } }
local calmRel = Relationships.getOrCreate(phase2Entity, calmAssociate.id)
calmRel.trust = 80
calmRel.affinity = 50

local reassuredPlayerRel, reassuranceDelta, reassuranceKind = PopulationManager.propagateAssociateSocialSignal(
	phase2Entity,
	calmAssociate,
	120,
	2
)
assertEquals(reassuranceKind, "reassurance", "an approaching trusted associate should propagate reassurance, not fear")
assertEquals(reassuranceDelta > 0, true, "a trusted calm associate should apply a social reassurance signal")
local threatMemoryAfterReassurance = reassuredPlayerRel and reassuredPlayerRel.threatMemory or math.huge
assertEquals(threatMemoryAfterReassurance < threatMemoryAfterFear, true, "propagated reassurance should lower threat memory toward the same target")

return true
