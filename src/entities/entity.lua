local BaseRanges = require("src.species.base_ranges")
local SpeciesEcology = require("src.species.species_ecology")
local Drives = require("src.needs.drives")
local CircadianSystem = require("src.circadian.circadian_system")

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

-- The game runtime is LuaJIT (Lua 5.1 semantics): no native bitwise
-- operators (`~`, `>>`) and numbers are doubles with only ~2^53 of exact
-- integer precision, so every intermediate product below must stay well
-- under that. MIX_MODULUS is a power of two comparable in size to the two
-- odd multipliers, which is what makes a tiny `seed` step (generator.lua's
-- personalitySeed = base + serial*13) produce a LARGE, well-scattered
-- change in the output instead of the previous single small-step LCG,
-- which drifted slowly and got stuck on one side of a threshold for dozens
-- of consecutive calls (real bug: every generated Pidgey landing in the
-- same family/species-pool bucket in a row).
local MIX_MODULUS = 67108864 -- 2^26

local function seededUnitInterval(seed, salt)
  local reduced = (seed or 0) % MIX_MODULUS
  local combined = (reduced * 40503199 + (salt or 0) * 40503) % MIX_MODULUS
  local mixed = (combined * 26146329 + 12345) % MIX_MODULUS
  return mixed / (MIX_MODULUS - 1)
end

local function sampleRange(range, seed, salt)
  range = range or {}
  local minV = range.min or 0
  local maxV = range.max or 1
  return minV + seededUnitInterval(seed, salt) * (maxV - minV)
end

-- The raw generated stat block for one individual, sampled within its
-- species' base ranges. This is what actually varies per generated entity;
-- named temperament fields below are derived from it.
function Entity.generateRawStats(species, personalitySeed)
  local base = BaseRanges.get(species)
  local stats = base.stats or {}
  local seed = personalitySeed or 1

  return {
    curiosity = sampleRange(stats.curiosity, seed, 11),
    timidity = sampleRange(stats.timidity, seed, 12),
    aggression = sampleRange(stats.aggression, seed, 13),
    social = sampleRange(stats.social, seed, 14),
    active = sampleRange(stats.active, seed, 15),
    independence = sampleRange(stats.independence, seed, 16)
  }
end

-- Existing behavior-scoring code (utility.lua/controller.lua) reads these
-- named fields; keep them derived from rawStats instead of renaming callers.
function Entity.deriveTemperament(rawStats)
  rawStats = rawStats or {}
  local social = rawStats.social or 0.5
  local independence = rawStats.independence or 0.5

  return {
    boldness = clamp(1 - (rawStats.timidity or 0.5), 0, 1),
    sociability = clamp(social, 0, 1),
    curiosity = clamp(rawStats.curiosity or 0.5, 0, 1),
    aggression = clamp(rawStats.aggression or 0.1, 0, 1),
    protectiveness = clamp(social * 0.5 + (1 - independence) * 0.5, 0, 1)
  }
end

function Entity.generateTemperament(species, personalitySeed)
  return Entity.deriveTemperament(Entity.generateRawStats(species, personalitySeed))
end

-- Family/kin-group is assigned per individual (not fixed per species) so
-- two same-species individuals can belong to different family groups.
function Entity.assignFamily(species, personalitySeed)
  local base = BaseRanges.get(species)
  local pool = base.familyPool or { "A" }
  local seed = personalitySeed or 1
  local index = math.floor(seededUnitInterval(seed, 97) * #pool) + 1
  if index > #pool then
    index = #pool
  end
  return pool[index]
end

function Entity.getSpeciesEcology(species, personalitySeed)
  local profile = SpeciesEcology.resolve(species)
  return {
    activityProfile = profile.activityProfile,
    family = Entity.assignFamily(species, personalitySeed)
  }
end

function Entity.newWildPokemon(params)
  local personalitySeed = params.personalitySeed or 1
  local rawStats = params.rawStats or Entity.generateRawStats(params.species, personalitySeed)
  local ecology = params.ecology or Entity.getSpeciesEcology(params.species, personalitySeed)

  local entity = {
    id = params.id,
    kind = "pokemon",
    species = params.species,
    level = params.level,
    encounteredLevel = params.encounteredLevel or params.level,
    firstEncounteredTick = params.firstEncounteredTick,
    personalitySeed = personalitySeed,
    mechanics = params.mechanics,
    ecology = ecology,
    rawStats = rawStats,
    temperament = params.temperament or Entity.deriveTemperament(rawStats),
    home = params.home or { zoneId = "default" },
    relationships = params.relationships or {},
    memory = params.memory or {},
    groupId = params.groupId
  }
  Drives.ensure(entity, params.firstEncounteredTick or 0)
  CircadianSystem.ensure(entity, ecology.activityProfile
    or SpeciesEcology.resolve(params.species).activityProfile)
  return entity
end

return Entity
