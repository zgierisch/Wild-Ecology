local SpatialGoal = require("src.behavior.spatial_goal")
local Steering = require("src.behavior.steering")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local goal = SpatialGoal.resolve("player", {
	player = { cellX = 5, cellY = 3 }
}, 1, { alignment = "CARDINAL" })
if not goal then
	error("target position should resolve into a proximity goal")
end
assertEquals(goal.kind, "PROXIMITY", "resolved target should create a proximity goal")
assertEquals(SpatialGoal.isSatisfied(goal, { cellX = 4, cellY = 3 }), true, "goal should accept positions inside its radius")
assertEquals(SpatialGoal.isSatisfied(goal, { cellX = 4, cellY = 2 }), false, "goal should reject diagonal settling")
assertEquals(SpatialGoal.isSatisfied(goal, { cellX = 5, cellY = 3 }), false, "goal should reject occupying the target cell")
local observationGoal = SpatialGoal.resolve("player", {
	player = { cellX = 5, cellY = 3 }
}, 3, { alignment = "ANY" })
assertEquals(SpatialGoal.isSatisfied(observationGoal, { cellX = 4, cellY = 2 }), true, "generic proximity should allow diagonal observation")
assertEquals(SpatialGoal.isSatisfied(observationGoal, { cellX = 2, cellY = 3 }), true, "investigate range should allow a wider same-row observation")

local fleeGoal = SpatialGoal.resolve("player", {
	player = { cellX = 5, cellY = 3 }
}, 4, { objective = "AWAY" })
assertEquals(SpatialGoal.isSatisfied(fleeGoal, { cellX = 1, cellY = 3 }), true, "flee goal should be satisfied outside its radius")
local fleeRequest = Steering.request({ cellX = 4, cellY = 3 }, fleeGoal)
assertEquals(fleeRequest.direction, "LEFT", "flee steering should choose a step away from the target")

local request = Steering.request({ cellX = 1, cellY = 3 }, goal)
assertEquals(request.direction, "RIGHT", "steering should rank the best direction without collision speculation")
assertEquals(request.traversalMode, "WALK", "steering should return an ordinary walk request")
assertEquals(request.targetEntityId, "player", "movement request should retain the dynamic target ID")
assertEquals(request.rankedDirections[1], "RIGHT", "steering should expose ranked directions")

local filtered = Steering.request({ cellX = 1, cellY = 3 }, goal, {
	rejectedDirections = { RIGHT = true }
})
assertEquals(filtered.direction, "UP", "steering should deprioritize locally rejected directions")

local directBlocked = Steering.request({ cellX = 1, cellY = 3 }, goal, {
	rejectedDirections = { RIGHT = true },
	directOnly = true
})
assertEquals(directBlocked.direction, "STAY", "direct-only steering should not route around a blocked adjacent destination")
assertEquals(directBlocked.reason, "NO_LEGAL_STEP", "direct-only steering should expose blocked completion to the controller")

local blockedFlee = Steering.request({ cellX = 4, cellY = 3 }, fleeGoal, {
	rejectedDirections = { LEFT = true }
})
assertEquals(blockedFlee.direction == "UP" or blockedFlee.direction == "DOWN", true, "blocked direct escape should choose a lateral step")

local escapeFlee = Steering.request({ cellX = 4, cellY = 3 }, fleeGoal, {
	escapeMode = true,
	recentCells = {
		{ key = "4,3" },
		{ key = "4,2" },
		{ key = "4,3" }
	},
	rejectedDirections = { LEFT = true }
})
assertEquals(escapeFlee.direction, "DOWN", "escape steering should prefer an unvisited lateral cell over immediate reversal")

local Environment = require("src.world.environment")
local deferred = Environment.evaluateTraversal({}, "ROUTE_1", 1, 3, 2, 3, "RIGHT", {}, true)
assertEquals(deferred.allowed, true, "available tryMove executor should allow a deferred WALK request")
assertEquals(deferred.collisionDeferredToExecutor, true, "collision should remain authoritative in tryMove")

