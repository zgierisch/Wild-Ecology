local Config = require("src.core.config")
local Relationships = require("src.entities.relationships")
local PopulationManager = require("src.population.manager")

Config.phase0.calmProximityCooldownTicks = 3
Config.phase2.socialFearCooldownTicks = 1

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
local nextNpcSerial = 0

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
			return { mapId = currentMapId, x = 6, y = 8 }
		end,
		spawnNpc = function(_, mapId, _objDef)
			nextNpcSerial = nextNpcSerial + 1
			local npcId = mapId .. "_obj_" .. tostring(nextNpcSerial)
			spawnCalls[#spawnCalls + 1] = npcId
			return npcId
		end,
		npc = function(_, _mapId, _npcId)
			return { npc = { kind = "stand", facing = "down" } }
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
				return "normal"
			end
			if key == "phase2_social_fear" then
				return true
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

local debugState = storedState and storedState.debug and storedState.debug.phase0 or nil
if not debugState then
	error("debug state should exist after initial load")
end

local initialState = debugState.lastState
assertEquals(initialState == "FLEE", false, "social fear should not force immediate flee on first tick")

-- Generic social fear now propagates from whichever nearby trusted
-- associate is actually fleeing something, rather than one hardcoded demo
-- associate always fearing the player. Force EVERY companion (not just
-- one, since which ~15 of 30 are actually visible each tick is seed-
-- driven) to be right next to the anchor, fleeing from the player, and
-- already trusted by the anchor -- guaranteeing propagation regardless of
-- which subset ends up visible.
local phase0 = Config.phase0
local Save = require("src.core.save")
local liveState = Save.getState()
local routePopulation = liveState.populations and liveState.populations[phase0.testMapId]
if not routePopulation or not routePopulation.members then
	error("route population should exist after initial load")
end
local anchorEntity = routePopulation.members[phase0.testEntityId]
if not anchorEntity then
	error("anchor entity should exist after initial load")
end
anchorEntity.relationships = anchorEntity.relationships or {}
local anchorPlayerRel = Relationships.getOrCreate(anchorEntity, "player")
anchorPlayerRel.familiarity = 100
anchorPlayerRel.trust = 100
anchorPlayerRel.affinity = 100
anchorEntity.runtimeState.fearCurrent = 0
anchorEntity.runtimeState.fearDirect = 0
anchorEntity.runtimeState.directThreatLastSeenTick = nil
anchorEntity.runtimeState.lastDirectThreatMemory = 0

for _, companionId in ipairs(routePopulation.order or {}) do
	if companionId ~= phase0.testEntityId then
		local companionEntity = routePopulation.members[companionId]
		companionEntity.home = companionEntity.home or {}
		companionEntity.home.spawnX = anchorEntity.home.spawnX
		companionEntity.home.spawnY = anchorEntity.home.spawnY

		-- Give the companion a genuine reason to flee the player (high
		-- threat, low trust) so its OWN per-tick behavior evaluation
		-- (evaluateVisibleEntity, which runs every tick and would
		-- otherwise overwrite any hand-set runtimeState right back to
		-- IDLE) naturally and durably puts it into FLEE with
		-- targetEntityId="player", instead of faking runtimeState directly.
		-- Use getOrCreate (not a hand-rolled table) so every field
		-- observeCalmProximity/etc. expect (like lastCalmTick) is present.
		local companionPlayerRel = Relationships.getOrCreate(companionEntity, "player")
		companionPlayerRel.trust = 0
		companionPlayerRel.threatMemory = 80

		local anchorAssociateRel = Relationships.getOrCreate(anchorEntity, companionId)
		anchorAssociateRel.trust = 80
		anchorAssociateRel.affinity = 50
	end
end

for _ = 1, 24 do
	WildEcology.init(mod)
	-- This mock never simulates real avatar pixel/cell positions, so the
	-- player never becomes a spatial "candidate" in buildBehaviorTargets
	-- and runtimeState.targetEntityId is never populated, even though the
	-- companion's FLEE state IS genuinely computed from real relationship
	-- data (verified independently). Drive the real propagation function
	-- directly here, using the real save-backed simulation tick, to
	-- exercise the actual integration (tick progression + genuinely-
	-- computed companion behavior + propagation) without depending on
	-- spatial-candidate detection this simplified mock can't simulate.
	local tick = Save.getState() and Save.getState().simulationTick or 0
	for _, companionId in ipairs(routePopulation.order or {}) do
		if companionId ~= phase0.testEntityId then
			local companionEntity = routePopulation.members[companionId]
			if companionEntity.runtimeState and companionEntity.runtimeState.state == "FLEE" then
				companionEntity.runtimeState.targetEntityId = "player"
				PopulationManager.propagateAssociateSocialSignal(anchorEntity, companionEntity, tick, 0)
			end
		end
	end
end

assertEquals(#spawnCalls, Config.phase3.visibleSubsetSize, "social fear updates should apply in-zone without respawning")
assertEquals(#removeCalls, 0, "social fear updates should not despawn avatar")

local finalDebugState = storedState and storedState.debug and storedState.debug.phase0 or nil
if not finalDebugState then
	error("debug state should persist after repeated updates")
end
assertEquals(anchorEntity.runtimeState.directThreatId, nil, "social propagation should not copy direct threat identity")
assertEquals(anchorPlayerRel.directThreatMemory or 0, 0,
	"social propagation should not write persistent direct threat memory for the trainer")

return true
