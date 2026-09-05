-- This is a TEST-ONLY fake RuntimeAvatarAdapter that uses a completely different
-- internal runtime representation than the Gen1Recomp-specific avatar_factory.
-- It demonstrates that replacing the runtime backend does NOT require changes
-- to portable Wild Ecology systems.
--
-- The fake uses:
-- - A simple array-based actor pool instead of Gen1Recomp's NPC/overworld objects
-- - A UUID-based ID scheme instead of Gen1Recomp string names
-- - A flat property map instead of nested npc/ow/handle structures
--
-- Portable ecology should work unchanged through this fake adapter.

local FakeRuntimeAvatarAdapter = {}

local nextActorId = 1000
local actorPool = {}

local function cloneCell(cell)
	if type(cell) ~= "table" then
		return nil
	end
	return { cellX = cell.cellX, cellY = cell.cellY }
end

function FakeRuntimeAvatarAdapter.materialize(mod, entity, spawnCell, requestedMapId)
	if type(entity) ~= "table" then
		return nil
	end

	local runtimeId = "FAKE_ACTOR_" .. tostring(nextActorId)
	nextActorId = nextActorId + 1

	if not spawnCell then
		spawnCell = { cellX = 6, cellY = 6 }
	end

	local actor = {
		id = runtimeId,
		entityId = entity.id,
		mapId = requestedMapId or (entity.home and entity.home.mapId),
		cellX = spawnCell.cellX,
		cellY = spawnCell.cellY,
		moving = false,
		targetX = nil,
		targetY = nil,
		direction = "down",
		species = entity.species,
		level = entity.level,
		movement = "STAY",
		range = "DOWN",
		runtimeAdapter = "FakeRuntimeAvatarAdapter"
	}

	actorPool[runtimeId] = actor

	return {
		id = runtimeId,
		entityId = entity.id,
		mapId = requestedMapId or (entity.home and entity.home.mapId),
		species = entity.species,
		level = entity.level,
		runtimeAdapter = "FakeRuntimeAvatarAdapter",
		requestedCell = cloneCell(spawnCell)
	}
end

function FakeRuntimeAvatarAdapter.resolve(mod, avatar)
	if type(avatar) ~= "table" or type(avatar.id) ~= "string" then
		return nil
	end
	return actorPool[avatar.id]
end

function FakeRuntimeAvatarAdapter.readPosition(mod, avatar)
	local actor = FakeRuntimeAvatarAdapter.resolve(mod, avatar)
	if not actor then
		return nil
	end
	return { cellX = actor.cellX, cellY = actor.cellY }
end

function FakeRuntimeAvatarAdapter.requestMovement(mod, avatar, direction)
	local actor = FakeRuntimeAvatarAdapter.resolve(mod, avatar)
	if not actor then
		return false
	end

	-- Fake movement logic: just mark the direction and set target
	actor.direction = direction
	if direction ~= "STAY" and not actor.moving then
		actor.moving = true
		local dx, dy = 0, 0
		if direction == "up" then dy = -1
		elseif direction == "down" then dy = 1
		elseif direction == "left" then dx = -1
		elseif direction == "right" then dx = 1
		end
		actor.targetX = actor.cellX + dx
		actor.targetY = actor.cellY + dy
		return true
	end

	return false
end

function FakeRuntimeAvatarAdapter.destroy(mod, avatar)
	if type(avatar) ~= "table" or type(avatar.id) ~= "string" then
		return false
	end

	if actorPool[avatar.id] then
		actorPool[avatar.id] = nil
		return true
	end

	return false
end

-- Debugging/test-only utilities
function FakeRuntimeAvatarAdapter.clearPool()
	actorPool = {}
	nextActorId = 1000
end

function FakeRuntimeAvatarAdapter.poolSize()
	local count = 0
	for _ in pairs(actorPool) do
		count = count + 1
	end
	return count
end

function FakeRuntimeAvatarAdapter.getActor(runtimeId)
	return actorPool[runtimeId]
end

return FakeRuntimeAvatarAdapter
