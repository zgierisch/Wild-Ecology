local WorldSemantics = require("src.world.world_semantics")

local HomeArea = {}

local MIN_RADIUS = 1
local MAX_RADIUS = 5

local function clamp(value, minimum, maximum)
  return math.max(minimum, math.min(maximum, value))
end

local function copyCell(cell)
  return cell and { cellX = cell.cellX, cellY = cell.cellY } or nil
end

local function distance(left, right)
  if not left or not right then return nil end
  return math.max(math.abs(left.cellX - right.cellX),
    math.abs(left.cellY - right.cellY))
end

local function legalCell(semantics, cell)
  return semantics ~= nil and cell ~= nil
    and WorldSemantics.isInside(semantics, cell.cellX, cell.cellY)
    and WorldSemantics.transitionAt(semantics, cell.cellX, cell.cellY) == nil
    and WorldSemantics.isLandingAllowed(semantics,
      cell.cellX, cell.cellY, "WALK")
end

function HomeArea.establish(entity, semantics, options)
  if not entity then return nil, "ENTITY_MISSING" end
  entity.home = entity.home or {}
  if entity.home.area ~= nil then return entity.home.area, "EXISTING" end
  local settings = options or {}
  local anchor = settings.anchorCell
  if not anchor and entity.home.spawnX ~= nil and entity.home.spawnY ~= nil then
    anchor = { cellX = entity.home.spawnX, cellY = entity.home.spawnY }
  end
  local mapId = settings.mapId or entity.home.mapId
  if not semantics or semantics.mapId ~= mapId then
    return nil, "SEMANTICS_MAP_MISMATCH"
  end
  if not legalCell(semantics, anchor) then return nil, "INVALID_ANCHOR" end
  entity.home.area = {
    mapId = mapId,
    anchorCell = copyCell(anchor),
    radius = clamp(math.floor(settings.radius or 2), MIN_RADIUS, MAX_RADIUS),
    establishedTick = settings.establishedTick or 0,
    provenance = settings.provenance or "PERSISTED_PLACEMENT"
  }
  return entity.home.area, "ESTABLISHED"
end

function HomeArea.position(entity, visiblePosition)
  local location = entity and entity.locationState
  if location and location.kind == "CONCEALED" then
    return copyCell(location.anchorCell), location.mapId
  end
  return copyCell(visiblePosition), visiblePosition and visiblePosition.mapId
end

function HomeArea.distance(entity, position, mapId)
  local area = entity and entity.home and entity.home.area
  if not area or not position or (mapId and area.mapId ~= mapId) then return nil end
  return distance(position, area.anchorCell)
end

function HomeArea.isInside(entity, position, mapId, margin)
  local area = entity and entity.home and entity.home.area
  local away = HomeArea.distance(entity, position, mapId)
  return away ~= nil and away <= math.max(0, area.radius + (margin or 0))
end

function HomeArea.selectDestination(entity, semantics, position)
  local area = entity and entity.home and entity.home.area
  if not area or not semantics or semantics.mapId ~= area.mapId or not position then
    return nil
  end
  local candidates = {}
  local radius = clamp(math.floor(area.radius or MIN_RADIUS), MIN_RADIUS, MAX_RADIUS)
  for cellY = math.max(0, area.anchorCell.cellY - radius),
    math.min((semantics.height or 1) - 1, area.anchorCell.cellY + radius) do
    for cellX = math.max(0, area.anchorCell.cellX - radius),
      math.min((semantics.width or 1) - 1, area.anchorCell.cellX + radius) do
      local candidate = { cellX = cellX, cellY = cellY }
      if legalCell(semantics, candidate)
        and distance(candidate, area.anchorCell) <= radius then
        candidate.distance = distance(candidate, position)
        candidates[#candidates + 1] = candidate
      end
    end
  end
  table.sort(candidates, function(left, right)
    if left.distance ~= right.distance then return left.distance < right.distance end
    if left.cellY ~= right.cellY then return left.cellY < right.cellY end
    return left.cellX < right.cellX
  end)
  local selected = candidates[1]
  if not selected then return nil end
  return {
    mapId = area.mapId,
    cellX = selected.cellX,
    cellY = selected.cellY,
    distance = selected.distance
  }
end

return HomeArea