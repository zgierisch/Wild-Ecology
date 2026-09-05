local Controller = require("src.behavior.controller")
local FleeEscape = require("src.behavior.flee_escape")
local Fear = require("src.behavior.fear")
local MovementClaims = require("src.world.movement_claims")
local RuntimeState = require("src.core.runtime_state")
local WorldSemantics = require("src.world.world_semantics")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function semantics(id, rows)
	return WorldSemantics.fromOverview({
		mapId = id,
		width = #rows[1],
		height = #rows,
		rows = rows
	})
end

local function coordinateSemantics(id, blocked)
	local rows = {}
	for cellY = 0, 14 do
		local row = {}
		for cellX = 0, 20 do
			row[#row + 1] = blocked[cellX .. "," .. cellY] and " " or "."
		end
		rows[#rows + 1] = table.concat(row)
	end
	return semantics(id, rows)
end

local function fleeEntity(id, seed)
	return {
		id = id,
		personalitySeed = seed,
		ecology = { locomotion = { WALK = true } },
		temperament = { boldness = 0 },
		runtimeState = {
			state = "FLEE",
			stateEnteredTick = 0,
			targetEntityId = "player",
			motion = { active = false },
			rejectedMoves = {}
		}
	}
end

local function forceFlee(entity, map, position, threat, tick, occupied, occupancyDetails)
	return Controller.tick(entity, { trust = 0, threatMemory = 80 }, 1, {
		hasTarget = true,
		purposefulTarget = true,
		targetEntityId = "player",
		threatAssessment = {
			primaryThreatId = "player",
			primaryThreatScore = 80,
			primaryThreatReason = "DIRECT_THREAT_MEMORY",
			primaryThreatDistance = 1
		},
		fleeRadius = 4,
		position = position,
		targetPositions = { player = threat },
		occupiedCells = occupied or { [WorldSemantics.cellKey(threat.cellX, threat.cellY)] = true },
		occupancyDetails = occupancyDetails or {},
		worldSemantics = map,
		mapId = map.mapId
	}, tick)
end

local open = semantics("OPEN_FLEE", {
	".......",
	".......",
	".......",
	".......",
	"......."
})

local safeDistanceMap = coordinateSemantics("SAFE_DISTANCE_FLEE", {})
local safeDistanceActor = fleeEntity("wild:test:safe-distance", 800)
forceFlee(safeDistanceActor, safeDistanceMap,
	{ cellX = 10, cellY = 10 }, { cellX = 10, cellY = 5 }, 1)
assertEquals(safeDistanceActor.runtimeState.movementRequest.direction ~= "STAY", true,
	"an open-ground FLEE actor with a legal safety-improving neighbor must not stay merely because its AWAY goal is already satisfied")
assertEquals(safeDistanceActor.runtimeState.movementRequest.traversalMode, "WALK",
	"the safety-improving FLEE override must create a WALK request")

local adjacentThreat = { cellX = 10, cellY = 10 }
local wallBackedActor = { cellX = 10, cellY = 11 }
local function wallBackedCase(id, seed, blocked)
	local map = coordinateSemantics(id, blocked)
	local entity = fleeEntity("wild:test:" .. id, seed)
	forceFlee(entity, map, wallBackedActor, adjacentThreat, 1, {
		[WorldSemantics.cellKey(adjacentThreat.cellX, adjacentThreat.cellY)] = true
	})
	return entity, map
end

local bothLateralEntity = wallBackedCase("WALL_BACKED_BOTH", 801, {
	["10,12"] = true
})
local bothExecution = bothLateralEntity.runtimeState.fleeExecution
assertEquals(bothLateralEntity.runtimeState.state, "FLEE",
	"Case A should remain in FLEE")
assertEquals(bothLateralEntity.runtimeState.targetEntityId, "player",
	"Case A should retain its authoritative generic threat identity")
assertEquals(bothLateralEntity.runtimeState.escapeReference.kind,
	"CURRENT_THREAT_POSITION", "Case A should use current threat geometry")
assertEquals(bothLateralEntity.runtimeState.escapeReference.position.cellX, 10,
	"Case A should retain exact threat X")
assertEquals(bothLateralEntity.runtimeState.escapeReference.position.cellY, 10,
	"Case A should retain exact threat Y")
assertEquals(bothExecution.localCandidates[1].direction, "UP",
	"candidate analysis should retain cardinal inspection order")
assertEquals(bothExecution.localCandidates[1].threatForbidden, true,
	"UP into the threat cell must remain forbidden")
assertEquals(bothExecution.localCandidates[2].direction, "DOWN",
	"direct-away DOWN should be inspected second")
assertEquals(bothExecution.localCandidates[2].staticLegal, false,
	"the wall immediately behind the actor should make DOWN statically illegal")
assertEquals(bothExecution.localCandidates[3].staticLegal, true,
	"LEFT should remain statically legal")
assertEquals(bothExecution.localCandidates[3].threatDelta, 0,
	"LEFT should be recognized as lateral rather than immediately farther")
assertEquals(bothExecution.localCandidates[4].staticLegal, true,
	"RIGHT should remain statically legal")
assertEquals(bothExecution.localCandidates[4].threatDelta, 0,
	"RIGHT should be recognized as lateral rather than immediately farther")
assertEquals(bothLateralEntity.runtimeState.movementRequest.direction == "LEFT"
	or bothLateralEntity.runtimeState.movementRequest.direction == "RIGHT", true,
	"Case A should choose a deterministic legal lateral escape")
assertEquals(bothExecution.planningState, "FOLLOWING_ROUTE",
	"Case A should use a bounded lateral escape route")
assertEquals(bothExecution.route ~= nil, true,
	"Case A should produce a route around the wall")
assertEquals(bothExecution.routeSuspended == true, false,
	"static terrain must not create dynamic route-wait semantics")

local leftBlockedEntity = wallBackedCase("WALL_BACKED_LEFT", 802, {
	["10,12"] = true, ["9,11"] = true
})
assertEquals(leftBlockedEntity.runtimeState.movementRequest.direction, "RIGHT",
	"Case B should escape right when left and direct-away are static walls")

local rightBlockedEntity = wallBackedCase("WALL_BACKED_RIGHT", 803, {
	["10,12"] = true, ["11,11"] = true
})
assertEquals(rightBlockedEntity.runtimeState.movementRequest.direction, "LEFT",
	"Case C should escape left when right and direct-away are static walls")

local trappedEntity = wallBackedCase("WALL_BACKED_TRAPPED", 804, {
	["10,12"] = true, ["9,11"] = true, ["11,11"] = true
})
assertEquals(trappedEntity.runtimeState.movementRequest.direction, "STAY",
	"Case D may stay only when the threat cell and every other adjacent cell are unavailable")

local rejectionMap = coordinateSemantics("WALL_BACKED_RUNTIME_REJECTION", {})
local rejectionActor = fleeEntity("wild:test:wall-backed-runtime-rejection", 805)
local threatOccupied = {
	[WorldSemantics.cellKey(adjacentThreat.cellX, adjacentThreat.cellY)] = true
}
forceFlee(rejectionActor, rejectionMap, wallBackedActor, adjacentThreat, 1,
	threatOccupied)
assertEquals(rejectionActor.runtimeState.movementRequest.direction, "DOWN",
	"runtime-rejection fixture should first request ideal direct-away movement")
rejectionActor.runtimeState.movementRequest.rejectionReason = "tile"
rejectionActor.runtimeState.rejectedMoves.DOWN = {
	mapId = rejectionMap.mapId,
	cellX = wallBackedActor.cellX,
	cellY = wallBackedActor.cellY,
	reason = "tile"
}
Controller.executeCurrentIntent(rejectionActor, {
	executionOnly = true, currentFear = 0.8, position = wallBackedActor,
	targetPositions = { player = adjacentThreat },
	threatAssessment = {
		primaryThreatId = "player", primaryThreatReason = "DIRECT_THREAT_MEMORY",
		primaryThreatDistance = 1
	},
	occupiedCells = threatOccupied, occupancyDetails = {},
	worldSemantics = rejectionMap, mapId = rejectionMap.mapId,
	fleeSafetyDistance = 8, fleeNeighbors = {}
}, 2)
assertEquals(rejectionActor.runtimeState.movementRequest.direction == "LEFT"
	or rejectionActor.runtimeState.movementRequest.direction == "RIGHT", true,
	"known-bad DOWN edge should immediately produce a lateral escape rather than wait")
assertEquals(rejectionActor.runtimeState.fleeExecution.planningState,
	"FOLLOWING_ROUTE", "static rejection should establish an alternate bounded route")
assertEquals(rejectionActor.runtimeState.fleeExecution.lastPlanningDirtyReason,
	"StaticRejection", "runtime wall discovery should expose its exact replan cause")
assertEquals(rejectionActor.runtimeState.rejectedMoves.DOWN.reason, "tile",
	"the known-bad DOWN edge should remain remembered at its actor cell")
assertEquals(rejectionActor.runtimeState.fleeExecution.routeSuspended == true, false,
	"a static rejection must not wait for a blocker to vacate")

local corridorEntity, corridorMap = wallBackedCase("WALL_BACKED_CORRIDOR", 806, {
	["10,12"] = true
})
local corridorRoute = corridorEntity.runtimeState.fleeExecution.route
local corridorPosition = { cellX = wallBackedActor.cellX, cellY = wallBackedActor.cellY }
local corridorInitialDistance = math.max(
	math.abs(corridorPosition.cellX - adjacentThreat.cellX),
	math.abs(corridorPosition.cellY - adjacentThreat.cellY))
local corridorDirections = {}
for tick = 2, 8 do
	local request = corridorEntity.runtimeState.movementRequest
	if not request or request.direction == "STAY" then break end
	corridorDirections[#corridorDirections + 1] = request.direction
	corridorPosition = { cellX = request.destinationX, cellY = request.destinationY }
	corridorEntity.runtimeState.motion.justCompleted = true
	forceFlee(corridorEntity, corridorMap, corridorPosition, adjacentThreat,
		tick, threatOccupied)
	if tick == 2 then
		assertEquals(corridorEntity.runtimeState.fleeExecution.route, corridorRoute,
			"successful lateral progress must preserve the committed route")
		assertEquals(corridorEntity.runtimeState.fleeExecution.lastPlanningDirtyReason,
			nil, "committed route movement must not become ActorMovement dirtiness")
	end
end
local corridorFinalDistance = math.max(
	math.abs(corridorPosition.cellX - adjacentThreat.cellX),
	math.abs(corridorPosition.cellY - adjacentThreat.cellY))
assertEquals(corridorFinalDistance > corridorInitialDistance, true,
	"Case E should make net displacement away after the lateral first step")
assertEquals(#corridorDirections >= 2, true,
	"Case E should continue through the side corridor instead of stopping laterally")

local lastKnownEntity = fleeEntity("wild:test:wall-backed-last-known", 807)
lastKnownEntity.runtimeState.targetEntityId = nil
lastKnownEntity.runtimeState.fleeThreatPosition = adjacentThreat
lastKnownEntity.runtimeState.fleeThreatPositionTick = 1
lastKnownEntity.runtimeState.fleeThreatEntityId = "threat-entity"
Controller.executeCurrentIntent(lastKnownEntity, {
	executionOnly = true, currentFear = 0.8, position = wallBackedActor,
	targetPositions = {}, threatAssessment = { primaryThreatId = nil },
	occupiedCells = {}, occupancyDetails = {}, worldSemantics = corridorMap,
	mapId = corridorMap.mapId, fleeSafetyDistance = 8, fleeNeighbors = {}
}, 2)
assertEquals(lastKnownEntity.runtimeState.escapeReference.kind,
	"LAST_KNOWN_THREAT_POSITION", "wall-backed recovery should retain last-known geometry")
assertEquals(lastKnownEntity.runtimeState.movementRequest.direction == "LEFT"
	or lastKnownEntity.runtimeState.movementRequest.direction == "RIGHT", true,
	"last-known wall-backed FLEE should also choose a lateral escape")
assertEquals(lastKnownEntity.runtimeState.targetEntityId, nil,
	"last-known geometry must remain targetless")

local headingEntity = fleeEntity("wild:test:wall-backed-heading", 808)
headingEntity.runtimeState.targetEntityId = nil
headingEntity.runtimeState.escapeHeading = {
	dx = 0, dy = 1, residualX = 0, residualY = 1, establishedTick = 1
}
Controller.executeCurrentIntent(headingEntity, {
	executionOnly = true, currentFear = 0.4, position = wallBackedActor,
	targetPositions = {}, threatAssessment = { primaryThreatId = nil },
	occupiedCells = {}, occupancyDetails = {}, worldSemantics = corridorMap,
	mapId = corridorMap.mapId, fleeSafetyDistance = 8, fleeNeighbors = {}
}, 2)
assertEquals(headingEntity.runtimeState.escapeReference.kind, "HEADING_INERTIA",
	"targetless recovery should use heading inertia")
assertEquals(headingEntity.runtimeState.movementRequest.direction == "LEFT"
	or headingEntity.runtimeState.movementRequest.direction == "RIGHT", true,
	"heading-inertia wall-backed FLEE should choose a lateral escape")
print(string.format(
	"WALL_BACKED_FLEE caseA=%s caseB=%s caseC=%s caseD=%s caseEStart=%s caseEEnd=%s caseESteps=%d runtimeFallback=%s planning=%s suspended=%s",
	tostring(bothLateralEntity.runtimeState.movementRequest.direction),
	tostring(leftBlockedEntity.runtimeState.movementRequest.direction),
	tostring(rightBlockedEntity.runtimeState.movementRequest.direction),
	tostring(trappedEntity.runtimeState.movementRequest.direction),
	tostring(corridorInitialDistance), tostring(corridorFinalDistance),
	#corridorDirections, tostring(rejectionActor.runtimeState.movementRequest.direction),
	tostring(rejectionActor.runtimeState.fleeExecution.planningState),
	tostring(rejectionActor.runtimeState.fleeExecution.routeSuspended == true)))
local actor = { cellX = 3, cellY = 2 }
local threat = { cellX = 3, cellY = 3 }
local openEntity = fleeEntity("wild:test:open", 1)
forceFlee(openEntity, open, actor, threat, 1)
assertEquals(openEntity.runtimeState.movementRequest.direction, "UP", "open-space FLEE should retain immediate local steering")
assertEquals(openEntity.runtimeState.fleeExecution.fleeMode, "NORMAL", "open-space FLEE should not invoke bounded search")
assertEquals(openEntity.runtimeState.fleeExecution.route, nil, "open-space FLEE should not allocate an escape route")

local boundary = semantics("BOUNDARY_FLEE", {
	".......",
	".. ...",
	".......",
	".......",
	"......."
})
local boundaryEntity = fleeEntity("wild:test:boundary", 2)
forceFlee(boundaryEntity, boundary, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, 1)
local boundaryExecution = boundaryEntity.runtimeState.fleeExecution
assertEquals(boundaryExecution.fleeMode, "ESCAPE_ROUTE", "blocked directly-away geometry should activate bounded escape")
assertEquals(boundaryEntity.runtimeState.movementRequest.direction == "LEFT" or boundaryEntity.runtimeState.movementRequest.direction == "RIGHT", true, "boundary escape should begin laterally")
assertEquals(boundaryExecution.nextStepThreatDelta, 0, "lateral escape may preserve threat distance on its first step")
assertEquals(boundaryExecution.endpointThreatDistance > boundaryExecution.threatDistance, true, "lateral route endpoint should be safer than its source")
local committedBoundaryRoute = boundaryExecution.route
local boundaryNext = boundaryEntity.runtimeState.movementRequest.destinationX
	and { cellX = boundaryEntity.runtimeState.movementRequest.destinationX, cellY = boundaryEntity.runtimeState.movementRequest.destinationY }
boundaryEntity.runtimeState.motion.justCompleted = true
forceFlee(boundaryEntity, boundary, boundaryNext, { cellX = 2, cellY = 3 }, 2)
assertEquals(boundaryEntity.runtimeState.fleeExecution.fleeMode, "ESCAPE_ROUTE", "one locally useful neighbor must not end route commitment")
assertEquals(boundaryEntity.runtimeState.fleeExecution.route, committedBoundaryRoute, "a valid escape route should survive its intermediate cells")
assertEquals(boundaryEntity.runtimeState.fleeExecution.route.index, 2, "completed route movement should advance rather than replan")
local boundaryPosition = boundaryNext
for tick = 3, 10 do
	local request = boundaryEntity.runtimeState.movementRequest
	if not request or request.direction == "STAY" then break end
	boundaryPosition = { cellX = request.destinationX, cellY = request.destinationY }
	boundaryEntity.runtimeState.motion.justCompleted = true
	forceFlee(boundaryEntity, boundary, boundaryPosition, { cellX = 2, cellY = 3 }, tick)
	if boundaryEntity.runtimeState.fleeExecution.route == nil then break end
end
assertEquals(boundaryEntity.runtimeState.fleeExecution.route, nil, "committed route should eventually complete")
assertEquals(boundaryEntity.runtimeState.fleeExecution.routeInvalidationReason, "ROUTE_COMPLETE", "route handoff should occur at its endpoint")

local regression = semantics("REGRESSION_FLEE", {
	"    .  ",
	"    .  ",
	"  . .  ",
	"  ...  ",
	"  .    ",
	"       "
})
local regressionEntity = fleeEntity("wild:test:regression", 3)
forceFlee(regressionEntity, regression, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 4 }, 1)
local regressionExecution = regressionEntity.runtimeState.fleeExecution
assertEquals(regressionEntity.runtimeState.movementRequest.direction, "DOWN", "bounded escape may begin with the only statically legal step")
assertEquals(regressionExecution.temporaryThreatRegression, true, "route should diagnose a temporary threat-distance regression")
assertEquals(regressionExecution.nextStepThreatDelta < 0, true, "temporary regression should be explicit")
assertEquals(regressionExecution.endpointThreatDistance - regressionExecution.threatDistance >= 2, true, "a regressive first step requires a substantially safer endpoint")
for _, action in ipairs(regressionExecution.route.actions) do
	assertEquals(action.destination.cellX == 2 and action.destination.cellY == 4, false, "escape route must never enter the threat cell")
end

local sameSourceEntity = fleeEntity("wild:test:same-source-regression", 3)
sameSourceEntity.runtimeState.targetEntityId = nil
sameSourceEntity.runtimeState.fleeThreatPosition = { cellX = 2, cellY = 4 }
sameSourceEntity.runtimeState.fleeThreatPositionTick = 1
sameSourceEntity.runtimeState.fleeThreatEntityId = "player"
local sameSourcePosition = { cellX = 2, cellY = 2 }
Controller.executeCurrentIntent(sameSourceEntity, {
	executionOnly = true,
	currentFear = 0.6,
	position = sameSourcePosition,
	targetPositions = {},
	threatAssessment = { primaryThreatId = nil },
	occupiedCells = {},
	worldSemantics = regression,
	mapId = regression.mapId,
	fleeSafetyDistance = 7,
	fleeNeighbors = {}
}, 2)
local sameSourceRoute = sameSourceEntity.runtimeState.fleeExecution.route
assertEquals(sameSourceEntity.runtimeState.fleeExecution.temporaryThreatRegression, true,
	"last-known route fixture should approve a temporary regression")
sameSourcePosition = {
	cellX = sameSourceEntity.runtimeState.movementRequest.destinationX,
	cellY = sameSourceEntity.runtimeState.movementRequest.destinationY
}
sameSourceEntity.runtimeState.motion.justCompleted = true
Controller.executeCurrentIntent(sameSourceEntity, {
	executionOnly = true,
	currentFear = 0.6,
	position = sameSourcePosition,
	targetPositions = { player = { cellX = 2, cellY = 4 } },
	threatAssessment = {
		primaryThreatId = "player",
		primaryThreatReason = "TRAINER_WARINESS",
		primaryThreatDistance = 1
	},
	occupiedCells = {},
	worldSemantics = regression,
	mapId = regression.mapId,
	fleeSafetyDistance = 7,
	fleeNeighbors = {}
}, 3)
assertEquals(sameSourceEntity.runtimeState.fleeExecution.route, sameSourceRoute,
	"same-player last-known to current transition should preserve the committed route")
assertEquals(sameSourceEntity.runtimeState.fleeExecution.route.index, 2,
	"same-source reacquisition should advance the route instead of replanning")

local function sparseRow(width, cells)
	local values = {}
	for x = 0, width - 1 do values[x + 1] = cells[x] and "." or " " end
	return table.concat(values)
end

local liveRows = {}
for y = 0, 15 do liveRows[y + 1] = sparseRow(27, {}) end
local liveUpper = {}
for x = 16, 20 do liveUpper[x] = true end
liveRows[13] = sparseRow(27, liveUpper)
liveRows[14] = sparseRow(27, { [20] = true, [21] = true })
liveRows[15] = sparseRow(27, { [19] = true, [20] = true, [21] = true })
local liveLoop = semantics("LIVE_X19_X20", liveRows)
local liveEntity = fleeEntity("wild:test:live-x19", 25)
liveEntity.runtimeState.targetEntityId = nil
liveEntity.runtimeState.fleeThreatPosition = { cellX = 24, cellY = 14 }
liveEntity.runtimeState.fleeThreatPositionTick = 1
liveEntity.runtimeState.fleeThreatEntityId = "player"
local livePosition = { cellX = 19, cellY = 14 }
local function executeLiveRoute(tick, primaryThreatId)
	Controller.executeCurrentIntent(liveEntity, {
		executionOnly = true,
		currentFear = 0.6,
		position = livePosition,
		targetPositions = primaryThreatId and {
			[primaryThreatId] = primaryThreatId == "player"
				and { cellX = 24, cellY = 14 } or { cellX = 20, cellY = 13 }
		} or {},
		threatAssessment = {
			primaryThreatId = primaryThreatId,
			primaryThreatReason = primaryThreatId and "TRAINER_WARINESS" or "NONE"
		},
		occupiedCells = {},
		worldSemantics = liveLoop,
		mapId = liveLoop.mapId,
		fleeSafetyDistance = 8,
		fleeNeighbors = {}
	}, tick)
end
executeLiveRoute(2, nil)
local liveRoute = liveEntity.runtimeState.fleeExecution.route
assertEquals(liveEntity.runtimeState.movementRequest.direction, "RIGHT",
	"x19 fixture should reproduce the approved first step toward the player")
assertEquals(liveEntity.runtimeState.fleeExecution.nextStepThreatDelta, -1,
	"x19 RIGHT should record one unit of temporary-regression debt")
assertEquals(liveEntity.runtimeState.fleeExecution.temporaryThreatRegression, true,
	"x19 route should explicitly approve temporary regression")
livePosition = { cellX = 20, cellY = 14 }
liveEntity.runtimeState.motion.justCompleted = true
executeLiveRoute(3, "player")
assertEquals(liveEntity.runtimeState.fleeExecution.route, liveRoute,
	"x20 same-player reacquisition must preserve the x19 committed route")
assertEquals(liveEntity.runtimeState.movementRequest.direction == "LEFT", false,
	"x20 committed detour must not reverse immediately to x19")
assertEquals(liveEntity.runtimeState.fleeExecution.routeRegressionDebt, 1,
	"committed route should carry its one-cell regression debt at x20")
assertEquals(liveEntity.runtimeState.fleeExecution.sameThreatSource, true,
	"last-known and current player references should share route source identity")
assertEquals(liveEntity.runtimeState.fleeExecution.routeRevalidated, true,
	"same-player reacquisition should explicitly revalidate the remaining route")
assertEquals(liveEntity.runtimeState.fleeExecution.localGreedyCandidate, "LEFT",
	"x20 fixture should expose the local greedy reversal")
assertEquals(liveEntity.runtimeState.fleeExecution.localGreedySuppressedByRoute, true,
	"valid route commitment should suppress the local greedy reversal")

local sawCurrentToLastKnown = false
local sawRegressionDebtRepaid = false
for tick = 4, 12 do
	local request = liveEntity.runtimeState.movementRequest
	if not request or request.direction == "STAY" then break end
	livePosition = { cellX = request.destinationX, cellY = request.destinationY }
	liveEntity.runtimeState.motion.justCompleted = true
	local directId = tick == 4 and nil or "player"
	executeLiveRoute(tick, directId)
	if tick == 4 then
		sawCurrentToLastKnown = liveEntity.runtimeState.fleeExecution.route == liveRoute
	end
	if liveEntity.runtimeState.fleeExecution.route == liveRoute
		and liveEntity.runtimeState.fleeExecution.routeRegressionDebt == 0 then
		sawRegressionDebtRepaid = true
	end
	if liveEntity.runtimeState.fleeExecution.route == nil then break end
end
assertEquals(sawCurrentToLastKnown, true,
	"same-player current to last-known transition should preserve commitment")
local liveFinalDistance = math.max(
	math.abs(livePosition.cellX - 24), math.abs(livePosition.cellY - 14))
assertEquals(liveFinalDistance > 5 and not (livePosition.cellX == 19 or livePosition.cellX == 20),
	true, string.format(
	"x19 actor should escape the loop and reach net safety improvement (cell=%s,%s distance=%s)",
	tostring(livePosition.cellX), tostring(livePosition.cellY), tostring(liveFinalDistance)))
assertEquals(sawRegressionDebtRepaid, true,
	"route progress should repay temporary-regression debt through recovered distance")

local changedThreatEntity = fleeEntity("wild:test:changed-threat", 25)
changedThreatEntity.runtimeState.targetEntityId = nil
changedThreatEntity.runtimeState.fleeThreatPosition = { cellX = 24, cellY = 14 }
changedThreatEntity.runtimeState.fleeThreatPositionTick = 1
changedThreatEntity.runtimeState.fleeThreatEntityId = "player"
local changedPosition = { cellX = 19, cellY = 14 }
Controller.executeCurrentIntent(changedThreatEntity, {
	executionOnly = true, currentFear = 0.6, position = changedPosition,
	targetPositions = {}, threatAssessment = { primaryThreatId = nil }, occupiedCells = {},
	worldSemantics = liveLoop, mapId = liveLoop.mapId, fleeSafetyDistance = 8, fleeNeighbors = {}
}, 2)
local playerRoute = changedThreatEntity.runtimeState.fleeExecution.route
changedPosition = {
	cellX = changedThreatEntity.runtimeState.movementRequest.destinationX,
	cellY = changedThreatEntity.runtimeState.movementRequest.destinationY
}
changedThreatEntity.runtimeState.motion.justCompleted = true
Controller.executeCurrentIntent(changedThreatEntity, {
	executionOnly = true, currentFear = 0.6, position = changedPosition,
	targetPositions = { hostile = { cellX = 20, cellY = 13 } },
	threatAssessment = { primaryThreatId = "hostile", primaryThreatReason = "HOSTILITY" },
	occupiedCells = {}, worldSemantics = liveLoop, mapId = liveLoop.mapId,
	fleeSafetyDistance = 8, fleeNeighbors = {}
}, 3)
assertEquals(changedThreatEntity.runtimeState.fleeExecution.route ~= playerRoute, true,
	"a different authoritative threat must not inherit the player route")
assertEquals(changedThreatEntity.runtimeState.fleeExecution.routeInvalidationReason,
	"THREAT_SOURCE_CHANGED", "different threat should expose explicit invalidation provenance")

local sealed = semantics("SEALED_FLEE", {
	"     ",
	"  .  ",
	"  .  ",
	"     "
})
local noEscape = FleeEscape.plan(fleeEntity("wild:test:sealed", 4), sealed, { cellX = 2, cellY = 1 }, { cellX = 2, cellY = 2 })
assertEquals(noEscape, nil, "sealed geometry should not invent an escape route or cycle")
local sealedEntity = fleeEntity("wild:test:sealed-controller", 41)
for tick = 1, 5 do
	forceFlee(sealedEntity, sealed, { cellX = 2, cellY = 1 }, { cellX = 2, cellY = 2 }, tick)
	assertEquals(sealedEntity.runtimeState.movementRequest.direction, "STAY", "sealed FLEE should wait and reconsider without cycling")
end
assertEquals(next(sealedEntity.runtimeState.rejectedMoves), nil, "waiting in sealed geometry should not poison collision memory")

local hotLoopEntity = fleeEntity("wild:test:unchanged-plan-block", 42)
local hotLoopContext = {
	executionOnly = true,
	currentFear = 0.8,
	position = { cellX = 2, cellY = 1 },
	targetPositions = { player = { cellX = 2, cellY = 2 } },
	threatAssessment = {
		primaryThreatId = "player",
		primaryThreatReason = "DIRECT_THREAT_MEMORY",
		primaryThreatDistance = 1
	},
	occupiedCells = {},
	occupancyDetails = {},
	worldSemantics = sealed,
	mapId = sealed.mapId,
	fleeSafetyDistance = 8,
	fleeNeighbors = {}
}
FleeEscape.resetCounters()
Controller.tick(hotLoopEntity, { trust = 0, threatMemory = 80 }, 1,
	hotLoopContext, 1)
for tick = 2, 300 do
	Controller.executeCurrentIntent(hotLoopEntity, hotLoopContext, tick)
end
local hotLoopCounters = FleeEscape.getCounters()
assertEquals(hotLoopEntity.runtimeState.state, "FLEE",
	"unchanged blocked planning must not weaken FLEE motivation")
assertEquals(hotLoopCounters.boundedFleePlannerCalls <= 3, true,
	"unchanged planning inputs should keep bounded planner calls effectively constant")
assertEquals(hotLoopCounters.boundedFleeRouteObjectsCreated, 0,
	"sealed unchanged geometry should create no executable route objects")
assertEquals(hotLoopEntity.runtimeState.behaviorDecisionCount, nil,
	"execution-only updates should not add high-level Controller deliberations")
print(string.format(
	"FLEE_HOT_LOOP_AFTER lifecycleTicks=300 plannerCalls=%d suppressed=%d dirty=%d routes=%d completedSteps=0 highLevelDeliberations=1 callsPer100=%.2f",
	hotLoopCounters.boundedFleePlannerCalls,
	hotLoopCounters.boundedFleePlannerCallsSuppressed,
	hotLoopCounters.boundedFleePlannerDirtyEvents,
	hotLoopCounters.boundedFleeRouteObjectsCreated,
	hotLoopCounters.boundedFleePlannerCalls / 3))

local rejectionEntity = fleeEntity("wild:test:static-rejection", 5)
rejectionEntity.runtimeState.movementRequest = {
	issuedTick = 1,
	direction = "UP",
	traversalMode = "WALK",
	rejectionReason = "tile"
}
rejectionEntity.runtimeState.rejectedMoves.UP = { mapId = "BOUNDARY_FLEE", cellX = 2, cellY = 2 }
forceFlee(rejectionEntity, boundary, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, 2)
assertEquals(rejectionEntity.runtimeState.fleeExecution.noProgressSteps, 1, "static rejection should count as FLEE no-progress without a completed step")
rejectionEntity.runtimeState.movementRequest = {
	issuedTick = 2,
	direction = "LEFT",
	traversalMode = "WALK",
	rejectionReason = "bounds"
}
forceFlee(rejectionEntity, boundary, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, 3)
assertEquals(rejectionEntity.runtimeState.fleeExecution.staticRejections, 2, "distinct static failures should accumulate")
assertEquals(rejectionEntity.runtimeState.fleeExecution.stuckReason, "REPEATED_STATIC_REJECTION", "repeated static failures should identify the local minimum")

local dynamicRejectionEntity = fleeEntity("wild:test:dynamic-rejection", 51)
dynamicRejectionEntity.runtimeState.movementRequest = {
	issuedTick = 1,
	direction = "LEFT",
	traversalMode = "WALK",
	rejectionReason = "entity"
}
forceFlee(dynamicRejectionEntity, boundary, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, 2, {
	[WorldSemantics.cellKey(1, 2)] = true,
	[WorldSemantics.cellKey(3, 2)] = true,
	[WorldSemantics.cellKey(2, 3)] = true
})
assertEquals(dynamicRejectionEntity.runtimeState.fleeExecution.noProgressSteps, 0, "dynamic occupancy rejection should not become static no-progress evidence")
assertEquals(dynamicRejectionEntity.runtimeState.fleeExecution.stuckReason, "CROWD_BLOCK", "entity rejection should be diagnosed as transient crowding")
assertEquals(next(dynamicRejectionEntity.runtimeState.rejectedMoves), nil, "entity rejection should never poison static rejection memory")

local leftKey = WorldSemantics.cellKey(1, 2)
local rightKey = WorldSemantics.cellKey(3, 2)
local threatKey = WorldSemantics.cellKey(2, 3)
local leftBlocked = { [leftKey] = true, [threatKey] = true }
local congestionEntity = fleeEntity("wild:test:congestion", 6)
forceFlee(congestionEntity, boundary, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, 1, leftBlocked)
assertEquals(congestionEntity.runtimeState.movementRequest.direction, "RIGHT", "escape search should prefer the currently open equivalent lateral route")
local diagnosed = {}
for _, candidate in ipairs(congestionEntity.runtimeState.fleeExecution.localCandidates) do
	diagnosed[candidate.direction] = candidate
end
assertEquals(diagnosed.UP.staticLegal, false, "candidate diagnostics should expose the statically blocked away direction")
assertEquals(diagnosed.LEFT.occupied, true, "candidate diagnostics should expose dynamic lateral occupancy")
assertEquals(diagnosed.DOWN.threatForbidden, true, "candidate diagnostics should identify the forbidden threat cell")

local fleeClaims = MovementClaims.new()
fleeClaims:publish({
	actorId = "other-fleer", fromX = 0, fromY = 2, toX = 1, toY = 2,
	intent = "FLEE", urgency = 0.5
}, 1)
local claimAwareEscape = FleeEscape.plan(
	fleeEntity("wild:test:claim-aware", 6), boundary,
	{ cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, {
		movementClaims = fleeClaims,
		occupiedCells = { [threatKey] = true }
	})
assertEquals(claimAwareEscape.actions[1].direction, "RIGHT",
	"bounded FLEE should penalize an already claimed equivalent first step")

local allBlocked = { [leftKey] = true, [rightKey] = true, [threatKey] = true }
local waitingEntity = fleeEntity("wild:test:waiting", 7)
forceFlee(waitingEntity, boundary, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, 1, allBlocked)
assertEquals(waitingEntity.runtimeState.movementRequest.direction, "STAY", "an actor surrounded by dynamic blockers should wait instead of poisoning topology")
assertEquals(next(waitingEntity.runtimeState.rejectedMoves), nil, "dynamic congestion should not enter permanent rejection memory")
forceFlee(waitingEntity, boundary, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, 2, leftBlocked)
assertEquals(waitingEntity.runtimeState.movementRequest.direction, "RIGHT", "blocked actor should proceed when transient space opens")

local suspendedEntity = fleeEntity("wild:test:suspended-route", 72)
forceFlee(suspendedEntity, boundary, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, 1)
local suspendedRoute = suspendedEntity.runtimeState.fleeExecution.route
local suspendedAction = suspendedRoute.actions[suspendedRoute.index]
local suspendedRouteIndex = suspendedRoute.index
local suspendedRecentCount = #suspendedEntity.runtimeState.fleeExecution.recentCells
local suspendedIntentProgress = suspendedEntity.runtimeState.intentEpisode
	and suspendedEntity.runtimeState.intentEpisode.progress or 0
local suspendedResidualX = suspendedEntity.runtimeState.escapeHeading.residualX
local suspendedResidualY = suspendedEntity.runtimeState.escapeHeading.residualY
local suspendedBlocker = {
	[WorldSemantics.cellKey(suspendedAction.destination.cellX, suspendedAction.destination.cellY)] = true
}
forceFlee(suspendedEntity, boundary, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, 2, suspendedBlocker)
assertEquals(suspendedEntity.runtimeState.fleeExecution.route, suspendedRoute,
	"transient occupancy should suspend rather than destroy a committed route")
assertEquals(suspendedEntity.runtimeState.movementRequest, nil,
	"a suspended route should not emit an actuator request")
assertEquals(suspendedEntity.runtimeState.fleeExecution.route.index, suspendedRouteIndex,
	"suspension should not advance the committed route")
assertEquals(#suspendedEntity.runtimeState.fleeExecution.recentCells, suspendedRecentCount,
	"suspension should not enter ABAB cell or direction history")
assertEquals(suspendedEntity.runtimeState.intentEpisode.progress, suspendedIntentProgress,
	"suspension should not count as purposeful progress")
assertEquals(suspendedEntity.runtimeState.escapeHeading.residualX, suspendedResidualX,
	"suspension should not consume horizontal EscapeHeading residual")
assertEquals(suspendedEntity.runtimeState.escapeHeading.residualY, suspendedResidualY,
	"suspension should not consume vertical EscapeHeading residual")
assertEquals(suspendedEntity.runtimeState.motion.active, false,
	"suspension should not start actuator motion")
assertEquals(suspendedEntity.runtimeState.motion.startedTick, nil,
	"suspension should not stamp a movement start")
assertEquals(suspendedEntity.runtimeState.motion.completedTick, nil,
	"suspension should not stamp movement completion")
assertEquals(suspendedEntity.runtimeState.state, "FLEE",
	"urgent FLEE selection should remain active while route execution waits")
forceFlee(suspendedEntity, boundary, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, 3)
assertEquals(suspendedEntity.runtimeState.fleeExecution.route, suspendedRoute,
	"cleared occupancy should resume the same route")
assertEquals(suspendedEntity.runtimeState.movementRequest.direction, suspendedAction.direction,
	"cleared occupancy should continue the original next action")

local persistentEntity = fleeEntity("wild:test:persistent-route-block", 73)
forceFlee(persistentEntity, boundary, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, 1)
local persistentRoute = persistentEntity.runtimeState.fleeExecution.route
local persistentAction = persistentRoute.actions[persistentRoute.index]
local persistentBlockedKey = WorldSemantics.cellKey(
	persistentAction.destination.cellX, persistentAction.destination.cellY)
local persistentBlocker = { [persistentBlockedKey] = true }
local persistentDetails = {
	[persistentBlockedKey] = {
		currentOccupants = {
			stationary = { entityId = "stationary", moving = false }
		},
		destinationReservations = {}
	}
}
forceFlee(persistentEntity, boundary, { cellX = 2, cellY = 2 },
	{ cellX = 2, cellY = 3 }, 2, persistentBlocker, persistentDetails)
assertEquals(persistentEntity.runtimeState.fleeExecution.route == persistentRoute, false,
	"persistent dynamic occupancy should release and replace the suspended route")
assertEquals(persistentEntity.runtimeState.fleeExecution.routeInvalidationReason,
	"PERSISTENT_DYNAMIC_OCCUPANCY", "bounded release should retain its dynamic cause")
forceFlee(persistentEntity, boundary, { cellX = 2, cellY = 2 },
	{ cellX = 2, cellY = 3 }, 3, persistentBlocker, persistentDetails)
assertEquals(persistentEntity.runtimeState.movementRequest.direction == persistentAction.direction, false,
	"replanning should avoid the recently persistent bottleneck when an alternative exists")
assertEquals(persistentEntity.runtimeState.fleeExecution.recentDynamicBlockedBottlenecks[
	persistentBlockedKey] > 0, true, "released routes should retain short-lived bottleneck memory")

local function executionContext(map, position, threatPosition, occupied, details)
	return {
		executionOnly = true,
		currentFear = 0.8,
		position = position,
		targetPositions = { player = threatPosition },
		threatAssessment = {
			primaryThreatId = "player",
			primaryThreatReason = "DIRECT_THREAT_MEMORY",
			primaryThreatDistance = math.max(
				math.abs(position.cellX - threatPosition.cellX),
				math.abs(position.cellY - threatPosition.cellY))
		},
		occupiedCells = occupied or {},
		occupancyDetails = details or {},
		worldSemantics = map,
		mapId = map.mapId,
		fleeSafetyDistance = 8,
		fleeNeighbors = {}
	}
end

local dirtyEntity = fleeEntity("wild:test:planner-dirty-events", 731)
local dirtyPosition = { cellX = 2, cellY = 2 }
local dirtyThreat = { cellX = 2, cellY = 3 }
FleeEscape.resetCounters()
forceFlee(dirtyEntity, boundary, dirtyPosition, dirtyThreat, 1)
local dirtyRoute = dirtyEntity.runtimeState.fleeExecution.route
local dirtyAction = dirtyRoute.actions[dirtyRoute.index]
local dirtyCell = WorldSemantics.cellKey(
	dirtyAction.destination.cellX, dirtyAction.destination.cellY)
local dirtyOccupied = { [dirtyCell] = true }
local blockerB = {
	[dirtyCell] = {
		currentOccupants = { B = {
			entityId = "B", moving = false,
			position = { cellX = dirtyAction.destination.cellX,
				cellY = dirtyAction.destination.cellY }
		} },
		destinationReservations = {}
	}
}
Controller.executeCurrentIntent(dirtyEntity,
	executionContext(boundary, dirtyPosition, dirtyThreat, dirtyOccupied, blockerB), 2)
for tick = 3, 300 do
	Controller.executeCurrentIntent(dirtyEntity,
		executionContext(boundary, dirtyPosition, dirtyThreat, dirtyOccupied, blockerB), tick)
end
local unchangedBlockerCounters = FleeEscape.getCounters()
assertEquals(dirtyEntity.runtimeState.state, "FLEE",
	"stationary congestion must not end FLEE motivation")
assertEquals(unchangedBlockerCounters.boundedFleePlannerCalls <= 3, true,
	"300 unchanged blocker ticks should invoke bounded planning only initially/watchdog")
local clearingEntity = fleeEntity("wild:test:blocker-clear-dirty", 735)
FleeEscape.resetCounters()
forceFlee(clearingEntity, boundary, dirtyPosition, dirtyThreat, 1, allBlocked)
for tick = 2, 20 do
	Controller.executeCurrentIntent(clearingEntity,
		executionContext(boundary, dirtyPosition, dirtyThreat,
			allBlocked, {}), tick)
end
assertEquals(clearingEntity.runtimeState.fleeExecution.planningState,
	"PLAN_BLOCKED_UNCHANGED", "released occupancy should wait before relevant input changes")
local callsBeforeBlockerMove = FleeEscape.getCounters().boundedFleePlannerCalls
Controller.executeCurrentIntent(clearingEntity,
	executionContext(boundary, dirtyPosition, dirtyThreat, leftBlocked, {}), 21)
local blockerMovedCounters = FleeEscape.getCounters()
assertEquals(blockerMovedCounters.boundedFleePlannerCalls
	> callsBeforeBlockerMove, true,
	"clearing the contested cell should dirty planning immediately")
assertEquals(blockerMovedCounters.dirtyByBlockerMovement > 0, true,
	"cell clearance should be attributed to blocker movement")

local replacementEntity = fleeEntity("wild:test:new-blocker-dirty", 732)
FleeEscape.resetCounters()
local function blockerDetails(id)
	return {
		[leftKey] = { currentOccupants = { [id] = {
			entityId = id, moving = false, position = { cellX = 1, cellY = 2 }
		} }, destinationReservations = {} },
		[rightKey] = { currentOccupants = { fixed = {
			entityId = "fixed", moving = false, position = { cellX = 3, cellY = 2 }
		} }, destinationReservations = {} }
	}
end
forceFlee(replacementEntity, boundary, dirtyPosition, dirtyThreat, 1,
	allBlocked, blockerDetails("B"))
local callsBeforeReplacement = FleeEscape.getCounters().boundedFleePlannerCalls
Controller.executeCurrentIntent(replacementEntity,
	executionContext(boundary, dirtyPosition, dirtyThreat,
		allBlocked, blockerDetails("C")), 2)
assertEquals(FleeEscape.getCounters().boundedFleePlannerCalls
	> callsBeforeReplacement, true,
	"replacing blocker B with C should dirty planning immediately")
assertEquals(FleeEscape.getCounters().dirtyByBlockerReplacement > 0, true,
	"blocker identity changes should retain replacement-specific attribution")

local bookkeepingEntity = fleeEntity("wild:test:blocker-bookkeeping", 738)
local function bookkeepingDetails(validationTick, animationProgress)
	return {
		[leftKey] = {
			currentOccupants = { B = {
				entityId = "B", moving = false, position = { cellX = 1, cellY = 2 },
				animationProgress = animationProgress
			} },
			destinationReservations = { R = {
				entityId = "R", destination = { cellX = 1, cellY = 2 },
				lastValidatedTick = validationTick
			} }
		},
		[rightKey] = {
			currentOccupants = { C = {
				entityId = "C", moving = false, position = { cellX = 3, cellY = 2 },
				animationProgress = animationProgress
			} }, destinationReservations = {}
		}
	}
end
FleeEscape.resetCounters()
forceFlee(bookkeepingEntity, boundary, dirtyPosition, dirtyThreat, 1,
	allBlocked, bookkeepingDetails(1, 0.1))
local callsBeforeBookkeeping = FleeEscape.getCounters().boundedFleePlannerCalls
Controller.executeCurrentIntent(bookkeepingEntity,
	executionContext(boundary, dirtyPosition, dirtyThreat, allBlocked,
		bookkeepingDetails(999, 0.9)), 2)
local bookkeepingCounters = FleeEscape.getCounters()
assertEquals(bookkeepingCounters.boundedFleePlannerCalls, callsBeforeBookkeeping,
	"claim validation timestamps and animation progress must not wake planning")
assertEquals(bookkeepingCounters.dirtyByClaimChange, 0,
	"claim bookkeeping timestamps are not meaningful claim changes")
assertEquals(bookkeepingCounters.dirtyByBlockerMovement, 0,
	"animation progress is not blocker movement")

local threatDirtyEntity = fleeEntity("wild:test:threat-dirty", 733)
FleeEscape.resetCounters()
local sealedPosition = { cellX = 2, cellY = 1 }
local sealedThreat = { cellX = 2, cellY = 2 }
forceFlee(threatDirtyEntity, sealed, sealedPosition, sealedThreat, 1)
local callsBeforeThreatMove = FleeEscape.getCounters().boundedFleePlannerCalls
local movedThreat = { cellX = 3, cellY = 2 }
Controller.executeCurrentIntent(threatDirtyEntity,
	executionContext(sealed, sealedPosition, movedThreat, {}, {}), 2)
local threatMovedCounters = FleeEscape.getCounters()
assertEquals(threatMovedCounters.boundedFleePlannerCalls
	> callsBeforeThreatMove, true,
	"material threat geometry movement should dirty planning immediately")
assertEquals(threatMovedCounters.dirtyByThreatChange > 0, true,
	"threat movement should retain its dirty-event attribution")

local staticLoopEntity = fleeEntity("wild:test:static-rejection-loop", 734)
FleeEscape.resetCounters()
forceFlee(staticLoopEntity, boundary, dirtyPosition, dirtyThreat, 1)
local staticRequest = staticLoopEntity.runtimeState.movementRequest
staticRequest.rejectionReason = "tile"
staticLoopEntity.runtimeState.rejectedMoves[staticRequest.direction] = {
	mapId = boundary.mapId,
	cellX = dirtyPosition.cellX,
	cellY = dirtyPosition.cellY,
	reason = "tile"
}
local staticContext = executionContext(boundary, dirtyPosition, dirtyThreat, allBlocked, {})
Controller.executeCurrentIntent(staticLoopEntity, staticContext, 2)
for tick = 3, 300 do
	Controller.executeCurrentIntent(staticLoopEntity, staticContext, tick)
end
local unchangedStaticCounters = FleeEscape.getCounters()
assertEquals(unchangedStaticCounters.boundedFleePlannerCalls <= 3, true,
	"known static rejection should not be rediscovered at execution frequency")
local changedPosition = { cellX = 3, cellY = 2 }
Controller.executeCurrentIntent(staticLoopEntity,
	executionContext(boundary, changedPosition, dirtyThreat, allBlocked, {}), 301)
assertEquals(FleeEscape.getCounters().dirtyByActorMovement > 0, true,
	"actor movement should dirty static-rejection planning immediately")
local topologyEntity = fleeEntity("wild:test:topology-dirty", 736)
FleeEscape.resetCounters()
forceFlee(topologyEntity, sealed, sealedPosition, sealedThreat, 1)
local callsBeforeTopology = FleeEscape.getCounters().boundedFleePlannerCalls
local replacementSealed = semantics("SEALED_FLEE", {
	"     ", "  .  ", "  .  ", "     "
})
Controller.executeCurrentIntent(topologyEntity,
	executionContext(replacementSealed, sealedPosition, sealedThreat, {}, {}), 2)
local topologyCounters = FleeEscape.getCounters()
assertEquals(topologyCounters.boundedFleePlannerCalls > callsBeforeTopology, true,
	"topology identity change should permit immediate replanning")
assertEquals(topologyCounters.dirtyByTopologyChange > 0, true,
	"topology replacement should retain dirty-event attribution")

local socialJitterEntity = fleeEntity("wild:test:social-vector-jitter", 737)
socialJitterEntity.species = "TEST"
socialJitterEntity.ecology.conspecificAlarmSensitivity = 1
socialJitterEntity.runtimeState.targetEntityId = nil
socialJitterEntity.runtimeState.socialEscapeBias = { dx = -0.81, dy = 0.34 }
socialJitterEntity.runtimeState.socialEscapeBiasConfidence = 0.8
local socialPosition = { cellX = 2, cellY = 2 }
local socialOccupied = { [leftKey] = true, [rightKey] = true, [threatKey] = true }
local socialDetails = {
	[leftKey] = { currentOccupants = { B = {
		entityId = "B", moving = false, position = { cellX = 1, cellY = 2 }
	} }, destinationReservations = {} },
	[rightKey] = { currentOccupants = { C = {
		entityId = "C", moving = false, position = { cellX = 3, cellY = 2 }
	} }, destinationReservations = {} },
	[threatKey] = { currentOccupants = { D = {
		entityId = "D", moving = false, position = { cellX = 2, cellY = 3 }
	} }, destinationReservations = {} }
}
local function socialContext(entity)
	local bias = entity.runtimeState.socialEscapeBias
	local target = bias and (entity.runtimeState.socialEscapeBiasConfidence or 0) >= 0.2
		and { cellX = socialPosition.cellX - bias.dx * 3,
			cellY = socialPosition.cellY - bias.dy * 3 } or nil
	return {
		executionOnly = true,
		currentFear = entity.runtimeState.fearCurrent or 0,
		position = socialPosition,
		targetPositions = {},
		threatAssessment = { primaryThreatId = nil, primaryThreatReason = "NONE" },
		socialAlarmTargetPosition = target,
		occupiedCells = socialOccupied,
		occupancyDetails = socialDetails,
		worldSemantics = boundary,
		mapId = boundary.mapId,
		fleeSafetyDistance = 8,
		fleeNeighbors = {}
	}
end
local jitterVectors = {
	{ dx = -0.81, dy = 0.34 }, { dx = -0.80, dy = 0.35 },
	{ dx = -0.79, dy = 0.36 }, { dx = -0.82, dy = 0.33 },
	{ dx = -0.80, dy = 0.34 }
}
local function integrateSocial(entity, tick, vector, sourceId)
	Fear.update(entity, {
		threatAssessment = { primaryThreatId = nil },
		socialSources = { {
			id = sourceId, species = entity.species,
			alarmOutput = 0.9, alarmGroundedness = 1,
			state = "FLEE", distance = 1, escapeBias = vector
		} },
		perceptionRadius = 5
	}, tick)
end
FleeEscape.resetCounters()
Fear.resetCounters()
local fearIntegrations = 0
local legacyThreatCell, legacyDirtyEvents = nil, 0
local lastSocialSource, socialSourceChanges = nil, 0
for tick = 1, 300 do
	if tick == 1 or (tick - 1) % 3 == 0 then
		local updateIndex = math.floor((tick - 1) / 3) + 1
		local sourceId = updateIndex % 2 == 0 and "source-b" or "source-a"
		integrateSocial(socialJitterEntity, tick,
			jitterVectors[(updateIndex - 1) % #jitterVectors + 1],
			sourceId)
		if lastSocialSource and lastSocialSource ~= sourceId then
			socialSourceChanges = socialSourceChanges + 1
		end
		lastSocialSource = sourceId
		fearIntegrations = fearIntegrations + 1
		local target = socialContext(socialJitterEntity).socialAlarmTargetPosition
		local exactCell = tostring(target.cellX) .. "," .. tostring(target.cellY)
		if legacyThreatCell and legacyThreatCell ~= exactCell then
			legacyDirtyEvents = legacyDirtyEvents + 1
		end
		legacyThreatCell = exactCell
	end
	Controller.executeCurrentIntent(socialJitterEntity,
		socialContext(socialJitterEntity), tick)
end
local socialJitterCounters = FleeEscape.getCounters()
assertEquals(socialJitterEntity.runtimeState.state, "FLEE",
	"social-vector jitter must not end FLEE")
assertEquals(socialJitterEntity.runtimeState.targetEntityId, nil,
	"social-only jitter must not invent a threat target")
assertEquals(socialJitterEntity.runtimeState.escapeReference.kind,
	"SOCIAL_ESCAPE_VECTOR", "social-only jitter must retain its aggregate reference")
assertEquals(legacyDirtyEvents >= 95, true,
	"exact projected-target comparison should reproduce cadence-coupled dirtiness")
assertEquals(socialJitterCounters.boundedFleePlannerCalls <= 2, true,
	"same-cardinal social jitter should plan only initially/watchdog")
assertEquals(socialJitterCounters.dirtyBySocialVector, 0,
	"same-cardinal social jitter should not dirty bounded planning")
assertEquals(socialJitterCounters.socialVectorUpdatesIgnoredAsEquivalent >= 95, true,
	"raw jitter and source churn should be counted as navigation-equivalent")
assertEquals(socialSourceChanges, 99,
	"source membership should churn while aggregate navigation remains equivalent")
assertEquals(Fear.getCounters().fearUpdates, fearIntegrations,
	"live-equivalent workload should retain normal Fear integration updates")

local callsBeforeSocialTurn = socialJitterCounters.boundedFleePlannerCalls
integrateSocial(socialJitterEntity, 301, { dx = 0, dy = -1 }, "source-north")
Controller.executeCurrentIntent(socialJitterEntity,
	socialContext(socialJitterEntity), 301)
local socialTurnCounters = FleeEscape.getCounters()
assertEquals(socialTurnCounters.dirtyBySocialVector, 1,
	"WEST-to-NORTH social instruction should dirty planning immediately")
assertEquals(socialTurnCounters.boundedFleePlannerCalls, callsBeforeSocialTurn + 1,
	"material social direction change should justify exactly one new plan")
assertEquals(socialJitterEntity.runtimeState.fleeExecution.lastPlanningDirtyReason,
	"SocialVectorChange", "material turn should expose its exact promotion cause")

local callsBeforeCueLoss = socialTurnCounters.boundedFleePlannerCalls
socialJitterEntity.runtimeState.socialEscapeBias = nil
socialJitterEntity.runtimeState.socialEscapeBiasConfidence = 0
Controller.executeCurrentIntent(socialJitterEntity,
	socialContext(socialJitterEntity), 302)
local cueLossCounters = FleeEscape.getCounters()
assertEquals(cueLossCounters.dirtyBySocialVector, 2,
	"social cue disappearance should dirty planning immediately")
assertEquals(cueLossCounters.boundedFleePlannerCalls, callsBeforeCueLoss + 1,
	"cue disappearance should justify one new planning attempt")
assertEquals(socialJitterEntity.runtimeState.targetEntityId, nil,
	"cue disappearance must remain targetless")

local callsBeforeCueActivation = cueLossCounters.boundedFleePlannerCalls
socialJitterEntity.runtimeState.socialEscapeBias = { dx = -1, dy = 0 }
socialJitterEntity.runtimeState.socialEscapeBiasConfidence = 0.8
Controller.executeCurrentIntent(socialJitterEntity,
	socialContext(socialJitterEntity), 303)
local cueActivationCounters = FleeEscape.getCounters()
assertEquals(cueActivationCounters.dirtyBySocialVector, 3,
	"social cue activation should dirty planning immediately")
assertEquals(cueActivationCounters.boundedFleePlannerCalls,
	callsBeforeCueActivation + 1,
	"cue activation should justify one new planning attempt")
assertEquals(socialJitterEntity.runtimeState.escapeReference.kind,
	"SOCIAL_ESCAPE_VECTOR", "reactivated cue should restore social reference")
assertEquals(socialJitterEntity.runtimeState.targetEntityId, nil,
	"reactivated social cue must remain targetless")
print(string.format(
	"SOCIAL_VECTOR_JITTER ticks=300 fearIntegrations=%d legacyExactDirty=%d legacyPlannerCalls=%d plannerCalls=%d sourceChanges=%d observed=%d material=%d equivalent=%d socialDirty=%d",
	fearIntegrations, legacyDirtyEvents, legacyDirtyEvents + 1,
	socialJitterCounters.boundedFleePlannerCalls,
	socialSourceChanges,
	socialJitterCounters.socialVectorUpdatesObserved,
	socialJitterCounters.socialVectorUpdatesMaterial,
	socialJitterCounters.socialVectorUpdatesIgnoredAsEquivalent,
	socialJitterCounters.dirtyBySocialVector))
print(string.format(
	"SOCIAL_VECTOR_MATERIAL turnPlannerDelta=1 cueLossPlannerDelta=1 cueActivationPlannerDelta=1 socialDirty=%d target=%s reference=%s",
	cueActivationCounters.dirtyBySocialVector,
	tostring(socialJitterEntity.runtimeState.targetEntityId or "none"),
	tostring(socialJitterEntity.runtimeState.escapeReference.kind)))

local waitingSocial = fleeEntity("wild:test:social-waiting-turn", 739)
waitingSocial.runtimeState.targetEntityId = nil
waitingSocial.runtimeState.socialEscapeBias = { dx = 0, dy = -1 }
waitingSocial.runtimeState.socialEscapeBiasConfidence = 0.8
local function waitingSocialContext(occupied, details)
	local bias = waitingSocial.runtimeState.socialEscapeBias
	return {
		executionOnly = true, currentFear = 0.7, position = dirtyPosition,
		targetPositions = {}, threatAssessment = { primaryThreatId = nil },
		socialAlarmTargetPosition = bias and {
			cellX = dirtyPosition.cellX - bias.dx * 3,
			cellY = dirtyPosition.cellY - bias.dy * 3
		} or nil,
		occupiedCells = occupied or {}, occupancyDetails = details or {},
		worldSemantics = boundary, mapId = boundary.mapId,
		fleeSafetyDistance = 8, fleeNeighbors = {}
	}
end
FleeEscape.resetCounters()
Controller.executeCurrentIntent(waitingSocial, waitingSocialContext(), 1)
local waitingSocialRoute = waitingSocial.runtimeState.fleeExecution.route
assertEquals(waitingSocialRoute ~= nil, true,
	"social NORTH fixture should establish a bounded detour route")
local waitingSocialAction = waitingSocialRoute.actions[waitingSocialRoute.index]
local waitingSocialKey = WorldSemantics.cellKey(
	waitingSocialAction.destination.cellX, waitingSocialAction.destination.cellY)
local waitingOccupancy = { [waitingSocialKey] = true }
local waitingDetails = { [waitingSocialKey] = {
	currentOccupants = { moving = {
		entityId = "moving", moving = true,
		position = waitingSocialAction.destination,
		destination = { cellX = dirtyPosition.cellX, cellY = dirtyPosition.cellY + 1 }
	} }, destinationReservations = {}
} }
Controller.executeCurrentIntent(waitingSocial,
	waitingSocialContext(waitingOccupancy, waitingDetails), 2)
assertEquals(waitingSocial.runtimeState.fleeExecution.planningState,
	"WAITING_FOR_ROUTE_CELL", "moving-away blocker should suspend the social route")
local callsBeforeWaitingTurn = FleeEscape.getCounters().boundedFleePlannerCalls
waitingSocial.runtimeState.socialEscapeBias = { dx = -1, dy = 0 }
Controller.executeCurrentIntent(waitingSocial,
	waitingSocialContext(waitingOccupancy, waitingDetails), 3)
local waitingTurnCounters = FleeEscape.getCounters()
assertEquals(waitingTurnCounters.dirtyBySocialVector, 1,
	"material social turn while waiting should have social-specific attribution")
assertEquals(waitingTurnCounters.boundedFleePlannerCalls,
	callsBeforeWaitingTurn + 1,
	"material social turn while waiting should replan without watchdog delay")

local repeatedlyBlockedFlee = fleeEntity("wild:test:repeated-route-release", 74)
forceFlee(repeatedlyBlockedFlee, boundary, { cellX = 2, cellY = 2 },
	{ cellX = 2, cellY = 3 }, 1)
local repeatedTick = 2
for release = 1, 3 do
	local execution = repeatedlyBlockedFlee.runtimeState.fleeExecution
	if not execution.route then
		forceFlee(repeatedlyBlockedFlee, boundary, { cellX = 2, cellY = 2 },
			{ cellX = 2, cellY = 3 }, repeatedTick)
		repeatedTick = repeatedTick + 1
		execution = repeatedlyBlockedFlee.runtimeState.fleeExecution
	end
	local route = execution.route
	local action = route.actions[route.index]
	local blockedKey = WorldSemantics.cellKey(
		action.destination.cellX, action.destination.cellY)
	forceFlee(repeatedlyBlockedFlee, boundary, { cellX = 2, cellY = 2 },
		{ cellX = 2, cellY = 3 }, repeatedTick, { [blockedKey] = true }, {
			[blockedKey] = {
				currentOccupants = {
					stationary = { entityId = "stationary", moving = false }
				},
				destinationReservations = {}
			}
		})
	assertEquals(repeatedlyBlockedFlee.runtimeState.state, "FLEE",
		"legitimate danger should keep FLEE selected after route release")
	assertEquals(repeatedlyBlockedFlee.runtimeState.intentEpisode.status, "ACTIVE",
		"failed escape routes must not mark the FLEE purpose failed")
	assertEquals(repeatedlyBlockedFlee.runtimeState.intentEpisode.failedAttempts, 0,
		"occupancy route releases must not weaken FLEE intent commitment")
	assertEquals(repeatedlyBlockedFlee.runtimeState.pendingOccupancyEpisodeFailure, nil,
		"FLEE route release should remain execution failure rather than intent failure")
	repeatedlyBlockedFlee.runtimeState.fleeExecution.recentDynamicBlockedBottlenecks = {}
	repeatedTick = repeatedTick + 1
end

local crowdLeft = fleeEntity("wild:test:crowd-left", 101)
local crowdRight = fleeEntity("wild:test:crowd-right", 202)
local crowdCenter = fleeEntity("wild:test:crowd-center", 303)
forceFlee(crowdLeft, boundary, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, 1, leftBlocked)
forceFlee(crowdRight, boundary, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, 1, { [rightKey] = true, [threatKey] = true })
forceFlee(crowdCenter, boundary, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, 1, allBlocked)
assertEquals(crowdLeft.runtimeState.movementRequest.direction, "RIGHT", "one crowded actor should peel toward its open side")
assertEquals(crowdRight.runtimeState.movementRequest.direction, "LEFT", "another crowded actor should peel toward its open side")
assertEquals(crowdCenter.runtimeState.movementRequest.direction, "STAY", "fully crowded actor should wait without deadlocking permanently")
forceFlee(crowdCenter, boundary, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, 2, leftBlocked)
assertEquals(crowdCenter.runtimeState.movementRequest.direction, "RIGHT", "waiting actor should peel away after another actor frees space")

-- Production evaluates visible actors sequentially. A WALK accepted for an
-- earlier actor reserves its destination while that actor is still moving;
-- every later actor must include that claimed cell in the same shared view.
local sharedReservations = {
	[WorldSemantics.cellKey(3, 1)] = true,
	[WorldSemantics.cellKey(3, 3)] = true
}
local firstGroupActor = fleeEntity("wild:test:group-first", 404)
forceFlee(firstGroupActor, open, { cellX = 3, cellY = 2 }, { cellX = 2, cellY = 2 }, 1, sharedReservations)
assertEquals(firstGroupActor.runtimeState.movementRequest.direction, "RIGHT", "highest-urgency actor should claim the directly-away cell")
sharedReservations[WorldSemantics.cellKey(
	firstGroupActor.runtimeState.movementRequest.destinationX,
	firstGroupActor.runtimeState.movementRequest.destinationY
)] = true

local secondGroupActor = fleeEntity("wild:test:group-second", 505)
forceFlee(secondGroupActor, open, { cellX = 3, cellY = 2 }, { cellX = 2, cellY = 2 }, 1, sharedReservations)
assertEquals(secondGroupActor.runtimeState.movementRequest.direction, "STAY", "later actor should wait when all non-threat exits are reserved")
assertEquals(secondGroupActor.runtimeState.movementRequest.destinationX == 4
	and secondGroupActor.runtimeState.movementRequest.destinationY == 2, false,
	"later actor must not request an earlier actor's in-progress destination")

sharedReservations[WorldSemantics.cellKey(4, 2)] = nil
forceFlee(secondGroupActor, open, { cellX = 3, cellY = 2 }, { cellX = 2, cellY = 2 }, 2, sharedReservations)
assertEquals(secondGroupActor.runtimeState.movementRequest.direction, "RIGHT", "a waiting or diverted actor should reclaim the best lane when its reservation clears")

local reversalMap = semantics("REVERSAL_REQUIRED", {
	"     ",
	".... ",
	"     "
})
local reversalEntity = fleeEntity("wild:test:required-reversal", 606)
reversalEntity.runtimeState.recentCommittedCells = {
	{ key = WorldSemantics.cellKey(1, 1), targetEntityId = "player" },
	{ key = WorldSemantics.cellKey(2, 1), targetEntityId = "player" }
}
reversalEntity.runtimeState.fleeExecution = {
	threatEntityId = "player",
	bestThreatDistance = 1,
	noProgressSteps = 0,
	escapeMode = false,
	fleeMode = "NORMAL",
	recentCells = {
		{ key = WorldSemantics.cellKey(1, 1), targetEntityId = "player" },
		{ key = WorldSemantics.cellKey(2, 1), targetEntityId = "player" }
	},
	previousCell = WorldSemantics.cellKey(1, 1)
}
forceFlee(reversalEntity, reversalMap, { cellX = 2, cellY = 1 }, { cellX = 3, cellY = 1 }, 3)
assertEquals(reversalEntity.runtimeState.movementRequest.direction, "LEFT", "reversal penalty must yield when the previous cell is the only viable escape")

local groupMap = semantics("GROUP_ESCAPE", {
	"...............",
	"...............",
	"...............",
	"...............",
	"...............",
	"...............",
	"..............."
})
local groupThreat = { cellX = 1, cellY = 3 }
local groupActors = {
	{ entity = fleeEntity("wild:test:long-a", 701), position = { cellX = 3, cellY = 2 }, origin = { cellX = 3, cellY = 2 }, history = {} },
	{ entity = fleeEntity("wild:test:long-b", 702), position = { cellX = 3, cellY = 3 }, origin = { cellX = 3, cellY = 3 }, history = {} },
	{ entity = fleeEntity("wild:test:long-c", 703), position = { cellX = 3, cellY = 4 }, origin = { cellX = 3, cellY = 4 }, history = {} }
}
for tick = 1, 10 do
	local occupied = { [WorldSemantics.cellKey(groupThreat.cellX, groupThreat.cellY)] = true }
	for _, actorState in ipairs(groupActors) do
		occupied[WorldSemantics.cellKey(actorState.position.cellX, actorState.position.cellY)] = true
	end
	local destinations = {}
	for _, actorState in ipairs(groupActors) do
		occupied[WorldSemantics.cellKey(actorState.position.cellX, actorState.position.cellY)] = nil
		Controller.tick(actorState.entity, { trust = 0, threatMemory = 80 }, 1, {
			hasTarget = true,
			purposefulTarget = true,
			targetEntityId = "player",
			threatAssessment = {
				primaryThreatId = "player",
				primaryThreatScore = 80,
				primaryThreatReason = "DIRECT_THREAT_MEMORY",
				primaryThreatDistance = 1
			},
			position = actorState.position,
			targetPositions = { player = groupThreat },
			occupiedCells = occupied,
			worldSemantics = groupMap,
			mapId = groupMap.mapId,
			fleeSafetyDistance = 12
		}, tick)
		local request = actorState.entity.runtimeState.movementRequest
		if request and request.traversalMode == "WALK" then
			local key = WorldSemantics.cellKey(request.destinationX, request.destinationY)
			assertEquals(occupied[key] == true, false, "production-style actors must not claim an existing reservation")
			occupied[key] = true
			destinations[actorState] = { cellX = request.destinationX, cellY = request.destinationY }
		end
	end
	for _, actorState in ipairs(groupActors) do
		if destinations[actorState] then
			actorState.position = destinations[actorState]
			actorState.entity.runtimeState.motion.justCompleted = true
		end
		actorState.history[#actorState.history + 1] = WorldSemantics.cellKey(actorState.position.cellX, actorState.position.cellY)
	end
end
for _, actorState in ipairs(groupActors) do
	local displacement = math.max(
		math.abs(actorState.position.cellX - actorState.origin.cellX),
		math.abs(actorState.position.cellY - actorState.origin.cellY)
	)
	assertEquals(displacement >= 4, true, "stationary-threat group should make sustained net escape progress")
	for index = 4, #actorState.history do
		local alternating = actorState.history[index] == actorState.history[index - 2]
			and actorState.history[index - 1] == actorState.history[index - 3]
		assertEquals(alternating, false, "stationary-threat group must not settle into a short ABAB cycle")
	end
end

local firstDirections = {}
local symmetricBoundary = semantics("SYMMETRIC_FLEE", {
	".......",
	"... ...",
	".......",
	".......",
	"......."
})
for index = 1, 12 do
	local entity = fleeEntity("wild:test:tie:" .. index, index * 17)
	forceFlee(entity, symmetricBoundary, { cellX = 3, cellY = 2 }, { cellX = 3, cellY = 3 }, 1)
	firstDirections[entity.runtimeState.movementRequest.direction] = true
end
assertEquals(firstDirections.LEFT == true and firstDirections.RIGHT == true, true, "stable per-entity tie breaking should distribute equivalent routes")

local movingThreatEntity = fleeEntity("wild:test:moving-threat", 8)
forceFlee(movingThreatEntity, boundary, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, 1)
local originalRoute = movingThreatEntity.runtimeState.fleeExecution.route
forceFlee(movingThreatEntity, boundary, { cellX = 2, cellY = 2 }, { cellX = 5, cellY = 3 }, 2)
assertEquals(movingThreatEntity.runtimeState.fleeExecution.routeInvalidationReason, "THREAT_MOVED", "substantial threat movement should invalidate the obsolete route")
assertEquals(movingThreatEntity.runtimeState.fleeExecution.route ~= originalRoute, true, "threat movement should force route reconsideration")

local mapChanged = semantics("BOUNDARY_FLEE_2", {
	".......",
	".. ...",
	".......",
	".......",
	"......."
})
local mapChangeEntity = fleeEntity("wild:test:map-change", 81)
forceFlee(mapChangeEntity, boundary, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, 1)
forceFlee(mapChangeEntity, mapChanged, { cellX = 2, cellY = 2 }, { cellX = 2, cellY = 3 }, 2)
assertEquals(mapChangeEntity.runtimeState.fleeExecution.routeInvalidationReason, "MAP_CHANGED", "map changes should invalidate runtime-only escape routes")

movingThreatEntity.runtimeState.state = "IDLE"
movingThreatEntity.runtimeState.stateEnteredTick = -100
Controller.tick(movingThreatEntity, {}, 8, {
	hasTarget = false,
	position = { cellX = 2, cellY = 2 },
	mapId = "BOUNDARY_FLEE"
}, 4)
assertEquals(movingThreatEntity.runtimeState.fleeExecution, nil, "ending FLEE should clear escape-route state")

local resetEntity = fleeEntity("wild:test:reset", 9)
resetEntity.runtimeState.fleeExecution = { route = { actions = {} }, fleeMode = "ESCAPE_ROUTE" }
RuntimeState.reset(resetEntity)
assertEquals(resetEntity.runtimeState.fleeExecution, nil, "runtime reset should clear bounded escape state")

return true