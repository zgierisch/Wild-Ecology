local Config = nil
local Save = nil
local Gen1PersistenceAdapter = nil
local PopulationManager = nil
local AvatarFactory = nil
local RuntimeAvatarAdapter = nil
local Controller = nil
local DebugLogger = nil
local TelemetryPolicy = nil
local RelationshipAudit = nil
local AgentAudit = nil
local Perception = nil
local Environment = nil
local RuntimeState = nil
local MovementClaims = nil
local Social = nil
local FlockSearch = nil
local FleeEscape = nil
local NavigationExecution = nil
local Fear = nil
local ThreatAssessment = nil
local BehaviorDebugPreset = nil
local WorldSemantics = nil
local Utility = nil
local SpeciesSprites = nil
local Relationships = nil
local EcologyClock = nil
local DormantLifecycle = nil
local Concealment = nil
local Disturbance = nil
local Emergence = nil
local SpawnCells = nil
local SpeciesEcology = nil
local applyMovementRequestToAvatar = nil
local updatePhase5Diagnostic = nil
local buildAgentAuditContext = nil
local buildAgentAuditSamples = nil
local spawnSyncIsStable = nil
local SPAWN_DEBUG_BUILD = "spawn-debug-20260825-09"
local BEHAVIOR_DECISION_INTERVAL_TICKS = 15
local FEAR_INTEGRATION_INTERVAL_TICKS = 3


local WildEcology = {
  activeAvatars = {},
  entityById = {},
  focusedEntityId = nil,
  mod = nil,
  saveReady = false,
  updateHookInstalled = false,
  debugUiInstalled = false,
  debugUiWrap = nil,
  perceptionPairs = {},
  perceptionPositions = {},
  actorFrameContexts = {},
  perceptionNeighbors = {},
  movementClaims = nil,
  relationshipAudit = nil,
  agentAudit = nil,
  behaviorDiagnosticsByMap = {},
  telemetryDiagnostics = {
    fleeRouteNormalRecords = 0,
    fleeRouteNormalSuppressedUnchanged = 0,
    fearNormalRecords = 0,
    fearNormalSuppressedCalmBookkeeping = 0
  },
  materializationDiagnostics = {},
  spawnDiagnostics = {
    materializationAttempts = 0,
    materializationValid = 0,
    materializationRejected = 0,
    spawnNpcCalls = 0,
    anchorCalls = 0,
    cohortCalls = 0,
    visibleRequested = 0,
    populationPersistentTotal = 0,
    populationEligibleTotal = 0,
    populationSelectedTotal = 0,
    populationConcealedTotal = 0,
    populationInvalidLocationTotal = 0,
    populationAlreadyActiveTotal = 0,
    spawnCellsAvailable = 0,
    spawnAssignmentsMade = 0,
    materializeCalls = 0,
    materializeSuccess = 0,
    materializeFailure = 0,
    activeAvatarCount = 0,
    materializedThisTick = 0,
    destroyedThisTick = 0,
    exclusionReasons = {},
    materializationStatus = "NOT_RUN",
    lastSpawnStatus = "NOT_RUN",
    lastAdapterResult = "nil",
    lastAdapterReason = "NOT_RUN",
    phase3Entered = 0,
    phase3LoopEntered = 0,
    phase3DispatchAttempts = 0,
    phase3SyncSkipped = 0,
    phase3DispatchStage = "NOT_RUN",
    phase3LastBlocker = "NOT_CALLED",
    lastPhase3Error = "NONE",
    lastPhase3ErrorStage = "NONE",
    lastPhase3ActorId = nil,
    lastPhase3ActorSpecies = nil,
    lastPhase3ActorCell = "NONE"
  },
  worldInputProbe = nil,
  worldInputProbeMapId = nil,
  worldInputProbeAt = nil,
  spawnInitialization = {
    status = "NOT_RUN",
    mapId = nil,
    semanticsGeneration = nil,
    reason = "NOT_RUN",
    attempts = 0
  },
  spawnSyncDirty = true,
  expectedSpawnIds = {},
  visiblePopulationByMap = {},
  visitSpawnCells = {},
  routeVisitEpoch = 0,
  routeVisitMapId = nil,
  routeVisitCounts = {},
  logSettingsScreenOpen = false,
  currentClockSample = nil,
  dormantEnvironmentByMap = {},
  disturbancesByMap = {},
  concealmentCuesByMap = {},
  lastConcealmentCueTickByEntity = {},
  lastPlayerPositionByMap = {},
  performanceProfiler = {
    enabled = false,
    totals = {},
    counts = {},
    samples = 0,
    memorySamples = {},
    lastMemorySampleTick = nil,
    startedAtTick = nil,
    lastTick = nil
  }
}

local OriginalRequire = require
local ActiveModRequirePrefix = nil
local ActiveModRootPath = nil
local RequireShimInstalled = false

local function performanceCount(name, amount)
  local profiler = WildEcology.performanceProfiler
  if profiler.enabled then
    profiler.counts[name] = (profiler.counts[name] or 0) + (amount or 1)
  end
end

local function performanceStart(name)
  if WildEcology.performanceProfiler.enabled and os.clock then
    return name, os.clock()
  end
  return nil, nil
end

local function performanceStop(name, startedAt)
  if name and startedAt then
    local profiler = WildEcology.performanceProfiler
    profiler.totals[name] = (profiler.totals[name] or 0)
      + (os.clock() - startedAt) * 1000
  end
end

function WildEcology.enablePerformanceProfiler(enabled)
  WildEcology.performanceProfiler.enabled = enabled == true
end

function WildEcology.resetPerformanceProfiler()
  local profiler = WildEcology.performanceProfiler
  profiler.totals, profiler.counts = {}, {}
  profiler.samples, profiler.startedAtTick, profiler.lastTick = 0, nil, nil
  profiler.memorySamples, profiler.lastMemorySampleTick = {}, nil
end

function WildEcology.getPerformanceSnapshot()
  local profiler = WildEcology.performanceProfiler
  local totals, counts = {}, {}
  for name, value in pairs(profiler.totals) do totals[name] = value end
  for name, value in pairs(profiler.counts) do counts[name] = value end
  return { enabled = profiler.enabled, totals = totals, counts = counts,
    samples = profiler.samples, startedAtTick = profiler.startedAtTick,
    lastTick = profiler.lastTick, memorySamples = profiler.memorySamples }
end

local function countKeys(value)
  if type(value) ~= "table" then return 0 end
  local count = 0
  for _ in pairs(value) do count = count + 1 end
  return count
end

function WildEcology.getLeakDiagnostics()
  local runtimeStates, runtimeEvents, relationshipRecords = 0, 0, 0
  local perceptionRecords, perceivedFearRecords = 0, 0
  local navigationRecords, intentRecords, rejectionRecords = 0, 0, 0
  local currentMap = WildEcology.spawnInitialization.mapId
  local visible = WildEcology.visiblePopulationByMap[currentMap] or {}
  for _, entity in ipairs(visible) do
    local runtime = entity.runtimeState or {}
    runtimeStates = runtimeStates + 1
    runtimeEvents = runtimeEvents + countKeys(entity.memory and entity.memory.events)
    relationshipRecords = relationshipRecords + countKeys(entity.relationships)
    perceptionRecords = perceptionRecords + countKeys(WildEcology.perceptionPositions[entity.id])
    perceivedFearRecords = perceivedFearRecords + countKeys(runtime.perceivedFear)
    navigationRecords = navigationRecords + countKeys(runtime.navigation and runtime.navigation.dynamicBlockedEdges)
    intentRecords = intentRecords + (runtime.intentEpisode and 1 or 0)
    rejectionRecords = rejectionRecords + countKeys(runtime.rejectedMoves)
  end
  local profiler = WildEcology.performanceProfiler
  return {
    luaKB = collectgarbage and collectgarbage("count") or 0,
    loggerEntries = DebugLogger and countKeys(DebugLogger.entries()) or 0,
    recentEvents = runtimeEvents,
    relationshipRecords = relationshipRecords,
    contactRecords = perceptionRecords,
    perceivedFearRecords = perceivedFearRecords,
    navigationRecords = navigationRecords,
    rejectionRecords = rejectionRecords,
    intentRecords = intentRecords,
    disturbanceRecords = countKeys(WildEcology.disturbancesByMap[currentMap]),
    cueRecords = countKeys(WildEcology.concealmentCuesByMap[currentMap]),
    runtimeStates = runtimeStates,
    activeAvatars = countKeys(WildEcology.activeAvatars),
    profilerSamples = profiler.samples,
    profilerMemorySamples = countKeys(profiler.memorySamples),
    mapCaches = countKeys(WildEcology.visiblePopulationByMap)
  }
end

function WildEcology.getActorFrameContext(entityId)
  return WildEcology.actorFrameContexts[entityId]
end

local function loadModuleFromFilePath(moduleName)
  if type(moduleName) ~= "string" then
    return false, "module name must be a string"
  end
  if not ActiveModRootPath then
    return false, "mod root path unavailable"
  end
  if not loadfile then
    return false, "loadfile unavailable in this runtime"
  end

  if package and package.loaded and package.loaded[moduleName] ~= nil then
    return true, package.loaded[moduleName]
  end

  local relativePath = moduleName:gsub("%.", "/") .. ".lua"
  local absolutePath = ActiveModRootPath .. "/" .. relativePath

  local chunk, loadErr = loadfile(absolutePath)
  if not chunk then
    return false, loadErr
  end

  local okExec, result = pcall(chunk)
  if not okExec then
    return false, result
  end

  if result == nil then
    result = true
  end
  if package and package.loaded then
    package.loaded[moduleName] = result
  end

  return true, result
end

local function installRequireShim(mod)
  if RequireShimInstalled then
    return
  end

  local modPath = mod and mod.path
  if modPath then
    local normalizedPath = tostring(modPath):gsub("\\", "/")
    ActiveModRootPath = normalizedPath
    ActiveModRequirePrefix = normalizedPath:gsub("[/\\]", ".")
  end

  require = function(moduleName)
    local okDirect, loadedDirect = pcall(OriginalRequire, moduleName)
    if okDirect then
      return loadedDirect
    end

    if type(moduleName) ~= "string" then
      error(loadedDirect)
    end
    if not ActiveModRequirePrefix then
      error(loadedDirect)
    end
    if moduleName:sub(1, 4) ~= "src." then
      error(loadedDirect)
    end

    local prefixedError = nil
    if ActiveModRequirePrefix then
      local prefixedName = ActiveModRequirePrefix .. "." .. moduleName
      local okPrefixed, loadedPrefixed = pcall(OriginalRequire, prefixedName)
      if okPrefixed then
        return loadedPrefixed
      end
      prefixedError = loadedPrefixed
    end

    local okFilePath, loadedFromFilePath = loadModuleFromFilePath(moduleName)
    if okFilePath then
      return loadedFromFilePath
    end

    local details = tostring(loadedDirect)
    if prefixedError then
      details = details .. "\n[prefixed require] " .. tostring(prefixedError)
    end
    details = details .. "\n[file path load] " .. tostring(loadedFromFilePath)
    error(details)
  end

  RequireShimInstalled = true
end

local function requireFromMod(_mod, moduleSuffix)
  return pcall(require, moduleSuffix)
end

local function loadModules(mod)
  if Config and Save and Gen1PersistenceAdapter and PopulationManager and AvatarFactory and Controller and DebugLogger and TelemetryPolicy and RelationshipAudit and AgentAudit and Perception and Environment and RuntimeState and MovementClaims and Social and FlockSearch and Fear and ThreatAssessment and WorldSemantics and NavigationExecution and Utility and Relationships and EcologyClock and DormantLifecycle and Concealment and Disturbance and Emergence then
    return true
  end

  local okConfig, loadedConfig = requireFromMod(mod, "src.core.config")
  if not okConfig then
    return false, loadedConfig
  end
  local okMechanics, mechanics = requireFromMod(mod, "src.adapters.pokemon_mechanics")
  if not okMechanics then return false, mechanics end
  local okGen1Mechanics, gen1Mechanics = requireFromMod(mod,
    "src.adapters.gen1.pokemon_mechanics")
  if not okGen1Mechanics then return false, gen1Mechanics end
  mechanics.register(gen1Mechanics)
  local okSave, loadedSave = requireFromMod(mod, "src.core.save")
  if not okSave then
    return false, loadedSave
  end
  local okGen1PersistenceAdapter, loadedGen1PersistenceAdapter = requireFromMod(mod,
    "src.adapters.gen1.persistence_adapter")
  if not okGen1PersistenceAdapter then
    return false, loadedGen1PersistenceAdapter
  end
  local okPop, loadedPop = requireFromMod(mod, "src.population.manager")
  if not okPop then
    return false, loadedPop
  end
  local okAvatar, loadedAvatar = requireFromMod(mod, "src.world.avatar_factory")
  if not okAvatar then
    return false, loadedAvatar
  end
  local okRuntimeAvatarAdapter, loadedRuntimeAvatarAdapter = requireFromMod(mod, "src.world.runtime_avatar_adapter")
  if not okRuntimeAvatarAdapter then
    return false, loadedRuntimeAvatarAdapter
  end
  local okController, loadedController = requireFromMod(mod, "src.behavior.controller")
  if not okController then
    return false, loadedController
  end
  local okLogger, loadedLogger = requireFromMod(mod, "src.debug.logger")
  if not okLogger then
    return false, loadedLogger
  end
  local okTelemetryPolicy, loadedTelemetryPolicy = requireFromMod(mod, "src.debug.telemetry_policy")
  if not okTelemetryPolicy then
    return false, loadedTelemetryPolicy
  end
  local okRelationshipAudit, loadedRelationshipAudit = requireFromMod(mod, "src.debug.relationship_audit")
  if not okRelationshipAudit then
    return false, loadedRelationshipAudit
  end
  local okAgentAudit, loadedAgentAudit = requireFromMod(mod, "src.debug.agent_audit")
  if not okAgentAudit then
    return false, loadedAgentAudit
  end
  local okPerception, loadedPerception = requireFromMod(mod, "src.world.perception")
  if not okPerception then
    return false, loadedPerception
  end
  local okEnvironment, loadedEnvironment = requireFromMod(mod, "src.world.environment")
  if not okEnvironment then
    return false, loadedEnvironment
  end
  local okRuntimeState, loadedRuntimeState = requireFromMod(mod, "src.core.runtime_state")
  if not okRuntimeState then
    return false, loadedRuntimeState
  end
  local okMovementClaims, loadedMovementClaims = requireFromMod(mod, "src.world.movement_claims")
  if not okMovementClaims then
    return false, loadedMovementClaims
  end
  local okSocial, loadedSocial = requireFromMod(mod, "src.behavior.social")
  if not okSocial then
    return false, loadedSocial
  end
  local okRelationships, loadedRelationships = requireFromMod(mod, "src.entities.relationships")
  if not okRelationships then
    return false, loadedRelationships
  end
  local okFlockSearch, loadedFlockSearch = requireFromMod(mod, "src.behavior.flock_search")
  if not okFlockSearch then
    return false, loadedFlockSearch
  end
  local okFleeEscape, loadedFleeEscape = requireFromMod(mod, "src.behavior.flee_escape")
  if not okFleeEscape then
    return false, loadedFleeEscape
  end
  local okNavigationExecution, loadedNavigationExecution = requireFromMod(mod,
    "src.navigation.navigation_execution")
  if not okNavigationExecution then
    return false, loadedNavigationExecution
  end
  local okFear, loadedFear = requireFromMod(mod, "src.behavior.fear")
  if not okFear then
    return false, loadedFear
  end
  local okThreatAssessment, loadedThreatAssessment = requireFromMod(mod, "src.behavior.threat_assessment")
  if not okThreatAssessment then
    return false, loadedThreatAssessment
  end
  local okBehaviorDebugPreset, loadedBehaviorDebugPreset = requireFromMod(mod, "src.behavior.debug_preset")
  if not okBehaviorDebugPreset then
    return false, loadedBehaviorDebugPreset
  end
  local okWorldSemantics, loadedWorldSemantics = requireFromMod(mod, "src.world.world_semantics")
  if not okWorldSemantics then
    return false, loadedWorldSemantics
  end
  local okSpeciesSprites, loadedSpeciesSprites = requireFromMod(mod, "src.world.species_sprites")
  if not okSpeciesSprites then
    return false, loadedSpeciesSprites
  end
  local okEcologyClock, loadedEcologyClock = requireFromMod(mod, "src.time.ecology_clock")
  if not okEcologyClock then
    return false, loadedEcologyClock
  end
  local okDormantLifecycle, loadedDormantLifecycle = requireFromMod(mod,
    "src.dormant.dormant_lifecycle")
  if not okDormantLifecycle then
    return false, loadedDormantLifecycle
  end
  local okConcealment, loadedConcealment = requireFromMod(mod,
    "src.world.concealment")
  if not okConcealment then return false, loadedConcealment end
  local okDisturbance, loadedDisturbance = requireFromMod(mod,
    "src.world.disturbance")
  if not okDisturbance then return false, loadedDisturbance end
  local okEmergence, loadedEmergence = requireFromMod(mod,
    "src.world.emergence")
  if not okEmergence then return false, loadedEmergence end
  local okSpawnCells, loadedSpawnCells = requireFromMod(mod,
    "src.world.spawn_cells")
  if not okSpawnCells then return false, loadedSpawnCells end
  local okSpeciesEcology, loadedSpeciesEcology = requireFromMod(mod,
    "src.species.species_ecology")
  if not okSpeciesEcology then return false, loadedSpeciesEcology end

  Config = loadedConfig
  Save = loadedSave
  Gen1PersistenceAdapter = loadedGen1PersistenceAdapter
  PopulationManager = loadedPop
  AvatarFactory = loadedAvatar
  RuntimeAvatarAdapter = loadedRuntimeAvatarAdapter
  if RuntimeAvatarAdapter and RuntimeAvatarAdapter.setAvatarFactory then
    RuntimeAvatarAdapter.setAvatarFactory(AvatarFactory)
  end
  Controller = loadedController
  DebugLogger = loadedLogger
  TelemetryPolicy = loadedTelemetryPolicy
  RelationshipAudit = loadedRelationshipAudit
  AgentAudit = loadedAgentAudit
  Perception = loadedPerception
  Environment = loadedEnvironment
  RuntimeState = loadedRuntimeState
  MovementClaims = loadedMovementClaims
  Social = loadedSocial
  Relationships = loadedRelationships
  FlockSearch = loadedFlockSearch
  FleeEscape = loadedFleeEscape
  NavigationExecution = loadedNavigationExecution
  Fear = loadedFear
  ThreatAssessment = loadedThreatAssessment
  BehaviorDebugPreset = loadedBehaviorDebugPreset
  WorldSemantics = loadedWorldSemantics
  local okUtility, loadedUtility = requireFromMod(mod, "src.behavior.utility")
  if not okUtility then
    return false, loadedUtility
  end
  Utility = loadedUtility
  SpeciesSprites = loadedSpeciesSprites
  EcologyClock = loadedEcologyClock
  DormantLifecycle = loadedDormantLifecycle
  Concealment = loadedConcealment
  Disturbance = loadedDisturbance
  Emergence = loadedEmergence
  SpawnCells = loadedSpawnCells
  SpeciesEcology = loadedSpeciesEcology
  return true
end

local DEBUG_MODE_OPTION_KEY = "phase0_behavior_mode"
local DEBUG_LOG_OPTION_KEY = "phase0_debug_log"
local DEBUG_LOG_VIEW_OPTION_KEY = "dev_log_view"
local DEBUG_LOG_LIFECYCLE_OPTION_KEY = "dev_log_lifecycle"
local DEBUG_LOG_BEHAVIOR_OPTION_KEY = "dev_log_behavior"
local DEBUG_LOG_BEHAVIOR_TRACE_OPTION_KEY = "dev_log_behavior_trace"
local DEBUG_LOG_RELATIONSHIPS_OPTION_KEY = "dev_log_relationships"
local DEBUG_LOG_RELATIONSHIP_AUDIT_OPTION_KEY = "relationship_audit_enabled"
local DEBUG_LOG_AGENT_AUDIT_OPTION_KEY = "agent_audit_enabled"
-- Must match src/population/generator.lua's Generator.GENERATION_LOG_OPTION_KEY.
local DEBUG_LOG_GENERATION_OPTION_KEY = "dev_log_generation"
local DEBUG_LOG_CONSOLE_OPTION_KEY = "dev_log_console"
local PHASE2_SOCIAL_FEAR_OPTION_KEY = "phase2_social_fear"
local PHASE2_SOCIAL_REASSURANCE_OPTION_KEY = "phase2_social_reassurance"
local PHASE5_DIAGNOSTICS_OPTION_KEY = "phase5_diagnostics"
local IGNORE_PLAYER_OPTION_KEY = "ignore_player"
local ECOLOGY_REAL_TIME_OPTION_KEY = "ecology_real_time"
local ECOLOGY_DAY_DURATION_OPTION_KEY = "ecology_day_duration"
local LOG_SETTINGS_SCREEN_ID = "WildEcologyLogSettings"

local DEBUG_CATEGORY_PREFIX = {
  lifecycle = "L",
  behavior = "B",
  relationships = "R",
  generation = "G"
}

-- Rendered inside the nested LOG SETTINGS screen (mod.save-backed, not
-- mod.options) instead of flooding the flat mod options menu with 6 rows.
local LOG_SCREEN_ITEMS = {
  { key = DEBUG_LOG_OPTION_KEY, label = "HUD LOG", kind = "toggle", default = false },
  { key = DEBUG_LOG_VIEW_OPTION_KEY, label = "VIEW", kind = "choice", default = "both", choices = { "summary", "events", "both" } },
  { key = DEBUG_LOG_LIFECYCLE_OPTION_KEY, label = "LIFECYCLE", kind = "toggle", default = true },
  { key = DEBUG_LOG_BEHAVIOR_OPTION_KEY, label = "BEHAVIOR", kind = "toggle", default = true },
  { key = DEBUG_LOG_BEHAVIOR_TRACE_OPTION_KEY, label = "BEHAVIOR TRACE", kind = "toggle", default = false },
  { key = DEBUG_LOG_RELATIONSHIPS_OPTION_KEY, label = "RELATIONSHIPS", kind = "toggle", default = false },
  { key = DEBUG_LOG_RELATIONSHIP_AUDIT_OPTION_KEY, label = "REL AUDIT", kind = "toggle", default = false },
  { key = DEBUG_LOG_AGENT_AUDIT_OPTION_KEY, label = "AGENT AUDIT", kind = "toggle", default = false },
  { key = DEBUG_LOG_GENERATION_OPTION_KEY, label = "GENERATION", kind = "toggle", default = false },
  -- Writes to a real file via mod.storage:writeBytes (see flushConsoleQueue
  -- below), not the console/print() -- look for "wildecology_log" under the
  -- LOVE save directory (Windows: %APPDATA%\love\pokemon-love2d\).
  { key = DEBUG_LOG_CONSOLE_OPTION_KEY, label = "LOG TO FILE", kind = "toggle", default = false }
}

local function defineOptions(mod)
  if not (mod and mod.options and mod.options.define) then
    return
  end

  mod.options:define({
    {
      key = DEBUG_MODE_OPTION_KEY,
      type = "choice",
      label = "PHASE0 BEHAVIOR",
      default = "normal",
      choices = {
        { "NORMAL", "normal" },
        { "FORCE IDLE", "force_idle" },
        { "FORCE FLEE", "force_flee" },
        { "FORCE APPROACH", "force_approach" },
        { "FORCE INVESTIGATE", "force_investigate" },
        { "FORCE TARGET", "force_target" },
        { "IGNORE PLAYER", "ignore_player" }
      }
    },
    {
      key = PHASE2_SOCIAL_FEAR_OPTION_KEY,
      type = "toggle",
      label = "PHASE2 SOCIAL FEAR",
      default = false
    },
    {
      key = PHASE2_SOCIAL_REASSURANCE_OPTION_KEY,
      type = "toggle",
      label = "PHASE2 SOCIAL REASSURANCE",
      default = false
    },
    {
      key = PHASE5_DIAGNOSTICS_OPTION_KEY,
      type = "toggle",
      label = "PHASE5 DIAGNOSTICS",
      default = true
    },
    {
      key = ECOLOGY_REAL_TIME_OPTION_KEY,
      type = "toggle",
      label = "SYNC ECOLOGY TO REAL TIME",
      default = false
    },
    {
      key = ECOLOGY_DAY_DURATION_OPTION_KEY,
      type = "choice",
      label = "SIMULATION DAY LENGTH",
      default = "1h",
      choices = {
        { "30 MINUTES", "30m" },
        { "1 HOUR", "1h" },
        { "6 HOURS", "6h" },
        { "24 HOURS", "24h" }
      }
    }
  })
end

local function normalizeMapId(value)
  if value == nil then
    return nil
  end

  local mapId = tostring(value):upper():gsub("%s+", "_")
  mapId = mapId:gsub("^ROUTE0+([0-9]+)$", "ROUTE_%1")
  mapId = mapId:gsub("^ROUTE([0-9]+)$", "ROUTE_%1")
  return mapId
end

local function isEcologyMap(mapId)
  return Config and Config.isEcologyEnabled and Config.isEcologyEnabled(mapId) or false
end

local function isPhase0AnchorMap(mapId)
  local phase0 = (Config and Config.phase0) or {}
  return normalizeMapId(mapId) == normalizeMapId(phase0.testMapId)
end

local function readCurrentMapId(mod)
  local world = mod and mod.world
  local current = world and world.current and world:current() or nil
  if not current then
    return nil
  end

  return current.mapId or current.id or current.name
end

