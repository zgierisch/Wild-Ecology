local Entity = require("src.entities.entity")
local Environment = require("src.world.environment")
local Save = require("src.core.save")
local DebugLogger = require("src.debug.logger")

local Generator = {}

-- Shared with main.lua's LOG_SCREEN_ITEMS entry so the toggle key stays in
-- sync. Read from mod.save (the nested LOG SETTINGS screen's backing store),
-- not mod.options -- there is no documented way for mod code to write an
-- option value itself, only the flat mod-options menu can.
Generator.GENERATION_LOG_OPTION_KEY = "dev_log_generation"

local function generationLogEnabled(mod)
  local save = mod and mod.save
  if save and save.get then
    local ok, value = pcall(function()
      return save:get(Generator.GENERATION_LOG_OPTION_KEY, false)
    end)
    if ok then
      return value == true
    end
  end
  return false
end

local function logGeneration(mod, message)
  if not generationLogEnabled(mod) then
    return
  end
  DebugLogger.log("generation", message)
end

local function makeEntityId(routeKey, serial)
  if routeKey == nil then
    error("routeKey is required for persistent wild entity identity")
  end
  return string.format("wild:%s:%04d", tostring(routeKey), tonumber(serial) or 1)
end

local function currentSimulationTick()
  local ok, state = pcall(Save.getState)
  if ok and state and state.simulationTick then
    return state.simulationTick
  end
  return 0
end

-- See src/entities/entity.lua's seededUnitInterval comment: the game
-- runtime is LuaJIT, so no bitwise operators and doubles-only precision.
-- This modular-multiplication mix (odd constants comparable in size to
-- MIX_MODULUS) fixes the same drift bug for the +13-per-entity
-- personalitySeed step.
local MIX_MODULUS = 67108864 -- 2^26

local function seededUnit(seed, salt)
  local reduced = (seed or 0) % MIX_MODULUS
  local combined = (reduced * 40503199 + (salt or 0) * 40503) % MIX_MODULUS
  local mixed = (combined * 26146329 + 12345) % MIX_MODULUS
  return mixed / (MIX_MODULUS - 1)
end

-- Weighted, seeded pick from the configured species pool (Config.phase3.
-- speciesPool) -- replaces picking a fixed per-slot spec out of a literal
-- template array.
local function rollSpeciesPoolEntry(speciesPool, seed)
  local pool = speciesPool or {}
  if #pool == 0 then
    return { species = "PIDGEY", levelRange = { min = 4, max = 4 } }
  end

  local totalWeight = 0
  for _, entry in ipairs(pool) do
    totalWeight = totalWeight + (entry.weight or 1)
  end
  if totalWeight <= 0 then
    return pool[1]
  end

  local threshold = seededUnit(seed, 31) * totalWeight
  local cumulative = 0
  for _, entry in ipairs(pool) do
    cumulative = cumulative + (entry.weight or 1)
    if threshold <= cumulative then
      return entry
    end
  end
  return pool[#pool]
end

local function rollLevelInRange(range, seed)
  local minLevel = (range and range.min) or 4
  local maxLevel = (range and range.max) or minLevel
  if maxLevel <= minLevel then
    return minLevel
  end
  return minLevel + math.floor(seededUnit(seed, 37) * (maxLevel - minLevel + 1))
end

local function zoneForIndex(zoneOrder, index)
  local zones = zoneOrder or { "default" }
  if #zones == 0 then
    return "default"
  end
  return zones[((index - 1) % #zones) + 1]
end

-- What would spawn absent real game encounter data: species/level rolled
-- from the configured species pool (weighted, seeded by personalitySeed),
-- zone cycled from the configured zone order. Same generation mechanics
-- (seeded rolls over a range/pool) as rawStats/family in entities/entity.lua,
-- instead of a fixed per-slot template.
local function buildPoolFallbackSpec(poolConfig, index, personalitySeed)
  poolConfig = poolConfig or {}
  local poolEntry = rollSpeciesPoolEntry(poolConfig.speciesPool, personalitySeed)
  return {
    species = poolEntry.species or "PIDGEY",
    level = rollLevelInRange(poolEntry.levelRange, personalitySeed),
    zoneId = zoneForIndex(poolConfig.zoneOrder, index)
  }
end

-- Prefers real game encounter data (mod.content.encounters, via
-- Environment.getWildEncounterTable) over the species-pool fallback; falls
-- back to the pool when `mod` is nil (headless tests) or the map has no
-- grass table. zoneId stays ours -- the registry has no zone concept.
local function resolveEncounterSpec(mapId, fallbackSpec, mod)
  local rolled = Environment.getWildEncounterTable and Environment.getWildEncounterTable(mod, mapId)
  if rolled and rolled.species then
    logGeneration(mod, string.format("encounter-table HIT map=%s species=%s level=%s (species-pool bypassed)", tostring(mapId), tostring(rolled.species), tostring(rolled.level)))
    return {
      species = rolled.species,
      level = rolled.level,
      zoneId = fallbackSpec.zoneId
    }
  end
  logGeneration(mod, string.format("encounter-table MISS map=%s -- falling back to species pool", tostring(mapId)))
  return fallbackSpec
end

-- The Phase 0 anchor is deterministic (stable id/seed for tests/debug) but
-- its species/level/seed are now config-driven inputs into the same
-- Entity.newWildPokemon generation path as every other individual, instead
-- of literals baked into this function.
function Generator.makePhase0Pidgey(id, config)
  config = config or {}
  local anchor = Entity.newWildPokemon({
    id = id,
    species = config.species or "PIDGEY",
    level = config.level or 4,
    personalitySeed = config.personalitySeed or 847219,
    firstEncounteredTick = currentSimulationTick(),
    home = {
      mapId = config.mapId or "ROUTE_1",
      zoneId = config.zoneId or "south_grass"
    }
  })
  logGeneration(config.mod, string.format("anchor spawned id=%s species=%s level=%s family=%s seed=%s zone=%s", tostring(anchor.id), tostring(anchor.species), tostring(anchor.level), tostring(anchor.ecology and anchor.ecology.family), tostring(anchor.personalitySeed), tostring(anchor.home.zoneId)))
  return anchor
end

-- Generates `count` new individuals starting at `startingSerial`, continuing
-- the zone cycle from `startIndex` (the route population's current size)
-- so incremental growth lines up with a single big batch.
function Generator.makeRoutePopulation(mapId, routeKey, poolConfig, count, startingSerial, mod, startIndex)
  if mapId == nil then
    error("mapId is required for route population generation")
  end
  local population = {
    members = {},
    order = {}
  }

  local total = count or 0
  local nextSerial = startingSerial or 1
  local baseIndex = startIndex or 0
  if total <= 0 then
    return population, nextSerial
  end

  for i = 1, total do
    local personalitySeed = 847219 + nextSerial * 13
    local fallbackSpec = buildPoolFallbackSpec(poolConfig, baseIndex + i, personalitySeed)
    local spec = resolveEncounterSpec(mapId, fallbackSpec, mod)
    local entityId = makeEntityId(routeKey, nextSerial)
    local entity = Entity.newWildPokemon({
      id = entityId,
      species = spec.species or "PIDGEY",
      level = spec.level or 4,
      personalitySeed = personalitySeed,
      firstEncounteredTick = currentSimulationTick(),
      home = {
        mapId = mapId,
        zoneId = spec.zoneId or "default"
      }
    })

    population.members[entity.id] = entity
    population.order[#population.order + 1] = entity.id
    nextSerial = nextSerial + 1
    logGeneration(mod, string.format("generated id=%s species=%s level=%s family=%s zone=%s seed=%s", tostring(entity.id), tostring(entity.species), tostring(entity.level), tostring(entity.ecology and entity.ecology.family), tostring(entity.home.zoneId), tostring(entity.personalitySeed)))
  end

  return population, nextSerial
end

return Generator
