local AvatarFactory = require("src.world.avatar_factory")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

-- Public API refusal reasons remain visible at the adapter boundary.
do
	local diagnostic = nil
	AvatarFactory.setSpawnDiagnosticSink(function(event, _, _, _, npcId, outcome)
		if event == "SPAWN_NPC_RESULT" then
			diagnostic = { npcId = npcId, outcome = outcome }
		end
	end)
	local mod = {
		world = {
			spawnNpc = function()
				return nil, "no overworld"
			end
		}
	}
	local entity = {
		id = "wild:route22:refused",
		species = "RATTATA",
		level = 3,
		home = { mapId = "ROUTE_22" }
	}

	assertEquals(AvatarFactory.spawn(mod, entity), nil,
		"public API refusal should not materialize an avatar")
	assertEquals(diagnostic and diagnostic.npcId, nil,
		"refused spawn diagnostic should not report an NPC id")
	assertEquals(diagnostic and diagnostic.outcome,
		"PUBLIC_API_RETURNED_NIL: no overworld",
		"refused spawn diagnostic should preserve the API reason")
	AvatarFactory.setSpawnDiagnosticSink(nil)
end

-- Public API path: spawnNpc/removeNpc + npc handle attachment.
do
	local called = {}
	local handle = { npc = { kind = "walk", roamDirs = { "up", "down" }, radiusX = 0, radiusY = 3 } }
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

	entity.avatar.movement = "STAY"
	entity.avatar.range = "DOWN"
	local applied = AvatarFactory.applyBehavior(mod, avatar, entity)
	assertEquals(applied, true, "applyBehavior should mutate active runtime npc")
	assertEquals(handle.movement, "STAY", "handle should mirror desired movement")
	assertEquals(handle.npc.kind, "stand", "gen2-style npc should switch to stand")
	assertEquals(handle.npc.facing, "down", "gen2-style npc should update facing")

	handle.npc.moving = true
	handle.npc.targetX = 8
	handle.npc.targetY = 10
	handle.npc.progress = 0.25
	entity.runtimeState = { motion = { active = true } }
	entity.avatar.autonomousMovement = true
	AvatarFactory.applyBehavior(mod, avatar, entity)
	assertEquals(handle.npc.moving, true, "disabling stock wander should preserve a mod-driven step")
	assertEquals(handle.npc.targetY, 10, "active mod-driven destination should survive behavior refresh")
	assertEquals(handle.npc.progress, 0.25, "active mod-driven progress should survive behavior refresh")
	entity.runtimeState.motion.active = false
	entity.avatar.autonomousMovement = nil

	entity.avatar.movement = "WALK"
	entity.avatar.range = "LEFT_RIGHT"
	AvatarFactory.applyBehavior(mod, avatar, entity)
	assertEquals(handle.npc.kind, "walk", "gen2-style npc should switch back to walk")
	assertEquals(handle.npc.roamDirs[1], "left", "gen2-style npc should apply constrained roam directions")
	assertEquals(handle.npc.roamDirs[2], "right", "gen2-style npc should apply constrained roam directions")
end

-- The runtime avatar boundary is formalized behind a dedicated adapter contract.
do
	local RuntimeAvatarAdapter = require("src.world.runtime_avatar_adapter")
	 RuntimeAvatarAdapter.setAvatarFactory(AvatarFactory)
	local called = {}
	local handle = { npc = { cellX = 7, cellY = 8, moving = false }, ow = { map = { id = "ROUTE_3" } } }
	local mod = {
		world = {
			spawnNpc = function(_, mapId, objDef)
				called.mapId = mapId
				called.objDef = objDef
				return "ROUTE_3_obj_42"
			end,
			npc = function(_, mapId, npcId)
				called.handleLookup = { mapId = mapId, npcId = npcId }
				return handle
			end,
			removeNpc = function(_, npcId)
				called.removedNpcId = npcId
				return true
			end
		}
	}
	local entity = {
		id = "wild:route03:0002",
		species = "RATTATA",
		level = 3,
		home = { mapId = "ROUTE_3", spawnX = 7, spawnY = 8 },
		avatar = { movement = "WALK", range = "ANY" }
	}
	local avatar = RuntimeAvatarAdapter.materialize(mod, entity, { cellX = 7, cellY = 8 }, "ROUTE_3")
	if not avatar then error("runtime avatar adapter should materialize a runtime avatar") end
	assertEquals(avatar.runtimeAdapter, "RuntimeAvatarAdapter", "avatar should advertise its runtime adapter")
	assertEquals(RuntimeAvatarAdapter.readPosition(mod, avatar).cellX, 7, "runtime adapter should read the live cell position")
	assertEquals(RuntimeAvatarAdapter.resolve(mod, avatar) == handle, true, "runtime adapter should resolve the live handle")
	assertEquals(RuntimeAvatarAdapter.destroy(mod, avatar), true, "runtime adapter should destroy a materialized avatar")
	assertEquals(called.removedNpcId, "ROUTE_3_obj_42", "runtime adapter should pass through despawn to the runtime backend")
end

-- A guarded caller's canonical cell overrides every independently stored
-- coordinate, including zero-valued cells.
do
	local called = {}
	local mod = {
		world = {
			spawnNpc = function(_, mapId, objDef)
				called.mapId = mapId
				called.objDef = objDef
				return "CANONICAL_obj_1"
			end
		}
	}
	local entity = {
		id = "canonical",
		species = "PIDGEY",
		level = 4,
		home = { mapId = "OLD_MAP", spawnX = 8, spawnY = 9 },
		avatar = { x = 40, y = 41 }
	}
	local avatar = AvatarFactory.spawn(mod, entity, { cellX = 0, cellY = 0 }, "CURRENT_MAP")
	assertEquals(called.mapId, "CURRENT_MAP", "canonical materialization should use the validated current map")
	assertEquals(called.objDef.x, 0, "canonical x=0 should be passed unchanged")
	assertEquals(called.objDef.y, 0, "canonical y=0 should be passed unchanged")
	if not avatar.requestedCell then
		error("avatar should record the exact requested cell")
	end
	assertEquals(avatar.requestedCell.cellX, 0, "avatar should record the exact requested x")
	assertEquals(avatar.requestedCell.cellY, 0, "avatar should record the exact requested y")
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

-- Legacy NPC behavior mutation path for Gen 1-style runtime objects.
do
	local avatar = { handle = { npc = { wanders = true, roamDirs = { "up", "down" } } } }
	local entity = { avatar = { movement = "STAY", range = "LEFT" } }
	local applied = AvatarFactory.applyBehavior({}, avatar, entity)
	assertEquals(applied, true, "legacy npc behavior should be mutable in place")
	assertEquals(avatar.handle.npc.wanders, false, "legacy npc should stop wandering for STAY")
	assertEquals(avatar.handle.npc.facing, "left", "legacy npc should face the configured direction")

	entity.avatar.movement = "WALK"
	entity.avatar.range = "UP_DOWN"
	AvatarFactory.applyBehavior({}, avatar, entity)
	assertEquals(avatar.handle.npc.wanders, true, "legacy npc should wander for WALK")
	assertEquals(avatar.handle.npc.roamDirs[1], "up", "legacy npc should use vertical roam directions")
	assertEquals(avatar.handle.npc.roamDirs[2], "down", "legacy npc should use vertical roam directions")
end

return true
