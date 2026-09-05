local RuntimeAvatarAdapter = require("src.world.runtime_avatar_adapter")
local AvatarFactory = require("src.world.avatar_factory")
RuntimeAvatarAdapter.setAvatarFactory(AvatarFactory)

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function assertTrue(actual, message)
	if not actual then
		error((message or "assertTrue failed") .. ": expected truthy, got " .. tostring(actual))
	end
end

-- Materialization creates a fresh runtime avatar with proper adapter marking.
do
	local handle = { npc = { cellX = 5, cellY = 6, moving = false } }
	local mod = {
		world = {
			spawnNpc = function(_, mapId, objDef)
				return "MAP_obj_10"
			end,
			npc = function(_, _, npcId)
				return handle
			end
		}
	}
	local entity = {
		id = "wild:map:0001",
		species = "BULBASAUR",
		level = 5,
		home = { mapId = "MAP", spawnX = 5, spawnY = 6 },
		avatar = {}
	}
	
	local avatar = RuntimeAvatarAdapter.materialize(mod, entity, { cellX = 5, cellY = 6 }, "MAP")
	assertEquals(avatar.runtimeAdapter, "RuntimeAvatarAdapter", "materialized avatar should carry adapter identifier")
	assertEquals(avatar.id, "MAP_obj_10", "materialized avatar should have a runtime ID")
	assertEquals(avatar.entityId, entity.id, "materialized avatar should link to persistent entity")
end

-- Resolve retrieves the runtime handle when avatar exists.
do
	local handle = { npc = { cellX = 9, cellY = 10 } }
	local mod = {
		world = {
			npc = function(_, mapId, npcId)
				if npcId == "STORED_obj_1" then return handle end
				return nil
			end
		}
	}
	local avatar = { id = "STORED_obj_1", mapId = "STORED", entityId = "wild:stored:0001" }
	
	local resolved = RuntimeAvatarAdapter.resolve(mod, avatar)
	assertEquals(resolved, handle, "resolve should return the live runtime handle")
end

-- Resolve returns nil when avatar has no backing handle.
do
	local mod = {
		world = {
			npc = function(_, _, _)
				return nil
			end
		}
	}
	local avatar = { id = "MISSING_obj_1", mapId = "MAP", entityId = "wild:map:0001" }
	
	local resolved = RuntimeAvatarAdapter.resolve(mod, avatar)
	assertEquals(resolved, nil, "resolve should return nil when handle is unavailable")
end

-- readPosition extracts the normalized cell position from a materialized avatar.
do
	local handle = { npc = { cellX = 11, cellY = 12, moving = false } }
	local mod = {
		world = {
			npc = function(_, _, npcId)
				return handle
			end
		}
	}
	local avatar = { id = "POS_obj_1", mapId = "MAP", handle = handle }
	
	local position = RuntimeAvatarAdapter.readPosition(mod, avatar)
	assertEquals(position.cellX, 11, "readPosition should extract cellX")
	assertEquals(position.cellY, 12, "readPosition should extract cellY")
end

-- readPosition returns nil when avatar is not resolved.
do
	local mod = {
		world = {
			npc = function(_, _, _)
				return nil
			end
		}
	}
	local avatar = { id = "NOPOS_obj_1", mapId = "MAP" }
	
	local position = RuntimeAvatarAdapter.readPosition(mod, avatar)
	assertEquals(position, nil, "readPosition should return nil when handle unavailable")
end

-- destroy removes a materialized avatar and clears its runtime mapping.
do
	local despawnCalled = false
	local mod = {
		world = {
			removeNpc = function(_, npcId)
				if npcId == "DEL_obj_1" then
					despawnCalled = true
				end
				return true
			end
		}
	}
	local avatar = { id = "DEL_obj_1", mapId = "MAP", entityId = "wild:map:0001" }
	
	local result = RuntimeAvatarAdapter.destroy(mod, avatar)
	assertEquals(result, true, "destroy should return true on success")
	assertEquals(despawnCalled, true, "destroy should call the runtime backend removal")
end

-- Rematerialization on the same map reuses entity but creates fresh runtime.
do
	local spawnCount = 0
	local handles = {}
	local mod = {
		world = {
			spawnNpc = function(_, mapId, objDef)
				spawnCount = spawnCount + 1
				return mapId .. "_obj_" .. tostring(spawnCount)
			end,
			npc = function(_, _, npcId)
				if not handles[npcId] then
					handles[npcId] = { npc = { cellX = 8, cellY = 9 } }
				end
				return handles[npcId]
			end,
			removeNpc = function(_, npcId)
				return true
			end
		}
	}
	local entity = {
		id = "wild:map:0002",
		species = "CHARMANDER",
		level = 4,
		home = { mapId = "MAP", spawnX = 8, spawnY = 9,
			area = { mapId = "MAP", anchorCell = { cellX = 8, cellY = 9 },
				radius = 2, establishedTick = 12,
				provenance = "POPULATION_PLACEMENT" } },
		avatar = {}
	}
	local homeArea = entity.home.area
	
	local avatar1 = RuntimeAvatarAdapter.materialize(mod, entity, { cellX = 8, cellY = 9 }, "MAP")
	assertEquals(avatar1.id, "MAP_obj_1", "first materialization should get first npc id")
	
	RuntimeAvatarAdapter.destroy(mod, avatar1)
	assertEquals(spawnCount, 1, "despawn should not increment spawn count")
	
	local avatar2 = RuntimeAvatarAdapter.materialize(mod, entity, { cellX = 8, cellY = 9 }, "MAP")
	assertEquals(avatar2.id, "MAP_obj_2", "rematerialization should get a fresh npc id")
	assertEquals(avatar2.entityId, entity.id, "rematerialized avatar should link to same entity")
	assertEquals(avatar1.id ~= avatar2.id, true, "runtime ids should differ after despawn-rematerialize cycle")
	assertEquals(entity.home.area, homeArea,
		"rematerialization must not regenerate persistent home ecology")
