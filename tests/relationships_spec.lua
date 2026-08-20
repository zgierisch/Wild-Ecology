local Relationships = require("src.entities.relationships")
local PopulationManager = require("src.population.manager")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local wildA = { id = "wild:a", relationships = {} }
local wildB = { id = "wild:b", relationships = {} }

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
	5
)
assertEquals(threatDelta > 0, true, "trusted associate fear should add threat memory")
assertEquals(updatedRel.threatMemory > 0, true, "player threat memory should increase from social fear")
assertEquals(updatedRel.trust < 20, true, "player trust should reduce slightly from social fear")

local phase2Entity = { id = "wild:phase2", relationships = {} }
local assocRel = PopulationManager.getOrCreatePhase2AssociateRelationship(phase2Entity, 30)
assertEquals(assocRel.familiarity >= 10, true, "phase2 helper should seed associate familiarity")
assertEquals(assocRel.trust >= 60, true, "phase2 helper should seed associate trust")

local phase2PlayerRel = Relationships.getOrCreate(phase2Entity, "player")
phase2PlayerRel.trust = 10
phase2PlayerRel.threatMemory = 0

local updatedPhase2PlayerRel, phase2Delta = PopulationManager.applyPhase2SocialFear(
	phase2Entity,
	{ id = "player" },
	31
)
assertEquals(phase2Delta > 0, true, "phase2 manager helper should apply social fear signal")
assertEquals(updatedPhase2PlayerRel.threatMemory > 0, true, "phase2 manager helper should modify player threat memory")

return true
