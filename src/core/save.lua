local Drives = require("src.needs.drives")
local CircadianSystem = require("src.circadian.circadian_system")

local Save = {
  cache = nil,
  persistenceAdapter = nil,
  loadStatus = "not_initialized",
  persistenceWritable = false,
  namespace = "wild_ecology"
}

local CURRENT_SCHEMA_VERSION = 8

local DEFAULT_STATE = {
  schemaVersion = CURRENT_SCHEMA_VERSION,
  nextEntitySerial = 1,
  simulationTick = 0,
  ecologyClock = {
    mode = "SIMULATION",
    previousMode = "SIMULATION",
    simulationEcologyTime = 43200,
    lastSimulationTick = 0,
    sourceTick = 0,
    lastObservedByMode = {}
  },
  dormantCohorts = {},
  populations = {},
  debug = {
    devLog = {
      nextSequence = 1,
      entries = {}
    },
    phase0 = {
      lastEvent = nil,
      lastEntityId = nil,
      lastSpawnAvatarId = nil,
      lastDespawnAvatarId = nil,
      lastRespawnCount = 0,
      lastState = nil,
      lastTrust = 0,
      lastThreatMemory = 0,
      lastMapId = nil,
      lastContextMapId = nil,
      lastBehaviorMode = "normal",
      lastIntent = nil,
      lastTargetEntityId = nil,
      lastBehaviorScores = nil,
      lastMovementApi = nil,
      lastMovementRequest = nil,
      lastMotionActive = false,
      lastPhase5Diagnostic = nil,
      lastFleeRadius = nil,
      lastPlayerDistance = nil
    }
  }
}

local function deepCopy(tbl)
  local copy = {}
  for k, v in pairs(tbl) do
    if type(v) == "table" then
      copy[k] = deepCopy(v)
    else
      copy[k] = v
    end
  end
  return copy
end

local function stripPopulationRuntimeState(state)
  for _, population in pairs(state and state.populations or {}) do
    for _, entity in pairs(population.members or {}) do
      entity.runtimeState = nil
    end
  end
  return state
end

local function stripResolvedSpeciesEcology(entity)
  local ecology = entity and entity.ecology
  if not ecology then return end
  for _, key in ipairs({ "archetype", "socialModifier", "familySocialModifier",
    "desiredGroupSize", "alarmBroadcastStrength",
    "conspecificAlarmSensitivity", "heterospecificAlarmSensitivity",
    "locomotion", "physiology", "feeding", "movement", "habitat", "restSites",
    "concealmentSites", "home" }) do
    ecology[key] = nil
  end
end

local function persistentSnapshot(state)
  local snapshot = stripPopulationRuntimeState(deepCopy(state))
  for _, population in pairs(snapshot.populations or {}) do
    for _, entity in pairs(population.members or {}) do
      stripResolvedSpeciesEcology(entity)
    end
  end
  return snapshot
end

local normalizeHomeArea