local unavailable = Environment.evaluateTraversal({}, "ROUTE_1", 1, 3, 2, 3, "RIGHT", {}, false)
assertEquals(unavailable.allowed, false, "missing movement executor should reject movement")
assertEquals(unavailable.reason, "COLLISION_UNAVAILABLE", "missing movement executor should expose its reason")

local satisfied = Steering.request({ cellX = 4, cellY = 3 }, goal, {
	evaluateTraversal = function()
		return { allowed = true, traversalMode = "WALK" }
	end
})
assertEquals(satisfied.traversalMode, "NONE", "satisfied goals should not claim to walk")
assertEquals(satisfied.reason, "GOAL_SATISFIED", "satisfied goals should expose why they stayed")

local requestedDirection = nil
local collisionCalls = 0
local collision = {
	canMove = function(_, _, _, direction)
		collisionCalls = collisionCalls + 1
		requestedDirection = direction
		return true
	end,
	target = function(x, y, _direction)
		return x + 1, y
	end
}
package.preload["src.world.Collision"] = function()
	return collision
end
local AvatarFactory = require("src.world.avatar_factory")
local avatar = {
	id = "ROUTE_1_obj_1",
	handle = {
		npc = { cellX = 1, cellY = 3, moving = false },
		ow = {
			map = {},
			entities = {}
		}
	}
}
local entity = {
	runtimeState = { movementRequest = request }
}
assertEquals(AvatarFactory.applyMovementRequest({}, avatar, entity), true, "movement request should cross through the avatar adapter")
assertEquals(requestedDirection, "right", "adapter should call the collision-aware movement seam with a normalized direction")
assertEquals(entity.runtimeState.motion.active, true, "successful movement should mark motion active")
avatar.handle.npc.moving = false
avatar.handle.npc.cellX = 2
avatar.handle.npc.cellY = 3
entity.runtimeState.movementRequest = {
	 direction = "STAY",
	 traversalMode = "NONE",
	 reason = "GOAL_SATISFIED"
}
assertEquals(AvatarFactory.applyMovementRequest({}, avatar, entity), false, "completed movement should not issue a new NONE request")
assertEquals(entity.runtimeState.motion.active, false, "completion callback should clear active motion")
assertEquals(avatar.movementRequest.direction, "RIGHT", "adapter should record the direction that actually succeeded")
assertEquals(avatar.movementRequest.traversalMode, "WALK", "adapter should preserve traversal mode")

local scriptMoveCalled = false
local noTraversalAvatar = {
	handle = {
		npc = {},
		ow = { map = {}, entities = {} },
		scriptMove = function()
			scriptMoveCalled = true
		end
	}
}
local noTraversalEntity = {
	runtimeState = { movementRequest = {
		direction = "UP",
		traversalMode = "NONE"
	} }
}
assertEquals(AvatarFactory.applyMovementRequest({}, noTraversalAvatar, noTraversalEntity), false, "NONE requests should not execute movement")
assertEquals(scriptMoveCalled, false, "adapter should not fall back to scriptMove")

local busyEntity = {
	runtimeState = {
		motion = { active = true },
		movementRequest = request
	}
}
assertEquals(AvatarFactory.applyMovementRequest({}, avatar, busyEntity), false, "active motion should suppress duplicate requests")
assertEquals(busyEntity.runtimeState.motion.active, true, "duplicate request should preserve active motion")

local orphanedEntity = {
	runtimeState = {
		motion = { active = true, destinationX = 9, destinationY = 9 }
	}
}
local orphanedAvatar = { handle = {} }
assertEquals(AvatarFactory.refreshMotionState({}, orphanedAvatar, orphanedEntity), true, "missing NPC context should clear stale motion")
assertEquals(orphanedEntity.runtimeState.motion.active, false, "missing NPC context should not leave the latch active")

