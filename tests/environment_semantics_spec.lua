local NavigationPlanner = require("src.navigation.navigation_planner")
local SpatialGoal = require("src.behavior.spatial_goal")
local WorldSemantics = require("src.world.world_semantics")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "assertEquals failed") .. ": expected "
      .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function block(c00, c10, c01, c11)
  local result = {}
  for index = 1, 16 do result[index] = 0 end
  result[5], result[7], result[13], result[15] = c00, c10, c01, c11
  return result
end

local function snapshot(tilesetId)
  local tileset = {
    grassTile = 82,
    walkable = { 10, 11, 20, 82 },
    blocks = { block(82, 10, 82, 11), block(20, 20, 20, 20) }
  }
  return {
    mapId = "SEMANTIC_FIXTURE",
    width = 4,
    height = 2,
    rows = { ". .~", "...." },
    mapDef = { id = "SEMANTIC_FIXTURE", tileset = tilesetId,
      width = 2, height = 1, blocks = { 0, 1 }, warps = {} },
    tilesetId = tilesetId,
    tileset = tileset,
    markers = {},
    ledges = {},
    tilePairs = { land = {}, water = {} },
    provenance = { overview = "TEST", map = "TEST", tileset = "TEST" }
  }
end

local semantics = assert(WorldSemantics.fromSnapshot(snapshot("OUTDOOR_A")))
assertEquals(WorldSemantics.describeCell(semantics, 0, 0).terrain,
  "TALL_GRASS", "grass tile should classify automatically")
assertEquals(WorldSemantics.describeCell(semantics, 2, 1).terrain,
  "OPEN_GROUND", "ordinary walkable terrain should remain generic")
assertEquals(WorldSemantics.describeCell(semantics, 3, 0).terrain,
  "WATER", "overview water should classify automatically")

local waterEdge = WorldSemantics.describeEdge(semantics, 2, 0, "RIGHT")
assert(waterEdge, "expected water edge")
assertEquals(waterEdge.barrierKind, "WATER_BOUNDARY",
  "land-water interfaces should be derived edge semantics")
assertEquals(waterEdge.traversal.executable.WALK, false,
  "water boundaries must not become executable WALK edges")
assertEquals(WorldSemantics.describeContext(semantics, 2, 0).contextTags[1],
  "WATER_ADJACENT", "water edge should also be a land-cell context")

assertEquals(WorldSemantics.describeContext(semantics, 0, 0).grassRelation,
  "EDGE", "grass with a non-grass neighbor should be a grass edge")
assertEquals(WorldSemantics.describeContext(semantics, 1, 1).grassRelation,
  "ADJACENT", "outside ground should know it is adjacent to grass")

local unknown = WorldSemantics.describeEdge(semantics, 0, 0, "RIGHT")
assert(unknown, "expected blocked edge")
assertEquals(unknown.barrierKind, "UNKNOWN_BARRIER",
  "unclassified blocked geometry must remain unknown")

local fence = WorldSemantics.fromSnapshot(snapshot("OUTDOOR_A"), {
  tilesets = { OUTDOOR_A = { edges = {
    [WorldSemantics.tilePairKey(82, 10)] = { barrierKind = "FENCE" }
  } } }
})
assertEquals(WorldSemantics.describeEdge(fence, 0, 0, "RIGHT").barrierKind,
  "FENCE", "tileset tile-pair annotations should classify fences")
assertEquals(WorldSemantics.describeEdge(fence, 0, 0, "RIGHT")
  .traversal.future.SQUEEZE, "POSSIBLE_WITH_CAPABILITY",
  "fence semantics may describe future traversal without executing it")

local cliff = WorldSemantics.fromSnapshot(snapshot("OUTDOOR_A"), {
  tilesets = { OUTDOOR_A = { edges = {
    [WorldSemantics.tilePairKey(82, 10)] = { barrierKind = "FENCE" }
  } } },
  edges = { [WorldSemantics.edgeKey(0, 0, 1, 0)] = {
    barrierKind = "CLIFF", WALK = false
  } }
})
assertEquals(WorldSemantics.describeEdge(cliff, 0, 0, "RIGHT").barrierKind,
  "CLIFF", "map edge override should beat tileset annotation")

