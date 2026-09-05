local Config = require("src.core.config")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function assertAtLeast(actual, minimum, message)
	if actual < minimum then
		error((message or "assertAtLeast failed") .. ": expected >= " .. tostring(minimum) .. ", got " .. tostring(actual))
	end
end

local function unloadModule(name)
	package.loaded[name] = nil
end

unloadModule("main")
unloadModule("src.core.save")
unloadModule("src.population.manager")
unloadModule("src.world.avatar_factory")
unloadModule("src.behavior.controller")

local storedState = nil
local currentMapId = Config.phase0.testMapId
local spawnCalls = {}
local removeCalls = {}
local handlesById = {}
local nextNpcSerial = 0
local writtenLog = ""

local mod = {
	storage = {
		read = function(_, _game, _key)
			return storedState, storedState == nil and "not_found" or nil
		end,
		write = function(_, _game, _key, value)
			storedState = value
			return true
		end,
		writeBytes = function(_, _game, key, bytes)
			if key == "wildecology_log" then
				writtenLog = bytes
			end
			return true
		end
	},
	game = {},
	world = {
		current = function(_)
			return { mapId = currentMapId, x = 1, y = 1 }
		end,
		spawnNpc = function(_, mapId, objDef)
			nextNpcSerial = nextNpcSerial + 1
			local npcId = mapId .. "_obj_" .. tostring(nextNpcSerial)
			spawnCalls[#spawnCalls + 1] = { mapId = mapId, objDef = objDef, npcId = npcId }
			return npcId
		end,
		npc = function(_, _mapId, npcId)
			handlesById[npcId] = handlesById[npcId] or {}
			return handlesById[npcId]
		end,
		removeNpc = function(_, npcId)
			removeCalls[#removeCalls + 1] = npcId
			return true
		end
	},
	options = {
		define = function(_, _rows)
			return nil
		end,
		get = function(_, key)
			if key == "phase0_behavior_mode" then
				return "normal"
			end
			return nil
		end
	},
	save = {
		get = function(_, key, default)
			local overrides = {
				phase0_debug_log = false,
				dev_log_view = "both",
				dev_log_lifecycle = true,
				dev_log_behavior = true,
				dev_log_relationships = true,
				dev_log_console = true
			}
			local value = overrides[key]
			if value == nil then
				return default
			end
			return value
		end,
		set = function() end
	}
}

local entry = require("main")
local WildEcology = entry(mod)
if not WildEcology then
	error("main entry should return WildEcology module API")
end

WildEcology.init(mod)
local Save = require("src.core.save")
assertEquals(#spawnCalls, Config.phase3.visibleSubsetSize, "initial load on route should spawn the visible subset")

local occupiedRuntimeCells = {}
for index = 1, Config.phase3.visibleSubsetSize do
	local payload = spawnCalls[index]
	local cellKey = tostring(payload.objDef.x) .. ":" .. tostring(payload.objDef.y)
	assertEquals(occupiedRuntimeCells[cellKey] == nil, true, "spawned runtime avatars should not overlap")
	occupiedRuntimeCells[cellKey] = true
end

local firstSpawnNpcId = spawnCalls[1].npcId
local liveState = Save.getState()
if not liveState or not liveState.populations or not liveState.populations[Config.phase0.testMapId] then
	error("storage should include phase 0 route population after init")
end
local firstPopulation = liveState.populations[Config.phase0.testMapId]
if not firstPopulation.members then
	error("phase 0 route population should include members table")
end
local firstEntity = firstPopulation.members[Config.phase0.testEntityId]
if not firstEntity then
	error("phase 0 entity should exist after init")
end
firstEntity.runtimeState = {
	motion = { active = true, destinationX = 99, destinationY = 99 },
	movementRequest = { direction = "RIGHT", traversalMode = "WALK" },
	rejectedMoves = { RIGHT = { mapId = Config.phase0.testMapId, cellX = 6, cellY = 8 } }
}
assertEquals(WildEcology.movementClaims:publish({
	actorId = firstEntity.id,
	fromX = 1,
	fromY = 1,
	toX = 2,
	toY = 1,
	intent = "TARGET",
	urgency = 0
}, liveState.simulationTick), true, "materialized actor should publish a runtime-only claim")
assertEquals(storedState.movementClaims, nil,
	"movement claim index must never be attached to serialized save state")

local firstRelationship = firstEntity.relationships and firstEntity.relationships.player
if not firstRelationship then
	error("player relationship should exist after init")
end
local trustBeforeTransition = firstRelationship.trust
local firstRespawnCount = firstEntity.memory and firstEntity.memory.debug and firstEntity.memory.debug.respawnCount
assertEquals(firstRespawnCount, 1, "first spawn should record respawn count 1")

currentMapId = "PALLET_TOWN"
WildEcology.shutdown()
assertEquals(WildEcology.movementClaims:claimForActor(firstEntity.id), nil,
	"map shutdown should clear movement claims before runtime reconstruction")
assertEquals(#removeCalls, Config.phase3.visibleSubsetSize, "route exit shutdown should despawn the visible subset")
assertEquals(removeCalls[1], firstSpawnNpcId, "despawn should remove the previously spawned npc")
-- Despawn order is sorted by entity id (main.lua's WildEcology.shutdown),
-- so whichever avatar sorts last is deterministic given the visible-subset
-- selection (weighted-random), not necessarily the 2nd spawned one.
local lastDespawnedNpcId = removeCalls[#removeCalls]

local despawnDebugState = storedState.debug and storedState.debug.phase0
if not despawnDebugState then
	error("phase 0 debug verification state should persist after despawn")
end
assertEquals(despawnDebugState.lastEvent, "despawn", "debug state should record route exit despawn")
assertEquals(despawnDebugState.lastContextMapId, "PALLET_TOWN", "debug state should record the map where despawn was observed")
assertEquals(despawnDebugState.lastDespawnAvatarId, lastDespawnedNpcId, "debug state should record the previous despawned avatar id")

currentMapId = Config.phase0.testMapId
WildEcology.init(mod)
assertEquals(#spawnCalls, Config.phase3.visibleSubsetSize * 2, "re-entering route should spawn the visible subset again")

local reentryAnchorNpcId = spawnCalls[Config.phase3.visibleSubsetSize + 1].npcId
assertEquals(reentryAnchorNpcId ~= firstSpawnNpcId, true, "re-entry should reconstruct a fresh runtime avatar")
assertEquals(handlesById[reentryAnchorNpcId] ~= handlesById[firstSpawnNpcId], true, "re-entry should use a new runtime handle table")

local secondHandle = handlesById[reentryAnchorNpcId]
if not secondHandle then
	error("second avatar handle should be tracked")
end
assertEquals(secondHandle.entityId, Config.phase0.testEntityId, "runtime avatar handle should carry stable entity id")

liveState = Save.getState()
if not liveState or not liveState.populations or not liveState.populations[Config.phase0.testMapId] then
	error("storage should include phase 0 route population after re-entry")
end
local secondPopulation = liveState.populations[Config.phase0.testMapId]
if not secondPopulation.members then
	error("phase 0 route population should include members table after re-entry")
end
local secondEntity = secondPopulation.members[Config.phase0.testEntityId]
if not secondEntity then
	error("phase 0 entity should persist after re-entry")
end
assertEquals(secondEntity.runtimeState.motion.active, false, "re-entry should reset disposable runtime motion state")
assertEquals(secondEntity.runtimeState.movementRequest == nil
	or secondEntity.runtimeState.movementRequest.destinationX ~= 99
	or secondEntity.runtimeState.movementRequest.destinationY ~= 99,
	true, "re-entry should not retain the previous movement request")
assertEquals(next(secondEntity.runtimeState.rejectedMoves), nil, "re-entry should clear previous cell rejection memory")

local secondRelationship = secondEntity.relationships and secondEntity.relationships.player
if not secondRelationship then
	error("player relationship should persist after re-entry")
end
assertAtLeast(secondRelationship.trust, trustBeforeTransition, "relationship trust should be preserved across transition")

local secondRespawnCount = secondEntity.memory and secondEntity.memory.debug and secondEntity.memory.debug.respawnCount
assertEquals(secondRespawnCount, 2, "re-entry should increment respawn count on the same persistent entity")

local debugState = storedState.debug and storedState.debug.phase0
if not debugState then
	error("phase 0 debug verification state should persist in save data")
end
local devLog = storedState.debug and storedState.debug.devLog
if not devLog then
	error("development log should persist in save data")
end
assertEquals(debugState.lastEvent, "spawn", "last debug event should reflect re-entry spawn")
assertEquals(debugState.lastEntityId, Config.phase0.testEntityId, "debug state should record the persistent entity id")
assertEquals(debugState.lastSpawnAvatarId, reentryAnchorNpcId, "debug state should record the latest runtime avatar id")
assertEquals(debugState.lastDespawnAvatarId, lastDespawnedNpcId, "debug state should record the previous despawned avatar id")
assertEquals(debugState.lastRespawnCount, 2, "debug state should track respawn count across transition")
assertEquals(debugState.lastContextMapId, Config.phase0.testMapId, "debug state should record the current map for the latest spawn")
assertEquals(debugState.lastBehaviorMode, "normal", "debug state should record the active behavior mode")
assertEquals(#devLog.entries >= 3, true, "development log should keep recent lifecycle and behavior events")

local sawLifecycle = false
local sawBehavior = false
local sawRelationships = false
for _, entry in ipairs(devLog.entries) do
	if entry.category == "lifecycle" then
		sawLifecycle = true
	elseif entry.category == "behavior" then
		sawBehavior = true
	elseif entry.category == "relationships" then
		sawRelationships = true
	end
end

assertEquals(sawLifecycle, true, "development log should capture lifecycle entries")
assertEquals(sawBehavior, true, "development log should capture behavior entries")
assertEquals(sawRelationships, true, "development log should capture relationship entries")
assertEquals(writtenLog:find("Materialization event=avatar_materialization", 1, true) ~= nil, true, "durable log should capture materialization diagnostics")
assertEquals(writtenLog:find("canonicalCell=", 1, true) ~= nil, true, "materialization diagnostic should include the canonical cell")
assertEquals(writtenLog:find("avatarRequestedCell=", 1, true) ~= nil, true, "materialization diagnostic should include the requested cell")
assertEquals(writtenLog:find("spawnClass=", 1, true) ~= nil, true, "materialization diagnostic should include spawn class")
assertEquals(writtenLog:find("spawnRestrictionReason=", 1, true) ~= nil, true, "materialization diagnostic should include the spawn restriction reason")

-- Persisted invalid positions remain unchanged and cannot reach either
-- production AvatarFactory.spawn call path.
mod.world.mapOverview = function()
	local rows = {}
	for _ = 1, 20 do rows[#rows + 1] = string.rep(".", 20) end
	return { mapId = currentMapId, width = 20, height = 20, rows = rows }
end
currentMapId = "PALLET_TOWN"
WildEcology.shutdown()
firstEntity.home.spawnX = -1
firstEntity.home.spawnY = 0
local beforeInvalidAnchor = #spawnCalls
currentMapId = Config.phase0.testMapId
WildEcology.init(mod)
for index = beforeInvalidAnchor + 1, #spawnCalls do
	assertEquals(spawnCalls[index].objDef.name ~= "wild_route01_0001", true, "invalid persisted anchor must not reach spawnNpc")
end
assertEquals(firstEntity.home.spawnX, -1, "invalid persisted anchor coordinate should remain unchanged")

currentMapId = "PALLET_TOWN"
WildEcology.shutdown()
firstEntity.home.spawnX = 1
firstEntity.home.spawnY = 1
for entityId, entity in pairs(firstPopulation.members) do
	if entityId ~= Config.phase0.testEntityId then
		entity.home.spawnX = 20
		entity.home.spawnY = 0
	end
end
local beforeInvalidOrdinary = #spawnCalls
currentMapId = Config.phase0.testMapId
WildEcology.init(mod)
assertEquals(#spawnCalls, beforeInvalidOrdinary + 1, "invalid persisted ordinary entities must not reach spawnNpc")
assertEquals(spawnCalls[#spawnCalls].objDef.name, "wild_route01_0001", "valid anchor should remain on the shared guarded path")

currentMapId = "PALLET_TOWN"
WildEcology.shutdown()
local originalMapModule = package.loaded["src.world.Map"]
package.loaded["src.world.Map"] = {
	isOutdoor = function() return true end,
	defPassable = function(definition, _, x, y, surfing)
		return surfing == false and definition.passable
			and definition.passable[tostring(x) .. ":" .. tostring(y)] == true
	end
}
local routeDefinition = {
	id = Config.phase0.testMapId,
	tileset = "OVERWORLD",
	width = 10,
	height = 10,
	connections = { south = { map = "SOUTH_DESTINATION", offset = 0 } },
	warps = {}
}
local routeMap = {
	id = routeDefinition.id,
	def = routeDefinition,
	widthCells = 20,
	heightCells = 20
}
function routeMap:isWalkableCell(x, y)
	return x >= 0 and y >= 0 and x < 20 and y < 20
end
mod.game.overworld = { map = routeMap }
mod.game.data = {
	maps = {
		[routeDefinition.id] = routeDefinition,
		SOUTH_DESTINATION = {
			id = "SOUTH_DESTINATION", tileset = "OVERWORLD", width = 10, height = 10,
			passable = { ["1:0"] = true }
		}
	},
	tilesets = { OVERWORLD = {} }
}

firstEntity.home.spawnX = 1
firstEntity.home.spawnY = 19
for entityId, entity in pairs(firstPopulation.members) do
	if entityId ~= Config.phase0.testEntityId then
		entity.home.spawnX = 20
		entity.home.spawnY = 0
	end
end
local beforeTransitionAnchor = #spawnCalls
currentMapId = Config.phase0.testMapId
WildEcology.init(mod)
assertEquals(#spawnCalls, beforeTransitionAnchor, "persisted anchor on a connection source must not reach spawnNpc")
assertEquals(firstEntity.home.spawnX, 1, "rejected anchor connection coordinate should remain unchanged")
assertEquals(firstEntity.home.spawnY, 19, "rejected anchor connection coordinate should remain unchanged")

currentMapId = "PALLET_TOWN"
WildEcology.shutdown()
firstEntity.home.spawnX = 1
firstEntity.home.spawnY = 1
for entityId, entity in pairs(firstPopulation.members) do
	if entityId ~= Config.phase0.testEntityId then
		entity.home.spawnX = 1
		entity.home.spawnY = 19
	end
end
local beforeTransitionOrdinary = #spawnCalls
currentMapId = Config.phase0.testMapId
WildEcology.init(mod)
assertEquals(#spawnCalls, beforeTransitionOrdinary + 1, "persisted ordinary entities on connection sources must not reach spawnNpc")
for entityId, entity in pairs(firstPopulation.members) do
	if entityId ~= Config.phase0.testEntityId then
		assertEquals(entity.home.spawnX, 1, "rejected ordinary connection coordinate should remain unchanged")
		assertEquals(entity.home.spawnY, 19, "rejected ordinary connection coordinate should remain unchanged")
	end
end
package.loaded["src.world.Map"] = originalMapModule

return true
