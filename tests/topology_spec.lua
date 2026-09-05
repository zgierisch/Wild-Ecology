local EngineTopology = require("src.world.engine_topology")
local NavigationPlanner = require("src.navigation.navigation_planner")
local SpawnCells = require("src.world.spawn_cells")
local WalkableCells = require("src.world.walkable_cells")
local WorldSemantics = require("src.world.world_semantics")
local WorldTopology = require("src.world.world_topology")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function mapFor(definition, rows)
	local map = {
		id = definition.id,
		def = definition,
		widthCells = #(rows[1] or ""),
		heightCells = #rows
	}
	function map:isWalkableCell(x, y)
		local row = rows[y + 1] or ""
		return row:sub(x + 1, x + 1) == "."
	end
	return map
end

local MapModule = {
	isOutdoor = function(definition)
		if definition.outdoor ~= nil then
			return definition.outdoor
		end
		return definition.tileset == "OVERWORLD"
	end,
	defPassable = function(definition, _, x, y, surfing)
		return surfing == false
			and definition.passable ~= nil
			and definition.passable[x .. ":" .. y] == true
	end
}

local function runtimeFor(definition, rows, destinations)
	local maps = { [definition.id] = definition }
	local tilesets = { OVERWORLD = {}, HOUSE = {}, CAVERN = {} }
	for id, destination in pairs(destinations or {}) do
		maps[id] = destination
	end
	return {
		overworld = { map = mapFor(definition, rows) },
		data = { maps = maps, tilesets = tilesets }
	}
end

local function overviewFor(definition, rows)
	return {
		mapId = definition.id,
		width = #(rows[1] or ""),
		height = #rows,
		rows = rows
	}
end

local walker = { ecology = { locomotion = { WALK = true } } }

local missingGameProbe = EngineTopology.probeFromMod({ world = { game = {} } }, "PROBE_MAP")
assertEquals(missingGameProbe.modGame, false, "topology probe should report the production mod.game input")
assertEquals(missingGameProbe.worldGame, true, "topology probe should separately expose the facade's retained game")
assertEquals(missingGameProbe.topologyReason, "MOD_GAME_MISSING", "topology probe should name a missing production game")

local missingDefProbe = EngineTopology.probeRuntime({
	overworld = { map = { id = "PROBE_MAP" } },
	data = { maps = {}, tilesets = {} }
}, "PROBE_MAP", MapModule)
assertEquals(missingDefProbe.topologyReason, "MAP_DEF_MISSING", "topology probe should name a missing runtime map definition")

local mismatchProbe = EngineTopology.probeRuntime({
	overworld = { map = { id = "OTHER_MAP", def = {} } },
	data = { maps = {}, tilesets = {} }
}, "PROBE_MAP", MapModule)
assertEquals(mismatchProbe.topologyReason, "MAP_ID_MISMATCH", "topology probe should distinguish an active-map mismatch")

