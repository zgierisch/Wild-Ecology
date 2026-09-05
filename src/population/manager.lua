local Config = require("src.core.config")
local Save = require("src.core.save")
local Generator = require("src.population.generator")
local Selection = require("src.population.selection")
local Relationships = require("src.entities.relationships")
local Social = require("src.behavior.social")
local SpawnCells = require("src.world.spawn_cells")
local WorldSemantics = require("src.world.world_semantics")
local HomeArea = require("src.world.home_area")
local SpeciesEcology = require("src.species.species_ecology")

local PopulationManager = {}

local spawnPositionSources = setmetatable({}, { __mode = "k" })
local spawnDiagnosticSink = nil
local diagnosedSemanticsByPopulation = setmetatable({}, { __mode = "k" })
local assignmentFailureSemanticsByPopulation = setmetatable({}, { __mode = "k" })
local assignmentGenerationByPopulation = setmetatable({}, { __mode = "k" })
local spawnDebugByMap = {}

local function emitSpawnDiagnostic(message)
  if spawnDiagnosticSink then
    pcall(spawnDiagnosticSink, message)
  end
end

local function routeKeyForMap(mapId)
  local ecologyMap = Config.ecologyMap and Config.ecologyMap(mapId) or nil
  if not ecologyMap or not ecologyMap.populationKey then
    error("route population requested for disabled ecology map " .. tostring(mapId))
  end
  return ecologyMap.populationKey
end

