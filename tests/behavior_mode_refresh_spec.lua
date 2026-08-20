local Config = require("src.core.config")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function unloadModule(name)
	package.loaded[name] = nil
end

unloadModule("main")
unloadModule("src.core.save")
unloadModule("src.population.manager")
unloadModule("src.world.avatar_factory")
unloadModule("src.behavior.controller")

local storedState = nil
local currentMapId = Config.phase0.testMapId
local spawnCalls = {}
local removeCalls = {}
local handlesById = {}
local nextNpcSerial = 0
local behaviorMode = "FORCE FLEE"

local mod = {
	storage = {
		get = function(_)
			return storedState
		end,
		set = function(_, value)
			storedState = value
		end
	},
	world = {
		current = function(_)
			return { mapId = currentMapId }
		end,
		spawnNpc = function(_, mapId, objDef)
			nextNpcSerial = nextNpcSerial + 1
			local npcId = mapId .. "_obj_" .. tostring(nextNpcSerial)
			spawnCalls[#spawnCalls + 1] = { npcId = npcId, movement = objDef.movement, range = objDef.range }
			return npcId
		end,
		npc = function(_, _mapId, npcId)
			handlesById[npcId] = handlesById[npcId] or {
				npc = {
					kind = "walk",
					roamDirs = { "up", "down", "left", "right" },
					radiusX = 3,
					radiusY = 3,
					facing = "down"
				}
			}
			return handlesById[npcId]
		end,
		removeNpc = function(_, npcId)
			removeCalls[#removeCalls + 1] = npcId
			return true
		end
	},
	options = {
		define = function(_, _rows)
			return nil
		end,
		get = function(_, key)
			if key == "phase0_behavior_mode" then
				return behaviorMode
			end
			if key == "phase0_debug_log" then
				return false
			end
			if key == "dev_log_view" then
				return "both"
			end
			if key == "dev_log_lifecycle" or key == "dev_log_behavior" or key == "dev_log_relationships" then
				return true
			end
			return nil
		end
	}
}

local entry = require("main")
local WildEcology = entry(mod)
if not WildEcology then
	error("main entry should return WildEcology module API")
end

WildEcology.init(mod)
assertEquals(#spawnCalls, 1, "initial load should spawn one avatar")
assertEquals(spawnCalls[1].movement, "WALK", "force flee should produce walking movement")
local firstNpcId = spawnCalls[1].npcId
local firstHandle = handlesById[firstNpcId]
if not firstHandle then
	error("first avatar handle should be available")
end
local firstDebugState = storedState and storedState.debug and storedState.debug.phase0 or nil
if not firstDebugState then
	error("debug state should exist after initial spawn")
end
assertEquals(firstDebugState.lastState, "FLEE", "debug state should reflect flee after initial spawn")

behaviorMode = "FORCE IDLE"
WildEcology.init(mod)

assertEquals(#removeCalls, 0, "changing behavior mode in-zone should not despawn the active avatar")
assertEquals(#spawnCalls, 1, "changing behavior mode in-zone should not respawn the avatar")
assertEquals(firstHandle.movement, "STAY", "force idle should update movement in place")
assertEquals(firstHandle.range, "DOWN", "force idle should update range in place")
assertEquals(firstHandle.npc.kind, "stand", "force idle should mutate runtime npc behavior in place")
assertEquals(firstHandle.npc.facing, "down", "force idle should update runtime facing")
local secondDebugState = storedState and storedState.debug and storedState.debug.phase0 or nil
if not secondDebugState then
	error("debug state should exist after in-zone behavior refresh")
end
assertEquals(secondDebugState.lastBehaviorMode, "force_idle", "debug state should update to the new behavior mode")
assertEquals(secondDebugState.lastState, "IDLE", "debug state should update to the new runtime state")
assertEquals(secondDebugState.lastEvent, "mode_change", "debug state should label in-zone mode changes distinctly")

behaviorMode = "idle"
WildEcology.init(mod)
assertEquals(#removeCalls, 0, "normalized idle aliases should still apply in place")
assertEquals(#spawnCalls, 1, "normalized idle aliases should not trigger respawn")
local thirdDebugState = storedState and storedState.debug and storedState.debug.phase0 or nil
if not thirdDebugState then
	error("debug state should exist after normalized idle alias update")
end
assertEquals(thirdDebugState.lastBehaviorMode, "force_idle", "idle alias should normalize to force_idle")
assertEquals(thirdDebugState.lastState, "IDLE", "idle alias should preserve idle state")

behaviorMode = "flee"
WildEcology.init(mod)
assertEquals(#removeCalls, 0, "flee alias should not despawn")
assertEquals(#spawnCalls, 1, "flee alias should not respawn")
assertEquals(firstHandle.npc.kind, "walk", "flee alias should restore runtime walk behavior")
assertEquals(firstHandle.npc.radiusX, 3, "flee alias should preserve walk radius")
assertEquals(firstHandle.npc.radiusY, 3, "flee alias should preserve walk radius")

return true