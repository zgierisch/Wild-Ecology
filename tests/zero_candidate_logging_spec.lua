local Config = require("src.core.config")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

for _, moduleName in ipairs({
	"main", "src.core.save", "src.population.manager", "src.world.walkable_cells",
	"src.world.world_semantics", "src.world.engine_topology", "src.navigation.navigation_planner"
}) do
	package.loaded[moduleName] = nil
end

local originalMapModule = package.loaded["src.world.Map"]
package.loaded["src.world.Map"] = {
	isOutdoor = function() return true end,
	defPassable = function() return false end
}

local storedState = nil
local writtenLog = ""
local spawnCalls = 0
local wrappedHooks = {}
local drawn = {}
local mapId = Config.phase0.testMapId
local definition = {
	id = mapId,
	tileset = "OVERWORLD",
	width = 2,
	height = 2,
	connections = { north = { map = "MISSING_DESTINATION", offset = 0 } },
	warps = {}
}
local rows = { "....", "....", "....", "...." }
local map = {
	id = mapId,
	def = definition,
	widthCells = 4,
	heightCells = 4
}
function map:isWalkableCell(x, y)
	return x >= 0 and y >= 0 and x < 4 and y < 4
end

local mod = {
	storage = {
		read = function() return storedState, storedState == nil and "not_found" or nil end,
		write = function(_, _game, _key, value) storedState = value return true end,
		writeBytes = function(_, _game, key, bytes)
			assertEquals(key, "wildecology_log", "spawn diagnostics should use the durable log stream")
			writtenLog = bytes
			return true
		end
	},
	game = {
		overworld = { map = map },
		data = {
			maps = { [mapId] = definition },
			tilesets = { OVERWORLD = {} }
		}
	},
	world = {
		current = function() return { mapId = mapId, x = 0, y = 0 } end,
		mapOverview = function()
			return { mapId = mapId, width = 4, height = 4, rows = rows }
		end,
		spawnNpc = function()
			spawnCalls = spawnCalls + 1
			return "unexpected"
		end,
		npc = function() return {} end,
		removeNpc = function() return true end
	},
	options = {
		define = function() end,
		get = function(_, key)
			if key == "phase0_behavior_mode" then return "normal" end
			return nil
		end
	},
	save = {
		get = function(_, key, default)
			if key == "dev_log_console" then return true end
			if key == "phase0_debug_log" then return true end
			return default
		end,
		set = function() end
	},
	hooks = {
		wrap = function(_, id, wrapper) wrappedHooks[id] = wrapper end
	},
	ui = {
		Font = {
			drawBox = function() end,
			draw = function(text) drawn[#drawn + 1] = tostring(text) end
		}
	}
}

local WildEcology = require("main")(mod)
assertEquals(spawnCalls, 0, "zero final candidates must not force an avatar spawn")
assertEquals(writtenLog:find("SpawnCandidates map=" .. mapId, 1, true) ~= nil, true, "spawn diagnostics should be written before materialization")
assertEquals(writtenLog:find("rawWalkable=16", 1, true) ~= nil, true, "durable diagnostics should report raw walkable cells")
assertEquals(writtenLog:find("spawnSemanticAllowed=16", 1, true) ~= nil, true, "ordinary ground should remain semantically spawnable")
assertEquals(writtenLog:find("connectivityAccepted=0", 1, true) ~= nil, true, "durable diagnostics should isolate connectivity failure")
assertEquals(writtenLog:find("usableOverworldExitCount=0", 1, true) ~= nil, true, "durable diagnostics should expose missing usable exits")
assertEquals(writtenLog:find("result=NO_SPAWN_CANDIDATES", 1, true) ~= nil, true, "durable diagnostics should classify the empty result")
assertEquals(writtenLog:find("SpawnAssignment entity=", 1, true) ~= nil, true, "an unassigned entity should produce a pre-materialization diagnostic")

local PopulationManager = require("src.population.manager")
local productionSnapshot = PopulationManager.getSpawnDebugSnapshot(mapId)
local debugSnapshot = WildEcology.getSpawnDebugSnapshot()
assertEquals(debugSnapshot.candidateAnalysis, productionSnapshot.candidateAnalysis, "HUD should expose the exact analysis object retained by production assignment")
assertEquals(debugSnapshot.spawnInitialization.status, "COMPLETE", "missing homes should normalize to no actor position without a Controller synchronization error")
assertEquals(debugSnapshot.semanticsStatus, "TOPOLOGY_UNRESOLVED", "HUD snapshot should distinguish unresolved topology")
assertEquals(debugSnapshot.candidateStatus, "NO_USABLE_EXIT", "HUD snapshot should distinguish missing usable exits")
assertEquals(debugSnapshot.populationRecords, Config.phase3.routePopulationSize, "HUD snapshot should report actual population records")
assertEquals(debugSnapshot.homesAssigned, 0, "HUD snapshot should report no assigned homes")
assertEquals(debugSnapshot.homesMissing, Config.phase3.routePopulationSize, "HUD snapshot should report every missing home")
assertEquals(WildEcology.spawnDiagnostics.spawnNpcCalls, 0, "zero candidates should expose zero actual spawnNpc calls")
assertEquals(next(WildEcology.activeAvatars), nil, "zero candidates should leave zero live avatars")

wrappedHooks["render.hud"](function() end, {}, {
	width = 640, height = 800, gameX = 0, gameY = 0,
	gameWidth = 640, gameHeight = 800
})
local rendered = table.concat(drawn, "\n")
local renderedCompact = rendered:gsub("\n", "")
assertEquals(renderedCompact:find("SPAWN DEBUG build=spawn-debug-20260825-09", 1, true) ~= nil, true, "zero-avatar HUD should show the build fingerprint")

local state = storedState
local population = state and state.populations and state.populations[mapId]
for _, entity in pairs(population and population.members or {}) do
	assertEquals(entity.home.spawnX, nil, "no-candidate entities should retain unset x coordinates")
	assertEquals(entity.home.spawnY, nil, "no-candidate entities should retain unset y coordinates")
end

WildEcology.shutdown()
package.loaded["src.world.Map"] = originalMapModule

return true