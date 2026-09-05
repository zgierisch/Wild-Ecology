local Config = require("src.core.config")

Config.phase0.calmProximityCooldownTicks = 90

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

-- Memory.recordEvent caps an entity's event history at 50 entries (oldest
-- evicted first), so an index-based "scan from where we were" check would
-- break once that cap is hit and the array starts shifting. Scan the tail
-- instead, which stays valid either way.
local function assertRecentEvent(events, eventName, message, lookback)
	lookback = lookback or 12
	local start = math.max(1, #events - lookback + 1)
	for index = start, #events do
		if events[index].event == eventName then
			return
		end
	end
	error(message or ("expected event " .. eventName))
end

local function unloadModule(name)
	package.loaded[name] = nil
end

unloadModule("main")
unloadModule("src.core.save")
unloadModule("src.population.manager")
unloadModule("src.world.avatar_factory")
unloadModule("src.behavior.controller")
unloadModule("src.world.perception")

local storedState = nil
local currentMapId = Config.phase0.testMapId
local playerX = 6
local playerY = 8
local playerPositionAvailable = true
local livePlayerPosition = nil
local spawnCalls = {}
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
			if not playerPositionAvailable then
				return { mapId = currentMapId }
			end
			return { mapId = currentMapId, x = playerX, y = playerY }
		end,
		player = livePlayerPosition,
		spawnNpc = function(_, mapId, objDef)
			nextNpcSerial = nextNpcSerial + 1
			local npcId = mapId .. "_obj_" .. tostring(nextNpcSerial)
			spawnCalls[#spawnCalls + 1] = { id = npcId, objDef = objDef }
			return npcId
		end,
		npc = function(_, _mapId, _npcId)
			return { npc = { kind = "stand", facing = "down" } }
		end,
		removeNpc = function(_, _npcId)
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
				dev_log_lifecycle = false,
				dev_log_behavior = false,
				dev_log_relationships = false
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
WildEcology.init(mod)
local Save = require("src.core.save")

assertEquals(#spawnCalls, Config.phase3.visibleSubsetSize, "runtime perception should preserve visible subset spawning")
if not storedState or not storedState.populations or not storedState.populations[Config.phase0.testMapId] then
	error("runtime perception should persist the route population")
end
local routePopulation = Save.getState().populations[Config.phase0.testMapId]
if not routePopulation.members or not routePopulation.members[Config.phase0.testEntityId] then
	error("runtime perception should persist the anchor entity")
end
local anchor = routePopulation.members[Config.phase0.testEntityId]
local anchorEvents = anchor.memory and anchor.memory.events or {}
assertEquals(#anchorEvents > 0, true, "visible runtime entities should produce perception events")
assertEquals(anchor.relationships.player.familiarity > 0, true, "player should be perceived through the generic runtime path")

-- Re-anchor the player exactly on the anchor's actual assigned spawn cell
-- (which now scatters across real walkable cells rather than a fixed
-- coordinate) so the retreat/approach checks below have a stable,
-- colocated baseline distance regardless of which cell got picked.
playerX = anchor.home.spawnX
playerY = anchor.home.spawnY
WildEcology.init(mod)

playerX = anchor.home.spawnX + 2
WildEcology.init(mod)
playerX = anchor.home.spawnX + 4
WildEcology.init(mod)
assertRecentEvent(anchor.memory.events, "ENTITY_RETREATING", "moving away should produce a retreating event")

playerX = anchor.home.spawnX + 2
WildEcology.init(mod)
playerX = anchor.home.spawnX
WildEcology.init(mod)
assertRecentEvent(anchor.memory.events, "ENTITY_APPROACHING", "moving toward the anchor should produce an approaching event")

playerX = 10
playerY = -1
WildEcology.init(mod)
assertEquals(playerPositionAvailable, true, "an out-of-body public x/y position should remain valid behavior input")

playerPositionAvailable = false
WildEcology.init(mod)
assertRecentEvent(anchor.memory.events, "ENTITY_LOST", "missing target position should produce a lost event")
assertEquals(anchor.memory.events[1].payload.targetEntityId ~= nil, true, "runtime events should persist stable target IDs")

return true