local northRows = { "  .   ", "  .   ", "  .   ", "  .   " }
local northDef = {
	id = "GENERIC_NORTH",
	tileset = "OVERWORLD",
	width = 3,
	height = 2,
	connections = { north = { map = "NORTH_DESTINATION", offset = 0 } },
	warps = {}
}
local northRuntime = runtimeFor(northDef, northRows, {
	NORTH_DESTINATION = {
		id = "NORTH_DESTINATION",
		tileset = "OVERWORLD",
		width = 3,
		height = 2,
		passable = { ["2:3"] = true }
	}
})
local northTopology = EngineTopology.fromRuntime(northRuntime, northDef.id, MapModule)
local northProbe = EngineTopology.probeRuntime(northRuntime, northDef.id, MapModule)
assertEquals(northProbe.topologyStatus, "READY", "complete runtime inputs should produce ready topology")
assertEquals(northProbe.topologyReason, "READY", "ready topology should have an explicit reason")
assertEquals(northProbe.topologyMapId, northDef.id, "topology probe should report the constructed map")
local northConnection = northTopology.connections[1]
assertEquals(northTopology.environmentClass, "OUTDOOR", "stock outdoor mechanics should classify arbitrary maps")
assertEquals(northTopology.width, 6, "topology should copy current map width")
assertEquals(northTopology.height, 4, "topology should copy current map height")
assertEquals(#northConnection.sourceCells, 6, "north connections should retain every current boundary cell")
assertEquals(#northConnection.usableSourceCells, 1, "north connections should expose only valid WALK landing pairs as usable")
assertEquals(northConnection.usableSourceCells[1].cellX, 2, "north source geometry should be derived from the current map")
assertEquals(northConnection.usableSourceCells[1].destinationY, 3, "north connections should land on the destination south edge")
assertEquals(northConnection.destinationWidth, 6, "topology should retain destination width for extension validation")
assertEquals(northConnection.destinationHeight, 4, "topology should retain destination height for extension validation")
local northSemantics = WorldSemantics.fromOverview(overviewFor(northDef, northRows), nil, northTopology)
assertEquals(WorldSemantics.transitionAt(northSemantics, 2, 0).kind, "OVERWORLD_EXIT", "usable north cells should become generic overworld exits")
local transitionReason, transitionSpawn = SpawnCells.assess(walker, northSemantics, { cellX = 2, cellY = 0 })
assertEquals(transitionSpawn.inBounds, true, "zero-based y=0 should be inside the map")
assertEquals(transitionSpawn.overviewCell, ".", "overview lookup should translate zero-based cells to Lua string indices")
assertEquals(WorldSemantics.cellAt(northSemantics, 2, 0).walkable, true, "connection sources should remain traversable ground")
assertEquals(WorldSemantics.isLandingAllowed(northSemantics, 2, 0, "WALK"), true, "connection sources should remain valid WALK landings")
assertEquals(transitionReason, "NON_SPAWNABLE_CELL", "connection sources should be rejected before connectivity")
assertEquals(transitionSpawn.spawnClass, "TRANSITION", "connection sources should carry explicit transition spawn semantics")
assertEquals(transitionSpawn.spawnAllowed, false, "connection sources should not be default wild spawn habitat")
assertEquals(transitionSpawn.spawnRestrictionReason, "OVERWORLD_CONNECTION_SOURCE", "connection sources should explain their spawn restriction")
assertEquals(transitionSpawn.reachableOverworldExit, nil, "non-spawnable cells should fail before connectivity")
local throughConnection = NavigationPlanner.plan(walker, northSemantics, { cellX = 2, cellY = 1 }, {
	kind = "POSITION",
	destination = { cellX = 2, cellY = 0 }
}, { maxDepth = 1, allowedModes = { WALK = true } })
assertEquals(throughConnection.reachedGoal, true, "navigation should still route an existing actor onto a connection source")
local ordinaryReason, ordinarySpawn = SpawnCells.assess(walker, northSemantics, { cellX = 2, cellY = 1 })
assertEquals(ordinaryReason, "VALID", "ordinary connected ground should remain eligible")
assertEquals(ordinarySpawn.spawnClass, "HABITAT", "ordinary connected ground should be habitat")
assertEquals(ordinarySpawn.spawnAllowed, true, "ordinary connected ground should remain spawnable")
for _, outside in ipairs({
	{ cellX = -1, cellY = 0 },
	{ cellX = 0, cellY = -1 },
	{ cellX = northSemantics.width, cellY = 0 },
	{ cellX = 0, cellY = northSemantics.height }
}) do
	local reason, details = SpawnCells.assess(walker, northSemantics, outside)
	assertEquals(reason, "OUT_OF_BOUNDS", "coordinates outside [0,width)x[0,height) should be rejected")
	assertEquals(details.isLandingAllowed, false, "bounds rejection should happen before landing/connectivity")
	assertEquals(details.reachableOverworldExit, nil, "bounds rejection should happen before exit reachability")
end
local invalidLandingReason, invalidLanding = SpawnCells.assess(walker, northSemantics, { cellX = 0, cellY = 1 })
assertEquals(invalidLandingReason, "INVALID_PERSISTED_CELL", "blocked in-bounds ground should fail landing validation")
assertEquals(invalidLanding.reachableOverworldExit, nil, "invalid landing should fail before connectivity")

WalkableCells.clearCache("GENERIC_NORTH")
local candidates = WalkableCells.computeForMap({
	world = { mapOverview = function() return overviewFor(northDef, northRows) end }
}, "GENERIC_NORTH")
local includesConnectionSource = false
for _, candidate in ipairs(candidates or {}) do
	if candidate.x == 2 and candidate.y == 0 then includesConnectionSource = true end
end
assertEquals(includesConnectionSource, true, "current candidate generation includes '.' connection-source boundary cells")
assertEquals(WorldSemantics.isConnectionSource(northSemantics, 2, 0), true, "semantics should identify connection-source candidates diagnostically")
assertEquals(WorldSemantics.isUsableConnectionSource(northSemantics, 2, 0), true, "semantics should distinguish usable connection sources")

local originalMapModuleForSelection = package.loaded["src.world.Map"]
package.loaded["src.world.Map"] = MapModule
WorldSemantics.clearCache("GENERIC_NORTH")
WalkableCells.clearCache("GENERIC_NORTH")
local selectionMod = {
	game = northRuntime,
	world = {
		current = function() return { mapId = "GENERIC_NORTH", x = 2, y = 1 } end,
		mapOverview = function() return overviewFor(northDef, northRows) end
	}
}
local selectionSemantics = WorldSemantics.fromMod(selectionMod, "GENERIC_NORTH")
local selectionProbe = WorldSemantics.probeFromMod(selectionMod, "GENERIC_NORTH")
assertEquals(selectionProbe.mapOverviewStatus, "OK", "complete public raster input should be ready")
assertEquals(selectionProbe.topologyStatus, "READY", "complete private topology inputs should be ready")
assertEquals(selectionProbe.semanticsStatus, "READY", "complete world inputs should produce ready semantics")
local spawnableCandidates = WalkableCells.computeSpawnableForMap(selectionMod, "GENERIC_NORTH", selectionSemantics)
assertEquals(spawnableCandidates[1].y, 1, "spawn candidate generation should exclude connection sources before selection")
local northAnalysis = SpawnCells.analyzeCandidates(selectionMod, "GENERIC_NORTH", walker, selectionSemantics)
assertEquals(northAnalysis.rawWalkable, 4, "Route-shaped diagnostics should count every raw walkable cell")
assertEquals(northAnalysis.landingValid, 4, "ordinary Route-shaped walkable cells should remain valid landings")
assertEquals(northAnalysis.spawnSemanticAllowed, 3, "only the usable connection source should fail static spawn semantics")
assertEquals(northAnalysis.connectionSourceRejected, 1, "connection-source rejection should be counted separately")
assertEquals(northAnalysis.connectivityAccepted, 3, "ordinary ground connected to an overworld exit should remain eligible")
assertEquals(northAnalysis.finalCandidateCount, 3, "the Route-shaped fixture should retain all connected ordinary ground")
local selected = SpawnCells.pickCell("GENERIC_NORTH", "default", {}, nil, selectionMod, walker)
assertEquals(selected.y, 1, "new spawn selection should skip a connection source before checking connectivity")
package.loaded["src.world.Map"] = originalMapModuleForSelection
WorldSemantics.clearCache("GENERIC_NORTH")
WalkableCells.clearCache("GENERIC_NORTH")

local eastRows = {
	"      ", "      ", "      ", "      ",
	"      ", "......", "      ", "      "
}
local eastDef = {
	id = "GENERIC_EAST_OFFSET",
	tileset = "OVERWORLD",
	width = 3,
	height = 4,
	connections = { east = { map = "EAST_DESTINATION", offset = 1 } },
	warps = {}
}
local eastRuntime = runtimeFor(eastDef, eastRows, {
	EAST_DESTINATION = {
		id = "EAST_DESTINATION",
		tileset = "OVERWORLD",
		width = 2,
		height = 4,
		passable = { ["0:3"] = true }
	}
})
local eastTopology = EngineTopology.fromRuntime(eastRuntime, eastDef.id, MapModule)
local eastUsable = eastTopology.connections[1].usableSourceCells[1]
assertEquals(eastTopology.connections[1].offset, 1, "nonzero stock offsets should be preserved")
assertEquals(eastUsable.cellX, 5, "east source cells should lie on the current east boundary")
assertEquals(eastUsable.cellY, 5, "east source row should remain in current-map coordinates")
assertEquals(eastUsable.destinationX, 0, "east connections should land on the destination west edge")
assertEquals(eastUsable.destinationY, 3, "east landing should subtract twice the block offset")

for _, case in ipairs({
	{ direction = "north", source = { cellX = 1, cellY = 0 } },
	{ direction = "south", source = { cellX = 1, cellY = 3 } },
	{ direction = "west", source = { cellX = 0, cellY = 1 } },
	{ direction = "east", source = { cellX = 3, cellY = 1 } }
}) do
	local semantics = WorldSemantics.fromOverview({
		mapId = "DIRECTION_" .. case.direction,
		width = 4,
		height = 4,
		rows = { "....", "....", "....", "...." }
	}, nil, {
		environmentClass = "OUTDOOR",
		connections = { {
			direction = case.direction,
			destinationMapId = "DESTINATION",
			sourceCells = { case.source },
			usableSourceCells = { case.source }
		} },
		warps = {}
	})
	local spawn = WorldSemantics.spawnSemanticsAt(semantics, case.source.cellX, case.source.cellY, walker)
	assertEquals(spawn.spawnAllowed, false, case.direction .. " connection source should be excluded generically")
	assertEquals(spawn.spawnRestrictionReason, "OVERWORLD_CONNECTION_SOURCE", case.direction .. " source should use the generic reason")
end

local multipleRows = {
	".     ",
	"      ",
	"      ",
	"      ",
	"  ....",
	"      "
}
local multipleDef = {
	id = "GENERIC_MULTIPLE",
	tileset = "OVERWORLD",
	width = 3,
	height = 3,
	connections = {
		north = { map = "MULTI_NORTH", offset = 0 },
		east = { map = "MULTI_EAST", offset = 0 }
	},
	warps = {}
}
local multipleRuntime = runtimeFor(multipleDef, multipleRows, {
	MULTI_NORTH = { id = "MULTI_NORTH", tileset = "OVERWORLD", width = 3, height = 2, passable = { ["0:3"] = true } },
	MULTI_EAST = { id = "MULTI_EAST", tileset = "OVERWORLD", width = 2, height = 3, passable = { ["0:4"] = true } }
})
local multipleTopology = EngineTopology.fromRuntime(multipleRuntime, multipleDef.id, MapModule)
local multipleSemantics = WorldSemantics.fromOverview(overviewFor(multipleDef, multipleRows), nil, multipleTopology)
assertEquals(#multipleSemantics.connections, 2, "all stock connections should remain available to shared semantics")
assertEquals(NavigationPlanner.isSpawnViable(walker, multipleSemantics, { cellX = 2, cellY = 4 }), true, "reaching any usable connection should satisfy outdoor spawn viability")

local warpOnlyRows = { "....", "...." }
local warpOnlyDef = {
	id = "GENERIC_WARP_ONLY",
	tileset = "OVERWORLD",
	width = 2,
	height = 1,
	connections = {},
	warps = {
		{ x = 1, y = 0, destMap = "HOUSE_ONE", destWarp = 1 },
		{ x = 2, y = 0, destMap = "HOUSE_TWO", destWarp = 2 }
	}
}
local warpOnlyTopology = EngineTopology.fromRuntime(runtimeFor(warpOnlyDef, warpOnlyRows), warpOnlyDef.id, MapModule)
local warpOnlySemantics = WorldSemantics.fromOverview(overviewFor(warpOnlyDef, warpOnlyRows), nil, warpOnlyTopology)
assertEquals(#warpOnlySemantics.warps, 2, "all stock warps should be copied independently of connections")
assertEquals(WorldSemantics.transitionAt(warpOnlySemantics, 1, 0).kind, "MAP_WARP", "generic warps should remain non-exit transitions")
assertEquals(NavigationPlanner.isSpawnViable(walker, warpOnlySemantics, { cellX = 0, cellY = 0 }), false, "warps alone must not satisfy outdoor connectivity")

local indoorDef = {
	id = "GENERIC_INTERIOR",
	tileset = "HOUSE",
	width = 2,
	height = 1,
	connections = {},
	warps = {}
}
local indoorRows = { "....", "...." }
local indoorTopology = EngineTopology.fromRuntime(runtimeFor(indoorDef, indoorRows), indoorDef.id, MapModule)
local indoorSemantics = WorldSemantics.fromOverview(overviewFor(indoorDef, indoorRows), nil, indoorTopology)
assertEquals(indoorSemantics.environmentClass, "NON_OUTDOOR", "stock non-outdoor maps should be classified without registry entries")
assertEquals(NavigationPlanner.isSpawnViable(walker, indoorSemantics, { cellX = 0, cellY = 0 }), true, "non-outdoor maps should skip connection validation")
assertEquals(SpawnCells.assess(walker, indoorSemantics, { cellX = 4, cellY = 0 }), "OUT_OF_BOUNDS", "non-outdoor maps should still enforce bounds")

local caveSemantics = WorldSemantics.fromOverview(
	overviewFor(warpOnlyDef, warpOnlyRows),
	{ mapKind = "CAVE" },
	warpOnlyTopology
)
assertEquals(caveSemantics.environmentClass, "NON_OUTDOOR", "an explicit cave annotation should suppress stock outdoor classification")
assertEquals(NavigationPlanner.isSpawnViable(walker, caveSemantics, { cellX = 0, cellY = 0 }), true, "explicit caves should skip outdoor connection validation")
assertEquals(SpawnCells.assess(walker, caveSemantics, { cellX = -1, cellY = 0 }), "OUT_OF_BOUNDS", "cave override should not bypass bounds")
local restrictedCave = WorldSemantics.fromOverview({ mapId = "RESTRICTED_CAVE", width = 1, height = 1, rows = { "." } }, {
	mapKind = "CAVE",
	cells = { [WorldSemantics.cellKey(0, 0)] = {
		kind = "GROUND", walkable = true, validLanding = true,
		spawnClass = "NON_HABITAT", spawnAllowed = false,
		spawnRestrictionReason = "NON_HABITAT"
	} }
})
assertEquals(SpawnCells.assess(walker, restrictedCave, { cellX = 0, cellY = 0 }), "NON_SPAWNABLE_CELL", "caves should skip exit connectivity but still enforce spawn semantics")

local unresolvedDef = {
	id = "GENERIC_UNRESOLVED",
	tileset = "OVERWORLD",
	width = 2,
	height = 1,
	connections = { north = { map = "MISSING_DESTINATION", offset = -2 } },
	warps = {}
}
local unresolvedRows = { "....", "...." }
local unresolvedTopology = EngineTopology.fromRuntime(runtimeFor(unresolvedDef, unresolvedRows), unresolvedDef.id, MapModule)
assertEquals(#unresolvedTopology.connections, 1, "unresolved stock connections should remain represented")
assertEquals(unresolvedTopology.connections[1].resolved, false, "unresolved destinations should be marked conservatively")
assertEquals(#unresolvedTopology.connections[1].usableSourceCells, 0, "unresolved destinations must expose no guessed usable cells")
local unresolvedSemantics = WorldSemantics.fromOverview(overviewFor(unresolvedDef, unresolvedRows), nil, unresolvedTopology)
assertEquals(NavigationPlanner.isSpawnViable(walker, unresolvedSemantics, { cellX = 0, cellY = 0 }), false, "unresolved connections should not satisfy outdoor connectivity")
local unresolvedAnalysis = SpawnCells.analyzeCandidates(nil, unresolvedDef.id, walker, unresolvedSemantics)
assertEquals(unresolvedAnalysis.rawWalkable, 8, "unresolved outdoor diagnostics should retain the raw walkable count")
assertEquals(unresolvedAnalysis.spawnSemanticAllowed, 8, "unresolved topology should not make ordinary ground non-spawnable")
assertEquals(unresolvedAnalysis.connectivityAccepted, 0, "no usable overworld exit should accept no connected cells")
assertEquals(unresolvedAnalysis.connectivityRejected, 0, "exit connectivity should not run without an active player component")
assertEquals(unresolvedAnalysis.spawnRejectedOutsidePlayableComponent, 8, "candidate analysis should reject cells when the player component is unavailable")
assertEquals(unresolvedAnalysis.finalCandidateCount, 0, "an outdoor map without usable exits should have no final candidates")
assertEquals(unresolvedAnalysis.stockConnectionCount, 1, "diagnostics should retain authored stock connections")
assertEquals(unresolvedAnalysis.resolvedConnectionCount, 0, "diagnostics should expose unresolved stock connections")
assertEquals(unresolvedAnalysis.usableOverworldExitCount, 0, "diagnostics should expose the absence of usable exits")
assertEquals(unresolvedAnalysis.result, "NO_SPAWN_CANDIDATES", "empty connectivity should be diagnosed explicitly")

local connectionOnlySemantics = WorldSemantics.fromOverview({
	mapId = "CONNECTION_ONLY", width = 1, height = 1, rows = { "." }
}, nil, {
	environmentClass = "OUTDOOR",
	connections = { {
		direction = "north", destinationMapId = "DESTINATION", resolved = true,
		sourceCells = { { cellX = 0, cellY = 0 } },
		usableSourceCells = { { cellX = 0, cellY = 0 } }
	} },
	warps = {}
})
local connectionOnlyAnalysis = SpawnCells.analyzeCandidates(nil, "CONNECTION_ONLY", walker, connectionOnlySemantics)
assertEquals(connectionOnlyAnalysis.rawWalkable, 1, "connection-only maps should retain their raw walkable count")
assertEquals(connectionOnlyAnalysis.spawnSemanticAllowed, 0, "a usable connection source should not become habitat")
assertEquals(connectionOnlyAnalysis.connectionSourceRejected, 1, "connection-only rejection should be attributed to transition semantics")
assertEquals(connectionOnlyAnalysis.finalCandidateCount, 0, "connection-only maps must not fall back to invalid spawn cells")

local liveRows = {}
for _ = 1, 36 do liveRows[#liveRows + 1] = string.rep(".", 20) end
local liveSource = { cellX = 4, cellY = 35 }
local liveSemantics = WorldSemantics.fromOverview({
	mapId = "ROUTE_1_LIVE_SHAPE", width = 20, height = 36, rows = liveRows
}, nil, {
	environmentClass = "OUTDOOR",
	connections = { {
		direction = "south", destinationMapId = "PALLET_TOWN", resolved = true,
		sourceCells = { liveSource }, usableSourceCells = { liveSource }
	} },
	warps = {}
})
local liveAnalysis = SpawnCells.analyzeCandidates({
	world = { current = function() return { mapId = "ROUTE_1_LIVE_SHAPE", x = 10, y = 10 } end }
}, "ROUTE_1_LIVE_SHAPE", walker, liveSemantics)
local liveFinalKeys = {}
for _, candidate in ipairs(liveAnalysis.finalCandidates) do
	liveFinalKeys[candidate.x .. ":" .. candidate.y] = true
end
local liveTransition = WorldSemantics.spawnSemanticsAt(liveSemantics, 4, 35, walker)
local knownConnection = WorldTopology.classifyTransition(liveSemantics,
	{ cellX = 4, cellY = 35 }, { cellX = 4, cellY = 36 })
assertEquals(knownConnection.status, "KNOWN_VALID_CONNECTION",
	"the known Route 1 south edge should remain distinguishable from hard bounds")
assertEquals(knownConnection.destinationMapId, "PALLET_TOWN",
	"the known Route 1 edge should expose its stock destination map")
assertEquals(knownConnection.executionStatus,
	"KNOWN_CONNECTION_BUT_NOT_EXECUTABLE",
	"topology discovery must not pretend cross-map avatar transfer is implemented")
local hardBoundary = WorldTopology.classifyTransition(liveSemantics,
	{ cellX = 19, cellY = 35 }, { cellX = 19, cellY = 36 })
assertEquals(hardBoundary.status, "HARD_BOUNDARY",
	"an arbitrary adjacent out-of-bounds cell must remain a hard boundary")
local palletTransitions = WorldTopology.transitionsTo(liveSemantics, "PALLET_TOWN")
assertEquals(#palletTransitions, 1,
	"topology should enumerate only authored usable connections to a destination")
assertEquals(palletTransitions[1].source.cellX, 4,
	"topology should retain the exact source exit region")
assertEquals(liveTransition.spawnAllowed, false, "known live connection source (4,35) should remain non-spawnable")
assertEquals(liveTransition.spawnClass, "TRANSITION", "known live connection source should be a transition")
assertEquals(liveFinalKeys["4:35"], nil, "known live connection source should be absent from final candidates")
for _, cell in ipairs({ { 19, 3 }, { 19, 26 }, { 19, 33 } }) do
	local x, y = cell[1], cell[2]
	local spawn = WorldSemantics.spawnSemanticsAt(liveSemantics, x, y, walker)
	assertEquals(WorldSemantics.isUsableConnectionSource(liveSemantics, x, y), false, "known ordinary live cell should not overmatch connection membership")
	assertEquals(spawn.spawnAllowed, true, "known ordinary live cell should remain spawnable")
	assertEquals(spawn.spawnClass, "HABITAT", "known ordinary live cell should remain habitat")
	assertEquals(liveFinalKeys[x .. ":" .. y], true, "known ordinary live cell should literally survive final candidate filtering")
end
for _, cell in ipairs({ { 4, 34 }, { 3, 35 }, { 4, 3 }, { 19, 35 } }) do
	assertEquals(
		WorldSemantics.spawnSemanticsAt(liveSemantics, cell[1], cell[2], walker).spawnAllowed,
		true,
		"same-axis and adjacent ordinary cells should not overmatch connection-source membership"
	)
end

local originalMapModule = package.loaded["src.world.Map"]
package.loaded["src.world.Map"] = MapModule
local activeDefinition = northDef
local activeRows = northRows
local activeRuntime = northRuntime
local overviewCalls = 0
local mod = {
	game = activeRuntime,
	world = {
		current = function()
			if activeDefinition.id == northDef.id then
				return { mapId = activeDefinition.id, x = 2, y = 1 }
			end
			return { mapId = activeDefinition.id, x = 1, y = 0 }
		end,
		mapOverview = function()
			overviewCalls = overviewCalls + 1
			return overviewFor(activeDefinition, activeRows)
		end
	}
}
WorldSemantics.clearCache()
local mapASemantics = WorldSemantics.fromMod(mod, northDef.id)
local mapASemanticsAgain = WorldSemantics.fromMod(mod, northDef.id)
assertEquals(mapASemanticsAgain, mapASemantics, "spawn and behavior callers should share one current-map semantics instance")
assertEquals(overviewCalls, 1, "cached current-map semantics should not rebuild mapOverview for every caller")
local originalEvaluateAdjacent = require("src.navigation.traversal_evaluator").evaluateAdjacent
local traversalChecks = 0
require("src.navigation.traversal_evaluator").evaluateAdjacent = function(...)
	traversalChecks = traversalChecks + 1
	return originalEvaluateAdjacent(...)
end
assertEquals(NavigationPlanner.isSpawnViable(walker, mapASemantics, { cellX = 2, cellY = 3 }), true, "shared current-map semantics should drive spawn connectivity")
local firstTraversalChecks = traversalChecks
assertEquals(NavigationPlanner.isSpawnViable(walker, mapASemantics, { cellX = 2, cellY = 2 }), true, "another cell in the same component should reuse cached viability")
assertEquals(traversalChecks, firstTraversalChecks, "spawn viability should flood the current map only once per semantics instance")
local seekRoute = NavigationPlanner.plan(walker, mapASemantics, { cellX = 2, cellY = 3 }, {
	kind = "DIRECTIONAL_REGION",
	source = "flock_search",
	direction = "NORTH"
}, { maxDepth = 2, allowedModes = { WALK = true } })
assertEquals(seekRoute.actions[1].direction, "UP", "the same current-map semantics should drive SEEK_FLOCK navigation")
require("src.navigation.traversal_evaluator").evaluateAdjacent = originalEvaluateAdjacent
local mapAAnalysis = SpawnCells.analyzeCandidates(mod, northDef.id, walker, mapASemantics)
activeDefinition = indoorDef
activeRows = indoorRows
activeRuntime.overworld.map = mapFor(indoorDef, indoorRows)
activeRuntime.data.maps[indoorDef.id] = indoorDef
local mapBSemantics = WorldSemantics.fromMod(mod, indoorDef.id)
assertEquals(mapASemantics.mapId, "GENERIC_NORTH", "map A should build from its current runtime definition")
assertEquals(mapBSemantics.mapId, "GENERIC_INTERIOR", "map B should rebuild from its new current runtime definition")
assertEquals(mapBSemantics.environmentClass, "NON_OUTDOOR", "map B must not retain map A outdoor classification")
assertEquals(#mapBSemantics.connections, 0, "map B must not retain map A connections")
assertEquals(WorldSemantics.transitionAt(mapBSemantics, 2, 0), nil, "map B must not retain map A transitions")
assertEquals(WorldSemantics.isSpawnAllowed(mapASemantics, 2, 0, walker), false, "map A should retain its connection-source spawn restriction")
assertEquals(WorldSemantics.isSpawnAllowed(mapBSemantics, 1, 0, walker), true, "map B should rebuild ordinary habitat semantics")
local mapBAnalysis = SpawnCells.analyzeCandidates(mod, indoorDef.id, walker, mapBSemantics)
assertEquals(mapAAnalysis.finalCandidateCount, 3, "map A candidate analysis should remain scoped to map A semantics")
assertEquals(mapBAnalysis.finalCandidateCount, 8, "map changes should build candidates from the new semantics rows")
assertEquals(mapAAnalysis.semantics ~= mapBAnalysis.semantics, true, "map changes must not reuse another map's spawnable cache identity")

local readinessRows = { ".", "." }
local readinessDef = {
	id = "READINESS_ROUTE",
	tileset = "OVERWORLD",
	width = 1,
	height = 1,
	connections = { north = { map = "LATE_DESTINATION", offset = 0 } },
	warps = {}
}
local readinessRuntime = runtimeFor(readinessDef, readinessRows)
local readinessMod = {
	game = readinessRuntime,
	world = {
		current = function() return { mapId = readinessDef.id, x = 0, y = 0 } end,
		mapOverview = function() return overviewFor(readinessDef, readinessRows) end
	}
}
WorldSemantics.clearCache()
local incompleteSemantics = WorldSemantics.fromMod(readinessMod, readinessDef.id)
local incompleteAnalysis = SpawnCells.analyzeCandidates(readinessMod, readinessDef.id, walker, incompleteSemantics)
assertEquals(incompleteAnalysis.finalCandidateCount, 0, "an unresolved early topology snapshot should conservatively produce no candidates")
readinessRuntime.data.maps.LATE_DESTINATION = {
	id = "LATE_DESTINATION", tileset = "OVERWORLD", width = 1, height = 1,
	passable = { ["0:1"] = true }
}
local completeSemantics = WorldSemantics.fromMod(readinessMod, readinessDef.id)
assertEquals(completeSemantics ~= incompleteSemantics, true, "same-map semantics should rebuild when connection resolution becomes ready")
local completeAnalysis = SpawnCells.analyzeCandidates(readinessMod, readinessDef.id, walker, completeSemantics)
assertEquals(completeAnalysis.usableOverworldExitCount, 1, "rebuilt semantics should expose the newly resolved overworld exit")
assertEquals(completeAnalysis.finalCandidateCount, 1, "an early empty spawn analysis must not survive a topology readiness change")
package.loaded["src.world.Map"] = originalMapModule
WorldSemantics.clearCache()