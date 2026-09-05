local WorldSemantics = require("src.world.world_semantics")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function overview()
	return { mapId = "PROBE_MAP", width = 2, height = 1, rows = { ".." } }
end

local missingWorld = WorldSemantics.probeFromMod(nil, "PROBE_MAP")
assertEquals(missingWorld.semanticsReason, "MOD_WORLD_MISSING", "missing mod.world should be explicit")

local missingMethod = WorldSemantics.probeFromMod({ world = {} }, "PROBE_MAP")
assertEquals(missingMethod.mapOverviewStatus, "UNAVAILABLE", "missing mapOverview should be unavailable")
assertEquals(missingMethod.semanticsReason, "MAP_OVERVIEW_UNAVAILABLE", "missing mapOverview should name the API prerequisite")

local throwing = WorldSemantics.probeFromMod({
	world = { mapOverview = function() error("overview exploded") end }
}, "PROBE_MAP")
assertEquals(throwing.mapOverviewStatus, "ERROR", "throwing mapOverview should be an error")
assertEquals(throwing.semanticsReason, "MAP_OVERVIEW_ERROR", "throwing mapOverview should have a stable reason")
assertEquals(throwing.mapOverviewError:find("overview exploded", 1, true) ~= nil, true, "probe should retain a short call error")

local nilOverview = WorldSemantics.probeFromMod({
	world = { mapOverview = function() return nil end }
}, "PROBE_MAP")
assertEquals(nilOverview.mapOverviewStatus, "NIL", "nil mapOverview result should be distinct")
assertEquals(nilOverview.semanticsReason, "MAP_OVERVIEW_NIL", "nil mapOverview should have a stable reason")

local missingRows = WorldSemantics.probeFromMod({
	world = { mapOverview = function() return { mapId = "PROBE_MAP" } end }
}, "PROBE_MAP")
assertEquals(missingRows.semanticsReason, "MAP_OVERVIEW_ROWS_MISSING", "missing raster rows should be explicit")

local invalidRows = WorldSemantics.probeFromMod({
	world = { mapOverview = function() return { mapId = "PROBE_MAP", rows = { 42 } } end }
}, "PROBE_MAP")
assertEquals(invalidRows.semanticsReason, "MAP_OVERVIEW_ROWS_INVALID", "malformed raster rows should not throw")

local rasterOnlyMod = { world = { mapOverview = overview } }
local rasterOnly = WorldSemantics.probeFromMod(rasterOnlyMod, "PROBE_MAP")
assertEquals(rasterOnly.mapOverviewStatus, "OK", "valid raster should be accepted")
assertEquals(rasterOnly.topologyStatus, "UNAVAILABLE", "missing topology inputs should remain visible")
assertEquals(rasterOnly.topologyReason, "MOD_GAME_MISSING", "topology should report its independent prerequisite")
assertEquals(rasterOnly.semanticsStatus, "READY", "valid raster should build semantics without topology")
assertEquals(rasterOnly.semantics.environmentClass, "UNKNOWN", "missing topology should retain unknown environment")

local missingMapDef = WorldSemantics.probeFromMod({
	game = {
		overworld = { map = { id = "PROBE_MAP" } },
		data = { maps = {}, tilesets = {} }
	},
	world = { mapOverview = overview }
}, "PROBE_MAP")
assertEquals(missingMapDef.semanticsStatus, "READY", "valid raster should remain sufficient for semantics")
assertEquals(missingMapDef.topologyReason, "MAP_DEF_MISSING", "topology should name the missing active map definition")

WorldSemantics.clearCache()
assertEquals(WorldSemantics.fromMod({ world = {} }, "PROBE_MAP"), nil, "production API should preserve nil on unavailable raster")
local productionUnavailable = WorldSemantics.getLastProductionProbe("PROBE_MAP")
if not productionUnavailable then error("production failure probe should be retained") end
assertEquals(productionUnavailable.semanticsReason, "MAP_OVERVIEW_UNAVAILABLE", "production should retain its exact failure")

local availableMod = { world = { mapOverview = overview } }
local ready = WorldSemantics.fromMod(availableMod, "PROBE_MAP")
assertEquals(ready ~= nil, true, "a later available raster should build without stale unavailability")
local productionReady = WorldSemantics.getLastProductionProbe("PROBE_MAP")
if not productionReady then error("production success probe should be retained") end
assertEquals(productionReady.semanticsStatus, "READY", "last production result should advance to ready")

return true