local function ensureStateShape(state)
  if state.schemaVersion == nil then
    state.schemaVersion = CURRENT_SCHEMA_VERSION
  end
  if state.nextEntitySerial == nil then
    state.nextEntitySerial = 1
  end
  if state.simulationTick == nil then
    state.simulationTick = 0
  end
  if state.populations == nil then
    state.populations = {}
  end
  state.ecologyClock = state.ecologyClock or {
    mode = "SIMULATION", previousMode = "SIMULATION",
    simulationEcologyTime = 43200, lastSimulationTick = state.simulationTick or 0,
    sourceTick = 0, lastObservedByMode = {}
  }
  state.ecologyClock.sourceTick = state.ecologyClock.sourceTick or 0
  state.ecologyClock.lastObservedByMode = state.ecologyClock.lastObservedByMode or {}
  state.dormantCohorts = state.dormantCohorts or {}
  for _, population in pairs(state.populations) do
    for _, entity in pairs(population.members or {}) do
      stripResolvedSpeciesEcology(entity)
      normalizeHomeArea(entity)
      Drives.ensure(entity, state.simulationTick)
      CircadianSystem.ensure(entity,
        entity.ecology and entity.ecology.activityProfile or "FLEXIBLE")
    end
  end
  if state.debug == nil then
    state.debug = {}
  end
  if state.debug.devLog == nil then
    state.debug.devLog = {
      nextSequence = 1,
      entries = {}
    }
  end
  state.debug.devLog.nextSequence = state.debug.devLog.nextSequence or 1
  state.debug.devLog.entries = state.debug.devLog.entries or {}
  if state.debug.phase0 == nil then
    state.debug.phase0 = {
      lastEvent = nil,
      lastEntityId = nil,
      lastSpawnAvatarId = nil,
      lastDespawnAvatarId = nil,
      lastRespawnCount = 0,
      lastState = nil,
      lastTrust = 0,
      lastThreatMemory = 0,
      lastMapId = nil,
      lastContextMapId = nil,
      lastBehaviorMode = "normal",
      lastIntent = nil,
      lastTargetEntityId = nil,
      lastBehaviorScores = nil,
      lastMovementApi = nil,
      lastMovementRequest = nil,
      lastMotionActive = false,
      lastPhase5Diagnostic = nil,
      lastFleeRadius = nil,
      lastPlayerDistance = nil
    }
  end

  if state.debug.phase0.lastContextMapId == nil then
    state.debug.phase0.lastContextMapId = nil
  end
  if state.debug.phase0.lastBehaviorMode == nil then
    state.debug.phase0.lastBehaviorMode = "normal"
  end
  if state.debug.phase0.lastIntent == nil then
    state.debug.phase0.lastIntent = nil
  end
  if state.debug.phase0.lastTargetEntityId == nil then
    state.debug.phase0.lastTargetEntityId = nil
  end
  if state.debug.phase0.lastBehaviorScores == nil then
    state.debug.phase0.lastBehaviorScores = nil
  end
  if state.debug.phase0.lastMovementApi == nil then
    state.debug.phase0.lastMovementApi = nil
  end
  if state.debug.phase0.lastMovementRequest == nil then
    state.debug.phase0.lastMovementRequest = nil
  end
  if state.debug.phase0.lastMotionActive == nil then
    state.debug.phase0.lastMotionActive = false
  end
  if state.debug.phase0.lastPhase5Diagnostic == nil then
    state.debug.phase0.lastPhase5Diagnostic = nil
  end
  if state.debug.phase0.lastFleeRadius == nil then
    state.debug.phase0.lastFleeRadius = nil
  end
  if state.debug.phase0.lastPlayerDistance == nil then
    state.debug.phase0.lastPlayerDistance = nil
  end

  return state
end

normalizeHomeArea = function(entity)
  local area = entity and entity.home and entity.home.area
  if area == nil then return end
  local anchor = area.anchorCell
  if type(area.mapId) ~= "string" or area.mapId == ""
    or type(anchor) ~= "table"
    or type(anchor.cellX) ~= "number" or type(anchor.cellY) ~= "number"
    or type(area.radius) ~= "number" then
    entity.home.area = nil
    return
  end
  area.radius = math.max(1, math.min(5, math.floor(area.radius)))
  area.establishedTick = tonumber(area.establishedTick) or 0
  area.provenance = type(area.provenance) == "string"
    and area.provenance or "LEGACY_VALIDATED"
end

