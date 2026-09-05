local PokemonMechanics = require("src.adapters.pokemon_mechanics")
local EcologicalPhenotype = require("src.mechanics.ecological_phenotype")
local SpeciesEcology = require("src.species.species_ecology")

local EcologyPhysiology = {}

function EcologyPhysiology.forEntity(entity)
	local signature = PokemonMechanics.signature(entity)
	local phenotype = EcologicalPhenotype.forEntity(entity,
		PokemonMechanics.snapshot(entity), signature)
	local profile = SpeciesEcology.getResolved(entity and entity.species)
	return {
		profile = profile,
		phenotype = phenotype,
		thirstRate = profile.physiology.thirstRate,
		hungerRate = profile.physiology.hungerRate,
		fatigueRate = profile.physiology.fatigueRate
			* (1.15 - phenotype.endurance * 0.3),
		restRecovery = profile.physiology.restRecovery
			* (0.85 + phenotype.recoveryCapacity * 0.3),
		wanderScale = profile.movement.wanderScale * phenotype.movementScale
	}
end

return EcologyPhysiology