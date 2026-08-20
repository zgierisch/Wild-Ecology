local Entity = {}

function Entity.newWildPokemon(params)
  return {
    id = params.id,
    kind = "pokemon",
    species = params.species,
    level = params.level,
    personalitySeed = params.personalitySeed or 1,
    temperament = params.temperament or {
      boldness = 0.3,
      sociability = 0.5,
      curiosity = 0.5,
      aggression = 0.1,
      protectiveness = 0.2
    },
    home = params.home or {
      mapId = "ROUTE_1",
      zoneId = "default"
    },
    relationships = params.relationships or {},
    memory = params.memory or {},
    groupId = params.groupId
  }
end

return Entity
