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

local mapId = Config.phase0.testMapId
local rows = {}
for _ = 1, 36 do rows[#rows + 1] = string.rep(".", 20) end

local storedState = nil
local spawnCalls = 0
local mod = {
	storage = {
		read = function() return storedState, storedState == nil and "not_found" or nil end,
		write = function(_, _game, _key, value) storedState = value return true end
	},
	world = {
		current = function() return { mapId = mapId, x = 10, y = 10 } end,
		mapOverview = function()
			return { mapId = mapId, width = 20, height = 36, rows = rows }
		end,
		spawnNpc = function()
			spawnCalls = spawnCalls + 1
			return nil, "no overworld"
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
local diagnostics = WildEcology.spawnDiagnostics
local phase3Attempts = Config.phase3.visibleSubsetSize - 1

assertEquals(spawnCalls, Config.phase3.visibleSubsetSize * 2,
	"refused entities should reach the public boundary on both startup sync passes")
assertEquals(diagnostics.materializeCalls, phase3Attempts,
	"phase 3 diagnostics should count every non-anchor spawn attempt in the latest pass")
assertEquals(diagnostics.materializeSuccess, 0,
	"refused public spawns must not count as successful materializations")
assertEquals(diagnostics.materializeFailure, phase3Attempts,
	"refused public spawns should count as failed materializations")
assertEquals(diagnostics.activeAvatarCount, 0,
	"refused public spawns must not enter the active avatar registry")
assertEquals(diagnostics.lastAdapterResult, "nil",
	"adapter diagnostics should expose the nil public API result")
assertEquals(diagnostics.lastAdapterReason, "PUBLIC_API_RETURNED_NIL: no overworld",
	"adapter diagnostics should preserve the public API refusal reason")

return true