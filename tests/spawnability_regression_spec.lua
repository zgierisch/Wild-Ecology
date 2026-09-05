local Config = require("src.core.config")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end
for _, moduleName in ipairs({
	"main", "src.core.save", "src.population.manager", "src.world.avatar_factory",
	"src.world.walkable_cells", "src.world.world_semantics", "src.world.engine_topology",
	"src.navigation.navigation_planner"
}) do
	package.loaded[moduleName] = nil
end

local originalMapModule = package.loaded["src.world.Map"]
package.loaded["src.world.Map"] = {
	isOutdoor = function() return true end,
	defPassable = function(definition, _, x, y, surfing)
		return surfing == false and definition.passable
			and definition.passable[x .. ":" .. y] == true
	end
}

local mapId = Config.phase0.testMapId
local rows = {}
for _ = 1, 36 do rows[#rows + 1] = string.rep(".", 20) end
local definition = {
	id = mapId,
	tileset = "OVERWORLD",
	width = 10,
	height = 18,
	connections = { south = { map = "PALLET_TOWN", offset = 0 } },
	warps = {}
}
local map = { id = mapId, def = definition, widthCells = 20, heightCells = 36 }
function map:isWalkableCell(x, y)
	return x >= 0 and y >= 0 and x < 20 and y < 36
end

local storedState = nil
local spawnCalls = {}
local removeCalls = {}
local currentMapId = mapId
local mod = {
	storage = {
		read = function() return storedState, storedState == nil and "not_found" or nil end,
		write = function(_, _game, _key, value) storedState = value return true end
	},
	game = {
		overworld = { map = map },
		data = {
			maps = {
				[mapId] = definition,
				PALLET_TOWN = {
					id = "PALLET_TOWN", tileset = "OVERWORLD", width = 10, height = 18,
					passable = { ["4:0"] = true }
				}
			},
			tilesets = { OVERWORLD = {} }
		}
	},
	world = {
		current = function() return { mapId = currentMapId, x = 10, y = 10 } end,
		mapOverview = function()
			return { mapId = mapId, width = 20, height = 36, rows = rows }
		end,
		spawnNpc = function(_, requestedMapId, objectDefinition)
			local id = "npc_" .. tostring(#spawnCalls + 1)
			spawnCalls[#spawnCalls + 1] = {
				id = id, mapId = requestedMapId, objDef = objectDefinition
			}
			return id
		end,
		npc = function() return {} end,
		removeNpc = function(_, id)
			removeCalls[#removeCalls + 1] = id
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
assertEquals(#spawnCalls, Config.phase3.visibleSubsetSize, "nonempty ordinary candidates should reach production spawnNpc")
local Save = require("src.core.save")
local population = Save.getState().populations[mapId]
local PopulationManager = require("src.population.manager")
local productionSnapshot = PopulationManager.getSpawnDebugSnapshot(mapId)
local debugSnapshot = WildEcology.getSpawnDebugSnapshot()
assertEquals(debugSnapshot.candidateAnalysis, productionSnapshot.candidateAnalysis, "HUD should retain the exact candidate analysis consumed by assignment")
assertEquals(productionSnapshot.assignmentAnalysis, productionSnapshot.candidateAnalysis, "representative assignment should consume the retained production analysis object")
assertEquals(debugSnapshot.candidateStatus, "READY", "nonempty production candidates should report READY")
assertEquals(debugSnapshot.candidateAnalysis.finalCandidates[1] ~= nil, true, "HUD production analysis should expose sampleable final coordinates")
assertEquals(WildEcology.spawnDiagnostics.spawnNpcCalls, Config.phase3.visibleSubsetSize, "HUD counter should reflect actual public spawnNpc calls")
for _, entity in pairs(population.members) do
	assertEquals(entity.home.spawnX ~= nil, true, "candidate assignment should write spawnX")
	assertEquals(entity.home.spawnY ~= nil, true, "candidate assignment should write spawnY")
	assertEquals(entity.home.spawnX == 4 and entity.home.spawnY == 35, false, "assignment must not select the connection source")
end

WildEcology.shutdown()
local ordered = population.order
population.members[ordered[1]].home.spawnX = 19
population.members[ordered[1]].home.spawnY = 3
for index = 2, #ordered do
	local entity = population.members[ordered[index]]
	entity.home.spawnX = 19
	entity.home.spawnY = index % 2 == 0 and 26 or 33
end
local beforePersistedOrdinary = #spawnCalls
WildEcology.init(mod)
assertEquals(#spawnCalls, beforePersistedOrdinary + Config.phase3.visibleSubsetSize, "persisted ordinary live cells should pass production materialization")
local saw19x3, saw19x26, saw19x33 = false, false, false
for index = beforePersistedOrdinary + 1, #spawnCalls do
	local objectDefinition = spawnCalls[index].objDef
	if objectDefinition.x == 19 and objectDefinition.y == 3 then saw19x3 = true end
	if objectDefinition.x == 19 and objectDefinition.y == 26 then saw19x26 = true end
	if objectDefinition.x == 19 and objectDefinition.y == 33 then saw19x33 = true end
end
assertEquals(saw19x3, true, "persisted ordinary cell (19,3) should reach spawnNpc")
assertEquals(saw19x26, true, "persisted ordinary cell (19,26) should reach spawnNpc")
assertEquals(saw19x33, true, "persisted ordinary cell (19,33) should reach spawnNpc")

WildEcology.shutdown()
population.members[ordered[1]].home.spawnX = 4
population.members[ordered[1]].home.spawnY = 35
local beforeTransition = #spawnCalls
WildEcology.init(mod)
assertEquals(#spawnCalls, beforeTransition + Config.phase3.visibleSubsetSize - 1, "persisted connection-source anchor should be the only rejected visible entity")
for index = beforeTransition + 1, #spawnCalls do
	assertEquals(spawnCalls[index].objDef.name ~= "wild_route01_0001", true, "connection-source anchor must not reach spawnNpc")
end

WildEcology.shutdown()
package.loaded["src.world.Map"] = originalMapModule

return true