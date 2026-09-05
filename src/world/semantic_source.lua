local SemanticSource = {}

local function registryGet(mod, registryName, id)
  local registry = mod and mod.content and mod.content[registryName]
  if not registry or type(registry.get) ~= "function" then return nil end
  local ok, value = pcall(registry.get, registry, id)
  return ok and value or nil
end

local function overviewFromMod(mod)
  local world = mod and mod.world
  if not world then return nil, "MOD_WORLD_MISSING" end
  if type(world.mapOverview) ~= "function" then
    return nil, "MAP_OVERVIEW_UNAVAILABLE"
  end
  local ok, overview = pcall(world.mapOverview, world)
  if not ok then return nil, "MAP_OVERVIEW_ERROR", tostring(overview) end
  if overview == nil then return nil, "MAP_OVERVIEW_NIL" end
  if type(overview) ~= "table" then
    return nil, "MAP_OVERVIEW_INVALID"
  end
  if overview.rows == nil then return nil, "MAP_OVERVIEW_ROWS_MISSING" end
  if type(overview.rows) ~= "table" then
    return nil, "MAP_OVERVIEW_ROWS_INVALID"
  end
  if overview.width ~= nil and type(overview.width) ~= "number" then
    return nil, "MAP_OVERVIEW_WIDTH_INVALID"
  end
  if overview.height ~= nil and type(overview.height) ~= "number" then
    return nil, "MAP_OVERVIEW_HEIGHT_INVALID"
  end
  for _, row in ipairs(overview.rows) do
    if type(row) ~= "string" then return nil, "MAP_OVERVIEW_ROWS_INVALID" end
  end
  return overview
end

local function blockIdAt(mapDef, cellX, cellY)
  if not mapDef or type(mapDef.blocks) ~= "table"
    or type(mapDef.width) ~= "number" then return nil end
  local blockX, blockY = math.floor(cellX / 2), math.floor(cellY / 2)
  if blockX < 0 or blockY < 0
    or blockX >= mapDef.width or blockY >= (mapDef.height or 0) then return nil end
  return mapDef.blocks[blockY * mapDef.width + blockX + 1]
end

local function tileIdAt(mapDef, tileset, cellX, cellY)
  local blockId = blockIdAt(mapDef, cellX, cellY)
  local block = blockId ~= nil and tileset and tileset.blocks
    and tileset.blocks[blockId + 1] or nil
  if type(block) ~= "table" then return nil end
  local tileX = (cellX % 2) * 2
  local tileY = (cellY % 2) * 2 + 1
  return block[tileY * 4 + tileX + 1]
end

local function fieldValue(mod, id)
  return registryGet(mod, "field", id)
end

local function contains(list, value)
  for _, item in ipairs(list or {}) do
    if item == value then return true end
  end
  return false
end

function SemanticSource.fromMod(mod, requestedMapId)
  local overview, reason, detail = overviewFromMod(mod)
  if not overview then return nil, reason, detail end
  local mapId = overview.mapId or requestedMapId
  if requestedMapId and mapId and requestedMapId ~= mapId then
    return nil, "MAP_OVERVIEW_MAP_ID_MISMATCH"
  end
  local mapDef = registryGet(mod, "maps", mapId)
  local tilesetId = mapDef and mapDef.tileset or nil
  local tileset = tilesetId and registryGet(mod, "tilesets", tilesetId) or nil
  return {
    mapId = mapId,
    width = overview.width or #(overview.rows[1] or ""),
    height = overview.height or #overview.rows,
    rows = overview.rows,
    markers = overview.markers or {},
    tileRows = overview.tileRows,
    tileDetailRows = overview.tileDetailRows,
    mapDef = mapDef,
    tilesetId = tilesetId,
    tileset = tileset,
    ledges = fieldValue(mod, "ledges") or {},
    tilePairs = fieldValue(mod, "tilePairs") or { land = {}, water = {} },
    provenance = {
      overview = "mod.world:mapOverview",
      map = mapDef and "mod.content.maps:get" or "UNAVAILABLE",
      tileset = tileset and "mod.content.tilesets:get" or "UNAVAILABLE",
      field = mod and mod.content and mod.content.field
        and "mod.content.field:get" or "UNAVAILABLE"
    }
  }
end

function SemanticSource.cell(snapshot, cellX, cellY)
  if not snapshot or cellX < 0 or cellY < 0
    or cellX >= (snapshot.width or 0) or cellY >= (snapshot.height or 0) then
    return nil
  end
  local row = snapshot.rows[cellY + 1] or ""
  local collisionClass = row:sub(cellX + 1, cellX + 1)
  local blockId = blockIdAt(snapshot.mapDef, cellX, cellY)
  local tileId = tileIdAt(snapshot.mapDef, snapshot.tileset, cellX, cellY)
  local tileWalkable = tileId ~= nil and snapshot.tileset
    and contains(snapshot.tileset.walkable, tileId) or false
  return {
    collisionClass = collisionClass,
    walkable = collisionClass == ".",
    water = collisionClass == "~",
    warp = collisionClass == "+",
    blocked = collisionClass == " ",
    tilesetId = snapshot.tilesetId,
    blockId = blockId,
    tileId = tileId,
    walkableByPlayer = collisionClass == "."
      or collisionClass == "+" and tileWalkable,
    grass = tileId ~= nil and snapshot.tileset
      and snapshot.tileset.grassTile == tileId or false
  }
end

return SemanticSource