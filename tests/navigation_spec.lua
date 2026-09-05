local NavigationGoal = require("src.navigation.navigation_goal")
local NavigationPlanner = require("src.navigation.navigation_planner")
local NavigationExecution = require("src.navigation.navigation_execution")
local SpawnCells = require("src.world.spawn_cells")
local TraversalCapabilities = require("src.navigation.traversal_capabilities")
local TraversalEvaluator = require("src.navigation.traversal_evaluator")
local WorldSemantics = require("src.world.world_semantics")
local PlayableComponent = require("src.world.playable_component")
local MovementClaims = require("src.world.movement_claims")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function routeSignature(route)
	local parts = {}
	for _, action in ipairs(route and route.actions or {}) do
		parts[#parts + 1] = table.concat({ action.mode, action.direction, action.destination.cellX, action.destination.cellY }, ":")
	end
	return table.concat(parts, "|")
end

local open = WorldSemantics.fromOverview({
	mapId = "TEST",
	width = 7,
	height = 5,
	rows = {
		".......",
		".......",
		".......",
		".......",
		"......."
	}
})
local seeker = {
	id = "seeker",
	ecology = { locomotion = { WALK = true } },
	relationships = {}
}
local eastGoal = NavigationGoal.fromFlockSearch({
	cueSource = "social_signal",
	cueDirection = "EAST",
	targetEntityId = "hidden-family",
	cuePosition = { cellX = 99, cellY = 99 }
})
assertEquals(eastGoal.kind, "DIRECTIONAL_REGION", "social signals should become directional regions")
assertEquals(eastGoal.destination, nil, "directional goals must not expose unseen coordinates")
local eastRoute = NavigationPlanner.plan(seeker, open, { cellX = 1, cellY = 2 }, eastGoal, {
	maxDepth = 4,
	allowedModes = { WALK = true }
})
assertEquals(eastRoute.waypoint.cellX > 1, true, "open EAST planning should choose an eastward frontier")
assertEquals(eastRoute.actions[1].direction, "RIGHT", "open EAST planning should initially advance east")
assertEquals(eastRoute.actions[1].source.cellX, 1, "planned actions should record their expected source")

local wall = WorldSemantics.fromOverview({
	mapId = "WALL",
	width = 7,
	height = 5,
	rows = {
		".......",
		".......",
		".. ....",
		".......",
		"......."
	}
})
local aroundWall = NavigationPlanner.plan(seeker, wall, { cellX = 1, cellY = 2 }, eastGoal, {
	maxDepth = 6,
	allowedModes = { WALK = true }
})
assertEquals(aroundWall.actions[1].direction == "UP" or aroundWall.actions[1].direction == "DOWN", true, "wall routing may initially move perpendicular to an EAST cue")
assertEquals(aroundWall.waypoint.cellX > 2, true, "wall route should ultimately make eastward progress")
local claimedDetour = MovementClaims.new()
local claimedAction = aroundWall.actions[1]
claimedDetour:publish({
	actorId = "incumbent",
	fromX = claimedAction.destination.cellX + (claimedAction.direction == "UP" and -1 or 1),
	fromY = claimedAction.destination.cellY,
	toX = claimedAction.destination.cellX,
	toY = claimedAction.destination.cellY
}, 1)
local claimAwareRoute = NavigationPlanner.plan(seeker, wall, { cellX = 1, cellY = 2 }, eastGoal, {
	maxDepth = 6,
	allowedModes = { WALK = true },
	movementClaims = claimedDetour
})
assertEquals(claimAwareRoute.actions[1].direction == claimedAction.direction, false,
	"generic navigation should prefer an equivalent unclaimed first step")
assertEquals(claimAwareRoute.actions[#claimAwareRoute.actions].destination.cellX > 2, true,
	"one-step claim cost must not reserve or forbid the future route")

local rememberedPosition = { cellX = 5, cellY = 3 }
local lastSeenGoal = NavigationGoal.fromFlockSearch({
	cueSource = "last_seen",
	targetEntityId = "remembered-family",
	cuePosition = rememberedPosition
})
rememberedPosition.cellX = 6
assertEquals(lastSeenGoal.destination.cellX, 5, "last-known navigation destinations should be frozen copies")
local lastSeenRoute = NavigationPlanner.plan(seeker, open, { cellX = 1, cellY = 3 }, lastSeenGoal, {
	maxDepth = 6,
	allowedModes = { WALK = true }
})
assertEquals(lastSeenRoute.waypoint.cellX, 5, "planner should route toward the cached last-known position")
assertEquals(lastSeenRoute.reachedGoal, true, "a route ending at its requested position should report goal completion")
local perceivedGoal = NavigationGoal.fromFlockSearch({
	cueSource = "perceived",
	targetEntityId = "visible-family",
	cuePosition = { cellX = 5, cellY = 3 }
})
assertEquals(perceivedGoal.kind, "PROXIMITY", "currently perceived peers should use a proximity goal")
local perceivedRoute = NavigationPlanner.plan(seeker, open, { cellX = 1, cellY = 3 }, perceivedGoal, {
	maxDepth = 6,
	allowedModes = { WALK = true }
})
assertEquals(perceivedRoute.waypoint.cellX, 4, "proximity navigation should stop adjacent to the observed peer")
assertEquals(perceivedRoute.reachedGoal, true, "adjacency should satisfy a perceived-peer goal")
local partialRoute = NavigationPlanner.plan(seeker, open, { cellX = 0, cellY = 0 }, {
	kind = "POSITION",
	source = "test",
	destination = { cellX = 6, cellY = 0 }
}, { maxDepth = 3, allowedModes = { WALK = true } })
assertEquals(partialRoute.reachedGoal, false, "a bounded frontier route must not claim the goal was reached")

local repeatRoute = NavigationPlanner.plan(seeker, wall, { cellX = 1, cellY = 2 }, eastGoal, {
	maxDepth = 6,
	allowedModes = { WALK = true }
})
assertEquals(routeSignature(repeatRoute), routeSignature(aroundWall), "same static state and cue should produce the same route")
assertEquals(seeker.memory, nil, "planning must not create perception events")
assertEquals(next(seeker.relationships), nil, "planning must not create relationships")

local special = WorldSemantics.fromOverview({
	mapId = "SPECIAL",
	width = 5,
	height = 3,
	rows = { ".....", ". ...", "....." }
}, {
	cells = {
		[WorldSemantics.cellKey(1, 1)] = {
			kind = "SPECIAL_LANDING",
			walkable = false,
			validLanding = false,
			landingModes = { FLY = true, SQUEEZE = true, CLIMB = true }
		}
	},
	edges = {
		[WorldSemantics.edgeKey(0, 1, 1, 1)] = { FLY = true },
		[WorldSemantics.edgeKey(2, 1, 1, 1)] = { SQUEEZE = true },
		[WorldSemantics.edgeKey(1, 0, 1, 1)] = { CLIMB = true }
	}
})
local sourceLeft = { cellX = 0, cellY = 1 }
local barrier = { cellX = 1, cellY = 1 }
assertEquals(TraversalEvaluator.evaluateAdjacent(seeker, special, sourceLeft, barrier).legal, false, "WALK-only entities cannot cross special barriers")
local flyer = { ecology = { locomotion = { WALK = true, FLY = true } } }
assertEquals(TraversalEvaluator.evaluateAdjacent(flyer, special, sourceLeft, barrier).mode, "FLY", "FLY requires an explicitly flyable edge")
local squeezer = { ecology = { locomotion = { WALK = true, SQUEEZE = true } } }
assertEquals(TraversalEvaluator.evaluateAdjacent(squeezer, special, { cellX = 2, cellY = 1 }, barrier).mode, "SQUEEZE", "SQUEEZE requires an explicitly compatible edge")
assertEquals(TraversalEvaluator.evaluateAdjacent(squeezer, wall, { cellX = 1, cellY = 2 }, { cellX = 2, cellY = 2 }).legal, false, "SQUEEZE must not cross an arbitrary solid wall")
local climber = { ecology = { locomotion = { WALK = true, CLIMB = true } } }
assertEquals(TraversalEvaluator.evaluateAdjacent(climber, special, { cellX = 1, cellY = 0 }, barrier).mode, "CLIMB", "CLIMB requires an explicitly climbable edge")
assertEquals(TraversalEvaluator.evaluateAdjacent(flyer, special, { cellX = 0, cellY = 0 }, { cellX = -1, cellY = 0 }).legal, false, "FLY must not cross simulation boundaries")
local invalidSpecialLanding = WorldSemantics.fromOverview({
	mapId = "INVALID_SPECIAL",
	width = 2,
	height = 1,
	rows = { ". " }
}, {
	edges = { [WorldSemantics.edgeKey(0, 0, 1, 0)] = { FLY = true } }
})
assertEquals(TraversalEvaluator.evaluateAdjacent(flyer, invalidSpecialLanding, { cellX = 0, cellY = 0 }, { cellX = 1, cellY = 0 }).legal, false, "special traversal should reject an invalid landing")
local deniedWalk = WorldSemantics.fromOverview({ mapId = "DENIED", width = 2, height = 1, rows = { ".." } }, {
	edges = { [WorldSemantics.edgeKey(0, 0, 1, 0)] = { WALK = false } }
})
assertEquals(TraversalEvaluator.evaluateAdjacent(seeker, deniedWalk, { cellX = 0, cellY = 0 }, { cellX = 1, cellY = 0 }).legal, false, "WALK should honor explicit edge denial")

local teleporter = { ecology = { locomotion = { WALK = true, TELEPORT = { enabled = true, maxRange = 3, requiresLineOfSight = false } } } }
local teleport = TraversalEvaluator.evaluateTeleport(teleporter, special, { cellX = 0, cellY = 0 }, { cellX = 3, cellY = 0 })
assertEquals(teleport.legal, true, "TELEPORT should permit bounded non-adjacent traversal to a valid landing")
assertEquals(teleport.mode, "TELEPORT", "teleport traversal should produce a first-class action mode")
assertEquals(TraversalEvaluator.evaluateTeleport(teleporter, special, { cellX = 0, cellY = 0 }, barrier).legal, false, "TELEPORT should reject invalid landing cells")
assertEquals(TraversalEvaluator.evaluateTeleport(teleporter, special, { cellX = 0, cellY = 0 }, { cellX = 5, cellY = 0 }).legal, false, "TELEPORT should reject out-of-bounds destinations")
local teleportRoute = NavigationPlanner.plan(teleporter, special, { cellX = 0, cellY = 0 }, {
	kind = "POSITION",
	source = "test",
	destination = { cellX = 3, cellY = 0 }
}, {
	maxDepth = 1,
	allowedModes = { TELEPORT = true },
	executableModes = { TELEPORT = true }
})
assertEquals(teleportRoute.actions[1].mode, "TELEPORT", "planner routes should represent bounded TELEPORT as a non-adjacent action")
local occluded = WorldSemantics.fromOverview({ mapId = "OCCLUDED", width = 3, height = 1, rows = { ". ." } })
local sightTeleporter = { ecology = { locomotion = { TELEPORT = { enabled = true, maxRange = 3, requiresLineOfSight = true } } } }
assertEquals(TraversalEvaluator.evaluateTeleport(sightTeleporter, occluded, { cellX = 0, cellY = 0 }, { cellX = 2, cellY = 0 }).legal, false, "general semantic occlusion should block line-of-sight traversal")

local legacyPidgey = { species = "PIDGEY", ecology = {} }
assertEquals(TraversalCapabilities.forEntity(legacyPidgey).FLY, true, "old entities should inherit species locomotion defaults")
legacyPidgey.ecology.locomotion = { FLY = false }
assertEquals(TraversalCapabilities.forEntity(legacyPidgey).FLY, false, "entity locomotion should override species defaults")
assertEquals(TraversalCapabilities.executableModes().WALK, true, "WALK should be executable")
assertEquals(TraversalCapabilities.executableModes().FLY, nil, "special traversal should remain non-executable")

local sealed = WorldSemantics.fromOverview({
	mapId = "SEALED",
	width = 5,
	height = 3,
	rows = { "     ", " . . ", "     " }
})
assertEquals(NavigationPlanner.isSpawnViable(seeker, sealed, { cellX = 1, cellY = 1 }), true, "non-route maps should require only a valid spawn cell")
local cave = WorldSemantics.fromOverview({ mapId = "CAVE", width = 1, height = 1, rows = { "." } }, { mapKind = "CAVE" })
assertEquals(NavigationPlanner.isSpawnViable(seeker, cave, { cellX = 0, cellY = 0 }), true, "caves should be exempt from outdoor route-exit validation")
local routeWithoutExit = WorldSemantics.fromOverview({ mapId = "ROUTE", width = 3, height = 1, rows = { "..." } }, { environmentClass = "OUTDOOR" })
assertEquals(NavigationPlanner.isSpawnViable(teleporter, routeWithoutExit, { cellX = 0, cellY = 0 }), false, "special non-executable movement must not rescue a route without an exit")
local routeWithExit = WorldSemantics.fromOverview({ mapId = "ROUTE", width = 3, height = 1, rows = { "..." } }, {
	environmentClass = "OUTDOOR",
	transitions = { [WorldSemantics.cellKey(2, 0)] = { kind = "OVERWORLD_EXIT", destinationMapId = "NEXT_ROUTE" } }
})
assertEquals(NavigationPlanner.isSpawnViable(seeker, routeWithExit, { cellX = 0, cellY = 0 }), true, "outdoor route spawns should connect by WALK to an authoritative route exit")

local EngineTopology = require("src.world.engine_topology")
local Config = require("src.core.config")
local routeOneRows = {
	"      . ",
	"      . ",
	" .    . ",
	" .    . ",
	"      . ",
	"      . "
}
local routeOneDef = {
	id = "ROUTE_1",
	tileset = "OVERWORLD",
	width = 4,
	height = 3,
	connections = {
		north = { map = "VIRIDIAN_CITY", offset = 0 },
		south = { map = "PALLET_TOWN", offset = 0 }
	},
	warps = {
		{ x = 1, y = 2, destMap = "TEST_CAVE", destWarp = 1 },
		{ x = 1, y = 3, destMap = "TEST_INTERIOR", destWarp = 2 }
	}
}
local routeOneMap = {
	id = "ROUTE_1",
	def = routeOneDef,
	widthCells = 8,
	heightCells = 6
}
function routeOneMap:isWalkableCell(x, y)
	local row = routeOneRows[y + 1] or ""
	return row:sub(x + 1, x + 1) == "."
end
local runtime = {
	overworld = { map = routeOneMap },
	data = {
		maps = {
			ROUTE_1 = routeOneDef,
			VIRIDIAN_CITY = { id = "VIRIDIAN_CITY", tileset = "OVERWORLD", width = 4, height = 2, passable = { ["6:3"] = true } },
			PALLET_TOWN = { id = "PALLET_TOWN", tileset = "OVERWORLD", width = 4, height = 2, passable = { ["6:0"] = true } },
			TEST_CAVE = { id = "TEST_CAVE", tileset = "CAVERN", width = 2, height = 2 },
			TEST_INTERIOR = { id = "TEST_INTERIOR", tileset = "HOUSE", width = 2, height = 2 }
		},
		tilesets = { OVERWORLD = {}, CAVERN = {}, HOUSE = {} }
	}
}
local fakeMapModule = {
	isOutdoor = function(definition)
		return definition.outdoor ~= false and definition.tileset == "OVERWORLD"
	end,
	defPassable = function(definition, _, x, y, surfing)
		return surfing == false and definition.passable and definition.passable[x .. ":" .. y] == true
	end
}
local routeOneTopology = EngineTopology.fromRuntime(runtime, "ROUTE_1", fakeMapModule)
assertEquals(routeOneTopology.connections[1].direction, "north", "stock north connection should be copied from the active Route 1 definition")
assertEquals(#routeOneTopology.connections[1].sourceCells, 8, "all Route 1 north boundary cells should remain represented")
assertEquals(#routeOneTopology.connections[1].usableSourceCells, 1, "only source edge cells with WALK-passable stock landings should become exits")
assertEquals(routeOneTopology.connections[1].usableSourceCells[1].cellX, 6, "connection offset math should preserve the usable Route 1 exit column")
assertEquals(routeOneTopology.warps[1].destinationMapId, "TEST_CAVE", "stock warp destinations should be copied separately from edge connections")

Config.worldSemantics.TEST_CAVE = { mapKind = "CAVE" }
Config.worldSemantics.TEST_INTERIOR = { mapKind = "INTERIOR" }
local routeOneSemantics = WorldSemantics.fromOverview({
	mapId = "ROUTE_1",
	width = 8,
	height = 6,
	rows = routeOneRows
}, Config.worldSemantics.ROUTE_1, routeOneTopology)
assertEquals(routeOneSemantics.environmentClass, "OUTDOOR", "Route 1 should inherit broad outdoor status from stock map mechanics")
assertEquals(WorldSemantics.transitionAt(routeOneSemantics, 6, 0).kind, "OVERWORLD_EXIT", "a usable stock outdoor connection should become an OVERWORLD_EXIT")
local routeOneConnectionReason, routeOneConnectionSpawn = SpawnCells.assess(seeker, routeOneSemantics, { cellX = 6, cellY = 0 })
assertEquals(routeOneConnectionReason, "NON_SPAWNABLE_CELL", "a Route 1-shaped stock connection source should be rejected without coordinate hardcoding")
assertEquals(routeOneConnectionSpawn.spawnRestrictionReason, "OVERWORLD_CONNECTION_SOURCE", "Route 1-shaped rejection should come from generic topology")
assertEquals(WorldSemantics.transitionAt(routeOneSemantics, 1, 2).kind, "CAVE_ENTRANCE", "a stock warp to an explicitly classified cave should remain a cave entrance")
assertEquals(WorldSemantics.transitionAt(routeOneSemantics, 1, 3).kind, "BUILDING_ENTRANCE", "a stock warp to an explicitly classified interior should remain a building entrance")
assertEquals(NavigationPlanner.isSpawnViable(seeker, routeOneSemantics, { cellX = 6, cellY = 3 }), true, "a WALK-connected Route 1 spawn should pass")
assertEquals(NavigationPlanner.isSpawnViable(seeker, routeOneSemantics, { cellX = 1, cellY = 2 }), false, "a disconnected Route 1 pocket should fail despite reachable cave and building warps")

local originalMapModule = package.loaded["src.world.Map"]
package.loaded["src.world.Map"] = fakeMapModule
WorldSemantics.clearCache("ROUTE_1")
local routeOneMod = {
	game = runtime,
	world = {
		current = function()
			return { mapId = "ROUTE_1", x = 6, y = 3 }
		end,
		mapOverview = function()
			return { mapId = "ROUTE_1", width = 8, height = 6, rows = routeOneRows }
		end
	}
}
local routeOneAnalysis = SpawnCells.analyzeCandidates(routeOneMod, "ROUTE_1", seeker, routeOneSemantics)
assertEquals(routeOneAnalysis.rawWalkable, 8, "Route 1-shaped diagnostics should count every raw walkable cell")
assertEquals(routeOneAnalysis.landingValid, 8, "Route 1-shaped walkable cells should remain valid landings")
assertEquals(routeOneAnalysis.spawnSemanticAllowed, 6, "Route 1-shaped semantics should exclude only two usable connection sources")
assertEquals(routeOneAnalysis.connectionSourceRejected, 2, "Route 1-shaped diagnostics should count both stock connection sources")
assertEquals(routeOneAnalysis.connectivityAccepted, 4, "Route 1-shaped connectivity should retain the ordinary cells connected to an exit")
assertEquals(routeOneAnalysis.connectivityRejected, 0, "exit connectivity should be evaluated only inside the playable component")
assertEquals(routeOneAnalysis.spawnRejectedOutsidePlayableComponent, 2, "the player-anchored component should reject the isolated warp pocket")
assertEquals(routeOneAnalysis.finalCandidateCount, 4, "Route 1-shaped final candidates should remain non-empty")
assertEquals(routeOneAnalysis.stockConnectionCount, 2, "Route 1-shaped diagnostics should report both stock connections")
assertEquals(routeOneAnalysis.resolvedConnectionCount, 2, "Route 1-shaped diagnostics should report both resolved connections")
assertEquals(routeOneAnalysis.usableOverworldExitCount, 2, "Route 1-shaped diagnostics should report both usable exits")
local PopulationManager = require("src.population.manager")
local anchor = { id = Config.phase0.testEntityId, ecology = { locomotion = { WALK = true } }, home = { spawnX = 1, spawnY = 2 } }
local ordinary = { id = "ordinary", ecology = { locomotion = { WALK = true } }, home = { spawnX = 1, spawnY = 2 } }
assertEquals(PopulationManager.assessMaterialization(anchor, routeOneMod, "ROUTE_1"), "OUTSIDE_PLAYABLE_COMPONENT", "the phase-zero anchor should remain outside the player component")
assertEquals(PopulationManager.assessMaterialization(ordinary, routeOneMod, "ROUTE_1"), "OUTSIDE_PLAYABLE_COMPONENT", "ordinary entities should use the same player-anchored component")
ordinary.home.spawnX = 6
ordinary.home.spawnY = 0
local persistedReason, persistedDetails = PopulationManager.assessMaterialization(ordinary, routeOneMod, "ROUTE_1")
assertEquals(persistedReason, "NON_SPAWNABLE_CELL", "persisted entities on connection sources should fail materialization")
assertEquals(type(persistedDetails), "table", "persisted spawn rejection should include diagnostic details")
assertEquals(persistedDetails.spawnRestrictionReason, "OVERWORLD_CONNECTION_SOURCE", "persisted rejection should preserve the source coordinate and explain it")
assertEquals(ordinary.home.spawnX, 6, "persisted connection-source coordinates should not be rewritten")
assertEquals(ordinary.home.spawnY, 0, "persisted connection-source coordinates should remain unchanged")
package.loaded["src.world.Map"] = originalMapModule
Config.worldSemantics.TEST_CAVE = nil
Config.worldSemantics.TEST_INTERIOR = nil
WorldSemantics.clearCache("ROUTE_1")

local spawnOverview = {
	mapId = "SPAWN_NAV_TEST",
	width = 5,
	height = 3,
	rows = { "     ", " . ..", "     " }
}
local spawnSemantics = WorldSemantics.fromOverview(spawnOverview, {
	environmentClass = "OUTDOOR",
	transitions = { [WorldSemantics.cellKey(4, 1)] = { kind = "OVERWORLD_EXIT" } }
})
assertEquals(SpawnCells.assess(seeker, spawnSemantics, { x = 1, y = 1 }), "NO_TRAVERSABLE_EXIT", "persisted disconnected positions should be reported without relocation")
assertEquals(SpawnCells.assess(seeker, spawnSemantics, { x = 3, y = 1 }), "VALID", "positions connected to an authoritative route exit should remain valid")

local splitSemantics = WorldSemantics.fromOverview({
	mapId = "SPLIT_ROUTE",
	width = 5,
	height = 1,
	rows = { ".. .." }
}, {
	environmentClass = "OUTDOOR",
	transitions = {
		[WorldSemantics.cellKey(1, 0)] = { kind = "OVERWORLD_EXIT" },
		[WorldSemantics.cellKey(4, 0)] = { kind = "OVERWORLD_EXIT" }
	}
})
local splitMod = {
	world = {
		current = function()
			return { mapId = "SPLIT_ROUTE", x = 0, y = 0 }
		end,
		mapOverview = function()
			return { mapId = "SPLIT_ROUTE", width = 5, height = 1, rows = { ".. .." } }
		end
	}
}
local splitAnalysis = SpawnCells.analyzeCandidates(splitMod, "SPLIT_ROUTE", seeker, splitSemantics)
assertEquals(splitAnalysis.walkComponentCount, 2, "solid terrain should split structural WALK components")
assertEquals(splitAnalysis.playableComponentCells, 2, "the player cell should anchor the active structural component")
assertEquals(splitAnalysis.exitConnectedComponentCount, 2, "both disconnected components should retain their own exit diagnostics")
assertEquals(splitAnalysis.spawnRejectedOutsidePlayableComponent, 2, "an independently exit-connected decorative component should still be rejected")
assertEquals(splitAnalysis.finalCandidateCount, 2, "only spawnable ground in the player's component should survive")
local outsideReason = SpawnCells.assess(seeker, splitSemantics, { x = 3, y = 0 }, splitMod, "SPLIT_ROUTE")
assertEquals(outsideReason, "OUTSIDE_PLAYABLE_COMPONENT", "persisted homes outside the active component should not materialize")

local oneWaySemantics = WorldSemantics.fromOverview({
	mapId = "ONE_WAY_COMPONENT",
	width = 3,
	height = 1,
	rows = { "..." }
}, {
	environmentClass = "OUTDOOR",
	edges = {
		[WorldSemantics.edgeKey(1, 0, 0, 0)] = { WALK = false }
	},
	transitions = {
		[WorldSemantics.cellKey(2, 0)] = { kind = "OVERWORLD_EXIT" }
	}
})
local playerX = 0
local oneWayMod = {
	world = {
		current = function()
			return { mapId = "ONE_WAY_COMPONENT", x = playerX, y = 0 }
		end,
		npcs = { { x = 1, y = 0 } }
	}
}
local buildsBefore = PlayableComponent.getBuildCount()
local oneWayAtStart = PlayableComponent.inspect(oneWayMod, "ONE_WAY_COMPONENT", oneWaySemantics)
assertEquals(oneWayAtStart.componentCount, 1, "a one-way WALK edge should not split the structural component")
assertEquals(oneWayAtStart.playableCells, 3, "dynamic NPC occupancy should not split the static WALK component")
playerX = 2
local oneWayAfterMove = PlayableComponent.inspect(oneWayMod, "ONE_WAY_COMPONENT", oneWaySemantics)
assertEquals(oneWayAfterMove.buildNumber, oneWayAtStart.buildNumber, "moving inside a component should reuse its cached classification")
assertEquals(PlayableComponent.getBuildCount(), buildsBefore + 1, "one semantics object should build structural components only once")
local regeneratedSemantics = WorldSemantics.fromOverview({
	mapId = "ONE_WAY_COMPONENT",
	width = 3,
	height = 1,
	rows = { "..." }
}, { environmentClass = "OUTDOOR" })
PlayableComponent.inspect(oneWayMod, "ONE_WAY_COMPONENT", regeneratedSemantics)
assertEquals(PlayableComponent.getBuildCount(), buildsBefore + 2, "a replacement semantics generation should rebuild structural components")

local Controller = require("src.behavior.controller")
local routedSeeker = {
	id = "routed-seeker",
	species = "PIDGEY",
	ecology = { family = "B", socialModifier = 1.5, locomotion = { WALK = true } },
	rawStats = { independence = 0.1 },
	temperament = { sociability = 0.9, curiosity = 0 },
	relationships = {}
}
local routedContext = {
	position = { cellX = 1, cellY = 2 },
	mapId = "WALL",
	worldSemantics = wall,
	flockSearch = {
		utility = 100,
		isolationPressure = 1,
		nearbySameSpecies = 0,
		cueSource = "social_signal",
		cueDirection = "EAST",
		targetEntityId = "hidden-family"
	}
}
assertEquals(Controller.tick(routedSeeker, {}, nil, routedContext, 400), "SEEK_FLOCK", "SEEK_FLOCK should consume the directional planner goal")
assertEquals(routedSeeker.runtimeState.movementRequest.direction, "UP", "controller should execute the first wall-detour route action")
routedSeeker.runtimeState.movementRequest.rejectionReason = "object"
Controller.tick(routedSeeker, {}, nil, routedContext, 401)
assertEquals(routedSeeker.runtimeState.navigation.replanReason, "EXECUTION_REJECTED", "authoritative rejection should invalidate the stale route")
assertEquals(routedSeeker.runtimeState.movementRequest.direction, "DOWN", "replanning should avoid the rejected edge")
routedSeeker.runtimeState.motion = { justCompleted = true }
routedContext.position = {
	cellX = routedSeeker.runtimeState.movementRequest.destinationX,
	cellY = routedSeeker.runtimeState.movementRequest.destinationY
}
Controller.tick(routedSeeker, {}, nil, routedContext, 402)
assertEquals(routedSeeker.runtimeState.navigation.replanReason == "EXECUTION_REJECTED", false,
	"a successful WALK should clear stale execution-rejection diagnostics")

local waitingSeeker = {
	id = "waiting-seeker",
	species = "PIDGEY",
	ecology = { family = "B", socialModifier = 1.5, locomotion = { WALK = true } },
	rawStats = { independence = 0.1 },
	temperament = { sociability = 0.9, curiosity = 0 },
	relationships = {},
	runtimeState = { state = "SEEK_FLOCK", stateEnteredTick = 0 }
}
local waitingContext = {
	executionOnly = true,
	position = { cellX = 1, cellY = 2 },
	mapId = "WALL",
	worldSemantics = wall,
	occupiedCells = {},
	occupancyDetails = {},
	movementClaims = MovementClaims.new(),
	flockSearch = {
		utility = 100,
		isolationPressure = 1,
		nearbySameSpecies = 0,
		cueSource = "social_signal",
		cueDirection = "EAST",
		targetEntityId = "hidden-family"
	}
}
Controller.executeCurrentIntent(waitingSeeker, waitingContext, 410)
local waitingRoute = waitingSeeker.runtimeState.navigation.route
local waitingAction = waitingRoute.actions[waitingRoute.index]
local waitingKey = WorldSemantics.cellKey(
	waitingAction.destination.cellX, waitingAction.destination.cellY)
waitingContext.occupiedCells[waitingKey] = true
waitingContext.occupancyDetails[waitingKey] = {
	currentOccupants = {
		blocker = {
			entityId = "blocker",
			position = {
				cellX = waitingAction.destination.cellX,
				cellY = waitingAction.destination.cellY
			},
			moving = true,
			motionStartedTick = 411,
			destination = { cellX = 2, cellY = 2 }
		}
	},
	destinationReservations = {
		reserver = {
			entityId = "reserver",
			moving = true,
			motionStartedTick = 405,
			destination = {
			cellX = waitingAction.destination.cellX,
			cellY = waitingAction.destination.cellY
			}
		}
	}
}
local occupancyDiagnostic = nil
NavigationExecution.setDiagnosticSink(function(event)
	occupancyDiagnostic = event
end)
Controller.executeCurrentIntent(waitingSeeker, waitingContext, 411)
NavigationExecution.setDiagnosticSink(nil)
assertEquals(occupancyDiagnostic.layer, "PLANNER_OCCUPANCY",
	"route suspension should identify planner occupancy as the deciding layer")
assertEquals(occupancyDiagnostic.occupancy,
	waitingContext.occupancyDetails[waitingKey],
	"planner occupancy diagnostics should retain the exact deciding evidence")
assertEquals(waitingSeeker.runtimeState.navigation.route, waitingRoute,
	"SEEK_FLOCK should suspend rather than mirror-replan around transient occupancy")
assertEquals(waitingSeeker.runtimeState.movementRequest, nil,
	"suspended SEEK_FLOCK should not emit a locomotion request")
assertEquals(waitingSeeker.runtimeState.navigation.blockerCurrentOccupantId, "blocker",
	"route suspension should retain current occupant identity")
assertEquals(waitingSeeker.runtimeState.navigation.blockerReservationOwnerId, "reserver",
	"route suspension should independently retain reservation ownership")
assertEquals(waitingSeeker.runtimeState.navigation.occupancyReason,
	"DESTINATION_RESERVATION", "the conflicting reservation should identify the preventing claim")
assertEquals(waitingSeeker.runtimeState.navigation.blockedSinceTick, 411,
	"route suspension should begin an elapsed-tick clock")
assertEquals(waitingSeeker.runtimeState.navigation.blockAgeTicks, 0,
	"the first blocked frame should have zero elapsed age")
waitingContext.occupancyDetails[waitingKey].destinationReservations = {}
Controller.executeCurrentIntent(waitingSeeker, waitingContext, 450)
assertEquals(waitingSeeker.runtimeState.navigation.route, waitingRoute,
	"a current occupant moving away should retain the route until observed clearance")
assertEquals(waitingSeeker.runtimeState.navigation.occupancyReason, "MOVING_AWAY_OCCUPANT",
	"moving-away lifecycle evidence should own the wait instead of elapsed animation frames")
assertEquals(waitingContext.movementClaims:snapshot().vacatingCellWaits, 1,
	"vacating-cell waits should be counted once on category transition")
assertEquals(waitingSeeker.runtimeState.movementRequest, nil,
	"moving-away blocker grace should remain pure execution state")
waitingContext.occupiedCells = {}
waitingContext.occupancyDetails = {}
Controller.executeCurrentIntent(waitingSeeker, waitingContext, 451)
assertEquals(waitingSeeker.runtimeState.navigation.route, waitingRoute,
	"cleared SEEK_FLOCK occupancy should resume the same route")
assertEquals(waitingSeeker.runtimeState.movementRequest.direction, waitingAction.direction,
	"cleared SEEK_FLOCK occupancy should continue the original action")

waitingContext.occupiedCells = { [waitingKey] = true }
waitingContext.occupancyDetails = {}
Controller.executeCurrentIntent(waitingSeeker, waitingContext, 500)
assertEquals(waitingSeeker.runtimeState.navigation.occupancyReason, "STALE_OCCUPANCY_STATE",
	"boolean occupancy without provenance should use the stale-state category")
Controller.executeCurrentIntent(waitingSeeker, waitingContext, 679)
assertEquals(waitingSeeker.runtimeState.navigation.route, waitingRoute,
	"stale-state watchdog should not borrow the stock 32-frame duration")
Controller.executeCurrentIntent(waitingSeeker, waitingContext, 680)
assertEquals(waitingSeeker.runtimeState.navigation.releaseReason, "STALE_OCCUPANCY_STATE",
	"only the simulation-domain watchdog should release missing occupancy provenance")
waitingContext.occupiedCells = {}
waitingContext.occupancyDetails = {}

local immortalSeeker = {
	id = "persistent-seeker",
	species = "PIDGEY",
	ecology = { family = "B", socialModifier = 1.5, locomotion = { WALK = true } },
	rawStats = { independence = 0.1 },
	temperament = { sociability = 0.9, curiosity = 0 },
	relationships = {},
	runtimeState = { state = "SEEK_FLOCK", stateEnteredTick = 0 }
}
local immortalContext = {
	executionOnly = true,
	position = { cellX = 3, cellY = 3 },
	mapId = "TEST",
	worldSemantics = open,
	occupiedCells = {},
	occupancyDetails = {},
	flockSearch = {
		utility = 100,
		nearbySameSpecies = 0,
		cueSource = "social_signal",
		cueDirection = "EAST",
		targetEntityId = "hidden-family"
	}
}
Controller.executeCurrentIntent(immortalSeeker, immortalContext, 500)
local cycleTick = 501
for failure = 1, 3 do
	local route = immortalSeeker.runtimeState.navigation.route
	local action = route.actions[route.index]
	local blockedKey = WorldSemantics.cellKey(
		action.destination.cellX, action.destination.cellY)
	immortalContext.occupiedCells = { [blockedKey] = true }
	immortalContext.occupancyDetails = {
		[blockedKey] = {
			currentOccupants = {
				stationary = { entityId = "stationary", moving = false }
			},
			destinationReservations = {}
		}
	}
	Controller.executeCurrentIntent(immortalSeeker, immortalContext, cycleTick)
	assertEquals(immortalSeeker.runtimeState.navigation.releaseReason,
		"STATIONARY_OCCUPANT", "stationary congestion should release without borrowing animation timing")
	immortalContext.occupiedCells = {}
	immortalContext.occupancyDetails = {}
	Controller.executeCurrentIntent(immortalSeeker, immortalContext, cycleTick + 1)
	assertEquals(immortalSeeker.runtimeState.intentEpisode.failedAttempts, failure,
		"each persistent release should feed one existing intent failure attempt")
	cycleTick = cycleTick + 2
end
assertEquals(immortalSeeker.runtimeState.intentEpisode.status, "FAILED",
	"repeated occupancy replans without spatial progress should eventually fail SEEK_FLOCK")

local partialSeeker = {
	id = "partial-seeker",
	species = "PIDGEY",
	ecology = { family = "B", socialModifier = 1.5, locomotion = { WALK = true } },
	rawStats = { independence = 0.1 },
	temperament = { sociability = 0.9, curiosity = 0 },
	relationships = {}
}
local partialContext = {
	position = { cellX = 0, cellY = 0 },
	mapId = "TEST",
	worldSemantics = open,
	navigationHorizon = 2,
	flockSearch = {
		utility = 100,
		isolationPressure = 1,
		nearbySameSpecies = 0,
		cueSource = "last_seen",
		cuePosition = { cellX = 6, cellY = 0 },
		targetEntityId = "remembered-family"
	}
}
Controller.tick(partialSeeker, {}, nil, partialContext, 500)
partialSeeker.runtimeState.motion = { justCompleted = true }
partialContext.position = { cellX = 1, cellY = 0 }
Controller.tick(partialSeeker, {}, nil, partialContext, 501)
partialSeeker.runtimeState.motion = { justCompleted = true }
partialContext.position = { cellX = 2, cellY = 0 }
Controller.tick(partialSeeker, {}, nil, partialContext, 502)
assertEquals(partialSeeker.runtimeState.navigation.replanReason, "SEGMENT_COMPLETE", "bounded segment completion should trigger replanning without claiming the goal")
assertEquals(partialSeeker.runtimeState.navigation.route.actions[1].source.cellX, 2, "the next bounded segment should start at the actor's current position")
assertEquals(partialContext.flockSearch.cueSource, "last_seen", "partial segment completion must preserve last-seen search memory")

partialContext.position = { cellX = 3, cellY = 1 }
partialSeeker.runtimeState.motion = nil
Controller.tick(partialSeeker, {}, nil, partialContext, 503)
assertEquals(partialSeeker.runtimeState.navigation.replanReason, "SOURCE_POSITION_MISMATCH", "unexpected actor position should invalidate the stale route")
assertEquals(partialSeeker.runtimeState.movementRequest.sourceX, 3, "replanned movement should carry the new expected source")

local collisionCalls = 0
package.loaded["src.world.avatar_factory"] = nil
package.loaded["src.world.Collision"] = nil
package.preload["src.world.Collision"] = function()
	return {
		canMove = function()
			collisionCalls = collisionCalls + 1
			return true
		end,
		target = function(x, y, direction)
			return x + (direction == "right" and 1 or direction == "left" and -1 or 0), y + (direction == "down" and 1 or direction == "up" and -1 or 0)
		end
	}
end
local AvatarFactory = require("src.world.avatar_factory")
local executionEntity = { runtimeState = { movementRequest = { direction = "RIGHT", traversalMode = "WALK", sourceX = 0, sourceY = 1 } } }
local executionAvatar = { handle = { npc = { cellX = 1, cellY = 1, moving = false }, ow = { map = { id = "TEST" }, entities = {} } } }
assertEquals(AvatarFactory.applyMovementRequest({}, executionAvatar, executionEntity), false, "the actuator should reject a WALK whose planned source no longer matches")
assertEquals(executionEntity.runtimeState.movementRequest.rejectionReason, "SOURCE_POSITION_MISMATCH", "source mismatch should be reported for route invalidation")
assertEquals(collisionCalls, 0, "source mismatch should be rejected before canonical collision")
executionEntity.runtimeState.movementRequest.sourceX = 1
assertEquals(AvatarFactory.applyMovementRequest({}, executionAvatar, executionEntity), true, "canonical actuator should execute planned WALK")
assertEquals(collisionCalls, 1, "actual WALK should call canonical Collision.canMove exactly once")

-- A deterministic claim winner still cannot walk into the stationary body on
-- the reverse edge. Exercise collision rejection back through controller route
-- handling and require both actors to abandon or replan that physical swap.
local headOnClaims = MovementClaims.new()
local headOnA = {
	id = "head-on-a",
	species = "PIDGEY",
	ecology = { family = "B", socialModifier = 1.5, locomotion = { WALK = true } },
	rawStats = { independence = 0.1 },
	temperament = { sociability = 0.9, curiosity = 0 },
	relationships = {},
	runtimeState = {
		state = "SEEK_FLOCK",
		stateEnteredTick = 0,
		movementRequest = {
			direction = "RIGHT", traversalMode = "WALK",
			sourceX = 1, sourceY = 2, destinationX = 2, destinationY = 2
		},
		navigation = { route = { index = 1, actions = {
			{ direction = "RIGHT", mode = "WALK", source = { cellX = 1, cellY = 2 },
				destination = { cellX = 2, cellY = 2 } }
		} } }
	}
}
local headOnB = {
	id = "head-on-b",
	species = "PIDGEY",
	ecology = headOnA.ecology,
	rawStats = headOnA.rawStats,
	temperament = headOnA.temperament,
	relationships = {},
	runtimeState = {
		state = "SEEK_FLOCK",
		stateEnteredTick = 0,
		movementRequest = {
			direction = "LEFT", traversalMode = "WALK",
			sourceX = 2, sourceY = 2, destinationX = 1, destinationY = 2
		},
		navigation = { route = { index = 1, actions = {
			{ direction = "LEFT", mode = "WALK", source = { cellX = 2, cellY = 2 },
				destination = { cellX = 1, cellY = 2 } }
		} } }
	}
}
local headOnAvatarA = {
	handle = { npc = { cellX = 1, cellY = 2, moving = false },
		ow = { map = { id = "TEST" }, entities = {} } }
}
local headOnAvatarB = {
	handle = { npc = { entityId = "head-on-b", cellX = 2, cellY = 2, moving = false },
		ow = { map = { id = "TEST" }, entities = {} } }
}
headOnAvatarA.handle.ow.entities = { headOnAvatarB.handle.npc }
package.loaded["src.world.Collision"] = {
	canMove = function(_, _, npc, direction)
		local destinationX = npc.cellX + (direction == "right" and 1 or direction == "left" and -1 or 0)
		if destinationX == 1 or destinationX == 2 then return false, "entity" end
		return true
	end,
	target = function(x, y, direction)
		return x + (direction == "right" and 1 or direction == "left" and -1 or 0), y
	end
}
package.loaded["src.world.avatar_factory"] = nil
AvatarFactory = require("src.world.avatar_factory")
assertEquals(headOnClaims:publish({
	actorId = headOnA.id, fromX = 1, fromY = 2, toX = 2, toY = 2
}, 700), true, "first head-on actor should deterministically establish ownership")
local headOnBClaimed = headOnClaims:publish({
	actorId = headOnB.id, fromX = 2, fromY = 2, toX = 1, toY = 2
}, 700)
assertEquals(headOnBClaimed, false, "reverse-edge contender should yield to incumbent")
headOnB.runtimeState.movementRequest.rejectionReason = "entity"
assertEquals(AvatarFactory.applyMovementRequest({}, headOnAvatarA, headOnA), false,
	"claim winner must still be physically rejected by stock collision")
assertEquals(headOnA.runtimeState.movementRequest.rejectionReason, "entity",
	"physical blocker should feed authoritative entity rejection back to the controller")
assertEquals(headOnA.runtimeState.movementRequest.blockingLayer, "STOCK_COLLISION",
	"stock rejection should preserve the deciding layer")
assertEquals(headOnA.runtimeState.movementRequest.blockerId, "head-on-b",
	"stock rejection should identify the concrete entity in its own collision collection")
assertEquals(headOnA.runtimeState.movementRequest.falseEntityBlock, false,
	"a matching stock entity must not be classified as an unexplained block")
headOnAvatarA.handle.ow.entities = {}
headOnA.runtimeState.movementRequest.rejectionReason = nil
assertEquals(AvatarFactory.applyMovementRequest({}, headOnAvatarA, headOnA), false,
	"the stock adapter should preserve an unmatched entity rejection")
assertEquals(headOnA.runtimeState.movementRequest.falseEntityBlock, true,
	"an entity rejection with no matching object in the supplied collection must be explicit")
local function headOnContext(position, blockerId, blockerPosition, cueDirection)
	local occupiedKey = WorldSemantics.cellKey(blockerPosition.cellX, blockerPosition.cellY)
	return {
		executionOnly = true,
		position = position,
		mapId = "TEST",
		worldSemantics = open,
		movementClaims = headOnClaims,
		occupiedCells = { [occupiedKey] = true },
		currentOccupiedCells = { [occupiedKey] = true },
		occupancyDetails = { [occupiedKey] = {
			currentOccupants = { [blockerId] = {
				entityId = blockerId, position = blockerPosition, moving = false
			} },
			destinationReservations = {}
		} },
		flockSearch = {
			utility = 100, nearbySameSpecies = 0, cueSource = "social_signal",
			cueDirection = cueDirection, targetEntityId = "hidden-family"
		}
	}
end
Controller.executeCurrentIntent(headOnA,
	headOnContext({ cellX = 1, cellY = 2 }, headOnB.id, { cellX = 2, cellY = 2 }, "EAST"), 701)
Controller.executeCurrentIntent(headOnB,
	headOnContext({ cellX = 2, cellY = 2 }, headOnA.id, { cellX = 1, cellY = 2 }, "WEST"), 701)
local requestA = headOnA.runtimeState.movementRequest
local requestB = headOnB.runtimeState.movementRequest
local stillSwapping = requestA and requestB
	and requestA.sourceX == 1 and requestA.destinationX == 2
	and requestB.sourceX == 2 and requestB.destinationX == 1
assertEquals(stillSwapping, false,
	"head-on physical rejection must produce net progress or abandon/replan the conflicting edge")

return true
