local AvatarFactory = require("src.world.avatar_factory")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

-- Public API path: spawnNpc/removeNpc + npc handle attachment.
do
	local called = {}
	local handle = {}
	local mod = {
		world = {
			spawnNpc = function(_, mapId, objDef)
				called.mapId = mapId
				called.objDef = objDef
				return "ROUTE_1_obj_99"
			end,
			npc = function(_, mapId, npcId)
				called.handleLookup = { mapId = mapId, npcId = npcId }
				return handle
			end,
			removeNpc = function(_, npcId)
				called.removedNpcId = npcId
				return true
			end,
		}
	}

	local entity = {
		id = "wild:route01:0001",
		species = "PIDGEY",
		level = 4,
		home = { mapId = "ROUTE_1", spawnX = 8, spawnY = 9 },
		avatar = { movement = "WALK", range = "ANY", sprite = "SPRITE_BIRD" }
	}

	local avatar = AvatarFactory.spawn(mod, entity)
	if not avatar then
		error("public API spawn should return an avatar")
	end
	assertEquals(called.mapId, "ROUTE_1", "public API spawn should use entity home map")
	assertEquals(called.objDef.x, 8, "public API spawn should use configured x")
	assertEquals(called.objDef.y, 9, "public API spawn should use configured y")
	assertEquals(avatar.id, "ROUTE_1_obj_99", "avatar should keep npc id")
	assertEquals(handle.entityId, entity.id, "npc handle should carry entity id")

	AvatarFactory.despawn(mod, avatar)
	assertEquals(called.removedNpcId, "ROUTE_1_obj_99", "despawn should remove by npc id")
end

-- Public API path: fallback map from world:current() when entity home map is missing.
do
	local mapUsed = nil
	local mod = {
		world = {
			current = function(_)
				return { mapId = "ROUTE_22" }
			end,
			spawnNpc = function(_, mapId, _objDef)
				mapUsed = mapId
				return "ROUTE_22_obj_1"
			end,
		}
	}

	local entity = {
		id = "wild:route22:0001",
		species = "RATTATA",
		level = 3,
		home = {}
	}

	local avatar = AvatarFactory.spawn(mod, entity)
	if not avatar then
		error("spawn should return an avatar when map is resolved from world:current")
	end
	assertEquals(mapUsed, "ROUTE_22", "spawn should fall back to current map")
	assertEquals(avatar.mapId, "ROUTE_22", "avatar should store fallback map id")
end

-- Engine internals fallback remains isolated when public API is unavailable.
do
	local internalsCalled = false
	local mod = {
		engine_internals = {
			spawnNpc = function(_obj)
				internalsCalled = true
				return {}
			end
		}
	}
	local entity = {
		id = "wild:route01:0099",
		species = "PIDGEY",
		level = 4,
		home = { mapId = "ROUTE_1" }
	}

	local avatar = AvatarFactory.spawn(mod, entity)
	if not avatar then
		error("engine internals fallback should return an avatar")
	end
	assertEquals(internalsCalled, true, "engine internals should be fallback only")
	assertEquals(avatar.entityId, entity.id, "fallback avatar should also carry entity id")
end

return true
