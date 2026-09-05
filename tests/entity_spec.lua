local Entity = require("src.entities.entity")
local BaseRanges = require("src.species.base_ranges")
local SpeciesEcology = require("src.species.species_ecology")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function contains(list, value)
	for _, item in ipairs(list) do
		if item == value then
			return true
		end
	end
	return false
end

local pidgeyA = Entity.newWildPokemon({
	id = "wild:test:0001",
	species = "PIDGEY",
	level = 4,
	personalitySeed = 847219
})

local pidgeyB = Entity.newWildPokemon({
	id = "wild:test:0002",
	species = "PIDGEY",
	level = 4,
	personalitySeed = 847219
})

local pidgeyC = Entity.newWildPokemon({
	id = "wild:test:0003",
	species = "PIDGEY",
	level = 4,
	personalitySeed = 777777
})

assertEquals(pidgeyA.temperament.boldness, pidgeyB.temperament.boldness, "same seed should produce same boldness")
assertEquals(pidgeyA.temperament.sociability, pidgeyB.temperament.sociability, "same seed should produce same sociability")
assertEquals(pidgeyA.ecology.family, pidgeyB.ecology.family, "same seed should produce the same assigned family")
local pidgeyEcology = SpeciesEcology.resolve("PIDGEY")
assertEquals(pidgeyEcology.archetype, "flocking_bird", "Pidgey should use the flocking bird ecology profile")
assertEquals(pidgeyEcology.social.modifier, 1.5, "Pidgey should have a strong social modifier")
assertEquals(pidgeyEcology.social.desiredGroupSize, 3, "Pidgey ecology should define its desired social group size")
assertEquals(contains(BaseRanges.get("PIDGEY").familyPool, pidgeyA.ecology.family), true, "assigned family should come from the species' family pool")
assertEquals(pidgeyA.temperament.boldness, 1 - pidgeyA.rawStats.timidity, "boldness should derive from raw timidity")
assertEquals(pidgeyA.temperament.sociability, pidgeyA.rawStats.social, "sociability should derive from raw social")
assertEquals(pidgeyA.temperament.curiosity, pidgeyA.rawStats.curiosity, "curiosity should derive from raw curiosity")

local pidgeyRange = BaseRanges.get("PIDGEY").stats
for _, statName in ipairs({ "curiosity", "timidity", "aggression", "social", "active", "independence" }) do
	local value = pidgeyA.rawStats[statName]
	local range = pidgeyRange[statName]
	assertEquals(value >= range.min and value <= range.max, true, statName .. " should fall within its species range")
end

if pidgeyA.temperament.boldness == pidgeyC.temperament.boldness
and pidgeyA.temperament.sociability == pidgeyC.temperament.sociability then
	error("different seeds should vary at least one temperament trait")
end

local rattata = Entity.newWildPokemon({
	id = "wild:test:0004",
	species = "RATTATA",
	level = 3,
	personalitySeed = 847219
})
local rattataEcology = SpeciesEcology.resolve("RATTATA")
assertEquals(rattataEcology.archetype, "small_forager", "Rattata should use its own ecology profile")
assertEquals(rattataEcology.social.modifier < pidgeyEcology.social.modifier, true, "species social modifiers should differ")
assertEquals(rattata.encounteredLevel, 3, "encounteredLevel should default to the level at generation")
assertEquals(rattata.level, rattata.encounteredLevel, "current level should start equal to encountered level")
return true