end

-- Position reading is normalized to { cellX, cellY } regardless of handle structure.
do
	local npcHandle = { cellX = 7, cellY = 8, moving = false }
	local mod = {
		world = {
			npc = function(_, _, npcId)
				if npcId == "NORM_obj_1" then
					return { npc = npcHandle, ow = { map = { id = "MAP" } } }
				end
				return nil
			end
		}
	}
	local avatar = { id = "NORM_obj_1", mapId = "MAP" }
	
	local position = RuntimeAvatarAdapter.readPosition(mod, avatar)
	assertTrue(position.cellX == 7 and position.cellY == 8, "readPosition should normalize position from nested handle structure")
end

-- Stale avatar (pointing to a despawned runtime actor) gracefully returns nil.
do
	local mod = {
		world = {
			npc = function(_, _, npcId)
				return nil
			end
		}
	}
	local staleAvatar = { id = "STALE_obj_1", mapId = "GONE", entityId = "wild:gone:0001" }
	
	local resolved = RuntimeAvatarAdapter.resolve(mod, staleAvatar)
	assertEquals(resolved, nil, "resolve should return nil for stale avatar")
	
	local position = RuntimeAvatarAdapter.readPosition(mod, staleAvatar)
	assertEquals(position, nil, "readPosition should return nil for stale avatar")
end

-- Materialization fails gracefully when spawn returns nil.
do
	local mod = {
		world = {
			spawnNpc = function(_, _, _)
				return nil
			end
		}
	}
	local entity = {
		id = "wild:map:0003",
		species = "SQUIRTLE",
		level = 4,
		home = { mapId = "MAP", spawnX = 10, spawnY = 11 },
		avatar = {}
	}
	
	local avatar = RuntimeAvatarAdapter.materialize(mod, entity, { cellX = 10, cellY = 11 }, "MAP")
	assertEquals(avatar, nil, "materialize should return nil on spawn failure")
end

-- Materialization with engine_internals fallback still works through adapter.
do
	local internalNpc = {}
	local mod = {
		engine_internals = {
			spawnNpc = function(_)
				return internalNpc
			end
		}
	}
	local entity = {
		id = "wild:map:0004",
		species = "PIKACHU",
		level = 5,
		home = { mapId = "MAP", spawnX = 12, spawnY = 13 },
		avatar = {}
	}
	
	local avatar = RuntimeAvatarAdapter.materialize(mod, entity, { cellX = 12, cellY = 13 }, "MAP")
	if avatar then
		assertEquals(avatar.runtimeAdapter, "RuntimeAvatarAdapter", "fallback avatar should still carry adapter identifier")
	end
end

-- Multiple entities cannot map to the same runtime avatar (prevent duplicate live handles).
do
	local sharedHandle = { npc = { cellX = 15, cellY = 16 } }
	local mod = {
		world = {
			spawnNpc = function(_, mapId, objDef)
				return "SHARED_obj_1"
			end,
			npc = function(_, _, npcId)
				if npcId == "SHARED_obj_1" then return sharedHandle end
				return nil
			end
		}
	}
	
	local entity1 = {
		id = "wild:map:0005",
		species = "MEOWTH",
		level = 3,
		home = { mapId = "MAP", spawnX = 15, spawnY = 16 },
		avatar = {}
	}
	
	local entity2 = {
		id = "wild:map:0006",
		species = "PSYDUCK",
		level = 3,
		home = { mapId = "MAP", spawnX = 15, spawnY = 16 },
		avatar = {}
	}
	
	local avatar1 = RuntimeAvatarAdapter.materialize(mod, entity1, { cellX = 15, cellY = 16 }, "MAP")
	if avatar1 then
		assertEquals(avatar1.entityId, entity1.id, "first avatar should link to entity1")
		assertEquals(avatar1.id, "SHARED_obj_1", "first avatar gets the shared runtime id")
		
		local avatar2 = RuntimeAvatarAdapter.materialize(mod, entity2, { cellX = 15, cellY = 16 }, "MAP")
		if avatar2 then
			assertEquals(avatar2.entityId, entity2.id, "second avatar should link to entity2 (adapter tracks separately)")
		end
	end
end

-- Position normalization works when cellX/cellY come from the outer handle directly.
do
	local npcData = { cellX = 20, cellY = 21, moving = false }
	local handle = { npc = npcData }
	local mod = {
		world = {
			npc = function(_, _, npcId)
				if npcId == "FLAT_obj_1" then return handle end
				return nil
			end
		}
	}
	local avatar = { id = "FLAT_obj_1", mapId = "MAP", handle = handle }
	
	local position = RuntimeAvatarAdapter.readPosition(mod, avatar)
	if position then
		assertEquals(position.cellX, 20, "readPosition should read cellX from handle.npc")
		assertEquals(position.cellY, 21, "readPosition should read cellY from handle.npc")
	else
		error("readPosition should return a position from handle.npc cellX/cellY")
	end
end

print("All 18 runtime avatar adapter boundary tests passed")
