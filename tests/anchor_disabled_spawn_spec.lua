local Config = require("src.core.config")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function assertGreaterThan(actual, minimum, message)
	if actual <= minimum then
		error((message or "should be greater than " .. tostring(minimum)) .. ": got " .. tostring(actual))
	end
end

local storedState = nil
local currentMapId = "ROUTE_2"  -- non-anchor map
local registeredScreens = {}
local wrappedHooks = {}
local handlesById = {}
local nextNpcSerial = 0
local optionValues = {
	phase0_behavior_mode = "force_flee",
	phase2_social_fear = true,
	phase2_social_reassurance = false
}
local saveValues = {
	phase0_debug_log = true,
	dev_log_view = "both",
	dev_log_lifecycle = true,
	dev_log_behavior = true,
	dev_log_relationships = false
}

local mod = {
	storage = {
		read = function(_, _game, _key)
			return storedState, storedState == nil and "not_found" or nil
		end,
		write = function(_, _game, _key, value)
			storedState = value
			return true
		end,
		writeBytes = function(_, _game, key, bytes)
			return true
		end
	},
	game = {},
	world = {
		current = function(_)
			return { mapId = currentMapId }
		end,
		spawnNpc = function(_, mapId, _objDef)
			nextNpcSerial = nextNpcSerial + 1
			return mapId .. "_obj_" .. tostring(nextNpcSerial)
		end,
		npc = function(_, _mapId, npcId)
			handlesById[npcId] = handlesById[npcId] or {}
			return handlesById[npcId]
		end,
		removeNpc = function(_, _npcId)
			return true
		end
	},
	content = {
		screens = {
			register = function(_, id, factory)
				registeredScreens[id] = factory
			end
		}
	},
	hooks = {
		wrap = function(_, id, wrapper)
			wrappedHooks[id] = wrapper
		end
	},
	options = {
		define = function(_, rows)
		end,
		get = function(_, key)
			return optionValues[key]
		end
	},
	save = {
		get = function(_, key, default)
			local value = saveValues[key]
			if value == nil then
				return default
			end
			return value
		end,
		set = function(_, key, value)
			saveValues[key] = value
		end
	},
	ui = {
		Font = {
			drawBox = function() end,
			draw = function() end
		}
	}
}

local entry = require("main")
local WildEcology = entry(mod)

if not WildEcology then
	error("main entry should return WildEcology module API")
end

-- This test is for a non-anchor map (ROUTE_2)
-- We should still get cohort spawning even though anchor is not active
WildEcology.init(mod)

local spawnDiag = WildEcology.spawnDiagnostics
print("=== Anchor-Disabled Spawn Test (Non-Anchor Map) ===")
print("persistent:", spawnDiag.populationPersistentTotal)
print("eligible:", spawnDiag.populationEligibleTotal)
print("selected:", spawnDiag.populationSelectedTotal)
print("phase3Entered:", spawnDiag.phase3Entered)
print("phase3LoopEntered:", spawnDiag.phase3LoopEntered)
print("phase3DispatchAttempts:", spawnDiag.phase3DispatchAttempts)
print("phase3LastBlocker:", spawnDiag.phase3LastBlocker)
print("mat ok:", spawnDiag.materializeSuccess)
print("mat fail:", spawnDiag.materializeFailure)
print("cohort calls:", spawnDiag.cohortCalls)
print("anchor calls:", spawnDiag.anchorCalls)

-- ASSERTIONS for non-anchor map
assertEquals(spawnDiag.phase3Entered, 1, "phase3Avatars should be called once for non-anchor map")
assertEquals(spawnDiag.phase3LoopEntered, 1, "loop should be entered if visible population exists")

if spawnDiag.populationSelectedTotal > 0 then
	assertGreaterThan(spawnDiag.phase3DispatchAttempts, 0, "dispatch attempts should happen if selected > 0")
	assertGreaterThan(spawnDiag.materializeSuccess + spawnDiag.materializeFailure, 0, "should attempt materialization")
end

assertEquals(spawnDiag.anchorCalls, 0, "anchor should not be spawned on non-anchor map")
assertEquals(spawnDiag.phase3LastBlocker, "SUCCESS", "blocker should show SUCCESS if cohort was materialized")

print("✓ Test passed: Cohort spawns independently of anchor on non-anchor maps")
