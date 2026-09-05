local Config = require("src.core.config")
local Relationships = require("src.entities.relationships")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

for _, moduleName in ipairs({
	"main", "src.core.save", "src.population.manager", "src.world.avatar_factory",
	"src.world.walkable_cells", "src.world.world_semantics", "src.world.engine_topology",
	"src.world.spawn_cells", "src.world.playable_component",
	"src.navigation.navigation_planner"
}) do
	package.loaded[moduleName] = nil
end

local originalMapModule = package.loaded["src.world.Map"]
local originalOverworldController = package.loaded["src.world.OverworldController"]
package.loaded["src.world.Map"] = {
	isOutdoor = function() return true end,
	defPassable = function() return true end
}
local OverworldController = { update = function(_, _) end }
package.loaded["src.world.OverworldController"] = OverworldController

local function rows(width, height)
	local result = {}
	for _ = 1, height do result[#result + 1] = string.rep(".", width) end
	return result
end

local function splitRows(height)
	local result = {}
	for _ = 1, height do result[#result + 1] = "........#..." end
	return result
end

local definitions = {
	ROUTE_1 = {
		id = "ROUTE_1", tileset = "OVERWORLD", width = 5, height = 6,
		connections = { south = { map = "PALLET_TOWN", offset = 0 } }, warps = {}
	},
	ROUTE_2 = {
		id = "ROUTE_2", tileset = "OVERWORLD", width = 6, height = 10,
		connections = { north = { map = "VIRIDIAN_CITY", offset = 0 } }, warps = {}
	},
	PALLET_TOWN = {
		id = "PALLET_TOWN", tileset = "OVERWORLD", width = 5, height = 6,
		connections = {}, warps = {}
	},
	VIRIDIAN_CITY = {
		id = "VIRIDIAN_CITY", tileset = "OVERWORLD", width = 6, height = 10,
		connections = {}, warps = {}
	}
}
local rasters = {
	ROUTE_1 = { width = 10, height = 12, rows = rows(10, 12) },
	ROUTE_2 = { width = 12, height = 20, rows = splitRows(20) },
	PALLET_TOWN = { width = 10, height = 12, rows = rows(10, 12) }
}

local currentMapId = "ROUTE_1"
local playerX, playerY = 2, 1
local storedState = nil
local spawnCalls = {}
local removeCalls = {}
local handlesById = {}
local npcSerial = 0

local function firstActiveOrdinary(WildEcology)
	local ids = {}
	for entityId in pairs(WildEcology.activeAvatars) do
		if entityId ~= Config.phase0.testEntityId then ids[#ids + 1] = entityId end
	end
	table.sort(ids)
	local entityId = ids[1]
	return entityId and WildEcology.entityById[entityId] or nil
end

local function runtimeMap(mapId)
	local raster = rasters[mapId]
	local map = {
		id = mapId,
		def = definitions[mapId],
		widthCells = raster.width,
		heightCells = raster.height
	}
	function map:isWalkableCell(x, y)
		return x >= 0 and y >= 0 and x < self.widthCells and y < self.heightCells
			and raster.rows[y + 1]:sub(x + 1, x + 1) == "."
	end
	return map
end

local mod = {
	storage = {
		read = function() return storedState, storedState == nil and "not_found" or nil end,
		write = function(_, _game, _key, value) storedState = value return true end
	},
	game = {
		overworld = { map = runtimeMap("ROUTE_1") },
		data = { maps = definitions, tilesets = { OVERWORLD = {} } }
	},
	world = {
		current = function()
			return { mapId = currentMapId, x = playerX, y = playerY }
		end,
		mapOverview = function()
			local raster = rasters[currentMapId]
			if not raster then return nil end
			return {
				mapId = currentMapId, width = raster.width,
				height = raster.height, rows = raster.rows
			}
		end,
		spawnNpc = function(_, mapId, objectDefinition)
			npcSerial = npcSerial + 1
			local npcId = "npc_" .. tostring(npcSerial)
			handlesById[npcId] = {
				x = objectDefinition.x,
				y = objectDefinition.y,
				position = function(self) return self.x, self.y end
			}
			spawnCalls[#spawnCalls + 1] = {
				id = npcId, mapId = mapId, objDef = objectDefinition
			}
			return npcId
		end,
		npc = function(_, _, npcId) return handlesById[npcId] end,
		removeNpc = function(_, npcId)
			removeCalls[#removeCalls + 1] = npcId
			return true
		end
	},
	options = {
		define = function() end,
		get = function(_, key)
			if key == "phase0_behavior_mode" then return "normal" end
			return nil
		end
	},
	save = { get = function(_, _, default) return default end, set = function() end }
}

local WildEcology = require("main")(mod)
local Save = require("src.core.save")
assertEquals(#spawnCalls, Config.phase3.visibleSubsetSize, "Route 1 should materialize one visible subset")
local route1Population = Save.getState().populations.ROUTE_1
local route1Anchor = route1Population.members[Config.phase0.testEntityId]
assertEquals(route1Anchor ~= nil, true, "Route 1 should retain its compatibility anchor")
local route1Homes = {}
local route1Personalities = {}
for entityId, entity in pairs(route1Population.members) do
	route1Homes[entityId] = tostring(entity.home.spawnX) .. ":" .. tostring(entity.home.spawnY)
	route1Personalities[entityId] = entity.personalitySeed
	assertEquals(entity.home.mapId, "ROUTE_1", "Route 1 homes should be map-local")
end
local route1Ordinary = firstActiveOrdinary(WildEcology)
assertEquals(route1Ordinary ~= nil, true, "Route 1 should have an active ordinary entity")
local route1InitialDecisions = route1Ordinary.runtimeState.behaviorDecisionCount
playerX, playerY = -100, -100
for _ = 1, 15 do OverworldController.update({}, 1 / 60) end
assertEquals(route1Ordinary.runtimeState.behaviorDecisionCount > route1InitialDecisions, true, "ordinary Route 1 entity should receive an autonomous cadence decision")
assertEquals(route1Ordinary.runtimeState.lastDecisionReason, "CADENCE",
	"an ordinary calm entity should remain simulated without inventing an investigation")

local route1Threat = Relationships.getOrCreate(route1Ordinary, "player")
route1Threat.trust = 0
route1Threat.threatMemory = 80
route1Threat.directThreatMemory = 80
playerX, playerY = route1Ordinary.home.spawnX, route1Ordinary.home.spawnY
local route1BeforeFlee = route1Ordinary.runtimeState.behaviorDecisionCount
OverworldController.update({}, 1 / 60)
assertEquals(route1Ordinary.runtimeState.behaviorDecisionCount, route1BeforeFlee,
	"passive equilibrium must not force deliberation one tick after cadence")
for _ = 1, 15 do
	if route1Ordinary.runtimeState.behaviorDecisionCount > route1BeforeFlee then break end
	OverworldController.update({}, 1 / 60)
end
assertEquals(route1Ordinary.runtimeState.behaviorDecisionCount, route1BeforeFlee + 1, "urgent fear crossing should interrupt Route 1 once")
assertEquals(route1Ordinary.runtimeState.lastDecisionReason, "EMERGENCY_THREAT", "Route 1 urgent fear should expose its interrupt reason")
assertEquals(route1Ordinary.runtimeState.candidateState, "FLEE", "ordinary Route 1 threat should win integrated utility")
assertEquals(route1Ordinary.runtimeState.selectionReason, "EMERGENCY_FLEE", "urgent fear crossing should use the existing emergency provenance path")
route1Anchor.runtimeState.motion = { active = true, destinationX = 9, destinationY = 9 }

currentMapId = "PALLET_TOWN"
playerX, playerY = 4, 4
mod.game.overworld.map = runtimeMap("PALLET_TOWN")
OverworldController.update({}, 1 / 60)
assertEquals(#removeCalls, Config.phase3.visibleSubsetSize, "disabled-map entry should despawn Route 1 avatars")
assertEquals(next(WildEcology.activeAvatars), nil, "disabled maps should have no live ecology avatars")
assertEquals(storedState.populations.PALLET_TOWN, nil, "disabled maps should not create populations")
assertEquals(route1Anchor.runtimeState.motion.active, false, "despawn should reset transient motion")
local disabledSnapshot = WildEcology.getSpawnDebugSnapshot()
assertEquals(disabledSnapshot.ecologyEnabled, false, "disabled-map HUD state should report ecology disabled")
assertEquals(disabledSnapshot.populationMap, "NONE", "disabled-map HUD state should hide stale population ownership")

currentMapId = "ROUTE_2"
playerX, playerY = 3, -1
mod.game.overworld.map = runtimeMap("ROUTE_2")
OverworldController.update({}, 1 / 60)
assertEquals(#spawnCalls, Config.phase3.visibleSubsetSize * 2, "Route 2 should materialize its own visible subset")
local route2Population = Save.getState().populations.ROUTE_2
assertEquals(route2Population ~= nil, true, "Route 2 should create a persistent population")
assertEquals(route2Population ~= route1Population, true, "route populations should be distinct records")
assertEquals(route2Population.members[Config.phase0.testEntityId], nil, "Route 1 anchor should not leak into Route 2")
for entityId, entity in pairs(route2Population.members) do
	assertEquals(entityId:find("wild:route02:", 1, true) == 1, true, "Route 2 IDs should use its registry key")
	assertEquals(route1Population.members[entityId], nil, "entity IDs should be globally unambiguous")
	assertEquals(entity.home.mapId, "ROUTE_2", "Route 2 homes should be map-local")
	assertEquals(entity.home.spawnX >= 0 and entity.home.spawnX < 8, true, "Route 2 homes should stay in the player-anchored component")
	assertEquals(entity.home.spawnY >= 0 and entity.home.spawnY < 20, true, "Route 2 homes should use Route 2 height")
end
local route2Snapshot = WildEcology.getSpawnDebugSnapshot()
assertEquals(route2Snapshot.ecologyEnabled, true, "Route 2 HUD state should report ecology enabled")
assertEquals(route2Snapshot.populationMap, "ROUTE_2", "Route 2 HUD state should name its population")
assertEquals(route2Snapshot.candidateAnalysis.componentSeedSource, "MAP_CONNECTION", "out-of-body Route 2 player should use connection topology")
assertEquals(route2Snapshot.candidateAnalysis.componentSeedDirection, "NORTH", "Route 2 should resolve its own north connection")
assertEquals(route2Snapshot.candidateAnalysis.width, 12, "Route 2 analysis should use Route 2 dimensions")
assertEquals(route2Snapshot.candidateAnalysis.spawnRejectedOutsidePlayableComponent > 0, true, "Route 2 should reject its disconnected walkable region")

local route2SpawnCount = #spawnCalls
local route2Ordinary = firstActiveOrdinary(WildEcology)
assertEquals(route2Ordinary ~= nil, true, "Route 2 should have an active ordinary entity")
local route2InitialDecisions = route2Ordinary.runtimeState.behaviorDecisionCount
local route2InitialTick = Save.getState().simulationTick
playerX, playerY = -100, -100
for _ = 1, 15 do OverworldController.update({}, 1 / 60) end
assertEquals(#spawnCalls, route2SpawnCount, "same-route updates should not duplicate Route 2 avatars")
assertEquals(Save.getState().simulationTick, route2InitialTick + 15, "Route 2 should advance the generic simulation clock without an anchor")
assertEquals(route2Ordinary.runtimeState.behaviorDecisionCount > route2InitialDecisions, true, "ordinary Route 2 entity should receive an autonomous cadence decision")
assertEquals(route2Ordinary.runtimeState.lastDecisionReason, "INTENT_SATISFIED",
	"an ordinary Route 2 entity within INVESTIGATE radius should complete without new perception")
local route2Behavior = WildEcology.getSpawnDebugSnapshot().behaviorDiagnostics
assertEquals(route2Behavior.behaviorDecisionTicks > 0, true, "Route 2 debug snapshot should count behavior decisions")
assertEquals(route2Behavior.ambientDecisions > 0, true, "Route 2 debug snapshot should count ambient decisions")

local route2Threat = Relationships.getOrCreate(route2Ordinary, "player")
route2Threat.trust = 0
route2Threat.threatMemory = 80
route2Threat.directThreatMemory = 80
playerX, playerY = route2Ordinary.home.spawnX, route2Ordinary.home.spawnY
local route2BeforeFlee = route2Ordinary.runtimeState.behaviorDecisionCount
OverworldController.update({}, 1 / 60)
assertEquals(route2Ordinary.runtimeState.behaviorDecisionCount, route2BeforeFlee + 1,
	"the next ordinary Route 2 cadence decision should still occur")
assertEquals(route2Ordinary.runtimeState.lastDecisionReason, "CADENCE",
	"the sub-emergency contact must not replace the cadence reason")
assertEquals(route2Ordinary.runtimeState.fearUpdated, true,
	"Route 2 first contact should integrate Fear immediately")
assertEquals(route2Ordinary.runtimeState.fearCurrent < 0.85, true,
	"the first Route 2 integration should remain below the emergency threshold")
for _ = 1, 3 do
	if route2Ordinary.runtimeState.state == "FLEE" then break end
	OverworldController.update({}, 1 / 60)
end
assertEquals(route2Ordinary.runtimeState.state, "FLEE",
	"Route 2 should enter FLEE on the first Fear integration that becomes urgent")
assertEquals(route2Ordinary.runtimeState.lastDecisionReason, "EMERGENCY_THREAT",
	"the urgent Fear crossing should own the high-level interrupt")
assertEquals(route2Ordinary.runtimeState.selectionReason, "EMERGENCY_FLEE",
	"the urgent Fear crossing should use emergency selection rather than stale intent failure")

currentMapId = "ROUTE_1"
playerX, playerY = 2, 1
mod.game.overworld.map = runtimeMap("ROUTE_1")
OverworldController.update({}, 1 / 60)
assertEquals(#removeCalls, Config.phase3.visibleSubsetSize * 2, "direct enabled-route transition should despawn Route 2 avatars")
assertEquals(Save.getState().populations.ROUTE_1, route1Population, "return should reuse the Route 1 population record")
assertEquals(#spawnCalls, Config.phase3.visibleSubsetSize * 3, "return should reconstruct one fresh Route 1 subset")
for entityId, entity in pairs(route1Population.members) do
	assertEquals(tostring(entity.home.spawnX) .. ":" .. tostring(entity.home.spawnY), route1Homes[entityId], "return should preserve Route 1 homes")
	assertEquals(entity.personalitySeed, route1Personalities[entityId], "return should preserve Route 1 personality")
end

package.loaded["src.world.Map"] = originalMapModule
package.loaded["src.world.OverworldController"] = originalOverworldController

return true