local mismatchedEntity = {
	runtimeState = {
		motion = { active = true, destinationX = 99, destinationY = 99 }
	}
}
local mismatchedAvatar = {
	handle = {
		npc = { cellX = 2, cellY = 2, moving = false },
		ow = { map = {}, entities = {} }
	}
}
assertEquals(AvatarFactory.refreshMotionState({}, mismatchedAvatar, mismatchedEntity), true, "non-moving NPC with stale destination should clear motion")
assertEquals(mismatchedEntity.runtimeState.motion.active, false, "destination mismatch should not leave motion latched")

local completedEntity = {
	runtimeState = {
		state = "IDLE",
		stateEnteredTick = -40,
		motion = { active = false, justCompleted = true },
		targetDestination = { id = "target_right", cellX = 8, cellY = 4 },
		targetCounter = 3
	}
}
local completedState, _ = require("src.behavior.controller").tick(completedEntity, {}, nil, {
	position = { cellX = 7, cellY = 4 },
	mapId = "ROUTE_1"
}, 12)
assertEquals(completedState, "SETTLED", "completed target step should discharge restlessness and settle")
assertEquals(completedEntity.runtimeState.motion.justCompleted, false, "completed step marker should be consumed")
assertEquals(completedEntity.runtimeState.targetCounter, 3,
	"settling should not create another ambient destination immediately")
assertEquals(completedEntity.runtimeState.movementRequest, nil,
	"settling after ambient travel should queue no additional step")

local completedAmbientEntity = {
	id = "wild:test:completed-ambient",
	temperament = { curiosity = 0, sociability = 0 },
	runtimeState = {
		state = "TARGET",
		stateEnteredTick = -20,
		targetDestination = { id = "target_up", cellX = 2, cellY = 22 },
		motion = { active = false, justCompleted = true }
	}
}
require("src.behavior.controller").tick(completedAmbientEntity, {}, nil, {
	position = { cellX = 2, cellY = 22 },
	mapId = "ROUTE_1"
}, 10)
assertEquals(completedAmbientEntity.runtimeState.state, "SETTLED", "successful ambient step should finish in passive equilibrium")
assertEquals(completedAmbientEntity.runtimeState.targetDestination, nil, "successful ambient step should consume its destination")

local blockedAmbientEntity = {
	id = "wild:test:blocked-ambient",
	temperament = { curiosity = 0, sociability = 0 },
	runtimeState = {
		state = "TARGET",
		stateEnteredTick = -20,
		targetDestination = { id = "target_right", cellX = 9, cellY = 8 },
		movementRequest = {
			direction = "RIGHT",
			traversalMode = "WALK",
			rejectionReason = "tile"
		},
		motion = { active = false }
	}
}
require("src.behavior.controller").tick(blockedAmbientEntity, {}, nil, {
	position = { cellX = 8, cellY = 8 },
	mapId = "ROUTE_1"
}, 10)
assertEquals(blockedAmbientEntity.runtimeState.state, "IDLE", "blocked ambient step should finish its wander episode")
assertEquals(blockedAmbientEntity.runtimeState.targetDestination, nil, "blocked ambient step should abandon its destination")
assertEquals(blockedAmbientEntity.runtimeState.movementRequest, nil, "blocked ambient step should not route around toward the synthetic cell")

