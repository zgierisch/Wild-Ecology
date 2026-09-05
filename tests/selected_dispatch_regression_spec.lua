--[[
This test attempts to reproduce the exact condition reported in live ROUTE_22:
  selected = 15
  phase3Entered = 1
  phase3LoopEntered = ?
  phase3DispatchAttempts = 0 (or very low)
  mat ok = 0
  mat fail = 0

This would indicate that either:
1. The loop isn't entering
2. All entities are being filtered before dispatch
3. AvatarFactory is not available
4. Some other early-return condition

The test will try various hypotheses.
]]

local Config = require("src.core.config")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

-- Test 1: Verify phase3LoopEntered increments when we have visible population
print("=== Test 1: Loop Entry Verification ===")

local storedState = nil
local currentMapId = "ROUTE_3"
local mod = {
	storage = {
		read = function(_, _game, _key)
			return storedState, storedState == nil and "not_found" or nil
		end,
		write = function(_, _game, _key, value)
			storedState = value
			return true
		end,
		writeBytes = function() return true end
	},
	game = {},
	world = {
		current = function(_) return { mapId = currentMapId } end,
		spawnNpc = function(_, mapId) return mapId .. "_obj_1" end,
		npc = function() return {} end,
		removeNpc = function() return true end
	},
	content = { screens = { register = function() end } },
	hooks = { wrap = function() end },
	options = {
		define = function() end,
		get = function() return true end
	},
	save = {
		get = function(_, key, default) 
			local vals = { phase0_debug_log=true, dev_log_view='both', dev_log_lifecycle=true, dev_log_behavior=true }
			local v = vals[key]
			return v or default
		end,
		set = function() end
	},
	ui = { Font = { drawBox = function() end, draw = function() end } }
}

local entry = require("main")
local WildEcology = entry(mod)
WildEcology.init(mod)

local rt = WildEcology.spawnDiagnostics
print("Selected:", rt.populationSelectedTotal)
print("Phase3Entered:", rt.phase3Entered)
print("Phase3LoopEntered:", rt.phase3LoopEntered)
print("Phase3DispatchAttempts:", rt.phase3DispatchAttempts)
print("Phase3LastBlocker:", rt.phase3LastBlocker)

if rt.populationSelectedTotal > 0 then
	assertEquals(rt.phase3LoopEntered, 1, "if selected > 0, loop should be entered")
	-- On non-anchor maps, all selected entities should attempt dispatch
	assertEquals(rt.phase3DispatchAttempts, rt.populationSelectedTotal, "all selected should attempt dispatch")
	if rt.phase3DispatchAttempts > 0 then
		assertEquals(rt.materializeSuccess + rt.materializeFailure, rt.phase3DispatchAttempts, "dispatch attempts should result in materialization calls")
	end
else
	print("WARNING: populationSelectedTotal is 0 - cannot test dispatch logic")
end

print("✓ Loop entry test passed")
print()

-- Test 2: Try with empty population
print("=== Test 2: Empty Population Handling ===")
storedState = nil
currentMapId = "ROUTE_UNUSED"

local WildEcology2 = entry(mod)
WildEcology2.init(mod)

local rt2 = WildEcology2.spawnDiagnostics
print("Selected:", rt2.populationSelectedTotal)
print("Phase3Entered:", rt2.phase3Entered)
print("Phase3LoopEntered:", rt2.phase3LoopEntered)
print("Phase3DispatchAttempts:", rt2.phase3DispatchAttempts)
print("Phase3LastBlocker:", rt2.phase3LastBlocker)

if rt2.populationSelectedTotal == 0 then
	assertEquals(rt2.phase3DispatchAttempts, 0, "no dispatch if no selection")
	assertEquals(rt2.materializeSuccess, 0, "no materialization if no dispatch")
	print("✓ Empty population handled correctly")
else
	print("✓ Non-empty population for this route")
end
