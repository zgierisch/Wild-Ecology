local SpeciesEcology = require("src.species.species_ecology")
local WorldSemantics = require("src.world.world_semantics")

local RestSiteResolver = {}

local DEFAULT_RADIUS = 5
local MEANINGFUL_IMPROVEMENT = 12
local scanCount = 0

local function contains(values, wanted)
  for _, value in ipairs(values or {}) do
    if value == wanted then return true end
  end
  return false
end

local function distance(left, right)
  return math.max(math.abs(left.cellX - right.cellX),
    math.abs(left.cellY - right.cellY))
end

local function travelBudget(fatigue, radius)
  local value = math.max(0, math.min(1, fatigue or 0))
  if value >= 0.9 then return 0 end
  if value >= 0.8 then return math.min(1, radius) end
  if value >= 0.7 then return math.min(2, radius) end
  return math.min(4, radius)
end

local function candidateFor(profile, semantics, position, origin)
  local cell = WorldSemantics.cellAt(semantics, position.cellX, position.cellY)
  local semanticType = cell.terrain
  if semanticType ~= "TALL_GRASS" then return nil end
  if not WorldSemantics.isLandingAllowed(semantics,
    position.cellX, position.cellY, "WALK") then return nil end
  local concealmentPossible = contains(profile.concealmentSites, semanticType)
  if not concealmentPossible then return nil end
  local candidateDistance = distance(origin, position)
  return {
    mapId = semantics.mapId,
    cellX = position.cellX,
    cellY = position.cellY,
    semanticType = semanticType,
    preferenceScore = 40,
    concealmentPossible = concealmentPossible,
    concealmentKind = concealmentPossible and semanticType or nil,
    distance = candidateDistance,
    score = 40 - candidateDistance * 5
  }
end

local function better(left, right)
  if left.score ~= right.score then return left.score > right.score end
  if left.distance ~= right.distance then return left.distance < right.distance end
  if left.cellY ~= right.cellY then return left.cellY < right.cellY end
  return left.cellX < right.cellX
end

function RestSiteResolver.travelBudget(fatigue, radius)
  return travelBudget(fatigue, radius or DEFAULT_RADIUS)
end

function RestSiteResolver.evaluate(entity, semantics, origin, fatigue, options)
  scanCount = scanCount + 1
  if not semantics or not origin then
    return { candidates = {}, selected = nil, travelBudget = 0 }
  end
  local settings = options or {}
  local radius = math.max(0, math.min(DEFAULT_RADIUS,
    settings.radius or DEFAULT_RADIUS))
  local budget = travelBudget(fatigue, radius)
  local profile = SpeciesEcology.getResolved(entity and entity.species)
  local candidates = {}
  for cellY = math.max(0, origin.cellY - radius),
    math.min((semantics.height or 1) - 1, origin.cellY + radius) do
    for cellX = math.max(0, origin.cellX - radius),
      math.min((semantics.width or 1) - 1, origin.cellX + radius) do
      local candidate = candidateFor(profile, semantics,
        { cellX = cellX, cellY = cellY }, origin)
      local candidateKey = WorldSemantics.cellKey(cellX, cellY)
      if candidate and candidate.distance <= budget
        and not (settings.excludedCells and settings.excludedCells[candidateKey]) then
        candidates[#candidates + 1] = candidate
      end
    end
  end
  table.sort(candidates, better)
  local current = nil
  for _, candidate in ipairs(candidates) do
    if candidate.distance == 0 then current = candidate break end
  end
  local selected = candidates[1]
  if current and selected
    and selected.score < current.score + MEANINGFUL_IMPROVEMENT then
    selected = current
  end
  return {
    candidates = candidates,
    selected = selected,
    current = current,
    travelBudget = budget,
    searchRadius = radius
  }
end

function RestSiteResolver.getScanCount()
  return scanCount
end

function RestSiteResolver.resetScanCount()
  scanCount = 0
end

return RestSiteResolver