local reentryEntity = {
	id = "wild:test:ambient-reentry",
	temperament = { curiosity = 1 },
	runtimeState = {
		state = "TARGET",
		stateEnteredTick = -20,
		targetDestination = { id = "target_up", cellX = 2, cellY = 22 },
		motion = { active = false }
	}
}
require("src.behavior.controller").tick(reentryEntity, {}, 4, {
	hasTarget = true,
	purposefulTarget = true,
	targetEntityId = "friend",
	position = { cellX = 2, cellY = 21 },
	targetPositions = { friend = { cellX = 4, cellY = 21 } },
	mapId = "ROUTE_1"
}, 20)
assertEquals(reentryEntity.runtimeState.targetDestination, nil, "leaving TARGET should clear its synthetic destination")
reentryEntity.runtimeState.state = "SETTLED"
reentryEntity.runtimeState.stateEnteredTick = -300
require("src.behavior.controller").tick(reentryEntity, {}, nil, {
	position = { cellX = 5, cellY = 5 },
	mapId = "ROUTE_1"
}, 21)
local freshDestination = reentryEntity.runtimeState.targetDestination
local freshDistance = math.abs(freshDestination.cellX - 5) + math.abs(freshDestination.cellY - 5)
assertEquals(freshDistance, 1, "returning to TARGET should create a fresh destination adjacent to the live cell")
assertEquals(freshDestination.cellX == 2 and freshDestination.cellY == 22, false, "returning to TARGET must not reuse the old coordinate")

require("src.behavior.controller").tick(completedAmbientEntity, {}, nil, {
	position = { cellX = 2, cellY = 22 },
	mapId = "ROUTE_1"
}, 11)
assertEquals(completedAmbientEntity.runtimeState.state, "SETTLED", "consumed destination should not immediately restart TARGET")
assertEquals(completedAmbientEntity.runtimeState.goalSatisfied, false, "consumed destination should not remain as a satisfied ambient goal")

local cyclingEntity = {
	id = "wild:test:cycling",
	temperament = { curiosity = 1 },
	relationships = { friend = { trust = 100, affinity = 100, familiarity = 100 } },
	runtimeState = {
		state = "APPROACH",
		stateEnteredTick = 0,
		targetEntityId = "friend",
		motion = { active = false }
	}
}
local cyclePositions = {
	{ cellX = 17, cellY = 2 },
	{ cellX = 17, cellY = 3 },
	{ cellX = 17, cellY = 2 },
	{ cellX = 17, cellY = 3 }
}
for index, cyclePosition in ipairs(cyclePositions) do
	cyclingEntity.runtimeState.motion.justCompleted = true
	require("src.behavior.controller").tick(cyclingEntity, cyclingEntity.relationships.friend, 5, {
		hasTarget = true,
		purposefulTarget = true,
		targetEntityId = "friend",
		candidates = { { id = "friend", distance = 5 } },
		position = cyclePosition,
		targetPositions = { friend = { cellX = 20, cellY = 2 } },
		mapId = "ROUTE_1"
	}, 40 + index)
end
assertEquals(cyclingEntity.runtimeState.navigationAvoidTargetId, "friend", "ABAB movement cycle should suppress the trapped target")
assertEquals(cyclingEntity.runtimeState.state, "IDLE", "cycle escape should abandon the entity-directed behavior")

local fleeingEntity = {
	id = "wild:test:flee-cycle",
	temperament = { boldness = 0 },
	runtimeState = {
		state = "FLEE",
		stateEnteredTick = 0,
		targetEntityId = "player",
		motion = { active = false }
	}
}
local fleeCyclePositions = {
	{ cellX = 8, cellY = 6 },
	{ cellX = 8, cellY = 7 },
	{ cellX = 8, cellY = 6 },
	{ cellX = 8, cellY = 7 }
}
for index, cyclePosition in ipairs(fleeCyclePositions) do
	fleeingEntity.runtimeState.motion.justCompleted = true
	require("src.behavior.controller").tick(fleeingEntity, { trust = 0, threatMemory = 20 }, 1, {
		hasTarget = true,
		purposefulTarget = true,
		targetEntityId = "player",
		threatAssessment = {
			primaryThreatId = "player",
			primaryThreatReason = "DIRECT_THREAT_MEMORY",
			primaryThreatDistance = 1
		},
		position = cyclePosition,
		targetPositions = { player = { cellX = 8, cellY = 8 } },
		mapId = "ROUTE_1"
	}, 60 + index)
