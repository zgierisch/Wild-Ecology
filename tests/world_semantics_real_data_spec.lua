local WorldSemantics = require("src.world.world_semantics")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "assertEquals failed") .. ": expected "
      .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function loadIfPresent(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  file:close()
  return assert(loadfile(path))()
end

local appData = os.getenv("APPDATA")
local cache = os.getenv("GEN1RECOMP_RED_CACHE")
  or (appData and appData .. "/pokemon-love2d/red")
if not cache then return true end

local maps = loadIfPresent(cache .. "/data/generated/maps.lua")
local tilesets = loadIfPresent(cache .. "/data/generated/tilesets.lua")
local field = loadIfPresent(cache .. "/data/generated/field.lua")
if not maps or not tilesets or not field then return true end

local function contains(values, expected)
  for _, value in ipairs(values or {}) do
    if value == expected then return true end
  end
  return false
end

local function cellTile(mapDef, tileset, cellX, cellY)
  local blockX, blockY = math.floor(cellX / 2), math.floor(cellY / 2)
  local blockId = mapDef.blocks[blockY * mapDef.width + blockX + 1]
  local block = tileset.blocks[blockId + 1]
  local tileX = (cellX % 2) * 2
  local tileY = (cellY % 2) * 2 + 1
  return block[tileY * 4 + tileX + 1]
end

local function isWater(tilesetId, tileId)
  if not contains(field.waterTilesets, tilesetId) then return false end
  return tileId == 0x14
    or tilesetId ~= "SHIP_PORT" and (tileId == 0x32 or tileId == 0x48)
end

local function warpSet(mapDef)
  local result = {}
  for _, warp in ipairs(mapDef.warps or {}) do
    result[warp.x .. ":" .. warp.y] = true
  end
  return result
end

local function snapshot(mapId)
  local mapDef = assert(maps[mapId], "missing real map " .. mapId)
  local tileset = assert(tilesets[mapDef.tileset],
    "missing real tileset " .. tostring(mapDef.tileset))
  local width, height = mapDef.width * 2, mapDef.height * 2
  local warps, rows = warpSet(mapDef), {}
  for cellY = 0, height - 1 do
    local characters = {}
    for cellX = 0, width - 1 do
      local tileId = cellTile(mapDef, tileset, cellX, cellY)
      local key = cellX .. ":" .. cellY
      characters[#characters + 1] = warps[key] and "+"
        or isWater(mapDef.tileset, tileId) and "~"
        or contains(tileset.walkable, tileId) and "." or " "
    end
    rows[#rows + 1] = table.concat(characters)
  end
  return {
    mapId = mapId,
    width = width,
    height = height,
    rows = rows,
    markers = {},
    mapDef = mapDef,
    tilesetId = mapDef.tileset,
    tileset = tileset,
    ledges = field.ledges,
    tilePairs = field.tilePairs,
    provenance = {
      overview = "GEN1RECOMP_CACHE_AUDIT",
      map = "GEN1RECOMP_CACHE_AUDIT",
      tileset = "GEN1RECOMP_CACHE_AUDIT",
      field = "GEN1RECOMP_CACHE_AUDIT"
    }
  }
end

local startedAt = os.clock()
local route22 = assert(WorldSemantics.fromSnapshot(snapshot("ROUTE_22")))
assertEquals(route22.width, 40, "Route 22 width should be block width x2")
assertEquals(route22.height, 18, "Route 22 height should be block height x2")
assertEquals(WorldSemantics.describeCell(route22, 28, 3).kind,
  "UNKNOWN_BARRIER", "known Route 22 cliff must fail closed")
for cellX = 28, 31 do
  for cellY = 4, 5 do
    assertEquals(WorldSemantics.describeCell(route22, cellX, cellY).walkable,
      true, "known Route 22 rival corridor must remain walkable")
  end
end

local grassCount, directedLedgeCount = 0, 0
for cellY = 0, route22.height - 1 do
  for cellX = 0, route22.width - 1 do
    if WorldSemantics.describeCell(route22, cellX, cellY).grass then
      grassCount = grassCount + 1
    end
    for _, direction in ipairs({ "UP", "DOWN", "LEFT", "RIGHT" }) do
      local edge = WorldSemantics.describeEdge(route22, cellX, cellY, direction)
      if edge and edge.barrierKind == "LEDGE" then
        directedLedgeCount = directedLedgeCount + 1
      end
    end
  end
end
assertEquals(grassCount > 0, true, "Route 22 should expose real grass tiles")
assertEquals(directedLedgeCount > 0, true,
  "Route 22 should expose directed ledges from stock field rows")

local route21 = assert(WorldSemantics.fromSnapshot(snapshot("ROUTE_21")))
assertEquals(WorldSemantics.describeCell(route21, 5, 0).terrain, "WATER",
  "known Route 21 seam cell should be water")

local pallet = assert(WorldSemantics.fromSnapshot(snapshot("PALLET_TOWN"), nil, {
  environmentClass = "OUTDOOR",
  connections = {
    { direction = "north", destinationMapId = "ROUTE_1",
      sourceCells = { { cellX = 10, cellY = 0 } },
      usableSourceCells = { { cellX = 10, cellY = 0 } } },
    { direction = "south", destinationMapId = "ROUTE_21",
      sourceCells = { { cellX = 5, cellY = 17 } },
      usableSourceCells = { { cellX = 5, cellY = 17 } } }
  },
  warps = {}
}))
assertEquals(WorldSemantics.describeCell(pallet, 2, 17).walkable, true,
  "Pallet south shore spit should remain walkable land")
assertEquals(WorldSemantics.describeEdge(pallet, 10, 0, "UP").topologyKind,
  "MAP_CONNECTION", "Pallet north should expose its Route 1 connection")

local tunnel = assert(WorldSemantics.fromSnapshot(snapshot("ROCK_TUNNEL_1F")))
local lab = assert(WorldSemantics.fromSnapshot(snapshot("OAKS_LAB")))
assertEquals(tunnel.mapKind, "CAVE", "Rock Tunnel should carry cave context")
assertEquals(tunnel.environmentClass, "NON_OUTDOOR",
  "Rock Tunnel should not be treated as outdoor habitat")
assertEquals(lab.mapKind, "INTERIOR", "Oak's Lab should carry interior context")
assertEquals(lab.environmentClass, "NON_OUTDOOR",
  "Oak's Lab should not be treated as outdoor habitat")

local before = WorldSemantics.metricsSnapshot(route22)
for pass = 1, 2 do
  for cellY = 0, route22.height - 1 do
    for cellX = 0, route22.width - 1 do
      WorldSemantics.describeContext(route22, cellX, cellY)
    end
  end
end
local after = WorldSemantics.metricsSnapshot(route22)
local addedQueries = after.cellQueries - before.cellQueries
local addedHits = after.cellCacheHits - before.cellCacheHits
assertEquals(addedQueries > 0 and addedHits / addedQueries > 0.95, true,
  "repeated whole-map context scans should overwhelmingly reuse cell cache")

if os.getenv("WORLD_SEMANTICS_AUDIT") == "1" then
  print(("world semantics audit: route22=%dx%d grass=%d ledges=%d "
    .. "repeatCacheHitRate=%.3f elapsedMs=%.2f"):format(
      route22.width, route22.height, grassCount, directedLedgeCount,
      addedHits / addedQueries, (os.clock() - startedAt) * 1000))
end

return true