local function behaviorDebugSnapshot(mapId)
  local diagnostics = WildEcology.behaviorDiagnosticsByMap[mapId] or {}
  local activeIds = {}
  for entityId in pairs(WildEcology.activeAvatars) do
    activeIds[#activeIds + 1] = entityId
  end
  table.sort(activeIds)

  local focusedId = WildEcology.focusedEntityId
  if not focusedId or not WildEcology.activeAvatars[focusedId] then
    local anchorId = Config and Config.phase0 and Config.phase0.testEntityId or nil
    focusedId = anchorId and WildEcology.activeAvatars[anchorId] and anchorId or activeIds[1]
  end
  local entity = focusedId and WildEcology.entityById[focusedId] or nil
  local runtime = entity and entity.runtimeState or {}
  local state = Save and Save.getState and Save.getState() or nil
  local tick = state and state.simulationTick or 0
  local lastDecisionTick = runtime.lastDecisionTick
  local totalSwitches, totalStarts, totalCompletions = 0, 0, 0
  local totalInterruptions, totalFailures, totalAmbientInterruptions = 0, 0, 0
  local lifecycleTicks, highLevelDeliberations, executionUpdates = 0, 0, 0
  local movementRequests, navigationReplans = 0, 0
  local emergencyInterruptChecks, emergencyInterrupts = 0, 0
  local fearUpdates, socialFearAggregations = 0, 0
  local socialSourceEvaluations, directFearEvaluations, alarmOutputUpdates = 0, 0, 0
  local perceptionPasses, observerTargetCandidateChecks = 0, 0
  local detailedPerceptionPairChecks, perceptionEvents = 0, 0
  for _, entityId in ipairs(activeIds) do
    local activeEntity = WildEcology.entityById[entityId]
    local intentMetrics = activeEntity and activeEntity.runtimeState
      and activeEntity.runtimeState.intentMetrics or {}
    totalSwitches = totalSwitches + (intentMetrics.intentSwitches or 0)
    totalStarts = totalStarts + (intentMetrics.purposefulIntentStarts or 0)
    totalCompletions = totalCompletions + (intentMetrics.purposefulIntentCompletions or 0)
    totalInterruptions = totalInterruptions + (intentMetrics.purposefulIntentInterruptions or 0)
    totalFailures = totalFailures + (intentMetrics.purposefulIntentFailures or 0)
    totalAmbientInterruptions = totalAmbientInterruptions + (intentMetrics.ambientInterruptions or 0)
    local schedulerMetrics = activeEntity and activeEntity.runtimeState
      and activeEntity.runtimeState.schedulerMetrics or {}
    lifecycleTicks = lifecycleTicks + (schedulerMetrics.lifecycleTicks or 0)
    highLevelDeliberations = highLevelDeliberations
      + (schedulerMetrics.highLevelDeliberations or 0)
    executionUpdates = executionUpdates + (schedulerMetrics.executionUpdates or 0)
    movementRequests = movementRequests + (schedulerMetrics.movementRequests or 0)
    navigationReplans = navigationReplans + (schedulerMetrics.navigationReplans or 0)
    emergencyInterruptChecks = emergencyInterruptChecks
      + (schedulerMetrics.emergencyInterruptChecks or 0)
    emergencyInterrupts = emergencyInterrupts
      + (schedulerMetrics.emergencyInterrupts or 0)
    local fearMetrics = activeEntity and activeEntity.runtimeState
      and activeEntity.runtimeState.fearMetrics or {}
    fearUpdates = fearUpdates + (fearMetrics.fearUpdates or 0)
    socialFearAggregations = socialFearAggregations
      + (fearMetrics.socialFearAggregations or 0)
    socialSourceEvaluations = socialSourceEvaluations
      + (fearMetrics.socialSourceEvaluations or 0)
    directFearEvaluations = directFearEvaluations
      + (fearMetrics.directFearEvaluations or 0)
    alarmOutputUpdates = alarmOutputUpdates + (fearMetrics.alarmOutputUpdates or 0)
    local perceptionMetrics = activeEntity and activeEntity.runtimeState
      and activeEntity.runtimeState.perceptionMetrics or {}
    perceptionPasses = perceptionPasses + (perceptionMetrics.perceptionPasses or 0)
    observerTargetCandidateChecks = observerTargetCandidateChecks
      + (perceptionMetrics.observerTargetCandidateChecks or 0)
    detailedPerceptionPairChecks = detailedPerceptionPairChecks
      + (perceptionMetrics.detailedPerceptionPairChecks or 0)
    perceptionEvents = perceptionEvents
      + (perceptionMetrics.seenEvents or 0)
      + (perceptionMetrics.lostEvents or 0)
      + (perceptionMetrics.approachingEvents or 0)
      + (perceptionMetrics.retreatingEvents or 0)
  end
  local metricAge = diagnostics.intentMetricStartTick
    and math.max(1, tick - diagnostics.intentMetricStartTick) or 1
  local fleePlannerCounters = FleeEscape and FleeEscape.getCounters
    and FleeEscape.getCounters() or {}
  local navigationCounters = NavigationExecution and NavigationExecution.getCounters
    and NavigationExecution.getCounters() or {}
  local telemetry = WildEcology.telemetryDiagnostics or {}

  return {
    activeEntities = #activeIds,
    behaviorEligible = diagnostics.behaviorEligible or 0,
    behaviorDecisionTicks = diagnostics.behaviorDecisionTicks or 0,
    ambientDecisions = diagnostics.ambientDecisions or 0,
    fleeDecisions = diagnostics.fleeDecisions or 0,
    directlyFrightenedCount = diagnostics.directlyFrightenedCount or 0,
    sociallyFrightenedCount = diagnostics.sociallyFrightenedCount or 0,
    highFearDirectCount = diagnostics.highFearDirectCount or 0,
    highFearSocialOnlyCount = diagnostics.highFearSocialOnlyCount or 0,
    averageAlarmGroundedness = diagnostics.averageAlarmGroundedness or 0,
    maxSocialRelayAlarm = diagnostics.maxSocialRelayAlarm or 0,
    intentSwitches = totalSwitches,
    intentSwitchesPer100Ticks = totalSwitches * 100 / metricAge,
    purposefulIntentStarts = totalStarts,
    purposefulIntentCompletions = totalCompletions,
    purposefulIntentInterruptions = totalInterruptions,
    purposefulIntentFailures = totalFailures,
    ambientInterruptions = totalAmbientInterruptions,
    lifecycleTicks = lifecycleTicks,
    highLevelDeliberations = highLevelDeliberations,
    deliberationsPer100Ticks = highLevelDeliberations * 100 / math.max(1, lifecycleTicks),
    executionUpdates = executionUpdates,
    movementRequests = movementRequests,
    movementRequestsPer100Ticks = movementRequests * 100 / math.max(1, lifecycleTicks),
    navigationReplans = navigationReplans,
    replansPer100Ticks = navigationReplans * 100 / math.max(1, lifecycleTicks),
    boundedFleePlannerCalls = fleePlannerCounters.boundedFleePlannerCalls or 0,
    genericPlannerCalls = navigationCounters.plannerCalls or 0,
    genericPlannerCallsSuppressed = navigationCounters.plannerCallsSuppressed or 0,
    genericLocalSteeringSteps = navigationCounters.localSteeringSteps or 0,
    genericRouteFollowingSteps = navigationCounters.routeFollowingSteps or 0,
    genericNavigationReplans = navigationCounters.replans or 0,
    genericSearchNodeExpansions = navigationCounters.searchNodeExpansions or 0,
    boundedFleeRouteObjectsCreated = fleePlannerCounters.boundedFleeRouteObjectsCreated or 0,
    boundedFleePlannerCallsSuppressed = fleePlannerCounters.boundedFleePlannerCallsSuppressed or 0,
    boundedFleePlannerDirtyEvents = fleePlannerCounters.boundedFleePlannerDirtyEvents or 0,
    dirtyByActorMovement = fleePlannerCounters.dirtyByActorMovement or 0,
    dirtyByBlockerMovement = fleePlannerCounters.dirtyByBlockerMovement or 0,
    dirtyByClaimChange = fleePlannerCounters.dirtyByClaimChange or 0,
    dirtyByThreatChange = fleePlannerCounters.dirtyByThreatChange or 0,
    dirtyBySocialVector = fleePlannerCounters.dirtyBySocialVector or 0,
    dirtyByTopologyChange = fleePlannerCounters.dirtyByTopologyChange or 0,
    dirtyByWatchdog = fleePlannerCounters.dirtyByWatchdog or 0,
    boundedFleeDirtyBySocialVector = fleePlannerCounters.dirtyBySocialVector or 0,
    boundedFleeDirtyByActorMovement = fleePlannerCounters.dirtyByActorMovement or 0,
    boundedFleeDirtyByBlockerMovement = fleePlannerCounters.dirtyByBlockerMovement or 0,
    boundedFleeDirtyByClaimChange = fleePlannerCounters.dirtyByClaimChange or 0,
    boundedFleeDirtyByThreatChange = fleePlannerCounters.dirtyByThreatChange or 0,
    boundedFleeDirtyByTopologyChange = fleePlannerCounters.dirtyByTopologyChange or 0,
    boundedFleeDirtyByWatchdog = fleePlannerCounters.dirtyByWatchdog or 0,
    socialVectorUpdatesObserved = fleePlannerCounters.socialVectorUpdatesObserved or 0,
    socialVectorUpdatesMaterial = fleePlannerCounters.socialVectorUpdatesMaterial or 0,
    socialVectorUpdatesIgnoredAsEquivalent =
      fleePlannerCounters.socialVectorUpdatesIgnoredAsEquivalent or 0,
    fleeRouteNormalRecords = telemetry.fleeRouteNormalRecords or 0,
    fleeRouteNormalSuppressedUnchanged = telemetry.fleeRouteNormalSuppressedUnchanged or 0,
    fearNormalRecords = telemetry.fearNormalRecords or 0,
    fearNormalSuppressedCalmBookkeeping = telemetry.fearNormalSuppressedCalmBookkeeping or 0,
    emergencyInterruptChecks = emergencyInterruptChecks,
    emergencyInterrupts = emergencyInterrupts,
    fearUpdates = fearUpdates,
    fearUpdatesPer100Ticks = fearUpdates * 100 / metricAge,
    socialFearAggregations = socialFearAggregations,
    socialFearAggregationsPer100Ticks = socialFearAggregations * 100 / metricAge,
    socialSourceEvaluations = socialSourceEvaluations,
    socialSourceEvaluationsPer100Ticks = socialSourceEvaluations * 100 / metricAge,
    directFearEvaluations = directFearEvaluations,
    directFearEvaluationsPer100Ticks = directFearEvaluations * 100 / metricAge,
    alarmOutputUpdates = alarmOutputUpdates,
    alarmOutputUpdatesPer100Ticks = alarmOutputUpdates * 100 / metricAge,
    perceptionPasses = perceptionPasses,
    perceptionPassesPer100Ticks = perceptionPasses * 100 / metricAge,
    observerTargetCandidateChecks = observerTargetCandidateChecks,
    observerTargetCandidateChecksPer100Ticks = observerTargetCandidateChecks * 100 / metricAge,
    detailedPerceptionPairChecks = detailedPerceptionPairChecks,
    detailedPerceptionPairChecksPer100Ticks = detailedPerceptionPairChecks * 100 / metricAge,
    perceptionEvents = perceptionEvents,
    perceptionEventsPer100Ticks = perceptionEvents * 100 / metricAge,
    entity = focusedId,
    lastDecisionTick = lastDecisionTick,
    decisionAge = lastDecisionTick and math.max(0, tick - lastDecisionTick) or nil,
    state = runtime.state,
    reason = runtime.lastDecisionReason,
    intentEpisode = runtime.intentEpisode and runtime.intentEpisode.intent or nil,
    intentEpisodeAge = runtime.intentEpisodeAge,
    lastDeliberationTick = runtime.lastDeliberationTick,
    nextDeliberationTick = runtime.nextDeliberationTick,
    deliberationDue = runtime.deliberationDue == true,
    deliberationPerformed = runtime.deliberationPerformed == true,
    reconsiderationReason = runtime.reconsiderationReason,
    executionUpdated = runtime.executionUpdated == true,
    executionUpdateReason = runtime.executionUpdateReason,
    perceptionUpdated = runtime.perceptionUpdated == true,
    fearUpdated = runtime.fearUpdated == true,
    navigationReplanned = runtime.navigationReplanned == true,
    navigationReplanReason = runtime.navigationReplanReason,
    movementRequested = runtime.movementRequested == true,
    perceptionContacts = runtime.perceptionContactCount or 0,
    motionActive = runtime.motion and runtime.motion.active == true or false
  }
end

function WildEcology.getSpawnDebugSnapshot()
  local mapId = readCurrentMapId(WildEcology.mod)
  local ecologyEnabled = isEcologyMap(mapId)
  local production = PopulationManager and PopulationManager.getSpawnDebugSnapshot
    and PopulationManager.getSpawnDebugSnapshot(mapId)
    or nil
  if not production then
    return {
      mapId = mapId,
      ecologyEnabled = ecologyEnabled,
      populationMap = "NONE",
      semanticsStatus = "UNAVAILABLE",
      candidateStatus = "NOT_RUN",
      assignmentStatus = "NOT_RUN",
      candidateAnalysis = nil,
      populationRecords = nil,
      homesAssigned = nil,
      homesMissing = nil,
      populationSamples = {},
      behaviorDiagnostics = behaviorDebugSnapshot(mapId),
      spawnInitialization = WildEcology.spawnInitialization,
      movementClaims = WildEcology.movementClaims and WildEcology.movementClaims:snapshot() or nil
    }
  end
  production.ecologyEnabled = ecologyEnabled
  production.populationMap = ecologyEnabled and production.mapId or "NONE"
  production.behaviorDiagnostics = behaviorDebugSnapshot(mapId)
  local analysis = production.candidateAnalysis
  production.semanticsStatus = analysis and analysis.semanticsStatus
    or (production.semantics and "READY" or "UNAVAILABLE")
  production.candidateStatus = analysis and analysis.candidateStatus or "NOT_RUN"
  production.spawnInitialization = WildEcology.spawnInitialization
  production.movementClaims = WildEcology.movementClaims and WildEcology.movementClaims:snapshot() or nil
  return production
end

function WildEcology.getWorldInputDebugSnapshot(force)
  local mapId = readCurrentMapId(WildEcology.mod)
  local now = os.clock and os.clock() or 0
  local probeExpired = WildEcology.worldInputProbeAt == nil
    or now - WildEcology.worldInputProbeAt >= 0.5
  if force or WildEcology.worldInputProbeMapId ~= mapId or probeExpired then
    local ok, probe = pcall(function()
      return WorldSemantics and WorldSemantics.probeFromMod
        and WorldSemantics.probeFromMod(WildEcology.mod, mapId)
        or nil
    end)
    WildEcology.worldInputProbe = ok and probe or {
      mapId = mapId,
      semanticsStatus = "UNAVAILABLE",
      semanticsReason = "SEMANTICS_PROBE_ERROR",
      semanticsError = tostring(probe):gsub("[\r\n]+", " "):sub(1, 160),
      mapOverviewStatus = "NOT_RUN",
      topologyStatus = "NOT_RUN",
      topologyReason = "NOT_RUN"
    }
    WildEcology.worldInputProbeMapId = mapId
    WildEcology.worldInputProbeAt = now
  end
  local current = WildEcology.worldInputProbe or {}
  local production = WorldSemantics and WorldSemantics.getLastProductionProbe
    and WorldSemantics.getLastProductionProbe(mapId)
    or nil
  return {
    current = current,
    lastProduction = production,
    currentSemanticsProbe = current.semanticsStatus == "READY"
      and "AVAILABLE" or "UNAVAILABLE",
    lastProductionSemanticsStatus = production and production.semanticsStatus or "NOT_RUN",
    lastProductionSemanticsReason = production and production.semanticsReason or "NOT_RUN"
  }
end

local function ensureSave(mod)
  if not WildEcology.saveReady or WildEcology.mod ~= mod then
    WildEcology.mod = mod
    if not Save or not Save.init then
      return
    end
    if Gen1PersistenceAdapter and Gen1PersistenceAdapter.init then
      Gen1PersistenceAdapter.init(mod)
    end
    Save.init(Gen1PersistenceAdapter)
    WildEcology.saveReady = true
  end
end

local function applyDebugRelationshipOverrides(rel)
  local phase0 = (Config and Config.phase0) or {}

  if phase0.debugForceTrust ~= nil then
    rel.trust = phase0.debugForceTrust
  end
  if phase0.debugForceThreatMemory ~= nil then
    rel.threatMemory = phase0.debugForceThreatMemory
  end
  if phase0.debugForceHostility ~= nil then
    rel.hostility = phase0.debugForceHostility
  end
end

local function applyPhase0AvatarBehavior(entity, state)
  entity.avatar = entity.avatar or {}

  if state == "FLEE" or state == "APPROACH" or state == "INVESTIGATE"
    or state == "TARGET" or state == "RETURN_HOME" then
    entity.avatar.movement = "WALK"
    entity.avatar.range = "ANY"
    entity.avatar.autonomousMovement = true
    return
  end

  entity.avatar.movement = "STAY"
  entity.avatar.range = "DOWN"
  entity.avatar.autonomousMovement = false
end

local function getPlayerEntity()
  return {
    id = "player",
    kind = "trainer"
  }
end

local function perceptionPositionForPlayer(mod)
  local world = mod and mod.world
  if not world then
    return nil
  end

  if type(world.player) == "table" then
    local playerX = world.player.cellX or world.player.x
    local playerY = world.player.cellY or world.player.y
    if type(playerX) == "number" and type(playerY) == "number" then
      return { cellX = playerX, cellY = playerY }
    end
  end

  if type(world.current) ~= "function" then
    return nil
  end

  local ok, current = pcall(world.current, world)
  if not ok or type(current) ~= "table"
    or type(current.x) ~= "number" or type(current.y) ~= "number" then
    return nil
  end

  return { cellX = current.x, cellY = current.y }
end

local function getEntityPosition(entity)
  if type(entity) ~= "table" then
    return nil, nil
  end

  local cellX = entity.cellX or entity.x
  local cellY = entity.cellY or entity.y

  if type(entity.position) == "function" then
    local ok, posX, posY = pcall(entity.position, entity)
    if ok and posX ~= nil and posY ~= nil then
      return posX, posY
    end
  end

  if type(entity.handle) == "table" and type(entity.handle.position) == "function" then
    local ok, posX, posY = pcall(entity.handle.position, entity.handle)
    if ok and posX ~= nil and posY ~= nil then
      return posX, posY
    end
  end

  if type(entity.handle) == "table" and type(entity.handle.npc) == "table" then
    cellX = cellX or entity.handle.npc.cellX or entity.handle.npc.x
    cellY = cellY or entity.handle.npc.cellY or entity.handle.npc.y
  end

  cellX = cellX or entity.px
  cellY = cellY or entity.py
  if cellX == nil or cellY == nil then
    return nil, nil
  end

  if entity.px and entity.py and (math.abs(entity.px) > 8 or math.abs(entity.py) > 8) then
    cellX = math.floor((entity.px or 0) / 16)
    cellY = math.floor((entity.py or 0) / 16)
  end

  return cellX, cellY
end

local function buildPositionEntity(entity)
  local cellX, cellY = getEntityPosition(entity)
  if cellX == nil or cellY == nil then
    return nil
  end

  return {
    cellX = cellX,
    cellY = cellY
  }
end

local function persistedHomePosition(entity)
  local home = entity and entity.home
  if not home then
    return nil
  end
  return buildPositionEntity({ x = home.spawnX, y = home.spawnY })
end

local function describeDistance(distance)
  if not Utility or not Utility.distanceBand then
    return "near", 1.0
  end

  return Utility.distanceBand(distance)
end

local function getDistanceToPlayer(mod, avatar)
  local playerPosition = perceptionPositionForPlayer(mod)
  local entityPosition = buildPositionEntity(avatar)
  if not playerPosition or not entityPosition then
    return nil
  end

  if not Utility or not Utility.chebyshevDistance then
    return nil
  end

  return Utility.chebyshevDistance(playerPosition, entityPosition)
end

local function getPhase0DebugState()
  if not Save or not Save.getState then
    return nil
  end

  local state = Save.getState()
  if not state then
    return nil
  end

  state.debug = state.debug or {}
  state.debug.phase0 = state.debug.phase0 or {
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
    lastBehaviorMode = "normal"
  }
  return state.debug.phase0
end

local function readOptionValue(mod, key, defaultValue)
  local options = mod and mod.options
  if options and options.get then
    local ok, value = pcall(function()
      return options:get(key)
    end)
    if ok and value ~= nil then
      return value
    end
  end

  return defaultValue
end

local function sampleEcologyClock(mod, advanceSimulation)
  ensureSave(mod)
  local state = Save and Save.getState and Save.getState() or nil
  if not state or not EcologyClock then return nil end
  local config = (Config and Config.ecologyClock) or {}
  local clock = EcologyClock.ensure(state)
  if advanceSimulation then
    clock.sourceTick = (clock.sourceTick or 0) + 1
  end
  local realTime = readOptionValue(mod, ECOLOGY_REAL_TIME_OPTION_KEY,
    config.defaultRealTime == true) == true
  local mode = realTime and "REAL_TIME" or "SIMULATION"
  if config.fixedPhase ~= nil then mode = "FIXED" end
  if clock.mode ~= mode then EcologyClock.setMode(state, mode) end
  local durationKey = readOptionValue(mod, ECOLOGY_DAY_DURATION_OPTION_KEY,
    config.defaultSimulationDayDuration or "1h")
  local dayDuration = (config.simulationDayDurations or {})[durationKey]
    or (60 * 60)
  local sample = EcologyClock.now(state, {
    simulationTick = clock.sourceTick,
    dayDurationSeconds = dayDuration,
    ticksPerSecond = config.ticksPerSecond or 60,
    fixedPhase = config.fixedPhase,
    forwardJumpThreshold = config.forwardJumpThresholdSeconds or 300
  })
  local previous = WildEcology.currentClockSample
  if DebugLogger and previous then
    if previous.source ~= sample.source then
      DebugLogger.log("lifecycle", string.format(
        "ECOLOGY_CLOCK_SOURCE_CHANGED from=%s to=%s",
        tostring(previous.source), tostring(sample.source)))
    end
    if previous.source == sample.source and previous.band ~= sample.band then
      DebugLogger.log("lifecycle", string.format(
        "ECOLOGY_CLOCK_BAND_CHANGED source=%s from=%s to=%s",
        tostring(sample.source), tostring(previous.band), tostring(sample.band)))
    end
    if sample.discontinuity then
      DebugLogger.log("lifecycle", string.format(
        "CLOCK_DISCONTINUITY source=%s direction=%s elapsed=%s",
        tostring(sample.source), tostring(sample.discontinuity),
        tostring(sample.elapsed or 0)))
    end
  end
  WildEcology.currentClockSample = sample
  return sample
end

-- The LOG SETTINGS submenu screen is mod.save-backed (not mod.options),
-- since mod.options rows always render in the flat mod manager list and
-- there is no documented way for mod code to write an option value itself.
local function readSaveFlag(mod, key, defaultValue)
  local save = mod and mod.save
  if save and save.get then
    local ok, value = pcall(function()
      return save:get(key, defaultValue)
    end)
    if ok and value ~= nil then
      return value
    end
  end

  return defaultValue
end

local function writeSaveFlag(mod, key, value)
  local save = mod and mod.save
  if save and save.set then
    pcall(function()
      save:set(key, value)
    end)
  end
end

local function readBehaviorMode(mod)
  local rawMode = readOptionValue(mod, DEBUG_MODE_OPTION_KEY, "normal")
  local normalized = tostring(rawMode or "normal"):lower():gsub("%s+", "_")

  if normalized == "force_idle" or normalized == "idle" then
    return "force_idle"
  end
  if normalized == "force_flee" or normalized == "flee" then
    return "force_flee"
  end
  if normalized == "force_approach" or normalized == "approach" then
    return "force_approach"
  end
  if normalized == "force_investigate" or normalized == "investigate" then
    return "force_investigate"
  end
  if normalized == "force_target" or normalized == "target" then
    return "force_target"
  end
  if normalized == "ignore_player" or normalized == "ignore" then
    return "ignore_player"
  end

  return "normal"
end

local function readPhase2SocialFearEnabled(mod)
  return readOptionValue(mod, PHASE2_SOCIAL_FEAR_OPTION_KEY, false) == true
end

local function readPhase2SocialReassuranceEnabled(mod)
  return readOptionValue(mod, PHASE2_SOCIAL_REASSURANCE_OPTION_KEY, false) == true
end

local function readDebugLogEnabled(mod)
  return readSaveFlag(mod, DEBUG_LOG_OPTION_KEY, false) == true
end

local function readPhase5DiagnosticsEnabled(mod)
  return readOptionValue(mod, PHASE5_DIAGNOSTICS_OPTION_KEY, false) == true
end

local function readBehaviorTraceEnabled(mod)
  -- NORMAL answers what changed or failed; TRACE is the per-step and
  -- per-evaluation execution transcript.
  return readSaveFlag(mod, DEBUG_LOG_BEHAVIOR_TRACE_OPTION_KEY, false) == true
end

local function readDebugLogView(mod)
  return readSaveFlag(mod, DEBUG_LOG_VIEW_OPTION_KEY, "both")
end

local function readDebugCategoryMask(mod)
  return {
    lifecycle = readSaveFlag(mod, DEBUG_LOG_LIFECYCLE_OPTION_KEY, true) == true,
    behavior = readSaveFlag(mod, DEBUG_LOG_BEHAVIOR_OPTION_KEY, true) == true,
    relationships = readSaveFlag(mod, DEBUG_LOG_RELATIONSHIPS_OPTION_KEY, false) == true,
    generation = readSaveFlag(mod, DEBUG_LOG_GENERATION_OPTION_KEY, false) == true
  }
end

local function shouldCaptureDebugCategory(mod, category)
  local mask = readDebugCategoryMask(mod)
  return mask[category] == true
end

-- Accumulated in memory and flushed to mod.storage:writeBytes, NOT printed
-- to the console: two separate attempts at print()/mod.log-based console
-- mirroring both froze/crashed the game on zone entry (a burst of log
-- calls), and batching the print() calls did not fix it either -- pointing
-- at print()/console I/O itself as the unsafe mechanism (e.g. a blocked,
-- undrained stdout pipe when no console reader is attached), not just call
-- volume. mod.storage:writeBytes is a documented, staged/byte-verified
-- write through the engine's own persistence backend -- no console, no
-- pipes, no print() at all -- landing in a real file under the LOVE save
-- directory (e.g. on Windows, under %APPDATA%\love\pokemon-love2d\) that
-- can be opened directly in any text editor.
local CONSOLE_LOG_TEXT_LIMIT = 200000 -- ~200 KB ceiling on the accumulated log
local CONSOLE_LOG_FLUSH_INTERVAL_TICKS = 30 -- avoid a disk write every single tick
local consoleLogText = ""
local consoleLogDirty = false
local consoleLogLastFlushTick = nil
local queueConsoleLog

local function resetConsoleLogEpoch(mod, enabled)
  consoleLogText = ""
  consoleLogDirty = false
  consoleLogLastFlushTick = nil
  if enabled then
    local state = Save and Save.getState and Save.getState() or nil
    local tick = state and state.simulationTick or 0
    queueConsoleLog("lifecycle", string.format(
      "AUDIT_EPOCH_START tick=%s auditEpochStartTick=%s",
      tostring(tick), tostring(tick)))
  end
end

queueConsoleLog = function(category, message)
  consoleLogText = consoleLogText .. string.format("[%s] %s\n", tostring(category), tostring(message))
  if #consoleLogText > CONSOLE_LOG_TEXT_LIMIT then
    -- Keep the newest data, drop the oldest, so the file stays bounded
    -- without ever needing to stop logging.
    consoleLogText = consoleLogText:sub(-CONSOLE_LOG_TEXT_LIMIT)
  end
  consoleLogDirty = true
end

local function flushConsoleQueue(mod)
  if not consoleLogDirty then
    return
  end
  local state = Save and Save.getState and Save.getState() or nil
  local tick = state and state.simulationTick or 0
  if consoleLogLastFlushTick and (tick - consoleLogLastFlushTick) < CONSOLE_LOG_FLUSH_INTERVAL_TICKS then
    return
  end
  local game = mod and mod.game
  if not (mod and mod.storage and mod.storage.writeBytes and game) then
    return
  end
  local ok = pcall(mod.storage.writeBytes, mod.storage, game, "wildecology_log", consoleLogText)
  if ok then
    consoleLogDirty = false
    consoleLogLastFlushTick = tick
  end
end

local function flushRelationshipAudit(mod, force)
  if not WildEcology.relationshipAudit then return end
  local state = Save and Save.getState and Save.getState() or nil
  WildEcology.relationshipAudit:flush(
    state and state.simulationTick or 0, force == true)
end

local function setRelationshipAuditEnabled(mod, enabled)
  if enabled then
    if WildEcology.relationshipAudit then return end
    local auditConfig = Config.relationshipAudit or {}
    local state = Save and Save.getState and Save.getState() or nil
    WildEcology.relationshipAudit = RelationshipAudit.new({
      maxBytes = auditConfig.maxBytes,
      flushIntervalTicks = auditConfig.flushIntervalTicks,
      storageKey = auditConfig.storageKey,
      epochStartTick = state and state.simulationTick or 0,
      writer = function(storageKey, bytes)
        local game = mod and mod.game
        if not (mod and mod.storage and mod.storage.writeBytes and game) then
          error("relationship audit storage unavailable")
        end
        local result = mod.storage:writeBytes(game, storageKey, bytes)
        if result == false then error("relationship audit write failed") end
      end
    })
    flushRelationshipAudit(mod, true)
    return
  end
  flushRelationshipAudit(mod, true)
  WildEcology.relationshipAudit = nil
end

local function flushAgentAudit(mod, force)
  if not WildEcology.agentAudit then return end
  local state = Save and Save.getState and Save.getState() or nil
  WildEcology.agentAudit:flush(
    state and state.simulationTick or 0, force == true)
end

local function setAgentAuditEnabled(mod, enabled)
  if enabled then
    if WildEcology.agentAudit then return end
    local config = Config.agentAudit or {}
    local state = Save and Save.getState and Save.getState() or nil
    WildEcology.agentAudit = AgentAudit.new({
      maxBytes = config.maxBytes,
      flushIntervalTicks = config.flushIntervalTicks,
      separationTicks = config.separationTicks,
      contactSampleTicks = config.contactSampleTicks,
      historySamples = config.historySamples,
      postSamples = config.postSamples,
      periodicTicks = config.periodicTicks,
      storageKey = config.storageKey,
      epochStartTick = state and state.simulationTick or 0,
      contextProvider = function(mutation)
        return buildAgentAuditContext and buildAgentAuditContext(mutation) or {}
      end,
      forensicEnabled = function()
        return readBehaviorTraceEnabled(mod)
      end,
      writer = function(storageKey, bytes)
        local game = mod and mod.game
        if not (mod and mod.storage and mod.storage.writeBytes and game) then
          error("agent audit storage unavailable")
        end
        local result = mod.storage:writeBytes(game, storageKey, bytes)
        if result == false then error("agent audit write failed") end
      end
    })
    flushAgentAudit(mod, true)
    return
  end
  flushAgentAudit(mod, true)
  WildEcology.agentAudit = nil
end

local function writeDebugLog(mod, category, message)
  if not DebugLogger or not shouldCaptureDebugCategory(mod, category) then
    return nil
  end
  performanceCount("log_records")

  if readSaveFlag(mod, DEBUG_LOG_CONSOLE_OPTION_KEY, false) == true then
    queueConsoleLog(category, message)
  end

  return DebugLogger.log(category, message)
end

local function firstEvidence(values)
  local firstId, firstValue
  for id, value in pairs(values or {}) do
    if firstId == nil or tostring(id) < tostring(firstId) then
      firstId, firstValue = id, value
    end
  end
  return firstId, firstValue
end

local function entityBlockDiagnostic(mod, event)
  if not event or not readPhase5DiagnosticsEnabled(mod) then return end
  local anchorId = Config and Config.phase0 and Config.phase0.testEntityId or nil
  local focusedId = WildEcology.focusedEntityId or anchorId
  if focusedId ~= nil and event.actorId ~= focusedId then return end
  local actor = WildEcology.entityById[event.actorId]
  local runtime = actor and actor.runtimeState or {}
  local request = event.request or runtime.movementRequest or {}
  local source = event.source or {
    cellX = request.sourceX,
    cellY = request.sourceY
  }
  local destination = event.destination or {
    cellX = request.destinationX,
    cellY = request.destinationY
  }
  local occupancy = event.occupancy or {}
  local occupantId, occupant = firstEvidence(occupancy.currentOccupants)
  local reservationId, reservation = firstEvidence(occupancy.destinationReservations)
  local stockBlockers = request.stockEntityBlockers or event.stockEntityBlockers or {}
  local stockBlocker = stockBlockers[1]
  local blockerId = event.blockerId or request.blockerId
    or stockBlocker and stockBlocker.id or occupantId
  local claimOwnerId = request.claimConflictActorId or reservationId
  local blockerEntity = blockerId and WildEcology.entityById[blockerId] or nil
  local blockerAvatar = blockerId and WildEcology.activeAvatars[blockerId] or nil
  local blockerPosition = blockerAvatar and buildPositionEntity(blockerAvatar) or nil
  local blockerRuntime = blockerEntity and blockerEntity.runtimeState or nil
  local blockerMotion = blockerRuntime and blockerRuntime.motion or nil
  local blockerClaim = blockerId and WildEcology.movementClaims
    and WildEcology.movementClaims:claimForActor(blockerId) or nil
  local targetId = runtime.targetEntityId
  local targetAvatar = targetId and WildEcology.activeAvatars[targetId] or nil
  local targetPosition = targetAvatar and buildPositionEntity(targetAvatar) or nil
  local destinationIsTargetCell = targetPosition and destination
    and targetPosition.cellX == destination.cellX
    and targetPosition.cellY == destination.cellY or false
  local liveOccupant = stockBlocker ~= nil or occupantId ~= nil
  local validReservation = claimOwnerId ~= nil or reservationId ~= nil
  local falseBlock = request.falseEntityBlock == true
    or event.layer == "PLANNER_OCCUPANCY"
      and not liveOccupant and not validReservation
  local layer = event.layer or request.blockingLayer or "OTHER"
  local signature = table.concat({
    tostring(event.actorId), tostring(source and source.cellX),
    tostring(source and source.cellY), tostring(destination and destination.cellX),
    tostring(destination and destination.cellY), tostring(layer),
    tostring(blockerId or "none"), tostring(claimOwnerId or "none"),
    tostring(falseBlock)
  }, ":")
  if runtime.lastEntityBlockDiagnosticSignature == signature then return end
  runtime.lastEntityBlockDiagnosticSignature = signature
  writeDebugLog(mod, "behavior", string.format(
    "ENTITY_BLOCK_DIAGNOSTIC tick=%s actor=%s layer=%s from=%s,%s to=%s,%s blocker=%s claimOwner=%s target=%s destinationIsTargetCell=%s persistent=%s materialized=%s runtime=%s blockerMap=%s blockerCell=%s,%s blockerMoving=%s blockerDestination=%s,%s claim=%s occupancyKind=%s stockMatches=%s false=%s",
    tostring(runtime.simulationTick or "none"), tostring(event.actorId),
    tostring(layer), tostring(source and source.cellX or "none"),
    tostring(source and source.cellY or "none"),
    tostring(destination and destination.cellX or "none"),
    tostring(destination and destination.cellY or "none"),
    tostring(blockerId or "none"), tostring(claimOwnerId or "none"),
    tostring(targetId or "none"), tostring(destinationIsTargetCell),
    tostring(blockerEntity ~= nil), tostring(blockerAvatar ~= nil),
    tostring(blockerRuntime ~= nil),
    tostring(blockerAvatar and blockerAvatar.mapId
      or blockerEntity and blockerEntity.home and blockerEntity.home.mapId or "none"),
    tostring(blockerPosition and blockerPosition.cellX
      or stockBlocker and stockBlocker.cellX or "none"),
    tostring(blockerPosition and blockerPosition.cellY
      or stockBlocker and stockBlocker.cellY or "none"),
    tostring(blockerMotion and blockerMotion.active == true
      or stockBlocker and stockBlocker.moving == true or false),
    tostring(blockerMotion and blockerMotion.destinationX
      or stockBlocker and stockBlocker.targetX or "none"),
    tostring(blockerMotion and blockerMotion.destinationY
      or stockBlocker and stockBlocker.targetY or "none"),
    tostring(blockerClaim and table.concat({ blockerClaim.fromX,
      blockerClaim.fromY, blockerClaim.toX, blockerClaim.toY }, ",") or "none"),
    tostring(occupant and "LIVE_ENTITY_SCAN"
      or reservation and "QUEUED_REQUEST_RESERVATION" or "none"),
    tostring(#stockBlockers), tostring(falseBlock)
  ))
  if falseBlock then
    writeDebugLog(mod, "behavior", string.format(
      "FALSE_ENTITY_BLOCK tick=%s actor=%s layer=%s from=%s,%s to=%s,%s blocker=%s claimOwner=%s stockMatches=%s liveOccupant=%s validReservation=%s",
      tostring(runtime.simulationTick or "none"), tostring(event.actorId),
      tostring(layer), tostring(source and source.cellX or "none"),
      tostring(source and source.cellY or "none"),
      tostring(destination and destination.cellX or "none"),
      tostring(destination and destination.cellY or "none"),
      tostring(blockerId or "none"), tostring(claimOwnerId or "none"),
      tostring(#stockBlockers), tostring(liveOccupant),
      tostring(validReservation)))
  end
end

local INVESTIGATE_STALL_TICKS = 180

local function investigateRuntimeDiagnostic(mod, entity, context, simulationTick)
  if not readPhase5DiagnosticsEnabled(mod) then return end
  local runtime = entity.runtimeState or {}
  local episode = runtime.intentEpisode or {}
  if runtime.state ~= "INVESTIGATE" or episode.intent ~= "INVESTIGATE"
    or episode.status ~= "ACTIVE" then
    runtime.lastInvestigateStallSignature = nil
    runtime.lastInvestigateDeadlockSignature = nil
    return
  end
  local targetId = episode.targetId or runtime.targetEntityId
  local targetPosition = targetId and context.targetPositions
    and context.targetPositions[targetId] or nil
  local distance = Utility.chebyshevDistance(context.position, targetPosition)
  local radius = context.investigateRadius or 3
  local noProgressAge = episode.lastProgressTick
    and math.max(0, simulationTick - episode.lastProgressTick) or 0
  local request = runtime.movementRequest or {}
  local navigation = runtime.navigation or {}
  local base = string.format(
    "tick=%s actor=%s episodeStart=%s target=%s targetValid=%s self=%s,%s targetCell=%s,%s distance=%s radius=%s lastProgressTick=%s noProgressAge=%s motion=%s request=%s/%s rejection=%s blockingLayer=%s blocker=%s routeSuspended=%s blockedCell=%s occupancyReason=%s",
    tostring(simulationTick), tostring(entity.id),
    tostring(episode.startedTick or "none"), tostring(targetId or "none"),
    tostring(targetPosition ~= nil and context.hasTarget == true),
    tostring(context.position and context.position.cellX or "none"),
    tostring(context.position and context.position.cellY or "none"),
    tostring(targetPosition and targetPosition.cellX or "none"),
    tostring(targetPosition and targetPosition.cellY or "none"),
    tostring(distance or "none"), tostring(radius),
    tostring(episode.lastProgressTick or "none"), tostring(noProgressAge),
    tostring(runtime.motion and runtime.motion.active == true),
    tostring(request.direction or "none"),
    tostring(request.traversalMode or "none"),
    tostring(request.rejectionReason or "none"),
    tostring(request.blockingLayer or "none"),
    tostring(request.blockerId or request.claimConflictActorId or "none"),
    tostring(navigation.routeSuspended == true),
    tostring(navigation.blockedCell or "none"),
    tostring(navigation.occupancyReason or "none"))
  if distance ~= nil and distance <= radius then
    local signature = table.concat({
      tostring(episode.startedTick), tostring(targetId), tostring(distance),
      tostring(radius), tostring(episode.status)
    }, ":")
    if runtime.lastInvestigateDeadlockSignature ~= signature then
      runtime.lastInvestigateDeadlockSignature = signature
      writeDebugLog(mod, "behavior",
        "INVESTIGATE_SATISFACTION_DEADLOCK " .. base)
    end
  else
    runtime.lastInvestigateDeadlockSignature = nil
  end
  if noProgressAge >= INVESTIGATE_STALL_TICKS then
    local signature = table.concat({
      tostring(episode.startedTick), tostring(targetId),
      tostring(episode.lastProgressTick), tostring(context.position and context.position.cellX),
      tostring(context.position and context.position.cellY),
      tostring(request.blockingLayer or request.rejectionReason or "none"),
      tostring(request.blockerId or request.claimConflictActorId or "none")
    }, ":")
    if runtime.lastInvestigateStallSignature ~= signature then
      runtime.lastInvestigateStallSignature = signature
      writeDebugLog(mod, "behavior", "INVESTIGATE_STALL " .. base)
    end
  else
    runtime.lastInvestigateStallSignature = nil
  end
end

local function writeHomeostasisWindowSummary(mod, summary)
  if not readPhase5DiagnosticsEnabled(mod) or not summary then return end
  local byBehavior = summary.ticksByBehavior or {}
  writeDebugLog(mod, "behavior", string.format(
    "HOMEOSTASIS_WINDOW_SUMMARY actor=%s startTick=%s endTick=%s ticksObserved=%s ticksSettled=%s SETTLED=%s TARGET=%s APPROACH=%s INVESTIGATE=%s SEEK_FLOCK=%s FLEE=%s IDLE=%s REST=%s ALERT=%s purposefulEpisodesStarted=%s purposefulEpisodesCompleted=%s purposefulToPurposefulTransitions=%s settledEntries=%s settledExits=%s averageSettledDuration=%.2f longestSettledDuration=%s wanderCompletions=%s investigationCompletions=%s approachCompletions=%s flockCompletions=%s interruptionsByThreat=%s",
    tostring(summary.actorId), tostring(summary.startTick),
    tostring(summary.endTick), tostring(summary.ticksObserved),
    tostring(summary.ticksSettled), tostring(byBehavior.SETTLED or 0),
    tostring(byBehavior.TARGET or 0), tostring(byBehavior.APPROACH or 0),
    tostring(byBehavior.INVESTIGATE or 0),
    tostring(byBehavior.SEEK_FLOCK or 0), tostring(byBehavior.FLEE or 0),
    tostring(byBehavior.IDLE or 0), tostring(byBehavior.REST or 0),
    tostring(byBehavior.ALERT or 0),
    tostring(summary.purposefulEpisodesStarted),
    tostring(summary.purposefulEpisodesCompleted),
    tostring(summary.purposefulToPurposefulTransitions),
    tostring(summary.settledEntries), tostring(summary.settledExits),
    summary.averageSettledDuration or 0,
    tostring(summary.longestSettledDuration),
    tostring(summary.wanderCompletions),
    tostring(summary.investigationCompletions),
    tostring(summary.approachCompletions),
    tostring(summary.flockCompletions),
    tostring(summary.interruptionsByThreat)))
end

local function writeSpawnGenerationDiagnostic(mod, message)
  if readSaveFlag(mod, DEBUG_LOG_CONSOLE_OPTION_KEY, false) == true then
    queueConsoleLog("generation", message)
  end
  if DebugLogger and shouldCaptureDebugCategory(mod, "generation") then
    return DebugLogger.log("generation", message)
  end
  return nil
end

local function appendWrappedLine(lines, text, maxWidth, maxLines)
  if maxLines and #lines >= maxLines then
    return
  end

  local remaining = tostring(text or "")
  if remaining == "" then
    if not maxLines or #lines < maxLines then
      lines[#lines + 1] = ""
    end
    return
  end

  while #remaining > maxWidth do
    if maxLines and #lines >= maxLines then
      return
    end
    lines[#lines + 1] = remaining:sub(1, maxWidth)
    remaining = remaining:sub(maxWidth + 1)
  end
  if not maxLines or #lines < maxLines then
    lines[#lines + 1] = remaining
  end
end

local function appendField(lines, label, value, maxWidth, maxLines)
  if maxLines and #lines >= maxLines then
    return
  end

  local rendered = label .. tostring(value or "none")
  if #rendered <= maxWidth then
    lines[#lines + 1] = rendered
    return
  end

  lines[#lines + 1] = label
  appendWrappedLine(lines, value or "none", maxWidth, maxLines)
end

local function enabledCategorySummary(categoryMask)
  local labels = {}
  if categoryMask.lifecycle then
    labels[#labels + 1] = "LIFECYCLE"
  end
  if categoryMask.behavior then
    labels[#labels + 1] = "BEHAVIOR"
  end
  if categoryMask.relationships then
    labels[#labels + 1] = "RELATIONSHIPS"
  end
  if categoryMask.generation then
    labels[#labels + 1] = "GENERATION"
  end

  if #labels == 0 then
    return "NONE"
  end

  return table.concat(labels, ", ")
end

local function formatBehaviorScores(scores)
  if type(scores) ~= "table" then
    return "none"
  end

  local names = {}
  for name in pairs(scores) do
    names[#names + 1] = name
  end
  table.sort(names)

  local rendered = {}
  for _, name in ipairs(names) do
    rendered[#rendered + 1] = string.format("%s=%.1f", name, scores[name] or 0)
  end
  return table.concat(rendered, ",")
end

local function relationshipSnapshotForEntity(entity, limit)
  local entries = {}
  local count = 0
  for targetId, relationship in pairs(entity and entity.relationships or {}) do
    count = count + 1
    entries[#entries + 1] = {
      targetId = targetId,
      familiarity = relationship.familiarity or 0,
      trust = relationship.trust or 0,
      affinity = relationship.affinity or 0,
      threatMemory = relationship.threatMemory or 0,
      directThreatMemory = relationship.directThreatMemory or 0,
      hostility = relationship.hostility or 0,
      lastSeenTick = relationship.lastSeenTick or 0,
      importance = relationship.importance or 0
    }
  end
  table.sort(entries, function(left, right)
    if left.importance ~= right.importance then
      return left.importance > right.importance
    end
    if left.lastSeenTick ~= right.lastSeenTick then
      return left.lastSeenTick > right.lastSeenTick
    end
    return tostring(left.targetId) < tostring(right.targetId)
  end)
  local bounded = {}
  for index = 1, math.min(#entries, limit or 8) do
    bounded[index] = entries[index]
  end
  return { relationshipCount = count, relationships = bounded }
end

local function focusedDebugState()
  local base = getPhase0DebugState()
  local focusedId = WildEcology.focusedEntityId
  if not focusedId or not Save or not Save.getState then
    return base
  end

  local state = Save.getState()
  local entity = nil
  for _, population in pairs(state and state.populations or {}) do
    entity = population.members and population.members[focusedId]
    if entity then break end
  end
  if not entity then
    return base
  end

  local snapshot = {}
  for key, value in pairs(base or {}) do snapshot[key] = value end
  local runtime = entity.runtimeState or {}
  local relationship = entity.relationships and entity.relationships.player or {}
  local avatar = WildEcology.activeAvatars[focusedId]
  local position = buildPositionEntity(avatar)
  snapshot.lastEntityId = focusedId
  snapshot.lastState = runtime.state or "unknown"
  snapshot.lastIntent = runtime.intent or snapshot.lastState
  snapshot.lastTargetEntityId = runtime.targetEntityId
  snapshot.lastTargetDestinationId = runtime.targetDestination and runtime.targetDestination.id or nil
  snapshot.lastBehaviorScores = runtime.behaviorScores
  snapshot.lastTrust = relationship.trust or 0
  snapshot.lastThreatMemory = relationship.threatMemory or 0
  local relationshipSnapshot = relationshipSnapshotForEntity(entity, 8)
  snapshot.relationshipCount = relationshipSnapshot.relationshipCount
  snapshot.relationships = relationshipSnapshot.relationships
  snapshot.lastPlayerDistance = getDistanceToPlayer(WildEcology.mod, avatar)
  local livePlayerPosition = perceptionPositionForPlayer(WildEcology.mod)
  snapshot.lastSelfCell = position and string.format("%s,%s", tostring(position.cellX), tostring(position.cellY)) or "none"
  snapshot.lastPlayerCell = livePlayerPosition and string.format("%s,%s", tostring(livePlayerPosition.cellX), tostring(livePlayerPosition.cellY)) or "none"
  snapshot.lastMotionActive = runtime.motion and runtime.motion.active or false
  -- Diagnosing "FLEE never moves": which single direction Steering picked
  -- this tick, why a movement got rejected (tile/bounds/entity/API), and
  -- which directions are currently remembered as blocked at this cell (only
  -- tile/bounds rejections persist -- see avatar_factory.lua's
  -- applyMovementRequest -- so a fully boxed-in cell shows all 4 here).
  local movementRequest = runtime.movementRequest
  snapshot.lastMovementDirection = movementRequest and movementRequest.direction or "none"
  snapshot.lastMovementRejectionReason = movementRequest and movementRequest.rejectionReason or "none"
  local blockedDirections = {}
  for direction in pairs(runtime.rejectedMoves or {}) do
    blockedDirections[#blockedDirections + 1] = direction
  end
  table.sort(blockedDirections)
  snapshot.lastBlockedDirections = #blockedDirections > 0 and table.concat(blockedDirections, ",") or "none"
  local fleeExecution = runtime.fleeExecution or {}
  snapshot.lastFleeMode = fleeExecution.fleeMode or (runtime.state == "FLEE" and "NORMAL" or "none")
  snapshot.lastFleeStuckReason = fleeExecution.stuckReason or "none"
  snapshot.lastEscapeRouteLength = fleeExecution.escapeRouteLength or 0
  snapshot.lastEscapeRouteIndex = fleeExecution.route and fleeExecution.route.index or 0
  snapshot.lastEscapeEndpoint = fleeExecution.escapeEndpoint
    and string.format("%s,%s", tostring(fleeExecution.escapeEndpoint.cellX), tostring(fleeExecution.escapeEndpoint.cellY)) or "none"
  snapshot.lastEndpointThreatDistance = fleeExecution.endpointThreatDistance or "none"
  snapshot.lastEndpointMobility = fleeExecution.endpointMobility or "none"
  snapshot.lastNextStepThreatDelta = fleeExecution.nextStepThreatDelta or "none"
  snapshot.lastTemporaryThreatRegression = fleeExecution.temporaryThreatRegression == true
  snapshot.lastRouteInvalidationReason = fleeExecution.routeInvalidationReason or "none"
  local fleeCandidates = {}
  for _, candidate in ipairs(fleeExecution.localCandidates or {}) do
    fleeCandidates[#fleeCandidates + 1] = string.format(
      "%s:%s/%s d=%s r=%s rev=%s rej=%s",
      tostring(candidate.direction),
      candidate.staticLegal and "S" or "X",
      candidate.occupied and "O" or "-",
      tostring(candidate.threatDelta),
      tostring(candidate.recentCellPenalty or 0),
      tostring(candidate.immediateReversalPenalty == true),
      tostring(candidate.rejected == true)
    )
  end
  snapshot.lastFleeCandidates = #fleeCandidates > 0 and table.concat(fleeCandidates, " ") or "none"
  snapshot.lastPhase5Diagnostic = string.format(
    "self=%s,%s target=%s,%s dx=%s dy=%s man=%s cheb=%s goal=%s/%s %s sat=%s motion=%s",
    tostring(runtime.goalSelfPosition and runtime.goalSelfPosition.cellX or position and position.cellX or "none"),
    tostring(runtime.goalSelfPosition and runtime.goalSelfPosition.cellY or position and position.cellY or "none"),
    tostring(runtime.goalTargetPosition and runtime.goalTargetPosition.cellX or "none"),
    tostring(runtime.goalTargetPosition and runtime.goalTargetPosition.cellY or "none"),
    tostring(runtime.goalDx or "none"), tostring(runtime.goalDy or "none"),
    tostring(runtime.goalManhattan or "none"), tostring(runtime.goalChebyshev or "none"),
    tostring(runtime.spatialGoal and runtime.spatialGoal.minRange or "none"),
    tostring(runtime.spatialGoal and runtime.spatialGoal.maxRange or "none"),
    tostring(runtime.spatialGoal and runtime.spatialGoal.alignment or "none"),
    tostring(runtime.goalSatisfied == true), tostring(snapshot.lastMotionActive)
  )
  return snapshot
end

function WildEcology.getFocusedRelationshipSnapshot(limit)
  local focusedId = WildEcology.focusedEntityId
  if not focusedId or not Save or not Save.getState then
    return { relationshipCount = 0, relationships = {} }
  end
  local state = Save.getState()
  for _, population in pairs(state and state.populations or {}) do
    local entity = population.members and population.members[focusedId]
    if entity then
      return relationshipSnapshotForEntity(entity, limit)
    end
  end
  return { relationshipCount = 0, relationships = {} }
end

function WildEcology.getRelationshipAuditSnapshot()
  if not WildEcology.relationshipAudit then return nil end
  return WildEcology.relationshipAudit:snapshot()
end

function WildEcology.getAgentAuditSnapshot()
  if not WildEcology.agentAudit then return nil end
  return WildEcology.agentAudit:snapshot()
end

local function pointerWorldCell(mod, event)
  local px = event and (event.gameX or event.x)
  local py = event and (event.gameY or event.y)
  if type(px) ~= "number" or type(py) ~= "number" then
    return nil, nil
  end

  local game = mod and mod.game
  local overworld = game and game.overworld
  local camera = overworld and overworld.camera
  local renderer = game and game.renderer
  if camera and type(camera.x) == "number" and type(camera.y) == "number" and renderer then
    local scale = nil
    local okZoom, Zoom = pcall(require, "src.render.Zoom")
    if type(renderer.fitScale) == "function" then
      local okScale, fitScale = pcall(renderer.fitScale, renderer)
      if okScale and type(fitScale) == "number" then
        scale = fitScale
        if okZoom and Zoom and type(Zoom.scale) == "function" then
          scale = Zoom.scale(fitScale)
        end
      end
    end
    if scale and scale > 0 then
      return math.floor((camera.x + px / scale) / 16), math.floor((camera.y + py / scale) / 16)
    end
  end

  local playerPosition = perceptionPositionForPlayer(mod)
  if not playerPosition then
    return math.floor(px / 16), math.floor(py / 16)
  end

  -- Gen I's camera centers the player in the 160x144 game viewport while
  -- the pointer hook reports viewport-local pixels.
  local worldPixelX = playerPosition.cellX * 16 + (px - 80)
  local worldPixelY = playerPosition.cellY * 16 + (py - 72)
  return math.floor(worldPixelX / 16), math.floor(worldPixelY / 16)
end

local function pointerLocalCell(event)
  local px = event and (event.gameX or event.x)
  local py = event and (event.gameY or event.y)
  if type(px) ~= "number" or type(py) ~= "number" then
    return nil, nil
  end
  return math.floor(px / 16), math.floor(py / 16)
end

local function buildDebugLines(maxWidth, maxLines)
  performanceCount("hud_builds")
  local profileName, profileStart = performanceStart("hud")
  local debugState = focusedDebugState() or {}
  maxWidth = maxWidth or 18
  maxLines = maxLines or 16
  local lines = { "SPAWN DEBUG build=" .. SPAWN_DEBUG_BUILD }
  local spawnDebug = WildEcology.getSpawnDebugSnapshot and WildEcology.getSpawnDebugSnapshot() or nil
  local worldInputs = WildEcology.getWorldInputDebugSnapshot
    and WildEcology.getWorldInputDebugSnapshot()
    or nil
  local currentProbe = worldInputs and worldInputs.current or nil
  local topologyProbe = currentProbe and currentProbe.topologyProbe or nil
  local analysis = spawnDebug and spawnDebug.candidateAnalysis or nil
  local runtime = WildEcology.spawnDiagnostics
  local initialization = spawnDebug and spawnDebug.spawnInitialization or nil
  local function available(value)
    return value == nil and "N/A" or tostring(value)
  end
  local function exact(value)
    if value == nil then return "nil" end
    if type(value) == "string" then return value end
    return tostring(value)
  end
  local function yesNo(value)
    return value and "yes" or "no"
  end
  appendWrappedLine(lines, string.format(
    "WORLD INPUTS mapOverviewStatus=%s semanticsReason=%s currentSemanticsProbe=%s lastProductionSemanticsStatus=%s map=%s ecologyEnabled=%s populationMap=%s environment=%s candidateStatus=%s attempts=%s valid=%s rejected=%s",
    available(currentProbe and currentProbe.mapOverviewStatus),
    available(currentProbe and currentProbe.semanticsReason),
    available(worldInputs and worldInputs.currentSemanticsProbe),
    available(worldInputs and worldInputs.lastProductionSemanticsStatus),
    available(spawnDebug and spawnDebug.mapId),
    yesNo(spawnDebug and spawnDebug.ecologyEnabled),
    available(spawnDebug and spawnDebug.populationMap),
    available(analysis and analysis.environmentClass),
    available(spawnDebug and spawnDebug.candidateStatus),
    tostring(runtime.materializationAttempts),
    tostring(runtime.materializationValid),
    tostring(runtime.materializationRejected)
  ), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("overviewMapId=%s overviewWidth=%s overviewHeight=%s overviewRows=%s", available(currentProbe and currentProbe.overviewMapId), available(currentProbe and currentProbe.overviewWidth), available(currentProbe and currentProbe.overviewHeight), available(currentProbe and currentProbe.overviewRows)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("modGame=%s worldGame=%s stack=%s overworld=%s runtimeMap=%s mapDef=%s", yesNo(topologyProbe and topologyProbe.modGame), yesNo(topologyProbe and topologyProbe.worldGame), yesNo(topologyProbe and topologyProbe.stack), yesNo(topologyProbe and topologyProbe.overworld), yesNo(topologyProbe and topologyProbe.runtimeMap), yesNo(topologyProbe and topologyProbe.mapDef)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("gameData=%s dataMaps=%s dataTilesets=%s mapModule=%s", yesNo(topologyProbe and topologyProbe.gameData), yesNo(topologyProbe and topologyProbe.dataMaps), yesNo(topologyProbe and topologyProbe.dataTilesets), available(topologyProbe and topologyProbe.mapModuleStatus)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("topologyStatus=%s topologyReason=%s topologyMapId=%s", available(currentProbe and currentProbe.topologyStatus), available(currentProbe and currentProbe.topologyReason), available(currentProbe and currentProbe.topologyMapId)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("semanticsStatus=%s semanticsReason=%s", available(currentProbe and currentProbe.semanticsStatus), available(currentProbe and currentProbe.semanticsReason)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("currentSemanticsProbe=%s lastProductionSemanticsStatus=%s lastProductionSemanticsReason=%s", available(worldInputs and worldInputs.currentSemanticsProbe), available(worldInputs and worldInputs.lastProductionSemanticsStatus), available(worldInputs and worldInputs.lastProductionSemanticsReason)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("spawnInitializationStatus=%s reason=%s generation=%s attempts=%s", available(initialization and initialization.status), available(initialization and initialization.reason), available(initialization and initialization.semanticsGeneration), available(initialization and initialization.attempts)), maxWidth, maxLines)
  if initialization and initialization.lastError then
    appendWrappedLine(lines, "spawnInitializationError=" .. tostring(initialization.lastError), maxWidth, maxLines)
  end
  appendWrappedLine(lines, string.format("map=%s ecologyEnabled=%s populationMap=%s environment=%s", available(spawnDebug and spawnDebug.mapId), yesNo(spawnDebug and spawnDebug.ecologyEnabled), available(spawnDebug and spawnDebug.populationMap), available(analysis and analysis.environmentClass)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("semanticsStatus=%s candidateStatus=%s", available(spawnDebug and spawnDebug.semanticsStatus), available(spawnDebug and spawnDebug.candidateStatus)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("semanticsGeneration=%s candidateAnalysisRuns=%s", available(analysis and analysis.semanticsGeneration), available(spawnDebug and spawnDebug.candidateAnalysisRuns)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("rawWalkable=%s landingValid=%s", available(analysis and analysis.rawWalkable), available(analysis and analysis.landingValid)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("spawnSemanticAllowed=%s connectionSourceRejected=%s", available(analysis and analysis.spawnSemanticAllowed), available(analysis and analysis.connectionSourceRejected)), maxWidth, maxLines)
  local rawPlayerCell = analysis and analysis.rawPlayerCell
  local componentSeedCell = analysis and analysis.componentSeedCell
  appendWrappedLine(lines, string.format("rawPlayerCell=%s componentSeedCell=%s", rawPlayerCell and string.format("%s,%s", tostring(rawPlayerCell.cellX), tostring(rawPlayerCell.cellY)) or "N/A", componentSeedCell and string.format("%s,%s", tostring(componentSeedCell.cellX), tostring(componentSeedCell.cellY)) or "N/A"), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("componentSeedSource=%s componentSeedDirection=%s componentSeedReason=%s", available(analysis and analysis.componentSeedSource), available(analysis and analysis.componentSeedDirection), available(analysis and analysis.playableComponentReason)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("playableComponentId=%s playableComponentStatus=%s playableComponentCells=%s", available(analysis and analysis.playableComponentId), available(analysis and analysis.playableComponentStatus), available(analysis and analysis.playableComponentCells)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("walkComponentCount=%s exitConnectedComponents=%s spawnRejectedOutsidePlayableComponent=%s", available(analysis and analysis.walkComponentCount), available(analysis and analysis.exitConnectedComponentCount), available(analysis and analysis.spawnRejectedOutsidePlayableComponent)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("connectivityAccepted=%s connectivityRejected=%s finalCandidates=%s", available(analysis and analysis.connectivityAccepted), available(analysis and analysis.connectivityRejected), available(analysis and analysis.finalCandidateCount)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("stockConnections=%s resolvedConnections=%s overworldExits=%s usableOverworldExits=%s", available(analysis and analysis.stockConnectionCount), available(analysis and analysis.resolvedConnectionCount), available(analysis and analysis.overworldExitCount), available(analysis and analysis.usableOverworldExitCount)), maxWidth, maxLines)
  for _, connection in ipairs(analysis and analysis.connectionSummaries or {}) do
    appendWrappedLine(lines, string.format("%s -> %s resolved=%s usableSources=%s reason=%s", string.upper(tostring(connection.direction or "?")):sub(1, 1), tostring(connection.destinationMapId or "?"), connection.resolved and "yes" or "no", tostring(connection.usableSourceCount or 0), tostring(connection.resolutionReason or "N/A")), maxWidth, maxLines)
  end
  local candidateSamples = {}
  local finalCandidates = analysis and analysis.finalCandidates or {}
  for index = 1, math.min(5, #finalCandidates) do
    local cell = finalCandidates[index]
    candidateSamples[#candidateSamples + 1] = string.format("(%s,%s)", tostring(cell.x), tostring(cell.y))
  end
  appendWrappedLine(lines, "candidates: " .. (#candidateSamples > 0 and table.concat(candidateSamples, " ") or "NONE"), maxWidth, maxLines)
  for _, sample in ipairs(analysis and analysis.outsidePlayableSamples or {}) do
    appendWrappedLine(lines, string.format("outsidePlayable=(%s,%s)", tostring(sample.x), tostring(sample.y)), maxWidth, maxLines)
  end
  if analysis and analysis.finalCandidateCount == 0 and analysis.spawnSemanticAllowed > 0 then
    for _, sample in ipairs(analysis.connectivityFailureSamples or {}) do
      appendWrappedLine(lines, string.format("(%s,%s): %s", tostring(sample.x), tostring(sample.y), tostring(sample.reason)), maxWidth, maxLines)
    end
  end
  appendWrappedLine(lines, string.format("populationRecords=%s withHome=%s withoutHome=%s assignmentStatus=%s", available(spawnDebug and spawnDebug.populationRecords), available(spawnDebug and spawnDebug.homesAssigned), available(spawnDebug and spawnDebug.homesMissing), available(spawnDebug and spawnDebug.assignmentStatus)), maxWidth, maxLines)
  local populationSamples = {}
  for _, sample in ipairs(spawnDebug and spawnDebug.populationSamples or {}) do
    local serial = tostring(sample.id or "?"):match("([^:]+)$") or tostring(sample.id or "?")
    local home = sample.x ~= nil and sample.y ~= nil
      and string.format("(%s,%s)", tostring(sample.x), tostring(sample.y)) or "NONE"
    populationSamples[#populationSamples + 1] = serial .. " home=" .. home
  end
  appendWrappedLine(lines, "records: " .. (#populationSamples > 0 and table.concat(populationSamples, " ") or "NONE"), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("visibleRequested=%s attempts=%s valid=%s rejected=%s", tostring(runtime.visibleRequested), tostring(runtime.materializationAttempts), tostring(runtime.materializationValid), tostring(runtime.materializationRejected)), maxWidth, maxLines)
  local avatarsAlive = 0
  for _ in pairs(WildEcology.activeAvatars) do avatarsAlive = avatarsAlive + 1 end
  appendWrappedLine(lines, string.format("spawnNpcCalls=%s avatarsAlive=%s materializationStatus=%s lastSpawnStatus=%s", tostring(runtime.spawnNpcCalls), tostring(avatarsAlive), tostring(runtime.materializationStatus), tostring(runtime.lastSpawnStatus)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("lastRejectedEntity=%s lastRejectedCell=%s lastRejectReason=%s", available(runtime.lastRejectedEntity), available(runtime.lastRejectedCell), available(runtime.lastRejectReason)), maxWidth, maxLines)

  local logView = readDebugLogView(WildEcology.mod)
  local categoryMask = readDebugCategoryMask(WildEcology.mod)
  local reserveLines = math.max(8, maxLines - 28)
  while #lines > reserveLines do
    table.remove(lines, 1)
  end
  appendWrappedLine(lines, "SPAWN DEBUG build=" .. SPAWN_DEBUG_BUILD, maxWidth, maxLines)
  appendWrappedLine(lines, string.format("currentSemanticsProbe=%s lastProductionSemanticsStatus=%s",
    available(worldInputs and worldInputs.currentSemanticsProbe),
    available(worldInputs and worldInputs.lastProductionSemanticsStatus)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("WORLD INPUTS mapOverviewStatus=%s semanticsReason=%s",
    available(currentProbe and currentProbe.mapOverviewStatus),
    available(currentProbe and currentProbe.semanticsReason)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("map=%s ecologyEnabled=%s populationMap=%s environment=%s candidateStatus=%s",
    available(spawnDebug and spawnDebug.mapId), yesNo(spawnDebug and spawnDebug.ecologyEnabled),
    available(spawnDebug and spawnDebug.populationMap), available(analysis and analysis.environmentClass),
    available(spawnDebug and spawnDebug.candidateStatus)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("attempts=%s valid=%s rejected=%s PLAYER DISTANCE: %s FLEE RADIUS: %s",
    tostring(runtime.materializationAttempts), tostring(runtime.materializationValid),
    tostring(runtime.materializationRejected), available(debugState.lastPlayerDistance),
    available(debugState.lastFleeRadius)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("DISPATCH phase3 entered %s dispatch %s blocker %s",
    tostring(runtime.phase3Entered), tostring(runtime.phase3DispatchAttempts),
    tostring(runtime.phase3LastBlocker)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("SPAWN result=%s SPAWN reason=%s",
    tostring(runtime.lastAdapterResult == nil and "nil" or runtime.lastAdapterResult),
    tostring(runtime.lastAdapterReason == nil and "nil" or runtime.lastAdapterReason)), maxWidth, maxLines)
  appendField(lines, "VIEW MODE: ", string.upper(tostring(logView or "both")), maxWidth, maxLines)
  appendField(lines, "ENABLED LOGS: ", enabledCategorySummary(categoryMask), maxWidth, maxLines)
  for _, category in ipairs({ "lifecycle", "behavior" }) do
    if categoryMask[category] and DebugLogger and DebugLogger.filteredEntries then
      local entries = DebugLogger.filteredEntries(function(entry)
        return entry.category == category
      end, 1)
      local entry = entries[1]
      if entry then
        appendWrappedLine(lines, string.upper(category) .. " #" .. tostring(entry.sequence or "?")
          .. ": " .. tostring(entry.message or ""), maxWidth, maxLines)
      end
    end
  end
  lines[#lines + 1] = "WILD ECOLOGY LOG"
  local runtime = WildEcology.spawnDiagnostics
  local excluded = runtime.exclusionReasons or {}
  appendWrappedLine(lines, "PIPELINE", maxWidth, maxLines)
  appendWrappedLine(lines, string.format("persistent %s", tostring(runtime.populationPersistentTotal)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("eligible %s", tostring(runtime.populationEligibleTotal)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("selected %s", tostring(runtime.populationSelectedTotal)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("anchor %s", tostring(runtime.anchorCalls)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("cohort %s", tostring(runtime.cohortCalls)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("mat ok %s", tostring(runtime.materializeSuccess)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("mat fail %s", tostring(runtime.materializeFailure)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("active %s", tostring(runtime.activeAvatarCount)), maxWidth, maxLines)
  appendWrappedLine(lines, "DISPATCH", maxWidth, maxLines)
  appendWrappedLine(lines, string.format("phase3 entered %s", tostring(runtime.phase3Entered)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("loop %s", tostring(runtime.phase3LoopEntered)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("dispatch %s", tostring(runtime.phase3DispatchAttempts)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("stage %s", tostring(runtime.phase3DispatchStage)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("blocker %s", tostring(runtime.phase3LastBlocker)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("actor %s", tostring(runtime.lastPhase3ActorId or "NONE")), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("species %s", tostring(runtime.lastPhase3ActorSpecies or "UNKNOWN")), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("cell %s", tostring(runtime.lastPhase3ActorCell or "NONE")), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("error %s", tostring(runtime.lastPhase3Error or "NONE")), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("SPAWN result=%s", tostring(runtime.lastAdapterResult == nil and "nil" or runtime.lastAdapterResult)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("SPAWN reason=%s", tostring(runtime.lastAdapterReason == nil and "nil" or runtime.lastAdapterReason)), maxWidth, maxLines)
  if WildEcology.performanceProfiler.enabled then
    local profiler = WildEcology.performanceProfiler
    appendWrappedLine(lines, string.format("PERF %s samples sync=%.2fms perc=%.2fms fear=%.2fms beh=%.2fms hud=%.2fms pairs=%s threats=%s plans=%s logs=%s",
      tostring(profiler.samples), profiler.totals.sync or 0,
      profiler.totals.perception or 0, profiler.totals.threat_fear or 0,
      profiler.totals.behavior or 0, profiler.totals.hud or 0,
      tostring(profiler.counts.perception_pair_checks or 0),
      tostring(profiler.counts.threat_assessments or 0),
      tostring(profiler.counts.navigation_plans or 0),
      tostring(profiler.counts.log_records or 0)), maxWidth, maxLines)
  end
  appendWrappedLine(lines, "EXCLUDED", maxWidth, maxLines)
  appendWrappedLine(lines, string.format("concealed %s", tostring(excluded.concealed or 0)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("already %s", tostring(excluded.already_active or 0)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("invalid %s", tostring(excluded.invalid_entity or 0)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("no cell %s", tostring(excluded.no_spawn_cell or 0)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("wrong %s", tostring(excluded.wrong_map or 0)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("other %s", tostring(excluded.lifecycle_blocked or 0)), maxWidth, maxLines)
  appendField(lines, "VIEW MODE: ", string.upper(tostring(logView or "both")), maxWidth, maxLines)
  appendField(lines, "ENABLED LOGS: ", enabledCategorySummary(categoryMask), maxWidth, maxLines)
  appendField(lines, "FOCUS: ", WildEcology.focusedEntityId or "anchor", maxWidth, maxLines)
  local behavior = spawnDebug and spawnDebug.behaviorDiagnostics or {}
  appendWrappedLine(lines, string.format("BEHAVIOR A=%s E=%s", available(behavior.activeEntities), available(behavior.behaviorEligible)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("D=%s AMB=%s FLEE=%s", available(behavior.behaviorDecisionTicks), available(behavior.ambientDecisions), available(behavior.fleeDecisions)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("FEAR D=%s S=%s HD=%s HS=%s G=%.2f R=%.2f",
    available(behavior.directlyFrightenedCount), available(behavior.sociallyFrightenedCount),
    available(behavior.highFearDirectCount), available(behavior.highFearSocialOnlyCount),
    behavior.averageAlarmGroundedness or 0, behavior.maxSocialRelayAlarm or 0), maxWidth, maxLines)
  appendWrappedLine(lines, "entity=" .. available(behavior.entity), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("lastTick=%s age=%s", available(behavior.lastDecisionTick), available(behavior.decisionAge)), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("D=%s/%s %s /100=%.1f/%.1f/%.1f/%.1f",
    available(behavior.lastDeliberationTick), available(behavior.nextDeliberationTick),
    available(behavior.reconsiderationReason),
    behavior.deliberationsPer100Ticks or 0, behavior.intentSwitchesPer100Ticks or 0,
    behavior.movementRequestsPer100Ticks or 0, behavior.replansPer100Ticks or 0),
    maxWidth, maxLines)
  appendWrappedLine(lines, "state=" .. available(behavior.state), maxWidth, maxLines)
  appendWrappedLine(lines, "reason=" .. available(behavior.reason), maxWidth, maxLines)
  appendWrappedLine(lines, string.format("contacts=%s motion=%s", available(behavior.perceptionContacts), yesNo(behavior.motionActive)), maxWidth, maxLines)
  local categorySummary = enabledCategorySummary(categoryMask)

  if categoryMask.generation and SpeciesSprites and SpeciesSprites.diagnostics then
    local spriteDiag = SpeciesSprites.diagnostics()
    if spriteDiag then
      if spriteDiag.skipped then
        appendField(lines, "SPRITES: ", "skipped (" .. tostring(spriteDiag.reason) .. ")", maxWidth, maxLines)
      else
        appendField(lines, "SPRITES: ", string.format("iter=%d walk=%d front=%d reg=%d ok=%s", spriteDiag.iterated or 0, spriteDiag.withWalkerSheet or 0, spriteDiag.withSpriteFront or 0, spriteDiag.registered or 0, tostring(spriteDiag.ok)), maxWidth, maxLines)
      end
    else
      appendField(lines, "SPRITES: ", "registerAll not run yet", maxWidth, maxLines)
    end
  end

  local wantsSummary = (logView == "summary" or logView == "both")
  local wantsEvents = (logView == "events" or logView == "both")

  if wantsSummary then
    appendField(lines, "LAST EVENT: ", debugState.lastEvent or "none", maxWidth, maxLines)
    appendField(lines, "CURRENT STATE: ", debugState.lastState or "unknown", maxWidth, maxLines)
    appendField(lines, "INTENT: ", debugState.lastIntent or "none", maxWidth, maxLines)
    appendField(lines, "TARGET ENTITY: ", debugState.lastTargetEntityId or "none", maxWidth, maxLines)
    if debugState.lastTargetDestinationId then
      appendField(lines, "DESTINATION: ", debugState.lastTargetDestinationId, maxWidth, maxLines)
    end
    appendField(lines, "SCORES: ", formatBehaviorScores(debugState.lastBehaviorScores), maxWidth, maxLines)
    appendField(lines, "BEHAVIOR MODE: ", debugState.lastBehaviorMode or "normal", maxWidth, maxLines)
    appendField(lines, "RESPAWN COUNT: ", debugState.lastRespawnCount or 0, maxWidth, maxLines)
    appendField(lines, "CURRENT MAP: ", debugState.lastContextMapId or "none", maxWidth, maxLines)
    appendField(lines, "HOME MAP: ", debugState.lastMapId or "none", maxWidth, maxLines)
    appendField(lines, "TRUST: ", debugState.lastTrust or 0, maxWidth, maxLines)
    appendField(lines, "THREAT MEMORY: ", debugState.lastThreatMemory or 0, maxWidth, maxLines)
    appendField(lines, "PLAYER DISTANCE: ", debugState.lastPlayerDistance or "none", maxWidth, maxLines)
    appendField(lines, "FLEE RADIUS: ", debugState.lastFleeRadius or "none", maxWidth, maxLines)
    if readPhase5DiagnosticsEnabled(WildEcology.mod) then
      appendField(lines, "SELF CELL: ", debugState.lastSelfCell or "none", maxWidth, maxLines)
      appendField(lines, "PLAYER CELL: ", debugState.lastPlayerCell or "none", maxWidth, maxLines)
      appendField(lines, "MOVE DIR: ", debugState.lastMovementDirection or "none", maxWidth, maxLines)
      appendField(lines, "MOVE REJECTED: ", debugState.lastMovementRejectionReason or "none", maxWidth, maxLines)
      appendField(lines, "BLOCKED DIRS: ", debugState.lastBlockedDirections or "none", maxWidth, maxLines)
      appendField(lines, "FLEE MODE: ", debugState.lastFleeMode or "none", maxWidth, maxLines)
      appendField(lines, "STUCK: ", debugState.lastFleeStuckReason or "none", maxWidth, maxLines)
      appendField(lines, "ESCAPE ROUTE: ", string.format("%s/%s -> %s", tostring(debugState.lastEscapeRouteIndex or 0), tostring(debugState.lastEscapeRouteLength or 0), tostring(debugState.lastEscapeEndpoint or "none")), maxWidth, maxLines)
      appendField(lines, "ENDPOINT: ", string.format("dist=%s mobility=%s", tostring(debugState.lastEndpointThreatDistance or "none"), tostring(debugState.lastEndpointMobility or "none")), maxWidth, maxLines)
      appendField(lines, "NEXT DELTA: ", string.format("%s regress=%s", tostring(debugState.lastNextStepThreatDelta or "none"), tostring(debugState.lastTemporaryThreatRegression == true)), maxWidth, maxLines)
      appendField(lines, "ROUTE INVALID: ", debugState.lastRouteInvalidationReason or "none", maxWidth, maxLines)
      appendField(lines, "FLEE CAND: ", debugState.lastFleeCandidates or "none", maxWidth, maxLines)
      appendField(lines, "PHASE5: ", debugState.lastPhase5Diagnostic or "none", maxWidth, maxLines)
    end
  end

  if wantsEvents and #lines < maxLines then
    lines[#lines + 1] = "RECENT EVENTS:"
    local eventSlots = math.max(0, math.min(2, maxLines - #lines))
    local entries = DebugLogger and DebugLogger.filteredEntries(function(entry)
      return categoryMask[entry.category] == true
    end, eventSlots) or {}

    if #entries == 0 then
      lines[#lines + 1] = "NO EVENTS CAPTURED"
    else
      for _, entry in ipairs(entries) do
        local prefix = entry.category and string.upper(entry.category) or "EVENT"
        appendWrappedLine(lines, prefix .. " #" .. tostring(entry.sequence or "?") .. ": " .. tostring(entry.message or ""), maxWidth, maxLines)
        if #lines >= maxLines then
          break
        end
      end
    end
  end

  performanceStop(profileName, profileStart)
  return lines
end

local function logScreenItemValue(mod, item)
  return readSaveFlag(mod, item.key, item.default)
end

local function logScreenItemDisplay(item, value)
  if item.kind == "choice" then
    return string.upper(tostring(value))
  end
  return value == true and "ON" or "OFF"
end

local function advanceLogScreenItem(mod, item)
  local current = logScreenItemValue(mod, item)
  if item.kind == "toggle" then
    local enabled = not (current == true)
    writeSaveFlag(mod, item.key, enabled)
    if item.key == DEBUG_LOG_RELATIONSHIP_AUDIT_OPTION_KEY then
      setRelationshipAuditEnabled(mod, enabled)
    elseif item.key == DEBUG_LOG_AGENT_AUDIT_OPTION_KEY then
      setAgentAuditEnabled(mod, enabled)
    elseif item.key == DEBUG_LOG_CONSOLE_OPTION_KEY then
      resetConsoleLogEpoch(mod, enabled)
    end
    return
  end
  if item.kind == "choice" and item.choices then
    local currentIndex = 1
    for index, choice in ipairs(item.choices) do
      if choice == current then
        currentIndex = index
        break
      end
    end
    local nextIndex = (currentIndex % #item.choices) + 1
    writeSaveFlag(mod, item.key, item.choices[nextIndex])
  end
end

-- Nested submenu (Tutorial 11 pattern: screens registry + Start-menu row)
-- instead of 6 separate rows in the flat mod options list.
local function registerLogSettingsScreen(mod)
  if not (mod and mod.content and mod.content.screens and mod.content.screens.register) then
    return
  end

  mod.content.screens:register(LOG_SETTINGS_SCREEN_ID, {
    new = function(game)
      local Font = mod.ui.Font
      local self = { game = game, isOpaque = true, cursor = 1 }
      WildEcology.logSettingsScreenOpen = true

      function self:update(_dt)
        local input = game.input
        if not input then
          return
        end
        if input:wasPressed("b") then
          WildEcology.logSettingsScreenOpen = false
          game.stack:pop()
          return
        end
        if input:wasPressed("up") then
          self.cursor = self.cursor - 1
          if self.cursor < 1 then
            self.cursor = #LOG_SCREEN_ITEMS
          end
        elseif input:wasPressed("down") then
          self.cursor = self.cursor + 1
          if self.cursor > #LOG_SCREEN_ITEMS then
            self.cursor = 1
          end
        elseif input:wasPressed("a") or input:wasPressed("left") or input:wasPressed("right") then
          advanceLogScreenItem(mod, LOG_SCREEN_ITEMS[self.cursor])
        end
      end

      function self:draw()
        Font.drawBox(0, 0, 20, 18)
        Font.draw("LOG SETTINGS", 16, 8)
        for index, item in ipairs(LOG_SCREEN_ITEMS) do
          local rowY = 16 + (index - 1) * 11
          local value = logScreenItemValue(mod, item)
          local cursorMark = (self.cursor == index) and ">" or " "
          Font.draw(cursorMark .. item.label, 8, rowY)
          Font.draw(logScreenItemDisplay(item, value), 128, rowY)
        end
        Font.draw("A CHANGE  B CLOSE", 8, 132)
      end

      return self
    end
  })
end

local function registerLogSettingsMenuEntry(mod)
  if not (mod and mod.hooks and mod.hooks.wrap and mod.ui and mod.ui.insertBefore and mod.ui.push) then
    return
  end

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    mod.ui.insertBefore(items, "OPTION", {
      label = "WILD ECOLOGY LOGS",
      onSelect = function()
        mod.ui.push(game, LOG_SETTINGS_SCREEN_ID)
      end
    })
    return next(game, items)
  end)
end

local function registerDebugUi(mod)
  local wrap = mod and mod.hooks and mod.hooks.wrap
  if WildEcology.debugUiInstalled and WildEcology.debugUiWrap == wrap then
    return
  end

  if mod and wrap and mod.ui and mod.ui.Font then
    wrap(mod.hooks, "input.pointer", function(next, game, event)
      local result = next(game, event)
      local button = event and tonumber(event.button)
      if event and event.phase == "pressed" and button == 1 and event.insideGame ~= false then
        local worldCellX, worldCellY = pointerWorldCell(mod, event)
        local localCellX, localCellY = pointerLocalCell(event)
        if worldCellX ~= nil and worldCellY ~= nil then
          local selected = nil
          local nearestDistance = math.huge
          for entityId, avatar in pairs(WildEcology.activeAvatars) do
            local ax, ay = getEntityPosition(avatar)
            if ax ~= nil and ay ~= nil then
              local worldDistance = math.max(math.abs(ax - worldCellX), math.abs(ay - worldCellY))
              local localDistance = localCellX and math.max(math.abs(ax - localCellX), math.abs(ay - localCellY)) or math.huge
              local distance = math.min(worldDistance, localDistance)
              if distance <= 1 and distance < nearestDistance then
                nearestDistance = distance
                selected = entityId
              end
            end
            if selected == entityId and nearestDistance == 0 then
              selected = entityId
              break
            end
          end
          WildEcology.focusedEntityId = selected
          if readDebugLogEnabled(mod) then
            writeDebugLog(mod, "behavior", string.format(
              "Debug focus click world=%s,%s local=%s,%s entity=%s",
              tostring(worldCellX), tostring(worldCellY), tostring(localCellX or "none"), tostring(localCellY or "none"), tostring(selected or "none")
            ))
          end
        end
      end
      return result
    end)
    wrap(mod.hooks, "render.hud", function(next, game, viewport)
      if type(next) == "function" then
        next(game, viewport)
      elseif viewport == nil then
        viewport = game
      end
      if WildEcology.logSettingsScreenOpen or not readDebugLogEnabled(mod) then
        return
      end

      local Font = mod.ui.Font
      local viewportX = math.floor(((viewport and viewport.gameX) or 0) / 8)
      local viewportY = math.floor(((viewport and viewport.gameY) or 0) / 8)
      local viewportWidthPx = (viewport and (viewport.gameWidth or viewport.width)) or 160
      local tw = math.max(20, math.min(52, math.floor(viewportWidthPx / 8)))
      local tx = viewportX
      local ty = viewportY
      local maxLines = math.max(10, math.min(42,
        math.floor((((viewport and viewport.gameHeight) or (viewport and viewport.height) or 144) / 8) - 2)))
      local lines = buildDebugLines(tw - 2, maxLines)
      local boxHeight = math.max(6, math.min(maxLines + 2, #lines + 2))
      Font.drawBox(tx, ty, tw, boxHeight)
      for index, line in ipairs(lines) do
        Font.draw(line, (tx + 1) * 8, (ty + index) * 8)
      end
    end)
  end

  WildEcology.debugUiInstalled = true
  WildEcology.debugUiWrap = wrap
end

-- Matches src/behavior/controller.lua's TARGET_DIRECTIONS ids, used to turn
-- an associate's last wander heading into a vector for alignment bias.
local TARGET_DIRECTION_VECTORS = {  target_up = { dx = 0, dy = -1 },
  target_down = { dx = 0, dy = 1 },
  target_left = { dx = -1, dy = 0 },
  target_right = { dx = 1, dy = 0 }
}

local function recordOccupancy(detailsByCell, key, entityId, kind, currentCell, destination, motion)
  local claims = detailsByCell[key] or {
    currentOccupants = {},
    destinationReservations = {}
  }
  detailsByCell[key] = claims
  local claim = {
    entityId = entityId,
    position = currentCell and {
      cellX = currentCell.cellX,
      cellY = currentCell.cellY
    } or nil,
    destination = destination and {
      cellX = destination.cellX,
      cellY = destination.cellY
    } or nil,
    moving = motion and motion.active == true or false,
    motionStartedTick = motion and motion.startedTick or nil
  }
  if kind == "CURRENT_NPC_CELL" then
    claims.currentOccupants[entityId] = claim
  else
    claims.destinationReservations[entityId] = claim
  end
end

-- Shared by the anchor and every visible companion so player relevance,
-- social target eligibility, and target stickiness never diverge between
-- the two call sites again.
local function buildBehaviorTargets(entity, position, player, playerDistance, ignoringPlayer, debugPreset, targetPositionForPlayer, simulationTick, mod, mapId)
    performanceCount("behavior_target_builds")
    local profileName, profileStart = performanceStart("target_build")
  local candidates = {}
  local targetPositions = {}
  local activeSocialCandidates = {}

  local playerIsRelevant = not ignoringPlayer and playerDistance ~= nil
    and (playerDistance <= 2 or (debugPreset ~= nil and playerDistance <= 5))
    and targetPositionForPlayer ~= nil
  if playerIsRelevant then
    candidates[#candidates + 1] = { id = player.id, distance = playerDistance, novelty = 0 }
    targetPositions[player.id] = targetPositionForPlayer
  end

  -- Nearby Pokémon within social perception range, regardless of whether
  -- the player is currently being ignored; normal mode should still fall
  -- back on social targets rather than idling whenever the player is far.
  -- Positions are read once per active avatar and reused below (crowding
  -- checks) instead of re-querying the engine per candidate per tick.
  local activePositions = {}
  local occupiedCells, currentOccupiedCells, vacatingCells, occupancyDetails = {}, {}, {}, {}
  local reservationCount = 0
  local function occupiedKey(cell)
    return tostring(cell.cellX) .. "," .. tostring(cell.cellY)
  end
  local nearbyAssociates = {}
  if position then
    for associateId, associateAvatar in pairs(WildEcology.activeAvatars) do
      if associateId ~= entity.id then
        local associatePosition = buildPositionEntity(associateAvatar)
        local associateEntity = WildEcology.entityById[associateId]
        if associatePosition then
          activePositions[associateId] = associatePosition
          local associateMotion = associateEntity and associateEntity.runtimeState
            and associateEntity.runtimeState.motion
          local associateClaim = WildEcology.movementClaims
            and WildEcology.movementClaims:claimForActor(associateId) or nil
          local currentKey = occupiedKey(associatePosition)
          occupiedCells[currentKey] = true
          currentOccupiedCells[currentKey] = true
          if associateClaim and (associateClaim.toX ~= associatePosition.cellX
            or associateClaim.toY ~= associatePosition.cellY) then
            vacatingCells[currentKey] = true
          end
          recordOccupancy(occupancyDetails, currentKey, associateId,
            "CURRENT_NPC_CELL", associatePosition,
            associateClaim and { cellX = associateClaim.toX, cellY = associateClaim.toY }
              or nil, associateMotion)
          if associateClaim then
            local destination = {
              cellX = associateClaim.toX,
              cellY = associateClaim.toY
            }
            local destinationKey = occupiedKey(destination)
            occupiedCells[destinationKey] = true
            recordOccupancy(occupancyDetails, destinationKey, associateId,
              "MOTION_DESTINATION_RESERVATION", associatePosition, destination,
              associateMotion)
            reservationCount = reservationCount + 1
          end
          if associateEntity then
            activeSocialCandidates[#activeSocialCandidates + 1] = {
              entity = associateEntity,
              position = associatePosition
            }
          end
          local associateDistance = math.max(
            math.abs(position.cellX - associatePosition.cellX),
            math.abs(position.cellY - associatePosition.cellY)
          )
          if associateDistance <= 5 then
            local relationship = entity.relationships and entity.relationships[associateId] or {}
            nearbyAssociates[associateId] = {
              distance = associateDistance,
              position = associatePosition,
              affinity = relationship.affinity or 0,
              familiarity = relationship.familiarity or 0,
              eligible = Social and Social.shouldFollowAssociate and Social.shouldFollowAssociate(relationship) or false,
              conspecific = associateAvatar.species ~= nil and associateAvatar.species == entity.species
            }
          end
        end
      end
    end
  end
  if targetPositionForPlayer then
    occupiedCells[occupiedKey(targetPositionForPlayer)] = true
  end
  local occupiedCellCount = 0
  for _ in pairs(occupiedCells) do occupiedCellCount = occupiedCellCount + 1 end

  -- Merely noticing a nearby Pokemon (novelty-driven INVESTIGATE) should not
  -- require an already-earned relationship; only becoming a sticky APPROACH
  -- target (below) needs trust/affinity. Otherwise wild Pokemon can only
  -- ever react to the player, since they start with zero history together.
  for associateId, info in pairs(nearbyAssociates) do
    candidates[#candidates + 1] = { id = associateId, distance = info.distance, novelty = math.max(0, 100 - info.familiarity) }
    targetPositions[associateId] = info.position
  end

  -- Avoid piling every seeker onto one popular associate: skip a candidate
  -- as a fresh pick when 2+ other avatars are already adjacent to it.
  local function crowdingAt(candidateId, candidatePosition)
    local count = 0
    for otherId, otherPosition in pairs(activePositions) do
      if otherId ~= candidateId then
        local d = math.max(
          math.abs(otherPosition.cellX - candidatePosition.cellX),
          math.abs(otherPosition.cellY - candidatePosition.cellY)
        )
        if d <= 1 then
          count = count + 1
        end
      end
    end
    return count
  end

  -- Sticky social target: hold the current target for the whole approach
  -- rather than re-electing "best affinity right now" every single tick,
  -- which previously caused target thrashing and permanent clumping.
  entity.runtimeState = entity.runtimeState or {}
  local stickyId = entity.runtimeState.socialTargetId
  if stickyId and not nearbyAssociates[stickyId] then
    stickyId = nil
  end
  if not stickyId then
    local bestId, bestAffinity = nil, -math.huge
    for associateId, info in pairs(nearbyAssociates) do
      if info.eligible and crowdingAt(associateId, info.position) < 2 and info.affinity > bestAffinity then
        bestAffinity = info.affinity
        bestId = associateId
      end
    end
    stickyId = bestId
  end
  entity.runtimeState.socialTargetId = stickyId

  local socialTargetId = (not playerIsRelevant) and stickyId or nil
  local threatAssessment = entity.runtimeState.threatAssessment
  local primaryThreatId = threatAssessment and threatAssessment.primaryThreatId or nil
  if primaryThreatId and not targetPositions[primaryThreatId] then
    if primaryThreatId == player.id then
      targetPositions[primaryThreatId] = targetPositionForPlayer
    else
      targetPositions[primaryThreatId] = activePositions[primaryThreatId]
    end
  end

  -- Weak directional alignment: nudge ambient wandering toward the average
  -- heading of nearby TRUSTED associates (not just any nearby Pokemon),
  -- so a loose group drifts together without any explicit herd-mode flag.
  -- Uses last tick's heading (entities are evaluated one at a time within
  -- a single WildEcology.init pass), which is fine for a "weak" bias.
  local groupHeadingBias = nil
  do
    local sumDx, sumDy, count = 0, 0, 0
    for associateId, info in pairs(nearbyAssociates) do
      if info.eligible then
        local associateEntity = WildEcology.entityById[associateId]
        local heading = associateEntity and associateEntity.runtimeState and associateEntity.runtimeState.lastTargetDirectionId
        local vector = TARGET_DIRECTION_VECTORS[heading]
        if vector then
          sumDx = sumDx + vector.dx
          sumDy = sumDy + vector.dy
          count = count + 1
        end
      end
    end
    if count > 0 and (sumDx ~= 0 or sumDy ~= 0) then
      groupHeadingBias = { dx = sumDx, dy = sumDy }
    end
  end

  -- Proximity fear/flee should react to whichever target is actually being
  -- interacted with, not always the player's distance, and should know
  -- whether that target is a conspecific (Pokemon don't find their own
  -- species awkwardly close the way they find the player).
  local targetDistance = playerDistance
  local targetIsConspecific = false
  if primaryThreatId then
    targetDistance = threatAssessment.primaryThreatDistance
    local threatInfo = nearbyAssociates[primaryThreatId]
    targetIsConspecific = threatInfo and threatInfo.conspecific or false
  elseif socialTargetId then
    local socialInfo = nearbyAssociates[socialTargetId]
    targetDistance = socialInfo and socialInfo.distance or playerDistance
    targetIsConspecific = socialInfo and socialInfo.conspecific or false
  end

  local flockSearch = FlockSearch and FlockSearch.update
    and FlockSearch.update(entity, position, activeSocialCandidates, simulationTick, { perceptionRadius = 5 })
    or nil
  local worldSemantics = WorldSemantics and WorldSemantics.fromMod
    and WorldSemantics.fromMod(mod, mapId)
    or nil

  local socialAlarmTargetPosition = nil
  local socialBias = entity.runtimeState and entity.runtimeState.socialEscapeBias
  local socialBiasConfidence = entity.runtimeState and entity.runtimeState.socialEscapeBiasConfidence or 0
  if position and socialBias and socialBiasConfidence >= 0.2
    and (socialBias.dx ~= 0 or socialBias.dy ~= 0) then
    socialAlarmTargetPosition = {
      cellX = position.cellX - socialBias.dx * 3,
      cellY = position.cellY - socialBias.dy * 3
    }
  end

  local result = {
    targetEntityId = socialTargetId or (playerIsRelevant and player.id or nil),
    hasTarget = #candidates > 0,
    purposefulTarget = #candidates > 0,
    candidates = candidates,
    targetPositions = targetPositions,
    socialTargetId = socialTargetId,
    groupHeadingBias = groupHeadingBias,
    targetDistance = targetDistance,
    targetIsConspecific = targetIsConspecific,
    flockSearch = flockSearch,
    worldSemantics = worldSemantics,
    occupiedCells = occupiedCells,
    currentOccupiedCells = currentOccupiedCells,
    vacatingCells = vacatingCells,
    occupancyDetails = occupancyDetails,
    movementClaims = WildEcology.movementClaims,
    occupiedCellCount = occupiedCellCount,
    reservationCount = reservationCount,
    socialAlarmTargetPosition = socialAlarmTargetPosition,
    threatAssessment = threatAssessment,
    fleeNeighbors = activeSocialCandidates
  }
  performanceStop(profileName, profileStart)
  return result
end

local function recordBehaviorDecision(mapId, entity, simulationTick, stateName, reason)
  local diagnostics = WildEcology.behaviorDiagnosticsByMap[mapId]
  if not diagnostics then
    diagnostics = {
      behaviorEligible = 0,
      behaviorDecisionTicks = 0,
      ambientDecisions = 0,
      fleeDecisions = 0
    }
    WildEcology.behaviorDiagnosticsByMap[mapId] = diagnostics
  end
  diagnostics.behaviorDecisionTicks = diagnostics.behaviorDecisionTicks + 1
  diagnostics.intentMetricStartTick = diagnostics.intentMetricStartTick or simulationTick
  if stateName == "FLEE" then
    diagnostics.fleeDecisions = diagnostics.fleeDecisions + 1
  else
    diagnostics.ambientDecisions = diagnostics.ambientDecisions + 1
  end
  entity.runtimeState = entity.runtimeState or {}
  entity.runtimeState.lastDecisionTick = simulationTick
  entity.runtimeState.nextDecisionTick = simulationTick + BEHAVIOR_DECISION_INTERVAL_TICKS
  entity.runtimeState.lastDecisionReason = reason
  entity.runtimeState.behaviorDecisionCount = (entity.runtimeState.behaviorDecisionCount or 0) + 1
  entity.runtimeState.schedulerMetrics = entity.runtimeState.schedulerMetrics or {}
  local metrics = entity.runtimeState.schedulerMetrics
  metrics.highLevelDeliberations = (metrics.highLevelDeliberations or 0) + 1
  if reason == "EMERGENCY_THREAT" or reason == "SEVERE_EVENT" then
    metrics.emergencyInterrupts = (metrics.emergencyInterrupts or 0) + 1
  end
  entity.runtimeState.lastDeliberationTick = simulationTick
  entity.runtimeState.nextDeliberationTick = entity.runtimeState.nextDecisionTick
  entity.runtimeState.reconsiderationReason = reason
  entity.runtimeState.deliberationDue = true
  entity.runtimeState.deliberationPerformed = true
end

local function logFocusedFleeDecision(mod, entity, position, simulationTick)
  local anchorId = Config and Config.phase0 and Config.phase0.testEntityId or nil
  local focusedId = WildEcology.focusedEntityId or anchorId
  local runtime = entity and entity.runtimeState or {}
  local execution = runtime.fleeExecution
  if not readPhase5DiagnosticsEnabled(mod) or not readBehaviorTraceEnabled(mod)
    or entity.id ~= focusedId
    or runtime.state ~= "FLEE" or not execution then
    return
  end
  local intent = execution.intent or {}
  local request = runtime.movementRequest or {}
  local bias = runtime.socialEscapeBias or {}
  local heading = runtime.escapeHeading or {}
  local search = runtime.flockSearch or {}
  local assessment = runtime.threatAssessment or {}
  local alignments = request.headingAlignments or {}
  local currentCell = position and tostring(position.cellX) .. "," .. tostring(position.cellY) or "none"
  local originCell = intent.originCell
    and tostring(intent.originCell.cellX) .. "," .. tostring(intent.originCell.cellY) or "none"
  writeDebugLog(mod, "behavior", string.format(
    "FLEE trace tick=%s actor=%s cell=%s previous=%s previousPrevious=%s threat=%s threatCell=%s threatDistance=%s fear=%.2f direct=%.2f social=%.2f recoveryProgress=%.2f threatPositionConfidence=%.2f directThreatLastSeenAge=%s exitBlocked=%s safeTicks=%s postFleeCalmTicks=%s heading=%.2f,%.2f residual=%.2f,%.2f headingAge=%s radial=%.2f,%.2f radialWeight=%.2f lateral=%.2f lateralWeight=%.2f separation=%.2f,%.2f separationWeight=%.2f openSpace=%.2f,%.2f openSpaceWeight=%.2f socialAlignment=%.2f,%.2f socialWeight=%.2f previousDirection=%s direction=%s alignUp=%.2f alignDown=%.2f alignLeft=%.2f alignRight=%.2f selectedScore=%.2f chosenAlignment=%.2f reassemblyPressure=%.2f seekUtility=%.2f nearbySameSpecies=%s nearbyFamily=%s socialBias=%s,%s socialConfidence=%.2f socialBiasAge=%s mode=%s endpoint=%s routeIndex=%s nextCell=%s chosenReason=%s routeDiscarded=%s invalidation=%s localRecovered=%s immediateReversal=%s oscillation=%s pattern=%s recentPenalty=%s intentAge=%s intentOrigin=%s intentBestSafety=%s desiredSafety=%s routeCommitment=%s commitmentReason=%s occupiedCells=%s reservationCount=%s nextCellReserved=%s primaryThreatId=%s primaryThreatAge=%s primaryThreatScore=%.2f primaryThreatReason=%s challengerThreatId=%s challengerScore=%.2f switchMargin=%.2f threatSwitch=%s threatSwitchReason=%s fearDirectThreatId=%s controllerFleeTargetId=%s identifiedThreatCount=%s",
    tostring(simulationTick), tostring(entity.id), tostring(execution.currentCell or currentCell),
    tostring(execution.previousCell or "none"), tostring(execution.previousPreviousCell or "none"),
    tostring(runtime.targetEntityId or "social_alarm_cue"), tostring(execution.threatCell or "none"),
    tostring(execution.threatDistance or "none"),
    runtime.fearCurrent or 0, runtime.fearDirect or 0, runtime.fearSocial or 0,
    runtime.fleeRecoveryProgress or 0, heading.threatPositionConfidence or 0,
    tostring(runtime.directThreatLastSeenAge or "none"),
    tostring(runtime.fleeExitBlockedReason or "none"), tostring(runtime.fleeSafeTicks or 0),
    tostring(runtime.postFleeCalmTicks or 0), heading.dx or 0, heading.dy or 0,
    heading.residualX or 0, heading.residualY or 0,
    tostring(heading.age or 0), heading.radialX or 0, heading.radialY or 0, heading.radialWeight or 0,
    heading.individualLateralBias or 0, heading.lateralWeight or 0,
    heading.separationX or 0, heading.separationY or 0, heading.separationWeight or 0,
    heading.openSpaceX or 0, heading.openSpaceY or 0, heading.openSpaceWeight or 0,
    heading.socialAlignmentX or 0, heading.socialAlignmentY or 0, heading.socialAlignmentWeight or 0,
    tostring(execution.previousDirection or "none"), tostring(request.direction or "none"),
    alignments.UP or 0, alignments.DOWN or 0, alignments.LEFT or 0, alignments.RIGHT or 0,
    request.headingResidualScore or 0,
    request.headingAlignmentScore or 0, search.reassemblyPressure or 0,
    runtime.behaviorScores and runtime.behaviorScores.SEEK_FLOCK or 0,
    tostring(search.nearbySameSpecies or 0), tostring(search.nearbyFamily or 0),
    tostring(bias.dx or "none"), tostring(bias.dy or "none"), runtime.socialEscapeBiasConfidence or 0,
    tostring(runtime.socialEscapeBiasAge or 0), tostring(execution.fleeMode or "NORMAL"),
    tostring(intent.routeId or "none"), tostring(execution.route and execution.route.index or 0),
    tostring(execution.nextCell or "none"),
    tostring(execution.chosenReason or "none"), tostring(execution.routeInvalidationTick == simulationTick),
    tostring(execution.routeInvalidationReason or "none"), tostring(execution.localEscapeRecovered == true),
    tostring(execution.immediateReversal == true), tostring(execution.oscillationDetected == true),
    tostring(execution.oscillationPattern or "none"), tostring(execution.recentPathPenalty or 0),
    tostring(intent.age or 0), tostring(originCell),
    tostring(intent.bestSafetyReached or "none"), tostring(runtime.fleeDesiredSafetyDistance or "none"),
    tostring(execution.routeCommitment == true), tostring(execution.routeCommitmentReason or "none"),
    tostring(execution.occupiedCellCount or 0), tostring(execution.reservationCount or 0),
    tostring(execution.nextCellReserved == true),
    tostring(assessment.primaryThreatId or "none"), tostring(assessment.primaryThreatAge or 0),
    assessment.primaryThreatScore or 0, tostring(assessment.primaryThreatReason or "NONE"),
    tostring(assessment.challengerThreatId or "none"), assessment.challengerScore or 0,
    assessment.switchMargin or 0, tostring(assessment.threatSwitch == true),
    tostring(assessment.threatSwitchReason or "NONE"), tostring(runtime.directThreatId or "none"),
    tostring(runtime.targetEntityId or "none"), tostring(assessment.identifiedThreatCount or 0)
  ))
  local candidateStatus = { UP = "UNAVAILABLE", DOWN = "UNAVAILABLE",
    LEFT = "UNAVAILABLE", RIGHT = "UNAVAILABLE" }
  for _, candidate in ipairs(execution.localCandidates or {}) do
    local status = candidate.threatForbidden and "THREAT_OCCUPIED"
      or not candidate.staticLegal and "STATIC_BLOCK"
      or candidate.rejected and "STATIC_REJECTED"
      or candidate.occupied and "DYNAMIC_OCCUPIED"
      or "LEGAL"
    candidateStatus[candidate.direction] = status
  end
  local threatPosition = runtime.escapeReference and runtime.escapeReference.position
  local deltaX = position and threatPosition
    and threatPosition.cellX - position.cellX or nil
  local deltaY = position and threatPosition
    and threatPosition.cellY - position.cellY or nil
  writeDebugLog(mod, "behavior", string.format(
    "FLEE spatial actor=%s cell=%s,%s primaryThreatId=%s threatCell=%s,%s delta=%s,%s reference=%s chosen=%s up=%s down=%s left=%s right=%s planningState=%s route=%s suspended=%s",
    tostring(entity.id),
    tostring(position and position.cellX or "none"),
    tostring(position and position.cellY or "none"),
    tostring(assessment.primaryThreatId or "none"),
    tostring(threatPosition and threatPosition.cellX or "none"),
    tostring(threatPosition and threatPosition.cellY or "none"),
    tostring(deltaX or "none"), tostring(deltaY or "none"),
    tostring(runtime.escapeReference and runtime.escapeReference.kind or "none"),
    tostring(request.direction or "none"),
    tostring(candidateStatus.UP), tostring(candidateStatus.DOWN),
    tostring(candidateStatus.LEFT), tostring(candidateStatus.RIGHT),
    tostring(execution.planningState or "none"),
    tostring(execution.route ~= nil), tostring(execution.routeSuspended == true)
  ))
end

local function logFocusedTrainerDecision(mod, entity, simulationTick)
  local anchorId = Config and Config.phase0 and Config.phase0.testEntityId or nil
  local focusedId = WildEcology.focusedEntityId or anchorId
  local runtime = entity and entity.runtimeState or {}
  local assessment = runtime.threatAssessment or {}
  if not readPhase5DiagnosticsEnabled(mod) or entity.id ~= focusedId
    or assessment.targetKind ~= "trainer" then
    return
  end
  local signature = table.concat({
    tostring(assessment.targetId), tostring(assessment.trainerWarinessApplicable),
    string.format("%.2f", assessment.trainerThreatScore or 0),
    tostring(assessment.primaryThreatId), tostring(runtime.state),
    tostring(assessment.persistentThreatMemoryWritten)
  }, ":")
  if runtime.lastTrainerThreatDiagnosticSignature == signature then return end
  runtime.lastTrainerThreatDiagnosticSignature = signature
  writeDebugLog(mod, "behavior", string.format(
    "Trainer threat actor=%s tick=%s targetId=%s targetKind=%s trainerWarinessApplicable=%s trainerThreatScore=%.2f trainerThreatDistanceComponent=%.2f trainerThreatApproachComponent=%.2f trainerThreatRelationshipModifier=%.2f familiarity=%.2f trust=%.2f affinity=%.2f primaryThreatId=%s primaryThreatReason=%s primaryThreatScore=%.2f persistentThreatMemoryWritten=%s persistentThreatMemoryReason=%s selectedBehavior=%s",
    tostring(entity.id), tostring(simulationTick), tostring(assessment.targetId or "none"),
    tostring(assessment.targetKind or "none"), tostring(assessment.trainerWarinessApplicable == true),
    assessment.trainerThreatScore or 0, assessment.trainerThreatDistanceComponent or 0,
    assessment.trainerThreatApproachComponent or 0,
    assessment.trainerThreatRelationshipModifier or 0,
    assessment.trainerRelationshipFamiliarity or 0, assessment.trainerRelationshipTrust or 0,
    assessment.trainerRelationshipAffinity or 0, tostring(assessment.primaryThreatId or "none"),
    tostring(assessment.primaryThreatReason or "NONE"), assessment.primaryThreatScore or 0,
    tostring(assessment.persistentThreatMemoryWritten == true),
    tostring(assessment.persistentThreatMemoryReason or "NONE"),
    tostring(runtime.state or "none")
  ))
end

local function logFocusedIntentDecision(mod, entity, simulationTick)
  local anchorId = Config and Config.phase0 and Config.phase0.testEntityId or nil
  local focusedId = WildEcology.focusedEntityId or anchorId
  if not readPhase5DiagnosticsEnabled(mod) or not entity or entity.id ~= focusedId then
    return
  end
  local runtime = entity.runtimeState or {}
  local scores = runtime.behaviorScores or {}
  local episode = runtime.intentEpisode or {}
  local search = runtime.flockSearch or {}
  local assessment = runtime.threatAssessment or {}
  local metrics = runtime.intentMetrics or {}
  local socialSignature = table.concat({
    tostring(runtime.socialFleeDecisionReason or "NONE"),
    tostring(runtime.socialFleeCueEligible == true),
    tostring(runtime.socialFleeEligible == true),
    tostring(runtime.candidateWinner or "none"),
    tostring(runtime.switchAllowed == true),
    tostring(runtime.switchReason or "NONE")
  }, ":")
  if runtime.lastSocialFleeDecisionSignature ~= socialSignature then
    runtime.lastSocialFleeDecisionSignature = socialSignature
    writeDebugLog(mod, "behavior", string.format(
      "Social FLEE decision actor=%s tick=%s socialFear=%.2f socialCueEligible=%s socialDirectionalConfidence=%.2f fleeScore=%.2f winningScore=%.2f winningIntent=%s fleeEligible=%s switchAllowed=%s switchReason=%s category=%s",
      tostring(entity.id), tostring(simulationTick), runtime.fearSocial or 0,
      tostring(runtime.socialFleeCueEligible == true),
      runtime.socialEscapeBiasConfidence or 0,
      scores.FLEE or 0, runtime.candidateWinnerScore or 0,
      tostring(runtime.candidateWinner or "none"),
      tostring(runtime.socialFleeEligible == true),
      tostring(runtime.switchAllowed == true),
      tostring(runtime.switchReason or "NONE"),
      tostring(runtime.socialFleeDecisionReason or "NONE")
    ))
  end
  local routeOwner = runtime.state == "FLEE" and runtime.fleeExecution
    or runtime.state == "SEEK_FLOCK" and runtime.navigation or nil
  local occupancyActive = routeOwner and (routeOwner.routeSuspended == true
    or routeOwner.routeReleased == true
    or routeOwner.blockedCell ~= nil
    or routeOwner.blockerCurrentOccupantId ~= nil
    or routeOwner.blockerReservationOwnerId ~= nil)
  if routeOwner and (occupancyActive or runtime.lastRouteOccupancySignature ~= nil) then
    local occupantDestination = routeOwner.blockerCurrentOccupantDestination
    local reservationDestination = routeOwner.blockerReservationOwnerDestination
    local episode = runtime.intentEpisode or {}
    local occupancySignature = table.concat({
      tostring(routeOwner.routeSuspended == true),
      tostring(routeOwner.blockedCell or "none"),
      tostring(routeOwner.blockerCurrentOccupantId or "none"),
      tostring(routeOwner.blockerCurrentOccupantMoving == true),
      tostring(routeOwner.blockerReservationOwnerId or "none"),
      tostring(routeOwner.routeReleased == true),
      tostring(routeOwner.releaseReason or "none"),
      tostring(routeOwner.occupancyReason or "none"),
      tostring(routeOwner.replanReason or routeOwner.routeInvalidationReason or "none")
    }, ":")
    if runtime.lastRouteOccupancySignature ~= occupancySignature then
      runtime.lastRouteOccupancySignature = occupancySignature
      writeDebugLog(mod, "behavior", string.format(
        "Route occupancy actor=%s tick=%s intent=%s routeSuspended=%s blockedSinceTick=%s blockAgeTicks=%s blockedCell=%s currentOccupantId=%s currentOccupantMoving=%s currentOccupantDestination=%s,%s reservationOwnerId=%s reservationOwnerDestination=%s,%s routeReleased=%s releaseReason=%s intentLastProgressTick=%s intentNoProgressAge=%s occupancyReason=%s replan=%s",
        tostring(entity.id), tostring(simulationTick), tostring(runtime.state),
        tostring(routeOwner.routeSuspended == true),
        tostring(routeOwner.blockedSinceTick or "none"),
        tostring(routeOwner.blockAgeTicks or 0),
        tostring(routeOwner.blockedCell or "none"),
        tostring(routeOwner.blockerCurrentOccupantId or "none"),
        tostring(routeOwner.blockerCurrentOccupantMoving == true),
        tostring(occupantDestination and occupantDestination.cellX or "none"),
        tostring(occupantDestination and occupantDestination.cellY or "none"),
        tostring(routeOwner.blockerReservationOwnerId or "none"),
        tostring(reservationDestination and reservationDestination.cellX or "none"),
        tostring(reservationDestination and reservationDestination.cellY or "none"),
        tostring(routeOwner.routeReleased == true),
        tostring(routeOwner.releaseReason or "none"),
        tostring(episode.lastProgressTick or "none"),
        tostring(episode.lastProgressTick
          and math.max(0, simulationTick - episode.lastProgressTick) or "none"),
        tostring(routeOwner.occupancyReason or "none"),
        tostring(routeOwner.replanReason or routeOwner.routeInvalidationReason or "none")
      ))
    end
  end
  local intentSignature = table.concat({
    tostring(runtime.candidateWinner or "none"),
    tostring(runtime.state or "none"),
    tostring(runtime.selectedState or "none"),
    tostring(runtime.switchAllowed == true),
    tostring(runtime.switchReason or "NONE"),
    tostring(episode.status or "NONE"),
    tostring(assessment.primaryThreatId or "none"),
    tostring(assessment.primaryThreatReason or "NONE"),
    tostring(runtime.navigationReplanReason or "NONE"),
    tostring(runtime.reconsiderationReason or "NONE")
  }, ":")
  if not readBehaviorTraceEnabled(mod)
    and runtime.lastIntentDecisionLogSignature == intentSignature then
    return
  end
  runtime.lastIntentDecisionLogSignature = intentSignature
  writeDebugLog(mod, "behavior", string.format(
    "Intent decision actor=%s tick=%s lastDeliberationTick=%s nextDeliberationTick=%s deliberationDue=%s deliberationPerformed=%s reconsiderationReason=%s executionUpdated=%s executionUpdateReason=%s perceptionUpdated=%s fearUpdated=%s navigationReplanned=%s navigationReplanReason=%s movementRequested=%s debugPreset=%s FLEE=%.2f APPROACH=%.2f INVESTIGATE=%.2f SEEK_FLOCK=%.2f TARGET=%.2f IDLE=%.2f REST=%.2f rawSeekFlock=%.2f seekSafetyFactor=%.2f candidateWinner=%s candidateScore=%.2f currentState=%s currentStateAge=%s hysteresisHeld=%s hysteresisReason=%s selectedState=%s selectedTarget=%s currentThreat=%s threatReason=%s fearCurrent=%.2f fearDirect=%.2f fearSocial=%.2f escapeUrgency=%.2f isolationPressure=%.2f reassemblyPressure=%.2f groupDeficit=%.2f independence=%.2f sociality=%.2f intentEpisodeAge=%s intentEpisodeStatus=%s intentTarget=%s intentCommitment=%.2f intentProgress=%.2f challengerIntent=%s challengerScore=%.2f switchMargin=%.2f switchAllowed=%s switchReason=%s recentSatisfiedIntent=%s recentSatisfiedTarget=%s satisfactionAge=%s switches=%s starts=%s completions=%s interruptions=%s failures=%s",
    tostring(entity.id), tostring(simulationTick),
    tostring(runtime.lastDeliberationTick or "none"),
    tostring(runtime.nextDeliberationTick or "none"),
    tostring(runtime.deliberationDue == true), tostring(runtime.deliberationPerformed == true),
    tostring(runtime.reconsiderationReason or "NONE"),
    tostring(runtime.executionUpdated == true), tostring(runtime.executionUpdateReason or "NONE"),
    tostring(runtime.perceptionUpdated == true), tostring(runtime.fearUpdated == true),
    tostring(runtime.navigationReplanned == true),
    tostring(runtime.navigationReplanReason or "NONE"),
    tostring(runtime.movementRequested == true),
    tostring(runtime.debugPreset or "NONE"),
    scores.FLEE or 0, scores.APPROACH or 0, scores.INVESTIGATE or 0,
    scores.SEEK_FLOCK or 0, scores.TARGET or 0, scores.IDLE or 0, scores.REST or 0,
    runtime.rawSeekFlockUtility or 0, runtime.seekFlockSafetyFactor or 1,
    tostring(runtime.candidateWinner or "none"), runtime.candidateWinnerScore or 0,
    tostring(runtime.intent or runtime.state or "none"), tostring(runtime.currentStateAge or 0),
    tostring(runtime.hysteresisHeld == true), tostring(runtime.hysteresisReason or "NONE"),
    tostring(runtime.selectedState or runtime.state or "none"),
    tostring(runtime.selectedTarget or "none"),
    tostring(assessment.primaryThreatId or "none"),
    tostring(assessment.primaryThreatReason or "NONE"),
    runtime.fearCurrent or 0, runtime.fearDirect or 0, runtime.fearSocial or 0,
    runtime.escapeUrgency or 0, search.isolationPressure or 0,
    search.reassemblyPressure or 0, search.groupDeficit or 0,
    search.independence or (entity.rawStats and entity.rawStats.independence) or 0,
    search.sociability or (entity.temperament and entity.temperament.sociability) or 0,
    tostring(runtime.intentEpisodeAge or 0), tostring(episode.status or "NONE"),
    tostring(episode.targetId or "none"), runtime.intentCommitment or 0,
    runtime.intentProgress or 0, tostring(runtime.challengerIntent or "none"),
    runtime.challengerScore or 0, runtime.intentSwitchMargin or 0,
    tostring(runtime.switchAllowed == true), tostring(runtime.switchReason or "NONE"),
    tostring(runtime.recentSatisfiedIntent or "none"),
    tostring(runtime.recentSatisfiedTarget or "none"),
    tostring(runtime.satisfactionAge or "none"), tostring(metrics.intentSwitches or 0),
    tostring(metrics.purposefulIntentStarts or 0),
    tostring(metrics.purposefulIntentCompletions or 0),
    tostring(metrics.purposefulIntentInterruptions or 0),
    tostring(metrics.purposefulIntentFailures or 0)
  ))
end

local function enterRequestedConcealment(mod, entity, simulationTick)
  local runtime = entity and entity.runtimeState
  local request = runtime and runtime.concealmentRequest
  local avatar = entity and WildEcology.activeAvatars[entity.id]
  if not request or not avatar or not Concealment then return false end
  if RuntimeAvatarAdapter and RuntimeAvatarAdapter.destroy then
    RuntimeAvatarAdapter.destroy(mod, avatar)
  else
    AvatarFactory.despawn(mod, avatar)
  end
  if WildEcology.movementClaims then
    WildEcology.movementClaims:clear(entity.id, simulationTick,
      "ENTER_CONCEALMENT")
  end
  WildEcology.activeAvatars[entity.id] = nil
  WildEcology.spawnSyncDirty = true
  WildEcology.spawnRetryTick = nil
  Concealment.enter(entity, request, simulationTick)
  RuntimeState.reset(entity)
  return true
end

local function evaluatePhase0State(mod, mapId, countRespawn, simulationTick, reconsiderationReason)
  local phase0 = (Config and Config.phase0) or {}
  local behaviorMode = readBehaviorMode(mod)

  ensureSave(mod)
  if not Save or not PopulationManager or not AvatarFactory or not Controller then
    return nil
  end

  simulationTick = simulationTick or (Save.getState() and Save.getState().simulationTick) or 0
  local entity = PopulationManager.getOrCreatePhase0Entity(mod)
  WildEcology.entityById[entity.id] = entity
  entity.home = entity.home or {}
  entity.home.mapId = mapId or entity.home.mapId or phase0.testMapId
  entity.memory = entity.memory or {}
  entity.memory.debug = entity.memory.debug or { respawnCount = 0 }
  if countRespawn ~= false then
    entity.memory.debug.respawnCount = (entity.memory.debug.respawnCount or 0) + 1
  end

  local player = getPlayerEntity()
  local avatar = WildEcology.activeAvatars[phase0.testEntityId]
  local ignoringPlayer = behaviorMode == "ignore_player"
  local playerDistance = ignoringPlayer and nil or getDistanceToPlayer(mod, avatar)
  if AvatarFactory and AvatarFactory.refreshMotionState then
    AvatarFactory.refreshMotionState(mod, avatar, entity)
  end
  local previousIntent = entity.runtimeState and entity.runtimeState.state or nil
  local rel, gainedCalmTrust = PopulationManager.updatePhase0Relationship(entity, player, simulationTick, playerDistance)

  -- Associate-driven social fear/reassurance is now generic (see
  -- PopulationManager.propagateAssociateSocialSignal, applied for the
  -- whole visible population in observeActivePopulation) rather than a
  -- fixed demo-associate/player-only pair evaluated only for this anchor.
  local socialFearEnabled = readPhase2SocialFearEnabled(mod)
  local socialThreatDelta = 0

  applyDebugRelationshipOverrides(rel)

  if gainedCalmTrust then
    local band, multiplier = describeDistance(playerDistance)
    writeDebugLog(mod, "relationships", string.format("Calm proximity to player increased trust to %s and threat memory to %s observer=%s distance=%s multiplier=%.2f", tostring(rel.trust or 0), tostring(rel.threatMemory or 0), tostring(entity.id), tostring(band), multiplier))
  end

  local debugPreset = behaviorMode and behaviorMode:match("^force_(.+)$")
  local activeAvatar = WildEcology.activeAvatars[entity.id]
  local movementAvailable = AvatarFactory and AvatarFactory.movementApiAvailable
    and AvatarFactory.movementApiAvailable(mod, activeAvatar)
  local livePosition = buildPositionEntity(activeAvatar)
  local position = livePosition or persistedHomePosition(entity)
  local behaviorTargets = buildBehaviorTargets(entity, position, player, playerDistance, ignoringPlayer, debugPreset, perceptionPositionForPlayer(mod), simulationTick, mod, mapId)
  if behaviorTargets.threatAssessment and behaviorTargets.threatAssessment.primaryThreatId then
    rel = behaviorTargets.threatAssessment.primaryThreatRelationship or rel
  elseif behaviorTargets.socialTargetId then
    rel = entity.relationships and entity.relationships[behaviorTargets.socialTargetId] or rel
  end
  local preset = BehaviorDebugPreset.apply(debugPreset, entity, {
    id = player.id, kind = "trainer", distance = playerDistance,
    relationship = rel, motion = "STABLE"
  }, rel)
  if preset.name then rel = preset.relationship end
  local runtimeBefore = entity.runtimeState or {}
  local beforeNavigationRoute = runtimeBefore.navigation and runtimeBefore.navigation.route
  local beforeFleeRoute = runtimeBefore.fleeExecution and runtimeBefore.fleeExecution.route
  local state = Controller.tick(entity, rel, behaviorTargets.targetDistance, {
    ecologyPhase = WildEcology.currentClockSample
      and WildEcology.currentClockSample.phase or 0.5,
    behaviorEntity = preset.name and preset.entity or nil,
    debugPreset = preset.name,
    debugPresetOriginalInputs = preset.name and preset.originalInputs or nil,
    debugPresetReplacedInputs = preset.name and preset.replacedInputs or nil,
    targetEntityId = behaviorTargets.targetEntityId,
    threatAssessment = behaviorTargets.threatAssessment,
    fleeNeighbors = behaviorTargets.fleeNeighbors,
    hasTarget = preset.name == nil and behaviorTargets.hasTarget or preset.hasTarget,
    purposefulTarget = preset.name == nil and behaviorTargets.purposefulTarget or preset.purposefulTarget,
    conspecific = behaviorTargets.targetIsConspecific,
    candidates = behaviorTargets.candidates,
    position = position,
    mapId = mapId,
    targetPositions = behaviorTargets.targetPositions,
    groupHeadingBias = behaviorTargets.groupHeadingBias,
    flockSearch = behaviorTargets.flockSearch,
    worldSemantics = behaviorTargets.worldSemantics,
    occupiedCells = behaviorTargets.occupiedCells,
    occupiedCellCount = behaviorTargets.occupiedCellCount,
    reservationCount = behaviorTargets.reservationCount,
    perceivedFear = entity.runtimeState and entity.runtimeState.perceivedFear and entity.runtimeState.perceivedFear[behaviorTargets.targetEntityId] or 0,
    currentFear = preset.fearCurrent ~= nil and preset.fearCurrent
      or entity.runtimeState and entity.runtimeState.fearCurrent or 0,
    allowTargeting = preset.allowTargeting,
    debugIdleElapsed = preset.idleElapsed,
    debugSettledElapsed = preset.settledElapsed,
    socialAlarmTargetPosition = behaviorTargets.socialAlarmTargetPosition,
    goalRadius = 1,
    investigateRadius = 3,
    locomotionPacing = true,
    fleeRadius = entity.runtimeState and entity.runtimeState.fleeRadius or 1
  }, simulationTick)
  local fleeRadius = entity.runtimeState and entity.runtimeState.fleeRadius or nil
  recordBehaviorDecision(mapId, entity, simulationTick, state, reconsiderationReason or "PHASE0_ANCHOR")
  entity.runtimeState.lastSchedulerDebugPreset = debugPreset
  local runtime = entity.runtimeState
  runtime.schedulerMetrics = runtime.schedulerMetrics or {}
  local schedulerMetrics = runtime.schedulerMetrics
  schedulerMetrics.executionUpdates = (schedulerMetrics.executionUpdates or 0) + 1
  local navigationReplanned = beforeNavigationRoute ~= (runtime.navigation and runtime.navigation.route)
    or beforeFleeRoute ~= (runtime.fleeExecution and runtime.fleeExecution.route)
  runtime.navigationReplanned = navigationReplanned
  runtime.navigationReplanReason = runtime.navigation and runtime.navigation.replanReason
    or runtime.fleeExecution and runtime.fleeExecution.routeInvalidationReason
    or "NONE"
  if navigationReplanned then
    schedulerMetrics.navigationReplans = (schedulerMetrics.navigationReplans or 0) + 1
  end
  local movementRequest = runtime.movementRequest
  runtime.movementRequested = movementRequest ~= nil
    and movementRequest.issuedTick == simulationTick
    and movementRequest.traversalMode == "WALK"
  if runtime.movementRequested then
    schedulerMetrics.movementRequests = (schedulerMetrics.movementRequests or 0) + 1
  end
  logFocusedFleeDecision(mod, entity, position, simulationTick)
  logFocusedTrainerDecision(mod, entity, simulationTick)
  logFocusedIntentDecision(mod, entity, simulationTick)
  applyPhase0AvatarBehavior(entity, state)
  updatePhase5Diagnostic(getPhase0DebugState(), entity)
  if readPhase5DiagnosticsEnabled(mod) and previousIntent ~= nil and previousIntent ~= state then
    local runtimeState = entity.runtimeState or {}
    local goal = runtimeState.spatialGoal
    local selfPosition = runtimeState.goalSelfPosition
    local targetPosition = runtimeState.goalTargetPosition
    writeDebugLog(mod, "behavior", string.format(
      "Intent transition %s -> %s target=%s distance=%s goalSatisfied=%s fear=%s trust=%s threat=%s self=%s,%s targetPos=%s,%s goal=%s/%s align=%s fleeEndTick=%s firstOrdinaryDecisionTick=%s firstOrdinaryState=%s firstSeekFlockTick=%s postFleeCalmTicks=%s reassemblyPressure=%.2f seekFlockUtility=%.2f",
      tostring(previousIntent or "none"),
      tostring(state),
      tostring(runtimeState.targetEntityId or "none"),
      tostring(runtimeState.goalChebyshev or playerDistance or "none"),
      tostring(runtimeState.goalSatisfied == true),
      tostring(runtimeState.perceivedFear and runtimeState.perceivedFear.player or 0),
      tostring(rel.trust or 0),
      tostring(rel.threatMemory or 0),
      tostring(selfPosition and selfPosition.cellX or "none"),
      tostring(selfPosition and selfPosition.cellY or "none"),
      tostring(targetPosition and targetPosition.cellX or "none"),
      tostring(targetPosition and targetPosition.cellY or "none"),
      tostring(goal and goal.minRange or "none"),
      tostring(goal and goal.maxRange or "none"),
      tostring(goal and goal.alignment or "none"),
      tostring(runtimeState.lastFleeEndTick or "none"),
      tostring(runtimeState.firstOrdinaryDecisionTick or "none"),
      tostring(runtimeState.firstOrdinaryState or "none"),
      tostring(runtimeState.firstSeekFlockTick or "none"),
      tostring(runtimeState.postFleeCalmTicks or 0),
      runtimeState.flockSearch and runtimeState.flockSearch.reassemblyPressure or 0,
      runtimeState.behaviorScores and runtimeState.behaviorScores.SEEK_FLOCK or 0
    ))
  end
  if not enterRequestedConcealment(mod, entity, simulationTick) then
    applyMovementRequestToAvatar(mod, WildEcology.activeAvatars[entity.id], entity)
  end

  return {
    behaviorMode = behaviorMode,
    entity = entity,
    rel = rel,
    state = state,
    mapId = mapId,
    gainedCalmTrust = gainedCalmTrust,
    socialFearEnabled = socialFearEnabled,
    socialThreatDelta = socialThreatDelta,
    fleeRadius = fleeRadius,
    playerDistance = playerDistance
  }
end

local function applyPhase0DebugState(debugState, payload, eventName, avatarId)
  if not debugState then
    return
  end

  debugState.lastEvent = eventName
  debugState.lastEntityId = payload.entity.id
  debugState.lastSpawnAvatarId = avatarId or debugState.lastSpawnAvatarId
  debugState.lastRespawnCount = payload.entity.memory.debug.respawnCount
  debugState.lastState = payload.state
  debugState.lastTrust = payload.rel.trust or 0
  debugState.lastThreatMemory = payload.rel.threatMemory or 0
  debugState.lastMapId = payload.entity.home.mapId
  debugState.lastContextMapId = payload.mapId or readCurrentMapId(WildEcology.mod)
  debugState.lastBehaviorMode = payload.behaviorMode
  debugState.lastIntent = payload.entity.runtimeState and payload.entity.runtimeState.intent or payload.state
  debugState.lastTargetEntityId = payload.entity.runtimeState and payload.entity.runtimeState.targetEntityId or nil
  debugState.lastTargetDestinationId = payload.entity.runtimeState and payload.entity.runtimeState.targetDestination and payload.entity.runtimeState.targetDestination.id or nil
  debugState.lastBehaviorScores = payload.entity.runtimeState and payload.entity.runtimeState.behaviorScores or nil
  debugState.debugPreset = payload.entity.runtimeState and payload.entity.runtimeState.debugPreset or "NONE"
  debugState.debugPresetInputs = payload.entity.runtimeState and payload.entity.runtimeState.debugPresetInputs or nil
  debugState.debugPresetOriginalInputs = payload.entity.runtimeState and payload.entity.runtimeState.debugPresetOriginalInputs or nil
  debugState.debugPresetReplacedInputs = payload.entity.runtimeState and payload.entity.runtimeState.debugPresetReplacedInputs or nil
  debugState.selectionReason = payload.entity.runtimeState and payload.entity.runtimeState.selectionReason or "UNKNOWN"
  debugState.lastMovementApi = payload.entity.runtimeState and payload.entity.runtimeState.movementApi or debugState.lastMovementApi
  debugState.lastMovementRequest = payload.entity.runtimeState and payload.entity.runtimeState.movementRequest and payload.entity.runtimeState.movementRequest.direction or debugState.lastMovementRequest
  debugState.lastMotionActive = payload.entity.runtimeState and payload.entity.runtimeState.motion and payload.entity.runtimeState.motion.active or false
  local runtimeState = payload.entity.runtimeState or {}
  local selfPosition = runtimeState.goalSelfPosition
  local targetPosition = runtimeState.goalTargetPosition
  local heading = runtimeState.escapeHeading or {}
  local search = runtimeState.flockSearch or {}
  debugState.lastPhase5Diagnostic = string.format(
    "self=%s,%s target=%s,%s dx=%s dy=%s man=%s cheb=%s goal=%s/%s %s sat=%s motion=%s fleeExit=%s safe=%s threatAge=%s heading=%.2f,%.2f calm=%s rejoin=%.2f seek=%.2f",
    tostring(selfPosition and selfPosition.cellX or "none"),
    tostring(selfPosition and selfPosition.cellY or "none"),
    tostring(targetPosition and targetPosition.cellX or "none"),
    tostring(targetPosition and targetPosition.cellY or "none"),
    tostring(runtimeState.goalDx or "none"),
    tostring(runtimeState.goalDy or "none"),
    tostring(runtimeState.goalManhattan or "none"),
    tostring(runtimeState.goalChebyshev or "none"),
    tostring(runtimeState.spatialGoal and runtimeState.spatialGoal.minRange or "none"),
    tostring(runtimeState.spatialGoal and runtimeState.spatialGoal.maxRange or "none"),
    tostring(runtimeState.spatialGoal and runtimeState.spatialGoal.alignment or "none"),
    tostring(runtimeState.goalSatisfied == true),
    tostring(runtimeState.motion and runtimeState.motion.active or false),
    tostring(runtimeState.fleeExitBlockedReason or "none"),
    tostring(runtimeState.fleeSafeTicks or 0),
    tostring(runtimeState.directThreatLastSeenAge or "none"),
    heading.dx or 0, heading.dy or 0,
    tostring(search.postFleeCalmTicks or runtimeState.postFleeCalmTicks or 0),
    search.reassemblyPressure or 0,
    runtimeState.behaviorScores and runtimeState.behaviorScores.SEEK_FLOCK or 0
  )
  debugState.lastFleeRadius = payload.fleeRadius or debugState.lastFleeRadius
  debugState.lastPlayerDistance = payload.playerDistance or debugState.lastPlayerDistance
end

updatePhase5Diagnostic = function(debugState, entity)
  if not debugState then
    return
  end

  local runtimeState = entity and entity.runtimeState or {}
  local selfPosition = runtimeState.goalSelfPosition
  local targetPosition = runtimeState.goalTargetPosition
  local heading = runtimeState.escapeHeading or {}
  local search = runtimeState.flockSearch or {}
  debugState.lastPhase5Diagnostic = string.format(
    "self=%s,%s target=%s,%s dx=%s dy=%s man=%s cheb=%s goal=%s/%s %s sat=%s motion=%s fleeExit=%s safe=%s threatAge=%s heading=%.2f,%.2f calm=%s rejoin=%.2f seek=%.2f",
    tostring(selfPosition and selfPosition.cellX or "none"),
    tostring(selfPosition and selfPosition.cellY or "none"),
    tostring(targetPosition and targetPosition.cellX or "none"),
    tostring(targetPosition and targetPosition.cellY or "none"),
    tostring(runtimeState.goalDx or "none"),
    tostring(runtimeState.goalDy or "none"),
    tostring(runtimeState.goalManhattan or "none"),
    tostring(runtimeState.goalChebyshev or "none"),
    tostring(runtimeState.spatialGoal and runtimeState.spatialGoal.minRange or "none"),
    tostring(runtimeState.spatialGoal and runtimeState.spatialGoal.maxRange or "none"),
    tostring(runtimeState.spatialGoal and runtimeState.spatialGoal.alignment or "none"),
    tostring(runtimeState.goalSatisfied == true),
    tostring(runtimeState.motion and runtimeState.motion.active or false),
    tostring(runtimeState.fleeExitBlockedReason or "none"),
    tostring(runtimeState.fleeSafeTicks or 0),
    tostring(runtimeState.directThreatLastSeenAge or "none"),
    heading.dx or 0, heading.dy or 0,
    tostring(search.postFleeCalmTicks or runtimeState.postFleeCalmTicks or 0),
    search.reassemblyPressure or 0,
    runtimeState.behaviorScores and runtimeState.behaviorScores.SEEK_FLOCK or 0
  )
end

applyMovementRequestToAvatar = function(mod, avatar, entity)
  if not RuntimeAvatarAdapter or not RuntimeAvatarAdapter.requestMovement then
    return false
  end

  entity.runtimeState = entity.runtimeState or {}
  local runtime = entity.runtimeState
  local state = Save and Save.getState and Save.getState() or nil
  local tick = state and state.simulationTick or 0
  if runtime.movementRequest == nil
    and not (runtime.motion and runtime.motion.active) then
    if WildEcology.movementClaims then
      WildEcology.movementClaims:clear(entity.id, tick, "NO_MOVEMENT_REQUEST")
    end
    return false
  end
  local position = buildPositionEntity(avatar) or persistedHomePosition(entity)
  if WildEcology.movementClaims then
    WildEcology.movementClaims:validateActor(entity.id, runtime, position, tick)
  end
  local movementApi = AvatarFactory and AvatarFactory.movementApiAvailable and AvatarFactory.movementApiAvailable(mod, avatar)
    and "AVAILABLE" or "UNAVAILABLE"
  local movementApiChanged = entity.runtimeState.movementApi ~= movementApi
  entity.runtimeState.movementApi = movementApi

  local debugState = getPhase0DebugState()
  if debugState then
    debugState.lastMovementApi = entity.runtimeState.movementApi
    debugState.lastMotionActive = entity.runtimeState.motion and entity.runtimeState.motion.active or false
  end

  local request = runtime.movementRequest
  if WildEcology.movementClaims and request and request.traversalMode == "WALK"
    and request.direction ~= "STAY" and request.destinationX ~= nil
    and request.destinationY ~= nil and position then
    local claimed, conflictType, conflictClaim = WildEcology.movementClaims:publish({
      actorId = entity.id,
      fromX = request.sourceX or position.cellX,
      fromY = request.sourceY or position.cellY,
      toX = request.destinationX,
      toY = request.destinationY,
      intent = runtime.state,
      urgency = runtime.escapeUrgency or 0,
      routeCommitted = runtime.fleeExecution and runtime.fleeExecution.routeCommitment == true
        or runtime.navigation and runtime.navigation.route ~= nil
    }, tick)
    if not claimed then
      request.rejectionReason = "entity"
      request.blockingLayer = "MOVEMENT_CLAIM"
      request.blockerId = conflictClaim and conflictClaim.actorId or nil
      request.claimIdentity = conflictClaim and table.concat({
        tostring(conflictClaim.actorId),
        tostring(conflictClaim.fromX), tostring(conflictClaim.fromY),
        tostring(conflictClaim.toX), tostring(conflictClaim.toY)
      }, ":") or nil
      request.claimConflictType = conflictType
      request.claimConflictActorId = conflictClaim and conflictClaim.actorId or nil
      runtime.movementClaimConflict = {
        type = conflictType,
        actorId = request.claimConflictActorId
      }
      entityBlockDiagnostic(mod, {
        actorId = entity.id,
        layer = "MOVEMENT_CLAIM",
        request = request
      })
      return false
    end
    runtime.movementClaimConflict = nil
  elseif WildEcology.movementClaims and not (runtime.motion and runtime.motion.active) then
    WildEcology.movementClaims:clear(entity.id, tick, "NO_MOVEMENT_REQUEST")
  end

  local applied = RuntimeAvatarAdapter.requestMovement(mod, avatar, entity)
  if entity.runtimeState and entity.runtimeState.state == "FLEE" then
    performanceCount("flee_request_applied", applied and 1 or 0)
  end
  if not applied and request and request.rejectionReason == "entity" then
    entityBlockDiagnostic(mod, {
      actorId = entity.id,
      layer = request.blockingLayer or "STOCK_COLLISION",
      request = request
    })
  end
  if WildEcology.movementClaims and not applied then
    local rejection = request and request.rejectionReason
    if rejection and rejection ~= "MOVEMENT_ACTIVE" then
      WildEcology.movementClaims:clear(entity.id, tick, "MOVEMENT_REJECTED")
    end
  end
  local motion = entity.runtimeState and entity.runtimeState.motion
  if readPhase5DiagnosticsEnabled(mod) and request
    and (request.traversalMode == "WALK" or entity.runtimeState.intent == "FLEE") then
    local movementResult = applied and "SUCCESS" or (request.rejectionReason or "REJECTED")
    local fleeExecution = entity.runtimeState.fleeExecution
    local assessment = entity.runtimeState.threatAssessment or {}
    local escapeReference = entity.runtimeState.escapeReference or {}
    if entity.runtimeState.intent == "FLEE" then
      local validProvenance, provenanceError = Controller.validateFleeProvenance(
        entity.runtimeState, request)
      entity.runtimeState.fleeProvenanceValid = validProvenance
      entity.runtimeState.fleeProvenanceError = provenanceError
      local provenanceSignature = table.concat({
        tostring(assessment.primaryThreatId or "none"),
        tostring(assessment.primaryThreatReason or "NONE"),
        tostring(escapeReference.kind or "none"),
        tostring(escapeReference.entityId or "none"),
        tostring(escapeReference.sourceThreatId or "none"),
        tostring(validProvenance)
      }, ":")
      if entity.runtimeState.lastFleeProvenanceSignature ~= provenanceSignature then
        entity.runtimeState.lastFleeProvenanceSignature = provenanceSignature
        if readBehaviorTraceEnabled(mod) then
          writeDebugLog(mod, "behavior", string.format(
          "FLEE provenance actor=%s primaryThreatId=%s previousPrimaryThreatId=%s primaryThreatReason=%s primaryThreatScore=%.2f threatSwitchReason=%s escapeReferenceKind=%s escapeReferenceEntityId=%s escapeReferencePosition=%s,%s escapeReferenceConfidence=%.2f lastKnownThreatId=%s lastKnownThreatAge=%s lastKnownThreatConfidence=%.2f socialAlarmSourceCount=%s strongestSocialSourceId=%s socialEscapeBias=%s,%s socialEscapeBiasConfidence=%.2f fleeEpisodeTargetId=%s movementDiagnosticTargetId=%s valid=%s error=%s",
          tostring(entity.id), tostring(assessment.primaryThreatId or "none"),
          tostring(assessment.previousPrimaryThreatId or "none"),
          tostring(assessment.primaryThreatReason or "NONE"), assessment.primaryThreatScore or 0,
          tostring(assessment.threatSwitchReason or "NONE"),
          tostring(escapeReference.kind or "none"),
          tostring(escapeReference.entityId or "none"),
          tostring(escapeReference.position and escapeReference.position.cellX or "none"),
          tostring(escapeReference.position and escapeReference.position.cellY or "none"),
          escapeReference.confidence or 0,
          tostring(entity.runtimeState.fleeThreatEntityId or "none"),
          tostring(escapeReference.age or "none"),
          escapeReference.kind == "LAST_KNOWN_THREAT_POSITION"
            and (escapeReference.confidence or 0) or 0,
          tostring(entity.runtimeState.nearbyFearSources or 0),
          tostring(entity.runtimeState.strongestFearSource or "none"),
          tostring(entity.runtimeState.socialEscapeBias and entity.runtimeState.socialEscapeBias.dx or "none"),
          tostring(entity.runtimeState.socialEscapeBias and entity.runtimeState.socialEscapeBias.dy or "none"),
          entity.runtimeState.socialEscapeBiasConfidence or 0,
          tostring(entity.runtimeState.intentEpisode and entity.runtimeState.intentEpisode.targetId or "none"),
          tostring(request.targetEntityId or "none"), tostring(validProvenance),
          tostring(provenanceError or "none")
          ))
        else
          writeDebugLog(mod, "behavior", string.format(
            "FLEE provenance actor=%s threat=%s reason=%s reference=%s referenceActor=%s valid=%s error=%s",
            tostring(entity.id), tostring(assessment.primaryThreatId or "none"),
            tostring(assessment.primaryThreatReason or "NONE"),
            tostring(escapeReference.kind or "none"),
            tostring(escapeReference.entityId or "none"), tostring(validProvenance),
            tostring(provenanceError or "none")
          ))
        end
      end
      local trace = readBehaviorTraceEnabled(mod)
      local semantic = TelemetryPolicy.fleeRouteSemantic(fleeExecution)
      local congestionState = semantic.congestionState
      local suspensionState = semantic.suspensionState
      local lifecycleState = semantic.lifecycleState
      local endpoint = fleeExecution and fleeExecution.escapeEndpoint
      local routeSignature = semantic.signature
      local previousRouteState = entity.runtimeState.lastFleeRouteDiagnosticState
      local routeEvent = TelemetryPolicy.fleeRouteEvent(previousRouteState, semantic)
      local routeChanged = entity.runtimeState.lastFleeRouteDiagnosticSignature ~= routeSignature
      if trace or routeChanged then
        local suppressed = entity.runtimeState.fleeRouteNormalSuppressedUnchanged or 0
        if not trace then
          WildEcology.telemetryDiagnostics.fleeRouteNormalRecords
            = WildEcology.telemetryDiagnostics.fleeRouteNormalRecords + 1
        end
        entity.runtimeState.lastFleeRouteDiagnosticSignature = routeSignature
        entity.runtimeState.lastFleeRouteDiagnosticState = semantic
        entity.runtimeState.fleeRouteNormalSuppressedUnchanged = 0
        if trace then
          writeDebugLog(mod, "behavior", string.format(
            "FLEE route actor=%s event=%s suppressedUnchanged=%s routeThreatSourceId=%s routeThreatReferenceKind=%s routeEstablishedTick=%s routeTemporaryRegressionActive=%s routeRegressionDebt=%s routeExpectedSource=%s,%s routeNextAction=%s routeEndpoint=%s,%s routeEndpointThreatDistance=%s currentThreatSourceId=%s sameThreatSource=%s routeRevalidated=%s routeRevalidationReason=%s routeInvalidated=%s routeInvalidationReason=%s routeSuspended=%s congestionState=%s localGreedyCandidate=%s localGreedySuppressedByRoute=%s",
            tostring(entity.id), tostring(routeEvent), tostring(suppressed),
            tostring(fleeExecution and fleeExecution.routeThreatSourceId or "none"),
            tostring(fleeExecution and fleeExecution.routeThreatReferenceKind or "none"),
            tostring(fleeExecution and fleeExecution.routeEstablishedTick or "none"),
            tostring(fleeExecution and fleeExecution.routeTemporaryRegressionActive == true),
            tostring(fleeExecution and fleeExecution.routeRegressionDebt or 0),
            tostring(fleeExecution and fleeExecution.routeExpectedSource
              and fleeExecution.routeExpectedSource.cellX or "none"),
            tostring(fleeExecution and fleeExecution.routeExpectedSource
              and fleeExecution.routeExpectedSource.cellY or "none"),
            tostring(fleeExecution and fleeExecution.routeNextAction or "none"),
            tostring(endpoint and endpoint.cellX or "none"),
            tostring(endpoint and endpoint.cellY or "none"),
            tostring(fleeExecution and fleeExecution.endpointThreatDistance or "none"),
            tostring(fleeExecution and fleeExecution.currentThreatSourceId or "none"),
            tostring(fleeExecution and fleeExecution.sameThreatSource == true),
            tostring(fleeExecution and fleeExecution.routeRevalidated == true),
            tostring(fleeExecution and fleeExecution.routeRevalidationReason or "none"),
            tostring(fleeExecution and fleeExecution.routeInvalidationTick == request.issuedTick),
            tostring(fleeExecution and fleeExecution.routeInvalidationReason or "none"),
            tostring(fleeExecution and fleeExecution.routeSuspended == true),
            tostring(congestionState),
            tostring(fleeExecution and fleeExecution.localGreedyCandidate or "none"),
            tostring(fleeExecution and fleeExecution.localGreedySuppressedByRoute == true)
          ))
        else
          writeDebugLog(mod, "behavior", string.format(
            "FLEE route actor=%s event=%s suppressedUnchanged=%s lifecycle=%s mode=%s routeEstablishedTick=%s threat=%s reference=%s invalidation=%s suspension=%s congestion=%s endpoint=%s,%s",
            tostring(entity.id), tostring(routeEvent), tostring(suppressed),
            tostring(lifecycleState),
            tostring(fleeExecution and fleeExecution.fleeMode or "NORMAL"),
            tostring(fleeExecution and fleeExecution.routeEstablishedTick or "none"),
            tostring(fleeExecution and fleeExecution.routeThreatSourceId or "none"),
            tostring(fleeExecution and fleeExecution.routeThreatReferenceKind or "none"),
            tostring(fleeExecution and fleeExecution.routeInvalidationReason or "none"),
            tostring(suspensionState), tostring(congestionState),
            tostring(endpoint and endpoint.cellX or "none"),
            tostring(endpoint and endpoint.cellY or "none")
          ))
        end
      else
        entity.runtimeState.fleeRouteNormalSuppressedUnchanged
          = (entity.runtimeState.fleeRouteNormalSuppressedUnchanged or 0) + 1
        WildEcology.telemetryDiagnostics.fleeRouteNormalSuppressedUnchanged
          = WildEcology.telemetryDiagnostics.fleeRouteNormalSuppressedUnchanged + 1
      end
    end
    local movementSignature = table.concat({
      tostring(entity.runtimeState.intent or entity.runtimeState.state or "none"),
      tostring(request.direction),
      tostring(movementResult),
      tostring(motion and motion.active or false),
      tostring(fleeExecution and fleeExecution.escapeMode or false),
      tostring(fleeExecution and fleeExecution.noProgressSteps or 0),
      tostring(entity.runtimeState.searchCueSource or "none"),
      tostring(entity.runtimeState.searchCueDirection or "none"),
      tostring(entity.runtimeState.navigation and entity.runtimeState.navigation.replanReason or "none")
    }, ":")
    local routineWalkSuccess = applied == true
      and request.traversalMode == "WALK"
      and request.rejectionReason == nil
      and not (fleeExecution and (fleeExecution.noProgressSteps or 0) >= 2)
      and not (fleeExecution and fleeExecution.oscillationDetected == true)
      and not (entity.runtimeState.navigation
        and entity.runtimeState.navigation.replanReason ~= nil)
    local shouldLog = movementResult ~= "MOVEMENT_ACTIVE"
      and entity.runtimeState.lastMovementSignature ~= movementSignature
      and (readBehaviorTraceEnabled(mod) or not routineWalkSuccess)
    entity.runtimeState.lastMovementSignature = movementSignature
    if debugState then
      debugState.lastMovementRequest = request.direction
      debugState.lastMotionActive = entity.runtimeState.motion and entity.runtimeState.motion.active or false
    end
    if shouldLog then
      local selfPosition = buildPositionEntity(avatar)
      if readBehaviorTraceEnabled(mod) then
        writeDebugLog(mod, "behavior", string.format(
        "Movement request actor=%s intent=%s from=%s,%s direction=%s primaryThreatId=%s primaryThreatReason=%s escapeReferenceKind=%s escapeReferenceEntityId=%s result=%s reason=%s active=%s threatDistance=%s fleeMode=%s stuckReason=%s noProgressSteps=%s escapeRouteLength=%s escapeRouteIndex=%s escapeEndpoint=%s,%s endpointThreatDistance=%s endpointMobility=%s nextStepThreatDelta=%s temporaryThreatRegression=%s routeInvalidationReason=%s isolation=%s cueSource=%s cueDirection=%s navGoal=%s waypoint=%s,%s routeLength=%s nextMode=%s nextDirection=%s replanReason=%s specialTraversal=%s",
        tostring(entity.id),
        tostring(entity.runtimeState.intent or entity.runtimeState.state or "none"),
        tostring(selfPosition and selfPosition.cellX or "none"),
        tostring(selfPosition and selfPosition.cellY or "none"),
        tostring(request.direction),
        tostring(request.primaryThreatId or "none"),
        tostring(assessment.primaryThreatReason or "NONE"),
        tostring(request.escapeReferenceKind or "none"),
        tostring(request.escapeReferenceEntityId or "none"),
        tostring(applied),
        tostring(request.rejectionReason or "none"),
        tostring(motion and motion.active or false),
        tostring(fleeExecution and fleeExecution.threatDistance or "none"),
        tostring(fleeExecution and fleeExecution.fleeMode or "NORMAL"),
        tostring(fleeExecution and fleeExecution.stuckReason or "none"),
        tostring(fleeExecution and fleeExecution.noProgressSteps or 0),
        tostring(fleeExecution and fleeExecution.escapeRouteLength or 0),
        tostring(fleeExecution and fleeExecution.route and fleeExecution.route.index or 0),
        tostring(fleeExecution and fleeExecution.escapeEndpoint and fleeExecution.escapeEndpoint.cellX or "none"),
        tostring(fleeExecution and fleeExecution.escapeEndpoint and fleeExecution.escapeEndpoint.cellY or "none"),
        tostring(fleeExecution and fleeExecution.endpointThreatDistance or "none"),
        tostring(fleeExecution and fleeExecution.endpointMobility or "none"),
        tostring(fleeExecution and fleeExecution.nextStepThreatDelta or "none"),
        tostring(fleeExecution and fleeExecution.temporaryThreatRegression or false),
        tostring(fleeExecution and fleeExecution.routeInvalidationReason or "none"),
        tostring(entity.runtimeState.searchIsolationPressure or "none"),
        tostring(entity.runtimeState.searchCueSource or "none"),
        tostring(entity.runtimeState.searchCueDirection or "none"),
        tostring(entity.runtimeState.navigation and entity.runtimeState.navigation.goalKind or "none"),
        tostring(request.waypoint and request.waypoint.cellX or "none"),
        tostring(request.waypoint and request.waypoint.cellY or "none"),
        tostring(request.routeLength or "none"),
        tostring(request.traversalMode or "none"),
        tostring(request.direction or "none"),
        tostring(entity.runtimeState.navigation and entity.runtimeState.navigation.replanReason or "none"),
        tostring(request.traversalMode ~= "WALK" and request.traversalMode or "none")
        ))
      else
        writeDebugLog(mod, "behavior", string.format(
          "Movement request actor=%s intent=%s from=%s,%s direction=%s result=%s reason=%s replan=%s noProgress=%s oscillation=%s traversal=%s fleeTrace=%s,%s->%s,%s threat=%s endpoint=%s,%s",
          tostring(entity.id), tostring(entity.runtimeState.intent or entity.runtimeState.state or "none"),
          tostring(selfPosition and selfPosition.cellX or "none"),
          tostring(selfPosition and selfPosition.cellY or "none"), tostring(request.direction),
          tostring(applied), tostring(request.rejectionReason or "none"),
          tostring(entity.runtimeState.navigation
            and entity.runtimeState.navigation.replanReason or "none"),
          tostring(fleeExecution and fleeExecution.noProgressSteps or 0),
          tostring(fleeExecution and fleeExecution.oscillationDetected == true),
          tostring(request.traversalMode or "none"),
          tostring(request.fleeTrace and request.fleeTrace.actorX or "none"),
          tostring(request.fleeTrace and request.fleeTrace.actorY or "none"),
          tostring(request.fleeTrace and request.fleeTrace.threatX or "none"),
          tostring(request.fleeTrace and request.fleeTrace.threatY or "none"),
          tostring(request.fleeTrace and request.fleeTrace.threatId or "none"),
          tostring(request.fleeTrace and request.fleeTrace.endpointX or "none"),
          tostring(request.fleeTrace and request.fleeTrace.endpointY or "none")
        ))
      end
    end
  elseif readPhase5DiagnosticsEnabled(mod)
    and movementApiChanged
    and entity.runtimeState.movementApi == "UNAVAILABLE"
    and request
    and request.traversalMode == "WALK" then
    writeDebugLog(mod, "behavior", "Movement API unavailable: stock NPC internals are not reachable")
  end
  return applied
end

local function materializationAttempt(mod, mapId, entity, path, visitCell)
  local status, details = "UNKNOWN", {}
  if PopulationManager and PopulationManager.assessMaterialization then
    status, details = PopulationManager.assessMaterialization(entity, mod, mapId)
  end
  if visitCell then
    local semantics = WorldSemantics and WorldSemantics.fromMod
      and WorldSemantics.fromMod(mod, mapId) or nil
    local cellDetails = SpawnCells and SpawnCells.inspect
      and SpawnCells.inspect(entity, semantics, visitCell, mod, mapId) or nil
    if cellDetails then
      status, details = cellDetails.reason, cellDetails
    end
  end
  if entity and entity.home then
    entity.home.spawnViability = status
  end
  details = type(details) == "table" and details or {}
  local allowed = status == "VALID" or status == "UNKNOWN"
  local runtime = WildEcology.spawnDiagnostics
  runtime.materializationAttempts = runtime.materializationAttempts + 1
  runtime.materializationStatus = allowed and "VALID" or "REJECTED"
  if allowed then
    runtime.materializationValid = runtime.materializationValid + 1
    runtime.lastSpawnStatus = "PENDING"
  else
    runtime.materializationRejected = runtime.materializationRejected + 1
    runtime.lastSpawnStatus = "NOT_CALLED"
    runtime.lastRejectedEntity = entity and entity.id or "unknown"
    runtime.lastRejectedCell = details.canonicalCell
      and tostring(details.canonicalCell.cellX) .. "," .. tostring(details.canonicalCell.cellY)
      or "NONE"
    runtime.lastRejectReason = status
  end
  return {
    entity = entity,
    mapId = mapId,
    path = path,
    status = status,
    details = details,
    canonicalCell = details.canonicalCell,
    allowed = allowed
  }
end

local function diagnosticValue(value)
  if value == nil then return "unknown" end
  if type(value) == "string" then return string.format("%q", value) end
  return tostring(value)
end

local function diagnosticCell(cell)
  if not cell then return "none" end
  return tostring(cell.cellX) .. "," .. tostring(cell.cellY)
end

local function logMaterializationAttempt(mod, attempt, avatar)
  local entity = attempt.entity or {}
  local details = attempt.details or {}
  local raw = details.rawPosition or {}
  local initialCell = avatar and buildPositionEntity(avatar) or nil
  local requestedCell = attempt.allowed and attempt.canonicalCell or nil
  local outcome = avatar and "SPAWNED" or (attempt.allowed and "SPAWN_FAILED" or "REJECTED")
  local signature = table.concat({
    tostring(attempt.mapId), tostring(attempt.path), tostring(details.positionSource),
    tostring(attempt.status), diagnosticCell(attempt.canonicalCell), outcome,
    diagnosticCell(initialCell)
  }, ":")
  if WildEcology.materializationDiagnostics[entity.id] == signature then
    return
  end
  WildEcology.materializationDiagnostics[entity.id] = signature
  local message = string.format(
    "Materialization event=avatar_materialization entity=%s map=%s path=%s source=%s rawPosition=spawnX:%s,spawnY:%s,avatarX:%s,avatarY:%s canonicalCell=%s worldWidth=%s worldHeight=%s inBounds=%s overviewCell=%s semanticCellKind=%s environmentClass=%s isLandingAllowed=%s spawnClass=%s spawnAllowed=%s spawnRestrictionReason=%s requiresOverworldExit=%s reachableOverworldExit=%s spawnViability=%s spawnViabilityReason=%s connectionSource=%s usableConnectionSource=%s materializationAllowed=%s avatarRequestedCell=%s avatarInitialCell=%s outcome=%s",
    tostring(entity.id or "unknown"),
    tostring(attempt.mapId or "unknown"),
    tostring(attempt.path or "unknown"),
    tostring(details.positionSource or "unknown"),
    diagnosticValue(raw.spawnX), diagnosticValue(raw.spawnY),
    diagnosticValue(raw.avatarX), diagnosticValue(raw.avatarY),
    diagnosticCell(attempt.canonicalCell),
    diagnosticValue(details.worldWidth), diagnosticValue(details.worldHeight),
    diagnosticValue(details.inBounds), diagnosticValue(details.overviewCell),
    diagnosticValue(details.semanticCellKind), diagnosticValue(details.environmentClass),
    diagnosticValue(details.isLandingAllowed), diagnosticValue(details.spawnClass),
    diagnosticValue(details.spawnAllowed), diagnosticValue(details.spawnRestrictionReason),
    diagnosticValue(details.requiresOverworldExit), diagnosticValue(details.reachableOverworldExit),
    diagnosticValue(details.spawnViability), diagnosticValue(attempt.status),
    diagnosticValue(details.connectionSource), diagnosticValue(details.usableConnectionSource),
    diagnosticValue(attempt.allowed), diagnosticCell(requestedCell),
    diagnosticCell(initialCell), outcome
  )
  if shouldCaptureDebugCategory(mod, "lifecycle") then
    if readSaveFlag(mod, DEBUG_LOG_CONSOLE_OPTION_KEY, false) == true then
      queueConsoleLog("lifecycle", message)
    end
    if outcome ~= "SPAWNED" and DebugLogger then
      DebugLogger.log("lifecycle", message)
    end
  end
end

local function spawnPhase0Avatar(mod, mapId, eventName, simulationTick)
  local phase0 = (Config and Config.phase0) or {}

  if WildEcology.activeAvatars[phase0.testEntityId] then
    return nil
  end

  local existing = PopulationManager and PopulationManager.getOrCreatePhase0Entity
    and PopulationManager.getOrCreatePhase0Entity(mod) or nil
  if existing and Concealment and Concealment.isConcealed(existing, mapId) then
    WildEcology.entityById[existing.id] = existing
    return { entity = existing, state = "CONCEALED", mapId = mapId }
  end

  local payload = evaluatePhase0State(mod, mapId, true, simulationTick)
  if not payload or not AvatarFactory or not AvatarFactory.spawn then
    return nil
  end
  local attempt = materializationAttempt(mod, mapId, payload.entity, "ANCHOR")
  if not attempt.allowed then
    logMaterializationAttempt(mod, attempt, nil)
    return payload
  end

  if WildEcology.movementClaims then
    WildEcology.movementClaims:clear(payload.entity.id, simulationTick, "RUNTIME_RESET")
  end
  RuntimeState.reset(payload.entity)
  WildEcology.spawnDiagnostics.anchorCalls = WildEcology.spawnDiagnostics.anchorCalls + 1
  local avatar = RuntimeAvatarAdapter and RuntimeAvatarAdapter.materialize
    and RuntimeAvatarAdapter.materialize(mod, payload.entity, attempt.canonicalCell, mapId)
    or AvatarFactory.spawn(mod, payload.entity, attempt.canonicalCell, mapId)
  WildEcology.spawnDiagnostics.lastSpawnStatus = avatar and "SPAWNED" or "SPAWN_FAILED"
  logMaterializationAttempt(mod, attempt, avatar)
  if avatar then
    PopulationManager.markSpawnPositionPersisted(payload.entity)
    avatar.spawnSequence = payload.entity.memory.debug.respawnCount
    WildEcology.activeAvatars[payload.entity.id] = avatar

    -- The initial behavior evaluation happens before the avatar exists. Re-evaluate
    -- once so reconstructed avatars can issue their first movement request immediately.
    local postSpawnPayload = evaluatePhase0State(mod, mapId, false, simulationTick)
    if postSpawnPayload then
      applyMovementRequestToAvatar(mod, avatar, postSpawnPayload.entity)
    end

    local debugState = getPhase0DebugState()
    applyPhase0DebugState(debugState, postSpawnPayload or payload, eventName or "spawn", avatar.id)

    writeDebugLog(mod, "behavior", string.format("Behavior resolved to %s under mode %s with trust=%s and threat=%s", tostring(payload.state), tostring(payload.behaviorMode), tostring(payload.rel.trust or 0), tostring(payload.rel.threatMemory or 0)))
    writeDebugLog(mod, "lifecycle", string.format("Spawned avatar %s on %s with respawn count %s", tostring(avatar.id or "none"), tostring(payload.entity.home.mapId or "none"), tostring(payload.entity.memory.debug.respawnCount or 0)))

    if Save and Save.flush then
      Save.flush()
    end
  end

  return payload
end

local function evaluateVisibleEntity(mod, mapId, entity, avatar, simulationTick, reason)
  local player = getPlayerEntity()
  local behaviorMode = readBehaviorMode(mod)
  local ignoringPlayer = behaviorMode == "ignore_player"
  local playerDistance = ignoringPlayer and nil or getDistanceToPlayer(mod, avatar)
  if AvatarFactory and AvatarFactory.refreshMotionState then
    AvatarFactory.refreshMotionState(mod, avatar, entity)
  end

  local rel = PopulationManager.updatePhase0Relationship(entity, player, simulationTick, playerDistance)
  local debugPreset = behaviorMode and behaviorMode:match("^force_(.+)$")

  local position = buildPositionEntity(avatar) or persistedHomePosition(entity)
  local behaviorTargets = buildBehaviorTargets(entity, position, player, playerDistance, ignoringPlayer, debugPreset, perceptionPositionForPlayer(mod), simulationTick, mod, mapId)
  if behaviorTargets.threatAssessment and behaviorTargets.threatAssessment.primaryThreatId then
    rel = behaviorTargets.threatAssessment.primaryThreatRelationship or rel
  elseif behaviorTargets.socialTargetId then
    rel = entity.relationships and entity.relationships[behaviorTargets.socialTargetId] or rel
  end
  local preset = BehaviorDebugPreset.apply(debugPreset, entity, {
    id = player.id, kind = "trainer", distance = playerDistance,
    relationship = rel, motion = "STABLE"
  }, rel)
  if preset.name then rel = preset.relationship end
  local runtimeBefore = entity.runtimeState or {}
  local beforeNavigationRoute = runtimeBefore.navigation and runtimeBefore.navigation.route
  local beforeFleeRoute = runtimeBefore.fleeExecution and runtimeBefore.fleeExecution.route
  local stateName = Controller.tick(entity, rel, behaviorTargets.targetDistance, {
    ecologyPhase = WildEcology.currentClockSample
      and WildEcology.currentClockSample.phase or 0.5,
    behaviorEntity = preset.name and preset.entity or nil,
    debugPreset = preset.name,
    debugPresetOriginalInputs = preset.name and preset.originalInputs or nil,
    debugPresetReplacedInputs = preset.name and preset.replacedInputs or nil,
    targetEntityId = behaviorTargets.targetEntityId,
    threatAssessment = behaviorTargets.threatAssessment,
    fleeNeighbors = behaviorTargets.fleeNeighbors,
    hasTarget = preset.name == nil and behaviorTargets.hasTarget or preset.hasTarget,
    purposefulTarget = preset.name == nil and behaviorTargets.purposefulTarget or preset.purposefulTarget,
    conspecific = behaviorTargets.targetIsConspecific,
    candidates = behaviorTargets.candidates,
    position = position,
    mapId = mapId,
    targetPositions = behaviorTargets.targetPositions,
    groupHeadingBias = behaviorTargets.groupHeadingBias,
    flockSearch = behaviorTargets.flockSearch,
    worldSemantics = behaviorTargets.worldSemantics,
    occupiedCells = behaviorTargets.occupiedCells,
    occupiedCellCount = behaviorTargets.occupiedCellCount,
    reservationCount = behaviorTargets.reservationCount,
    perceivedFear = entity.runtimeState and entity.runtimeState.perceivedFear and entity.runtimeState.perceivedFear[behaviorTargets.targetEntityId] or 0,
    currentFear = preset.fearCurrent ~= nil and preset.fearCurrent
      or entity.runtimeState and entity.runtimeState.fearCurrent or 0,
    allowTargeting = preset.allowTargeting,
    debugIdleElapsed = preset.idleElapsed,
    debugSettledElapsed = preset.settledElapsed,
    goalRadius = 1,
    investigateRadius = 3,
    locomotionPacing = true,
    fleeRadius = entity.runtimeState and entity.runtimeState.fleeRadius or 1
  }, simulationTick)
  if stateName == "FLEE" then
    performanceCount("flee_selected")
    if entity.runtimeState and entity.runtimeState.fleeExecution
      and entity.runtimeState.fleeExecution.escapeEndpoint then
      performanceCount("flee_endpoint_planned")
    end
    if entity.runtimeState and entity.runtimeState.movementRequest then
      performanceCount("flee_request_created")
    end
  end
  recordBehaviorDecision(mapId, entity, simulationTick, stateName, reason or "CADENCE")
  entity.runtimeState.lastSchedulerDebugPreset = debugPreset
  local runtime = entity.runtimeState
  runtime.schedulerMetrics = runtime.schedulerMetrics or {}
  local metrics = runtime.schedulerMetrics
  metrics.executionUpdates = (metrics.executionUpdates or 0) + 1
  local navigationReplanned = beforeNavigationRoute ~= (runtime.navigation and runtime.navigation.route)
    or beforeFleeRoute ~= (runtime.fleeExecution and runtime.fleeExecution.route)
  runtime.navigationReplanned = navigationReplanned
  runtime.navigationReplanReason = runtime.navigation and runtime.navigation.replanReason
    or runtime.fleeExecution and runtime.fleeExecution.routeInvalidationReason
    or "NONE"
  if navigationReplanned then
    metrics.navigationReplans = (metrics.navigationReplans or 0) + 1
  end
  local request = runtime.movementRequest
  runtime.movementRequested = request ~= nil and request.issuedTick == simulationTick
    and request.traversalMode == "WALK"
  if runtime.movementRequested then
    metrics.movementRequests = (metrics.movementRequests or 0) + 1
  end
  logFocusedFleeDecision(mod, entity, position, simulationTick)
  logFocusedTrainerDecision(mod, entity, simulationTick)
  logFocusedIntentDecision(mod, entity, simulationTick)
  applyPhase0AvatarBehavior(entity, stateName)
  if not enterRequestedConcealment(mod, entity, simulationTick) then
    applyMovementRequestToAvatar(mod, avatar, entity)
  end
  return stateName
end

local function executionContextForVisibleEntity(mod, mapId, entity, avatar, simulationTick)
  local profileName, profileStart = performanceStart("execution_context")
  local runtime = entity.runtimeState or {}
  local position = buildPositionEntity(avatar) or persistedHomePosition(entity)
  local targetPositions = {}
  local targetId = runtime.targetEntityId
  if targetId == "player" then
    targetPositions.player = perceptionPositionForPlayer(mod)
  elseif targetId and WildEcology.activeAvatars[targetId] then
    targetPositions[targetId] = buildPositionEntity(WildEcology.activeAvatars[targetId])
  elseif targetId and runtime.fleeThreatPosition then
    targetPositions[targetId] = runtime.fleeThreatPosition
  end

  local occupiedCells, currentOccupiedCells, vacatingCells, occupancyDetails = {}, {}, {}, {}
  local occupiedCellCount, reservationCount = 0, 0
  local fleeNeighbors = {}
  for otherId, otherAvatar in pairs(WildEcology.activeAvatars) do
    if otherId ~= entity.id then
      local otherPosition = buildPositionEntity(otherAvatar)
      local otherEntity = WildEcology.entityById[otherId]
      local otherMotion = otherEntity and otherEntity.runtimeState
        and otherEntity.runtimeState.motion
      local otherClaim = WildEcology.movementClaims
        and WildEcology.movementClaims:claimForActor(otherId) or nil
      if otherPosition then
        local key = WorldSemantics.cellKey(otherPosition.cellX, otherPosition.cellY)
        if not occupiedCells[key] then
          occupiedCells[key] = true
          occupiedCellCount = occupiedCellCount + 1
        end
        currentOccupiedCells[key] = true
        if otherClaim and (otherClaim.toX ~= otherPosition.cellX
          or otherClaim.toY ~= otherPosition.cellY) then
          vacatingCells[key] = true
        end
        recordOccupancy(occupancyDetails, key, otherId,
          "CURRENT_NPC_CELL", otherPosition,
          otherClaim and { cellX = otherClaim.toX, cellY = otherClaim.toY }
            or nil, otherMotion)
        fleeNeighbors[#fleeNeighbors + 1] = { entity = otherEntity, position = otherPosition }
      end
      if otherClaim then
        local key = WorldSemantics.cellKey(otherClaim.toX, otherClaim.toY)
        if not occupiedCells[key] then
          occupiedCells[key] = true
          occupiedCellCount = occupiedCellCount + 1
        end
        recordOccupancy(occupancyDetails, key, otherId,
          "MOTION_DESTINATION_RESERVATION", otherPosition, {
            cellX = otherClaim.toX,
            cellY = otherClaim.toY
          }, otherMotion)
        reservationCount = reservationCount + 1
      end
    end
  end

  local search = runtime.flockSearch
  if search and search.utility == nil then
    search.utility = runtime.rawSeekFlockUtility or 0
  end
  local socialAlarmTargetPosition = nil
  local socialBias = runtime.socialEscapeBias
  if position and socialBias and (runtime.socialEscapeBiasConfidence or 0) >= 0.2
    and (socialBias.dx ~= 0 or socialBias.dy ~= 0) then
    socialAlarmTargetPosition = {
      cellX = position.cellX - socialBias.dx * 3,
      cellY = position.cellY - socialBias.dy * 3
    }
  end
  local context = {
    executionOnly = true,
    executionUpdateReason = runtime.motion and runtime.motion.justCompleted
      and "MOVEMENT_COMPLETED" or runtime.movementRequest == nil
      and "ACTION_NEEDED" or "MOTION_POLL",
    hasTarget = targetId ~= nil and targetPositions[targetId] ~= nil,
    targetEntityId = targetId,
    position = position,
    mapId = mapId,
    targetPositions = targetPositions,
    flockSearch = search,
    threatAssessment = runtime.threatAssessment,
    currentFear = runtime.fearCurrent or 0,
    socialAlarmTargetPosition = socialAlarmTargetPosition,
    worldSemantics = WorldSemantics.fromMod(mod, mapId),
    occupiedCells = occupiedCells,
    currentOccupiedCells = currentOccupiedCells,
    vacatingCells = vacatingCells,
    occupancyDetails = occupancyDetails,
    movementClaims = WildEcology.movementClaims,
    occupiedCellCount = occupiedCellCount,
    reservationCount = reservationCount,
    fleeNeighbors = fleeNeighbors,
    goalRadius = 1,
    investigateRadius = 3,
    locomotionPacing = true,
    fleeRadius = runtime.fleeRadius or 1,
    fleeSafetyDistance = runtime.fleeDesiredSafetyDistance
  }
  performanceStop(profileName, profileStart)
  return context
end

local function executeVisibleEntity(mod, mapId, entity, avatar, simulationTick)
  performanceCount("execution_calls")
  local totalName, totalStart = performanceStart("execution_total")
  if AvatarFactory and AvatarFactory.refreshMotionState then
    AvatarFactory.refreshMotionState(mod, avatar, entity)
  end
  local runtime = entity.runtimeState or {}
  if (runtime.state == "SETTLED" or runtime.state == "IDLE")
    and runtime.movementRequest == nil
    and not (runtime.motion and runtime.motion.active)
    and not (Controller and Controller.isEmergencyThreat
      and Controller.isEmergencyThreat(runtime, runtime.threatAssessment)) then
    performanceCount("execution_settled_fast_path")
    runtime.executionUpdated = true
    runtime.executionUpdateReason = "SETTLED_FAST_PATH"
    runtime.executionTerminalReason = nil
    runtime.schedulerMetrics = runtime.schedulerMetrics or {}
    runtime.schedulerMetrics.executionUpdates =
      (runtime.schedulerMetrics.executionUpdates or 0) + 1
    performanceStop(totalName, totalStart)
    return nil
  end
  local beforeNavigationRoute = runtime.navigation and runtime.navigation.route
  local beforeFleeRoute = runtime.fleeExecution and runtime.fleeExecution.route
  if runtime.motion and runtime.motion.active then
    performanceCount("execution_motion_polls")
  end
  local context = executionContextForVisibleEntity(mod, mapId, entity, avatar, simulationTick)
  local controllerName, controllerStart = performanceStart("execution_controller")
  local stateName = Controller.executeCurrentIntent(entity, context, simulationTick)
  performanceStop(controllerName, controllerStart)
  if stateName == "FLEE" then
    performanceCount("flee_execution")
    if entity.runtimeState and entity.runtimeState.fleeExecution
      and entity.runtimeState.fleeExecution.escapeEndpoint then
      performanceCount("flee_endpoint_planned")
    end
    if entity.runtimeState and entity.runtimeState.movementRequest then
      performanceCount("flee_request_created")
    end
  end
  investigateRuntimeDiagnostic(mod, entity, context, simulationTick)
  runtime = entity.runtimeState
  runtime.schedulerMetrics = runtime.schedulerMetrics or {}
  local metrics = runtime.schedulerMetrics
  metrics.executionUpdates = (metrics.executionUpdates or 0) + 1
  local navigationReplanned = beforeNavigationRoute ~= (runtime.navigation and runtime.navigation.route)
    or beforeFleeRoute ~= (runtime.fleeExecution and runtime.fleeExecution.route)
  runtime.navigationReplanned = navigationReplanned
  runtime.navigationReplanReason = runtime.navigation and runtime.navigation.replanReason
    or runtime.fleeExecution and runtime.fleeExecution.routeInvalidationReason
    or "NONE"
  if navigationReplanned then
    metrics.navigationReplans = (metrics.navigationReplans or 0) + 1
  end
  local request = runtime.movementRequest
  runtime.movementRequested = request ~= nil and request.issuedTick == simulationTick
    and request.traversalMode == "WALK"
  if runtime.movementRequested then
    metrics.movementRequests = (metrics.movementRequests or 0) + 1
  end
  local anchorId = Config and Config.phase0 and Config.phase0.testEntityId or nil
  local focusedId = WildEcology.focusedEntityId or anchorId
  if readBehaviorTraceEnabled(mod) and entity.id == focusedId then
    writeDebugLog(mod, "behavior", string.format(
      "Execution trace actor=%s tick=%s intent=%s episode=%s episodeAge=%s deliberationDue=%s deliberationPerformed=%s executionReason=%s perceptionUpdated=%s fearUpdated=%s navigationReplanned=%s navigationReplanReason=%s movementRequested=%s",
      tostring(entity.id), tostring(simulationTick),
      tostring(runtime.state or "none"),
      tostring(runtime.intentEpisodeStatus or "NONE"),
      tostring(runtime.intentEpisodeAge or 0),
      tostring(runtime.deliberationDue == true),
      tostring(runtime.deliberationPerformed == true),
      tostring(runtime.executionUpdateReason or "NONE"),
      tostring(runtime.perceptionUpdated == true),
      tostring(runtime.fearUpdated == true),
      tostring(runtime.navigationReplanned == true),
      tostring(runtime.navigationReplanReason or "NONE"),
      tostring(runtime.movementRequested == true)
    ))
  end
  applyPhase0AvatarBehavior(entity, stateName)
  if not enterRequestedConcealment(mod, entity, simulationTick) then
    local movementName, movementStart = performanceStart("execution_movement")
    applyMovementRequestToAvatar(mod, avatar, entity)
    performanceStop(movementName, movementStart)
  end
  performanceStop(totalName, totalStart)
  return runtime.executionTerminalReason
end

local function spawnPhase3Avatars(mod, mapId, seed)
  local runtime = WildEcology.spawnDiagnostics
  runtime.phase3Entered = runtime.phase3Entered + 1

  local visiblePopulation = PopulationManager and PopulationManager.getVisibleRoutePopulation
    and PopulationManager.getVisibleRoutePopulation(mapId, seed, mod)
    or nil
  local state = Save and Save.getState and Save.getState() or nil
  local population = state and state.populations and state.populations[mapId] or nil
  local members = population and population.members or {}
  local production = PopulationManager and PopulationManager.getSpawnDebugSnapshot
    and PopulationManager.getSpawnDebugSnapshot(mapId) or nil
  runtime.populationPersistentTotal = 0
  runtime.populationEligibleTotal = 0
  runtime.populationSelectedTotal = type(visiblePopulation) == "table"
    and #visiblePopulation or 0
  runtime.visibleSelectionCalls = (runtime.visibleSelectionCalls or 0) + 1
  WildEcology.visiblePopulationByMap[mapId] = visiblePopulation
  local visitCells = {}
  local occupiedKeys = {}
  local analysis = production and production.candidateAnalysis or nil
  for _, entity in ipairs(visiblePopulation or {}) do
    local home = entity and entity.home
    if home and home.spawnX ~= nil and home.spawnY ~= nil then
      occupiedKeys[SpawnCells.keyForCell({ x = home.spawnX, y = home.spawnY })] = true
    end
  end
  for index, entity in ipairs(visiblePopulation or {}) do
    if (WildEcology.routeVisitCounts[mapId] or 0) <= 1 then
      break
    end
    if entity and entity.id ~= (Config and Config.phase0 and Config.phase0.testEntityId)
      and not Concealment.isConcealed(entity, mapId) and SpawnCells
      and SpawnCells.pickCell then
      local picked = SpawnCells.pickCell(mapId, entity.home and entity.home.zoneId,
        occupiedKeys, (seed or 0) + index * 7919, mod, entity, analysis)
      if picked then
        visitCells[entity.id] = { cellX = picked.x, cellY = picked.y }
        occupiedKeys[SpawnCells.keyForCell(picked)] = true
      end
    end
  end
  WildEcology.visitSpawnCells[mapId] = visitCells
  runtime.populationConcealedTotal = 0
  runtime.populationInvalidLocationTotal = 0
  runtime.populationAlreadyActiveTotal = 0
  runtime.spawnCellsAvailable = production and production.candidateAnalysis
    and production.candidateAnalysis.finalCandidateCount or 0
  runtime.spawnAssignmentsMade = production and production.homesAssigned or 0
  runtime.materializeCalls = 0
  runtime.materializeSuccess = 0
  runtime.materializeFailure = 0
  runtime.materializedThisTick = 0
  runtime.phase3LoopEntered = 0
  runtime.phase3DispatchAttempts = 0
  runtime.phase3DispatchStage = "NOT_RUN"
  runtime.phase3LastBlocker = "UNKNOWN"
  runtime.lastPhase3Error = "NONE"
  runtime.lastPhase3ErrorStage = "NONE"
  runtime.lastPhase3ActorId = nil
  runtime.lastPhase3ActorSpecies = nil
  runtime.lastPhase3ActorCell = "NONE"
  runtime.exclusionReasons = {
    concealed = 0, already_active = 0, invalid_entity = 0,
    no_spawn_cell = 0, wrong_map = 0, lifecycle_blocked = 0
  }
  for _, entity in pairs(members) do
    runtime.populationPersistentTotal = runtime.populationPersistentTotal + 1
    if type(entity) ~= "table" or entity.id == nil then
      runtime.exclusionReasons.invalid_entity = runtime.exclusionReasons.invalid_entity + 1
    elseif Concealment and Concealment.isConcealed(entity, mapId) then
      runtime.populationConcealedTotal = runtime.populationConcealedTotal + 1
    else
      runtime.populationEligibleTotal = runtime.populationEligibleTotal + 1
    end
  end
  if type(visiblePopulation) ~= "table" then
    runtime.phase3LastBlocker = "VISIBLE_POPULATION_NOT_TABLE"
    return
  end
  runtime.visibleRequested = #visiblePopulation

  local anchorId = Config and Config.phase0 and Config.phase0.testEntityId or nil
  runtime.phase3LoopEntered = 1

  for _, entity in ipairs(visiblePopulation) do
    if type(entity) ~= "table" or entity.id == nil then
      runtime.exclusionReasons.invalid_entity = runtime.exclusionReasons.invalid_entity + 1
      runtime.phase3LastBlocker = "INVALID_ENTITY"
    elseif entity.id == anchorId then
      runtime.exclusionReasons.lifecycle_blocked = runtime.exclusionReasons.lifecycle_blocked + 1
      runtime.phase3LastBlocker = "IS_ANCHOR"
    else
      WildEcology.entityById[entity.id] = entity
      local avatar = WildEcology.activeAvatars[entity.id]
      if avatar then
        runtime.populationAlreadyActiveTotal = runtime.populationAlreadyActiveTotal + 1
        runtime.exclusionReasons.already_active = runtime.exclusionReasons.already_active + 1
        runtime.phase3LastBlocker = "ALREADY_ACTIVE"
      elseif Concealment and Concealment.isConcealed(entity, mapId) then
        runtime.exclusionReasons.concealed = runtime.exclusionReasons.concealed + 1
        runtime.phase3LastBlocker = "CONCEALED"
      elseif AvatarFactory and AvatarFactory.spawn then
        local dispatchStage = "BEGIN"
        runtime.phase3DispatchStage = dispatchStage
        runtime.lastPhase3ActorId = entity.id
        runtime.lastPhase3ActorSpecies = entity.species
        runtime.lastPhase3ActorCell = "NONE"
        local dispatchOk, dispatchErr = pcall(function()
          runtime.phase3DispatchAttempts = runtime.phase3DispatchAttempts + 1
          dispatchStage = "ENTITY_OK"
          runtime.phase3DispatchStage = dispatchStage
          local attempt = materializationAttempt(mod, mapId, entity,
            "EXISTING_POPULATION", visitCells[entity.id])
          dispatchStage = "POSITION_OK"
          runtime.phase3DispatchStage = dispatchStage
          if not attempt then
            error("MATERIALIZATION_ATTEMPT_INVALID")
          end
          if attempt.canonicalCell then
            runtime.lastPhase3ActorCell = tostring(attempt.canonicalCell.cellX) .. "," .. tostring(attempt.canonicalCell.cellY)
          end
          if attempt.allowed then
            runtime.materializeCalls = runtime.materializeCalls + 1
            runtime.lastRequestedEntityId = entity.id
            runtime.lastRequestedSpecies = entity.species
            runtime.lastRequestedCell = attempt.canonicalCell
              and tostring(attempt.canonicalCell.cellX) .. ","
                .. tostring(attempt.canonicalCell.cellY) or "NONE"
            runtime.cohortCalls = runtime.cohortCalls + 1
            dispatchStage = "SPECIES_OK"
            runtime.phase3DispatchStage = dispatchStage
            dispatchStage = "SPRITE_OK"
            runtime.phase3DispatchStage = dispatchStage
            dispatchStage = "REQUEST_OK"
            runtime.phase3DispatchStage = dispatchStage
            dispatchStage = "CALL_MATERIALIZE"
            runtime.phase3DispatchStage = dispatchStage
            avatar = RuntimeAvatarAdapter and RuntimeAvatarAdapter.materialize
              and RuntimeAvatarAdapter.materialize(mod, entity, attempt.canonicalCell, mapId)
              or AvatarFactory.spawn(mod, entity, attempt.canonicalCell, mapId)
            dispatchStage = "RETURNED"
            runtime.phase3DispatchStage = dispatchStage
            runtime.lastSpawnStatus = avatar and "SPAWNED" or "SPAWN_FAILED"
            logMaterializationAttempt(mod, attempt, avatar)
            if avatar then
              runtime.materializeSuccess = runtime.materializeSuccess + 1
              runtime.materializedThisTick = runtime.materializedThisTick + 1
              runtime.phase3LastBlocker = "SUCCESS"
              PopulationManager.markSpawnPositionPersisted(entity)
              if WildEcology.movementClaims then
                WildEcology.movementClaims:clear(
                  entity.id, state and state.simulationTick or 0, "RUNTIME_RESET")
              end
              RuntimeState.reset(entity)
              WildEcology.activeAvatars[entity.id] = avatar
            else
              runtime.materializeFailure = runtime.materializeFailure + 1
              runtime.phase3LastBlocker = "MATERIALIZE_FAILED"
            end
          else
            runtime.populationInvalidLocationTotal = runtime.populationInvalidLocationTotal + 1
            if attempt.status == "MISSING_POSITION" then
              runtime.exclusionReasons.no_spawn_cell = runtime.exclusionReasons.no_spawn_cell + 1
              runtime.phase3LastBlocker = "MISSING_POSITION"
            elseif attempt.status == "SEMANTICS_MAP_MISMATCH" then
              runtime.exclusionReasons.wrong_map = runtime.exclusionReasons.wrong_map + 1
              runtime.phase3LastBlocker = "SEMANTICS_MISMATCH"
            else
              runtime.phase3LastBlocker = "ATTEMPT_NOT_ALLOWED:" .. tostring(attempt.status)
            end
            logMaterializationAttempt(mod, attempt, nil)
          end
        end)
        if not dispatchOk then
          runtime.materializeFailure = runtime.materializeFailure + 1
          runtime.phase3LastBlocker = "ERROR"
          runtime.phase3DispatchStage = dispatchStage or "ERROR"
          runtime.lastPhase3Error = tostring(dispatchErr):gsub("[\r\n]+", " "):sub(1, 160)
          runtime.lastPhase3ErrorStage = dispatchStage or "ERROR"
          if runtime.lastPhase3ActorCell == "NONE" and entity and entity.home then
            runtime.lastPhase3ActorCell = tostring(entity.home.spawnX or "?") .. "," .. tostring(entity.home.spawnY or "?")
          end
        end
      else
        runtime.phase3LastBlocker = "NO_AVATARFACTORY"
      end
    end
  end
  runtime.activeAvatarCount = 0
  for _ in pairs(WildEcology.activeAvatars) do
    runtime.activeAvatarCount = runtime.activeAvatarCount + 1
  end
  WildEcology.expectedSpawnIds = {}
  for _, entity in ipairs(visiblePopulation) do
    if entity and not Concealment.isConcealed(entity, mapId) then
      WildEcology.expectedSpawnIds[entity.id] = true
    end
  end
  WildEcology.spawnSyncDirty = false
  if runtime.materializeFailure > 0 then
    WildEcology.spawnSyncDirty = true
    local currentTick = state and state.simulationTick or 0
    WildEcology.spawnRetryTick = currentTick + 60
  end

  if WildEcology.dormantEnvironmentByMap[mapId] == nil then
    local semantics = WorldSemantics and WorldSemantics.fromMod
      and WorldSemantics.fromMod(mod, mapId) or nil
    local reachableWater = false
    if semantics then
      for _, entity in ipairs(visiblePopulation) do
        local position = buildPositionEntity(WildEcology.activeAvatars[entity.id])
          or persistedHomePosition(entity)
        if DormantLifecycle and DormantLifecycle.reachableWaterEvidence
          and DormantLifecycle.reachableWaterEvidence(entity, semantics, position) then
          reachableWater = true
          break
        end
      end
    end
    WildEcology.dormantEnvironmentByMap[mapId] = {
      reachableWater = reachableWater
    }
  end
end

spawnSyncIsStable = function(mapId)
  local state = Save and Save.getState and Save.getState() or nil
  if WildEcology.spawnSyncDirty and WildEcology.spawnRetryTick
    and (state and state.simulationTick or 0) < WildEcology.spawnRetryTick then
    return true
  end
  if WildEcology.spawnSyncDirty
    or WildEcology.spawnInitialization.mapId ~= mapId
    or next(WildEcology.expectedSpawnIds) == nil then
    return false
  end
  local activeCount = 0
  for entityId in pairs(WildEcology.activeAvatars) do
    if not WildEcology.expectedSpawnIds[entityId] then
      return false
    end
    activeCount = activeCount + 1
  end
  if activeCount ~= 0 then
    for entityId in pairs(WildEcology.expectedSpawnIds) do
      if not WildEcology.activeAvatars[entityId] then
        return false
      end
    end
  end
  return activeCount == 0 and next(WildEcology.expectedSpawnIds) == nil
    or activeCount > 0
end

local function currentPhase3Seed(mapId)
  local phase0 = (Config and Config.phase0) or {}
  local activeAnchor = WildEcology.activeAvatars[phase0.testEntityId]
  if type(activeAnchor) == "table" and activeAnchor.spawnSequence then
    return activeAnchor.spawnSequence
  end

  local state = Save and Save.getState and Save.getState() or nil
  local routePopulation = state
    and state.populations
    and state.populations[mapId]
    and state.populations[mapId].members
    and state.populations[mapId].members[phase0.testEntityId]
  local respawnCount = routePopulation
    and routePopulation.memory
    and routePopulation.memory.debug
    and routePopulation.memory.debug.respawnCount
  return respawnCount or 0
end

local function currentVisitSeed(mapId)
  return currentPhase3Seed(mapId)
    + (WildEcology.routeVisitCounts[mapId] or 1) * 104729
end

local function distanceBetweenPositions(left, right)
  if not left or not right then
    return nil
  end

  return math.max(math.abs(left.cellX - right.cellX), math.abs(left.cellY - right.cellY))
end

local function perceptionPositionForEntity(entity)
  local frameContext = entity and WildEcology.actorFrameContexts[entity.id]
  if frameContext then
    return frameContext.position
  end
  local avatar = entity and WildEcology.activeAvatars[entity.id]
  local livePosition = avatar and buildPositionEntity(avatar)
  if livePosition then
    return livePosition
  end

  local home = entity and entity.home or {}
  if home.spawnX == nil or home.spawnY == nil then
    return nil
  end

  return { cellX = home.spawnX, cellY = home.spawnY }
end

local function compactCell(x, y)
  if x == nil or y == nil then return nil end
  return tostring(x) .. "," .. tostring(y)
end

local function relevantRelationshipSummary(entity, limit)
  local rows = {}
  for subjectId, relationship in pairs(entity and entity.relationships or {}) do
    rows[#rows + 1] = {
      subjectId = subjectId,
      relationship = relationship,
      importance = relationship.importance or 0
    }
  end
  table.sort(rows, function(left, right)
    if left.importance == right.importance then
      return tostring(left.subjectId) < tostring(right.subjectId)
    end
    return left.importance > right.importance
  end)
  local summaries = {}
  for index = 1, math.min(limit or 3, #rows) do
    local row = rows[index]
    local relationship = row.relationship
    summaries[#summaries + 1] = string.format(
      "%s:f=%.2f:t=%.2f:a=%.2f:tm=%.2f:dt=%.2f:h=%.2f",
      tostring(row.subjectId), relationship.familiarity or 0,
      relationship.trust or 0, relationship.affinity or 0,
      relationship.threatMemory or 0,
      relationship.directThreatMemory or 0, relationship.hostility or 0)
  end
  return table.concat(summaries, ","), #rows
end

local function agentActorSnapshot(entity, mapId, nearbyCount)
  if not entity then return nil end
  local runtime = entity.runtimeState or {}
  local position = perceptionPositionForEntity(entity)
  local episode = runtime.intentEpisode or {}
  local motion = runtime.motion or {}
  local request = runtime.movementRequest or {}
  local navigation = runtime.navigation or {}
  local goal = runtime.spatialGoal or {}
  local escapeReference = runtime.escapeReference or {}
  local assessment = runtime.threatAssessment or {}
  local relevantRelationships, relationshipCount
    = relevantRelationshipSummary(entity, 3)
  return {
    id = entity.id,
    persistentId = entity.id,
    species = entity.species,
    kind = "POKEMON",
    map = mapId or (entity.home and entity.home.mapId),
    cellX = position and position.cellX,
    cellY = position and position.cellY,
    behavior = runtime.state,
    previousBehavior = runtime.previousBehaviorState,
    targetEntityId = runtime.targetEntityId,
    targetDestination = runtime.targetDestination
      and (runtime.targetDestination.id or compactCell(
        runtime.targetDestination.cellX, runtime.targetDestination.cellY)),
    intentState = episode.status or runtime.intentEpisodeStatus,
    intentTargetId = episode.targetId,
    intentProgress = episode.progress,
    intentCommitment = episode.commitment,
    intentSatisfaction = episode.satisfactionTick
      or runtime.goalSatisfied,
    intentRejections = episode.failedAttempts,
    intentFailures = runtime.lastIntentEpisodeOutcome,
    spatialGoalKind = goal.kind or goal.mode or goal.alignment,
    spatialGoalTarget = goal.targetEntityId or goal.referenceId,
    movementRequest = request.direction and string.format("%s:%s->%s",
      tostring(request.direction), compactCell(request.sourceX, request.sourceY)
        or "none", compactCell(request.destinationX, request.destinationY)
        or "none") or nil,
    motionActive = motion.active == true,
    motionSource = compactCell(motion.sourceX, motion.sourceY),
    motionDestination = compactCell(motion.destinationX, motion.destinationY),
    navigationGoal = navigation.goalSignature or navigation.goalKind,
    navigationReference = navigation.targetEntityId or navigation.goalSource,
    navigationReplanReason = navigation.replanReason,
    fearCurrent = runtime.fearCurrent,
    fearDirect = runtime.fearDirect,
    fearSocial = runtime.fearSocial,
    primaryThreatId = assessment.primaryThreatId,
    directThreatId = runtime.directThreatId,
    escapeReferenceKind = escapeReference.kind,
    socialOnly = runtime.socialOnlyFlee or runtime.socialFleeActive,
    groupId = entity.groupId or (entity.ecology and entity.ecology.family),
    sociality = entity.rawStats and entity.rawStats.social,
    independence = entity.rawStats and entity.rawStats.independence,
    relationshipCount = relationshipCount,
    relevantRelationships = relevantRelationships,
    nearbyCount = nearbyCount
  }
end

buildAgentAuditContext = function(mutation)
  local observer = WildEcology.entityById[mutation.observerId]
  local subject = WildEcology.entityById[mutation.subjectId]
  local mapId = readCurrentMapId(WildEcology.mod)
  local observerSnapshot = agentActorSnapshot(observer, mapId)
  local subjectSnapshot = agentActorSnapshot(subject, mapId)
  if mutation.subjectId == "player" and not subjectSnapshot then
    local playerPosition = perceptionPositionForPlayer(WildEcology.mod)
    subjectSnapshot = {
      id = "player", persistentId = "player", kind = "PLAYER",
      map = mapId, cellX = playerPosition and playerPosition.cellX,
      cellY = playerPosition and playerPosition.cellY
    }
  end
  if observerSnapshot and mutation.diagnosticContext then
    observerSnapshot.previousBehavior
      = mutation.diagnosticContext.previousBehaviorState
  end
  local observerPosition = observer and perceptionPositionForEntity(observer)
  local subjectPosition = subject and perceptionPositionForEntity(subject)
    or mutation.subjectId == "player"
      and perceptionPositionForPlayer(WildEcology.mod) or nil
  local observerGroup = observerSnapshot and observerSnapshot.groupId
  local subjectGroup = subjectSnapshot and subjectSnapshot.groupId
  return {
    observer = observerSnapshot,
    subject = subjectSnapshot,
    distance = distanceBetweenPositions(observerPosition, subjectPosition),
    sameGroup = observerGroup ~= nil and observerGroup == subjectGroup,
    sameSpecies = observer and subject
      and observer.species == subject.species or false,
    socialCompatibility = observer and subject
      and observer.species == subject.species and 1 or nil
  }
end

buildAgentAuditSamples = function(mapId)
  local samples = {}
  for entityId, entity in pairs(WildEcology.entityById) do
    if WildEcology.activeAvatars[entityId] then
      samples[entityId] = agentActorSnapshot(entity, mapId, nil)
    end
  end
  return samples
end

-- Answers the three review questions this way:
-- 1) APPROACHING/RETREATING are edge-triggered episodes with hysteresis
--    (see observeTarget below): a new direction commits immediately, but
--    continuing that same direction emits nothing further, and enough
--    stable (unchanged-distance) samples reset internally to STABLE so a
--    later step -- even in the same direction -- is recognized as a new
--    episode instead of being silently absorbed.
-- 2) Perception has a finite locality radius (PERCEPTION_RADIUS) -- an
--    observer no longer perceives every visible entity on the whole route
--    regardless of distance.
-- 3) LOST and SEEN tracking share the same key and are cleared together,
--    so leaving then re-entering range always re-triggers a fresh SEEN
--    instead of silently resuming tracking (which previously produced
--    repeated LOST with no intervening SEEN for anything hovering near
--    the radius boundary).
local PERCEPTION_RADIUS = 5
-- How many consecutive unchanged-distance samples silently reset a
-- committed APPROACHING/RETREATING episode back to STABLE (see
-- observeTarget), so a later step in the same direction still counts as
-- a new episode instead of being absorbed into "no new event".
local PERCEPTION_STABILITY_RESET_TICKS = 3

local function observeActivePopulation(mod, mapId)
  performanceCount("perception_updates")
  local profileName, profileStart = performanceStart("perception")
  if not Perception or not PopulationManager or not PopulationManager.getVisibleRoutePopulation then
    performanceStop(profileName, profileStart)
    return {}
  end

  local state = Save and Save.getState and Save.getState() or nil
  local tick = state and state.simulationTick or 0
  local visiblePopulation = WildEcology.visiblePopulationByMap[mapId]
    or PopulationManager.getVisibleRoutePopulation(mapId, currentPhase3Seed(mapId), mod)
  WildEcology.actorFrameContexts = {}
  local playerPosition = perceptionPositionForPlayer(mod)
  local positionsById = {}
  local entitiesById = {}
  local urgentById = {}

  for _, entity in ipairs(visiblePopulation or {}) do
    local avatar = WildEcology.activeAvatars[entity.id]
    local position = avatar and buildPositionEntity(avatar)
      or persistedHomePosition(entity)
    local context = {
      entity = entity,
      entityId = entity.id,
      mapId = mapId,
      position = position,
      runtimeAvatar = avatar,
      runtimeState = entity.runtimeState,
      speciesProfile = SpeciesEcology.getResolved(entity.species),
      visibleCohort = visiblePopulation,
      perceptionNeighbors = nil
    }
    WildEcology.actorFrameContexts[entity.id] = context
    positionsById[entity.id] = position
    entitiesById[entity.id] = entity
  end

  for _, observer in ipairs(visiblePopulation or {}) do
    observer.runtimeState = observer.runtimeState or {}
    observer.runtimeState.perceptionUpdated = true
    observer.runtimeState.lastPerceptionTick = tick
    observer.runtimeState.perceptionMetrics = observer.runtimeState.perceptionMetrics or {
      perceptionPasses = 0,
      observerTargetCandidateChecks = 0,
      detailedPerceptionPairChecks = 0,
      seenEvents = 0,
      lostEvents = 0,
      approachingEvents = 0,
      retreatingEvents = 0
    }
    local perceptionMetrics = observer.runtimeState.perceptionMetrics
    perceptionMetrics.perceptionPasses = perceptionMetrics.perceptionPasses + 1
    observer.runtimeState.perceptionMotionByTarget = observer.runtimeState.perceptionMotionByTarget or {}
    local perceptionMotionByTarget = observer.runtimeState.perceptionMotionByTarget
    local observerPosition = positionsById[observer.id]
    local observations = {}
    local contactCount = 0
    local nearbyEntities = {}
    local observerPairs = WildEcology.perceptionPairs[observer.id] or {}
    local observerPositions = WildEcology.perceptionPositions[observer.id] or {}
    WildEcology.perceptionPairs[observer.id] = observerPairs
    WildEcology.perceptionPositions[observer.id] = observerPositions

    -- Hold the observer's prior position fixed to isolate target motion.
    local function observeTarget(targetId, targetPosition, distance)
      performanceCount("perception_pair_checks")
      perceptionMetrics.detailedPerceptionPairChecks
        = perceptionMetrics.detailedPerceptionPairChecks + 1
      local positionKey = "entity:" .. tostring(targetId)
      local record = observerPositions[positionKey]

      if not targetPosition or distance == nil or distance > PERCEPTION_RADIUS then
        -- Out of perception range is treated the same as no longer
        -- perceivable at all: drop tracking and emit LOST if we were
        -- previously tracking it. Also clear the SEEN flag for this same
        -- key so re-entering range later genuinely re-triggers ENTITY_SEEN
        -- instead of silently resuming tracking with no acquisition event
        -- (previously these two tables could desync: LOST cleared this
        -- record but never touched observerPairs, so a target hovering
        -- near the radius boundary produced LOST over and over with no
        -- SEEN in between).
        if record then
          observations[#observations + 1] = {
            name = Perception.EVENTS.ENTITY_LOST,
            targetEntityId = targetId
          }
          observerPositions[positionKey] = nil
          observerPairs[positionKey] = nil
          perceptionMotionByTarget[targetId] = nil
        end
        return
      end

      if not record then
        -- First perceivable sighting: establish a baseline only, nothing
        -- to compare motion against yet.
        observerPositions[positionKey] = {
          targetPos = { cellX = targetPosition.cellX, cellY = targetPosition.cellY },
          observerPos = observerPosition and { cellX = observerPosition.cellX, cellY = observerPosition.cellY } or nil,
          state = "STABLE",
          stableTicks = 0
        }
        perceptionMotionByTarget[targetId] = { direction = "STABLE", tick = tick }
        return
      end

      local targetMoved = record.targetPos.cellX ~= targetPosition.cellX or record.targetPos.cellY ~= targetPosition.cellY
      local observerMoved = record.observerPos
        and (record.observerPos.cellX ~= observerPosition.cellX or record.observerPos.cellY ~= observerPosition.cellY)
        or false
      local targetEntity = entitiesById[targetId]
      local targetMotionActive = targetEntity
        and targetEntity.runtimeState
        and targetEntity.runtimeState.motion
        and targetEntity.runtimeState.motion.active == true
      if targetId == "player" then
        targetMotionActive = mod and mod.world and mod.world.player and mod.world.player.moving == true
      end
      local observerMotionActive = observer.runtimeState
        and observer.runtimeState.motion
        and observer.runtimeState.motion.active == true
      local referenceObserverPos = record.observerPos or observerPosition

      local rawDirection = nil
      if targetMoved then
        local oldDistance = distanceBetweenPositions(referenceObserverPos, record.targetPos)
        local newDistance = distanceBetweenPositions(referenceObserverPos, targetPosition)
        if oldDistance ~= nil and newDistance ~= nil then
          if newDistance < oldDistance then
            rawDirection = "APPROACHING"
          elseif newDistance > oldDistance then
            rawDirection = "RETREATING"
          end
        end
      end

      record.targetPos = { cellX = targetPosition.cellX, cellY = targetPosition.cellY }
      record.observerPos = observerPosition and { cellX = observerPosition.cellX, cellY = observerPosition.cellY } or record.observerPos

      if not rawDirection then
        if targetMoved or observerMoved or targetMotionActive or observerMotionActive then
          record.stableTicks = 0
          return
        end
        record.stableTicks = record.stableTicks + 1
        if record.stableTicks >= PERCEPTION_STABILITY_RESET_TICKS then
          -- Silent reset, no event: lets a later step in the SAME
          -- direction still count as a fresh episode.
          record.state = "STABLE"
          perceptionMotionByTarget[targetId] = { direction = "STABLE", tick = tick }
        end
        return
      end

      record.stableTicks = 0
      if rawDirection == record.state then
        -- Continuing an already-committed direction: no new event.
        return
      end

      record.state = rawDirection
      perceptionMotionByTarget[targetId] = { direction = rawDirection, tick = tick }
      observations[#observations + 1] = {
        name = rawDirection == "APPROACHING" and Perception.EVENTS.ENTITY_APPROACHING or Perception.EVENTS.ENTITY_RETREATING,
        targetEntityId = targetId,
        threatDelta = rawDirection == "APPROACHING" and 1 or nil
      }
    end

    for _, target in ipairs(visiblePopulation or {}) do
      if target.id ~= observer.id then
        perceptionMetrics.observerTargetCandidateChecks
          = perceptionMetrics.observerTargetCandidateChecks + 1
        local distance = distanceBetweenPositions(observerPosition, positionsById[target.id])
        if distance ~= nil and distance <= PERCEPTION_RADIUS then
          nearbyEntities[#nearbyEntities + 1] = target
        end
        observeTarget(target.id, positionsById[target.id], distance)
        if distance ~= nil and distance <= 5 and Social and Social.observeNearby then
          contactCount = contactCount + 1
          Social.observeNearby(observer, target.id, distance, tick, target)
        end
        if distance ~= nil and distance <= 5 and (readPhase2SocialFearEnabled(mod) or readPhase2SocialReassuranceEnabled(mod)) and PopulationManager.propagateAssociateSocialSignal then
          local _, signalDelta, signalKind = PopulationManager.propagateAssociateSocialSignal(observer, target, tick, distance)
          if signalDelta and signalDelta > 0 then
            urgentById[observer.id] = true
            if readBehaviorTraceEnabled(mod) then
              writeDebugLog(mod, "relationships", string.format("Associate %s propagated %s (delta=%.2f) from %s to %s", tostring(target.id), tostring(signalKind), signalDelta, tostring(target.id), tostring(target.runtimeState and target.runtimeState.targetEntityId)))
            end
          end
        end
        if distance ~= nil and distance <= 5 then
          local pairKey = "entity:" .. tostring(target.id)
          if not observerPairs[pairKey] then
            observations[#observations + 1] = {
              name = Perception.EVENTS.ENTITY_SEEN,
              targetEntityId = target.id
            }
            observerPairs[pairKey] = true
          end
          if distance <= 2 then
            observations[#observations + 1] = {
              name = Perception.EVENTS.ENTITY_NEAR,
              targetEntityId = target.id
            }
          end
        end
      end
    end
    WildEcology.perceptionNeighbors[observer.id] = nearbyEntities
    local frameContext = WildEcology.actorFrameContexts[observer.id]
    if frameContext then frameContext.perceptionNeighbors = nearbyEntities end

    local playerDistance = distanceBetweenPositions(observerPosition, playerPosition)
    perceptionMetrics.observerTargetCandidateChecks
      = perceptionMetrics.observerTargetCandidateChecks + 1
    observeTarget("player", playerPosition, playerDistance)
    if playerDistance ~= nil and playerDistance <= 5 then
      contactCount = contactCount + 1
      if playerDistance <= 2 then
        urgentById[observer.id] = true
      end
      if not observerPairs["entity:player"] then
        observations[#observations + 1] = {
          name = Perception.EVENTS.ENTITY_SEEN,
          targetEntityId = "player"
        }
        observerPairs["entity:player"] = true
      end
      if playerDistance <= 2 then
        observations[#observations + 1] = {
          name = Perception.EVENTS.ENTITY_NEAR,
          targetEntityId = "player"
        }
      end
    end

    if #observations > 0 then
      for _, observation in ipairs(observations) do
        if observation.targetEntityId == "player"
          and observation.name == Perception.EVENTS.ENTITY_APPROACHING then
          urgentById[observer.id] = true
        end
      end
      performanceCount("relationship_observation_calls")
      local result = Perception.observe(observer, observations, tick)
      for _, event in ipairs(result.events or {}) do
        local eventName = event.event or event.name
        if eventName == Perception.EVENTS.ENTITY_SEEN then
          perceptionMetrics.seenEvents = perceptionMetrics.seenEvents + 1
        elseif eventName == Perception.EVENTS.ENTITY_LOST then
          perceptionMetrics.lostEvents = perceptionMetrics.lostEvents + 1
        elseif eventName == Perception.EVENTS.ENTITY_APPROACHING then
          perceptionMetrics.approachingEvents = perceptionMetrics.approachingEvents + 1
        elseif eventName == Perception.EVENTS.ENTITY_RETREATING then
          perceptionMetrics.retreatingEvents = perceptionMetrics.retreatingEvents + 1
        end
        local focusedId = WildEcology.focusedEntityId
          or (Config and Config.phase0 and Config.phase0.testEntityId)
        local normalPerceptionRelevant = observer.id == focusedId
          or event.targetEntityId == "player"
        if eventName ~= Perception.EVENTS.ENTITY_NEAR
          and (eventName ~= Perception.EVENTS.ENTITY_SEEN or readPhase5DiagnosticsEnabled(mod))
          and (readBehaviorTraceEnabled(mod) or normalPerceptionRelevant) then
          writeDebugLog(mod, "relationships", string.format(
            "Perception %s observer=%s target=%s",
            tostring(eventName),
            tostring(observer.id),
            tostring(event.targetEntityId or "none")
          ))
        end
      end
    end
    observer.runtimeState = observer.runtimeState or {}
    observer.runtimeState.perceptionContactCount = contactCount
  end

  if Save and Save.flush then
    Save.flush()
  end
  performanceStop(profileName, profileStart)
  return urgentById
end

local function movementBias(entity, position)
  local runtime = entity and entity.runtimeState or {}
  local motion = runtime.motion
  if motion and motion.active and motion.destinationX ~= nil and motion.destinationY ~= nil and position then
    return { dx = motion.destinationX - position.cellX, dy = motion.destinationY - position.cellY }
  end
  local request = runtime.movementRequest
  if request and request.destinationX ~= nil and request.destinationY ~= nil and position then
    return { dx = request.destinationX - position.cellX, dy = request.destinationY - position.cellY }
  end
  return nil
end

local function updateVisibleFear(mod, visiblePopulation, simulationTick)
  if not Fear then return end
  performanceCount("threat_fear_updates", #visiblePopulation)
  local profileName, profileStart = performanceStart("threat_fear")
  local positions, snapshots = {}, {}
  local player = getPlayerEntity()
  local behaviorMode = readBehaviorMode(mod)
  local debugPreset = behaviorMode and behaviorMode:match("^force_(.+)$")
  local playerPosition = perceptionPositionForPlayer(mod)
  for _, entity in ipairs(visiblePopulation or {}) do
    local position = perceptionPositionForEntity(entity)
    positions[entity.id] = position
    local runtime = entity.runtimeState or {}
    snapshots[entity.id] = {
      alarmOutput = runtime.alarmOutput or 0,
      alarmDirectComponent = runtime.alarmDirectComponent or 0,
      alarmRelayedComponent = runtime.alarmRelayedComponent or 0,
      alarmGroundedness = runtime.alarmGroundedness or 0,
      socialInputRaw = runtime.socialInputRaw or 0,
      contributionBySource = runtime.socialContributionBySource or {},
      state = runtime.state,
      escapeBias = movementBias(entity, position),
      species = entity.species,
      ecology = entity.ecology
    }
  end

  local totalFear, maxFear, frightened, fleeing, sociallyAlarmed = 0, 0, 0, 0, 0
  local directlyFrightened, sociallyFrightened = 0, 0
  local highFearDirect, highFearSocialOnly = 0, 0
  local totalGroundedness, maxSocialRelayAlarm = 0, 0
  for _, entity in ipairs(visiblePopulation or {}) do
    local position = positions[entity.id]
    local threatCandidates = {}
    local playerDistance = distanceBetweenPositions(position, playerPosition)
    local playerRelationship = entity.relationships and entity.relationships[player.id] or {}
    local fearPreset = nil
    if playerDistance and playerDistance <= PERCEPTION_RADIUS then
      local evidence = entity.runtimeState and entity.runtimeState.directThreatEvidence
        and entity.runtimeState.directThreatEvidence[player.id]
      threatCandidates[#threatCandidates + 1] = {
        id = player.id,
        kind = "trainer",
        distance = playerDistance,
        relationship = playerRelationship,
        motion = entity.runtimeState and entity.runtimeState.perceptionMotionByTarget
          and entity.runtimeState.perceptionMotionByTarget[player.id]
          and entity.runtimeState.perceptionMotionByTarget[player.id].direction or "STABLE",
        directThreatSeverity = evidence and simulationTick - evidence.tick <= 2 and evidence.severity or nil,
        persistentThreatMemoryWritten = evidence ~= nil,
        persistentThreatMemoryReason = evidence and evidence.reason or nil
      }
      fearPreset = BehaviorDebugPreset.apply(debugPreset, entity,
        threatCandidates[#threatCandidates], playerRelationship)
      if fearPreset.name then
        threatCandidates[#threatCandidates] = fearPreset.candidate
      end
    end
    for _, candidate in ipairs(WildEcology.perceptionNeighbors[entity.id] or {}) do
      if candidate.id ~= entity.id then
        local candidateDistance = distanceBetweenPositions(position, positions[candidate.id])
        local candidateRelationship = entity.relationships and entity.relationships[candidate.id] or {}
        if candidateDistance and candidateDistance <= PERCEPTION_RADIUS then
          local evidence = entity.runtimeState and entity.runtimeState.directThreatEvidence
            and entity.runtimeState.directThreatEvidence[candidate.id]
          threatCandidates[#threatCandidates + 1] = {
            id = candidate.id,
            kind = "pokemon",
            distance = candidateDistance,
            relationship = candidateRelationship,
            motion = entity.runtimeState and entity.runtimeState.perceptionMotionByTarget
              and entity.runtimeState.perceptionMotionByTarget[candidate.id]
              and entity.runtimeState.perceptionMotionByTarget[candidate.id].direction or "STABLE",
            directThreatSeverity = evidence and simulationTick - evidence.tick <= 2 and evidence.severity or nil,
            persistentThreatMemoryWritten = evidence ~= nil,
            persistentThreatMemoryReason = evidence and evidence.reason or nil
          }
        end
      end
    end
    performanceCount("threat_assessments")
    local assessment = ThreatAssessment.assess(
      fearPreset and fearPreset.name and fearPreset.entity or entity,
      threatCandidates,
      simulationTick)
    if readPhase5DiagnosticsEnabled(mod) and assessment.threatSwitch then
      writeDebugLog(mod, "behavior", string.format(
        "Threat switch actor=%s primaryThreatId=%s primaryThreatAge=%s primaryThreatScore=%.2f primaryThreatReason=%s challengerThreatId=%s challengerScore=%.2f switchMargin=%.2f threatSwitch=%s threatSwitchReason=%s identifiedThreatCount=%s",
        tostring(entity.id), tostring(assessment.primaryThreatId or "none"),
        tostring(assessment.primaryThreatAge or 0), assessment.primaryThreatScore or 0,
        tostring(assessment.primaryThreatReason or "NONE"),
        tostring(assessment.challengerThreatId or "none"), assessment.challengerScore or 0,
        assessment.switchMargin or 0, tostring(assessment.threatSwitch),
        tostring(assessment.threatSwitchReason or "NONE"),
        tostring(assessment.identifiedThreatCount or 0)
      ))
    end
    local directThreatId = assessment.primaryThreatId
    if directThreatId then
      performanceCount("flee_threat_detected")
    end
    local threatDistance = assessment.primaryThreatDistance
    local relationship = assessment.primaryThreatRelationship or {}
    local perceivedFear = 0
    if directThreatId and entity.runtimeState and entity.runtimeState.perceivedFear then
      perceivedFear = entity.runtimeState.perceivedFear[directThreatId] or 0
    end

    local socialSources = {}
    local runtime = entity.runtimeState or {}
    local previousAssessment = runtime.lastFastThreatAssessment
    local previousDistance = previousAssessment and previousAssessment.primaryThreatDistance or nil
    local threatChanged = assessment.primaryThreatId ~= runtime.directThreatId
    local urgentDistanceCrossing = assessment.primaryThreatId ~= nil
      and (assessment.primaryThreatDistance or math.huge) <= 1
      and (previousDistance == nil or previousDistance > 1)
    local presetChanged = runtime.lastFearDebugPreset ~= (fearPreset and fearPreset.name or nil)
    local integrationDue = runtime.lastFearTick == nil
      or simulationTick - runtime.lastFearTick >= FEAR_INTEGRATION_INTERVAL_TICKS
      or assessment.primaryThreatSevere == true
      or threatChanged
      or urgentDistanceCrossing
      or presetChanged
    runtime.lastFastThreatAssessment = assessment
    runtime.threatAssessment = assessment
    runtime.fearUpdated = false
    if integrationDue then
      for _, source in ipairs(WildEcology.perceptionNeighbors[entity.id] or {}) do
        if source.id ~= entity.id then
          local distance = distanceBetweenPositions(position, positions[source.id])
          local snapshot = snapshots[source.id]
          if distance and distance <= PERCEPTION_RADIUS and snapshot and snapshot.alarmOutput > 0 then
            local sourceRelationship = entity.relationships and entity.relationships[source.id] or {}
            socialSources[#socialSources + 1] = {
              id = source.id,
              species = snapshot.species,
              ecology = snapshot.ecology,
              alarmOutput = snapshot.alarmOutput,
              alarmDirectComponent = snapshot.alarmDirectComponent,
              alarmRelayedComponent = snapshot.alarmRelayedComponent,
              alarmGroundedness = snapshot.alarmGroundedness,
              socialInputRaw = snapshot.socialInputRaw,
              echoContribution = snapshot.contributionBySource[entity.id] or 0,
              state = snapshot.state,
              distance = distance,
              escapeBias = snapshot.escapeBias,
              relationship = sourceRelationship,
              trusted = (sourceRelationship.trust or 0) >= 20,
              family = entity.ecology and source.ecology and entity.ecology.family == source.ecology.family
            }
          end
        end
      end
    end
    if fearPreset and fearPreset.name and fearPreset.socialSources then
      socialSources = fearPreset.socialSources
    end
    local fear = runtime.fearCurrent or 0
    if integrationDue then
      performanceCount("fear_updates")
      fear = Fear.update(entity, {
        threatAssessment = assessment,
        threatDistance = threatDistance,
        relationship = relationship,
        perceivedFear = perceivedFear,
        socialSources = socialSources,
        perceptionRadius = PERCEPTION_RADIUS
      }, simulationTick)
      runtime.fearUpdated = true
      runtime.lastFearUpdateTick = simulationTick
      runtime.lastFearDebugPreset = fearPreset and fearPreset.name or nil
      if fearPreset and fearPreset.name then
        runtime.fearCurrent = fearPreset.fearCurrent
        runtime.fearDirect = fearPreset.fearDirect
        runtime.fearSocial = fearPreset.fearSocial
        fear = fearPreset.fearCurrent
      end
    end
    runtime.escapeUrgency = Fear.escapeUrgency(entity, threatDistance)
    local focusedId = WildEcology.focusedEntityId
      or (Config and Config.phase0 and Config.phase0.testEntityId)
    local trace = readBehaviorTraceEnabled(mod) and entity.id == focusedId
    local fearEvent = integrationDue and Fear.diagnosticEvent(runtime, trace) or nil
    local calmBookkeeping = TelemetryPolicy.suppressFearNormal(fearEvent, runtime, trace)
    if calmBookkeeping and not trace then
      WildEcology.telemetryDiagnostics.fearNormalSuppressedCalmBookkeeping
        = WildEcology.telemetryDiagnostics.fearNormalSuppressedCalmBookkeeping + 1
      fearEvent = nil
    end
    if readPhase5DiagnosticsEnabled(mod) and fearEvent then
      if not trace then
        WildEcology.telemetryDiagnostics.fearNormalRecords
          = WildEcology.telemetryDiagnostics.fearNormalRecords + 1
      end
      local baseRadius = Utility and Utility.fleeRadius and Utility.fleeRadius(relationship) or 4
      local triggerRadius, safetyDistance = Fear.escapeDistances(
        baseRadius,
        fear,
        entity.runtimeState.fearDirect,
        entity.runtimeState.fearSocial,
        entity.runtimeState.alarmGroundedness
      )
      if trace then
        writeDebugLog(mod, "behavior", string.format(
        "Fear actor=%s event=%s current=%.2f direct=%.2f social=%.2f decay=%.2f alarmOutput=%.2f alarmDirect=%.2f alarmRelayed=%.2f groundedness=%.2f socialInputRaw=%.2f socialAfterRelay=%.2f echoSuppressed=%.2f baseRadius=%s effectiveRadius=%s desiredSafety=%s urgency=%.2f directThreat=%s socialSources=%s conspecificSources=%s heterospecificSources=%s strongestSource=%s strongestSourceSpecies=%s escapeBias=%s,%s socialOnly=%s",
        tostring(entity.id), tostring(fearEvent), fear, runtime.fearDirect or 0,
        runtime.fearSocial or 0, runtime.fearDecay or 0,
        runtime.alarmOutput or 0,
        runtime.alarmDirectComponent or 0,
        runtime.alarmRelayedComponent or 0,
        runtime.alarmGroundedness or 0,
        runtime.socialInputRaw or 0,
        runtime.socialInputAfterRelayLoss or 0,
        runtime.echoSuppressedAmount or 0,
        tostring(baseRadius), tostring(triggerRadius), tostring(safetyDistance),
        runtime.escapeUrgency or 0,
        tostring(runtime.directThreatId or "none"),
        tostring(runtime.nearbyFearSources or 0),
        tostring(runtime.conspecificSourceCount or 0),
        tostring(runtime.heterospecificSourceCount or 0),
        tostring(runtime.strongestFearSource or "none"),
        tostring(runtime.strongestSocialSourceSpecies or "none"),
        tostring(runtime.socialEscapeBias and runtime.socialEscapeBias.dx or "none"),
        tostring(runtime.socialEscapeBias and runtime.socialEscapeBias.dy or "none"),
        tostring((runtime.fearDirect or 0) < 0.05 and (runtime.fearSocial or 0) > 0)
        ))
      else
        writeDebugLog(mod, "behavior", string.format(
          "Fear actor=%s event=%s current=%.2f direct=%.2f social=%.2f threat=%s sources=%s strongest=%s socialOnly=%s",
          tostring(entity.id), tostring(fearEvent), fear, runtime.fearDirect or 0,
          runtime.fearSocial or 0, tostring(runtime.directThreatId or "none"),
          tostring(runtime.nearbyFearSources or 0),
          tostring(runtime.strongestFearSource or "none"),
          tostring((runtime.fearDirect or 0) < 0.05 and (runtime.fearSocial or 0) > 0)
        ))
      end
      if trace then
        for _, detail in ipairs(runtime.socialContributionDetails or {}) do
          writeDebugLog(mod, "behavior", string.format(
            "Social fear contribution actor=%s source=%s sourceSpecies=%s observerSpecies=%s sameSpecies=%s speciesAlarmCompatibility=%.2f sourceAlarmOutput=%.2f sourceBroadcastStrength=%.2f distanceAttenuation=%.2f provenanceAttenuation=%.2f finalSocialContribution=%.2f",
            tostring(entity.id), tostring(detail.sourceId), tostring(detail.sourceSpecies or "none"),
            tostring(detail.observerSpecies or "none"), tostring(detail.sameSpecies),
            detail.speciesAlarmCompatibility or 0, detail.sourceAlarmOutput or 0,
            detail.sourceBroadcastStrength or 0, detail.distanceAttenuation or 0,
            detail.provenanceAttenuation or 0, detail.finalSocialContribution or 0
          ))
        end
      end
    end
    totalFear = totalFear + fear
    maxFear = math.max(maxFear, fear)
    frightened = frightened + (fear >= 0.22 and 1 or 0)
    fleeing = fleeing + (entity.runtimeState.state == "FLEE" and 1 or 0)
    sociallyAlarmed = sociallyAlarmed + ((entity.runtimeState.fearSocial or 0) >= 0.22 and 1 or 0)
    directlyFrightened = directlyFrightened + ((entity.runtimeState.fearDirect or 0) >= 0.22 and 1 or 0)
    sociallyFrightened = sociallyFrightened + ((entity.runtimeState.fearSocial or 0) >= 0.22 and 1 or 0)
    highFearDirect = highFearDirect + (fear >= 0.7 and (entity.runtimeState.fearDirect or 0) >= 0.22 and 1 or 0)
    highFearSocialOnly = highFearSocialOnly + (fear >= 0.7 and (entity.runtimeState.fearDirect or 0) < 0.05 and 1 or 0)
    totalGroundedness = totalGroundedness + (entity.runtimeState.alarmGroundedness or 0)
    maxSocialRelayAlarm = math.max(maxSocialRelayAlarm, entity.runtimeState.alarmRelayedComponent or 0)
  end
  local diagnostics = WildEcology.behaviorDiagnosticsByMap[readCurrentMapId(mod)] or {}
  WildEcology.behaviorDiagnosticsByMap[readCurrentMapId(mod)] = diagnostics
  diagnostics.averageFear = #visiblePopulation > 0 and totalFear / #visiblePopulation or 0
  diagnostics.maxFear = maxFear
  diagnostics.frightenedCount = frightened
  diagnostics.fleeingCount = fleeing
  diagnostics.sociallyAlarmedCount = sociallyAlarmed
  diagnostics.directlyFrightenedCount = directlyFrightened
  diagnostics.sociallyFrightenedCount = sociallyFrightened
  diagnostics.highFearDirectCount = highFearDirect
  diagnostics.highFearSocialOnlyCount = highFearSocialOnly
  diagnostics.averageAlarmGroundedness = #visiblePopulation > 0 and totalGroundedness / #visiblePopulation or 0
  diagnostics.maxSocialRelayAlarm = maxSocialRelayAlarm
  performanceStop(profileName, profileStart)
end

local function updateActivePopulationBehavior(mod, mapId, simulationTick, urgentById)
  local visiblePopulation = WildEcology.visiblePopulationByMap[mapId]
    or PopulationManager and PopulationManager.getVisibleRoutePopulation
      and PopulationManager.getVisibleRoutePopulation(mapId, currentPhase3Seed(mapId), mod)
    or {}
  performanceCount("behavior_population_updates")
  local profileName, profileStart = performanceStart("behavior")
  local anchorId = Config and Config.phase0 and Config.phase0.testEntityId or nil
  local diagnostics = WildEcology.behaviorDiagnosticsByMap[mapId] or {
    behaviorEligible = 0,
    behaviorDecisionTicks = 0,
    ambientDecisions = 0,
    fleeDecisions = 0
  }
  WildEcology.behaviorDiagnosticsByMap[mapId] = diagnostics
  diagnostics.behaviorEligible = 0

  if WildEcology.movementClaims and WildEcology.movementClaims.validateAll then
    WildEcology.movementClaims:validateAll(function(actorId)
      local actor = WildEcology.entityById[actorId]
      local actorAvatar = WildEcology.activeAvatars[actorId]
      return actor and actor.runtimeState or nil,
        actorAvatar and buildPositionEntity(actorAvatar) or nil
    end, simulationTick)
  end

  updateVisibleFear(mod, visiblePopulation, simulationTick)
  table.sort(visiblePopulation, function(left, right)
    local leftUrgency = left.runtimeState and left.runtimeState.escapeUrgency or 0
    local rightUrgency = right.runtimeState and right.runtimeState.escapeUrgency or 0
    if leftUrgency == rightUrgency then
      return tostring(left.id) < tostring(right.id)
    end
    return leftUrgency > rightUrgency
  end)

  for _, entity in ipairs(visiblePopulation) do
    local avatar = entity and WildEcology.activeAvatars[entity.id] or nil
    if avatar and entity.id ~= anchorId then
      local runtime = entity.runtimeState or {}
      runtime.schedulerMetrics = runtime.schedulerMetrics or {}
      local metrics = runtime.schedulerMetrics
      metrics.lifecycleTicks = (metrics.lifecycleTicks or 0) + 1
      metrics.emergencyInterruptChecks = (metrics.emergencyInterruptChecks or 0) + 1
      local behaviorMode = readBehaviorMode(mod)
      local debugPreset = behaviorMode and behaviorMode:match("^force_(.+)$")
      local targetAvailable = runtime.targetEntityId == nil
        or runtime.targetEntityId == "player"
        or WildEcology.activeAvatars[runtime.targetEntityId] ~= nil
      local reason = Controller.reconsiderationReason(
        runtime, simulationTick, debugPreset, targetAvailable)
      if reason == "EMERGENCY_THREAT" or reason == "SEVERE_EVENT" then
        performanceCount("flee_emergency_reason")
      end
      runtime.deliberationDue = reason ~= nil
      runtime.deliberationPerformed = false
      runtime.reconsiderationReason = reason or "NOT_DUE"
      if reason then
        performanceCount("controller_deliberations")
        diagnostics.behaviorEligible = diagnostics.behaviorEligible + 1
        local decisionName, decisionStart = performanceStart("deliberation")
        local ok, err = pcall(evaluateVisibleEntity, mod, mapId, entity, avatar, simulationTick, reason)
        performanceStop(decisionName, decisionStart)
        if not ok then
          writeDebugLog(mod, "behavior", string.format("evaluateVisibleEntity error for %s: %s", tostring(entity.id), tostring(err)))
        end
      else
        performanceCount("intent_executions")
        local executionName, executionStart = performanceStart("execution")
        local ok, terminal = pcall(executeVisibleEntity, mod, mapId, entity, avatar, simulationTick)
        performanceStop(executionName, executionStart)
        if not ok then
          writeDebugLog(mod, "behavior", string.format("executeVisibleEntity error for %s: %s", tostring(entity.id), tostring(terminal)))
        elseif terminal then
          runtime.deliberationDue = true
          local deliberateOk, err = pcall(evaluateVisibleEntity, mod, mapId, entity, avatar, simulationTick, terminal)
          if not deliberateOk then
            writeDebugLog(mod, "behavior", string.format("terminal evaluateVisibleEntity error for %s: %s", tostring(entity.id), tostring(err)))
          end
        end
      end
    end
  end
  performanceStop(profileName, profileStart)
end

function WildEcology.emitDisturbance(mapId, spec)
  if not Disturbance or not mapId then return nil end
  local event = Disturbance.new(spec)
  local queue = WildEcology.disturbancesByMap[mapId] or {}
  queue[#queue + 1] = event
  while #queue > 32 do table.remove(queue, 1) end
  WildEcology.disturbancesByMap[mapId] = queue
  return event
end

local function recordPlayerMovementDisturbance(mod, mapId, simulationTick)
  local position = perceptionPositionForPlayer(mod)
  local previous = WildEcology.lastPlayerPositionByMap[mapId]
  WildEcology.lastPlayerPositionByMap[mapId] = position and {
    cellX = position.cellX, cellY = position.cellY
  } or nil
  if position and previous
    and (position.cellX ~= previous.cellX or position.cellY ~= previous.cellY) then
    WildEcology.emitDisturbance(mapId, {
      kind = "ACTOR_MOVEMENT",
      sourceEntityId = "player",
      sourcePosition = position,
      intensity = 0.45,
      radius = 2,
      tick = simulationTick
    })
  end
end

local function occupiedAvatarCells()
  local occupied = {}
  for _, avatar in pairs(WildEcology.activeAvatars) do
    local position = buildPositionEntity(avatar)
    if position then
      occupied[WorldSemantics.cellKey(position.cellX, position.cellY)] = true
    end
  end
  return occupied
end

local function updateConcealedPopulation(mod, mapId, simulationTick)
  local state = Save and Save.getState and Save.getState() or nil
  local members = state and state.populations and state.populations[mapId]
    and state.populations[mapId].members or {}
  local events = WildEcology.disturbancesByMap[mapId] or {}
  WildEcology.disturbancesByMap[mapId] = {}
  if #events == 0 and simulationTick % BEHAVIOR_DECISION_INTERVAL_TICKS ~= 0 then
    return
  end
  local semantics = WorldSemantics.fromMod(mod, mapId)
  local occupied = occupiedAvatarCells()
  local cues = WildEcology.concealmentCuesByMap[mapId] or {}
  for entityId, entity in pairs(members) do
    if Concealment.isConcealed(entity, mapId) then
      WildEcology.entityById[entityId] = entity
      local lifecycle = Concealment.updateRest(entity, simulationTick)
      local emergenceRequested = lifecycle
        and lifecycle.action == "REQUEST_EMERGENCE"
      local fleeRequested = false
      local sourceEvent = nil
      for _, event in ipairs(events) do
        local response = Concealment.respond(entity, event)
        local lastCueTick = WildEcology.lastConcealmentCueTickByEntity[entityId]
        if response.cue
          and (lastCueTick == nil or simulationTick - lastCueTick >= 30) then
          cues[#cues + 1] = {
            entityId = entityId,
            mapId = mapId,
            anchorCell = entity.locationState and entity.locationState.anchorCell,
            cue = response.cue,
            tick = simulationTick,
            expiresTick = simulationTick + 30
          }
          WildEcology.lastConcealmentCueTickByEntity[entityId] = simulationTick
        end
        if response.requestEmergence then
          emergenceRequested = true
          sourceEvent = event
          fleeRequested = fleeRequested or response.requestFlee == true
        end
      end
      if emergenceRequested and semantics then
        local cell = Emergence.selectCell(entity, semantics, occupied, { radius = 1 })
        if cell then
          local avatar = RuntimeAvatarAdapter.materialize(mod, entity, cell, mapId)
          if avatar then
            Concealment.clear(entity)
            RuntimeState.reset(entity)
            if fleeRequested then
              entity.runtimeState.fearCurrent = 0.9
              entity.runtimeState.fearDirect = 0.9
              entity.runtimeState.fleeThreatPosition = sourceEvent
                and sourceEvent.sourcePosition or nil
              entity.runtimeState.fleeThreatPositionTick = simulationTick
              entity.runtimeState.fleeThreatEntityId = sourceEvent
                and sourceEvent.sourceEntityId or nil
            end
            WildEcology.activeAvatars[entityId] = avatar
            occupied[WorldSemantics.cellKey(cell.cellX, cell.cellY)] = true
          end
        end
      end
    end
  end
  local retained = {}
  for _, cue in ipairs(cues) do
    if simulationTick <= cue.expiresTick then retained[#retained + 1] = cue end
  end
  WildEcology.concealmentCuesByMap[mapId] = retained
end

local function applyBehaviorModeToActiveAvatar(mod, mapId, simulationTick)
  local phase0 = (Config and Config.phase0) or {}
  local avatar = WildEcology.activeAvatars[phase0.testEntityId]
  if not avatar then
    return false
  end

  local schedulerReason = nil
  local entity = WildEcology.entityById[phase0.testEntityId]
  local runtime = entity and entity.runtimeState or nil
  if entity and runtime then
    runtime.schedulerMetrics = runtime.schedulerMetrics or {}
    local metrics = runtime.schedulerMetrics
    metrics.lifecycleTicks = (metrics.lifecycleTicks or 0) + 1
    metrics.emergencyInterruptChecks = (metrics.emergencyInterruptChecks or 0) + 1
    local behaviorMode = readBehaviorMode(mod)
    local debugPreset = behaviorMode and behaviorMode:match("^force_(.+)$")
    local targetAvailable = runtime.targetEntityId == nil
      or runtime.targetEntityId == "player"
      or WildEcology.activeAvatars[runtime.targetEntityId] ~= nil
    local reason = Controller.reconsiderationReason(
      runtime, simulationTick, debugPreset, targetAvailable)
    runtime.deliberationDue = reason ~= nil
    runtime.deliberationPerformed = false
    runtime.reconsiderationReason = reason or "NOT_DUE"
    if not reason then
      local terminal = executeVisibleEntity(mod, mapId, entity, avatar, simulationTick)
      if not terminal then
        return true
      end
      reason = terminal
    end
    schedulerReason = reason
  end

  local payload = evaluatePhase0State(mod, mapId, false, simulationTick, schedulerReason)
  if not payload then
    return false
  end

  local debugState = getPhase0DebugState()
  local previousMode = debugState and debugState.lastBehaviorMode or nil
  local previousState = debugState and debugState.lastState or nil
  local modeChanged = previousMode ~= payload.behaviorMode
  local stateChanged = previousState ~= payload.state
  if not modeChanged and not stateChanged then
    applyMovementRequestToAvatar(mod, avatar, payload.entity)
    return true
  end

  avatar.behaviorMode = payload.behaviorMode
  avatar.runtimeState = payload.state

  local behaviorApplied = false
  if AvatarFactory and AvatarFactory.applyBehavior then
    behaviorApplied = AvatarFactory.applyBehavior(mod, avatar, payload.entity)
  elseif type(avatar.handle) == "table" then
    -- Legacy fallback for tests if the adapter seam is unavailable.
    avatar.handle.movement = payload.entity.avatar and payload.entity.avatar.movement or avatar.handle.movement
    avatar.handle.range = payload.entity.avatar and payload.entity.avatar.range or avatar.handle.range
    behaviorApplied = true
  end

  applyPhase0DebugState(debugState, {
    behaviorMode = payload.behaviorMode,
    entity = payload.entity,
    rel = payload.rel,
    state = payload.state,
    mapId = mapId,
    gainedCalmTrust = payload.gainedCalmTrust
  }, modeChanged and "mode_change" or "state_update", type(avatar) == "table" and avatar.id or nil)

  writeDebugLog(mod, "behavior", string.format("Applied live behavior update: mode=%s state=%s trust=%s threat=%s runtime=%s", tostring(payload.behaviorMode), tostring(payload.state), tostring(payload.rel.trust or 0), tostring(payload.rel.threatMemory or 0), tostring(behaviorApplied)))
  applyMovementRequestToAvatar(mod, avatar, payload.entity)

  if Save and Save.flush then
    Save.flush()
  end

  return true
end

function WildEcology.init(mod, skipSpawnSync)
  local mapId = readCurrentMapId(mod)
  if not isEcologyMap(mapId) then
    return
  end

  ensureSave(mod)
  if not Save or not Save.nextTick then
    return
  end
  local simulationTick = Save.nextTick()
  recordPlayerMovementDisturbance(mod, mapId, simulationTick)
  updateConcealedPopulation(mod, mapId, simulationTick)
  local clockSample = WildEcology.currentClockSample or sampleEcologyClock(mod, false)
  if clockSample and DormantLifecycle then
    DormantLifecycle.catchUpBeforeMaterialization(
      Save.getState(), mapId, clockSample)
  end
  local seed = currentVisitSeed(mapId)
  if isPhase0AnchorMap(mapId) then
    if applyBehaviorModeToActiveAvatar(mod, mapId, simulationTick) then
      if not skipSpawnSync and not spawnSyncIsStable(mapId) then
        spawnPhase3Avatars(mod, mapId, seed)
      elseif not skipSpawnSync then
        WildEcology.spawnDiagnostics.phase3SyncSkipped =
          WildEcology.spawnDiagnostics.phase3SyncSkipped + 1
      end
      local urgentById = observeActivePopulation(mod, mapId)
      updateActivePopulationBehavior(mod, mapId, simulationTick, urgentById)
      if WildEcology.agentAudit then
        WildEcology.agentAudit:sample(
          simulationTick, buildAgentAuditSamples(mapId))
      end
      flushConsoleQueue(mod)
      flushRelationshipAudit(mod)
      flushAgentAudit(mod)
      return
    end

    local spawned = spawnPhase0Avatar(mod, mapId, nil, simulationTick)
    seed = spawned and spawned.entity and spawned.entity.memory and spawned.entity.memory.debug and spawned.entity.memory.debug.respawnCount
      or seed
  end
  if not skipSpawnSync and not spawnSyncIsStable(mapId) then
    spawnPhase3Avatars(mod, mapId, seed)
  else
    WildEcology.spawnDiagnostics.phase3SyncSkipped =
      WildEcology.spawnDiagnostics.phase3SyncSkipped + 1
  end
  local urgentById = observeActivePopulation(mod, mapId)
  updateActivePopulationBehavior(mod, mapId, simulationTick, urgentById)
  if WildEcology.agentAudit then
    WildEcology.agentAudit:sample(
      simulationTick, buildAgentAuditSamples(mapId))
  end
  flushConsoleQueue(mod)
  flushRelationshipAudit(mod)
  flushAgentAudit(mod)
end

function WildEcology.sync(mod)
  local profiler = WildEcology.performanceProfiler
  if profiler.enabled then
    profiler.samples = profiler.samples + 1
    local state = Save and Save.getState and Save.getState() or nil
    profiler.lastTick = state and state.simulationTick or nil
    profiler.startedAtTick = profiler.startedAtTick or profiler.lastTick
    if profiler.lastTick and (profiler.lastMemorySampleTick == nil
      or profiler.lastTick - profiler.lastMemorySampleTick >= 300) then
      profiler.lastMemorySampleTick = profiler.lastTick
      profiler.memorySamples[#profiler.memorySamples + 1] = {
        tick = profiler.lastTick,
        luaKB = collectgarbage and collectgarbage("count") or 0
      }
      while #profiler.memorySamples > 64 do
        table.remove(profiler.memorySamples, 1)
      end
    end
  end
  local mapId = readCurrentMapId(mod)
  local clockSample = sampleEcologyClock(mod, true)
  if clockSample and clockSample.discontinuity == "FORWARD"
    and next(WildEcology.activeAvatars) ~= nil then
    local liveMapId = WildEcology.spawnInitialization.mapId or mapId
    local entities, positions = {}, {}
    for entityId in pairs(WildEcology.activeAvatars) do
      local entity = WildEcology.entityById[entityId]
      if entity then
        entities[#entities + 1] = entity
        positions[entityId] = perceptionPositionForEntity(entity)
      end
    end
    DormantLifecycle.advanceLive(liveMapId, entities, clockSample, {
      positions = positions,
      reachableWater = WildEcology.dormantEnvironmentByMap[liveMapId]
        and WildEcology.dormantEnvironmentByMap[liveMapId].reachableWater
    })
  end
  if isEcologyMap(mapId) then
    if normalizeMapId(WildEcology.routeVisitMapId) ~= normalizeMapId(mapId) then
      WildEcology.routeVisitEpoch = WildEcology.routeVisitEpoch + 1
      WildEcology.routeVisitMapId = mapId
      WildEcology.routeVisitCounts[mapId] =
        (WildEcology.routeVisitCounts[mapId] or 0) + 1
      WildEcology.visiblePopulationByMap[mapId] = nil
      WildEcology.visitSpawnCells[mapId] = nil
      WildEcology.expectedSpawnIds = {}
      WildEcology.spawnSyncDirty = true
      WildEcology.spawnRetryTick = nil
    end
    local initialization = WildEcology.spawnInitialization
    if initialization.mapId ~= nil
      and normalizeMapId(initialization.mapId) ~= normalizeMapId(mapId)
      and next(WildEcology.activeAvatars) ~= nil then
      WildEcology.shutdown()
    end
    local semantics = WorldSemantics and WorldSemantics.fromMod
      and WorldSemantics.fromMod(mod, mapId)
      or nil
    if not semantics then
      local productionProbe = WorldSemantics and WorldSemantics.getLastProductionProbe
        and WorldSemantics.getLastProductionProbe(mapId)
        or nil
      initialization.status = "PENDING_WORLD"
      initialization.mapId = mapId
      initialization.semanticsGeneration = nil
      initialization.reason = productionProbe and productionProbe.semanticsReason
        or "SEMANTICS_UNAVAILABLE"
      initialization.lastError = nil
      return false
    end

    local continuingComplete = initialization.status == "COMPLETE"
      and initialization.mapId == mapId
      and initialization.semanticsGeneration == semantics.generation
    if not continuingComplete then
      if PopulationManager and PopulationManager.getRoutePopulationMembers then
        PopulationManager.getRoutePopulationMembers(mapId, mod)
      end
      initialization.status = "RUNNING"
      initialization.mapId = mapId
      initialization.semanticsGeneration = semantics.generation
      initialization.reason = "SEMANTICS_READY"
      initialization.lastError = nil
      initialization.attempts = (initialization.attempts or 0) + 1
    end
    if continuingComplete then
      if not spawnSyncIsStable(mapId) then
        initialization.status = "RUNNING"
        initialization.reason = "SPAWN_SYNC_DIRTY"
        WildEcology.init(mod)
        initialization.status = "COMPLETE"
        initialization.reason = "COMPLETE"
      else
        WildEcology.init(mod, true)
      end
      return true
    end
    WildEcology.init(mod)
    local production = PopulationManager and PopulationManager.getSpawnDebugSnapshot
      and PopulationManager.getSpawnDebugSnapshot(mapId)
      or nil
    local analysis = production and production.candidateAnalysis or nil
    if analysis then
      initialization.status = "COMPLETE"
      initialization.reason = production and production.assignmentStatus or "COMPLETE"
      initialization.semanticsGeneration = analysis.semanticsGeneration
    else
      initialization.status = "PENDING_WORLD"
      initialization.reason = "CANDIDATE_ANALYSIS_NOT_RUN"
    end
    return initialization.status == "COMPLETE"
  end

  if next(WildEcology.activeAvatars) ~= nil then
    WildEcology.shutdown()
  end
  WildEcology.routeVisitMapId = nil
  WildEcology.visiblePopulationByMap = {}
  WildEcology.visitSpawnCells = {}
  WildEcology.expectedSpawnIds = {}
  WildEcology.spawnSyncDirty = true
  WildEcology.spawnInitialization.status = "NOT_RUN"
  WildEcology.spawnInitialization.mapId = mapId
  WildEcology.spawnInitialization.semanticsGeneration = nil
  WildEcology.spawnInitialization.reason = "ECOLOGY_DISABLED"
  WildEcology.spawnInitialization.lastError = nil
  return false
end

local function synchronizeSafely(mod)
  performanceCount("sync_calls")
  local profileName, profileStart = performanceStart("sync")
  local okSync, syncResult = pcall(WildEcology.sync, mod)
  performanceStop(profileName, profileStart)
  if not okSync then
    local initialization = WildEcology.spawnInitialization
    initialization.status = "ERROR"
    initialization.mapId = readCurrentMapId(mod)
    initialization.reason = "SYNC_ERROR"
    initialization.lastError = tostring(syncResult):gsub("[\r\n]+", " "):sub(1, 160)
    return false, syncResult
  end
  return syncResult == true, nil
end

local function findPersistentEntity(entityId)
  local state = Save and Save.getState and Save.getState() or nil
  for _, population in pairs(state and state.populations or {}) do
    local entity = population.members and population.members[entityId]
    if entity then
      return entity
    end
  end
  return nil
end

local function retainLocalMaterializationPosition(entity, avatar)
  if not entity or not avatar or not RuntimeAvatarAdapter
    or not RuntimeAvatarAdapter.readPosition then return false end
  local position = RuntimeAvatarAdapter.readPosition(WildEcology.mod, avatar)
  if not position or position.cellX == nil or position.cellY == nil then
    return false
  end
  entity.home = entity.home or {}
  entity.home.spawnX = position.cellX
  entity.home.spawnY = position.cellY
  return true
end

function WildEcology.shutdown()
  flushRelationshipAudit(WildEcology.mod, true)
  flushAgentAudit(WildEcology.mod, true)
  if not AvatarFactory or not AvatarFactory.despawn then
    return
  end

  local ids = {}
  for id in pairs(WildEcology.activeAvatars) do
    ids[#ids + 1] = id
  end
  table.sort(ids, function(left, right)
    return tostring(left) < tostring(right)
  end)
  local state = Save and Save.getState and Save.getState() or nil
  local cohortMapId = WildEcology.spawnInitialization.mapId
  if state and cohortMapId and DormantLifecycle
    and WildEcology.currentClockSample then
    local entities, positions = {}, {}
    for _, id in ipairs(ids) do
      local entity = findPersistentEntity(id)
      if entity then
        entities[#entities + 1] = entity
        positions[id] = perceptionPositionForEntity(entity)
      end
    end
    DormantLifecycle.capture(state, cohortMapId, entities,
      WildEcology.currentClockSample, {
        positions = positions,
        reachableWater = WildEcology.dormantEnvironmentByMap[cohortMapId]
          and WildEcology.dormantEnvironmentByMap[cohortMapId].reachableWater
      })
  end
  if WildEcology.movementClaims then
    WildEcology.movementClaims:clearAll(
      state and state.simulationTick or 0, "MAP_OR_RUNTIME_RESET")
  end

  for _, id in ipairs(ids) do
    local avatar = WildEcology.activeAvatars[id]
    local entity = findPersistentEntity(id)
    retainLocalMaterializationPosition(entity, avatar)
    local debugState = getPhase0DebugState()
    if debugState then
      debugState.lastEvent = "despawn"
      debugState.lastEntityId = id
      debugState.lastDespawnAvatarId = type(avatar) == "table" and avatar.id or avatar
      debugState.lastRespawnCount = type(avatar) == "table" and avatar.spawnSequence or debugState.lastRespawnCount
      debugState.lastContextMapId = readCurrentMapId(WildEcology.mod)
    end

    writeDebugLog(WildEcology.mod, "lifecycle", string.format("Despawned avatar %s after leaving to %s", tostring(type(avatar) == "table" and avatar.id or avatar or "none"), tostring(readCurrentMapId(WildEcology.mod) or "unknown")))

    if RuntimeAvatarAdapter and RuntimeAvatarAdapter.destroy then
      RuntimeAvatarAdapter.destroy(WildEcology.mod, avatar)
    else
      AvatarFactory.despawn(WildEcology.mod, avatar)
    end
    if entity and RuntimeState then
      RuntimeState.reset(entity)
    end
    WildEcology.activeAvatars[id] = nil
  end

  WildEcology.perceptionPairs = {}
  WildEcology.perceptionPositions = {}
  WildEcology.perceptionNeighbors = {}
  WildEcology.spawnSyncDirty = true
  WildEcology.spawnRetryTick = nil

  if WildEcology.saveReady and Save and Save.flush then
    Save.flush()
  end
end

function WildEcology.start(mod)
  installRequireShim(mod)

  local loaded, loadErr = loadModules(mod)
  if not loaded then
    error(loadErr)
  end

  WildEcology.mod = mod
  resetConsoleLogEpoch(mod, readSaveFlag(mod,
    DEBUG_LOG_CONSOLE_OPTION_KEY, false) == true)
  local auditConfig = Config.relationshipAudit or {}
  WildEcology.relationshipAudit = nil
  setRelationshipAuditEnabled(mod, readSaveFlag(mod,
    DEBUG_LOG_RELATIONSHIP_AUDIT_OPTION_KEY,
    auditConfig.defaultEnabled == true) == true)
  local agentAuditConfig = Config.agentAudit or {}
  WildEcology.agentAudit = nil
  setAgentAuditEnabled(mod, readSaveFlag(mod,
    DEBUG_LOG_AGENT_AUDIT_OPTION_KEY,
    agentAuditConfig.defaultEnabled == true) == true)
  WildEcology.movementClaims = MovementClaims.new(function(action, claim, reason, conflict)
    local focusedId = WildEcology.focusedEntityId
      or (Config and Config.phase0 and Config.phase0.testEntityId)
    local trace = readBehaviorTraceEnabled(mod)
    local routine = action == "PUBLISHED" or action == "UPDATED"
      or (action == "CLEARED" and (reason == "MOVEMENT_COMPLETED"
        or reason == "DESTINATION_REACHED" or reason == "NO_MOVEMENT_REQUEST"))
    if readPhase5DiagnosticsEnabled(mod) and claim.actorId == focusedId
      and (trace or not routine) then
      writeDebugLog(mod, "behavior", string.format(
        "Movement claim actor=%s from=%s,%s to=%s,%s intent=%s urgency=%.2f claimAction=%s conflictActorId=%s conflictType=%s reason=%s",
        tostring(claim.actorId), tostring(claim.fromX), tostring(claim.fromY),
        tostring(claim.toX), tostring(claim.toY), tostring(claim.intent or "none"),
        claim.urgency or 0, tostring(action),
        tostring(conflict and conflict.actorId or "none"),
        tostring(conflict and conflict.type or "none"), tostring(reason or "none")
      ))
    end
  end)
  defineOptions(mod)
  if PopulationManager and PopulationManager.setSpawnDiagnosticSink then
    PopulationManager.setSpawnDiagnosticSink(function(message)
      writeSpawnGenerationDiagnostic(mod, message)
    end)
  end
  if Relationships and Relationships.setMutationSink then
    Relationships.setMutationSink(function(mutation)
      local relationshipAuditEmission = nil
      if WildEcology.relationshipAudit then
        local _, emission = WildEcology.relationshipAudit:observe(mutation)
        relationshipAuditEmission = emission
      end
      if WildEcology.agentAudit then
        WildEcology.agentAudit:observeMutation(
          mutation, relationshipAuditEmission)
      end
      local focusedId = WildEcology.focusedEntityId
        or (Config and Config.phase0 and Config.phase0.testEntityId)
      if not readBehaviorTraceEnabled(mod)
        or mutation.observerId ~= focusedId then
        return
      end
      local changes = {}
      for _, change in ipairs(mutation.changes or {}) do
        changes[#changes + 1] = string.format("%s=%s->%s",
          tostring(change.field), tostring(change.old), tostring(change.new))
      end
      if #changes > 0 then
        writeDebugLog(mod, "relationships", string.format(
          "RELATIONSHIP observer=%s subject=%s event=%s tick=%s %s",
          tostring(mutation.observerId), tostring(mutation.subjectId),
          tostring(mutation.event), tostring(mutation.tick or "none"),
          table.concat(changes, " ")))
      end
    end)
  end
  if Social and Social.setContactSink then
    Social.setContactSink(function(contact)
      if WildEcology.agentAudit then
        WildEcology.agentAudit:observeContact(contact)
      end
    end)
  end
  if Relationships and Relationships.setDiagnosticSink then
    Relationships.setDiagnosticSink(function(event)
      if WildEcology.agentAudit then
        WildEcology.agentAudit:observeEvent(event)
      end
    end)
  end
  if DormantLifecycle and DormantLifecycle.setDiagnosticSink then
    DormantLifecycle.setDiagnosticSink(function(event)
      if event.event == "DORMANT_CATCHUP_START"
        or event.event == "DORMANT_CATCHUP_COMPLETE" then
        writeDebugLog(mod, "lifecycle", string.format(
          "%s map=%s elapsed=%s members=%s pairs=%s social=%s",
          tostring(event.event), tostring(event.mapId), tostring(event.elapsed or 0),
          tostring(event.members or "none"), tostring(event.pairCandidates or "none"),
          tostring(event.socialUpdates or "none")))
      end
    end)
  end
  if Controller and Controller.setHomeostasisSummarySink then
    Controller.setHomeostasisSummarySink(function(summary)
      writeHomeostasisWindowSummary(mod, summary)
    end)
  end
  if NavigationExecution and NavigationExecution.setDiagnosticSink then
    NavigationExecution.setDiagnosticSink(function(event)
      entityBlockDiagnostic(mod, event)
    end)
  end
  if AvatarFactory and AvatarFactory.setSpawnDiagnosticSink then
    AvatarFactory.setSpawnDiagnosticSink(function(eventName, entity, spawnCell,
      mapId, result, reason)
      if eventName == "SPAWN_NPC_CALLED" then
        WildEcology.spawnDiagnostics.spawnNpcCalls = WildEcology.spawnDiagnostics.spawnNpcCalls + 1
      elseif eventName == "SPAWN_NPC_RESULT"
        or eventName == "SPAWN_NPC_UNAVAILABLE" then
        local runtime = WildEcology.spawnDiagnostics
        runtime.lastRequestedEntityId = entity and entity.id or runtime.lastRequestedEntityId
        runtime.lastRequestedSpecies = entity and entity.species or runtime.lastRequestedSpecies
        runtime.lastRequestedCell = spawnCell
          and tostring(spawnCell.cellX) .. "," .. tostring(spawnCell.cellY)
          or runtime.lastRequestedCell
        runtime.lastRequestedMapId = mapId
        runtime.lastAdapterResult = result ~= nil and tostring(result) or "nil"
        runtime.lastAdapterReason = reason or eventName
      end
    end)
  end
  if SpeciesSprites and SpeciesSprites.registerAll then
    SpeciesSprites.registerAll(mod)
  end
  registerLogSettingsScreen(mod)
  registerLogSettingsMenuEntry(mod)
  registerDebugUi(mod)

  if not WildEcology.updateHookInstalled then
    local ok, OverworldController = pcall(require, "src.world.OverworldController")
    if ok and OverworldController and type(OverworldController.update) == "function" then
      local originalUpdate = OverworldController.update
      OverworldController.update = function(self, dt)
        originalUpdate(self, dt)
        synchronizeSafely(mod)
      end
      WildEcology.updateHookInstalled = true
    end
  end

  synchronizeSafely(mod)
  return WildEcology
end

return function(mod)
  return WildEcology.start(mod)
end