end
assertEquals(fleeingEntity.runtimeState.state, "FLEE", "FLEE cycle detection must keep the threat behavior active")
assertEquals(fleeingEntity.runtimeState.fleeExecution.escapeMode, true, "FLEE ABAB cycle should enter obstacle escape mode")
assertEquals(fleeingEntity.runtimeState.navigationAvoidTargetId, nil, "FLEE cycle must not suppress the threat target")

fleeingEntity.runtimeState.motion.justCompleted = true
require("src.behavior.controller").tick(fleeingEntity, { trust = 0, threatMemory = 20 }, 1, {
	hasTarget = true,
	purposefulTarget = true,
	targetEntityId = "player",
	threatAssessment = {
		primaryThreatId = "player",
		primaryThreatReason = "DIRECT_THREAT_MEMORY",
		primaryThreatDistance = 1
	},
	position = { cellX = 8, cellY = 4 },
	targetPositions = { player = { cellX = 8, cellY = 8 } },
	mapId = "ROUTE_1"
}, 65)
assertEquals(fleeingEntity.runtimeState.fleeExecution.escapeMode, false, "increasing threat distance should restore normal FLEE steering")
assertEquals(fleeingEntity.runtimeState.fleeExecution.noProgressSteps, 0, "escape recovery should clear no-progress count")

-- The direction picker previously cycled through the same 4 headings in a
-- fixed order every time (an "L shaped" loop that always returns near its
-- start). Simulate many completed steps and confirm real ground gets
-- covered instead of oscillating in a tiny fixed box.
local Controller = require("src.behavior.controller")
local wanderer = {
	id = "wild:test:wanderer",
	personalitySeed = 42,
	runtimeState = { state = "TARGET", stateEnteredTick = 0, motion = { active = false } }
}
local wanderPosition = { cellX = 0, cellY = 0 }
for step = 1, 20 do
	wanderer.runtimeState.motion.active = false
	wanderer.runtimeState.state = "TARGET"
	wanderer.runtimeState.stateEnteredTick = 20 + step
	wanderer.runtimeState.targetDestination = nil
	Controller.tick(wanderer, {}, nil, {
		position = wanderPosition,
		mapId = "ROUTE_1"
	}, 20 + step)
	local destination = wanderer.runtimeState.targetDestination
	wanderPosition = { cellX = destination.cellX, cellY = destination.cellY }
end
local netDisplacement = math.abs(wanderPosition.cellX) + math.abs(wanderPosition.cellY)
assertEquals(netDisplacement > 2, true, "ambient wandering should cover real ground instead of looping in a tiny fixed box")

-- Weak directional alignment (Phase 6): a groupHeadingBias should nudge
-- ambient wandering toward the trusted group's recent heading over many
-- steps, without hard-locking the individual to it (momentum still wins
-- most rerolls). Compare net rightward drift with vs. without a strong
-- rightward bias, using a different personality seed than the test above
-- so this is an independent sample.
local function simulateWander(personalitySeed, groupHeadingBias)
	local entity = {
		id = "wild:test:aligning-wanderer",
		personalitySeed = personalitySeed,
		runtimeState = { state = "TARGET", stateEnteredTick = 0, motion = { active = false } }
	}
	local position = { cellX = 0, cellY = 0 }
	for step = 1, 40 do
		entity.runtimeState.motion.active = false
		entity.runtimeState.state = "TARGET"
		entity.runtimeState.stateEnteredTick = 100 + step
		entity.runtimeState.targetDestination = nil
		Controller.tick(entity, {}, nil, {
			position = position,
			mapId = "ROUTE_1",
			groupHeadingBias = groupHeadingBias
		}, 100 + step)
		local destination = entity.runtimeState.targetDestination
		position = { cellX = destination.cellX, cellY = destination.cellY }
	end
	return position
end

local unbiasedPosition = simulateWander(7, nil)
local biasedPosition = simulateWander(7, { dx = 1, dy = 0 })
assertEquals(biasedPosition.cellX > unbiasedPosition.cellX, true, "a strong rightward group heading bias should drift wandering further right than no bias")

