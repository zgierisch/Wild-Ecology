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
  return rel
end

return PopulationManager
