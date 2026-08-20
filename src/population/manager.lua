local Config = require("src.core.config")
local Save = require("src.core.save")
local Generator = require("src.population.generator")
local Relationships = require("src.entities.relationships")

local PopulationManager = {}

local function getOrCreateRoutePopulation(state, mapId)
  state.populations = state.populations or {}
  if not state.populations[mapId] then
    state.populations[mapId] = { members = {} }
  end
  state.populations[mapId].members = state.populations[mapId].members or {}
  return state.populations[mapId]
end

function PopulationManager.getOrCreatePhase0Entity()
  local state = Save.getState()
  local routePopulation = getOrCreateRoutePopulation(state, Config.phase0.testMapId)
  local members = routePopulation.members

  local entity = members[Config.phase0.testEntityId]
  if not entity then
    entity = Generator.makePhase0Pidgey(Config.phase0.testEntityId)
    members[entity.id] = entity
  end

  return entity
end

function PopulationManager.updatePhase0Relationship(entity, playerEntity, simulationTick)
  local rel = Relationships.observeCalmProximity(
    entity,
    playerEntity.id,
    simulationTick,
    Config.phase0.calmProximityCooldownTicks
  )
  rel.trust = math.max(rel.trust, Config.phase0.defaultRelationshipTrust)
  local gainedCalmTrust = rel.lastCalmTick == simulationTick
  return rel, gainedCalmTrust
end

function PopulationManager.getOrCreatePhase2AssociateRelationship(entity, simulationTick)
  local phase2 = Config.phase2 or {}
  local associateId = phase2.demoAssociateId or "wild:route01:ally"
  local rel = Relationships.getOrCreate(entity, associateId)

  rel.lastSeenTick = simulationTick or rel.lastSeenTick
  rel.familiarity = math.max(rel.familiarity or 0, 10)
  rel.trust = math.max(rel.trust or 0, phase2.defaultAssociateTrust or 60)

  return rel
end

function PopulationManager.applyPhase2SocialFear(entity, playerEntity, simulationTick)
  local phase2 = Config.phase2 or {}
  local associateId = phase2.demoAssociateId or "wild:route01:ally"
  local signal = phase2.socialFearSignal or 0
  return Relationships.applySocialFear(entity, associateId, playerEntity.id, simulationTick, signal)
end

return PopulationManager
