local Config = require("src.core.config")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

for _, moduleName in ipairs({
	"main", "src.core.save", "src.population.manager", "src.world.avatar_factory",
	"src.world.walkable_cells", "src.world.world_semantics", "src.world.engine_topology",
	"src.world.spawn_cells", "src.navigation.navigation_planner"
}) do
	package.loaded[moduleName] = nil
end

local originalMapModule = package.loaded["src.world.Map"]
local originalOverworldController = package.loaded["src.world.OverworldController"]
package.loaded["src.world.Map"] = {
	isOutdoor = function() return true end,
	defPassable = function(definition, _, x, y, surfing)
		return surfing == false and definition.passable
			and definition.passable[x .. ":" .. y] == true
	end
}
local OverworldController = {
	update = function(self, _dt)
		self.engineUpdates = (self.engineUpdates or 0) + 1
	end
}
package.loaded["src.world.OverworldController"] = OverworldController

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

local overviewReady = false
local storedState = nil
local spawnCalls = {}
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
		current = function() return { mapId = mapId, x = 1, y = 0 } end,
		mapOverview = function()
			if not overviewReady then return nil end
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
		removeNpc = function() return true end
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
local SpawnCells = require("src.world.spawn_cells")
local loadedRequire = require
local runtimeLocalModules = {
	["src.world.world_semantics"] = true,
	["src.world.walkable_cells"] = true,
	["src.world.spawn_cells"] = true,
	["src.population.manager"] = true,
	["src.behavior.utility"] = true,
	["src.navigation.navigation_planner"] = true,
	["src.navigation.traversal_evaluator"] = true,
	["src.navigation.traversal_capabilities"] = true
}
_G.require = function(moduleName, ...)
	if runtimeLocalModules[moduleName] then
		error("runtime mod-local require blocked: " .. tostring(moduleName))
	end
	return loadedRequire(moduleName, ...)
