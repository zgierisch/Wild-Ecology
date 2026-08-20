local Config = require("src.core.config")
local Save = require("src.core.save")
local Generator = require("src.population.generator")
local Relationships = require("src.entities.relationships")

local PopulationManager = {}

function PopulationManager.getOrCreatePhase0Entity()
  local state = Save.getState()
  state.entities = state.entities or {}

  local entity = state.entities[Config.phase0.testEntityId]
  if not entity then
    entity = Generator.makePhase0Pidgey(Config.phase0.testEntityId)
    state.entities[entity.id] = entity
  end

  return entity
end

function PopulationManager.updatePhase0Relationship(entity, playerEntity)
  local rel = Relationships.observeCalmProximity(entity, playerEntity.id)
  rel.trust = math.max(rel.trust, Config.phase0.defaultRelationshipTrust)
  return rel
end

return PopulationManager
