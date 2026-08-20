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

local mod = {
	storage = {
		get = function(_)
			return storedState
		end,
		set = function(_, value)
			storedState = value
		end
	},
	world = {
		current = function(_)
			return { mapId = currentMapId }
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
			if key == "phase0_debug_log" then
				return false
			end
			if key == "dev_log_view" then
				return "both"
			end
			if key == "dev_log_lifecycle" or key == "dev_log_behavior" or key == "dev_log_relationships" then
				return true
			end
			return nil
		end
	}
}

local entry = require("main")
local WildEcology = entry(mod)
if not WildEcology then
	error("main entry should return WildEcology module API")
end

WildEcology.init(mod)
assertEquals(#spawnCalls, 1, "initial load on route should spawn one avatar")

local firstSpawnNpcId = spawnCalls[1].npcId
if not storedState or not storedState.populations or not storedState.populations[Config.phase0.testMapId] then
	error("storage should include phase 0 route population after init")
end
local firstPopulation = storedState.populations[Config.phase0.testMapId]
if not firstPopulation.members then
	error("phase 0 route population should include members table")
end
local firstEntity = firstPopulation.members[Config.phase0.testEntityId]
if not firstEntity then
	error("phase 0 entity should exist after init")
end

local firstRelationship = firstEntity.relationships and firstEntity.relationships.player
if not firstRelationship then
	error("player relationship should exist after init")
end
local trustBeforeTransition = firstRelationship.trust
local firstRespawnCount = firstEntity.memory and firstEntity.memory.debug and firstEntity.memory.debug.respawnCount
assertEquals(firstRespawnCount, 1, "first spawn should record respawn count 1")

currentMapId = "ROUTE_2"
WildEcology.shutdown()
assertEquals(#removeCalls, 1, "route exit shutdown should despawn current avatar")
assertEquals(removeCalls[1], firstSpawnNpcId, "despawn should remove the previously spawned npc")

local despawnDebugState = storedState.debug and storedState.debug.phase0
if not despawnDebugState then
	error("phase 0 debug verification state should persist after despawn")
end
assertEquals(despawnDebugState.lastEvent, "despawn", "debug state should record route exit despawn")
assertEquals(despawnDebugState.lastContextMapId, "ROUTE_2", "debug state should record the map where despawn was observed")

currentMapId = Config.phase0.testMapId
WildEcology.init(mod)
assertEquals(#spawnCalls, 2, "re-entering route should spawn avatar again")

local secondSpawnNpcId = spawnCalls[2].npcId
assertEquals(secondSpawnNpcId ~= firstSpawnNpcId, true, "re-entry should reconstruct a fresh runtime avatar")
assertEquals(handlesById[secondSpawnNpcId] ~= handlesById[firstSpawnNpcId], true, "re-entry should use a new runtime handle table")

local secondHandle = handlesById[secondSpawnNpcId]
if not secondHandle then
	error("second avatar handle should be tracked")
end
assertEquals(secondHandle.entityId, Config.phase0.testEntityId, "runtime avatar handle should carry stable entity id")

if not storedState or not storedState.populations or not storedState.populations[Config.phase0.testMapId] then
	error("storage should include phase 0 route population after re-entry")
end
local secondPopulation = storedState.populations[Config.phase0.testMapId]
if not secondPopulation.members then
	error("phase 0 route population should include members table after re-entry")
end
local secondEntity = secondPopulation.members[Config.phase0.testEntityId]
if not secondEntity then
	error("phase 0 entity should persist after re-entry")
end

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
assertEquals(debugState.lastSpawnAvatarId, secondSpawnNpcId, "debug state should record the latest runtime avatar id")
assertEquals(debugState.lastDespawnAvatarId, firstSpawnNpcId, "debug state should record the previous despawned avatar id")
assertEquals(debugState.lastRespawnCount, 2, "debug state should track respawn count across transition")
assertEquals(debugState.lastContextMapId, Config.phase0.testMapId, "debug state should record the current map for the latest spawn")
assertEquals(debugState.lastBehaviorMode, "normal", "debug state should record the active behavior mode")
assertEquals(#devLog.entries >= 5, true, "development log should keep recent lifecycle and behavior events")

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

return true
