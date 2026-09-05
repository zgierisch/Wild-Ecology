package.path = package.path .. ";./?.lua;./?/init.lua"

local PokemonMechanics = require("src.adapters.pokemon_mechanics")
local Gen1 = require("src.adapters.gen1.pokemon_mechanics")
local MoveSemantics = require("src.mechanics.move_semantics")
local EcologicalPhenotype = require("src.mechanics.ecological_phenotype")
local SpeciesEcology = require("src.species.species_ecology")
local EcologyPhysiology = require("src.species.ecology_physiology")
local TraversalCapabilities = require("src.navigation.traversal_capabilities")
local Entity = require("src.entities.entity")

PokemonMechanics.register(Gen1)
local function actor(id, dvs, statExp, moveIds)
	local moves = {}
	for slot, moveId in ipairs(moveIds or {}) do
		moves[slot] = { id = moveId, pp = 5 }
	end
	return Entity.newWildPokemon({ id = id, species = "PIDGEY", level = 10,
		personalitySeed = 100, mechanics = { adapter = "GEN1", pokemon = {
			species = "PIDGEY", level = 10, hp = 25, dvs = dvs,
			statExp = statExp, stats = { hp = 30, attack = 20, defense = 18,
				speed = 25, special = 19 }, moves = moves
		} } })
end

local low = actor("low", { attack = 1, defense = 1, speed = 1, special = 1 },
	{ hp = 0, attack = 0, defense = 0, speed = 0, special = 0 }, { "FLY" })
local high = actor("high", { attack = 15, defense = 15, speed = 15, special = 15 },
	{ hp = 65535, attack = 65535, defense = 65535, speed = 65535, special = 65535 },
	{ "FLY" })
local lowSnapshot = PokemonMechanics.snapshot(low)
local highSnapshot = PokemonMechanics.snapshot(high)
local lowPhenotype = EcologicalPhenotype.derive(lowSnapshot)
local highPhenotype = EcologicalPhenotype.derive(highSnapshot)
assert(highPhenotype.mobility > lowPhenotype.mobility,
	"same-species innate and development differences should affect physical phenotype")
assert(highPhenotype.endurance > lowPhenotype.endurance,
	"stat development should affect endurance through normalized mechanics")

local otherMoves = actor("other-moves",
	{ attack = 1, defense = 1, speed = 1, special = 1 },
	{ hp = 0, attack = 0, defense = 0, speed = 0, special = 0 }, { "ROAR" })
local otherPhenotype = EcologicalPhenotype.derive(PokemonMechanics.snapshot(otherMoves))
assert(otherPhenotype.mobility == lowPhenotype.mobility,
	"move-set differences must not alter physical phenotype")
assert(otherMoves.temperament.aggression == low.temperament.aggression,
	"moves and mechanics must not create personality differences")
local lowPhysiology = EcologyPhysiology.forEntity(low)
local highPhysiology = EcologyPhysiology.forEntity(high)
assert(highPhysiology.fatigueRate < lowPhysiology.fatigueRate,
	"greater endurance should modestly reduce fatigue accumulation")
assert(highPhysiology.restRecovery > lowPhysiology.restRecovery,
	"greater recovery capacity should modestly improve rest recovery")

local moveSnapshot = { moves = {
	{ slot = 1, canonicalKey = "DIG", known = true, usableNow = true },
	{ slot = 2, canonicalKey = "ROAR", known = true, usableNow = false },
	{ slot = 3, canonicalKey = "RECOVER", known = true, usableNow = true }
} }
local semantics = MoveSemantics.analyze(moveSnapshot, {
	semanticAvailability = { BURROW = true, LOUD_SIGNAL = true,
		SELF_RECOVERY = true },
	executableAffordances = { LOUD_SIGNAL = true }
})
assert(semantics.declaredCapabilities.BURROW,
	"known traversal moves should declare learned capability")
assert(semantics.options[1].semanticallyPossible and not semantics.options[1].executable,
	"semantic possibility must not imply executable support")
assert(not semantics.options[3].available,
	"an unusable known move must not become an available ecological option")

local declarations = TraversalCapabilities.declarationsForEntity(low)
assert(declarations.biological.FLY and declarations.learned.FLY,
	"biological and learned traversal declarations should remain separately inspectable")
assert(declarations.executable.WALK and not declarations.executable.FLY,
	"learned FLY must not bypass WALK-only execution authority")

local pidgey = SpeciesEcology.resolve("PIDGEY")
local fallback = SpeciesEcology.resolve("UNPROFILED_SPECIES")
assert(pidgey.social.modifier == 1.5 and pidgey.activityProfile == "DIURNAL",
	"species overrides should layer over archetype defaults")
assert(fallback.archetype == "solitary" and fallback.biologicalCapabilities.WALK,
	"unknown species should receive a valid conservative fallback")
local invalid = SpeciesEcology.resolve("PIDGEY")
invalid.physiology.thirstRate = 99
assert(not pcall(SpeciesEcology.validate, invalid),
	"invalid profile data should fail validation")

for _, phenotype in ipairs({ lowPhenotype, highPhenotype, otherPhenotype }) do
	for _, key in ipairs({ "mobility", "endurance", "robustness",
		"physicalPower", "recoveryCapacity" }) do
		assert(phenotype[key] >= 0 and phenotype[key] <= 1,
			"phenotype dimensions must remain bounded")
	end
end

local originalMobility = lowPhenotype.mobility
low.mechanics.pokemon.dvs.speed = 15
local revisedSignature = PokemonMechanics.signature(low)
local revisedPhenotype = EcologicalPhenotype.forEntity(low,
	PokemonMechanics.snapshot(low), revisedSignature)
assert(revisedPhenotype.mobility > originalMobility,
	"mechanics signatures must invalidate phenotype after source changes")

local started = os.clock()
for _ = 1, 10000 do
	local snapshot = PokemonMechanics.snapshot(high)
	local phenotype = EcologicalPhenotype.forEntity(high, snapshot,
		PokemonMechanics.signature(high))
	assert(phenotype.mobility >= 0 and phenotype.mobility <= 1)
end
assert(os.clock() - started < 2,
	"10,000 cached mechanics/phenotype reads should remain bounded")

return true