end
assertEquals(OverworldController.update ~= nil, true, "overworld update retry owner should be installed while initialization is pending")
assertEquals(WildEcology.spawnInitialization.status, "PENDING_WORLD", "initial unavailable semantics should remain retryable")
assertEquals(WildEcology.getSpawnDebugSnapshot().candidateStatus, "NOT_RUN", "pending initialization must not run candidate analysis")
assertEquals(SpawnCells.getCandidateAnalysisRunCount(), 0, "pending initialization must not enter candidate analysis")
assertEquals(storedState, nil, "pending initialization must not create or assign the population")
assertEquals(#spawnCalls, 0, "pending initialization must not materialize avatars")

overviewReady = true
OverworldController.update({}, 1 / 60)
local Save = require("src.core.save")
local readySnapshot = WildEcology.getSpawnDebugSnapshot()
assertEquals(WildEcology.spawnInitialization.status, "COMPLETE", "same-map update should complete deferred initialization")
assertEquals(WildEcology.spawnInitialization.status ~= "ERROR", true, "ready synchronization must not depend on runtime mod-local require resolution")
assertEquals(readySnapshot.candidateStatus, "READY", "deferred production candidate analysis should become ready")
assertEquals(readySnapshot.populationRecords, Config.phase3.routePopulationSize, "deferred initialization should create one population")
assertEquals(readySnapshot.homesAssigned, Config.phase3.routePopulationSize, "deferred initialization should assign all homes")
assertEquals(#spawnCalls, Config.phase3.visibleSubsetSize, "deferred initialization should materialize the visible subset")

if not storedState or not storedState.populations or not storedState.populations[mapId] then
	error("completed initialization should persist the route population")
end
local population = Save.getState().populations[mapId]
local firstHomes = {}
local firstHomeAreas = {}
for entityId, entity in pairs(population.members) do
	firstHomes[entityId] = tostring(entity.home.spawnX) .. ":" .. tostring(entity.home.spawnY)
	assertEquals(entity.home.area ~= nil, true,
		"legal persistent placement should establish a local home area")
	firstHomeAreas[entityId] = table.concat({
		entity.home.area.mapId,
		entity.home.area.anchorCell.cellX,
		entity.home.area.anchorCell.cellY,
		entity.home.area.radius,
		entity.home.area.establishedTick,
		entity.home.area.provenance
	}, ":")
end
local firstAnalysisRuns = SpawnCells.getCandidateAnalysisRunCount()
local firstSpawnCalls = #spawnCalls
for _ = 1, 3 do OverworldController.update({}, 1 / 60) end
assertEquals(Save.getState().populations[mapId], population, "later frames must reuse the persistent population")
assertEquals(#spawnCalls, firstSpawnCalls, "later frames must not duplicate avatars")
assertEquals(SpawnCells.getCandidateAnalysisRunCount(), firstAnalysisRuns, "later frames must not rerun unchanged candidate analysis")
assertEquals(WildEcology.spawnInitialization.attempts, 1, "completed same-generation frames must not restart initialization")
for entityId, entity in pairs(population.members) do
	assertEquals(tostring(entity.home.spawnX) .. ":" .. tostring(entity.home.spawnY), firstHomes[entityId], "later frames must not reroll homes")
	assertEquals(table.concat({ entity.home.area.mapId,
		entity.home.area.anchorCell.cellX, entity.home.area.anchorCell.cellY,
		entity.home.area.radius, entity.home.area.establishedTick,
		entity.home.area.provenance }, ":"), firstHomeAreas[entityId],
		"later frames must not re-establish home areas")
end

local function replacementMap()
	local replacement = {
		id = mapId,
		def = definition,
		widthCells = 20,
		heightCells = 36
	}
	function replacement:isWalkableCell(x, y)
		return x >= 0 and y >= 0 and x < 20 and y < 36
	end
	return replacement
end

mod.game.overworld.map = replacementMap()
OverworldController.update({}, 1 / 60)
local generationAnalysisRuns = SpawnCells.getCandidateAnalysisRunCount()
assertEquals(generationAnalysisRuns, firstAnalysisRuns + 1, "a new semantics generation should run assignment analysis once")
assertEquals(WildEcology.spawnInitialization.attempts, 2, "a new semantics generation should restart synchronization once")
assertEquals(#spawnCalls, firstSpawnCalls, "a generation refresh must not duplicate live avatars")
for entityId, entity in pairs(population.members) do
	assertEquals(tostring(entity.home.spawnX) .. ":" .. tostring(entity.home.spawnY), firstHomes[entityId], "a generation refresh must preserve assigned homes")
	assertEquals(table.concat({ entity.home.area.mapId,
		entity.home.area.anchorCell.cellX, entity.home.area.anchorCell.cellY,
		entity.home.area.radius, entity.home.area.establishedTick,
		entity.home.area.provenance }, ":"), firstHomeAreas[entityId],
		"semantics refresh must preserve established home ecology")
end

local originalAnalyzeCandidates = SpawnCells.analyzeCandidates
local failOnce = true
rawset(SpawnCells, "analyzeCandidates", function(...)
	if failOnce then
		failOnce = false
		error("transient candidate analysis failure")
	end
	return originalAnalyzeCandidates(...)
end)
mod.game.overworld.map = replacementMap()
OverworldController.update({}, 1 / 60)
assertEquals(WildEcology.spawnInitialization.status, "ERROR", "update callback should expose a synchronization exception")
assertEquals(WildEcology.spawnInitialization.lastError:find("transient candidate analysis failure", 1, true) ~= nil, true, "synchronization error should retain the failing reason")
OverworldController.update({}, 1 / 60)
rawset(SpawnCells, "analyzeCandidates", originalAnalyzeCandidates)
assertEquals(WildEcology.spawnInitialization.status, "COMPLETE", "the next same-map frame should retry a transient synchronization error")
assertEquals(SpawnCells.getCandidateAnalysisRunCount(), generationAnalysisRuns + 1, "error recovery should complete one new generation analysis")
assertEquals(#spawnCalls, firstSpawnCalls, "error recovery must not duplicate live avatars")

_G.require = loadedRequire
package.loaded["src.world.Map"] = originalMapModule
package.loaded["src.world.OverworldController"] = originalOverworldController

return true