local SpeciesEcology = require("src.species.species_ecology")
local WorldSemantics = require("src.world.world_semantics")

local FoodOpportunities = {}

local DEFINITIONS = {
  TALL_GRASS_FORAGE = {
    semantic = "TALL_GRASS",
    feedingDuration = 12,
    depletionTicks = 300,
    value = 0.72,
    provenance = "WORLD_SEMANTIC"
  }
}

local depletedUntil = {}

local function key(mapId, x, y, opportunityType)
  return table.concat({ tostring(mapId), tostring(x), tostring(y),
    tostring(opportunityType) }, ":")
end

local function acceptedTypes(entity)
  local profile = SpeciesEcology.getResolved(entity and entity.species)
  return profile.feeding and profile.feeding.acceptedOpportunityTypes or {}
end

function FoodOpportunities.isAvailable(opportunity, tick)
  if not opportunity or not opportunity.key then return false end
  return (depletedUntil[opportunity.key] or 0) <= (tick or 0)
end

function FoodOpportunities.findNearby(entity, context, tick)
  if not context or not context.worldSemantics or not context.position then return {} end
  local results = {}
  for _, opportunityType in ipairs(acceptedTypes(entity)) do
    local definition = DEFINITIONS[opportunityType]
    if definition then
      local cells = WorldSemantics.findNearbyFeature(context.worldSemantics,
        context.position, definition.semantic, context.needSearchRadius or 12)
      for _, cell in ipairs(cells) do
        local opportunity = {
          kind = "FOOD_OPPORTUNITY",
          opportunityType = opportunityType,
          semantic = definition.semantic,
          cellX = cell.x,
          cellY = cell.y,
          distance = cell.distance,
          mapId = context.mapId or context.worldSemantics.mapId,
          value = definition.value,
          feedingDuration = definition.feedingDuration,
          depletionTicks = definition.depletionTicks,
          provenance = definition.provenance
        }
        opportunity.key = key(opportunity.mapId, cell.x, cell.y, opportunityType)
        if FoodOpportunities.isAvailable(opportunity, tick) then
          results[#results + 1] = opportunity
        end
      end
    end
  end
  table.sort(results, function(left, right)
    if left.distance ~= right.distance then return left.distance < right.distance end
    return left.key < right.key
  end)
  return results
end

function FoodOpportunities.consume(opportunity, tick)
  if not FoodOpportunities.isAvailable(opportunity, tick) then return false end
  depletedUntil[opportunity.key] = (tick or 0) + (opportunity.depletionTicks or 0)
  return true
end

function FoodOpportunities.depletedUntil(opportunity)
  return opportunity and depletedUntil[opportunity.key] or nil
end

function FoodOpportunities.reset()
  depletedUntil = {}
end

function FoodOpportunities.definition(opportunityType)
  local definition = DEFINITIONS[opportunityType]
  if not definition then return nil end
  local result = {}
  for field, value in pairs(definition) do result[field] = value end
  return result
end

return FoodOpportunities
