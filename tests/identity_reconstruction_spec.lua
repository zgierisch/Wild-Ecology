local Config = require("src.core.config")
local Perception = require("src.world.perception")

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
			return { mapId = currentMapId }
		end,
		spawnNpc = function(_, mapId, _objDef)
			nextNpcSerial = nextNpcSerial + 1
			local npcId = mapId .. "_obj_" .. tostring(nextNpcSerial)
			spawnCalls[#spawnCalls + 1] = npcId
			return npcId
		end,
		npc = function(_, _mapId, _npcId)
			return {}
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

-- 1-3. Enter route and spawn persistent phase-0 entity.
WildEcology.init(mod)
assertEquals(#spawnCalls, Config.phase3.visibleSubsetSize, "entering route should spawn the visible subset")

local Save = require("src.core.save")
local liveState = Save.getState()
local routePopulation = liveState
	and liveState.populations
	and liveState.populations[Config.phase0.testMapId]
if not routePopulation or not routePopulation.members then
	error("phase0 route population should exist in storage")
end
local persistent = routePopulation.members[Config.phase0.testEntityId]
if not persistent then
	error("phase0 persistent entity should exist in storage")
end
assertEquals(persistent.id, "wild:route01:0001", "phase0 entity id should be stable")

-- 4. Seed familiarity toward player and lock calm gain cooldown for re-entry.
local rel = persistent.relationships and persistent.relationships.player
if not rel then
	error("player relationship should exist after initial spawn")
end
rel.familiarity = 12
rel.lastCalmTick = liveState.simulationTick or 0
local companionId = routePopulation.order[2]
local companion = routePopulation.members[companionId]
Perception.observe(persistent, {
	{ name = Perception.EVENTS.ENTITY_SEEN, targetEntityId = companion.id }
}, liveState.simulationTick or 0)
local interPokemonRelationship = persistent.relationships[companion.id]
interPokemonRelationship.trust = 7
interPokemonRelationship.affinity = 4
local familiarityBeforeDespawn = interPokemonRelationship.familiarity
local affinityBeforeDespawn = interPokemonRelationship.affinity

-- 5-6. Leave route and confirm runtime avatar was destroyed.
local firstAvatarId = spawnCalls[1]
currentMapId = "ROUTE_2"
WildEcology.shutdown()
assertEquals(#removeCalls, Config.phase3.visibleSubsetSize, "leaving route should despawn the visible subset")
assertEquals(removeCalls[1], firstAvatarId, "despawn should target the first runtime avatar")

-- 7-10. Re-enter route, rebuild runtime avatar, preserve persistent relationship.
currentMapId = Config.phase0.testMapId
WildEcology.init(mod)
assertEquals(#spawnCalls, Config.phase3.visibleSubsetSize * 2, "re-entering route should spawn a fresh visible subset")
assertEquals(spawnCalls[2] ~= firstAvatarId, true, "re-entry should rebuild a new runtime avatar id")

local reloadedState = Save.getState()
local reloaded = reloadedState
	and reloadedState.populations
	and reloadedState.populations[Config.phase0.testMapId]
	and reloadedState.populations[Config.phase0.testMapId].members
	and reloadedState.populations[Config.phase0.testMapId].members[Config.phase0.testEntityId]
if not reloaded then
	error("persistent entity should still exist after route re-entry")
end
assertEquals(reloaded.id, "wild:route01:0001", "same persistent entity should be reloaded")

local reloadedRel = reloaded.relationships and reloaded.relationships.player
if not reloadedRel then
	error("player relationship should persist after route re-entry")
end
assertEquals(reloadedRel.familiarity, 12, "player familiarity should survive runtime avatar reconstruction")
assertEquals(reloaded.relationships[companionId].familiarity >= familiarityBeforeDespawn,
	true, "inter-Pokemon familiarity should survive or gain after reconstruction")
assertEquals(reloaded.relationships[companionId].trust, 7,
	"directed inter-Pokemon trust should survive route re-entry")
assertEquals(reloaded.relationships[companionId].affinity >= affinityBeforeDespawn,
	true, "directed inter-Pokemon affinity should remain attached to the target ID")
assertEquals(reloaded.relationships[persistent.id], nil,
	"route re-entry must not mirror the observer's relationship onto itself")

return true
