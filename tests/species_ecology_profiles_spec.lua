package.path = package.path .. ";./?.lua;./?/init.lua"

local SpeciesEcology = require("src.species.species_ecology")
local EcologyArchetypes = require("src.species.ecology_archetypes")
local Profiles = require("src.species.profiles")
local TraversalCapabilities = require("src.navigation.traversal_capabilities")
local CircadianSystem = require("src.circadian.circadian_system")
local Entity = require("src.entities.entity")
local EcologyPhysiology = require("src.species.ecology_physiology")
local DormantCohortSimulator = require("src.dormant.dormant_cohort_simulator")

assert(SpeciesEcology.validateDefinitions(EcologyArchetypes, Profiles))

local pidgey = SpeciesEcology.resolve("PIDGEY")
local pidgeyAgain = SpeciesEcology.resolve("PIDGEY")
pidgey.social.modifier = 0
pidgey.habitat[1] = "GENERAL"
assert(pidgeyAgain.social.modifier == 1.5
	and pidgeyAgain.habitat[1] == "OPEN_GRASS",
	"resolved profiles must not mutate archetype or species definitions")

local invalidArchetype = { TEST = { archetype = "missing" } }
assert(not pcall(SpeciesEcology.validateDefinitions, EcologyArchetypes, invalidArchetype),
	"unknown archetypes must fail definition validation")
local invalidField = { TEST = { archetype = "solitary", appetite = 2 } }
assert(not pcall(SpeciesEcology.validateDefinitions, EcologyArchetypes, invalidField),
	"unknown profile fields must fail definition validation")
local invalidEnum = { TEST = { archetype = "solitary", habitat = { "MOON" } } }
assert(not pcall(SpeciesEcology.validateDefinitions, EcologyArchetypes, invalidEnum),
	"unknown ecology enums must fail definition validation")
local invalidNested = { TEST = { archetype = "solitary", social = { loyalty = 1 } } }
assert(not pcall(SpeciesEcology.validateDefinitions, EcologyArchetypes, invalidNested),
	"unknown nested fields must fail definition validation")
local missingArchetype = { TEST = { movement = { wanderScale = 1 } } }
assert(not pcall(SpeciesEcology.validateDefinitions, EcologyArchetypes, missingArchetype),
	"every species profile must explicitly select an archetype")
local malformedOverride = { TEST = {
	archetype = "solitary", movement = { wanderScale = 9 }
} }
assert(not pcall(SpeciesEcology.validateDefinitions, EcologyArchetypes, malformedOverride),
	"invalid composed override ranges must fail definition validation")
local invalidFood = { TEST = { archetype = "solitary",
	feeding = { acceptedOpportunityTypes = { "BERRIES" } } } }
assert(not pcall(SpeciesEcology.validateDefinitions, EcologyArchetypes, invalidFood),
	"unknown food opportunity types must fail definition validation")
local malformedFood = { TEST = { archetype = "solitary",
	feeding = { acceptedOpportunityTypes = { [2] = "TALL_GRASS_FORAGE" } } } }
assert(not pcall(SpeciesEcology.validateDefinitions, EcologyArchetypes, malformedFood),
	"feeding opportunity types must be a dense array")

local caterpie = SpeciesEcology.resolve("CATERPIE")
local zubat = SpeciesEcology.resolve("ZUBAT")
local geodude = SpeciesEcology.resolve("GEODUDE")
local goldeen = SpeciesEcology.resolve("GOLDEEN")
local abra = SpeciesEcology.resolve("ABRA")
local magnemite = SpeciesEcology.resolve("MAGNEMITE")
assert(caterpie.movement.wanderScale < zubat.movement.wanderScale,
	"sheltered grazers and cave flyers should have distinct movement baselines")
assert(geodude.physiology.thirstRate < pidgeyAgain.physiology.thirstRate,
	"rocky species should have a distinct physiology baseline")
assert(goldeen.biologicalCapabilities.SWIM
	and goldeen.biologicalCapabilities.WALK == false,
	"aquatic profiles should declare biology without claiming execution")
assert(abra.biologicalCapabilities.TELEPORT
	and magnemite.activityProfile == "WEAK_CIRCADIAN",
	"special biology and weak circadian activity should remain declarative")
assert(pidgeyAgain.feeding.acceptedOpportunityTypes[1] == "TALL_GRASS_FORAGE"
	and caterpie.feeding.acceptedOpportunityTypes[1] == "TALL_GRASS_FORAGE",
	"eligible species should explicitly accept abstract tall-grass forage")
assert(#goldeen.feeding.acceptedOpportunityTypes == 0
	and #magnemite.feeding.acceptedOpportunityTypes == 0,
	"unsupported species must not receive terrestrial food compatibility")

local aquaticEntity = { species = "GOLDEEN", ecology = {}, relationships = {} }
local traversal = TraversalCapabilities.declarationsForEntity(aquaticEntity)
assert(traversal.biological.SWIM and not traversal.learned.SWIM,
	"biological and learned traversal declarations must remain separate")
assert(traversal.executable.WALK and not traversal.executable.SWIM,
	"declared SWIM must not create an executable traversal mode")

local zubatEntity = { id = "zubat", species = "ZUBAT", personalitySeed = 10,
	relationships = {} }
local noon = CircadianSystem.evaluate(zubatEntity, 0.5)
local midnight = CircadianSystem.evaluate(zubatEntity, 0)
assert(midnight.activityBias > noon.activityBias,
	"species activity profiles must flow through CircadianSystem")

local socialEntity = Entity.newWildPokemon({ id = "social", species = "ZUBAT",
	level = 5, personalitySeed = 44 })
assert(next(socialEntity.relationships) == nil,
	"a social species baseline must not allocate relationships automatically")

local dormantEntity = Entity.newWildPokemon({ id = "dormant", species = "GEODUDE",
	level = 5, personalitySeed = 45 })
dormantEntity.drives = { THIRST = { value = 0, lastUpdatedTick = 0 } }
local physiology = EcologyPhysiology.forEntity(dormantEntity)
local cohort = { mapId = "test", memberIds = { dormantEntity.id },
	memberSnapshots = {}, lastEcologyTime = 0, environment = {} }
DormantCohortSimulator.advance(cohort, { [dormantEntity.id] = dormantEntity }, 3600)
local expectedThirst = 0.08 * physiology.thirstRate
assert(math.abs(dormantEntity.drives.THIRST.value - expectedThirst) < 0.000001,
	"dormant drive updates must use the same resolved physiology as live behavior")

for _, species in ipairs({ "PIDGEY", "RATTATA", "SPEAROW", "CATERPIE",
	"ZUBAT", "GEODUDE", "ONIX", "GOLDEEN", "MAGIKARP", "ABRA", "MAGNEMITE" }) do
	assert(SpeciesEcology.validate(SpeciesEcology.resolve(species)),
		"representative species must resolve to valid ecology: " .. species)
end

return true