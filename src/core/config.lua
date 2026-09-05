local Config = {}

-- Semantic map classifications and exceptional transition overrides belong here.
-- Transition geometry comes from engine topology, never map ids or generic "+" cells.
Config.worldSemantics = {}

-- Wild Ecology-owned enablement and stable identity only. Map dimensions,
-- connections, traversal, and spawn geometry remain engine-derived.
Config.ecologyMaps = {
  ROUTE_1 = { kind = "ROUTE", populationKey = "route01" },
  ROUTE_2 = { kind = "ROUTE", populationKey = "route02" },
  ROUTE_3 = { kind = "ROUTE", populationKey = "route03" },
  ROUTE_4 = { kind = "ROUTE", populationKey = "route04" },
  ROUTE_5 = { kind = "ROUTE", populationKey = "route05" },
  ROUTE_6 = { kind = "ROUTE", populationKey = "route06" },
  ROUTE_7 = { kind = "ROUTE", populationKey = "route07" },
  ROUTE_8 = { kind = "ROUTE", populationKey = "route08" },
  ROUTE_9 = { kind = "ROUTE", populationKey = "route09" },
  ROUTE_10 = { kind = "ROUTE", populationKey = "route10" },
  ROUTE_11 = { kind = "ROUTE", populationKey = "route11" },
  ROUTE_12 = { kind = "ROUTE", populationKey = "route12" },
  ROUTE_13 = { kind = "ROUTE", populationKey = "route13" },
  ROUTE_14 = { kind = "ROUTE", populationKey = "route14" },
  ROUTE_15 = { kind = "ROUTE", populationKey = "route15" },
  ROUTE_16 = { kind = "ROUTE", populationKey = "route16" },
  ROUTE_22 = { kind = "ROUTE", populationKey = "route22" },
  ROUTE_24 = { kind = "ROUTE", populationKey = "route24" },
  ROUTE_25 = { kind = "ROUTE", populationKey = "route25" }
}

function Config.normalizeMapId(value)
  if value == nil then
    return nil
  end

  local mapId = tostring(value):upper():gsub("%s+", "_")
  mapId = mapId:gsub("^ROUTE0+([0-9]+)$", "ROUTE_%1")
  mapId = mapId:gsub("^ROUTE([0-9]+)$", "ROUTE_%1")
  if mapId:match("^%d+$") then
    mapId = "ROUTE_" .. tostring(tonumber(mapId))
  end
  return mapId
end

function Config.ecologyMap(mapId)
  return Config.ecologyMaps[Config.normalizeMapId(mapId)]
end

function Config.isEcologyEnabled(mapId)
  return Config.ecologyMap(mapId) ~= nil
end

Config.phase0 = {
  testMapId = "ROUTE_1",
  testEntityId = "wild:route01:0001",
  testSpecies = "PIDGEY",
  testLevel = 4,
  testPersonalitySeed = 847219,
  testZoneId = "south_grass",
  defaultRelationshipTrust = 10,
  calmProximityCooldownTicks = 90,
  warmupPerVisitCap = 2,

  -- Optional in-game verification knobs for Phase 0. Keep nil for normal behavior.
  debugForceTrust = nil,
  debugForceThreatMemory = nil,
  debugForceHostility = nil
}

Config.phase3 = {
  routePopulationSize = 30,
  visibleSubsetSize = 15,
  sameSpeciesFamilySpawnWeight = 3,
  unrelatedSpawnWeight = 1,
  routeSpawnCells = {
    south_grass = {
      { x = 6, y = 8 },
      { x = 7, y = 8 },
      { x = 6, y = 9 },
      { x = 7, y = 9 },
      { x = 8, y = 8 },
      { x = 8, y = 9 }
    },
    north_grass = {
      { x = 8, y = 4 },
      { x = 9, y = 4 },
      { x = 8, y = 5 },
      { x = 9, y = 5 },
      { x = 10, y = 4 },
      { x = 10, y = 5 }
    },
    east_grass = {
      { x = 11, y = 7 },
      { x = 12, y = 7 },
      { x = 11, y = 8 },
      { x = 12, y = 8 },
      { x = 13, y = 7 },
      { x = 13, y = 8 }
    },
    west_grass = {
      { x = 3, y = 7 },
      { x = 4, y = 7 },
      { x = 3, y = 8 },
      { x = 4, y = 8 },
      { x = 5, y = 7 },
      { x = 5, y = 8 }
    },
    center_grass = {
      { x = 7, y = 6 },
      { x = 8, y = 6 },
      { x = 7, y = 7 },
      { x = 8, y = 7 },
      { x = 9, y = 6 },
      { x = 9, y = 7 }
    },
    default = {
      { x = 6, y = 6 },
      { x = 8, y = 6 },
      { x = 10, y = 6 },
      { x = 6, y = 8 },
      { x = 8, y = 8 }
    }
  },
  -- Weighted species pool: each entry's species/level are rolled per
  -- individual (seeded by personalitySeed), same generation mechanics as
  -- rawStats/family, instead of picking from a fixed per-slot list.
  speciesPool = {
    { species = "PIDGEY", weight = 3, levelRange = { min = 4, max = 5 } },
    { species = "RATTATA", weight = 2, levelRange = { min = 3, max = 4 } }
  },
  zoneOrder = { "south_grass", "north_grass", "east_grass", "west_grass", "center_grass" }
}

Config.relationships = {
  familiarityDecayPerDay = 0,
  trustDecayPerDay = 0,
  contactSeparationTicks = 30,
  contactExposureIntervalTicks = 100
}

Config.ecologyClock = {
  defaultRealTime = false,
  defaultSimulationDayDuration = "1h",
  simulationDayDurations = {
    ["30m"] = 30 * 60,
    ["1h"] = 60 * 60,
    ["6h"] = 6 * 60 * 60,
    ["24h"] = 24 * 60 * 60
  },
  ticksPerSecond = 60,
  forwardJumpThresholdSeconds = 5 * 60,
  closedSimulationPolicy = "FREEZE"
}

Config.relationshipAudit = {
  defaultEnabled = false,
  maxBytes = 196 * 1024,
  flushIntervalTicks = 30,
  storageKey = "relationship_audit"
}

Config.agentAudit = {
  defaultEnabled = false,
  maxBytes = 196 * 1024,
  flushIntervalTicks = 30,
  separationTicks = 30,
  contactSampleTicks = 100,
  historySamples = 45,
  postSamples = 25,
  periodicTicks = 300,
  storageKey = "agent_audit"
}

Config.phase2 = {
  -- Trust/affinity gating for who counts as a real associate now lives in
  -- Social.shouldFollowAssociate (single source of truth); no fixed demo
  -- associate id or forced trust floor anymore -- see
  -- PopulationManager.propagateAssociateSocialSignal.
  socialFearSignal = 1,
  socialFearCooldownTicks = 45,
  socialReassuranceSignal = 1,
  socialReassuranceCooldownTicks = 45
}

return Config