local function migrateState(state)
  if state == nil then
    return deepCopy(DEFAULT_STATE)
  end

  stripPopulationRuntimeState(state)

  if (state.schemaVersion or 1) < 2 then
    for _, population in pairs(state.populations or {}) do
      for _, entity in pairs(population.members or {}) do
        for _, relationship in pairs(entity.relationships or {}) do
          relationship.directThreatMemory = relationship.directThreatMemory or 0
        end
      end
    end
    state.schemaVersion = 2
  end
  if (state.schemaVersion or 1) < 3 then
    for _, population in pairs(state.populations or {}) do
      for _, entity in pairs(population.members or {}) do
        Drives.ensure(entity, state.simulationTick or 0)
      end
    end
    state.schemaVersion = 3
  end
  if (state.schemaVersion or 1) < 4 then
    state.ecologyClock = state.ecologyClock or {
      mode = "SIMULATION", previousMode = "SIMULATION",
      simulationEcologyTime = 43200,
      lastSimulationTick = state.simulationTick or 0,
      sourceTick = 0, lastObservedByMode = {}
    }
    state.dormantCohorts = state.dormantCohorts or {}
    for _, population in pairs(state.populations or {}) do
      for _, entity in pairs(population.members or {}) do
        CircadianSystem.ensure(entity,
          entity.ecology and entity.ecology.activityProfile or "FLEXIBLE")
      end
    end
    state.schemaVersion = 4
  end
  if (state.schemaVersion or 1) < 5 then
    for _, population in pairs(state.populations or {}) do
      for _, entity in pairs(population.members or {}) do
        stripResolvedSpeciesEcology(entity)
      end
    end
    state.schemaVersion = 5
  end
  if (state.schemaVersion or 1) < 6 then
    for _, population in pairs(state.populations or {}) do
      for _, entity in pairs(population.members or {}) do
        Drives.ensureOne(entity, "HUNGER", state.simulationTick or 0)
      end
    end
    state.schemaVersion = 6
  end
  if (state.schemaVersion or 1) < 7 then
    for _, population in pairs(state.populations or {}) do
      for _, entity in pairs(population.members or {}) do
        if entity.locationState ~= nil
          and entity.locationState.kind ~= "CONCEALED" then
          entity.locationState = nil
        end
      end
    end
    state.schemaVersion = 7
  end
  if (state.schemaVersion or 1) < 8 then
    for _, population in pairs(state.populations or {}) do
      for _, entity in pairs(population.members or {}) do
        normalizeHomeArea(entity)
      end
    end
    state.schemaVersion = 8
  end
  return ensureStateShape(state)
end

function Save.init(persistenceAdapter)
  Save.persistenceAdapter = persistenceAdapter
  Save.loadStatus = "not_found"
  Save.persistenceWritable = persistenceAdapter ~= nil
  local savedState = nil
  if persistenceAdapter then
    local ok, loadedState, loadStatus = pcall(function()
      return persistenceAdapter.load(Save.namespace)
    end)
    if not ok then
      Save.loadStatus = "error"
      Save.persistenceWritable = false
    elseif loadStatus == "error" then
      Save.loadStatus = "error"
      Save.persistenceWritable = false
    elseif loadedState == nil then
      Save.loadStatus = "not_found"
    elseif type(loadedState) ~= "table" then
      Save.loadStatus = "malformed"
      Save.persistenceWritable = false
    else
      savedState = loadedState
      Save.loadStatus = "ok"
    end
  end
  Save.cache = migrateState(savedState)
end

function Save.getState()
  return Save.cache
end

function Save.getPhase0Debug()
  local state = Save.getState()
  return state and state.debug and state.debug.phase0 or nil
end

function Save.getDevLog()
  local state = Save.getState()
  return state and state.debug and state.debug.devLog or nil
end

function Save.flush()
  if not Save.persistenceAdapter or not Save.cache or not Save.persistenceWritable then
    return false
  end
  return Save.persistenceAdapter.save(Save.namespace, persistentSnapshot(Save.cache))
end

function Save.nextTick()
  local state = Save.getState()
  if state == nil then
    state = deepCopy(DEFAULT_STATE)
    Save.cache = state
  end
  if state.simulationTick == nil then
    state.simulationTick = 0
  end
  state.simulationTick = state.simulationTick + 1
  return state.simulationTick
end

return Save
