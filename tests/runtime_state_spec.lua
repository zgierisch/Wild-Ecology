local RuntimeState = require("src.core.runtime_state")

local entity = {
	id = "wild:test:runtime",
	personalitySeed = 847219,
	relationships = { player = { trust = 42 } },
	runtimeState = {
	fleeExecution = { escapeMode = true, noProgressSteps = 4 },
	recentCommittedCells = { { key = "1,1" } },
	motion = { active = true, destinationX = 99, destinationY = 99 },
	movementRequest = { direction = "RIGHT", traversalMode = "WALK" },
	rejectedMoves = { RIGHT = { mapId = "ROUTE_1", cellX = 6, cellY = 8 } },
	behaviorScores = { APPROACH = 80 },
	intentEpisode = { intent = "APPROACH", targetId = "ally", status = "ACTIVE" },
	recentSatisfiedIntent = "APPROACH",
	recentSatisfiedTarget = "ally",
	recentSatisfactionTick = 30,
	intentMetrics = { intentSwitches = 7, purposefulIntentStarts = 2 },
	perceptionContacts = { player = true },
	flockSearch = { isolationSinceTick = 10, sightings = { ally = { tick = 8 } } },
	flockSearchDestination = { cellX = 4, cellY = 4 },
	navigation = {
		route = { actions = { { mode = "WALK", direction = "RIGHT" } }, index = 1 },
		waypoint = { cellX = 8, cellY = 8 },
		currentTraversalAction = { mode = "WALK" },
		plannerWorkingState = { frontier = {} },
		replanReason = "TEST"
	}
	}
}

local persistentId = entity.id
local persistentSeed = entity.personalitySeed
local persistentPlayerRelationship = entity.relationships.player

local reset = RuntimeState.reset(entity)
if reset == nil then
	error("runtime state reset should return the new state")
end
if reset.motion.active ~= false then
	error("runtime reset should clear active motion")
end
if reset.fleeExecution ~= nil or reset.recentCommittedCells ~= nil then
	error("runtime reset should discard transient flee navigation state")
end
if reset.movementRequest ~= nil then
	error("runtime reset should clear movement requests")
end
if next(reset.rejectedMoves) ~= nil then
	error("runtime reset should clear rejection memory")
end
if reset.behaviorScores ~= nil or reset.perceptionContacts ~= nil then
	error("runtime reset should discard avatar-only execution state")
end
if reset.intentEpisode ~= nil or reset.recentSatisfiedIntent ~= nil
		or reset.recentSatisfiedTarget ~= nil or reset.recentSatisfactionTick ~= nil
		or reset.intentMetrics ~= nil then
	error("runtime reset should discard transient intent episodes, satisfaction, and metrics")
end
if reset.flockSearch ~= nil or reset.flockSearchDestination ~= nil then
	error("runtime reset should discard transient isolation and flock-search execution state")
end
if reset.navigation ~= nil then
	error("runtime reset should discard route, waypoint, traversal action, planner work, and replan bookkeeping")
end
if entity.id ~= persistentId or entity.personalitySeed ~= persistentSeed then
	error("runtime reset must preserve persistent identity")
end
if entity.relationships.player ~= persistentPlayerRelationship then
	error("runtime reset must preserve persistent relationships")
end

local secondReset = RuntimeState.reset(entity)
if not secondReset.motion or secondReset.motion.active ~= false
		or not secondReset.rejectedMoves or next(secondReset.rejectedMoves) ~= nil then
	error("runtime reset should be idempotent")
end

return true