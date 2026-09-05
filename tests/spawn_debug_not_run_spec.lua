local Config = require("src.core.config")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

for _, moduleName in ipairs({ "main", "src.core.save", "src.population.manager" }) do
	package.loaded[moduleName] = nil
end

local drawn = {}
local hooks = {}
local mod = {
	storage = {
		read = function() return nil, "not_found" end,
		write = function() return true end
	},
	game = {},
	world = { current = function() return { mapId = "ROUTE_2" } end },
	options = { define = function() end, get = function() return nil end },
	save = {
		get = function(_, key, default)
			if key == "phase0_debug_log" then return true end
			return default
		end,
		set = function() end
	},
	hooks = { wrap = function(_, id, wrapper) hooks[id] = wrapper end },
	ui = {
		Font = {
			drawBox = function() end,
			draw = function(text) drawn[#drawn + 1] = tostring(text) end
		}
	}
}

local WildEcology = require("main")(mod)
local WorldSemantics = require("src.world.world_semantics")
WorldSemantics.fromMod(mod, "ROUTE_2")
local snapshot = WildEcology.getSpawnDebugSnapshot()
assertEquals(snapshot.mapId, "ROUTE_2", "not-run snapshot should still report the current map")
assertEquals(snapshot.semanticsStatus, "UNAVAILABLE", "not-run snapshot should distinguish unavailable semantics")
assertEquals(snapshot.candidateStatus, "NOT_RUN", "not-run snapshot should not report misleading zero candidates")
assertEquals(snapshot.assignmentStatus, "NOT_RUN", "not-run snapshot should expose assignment state")
assertEquals(WildEcology.spawnDiagnostics.materializationAttempts, 0, "never-invoked materialization should remain an explicit zero")
assertEquals(WildEcology.spawnDiagnostics.materializationStatus, "NOT_RUN", "never-invoked materialization should report NOT_RUN")
local worldInputs = WildEcology.getWorldInputDebugSnapshot(true)
assertEquals(worldInputs.current.mapOverviewStatus, "UNAVAILABLE", "current probe should report the missing public raster method")
assertEquals(worldInputs.current.semanticsReason, "MAP_OVERVIEW_UNAVAILABLE", "current probe should expose the exact semantics prerequisite")
assertEquals(worldInputs.currentSemanticsProbe, "UNAVAILABLE", "current probe availability should be explicit")
assertEquals(worldInputs.lastProductionSemanticsStatus, "UNAVAILABLE", "HUD should retain the exact last production result")
assertEquals(worldInputs.lastProductionSemanticsReason, "MAP_OVERVIEW_UNAVAILABLE", "HUD should compare against the production failure reason")

hooks["render.hud"](function() end, {}, {
	width = 640, height = 800, gameX = 0, gameY = 0,
	gameWidth = 640, gameHeight = 800
})
local rendered = table.concat(drawn, "\n")
local renderedCompact = rendered:gsub("\n", "")
assertEquals(renderedCompact:find("WORLD INPUTS", 1, true) ~= nil, true, "HUD should lead with world prerequisites")
assertEquals(renderedCompact:find("mapOverviewStatus=UNAVAILABLE", 1, true) ~= nil, true, "HUD should expose the missing raster API")
assertEquals(renderedCompact:find("semanticsReason=MAP_OVERVIEW_UNAVAILABLE", 1, true) ~= nil, true, "HUD should expose the exact semantics failure")
assertEquals(renderedCompact:find("currentSemanticsProbe=UNAVAILABLE", 1, true) ~= nil, true, "HUD should expose current probe availability")
assertEquals(renderedCompact:find("lastProductionSemanticsStatus=UNAVAILABLE", 1, true) ~= nil, true, "HUD should expose last production availability")
assertEquals(renderedCompact:find("map=ROUTE_2 ecologyEnabled=yes populationMap=NONE environment=N/A", 1, true) ~= nil, true, "not-run HUD should expose enabled ecology without stale population ownership")
assertEquals(renderedCompact:find("candidateStatus=NOT_RUN", 1, true) ~= nil, true, "not-run HUD should expose candidate status")
assertEquals(renderedCompact:find("attempts=0 valid=0 rejected=0", 1, true) ~= nil, true, "not-run HUD should show actual zero attempts")

return true