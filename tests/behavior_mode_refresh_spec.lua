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
		read = function(_, _game, _key)
			return storedState, storedState == nil and "not_found" or nil
		end,
		write = function(_, _game, _key, value)
			storedState = value
			return true
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
			return nil
		end
	},
	save = {
		get = function(_, key, default)
			local overrides = {
				phase0_debug_log = false,
				dev_log_view = "both",
				dev_log_lifecycle = true,
				dev_log_behavior = true,
				dev_log_relationships = true
			}
			local value = overrides[key]
			if value == nil then
				return default
			end
			return value
		end,
		set = function() end
	}
}

local entry = require("main")
local WildEcology = entry(mod)
if not WildEcology then
	error("main entry should return WildEcology module API")
end

WildEcology.init(mod)
assertEquals(#spawnCalls, Config.phase3.visibleSubsetSize, "initial load should spawn the visible subset")
assertEquals(spawnCalls[1].movement, "STAY", "force flee should disable ambient wandering")
local firstNpcId = spawnCalls[1].npcId
local firstHandle = handlesById[firstNpcId]
if not firstHandle then
	error("first avatar handle should be available")
end
local firstDebugState = storedState and storedState.debug and storedState.debug.phase0 or nil
if not firstDebugState then
	error("debug state should exist after initial spawn")
end
local firstScores = firstDebugState.lastBehaviorScores or {}
local firstInputs = firstDebugState.debugPresetInputs or {}
assertEquals(firstDebugState.lastState, "FLEE", string.format(
	"FLEE preset should emerge from normal scoring FLEE=%.2f APPROACH=%.2f INVESTIGATE=%.2f TARGET=%.2f IDLE=%.2f reason=%s inputs=trust:%s threat:%s fear:%s boldness:%s",
	firstScores.FLEE or 0, firstScores.APPROACH or 0, firstScores.INVESTIGATE or 0,
	firstScores.TARGET or 0, firstScores.IDLE or 0,
	tostring(firstDebugState.selectionReason or "unknown") .. " preset=" .. tostring(firstDebugState.debugPreset),
	tostring(firstInputs.trust), tostring(firstInputs.threatMemory), tostring(firstInputs.currentFear),
	tostring(firstInputs.boldness)))

behaviorMode = "FORCE IDLE"
WildEcology.init(mod)

assertEquals(#removeCalls, 0, "changing behavior mode in-zone should not despawn the active avatar")
assertEquals(#spawnCalls, Config.phase3.visibleSubsetSize, "changing behavior mode in-zone should not respawn avatars")
local secondDebugState = storedState and storedState.debug and storedState.debug.phase0 or nil
if not secondDebugState then
	error("debug state should exist after in-zone behavior refresh")
end
assertEquals(secondDebugState.lastBehaviorMode, "force_idle", "debug state should update to the new behavior mode")
assertEquals(secondDebugState.debugPreset, "IDLE", "live refresh should apply the IDLE input preset")
assertEquals(secondDebugState.debugPresetInputs.currentFear, 0, "IDLE preset should replace current fear with calm input")
assertEquals(secondDebugState.debugPresetInputs.hasTarget, false, "IDLE preset should remove purposeful target input")
assertEquals(secondDebugState.lastEvent, "mode_change", "debug state should label in-zone mode changes distinctly")

behaviorMode = "idle"
WildEcology.init(mod)
assertEquals(#removeCalls, 0, "normalized idle aliases should still apply in place")
assertEquals(#spawnCalls, Config.phase3.visibleSubsetSize, "normalized idle aliases should not trigger respawn")
local thirdDebugState = storedState and storedState.debug and storedState.debug.phase0 or nil
if not thirdDebugState then
	error("debug state should exist after normalized idle alias update")
end
assertEquals(thirdDebugState.lastBehaviorMode, "force_idle", "idle alias should normalize to force_idle")
assertEquals(thirdDebugState.debugPreset, "IDLE", "idle alias should preserve the IDLE counterfactual")

behaviorMode = "flee"
WildEcology.init(mod)
assertEquals(#removeCalls, 0, "flee alias should not despawn")
assertEquals(#spawnCalls, Config.phase3.visibleSubsetSize, "flee alias should not respawn")
assertEquals(storedState.debug.phase0.debugPreset, "FLEE", "flee alias should apply the FLEE counterfactual")
assertEquals(storedState.debug.phase0.debugPresetInputs.threatMemory, 20, "FLEE should supply legitimate threat memory input")

behaviorMode = "FORCE APPROACH"
WildEcology.init(mod)
assertEquals(#removeCalls, 0, "force approach should not despawn")
assertEquals(#spawnCalls, Config.phase3.visibleSubsetSize, "force approach should not respawn")
if not storedState or not storedState.debug or not storedState.debug.phase0 then
	error("force approach should update persisted debug state")
end
assertEquals(storedState.debug.phase0.debugPreset, "APPROACH", "force approach should apply the APPROACH counterfactual")
assertEquals(storedState.debug.phase0.debugPresetInputs.trust, 90, "APPROACH should supply high trust input")

behaviorMode = "FORCE INVESTIGATE"
WildEcology.init(mod)
assertEquals(#removeCalls, 0, "force investigate should not despawn")
assertEquals(#spawnCalls, Config.phase3.visibleSubsetSize, "force investigate should not respawn")
assertEquals(storedState.debug.phase0.debugPreset, "INVESTIGATE", "force investigate should apply the INVESTIGATE counterfactual")
assertEquals(storedState.debug.phase0.debugPresetInputs.currentFear, 0, "INVESTIGATE should supply calm input")

behaviorMode = "FORCE TARGET"
WildEcology.init(mod)
assertEquals(storedState.debug.phase0.debugPreset, "TARGET", "force target should apply the TARGET counterfactual")
if (storedState.debug.phase0.lastBehaviorScores.TARGET or 0) <= (storedState.debug.phase0.lastBehaviorScores.IDLE or 0) then
	error("TARGET counterfactual should favor TARGET through restlessness utility")
end

behaviorMode = "IGNORE PLAYER"
WildEcology.init(mod)
assertEquals(storedState.debug.phase0.lastTargetEntityId, nil, "ignore player should remove player as a behavior target")

return true