local function orderMembers(members)
  local ordered = {}
  for _, entity in pairs(members or {}) do
    ordered[#ordered + 1] = entity
  end

  table.sort(ordered, function(left, right)
    return tostring(left and left.id or "") < tostring(right and right.id or "")
  end)

  return ordered
end

local function existingMaxSerial(members)
  local maxSerial = 0
  for entityId in pairs(members or {}) do
    local serialText = tostring(entityId):match("wild:[^:]+:(%d+)")
    local serial = tonumber(serialText) or 0
    if serial > maxSerial then
      maxSerial = serial
    end
  end
  return maxSerial
end

local function assignSpawnCells(mapId, routePopulation, mod, semantics)
  local occupiedKeys = {}
  local orderedIds = routePopulation.order or {}
  if not semantics then
    semantics = WorldSemantics.fromMod(mod, mapId)
  end
  local representativeEntity = routePopulation.members and routePopulation.members[orderedIds[1]] or nil
  local candidateAnalysis = representativeEntity
    and SpawnCells.analyzeCandidates(mod, mapId, representativeEntity, semantics)
    or nil
  local diagnosticIdentity = semantics or false
  if diagnosedSemanticsByPopulation[routePopulation] ~= diagnosticIdentity then
    emitSpawnDiagnostic(SpawnCells.formatCandidateAnalysis(candidateAnalysis))
    diagnosedSemanticsByPopulation[routePopulation] = diagnosticIdentity
  end

  for index = 1, #orderedIds do
    local entityId = orderedIds[index]
    local entity = routePopulation.members and routePopulation.members[entityId] or nil
    if entity then
      entity.home = entity.home or {}
      if entity.home.spawnX ~= nil and entity.home.spawnY ~= nil then
        if spawnPositionSources[entity] == nil then
          spawnPositionSources[entity] = "PERSISTED_HOME"
        end
        entity.home.spawnViability = SpawnCells.assess(entity, semantics, {
          x = entity.home.spawnX,
          y = entity.home.spawnY
        }, mod, mapId)
        occupiedKeys[SpawnCells.keyForCell({ x = entity.home.spawnX, y = entity.home.spawnY })] = true
      end
    end
  end

  for index = 1, #orderedIds do
    local entityId = orderedIds[index]
    local entity = routePopulation.members and routePopulation.members[entityId] or nil
    if entity then
      entity.home = entity.home or {}
      if entity.home.spawnX == nil or entity.home.spawnY == nil then
        local cell = SpawnCells.pickCell(mapId, entity.home.zoneId, occupiedKeys, index, mod, entity, candidateAnalysis)
        if cell then
          entity.home.spawnX = cell.x
          entity.home.spawnY = cell.y
          entity.home.spawnViability = "VALID"
          spawnPositionSources[entity] = "NEW_SPAWN"
          occupiedKeys[SpawnCells.keyForCell(cell)] = true
        else
          entity.home.spawnViability = "NO_TRAVERSABLE_EXIT"
          if assignmentFailureSemanticsByPopulation[routePopulation] ~= diagnosticIdentity then
            emitSpawnDiagnostic(string.format(
              "SpawnAssignment entity=%s map=%s result=NO_CANDIDATE candidateCount=%s",
              tostring(entity.id), tostring(mapId),
              tostring(candidateAnalysis and candidateAnalysis.finalCandidateCount or 0)
            ))
            assignmentFailureSemanticsByPopulation[routePopulation] = diagnosticIdentity
          end
        end
      end
      if entity.home.spawnX ~= nil and entity.home.spawnY ~= nil
        and entity.home.area == nil then
        local profile = SpeciesEcology.getResolved(entity.species)
        HomeArea.establish(entity, semantics, {
          mapId = mapId,
          anchorCell = {
            cellX = entity.home.spawnX, cellY = entity.home.spawnY
          },
          radius = profile.home.radius,
          establishedTick = Save.getState()
            and Save.getState().simulationTick or 0,
          provenance = "POPULATION_PLACEMENT"
        })
      end
    end
  end

  local populationRecords = 0
  local homesAssigned = 0
  local homesMissing = 0
  local samples = {}
  for _, entityId in ipairs(orderedIds) do
    local entity = routePopulation.members and routePopulation.members[entityId] or nil
    if entity then
      populationRecords = populationRecords + 1
      local home = entity.home or {}
      if home.spawnX ~= nil and home.spawnY ~= nil then
        homesAssigned = homesAssigned + 1
      else
        homesMissing = homesMissing + 1
      end
      if #samples < 3 then
        samples[#samples + 1] = {
          id = entity.id,
          x = home.spawnX,
          y = home.spawnY
        }
      end
    end
  end
  local assignmentStatus = "ASSIGNED"
  if populationRecords == 0 then
    assignmentStatus = "NOT_RUN"
  elseif homesMissing > 0 and (not candidateAnalysis or candidateAnalysis.finalCandidateCount == 0) then
    assignmentStatus = "NO_CANDIDATES"
  elseif homesMissing > 0 then
    assignmentStatus = "PARTIAL"
  end
  spawnDebugByMap[mapId] = {
    mapId = mapId,
    semantics = semantics,
    candidateAnalysis = candidateAnalysis,
    population = routePopulation,
    populationRecords = populationRecords,
    homesAssigned = homesAssigned,
    homesMissing = homesMissing,
    populationSamples = samples,
    assignmentStatus = assignmentStatus,
    assignmentAnalysis = candidateAnalysis,
    candidateAnalysisRuns = SpawnCells.getCandidateAnalysisRunCount()
  }
  assignmentGenerationByPopulation[routePopulation] = semantics and semantics.generation or nil
  return true
end

local function ensureSpawnAssignments(mapId, routePopulation, mod, force)
  local semantics = WorldSemantics.fromMod(mod, mapId)
  if not semantics then
    return assignSpawnCells(mapId, routePopulation, mod, nil)
  end
  local generation = semantics.generation
  if not force
    and generation ~= nil
    and assignmentGenerationByPopulation[routePopulation] == generation
    and spawnDebugByMap[mapId] ~= nil then
    return true
  end
  return assignSpawnCells(mapId, routePopulation, mod, semantics)
end

function PopulationManager.setSpawnDiagnosticSink(sink)
  spawnDiagnosticSink = type(sink) == "function" and sink or nil
end

function PopulationManager.getSpawnDebugSnapshot(mapId)
  return spawnDebugByMap[mapId]
end

local function getOrCreateRoutePopulation(state, mapId)
  state.populations = state.populations or {}
  if not state.populations[mapId] then
    state.populations[mapId] = { members = {} }
  end
  state.populations[mapId].members = state.populations[mapId].members or {}
  return state.populations[mapId]
end

function PopulationManager.getOrCreatePhase0Entity(mod)
  local state = Save.getState()
  local routePopulation = PopulationManager.getOrCreateRoutePopulation(Config.phase0.testMapId, mod)
  local members = routePopulation.members

  local entity = members[Config.phase0.testEntityId]
  if not entity then
    entity = Generator.makePhase0Pidgey(Config.phase0.testEntityId, {
      species = Config.phase0.testSpecies,
      level = Config.phase0.testLevel,
      personalitySeed = Config.phase0.testPersonalitySeed,
      mapId = Config.phase0.testMapId,
      zoneId = Config.phase0.testZoneId,
      mod = mod
    })
    members[entity.id] = entity
    routePopulation.order = routePopulation.order or {}
    routePopulation.order[#routePopulation.order + 1] = entity.id
  end

  return entity
end

function PopulationManager.getOrCreateRoutePopulation(mapId, mod)
  local state = Save.getState()
  if state == nil then
    Save.nextTick()
    state = Save.getState()
  end
  if state == nil then
    error("save state should be initialized before route population access")
  end
  local routePopulation = getOrCreateRoutePopulation(state, mapId)
  local phase3 = Config.phase3 or {}
  local poolConfig = { speciesPool = phase3.speciesPool, zoneOrder = phase3.zoneOrder }
  local targetCount = phase3.routePopulationSize or 0

  routePopulation.order = routePopulation.order or {}
  if #routePopulation.order == 0 and next(routePopulation.members) ~= nil then
    routePopulation.order = orderMembers(routePopulation.members)
  end

  local routeKey = routeKeyForMap(mapId)
  local stateNextSerial = tonumber(state.nextEntitySerial) or 1
  local existingNextSerial = existingMaxSerial(routePopulation.members) + 1
  local nextSerial = math.max(stateNextSerial, existingNextSerial)
  local needed = targetCount - #routePopulation.order
  if needed > 0 then
    local startIndex = #routePopulation.order
    local generatedPopulation, updatedSerial = Generator.makeRoutePopulation(mapId, routeKey, poolConfig, needed, nextSerial, mod, startIndex)
    nextSerial = updatedSerial
    for _, entityId in ipairs(generatedPopulation.order) do
      local generatedEntity = generatedPopulation.members[entityId]
      routePopulation.members[entityId] = generatedEntity
      routePopulation.order[#routePopulation.order + 1] = entityId
    end
  end

  state.nextEntitySerial = math.max(stateNextSerial, tonumber(nextSerial) or stateNextSerial)
  ensureSpawnAssignments(mapId, routePopulation, mod, needed > 0)
  return routePopulation
end

function PopulationManager.getRoutePopulationMembers(mapId, mod)
  local routePopulation = PopulationManager.getOrCreateRoutePopulation(mapId, mod)
  return orderMembers(routePopulation.members)
end

function PopulationManager.getVisibleRoutePopulation(mapId, simulationTick, mod)
  local phase3 = Config.phase3 or {}
  local members = PopulationManager.getRoutePopulationMembers(mapId, mod)
  local maxCount = phase3.visibleSubsetSize or #members
  return Selection.pickVisibleSubsetWithAnchor(members, maxCount, simulationTick, Config.phase0.testEntityId)
end

function PopulationManager.assessMaterialization(entity, mod, mapId)
  if not entity then
    return "MISSING_ENTITY"
  end
  local semantics = WorldSemantics.fromMod(mod, mapId)
  local home = entity.home or {}
  local cell = PopulationManager.canonicalSpawnCell(entity)
  local status, details = SpawnCells.assess(entity, semantics, cell, mod, mapId)
  details.rawPosition = {
    spawnX = home.spawnX,
    spawnY = home.spawnY,
    avatarX = entity.avatar and entity.avatar.x or nil,
    avatarY = entity.avatar and entity.avatar.y or nil
  }
  details.positionSource = spawnPositionSources[entity] or "PERSISTED_HOME"
  return status, details
end

function PopulationManager.canonicalSpawnCell(entity)
  local home = entity and entity.home or nil
  if not home or home.spawnX == nil or home.spawnY == nil then
    return nil
  end
  return { cellX = home.spawnX, cellY = home.spawnY }
end

function PopulationManager.markSpawnPositionPersisted(entity)
  if entity then
    spawnPositionSources[entity] = "PERSISTED_HOME"
  end
end

function PopulationManager.updatePhase0Relationship(entity, playerEntity, simulationTick, distance)
  local rel, gainedCalmTrust = Relationships.observeCalmProximity(
    entity,
    playerEntity.id,
    simulationTick,
    Config.phase0.calmProximityCooldownTicks,
    distance
  )
  if not rel then return {}, false end
  rel.trust = math.max(rel.trust, Config.phase0.defaultRelationshipTrust)
  return rel, gainedCalmTrust
end

-- Generic social propagation: a trusted nearby associate's own current
-- behavior (fleeing something, or calmly approaching/tolerating it) can
-- rub off on the observer's relationship with WHATEVER the associate is
-- reacting to -- not a fixed demo associate, and not player-only. Reuses
-- the same Relationships.applySocialFear/applySocialReassurance primitives
-- (already generic); this is just the caller that discovers source/target
-- dynamically instead of hardcoding them.
function PopulationManager.propagateAssociateSocialSignal(entity, associateEntity, simulationTick, distance)
  if not associateEntity or not associateEntity.id or associateEntity.id == entity.id then
    return nil, 0, "none"
  end

  local associateRel = Relationships.getOrCreate(entity, associateEntity.id)
  if not Social.shouldFollowAssociate(associateRel) then
    return nil, 0, "none"
  end

  local associateRuntimeState = associateEntity.runtimeState or {}
  local associateTargetId = associateRuntimeState.targetEntityId
  if not associateTargetId or associateTargetId == entity.id then
    return nil, 0, "none"
  end

  local phase2 = Config.phase2 or {}
  if associateRuntimeState.state == "FLEE" then
    local signal = phase2.socialFearSignal or 0
    local cooldown = phase2.socialFearCooldownTicks or 0
    local rel, delta = Relationships.applySocialFear(entity, associateEntity.id, associateTargetId, simulationTick, signal, cooldown, distance)
    return rel, delta, "fear"
  elseif associateRuntimeState.state == "APPROACH" then
    local signal = phase2.socialReassuranceSignal or 0
    local cooldown = phase2.socialReassuranceCooldownTicks or 0
    local rel, delta = Relationships.applySocialReassurance(entity, associateEntity.id, associateTargetId, simulationTick, signal, cooldown, distance)
    return rel, delta, "reassurance"
  end

  return nil, 0, "none"
end

return PopulationManager
