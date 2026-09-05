local HomeArea = require("src.world.home_area")
local SpeciesEcology = require("src.species.species_ecology")

local HomeReturn = {}

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

function HomeReturn.evaluate(entity, position, mapId, context)
  local area = entity and entity.home and entity.home.area
  if not area or not position or area.mapId ~= mapId then
    return { available = false, score = 0, inside = false }
  end
  local settings = context or {}
  local profile = SpeciesEcology.getResolved(entity.species)
  local home = profile.home
  local distance = HomeArea.distance(entity, position, mapId)
  local inside = HomeArea.isInside(entity, position, mapId)
  local activationDistance = area.radius + home.roamingTolerance
  local currentReturn = entity.runtimeState
    and entity.runtimeState.state == "RETURN_HOME"
  local active = not inside and (currentReturn or distance > activationDistance)
  local independence = clamp(entity.rawStats and entity.rawStats.independence or 0.5, 0, 1)
  local boldness = clamp(entity.temperament and entity.temperament.boldness or 0.5, 0, 1)
  local individualAttachment = clamp(home.attachment
    * (1.15 - independence * 0.2 - boldness * 0.1), 0.5, 1.5)
  local outsidePressure = clamp((distance - activationDistance)
    / math.max(2, home.roamingTolerance + 2), 0, 1)
  local fatigue = clamp(settings.fatigue or 0, 0, 1)
  local travelCapacity = clamp((0.95 - fatigue) / 0.35, 0.12, 1)
  local circadianPressure = clamp(settings.circadianRestBias or 0, 0, 1)
  local score = active and clamp((outsidePressure * 48
    + circadianPressure * 22 + fatigue * 8) * individualAttachment
    * travelCapacity, 0, 90) or 0
  return {
    available = active,
    score = score,
    inside = inside,
    distance = distance,
    radius = area.radius,
    activationDistance = activationDistance,
    outsidePressure = outsidePressure,
    attachment = individualAttachment,
    circadianPressure = circadianPressure,
    travelCapacity = travelCapacity
  }
end

return HomeReturn