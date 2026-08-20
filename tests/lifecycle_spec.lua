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
	}
}

local WildEcology = require("main")

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

currentMapId = "ROUTE_2"
WildEcology.shutdown()
assertEquals(#removeCalls, 1, "route exit shutdown should despawn current avatar")
assertEquals(removeCalls[1], firstSpawnNpcId, "despawn should remove the previously spawned npc")

currentMapId = Config.phase0.testMapId
WildEcology.init(mod)
assertEquals(#spawnCalls, 2, "re-entering route should spawn avatar again")

local secondSpawnNpcId = spawnCalls[2].npcId
assertEquals(secondSpawnNpcId ~= firstSpawnNpcId, true, "re-entry should reconstruct a fresh runtime avatar")

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

return true