-- Bug: an entity that reaches (satisfies) an APPROACH goal never left that
-- state again, since trust/affinity don't decay and kept out-scoring
-- everything else -- Pokemon would move toward a friend once, then freeze
-- there permanently. Simulate arriving right next to a friend and confirm
-- restlessness eventually breaks the parked APPROACH.
local Controller2 = require("src.behavior.controller")
local arrivedEntity = {
	id = "wild:test:arrived-approach",
	temperament = { curiosity = 0 }
}
local arrivedRelationship = { trust = 80, affinity = 60, threatMemory = 0, hostility = 0 }
local approachPosition = { cellX = 0, cellY = 0 }
local targetPositions = { ["wild:test:friend"] = { cellX = 1, cellY = 0 } }
Controller2.tick(arrivedEntity, arrivedRelationship, 1, {
	targetEntityId = "wild:test:friend",
	hasTarget = true,
	purposefulTarget = true,
	position = approachPosition,
	targetPositions = targetPositions,
	mapId = "ROUTE_1"
}, 1)
assertEquals(arrivedEntity.runtimeState.state, "SETTLED",
	"an already-adjacent friend should satisfy social context without APPROACH")
assertEquals(arrivedEntity.runtimeState.spatialGoal, nil,
	"acceptable social proximity should create no spatial objective")

local stayedSettled = true
for tick = 2, 80 do
	local state = Controller2.tick(arrivedEntity, arrivedRelationship, 1, {
		targetEntityId = "wild:test:friend",
		hasTarget = true,
		purposefulTarget = true,
		position = approachPosition,
		targetPositions = targetPositions,
		mapId = "ROUTE_1"
	}, tick)
	if state ~= "SETTLED" then stayedSettled = false end
end
assertEquals(stayedSettled, true,
	"high affinity should not create a repeated nearby pursuit loop")
assertEquals(arrivedEntity.runtimeState.movementRequest, nil,
	"settled social proximity should emit no movement request")

collision.canMove = function(_, _, _, direction)
	collisionCalls = collisionCalls + 1
	requestedDirection = direction
	return false, "tile"
end
local blockedEntity = {
	runtimeState = {
		simulationTick = 20,
		movementRequest = request
	}
}
local blockedAvatar = {
	handle = {
		npc = { cellX = 7, cellY = 4, moving = false },
		ow = { map = { id = "ROUTE_1" }, entities = {} }
	}
}
local callsBeforeBlocked = collisionCalls
assertEquals(AvatarFactory.applyMovementRequest({}, blockedAvatar, blockedEntity), false, "blocked movement should return without moving")
assertEquals(collisionCalls, callsBeforeBlocked + 1, "one locomotion opportunity should make one collision attempt")
assertEquals(blockedEntity.runtimeState.rejectedMoves.RIGHT.mapId, "ROUTE_1", "rejection should record its map")
assertEquals(blockedEntity.runtimeState.rejectedMoves.RIGHT.cellX, 7, "rejection should record its source cell")

local scopedRequest = Steering.request({ cellX = 7, cellY = 4 }, goal, {
	rejectedDirections = blockedEntity.runtimeState.rejectedMoves,
	mapId = "ROUTE_1"
})
assertEquals(scopedRequest.direction ~= "RIGHT", true, "same-cell stable rejection should be suppressed")
local newCellRequest = Steering.request({ cellX = 7, cellY = 5 }, goal, {
	rejectedDirections = blockedEntity.runtimeState.rejectedMoves,
	mapId = "ROUTE_1"
})
local rightStillRanked = false
for _, direction in ipairs(newCellRequest.rankedDirections or {}) do
	if direction == "RIGHT" then
		rightStillRanked = true
	end
end
assertEquals(rightStillRanked, true, "rejection should not suppress the direction from a new cell")

return true