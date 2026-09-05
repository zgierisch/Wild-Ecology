local Config = require("src.core.config")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

for _, moduleName in ipairs({
	"main", "src.core.save", "src.population.manager", "src.world.avatar_factory",
	"src.world.walkable_cells", "src.world.world_semantics", "src.world.engine_topology"
}) do
	package.loaded[moduleName] = nil
end

local mapId = "ROUTE_3"
local rows = {}
for _ = 1, 36 do rows[#rows + 1] = string.rep(".", 20) end

local observed = {}
local storedState = nil
local mod = {
	storage = {
		read = function() return storedState, storedState == nil and "not_found" or nil end,
		write = function(_, _game, _key, value) storedState = value return true end
	},
	world = {
		current = function() return { mapId = mapId, x = 10, y = 10 } end,
		mapOverview = function() return { mapId = mapId, width = 20, height = 36, rows = rows } end,
		spawnNpc = function(_, _, obj)
			observed[#observed + 1] = { obj = obj }
			return "npc_" .. tostring(#observed)
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

local PopulationManager = require("src.population.manager")
PopulationManager.getVisibleRoutePopulation = function()
	return {
		{ id = "throwing_actor_1", species = "PIDGEY", home = { spawnX = 5, spawnY = 7, mapId = mapId }, avatar = {} }
	}
end
PopulationManager.assessMaterialization = function()
	error("intentional dispatch injection error")
end

PopulationManager.getSpawnDebugSnapshot = function()
	return { candidateAnalysis = { finalCandidateCount = 1 }, homesAssigned = 1 }
end

local WildEcology = require("main")(mod)
local beforeSpawnCalls = #observed
WildEcology.init(mod)

assertEquals(WildEcology.spawnDiagnostics.phase3DispatchAttempts > 0, true, "dispatch should have attempted at least one materialization")
assertEquals(WildEcology.spawnDiagnostics.phase3LastBlocker, "ERROR", "a thrown dispatch error must resolve to ERROR")
assertEquals(string.find(WildEcology.spawnDiagnostics.lastPhase3Error or "", "intentional dispatch injection error", 1, true) ~= nil, true, "diagnostic should preserve a short Lua error string")
assertEquals(#observed, beforeSpawnCalls, "an error in the dispatch path must not count as a successful spawn")
assertEquals(WildEcology.spawnDiagnostics.materializeFailure >= 1, true, "dispatch failures should count as materialization failures")

print("dispatch exception regression: ok")
return true
