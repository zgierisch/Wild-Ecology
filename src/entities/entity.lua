local Entity = {}

local function clamp(value, minV, maxV)
  if value < minV then
    return minV
  end
  if value > maxV then
    return maxV
  end
  return value
end

local function seededUnitInterval(seed, salt)
  local x = (seed + salt * 1013904223) % 4294967296
  x = (1664525 * x + 1013904223) % 4294967296
  return x / 4294967295
end

function Entity.getSpeciesTemperamentDefaults(species)
  if species == "PIDGEY" then
    return {
      boldness = 0.30,
      sociability = 0.75,
      curiosity = 0.40,
      aggression = 0.10,
      protectiveness = 0.25
    }
  end

  return {
    boldness = 0.30,
    sociability = 0.50,
    curiosity = 0.50,
    aggression = 0.10,
    protectiveness = 0.20
  }
end

local function varyTrait(baseValue, seed, salt)
  local spread = 0.80 + seededUnitInterval(seed, salt) * 0.40
  return clamp(baseValue * spread, 0, 1)
end

function Entity.generateTemperament(species, personalitySeed)
  local defaults = Entity.getSpeciesTemperamentDefaults(species)
  local seed = personalitySeed or 1

  return {
    boldness = varyTrait(defaults.boldness, seed, 1),
    sociability = varyTrait(defaults.sociability, seed, 2),
    curiosity = varyTrait(defaults.curiosity, seed, 3),
    aggression = varyTrait(defaults.aggression, seed, 4),
    protectiveness = varyTrait(defaults.protectiveness, seed, 5)
  }
end

function Entity.newWildPokemon(params)
  local personalitySeed = params.personalitySeed or 1

  return {
    id = params.id,
    kind = "pokemon",
    species = params.species,
    level = params.level,
    personalitySeed = personalitySeed,
    temperament = params.temperament or Entity.generateTemperament(params.species, personalitySeed),
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