local scopedA = WorldSemantics.fromSnapshot(snapshot("OUTDOOR_A"), {
  tilesets = { OUTDOOR_A = { blocks = { [0] = { terrain = "PATH" } } } }
})
local scopedB = WorldSemantics.fromSnapshot(snapshot("OUTDOOR_B"), {
  tilesets = { OUTDOOR_B = { blocks = { [0] = { terrain = "SAND" } } } }
})
assertEquals(WorldSemantics.describeCell(scopedA, 0, 1).terrain, "PATH",
  "block semantics should be scoped by tileset")
assertEquals(WorldSemantics.describeCell(scopedB, 0, 1).terrain, "SAND",
  "the same block id may mean something else in another tileset")

local ledgeSnapshot = snapshot("OUTDOOR_A")
ledgeSnapshot.ledges = { { tileset = "OUTDOOR_A", facing = "right",
  input = "right", standingTile = 82, ledgeTile = 10 } }
local ledge = WorldSemantics.fromSnapshot(ledgeSnapshot)
assertEquals(WorldSemantics.describeEdge(ledge, 0, 0, "RIGHT").barrierKind,
  "LEDGE", "stock ledge rows should provide reliable directed evidence")

local boundary = WorldSemantics.describeEdge(semantics, 0, 0, "UP")
assert(boundary, "expected map boundary")
assertEquals(boundary.boundaryKind, "MAP_BOUNDARY",
  "unconnected bounds should remain hard map boundaries")
local connected = WorldSemantics.fromSnapshot(snapshot("OUTDOOR_A"), nil, {
  environmentClass = "OUTDOOR",
  connections = { { direction = "north", destinationMapId = "NEXT",
    sourceCells = { { cellX = 0, cellY = 0 } },
    usableSourceCells = { { cellX = 0, cellY = 0 } } } },
  warps = { { index = 1, cellX = 2, cellY = 1,
    destinationMapId = "HOUSE", destinationWarp = 1 } }
})
assertEquals(WorldSemantics.describeEdge(connected, 0, 0, "UP").topologyKind,
  "MAP_CONNECTION", "known connection should beat hard-boundary fallback")
assertEquals(WorldSemantics.transitionAt(connected, 2, 1).topologyKind,
  "WARP", "known warp should remain distinct from map connections")

local nearby = WorldSemantics.findNearbyFeature(
  semantics, { cellX = 1, cellY = 0 }, "WATER_ADJACENT", 2)
assertEquals(nearby[1].x, 2, "nearby feature query should return candidate cells")
assertEquals(nearby[1].y, 0, "nearby feature query should be deterministic")

local goal = SpatialGoal.position({ cellX = nearby[1].x, cellY = nearby[1].y }, {
  mapId = semantics.mapId, source = "ENVIRONMENTAL_FEATURE"
})
local route = NavigationPlanner.plan(
  { ecology = { locomotion = { WALK = true } } }, semantics,
  { cellX = 1, cellY = 1 }, goal,
  { allowedModes = { WALK = true } })
assert(route, "expected environmental route")
assertEquals(route.reachedGoal, true,
  "environmental candidates should use generic SpatialGoal and navigation")

WorldSemantics.describeCell(semantics, 0, 0)
WorldSemantics.describeCell(semantics, 0, 0)
local metrics = WorldSemantics.metricsSnapshot(semantics)
assertEquals(metrics.cellCacheHits > 0, true,
  "repeated semantic queries should hit the per-map static cache")
local inspection = WorldSemantics.inspect(semantics, 0, 0)
assertEquals(inspection:find("terrain=TALL_GRASS", 1, true) ~= nil, true,
  "explicit inspector should report structured cell semantics")
assertEquals(inspection:find("RIGHT=UNKNOWN_BARRIER", 1, true) ~= nil, true,
  "explicit inspector should report structured edge semantics")

return true