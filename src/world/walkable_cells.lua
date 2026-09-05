-- Computes the REAL set of walkable, non-water, non-warp cells for the
-- currently active map via the documented public mod.world:mapOverview()
-- API (docs/modding.md "Read-only map overviews"), instead of relying on a
-- small hand-authored coordinate box (Config.phase3.routeSpawnCells).
-- mapOverview().rows encodes one character per cell: "+"=warp, "~"=water,
-- "."=walkable, " "=blocked -- verified against src/world/MapOverview.lua
-- and tests/engine/world_map_overview_test.lua in the gen1recomp source.
-- Only walkable cells with no encounter-tile semantics assumed (this mod
-- treats spawn/home cells as "somewhere a wild Pokemon can stand", not
-- specifically "grass" -- real wild battles remain vanilla's own system).
local WorldSemantics = require("src.world.world_semantics")

local WalkableCells = {}

local cache = {}
local spawnableAnalysisCache = setmetatable({}, { __mode = "k" })

-- mapOverview() only answers for the CURRENTLY ACTIVE overworld map (same
-- contract as mod.world:current()), so this only produces real data once
-- the player has actually entered that map. Cached per mapId so the O(w*h)
-- scan only ever runs once per map, not once per tick.
function WalkableCells.computeForMap(mod, mapId)
  if mapId and cache[mapId] then
    return cache[mapId]
  end

  local world = mod and mod.world
  if not world or not world.mapOverview then
    return nil
  end

  local ok, overview = pcall(function() return world:mapOverview() end)
  if not ok or not overview or not overview.rows then
    return nil
  end
  if mapId and overview.mapId and overview.mapId ~= mapId then
    return nil
  end

  local cells = {}
  local height = overview.height or #overview.rows
  for y = 0, height - 1 do
    local row = overview.rows[y + 1]
    if row then
      local width = overview.width or #row
      for x = 0, width - 1 do
        if row:sub(x + 1, x + 1) == "." then
          cells[#cells + 1] = { x = x, y = y }
        end
      end
    end
  end

  if #cells == 0 then
    return nil
  end

  if mapId then
    cache[mapId] = cells
  end
  return cells
end

function WalkableCells.analyzeSpawnableForMap(mod, mapId, semantics)
  if not semantics then
    return nil
  end
  local cached = spawnableAnalysisCache[semantics]
  if cached then
    return cached
  end
  local walkable = {}
  local spawnable = {}
  local analysis = {
    mapId = mapId or semantics.mapId,
    semantics = semantics,
    rawWalkable = 0,
    landingValid = 0,
    landingRejected = 0,
    spawnSemanticAllowed = 0,
    spawnSemanticRejected = 0,
    connectionSourceRejected = 0,
    rawCells = walkable,
    spawnableCells = spawnable
  }
  for y = 0, (semantics.height or 0) - 1 do
    local row = semantics.rows[y + 1] or ""
    for x = 0, (semantics.width or 0) - 1 do
      if row:sub(x + 1, x + 1) == "." then
        local cell = { x = x, y = y }
        walkable[#walkable + 1] = cell
        analysis.rawWalkable = analysis.rawWalkable + 1
        if WorldSemantics.isLandingAllowed(semantics, x, y, "WALK") then
          analysis.landingValid = analysis.landingValid + 1
          if WorldSemantics.isSpawnAllowed(semantics, x, y) then
            spawnable[#spawnable + 1] = cell
            analysis.spawnSemanticAllowed = analysis.spawnSemanticAllowed + 1
          else
            analysis.spawnSemanticRejected = analysis.spawnSemanticRejected + 1
            if WorldSemantics.isUsableConnectionSource(semantics, x, y) then
              analysis.connectionSourceRejected = analysis.connectionSourceRejected + 1
            end
          end
        else
          analysis.landingRejected = analysis.landingRejected + 1
        end
      end
    end
  end
  spawnableAnalysisCache[semantics] = analysis
  return analysis
end

function WalkableCells.computeSpawnableForMap(mod, mapId, semantics)
  local analysis = WalkableCells.analyzeSpawnableForMap(mod, mapId, semantics)
  if analysis then
    return analysis.spawnableCells
  end
  return WalkableCells.computeForMap(mod, mapId)
end

function WalkableCells.clearCache(mapId)
  if mapId then
    cache[mapId] = nil
  else
    cache = {}
  end
  spawnableAnalysisCache = setmetatable({}, { __mode = "k" })
end

return WalkableCells
