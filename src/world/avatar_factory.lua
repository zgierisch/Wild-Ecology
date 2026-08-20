local AvatarFactory = {}

local WALK_DIRS = {
  ANY = { "up", "down", "left", "right" },
  UP_DOWN = { "up", "down" },
  LEFT_RIGHT = { "left", "right" }
}

local FACING_FROM_RANGE = {
  UP = "up",
  DOWN = "down",
  LEFT = "left",
  RIGHT = "right"
}

local function normalizeNameForObjectId(entityId)
  return tostring(entityId or "wild"):gsub("[^%w_]", "_")
end

local function buildObjectDef(entity)
  local home = entity.home or {}
  local avatar = entity.avatar or {}

  return {
    name = avatar.name or normalizeNameForObjectId(entity.id),
    x = avatar.x or home.spawnX or 6,
    y = avatar.y or home.spawnY or 6,
    sprite = avatar.sprite or "SPRITE_BIRD",
    movement = avatar.movement or "STAY",
    range = avatar.range or "DOWN"
  }
end

local function spawnViaPublicApi(mod, entity)
  local world = mod and mod.world
  if not world or not world.spawnNpc then
    return nil
  end

  local mapId = entity.home and entity.home.mapId
  if not mapId and world.current then
    local current = world:current()
    mapId = current and current.mapId or nil
  end
  if not mapId then
    return nil
  end

  local npcId = world:spawnNpc(mapId, buildObjectDef(entity))
  if not npcId then
    return nil
  end

  local avatar = {
    id = npcId,
    mapId = mapId,
    entityId = entity.id,
    species = entity.species,
    level = entity.level
  }

  if world.npc then
    local handle = world:npc(mapId, npcId)
    if handle then
      handle.entityId = entity.id
      avatar.handle = handle
    end
  end

  return avatar
end

local function spawnViaEngineInternals(mod, entity)
  local internals = mod and mod.engine_internals
  if not internals or not internals.spawnNpc then
    return nil
  end

  local npc = internals.spawnNpc({
    species = entity.species,
    level = entity.level,
    movement = "WALK"
  })

  if npc then
    npc.entityId = entity.id
  end

  return npc
end

function AvatarFactory.spawn(mod, entity)
  return spawnViaPublicApi(mod, entity) or spawnViaEngineInternals(mod, entity)
end

local function cloneDirs(dirs)
  if type(dirs) ~= "table" then
    return nil
  end

  local out = {}
  for i = 1, #dirs do
    out[i] = dirs[i]
  end
  return out
end

local function walkDirsForRange(range)
  return cloneDirs(WALK_DIRS[range or "ANY"] or WALK_DIRS.ANY)
end

local function applyLegacyNpcBehavior(npc, movement, range)
  if type(npc) ~= "table" then
    return false
  end

  if movement == "WALK" then
    npc.wanders = true
    npc.roamDirs = walkDirsForRange(range)
    npc.timer = 0
    npc.frozen = false
    return true
  end

  npc.wanders = false
  npc.roamDirs = nil
  npc.moving = false
  npc.targetX = nil
  npc.targetY = nil
  npc.progress = 0
  npc.facing = FACING_FROM_RANGE[range] or npc.facing or "down"
  npc.frozen = false
  return true
end

local function applyGen2NpcBehavior(npc, movement, range)
  if type(npc) ~= "table" then
    return false
  end

  if movement == "WALK" then
    npc.kind = "walk"
    npc.roamDirs = walkDirsForRange(range)
    if range == "UP_DOWN" then
      npc.radiusX = 0
      npc.radiusY = 3
    elseif range == "LEFT_RIGHT" then
      npc.radiusX = 3
      npc.radiusY = 0
    else
      npc.radiusX = 3
      npc.radiusY = 3
    end
    npc.timer = 0
    npc.frozen = false
    return true
  end

  npc.kind = "stand"
  npc.roamDirs = nil
  npc.radiusX = 0
  npc.radiusY = 0
  npc.moving = false
  npc.targetX = nil
  npc.targetY = nil
  npc.progress = 0
  npc.facing = FACING_FROM_RANGE[range] or npc.facing or "down"
  npc.frozen = false
  return true
end

local function applyRuntimeNpcBehavior(npc, movement, range)
  if type(npc) ~= "table" then
    return false
  end

  -- Gen 2 NPCs drive wander from kind/roamDirs/radius; Gen 1 uses wanders/roamDirs.
  if npc.kind ~= nil or npc.radiusX ~= nil or npc.radiusY ~= nil then
    return applyGen2NpcBehavior(npc, movement, range)
  end

  return applyLegacyNpcBehavior(npc, movement, range)
end

function AvatarFactory.applyBehavior(mod, avatar, entity)
  if type(avatar) ~= "table" or type(entity) ~= "table" then
    return false
  end

  local desired = entity.avatar or {}
  local movement = desired.movement or "STAY"
  local range = desired.range or "DOWN"

  local handle = avatar.handle
  if type(handle) ~= "table" and mod and mod.world and mod.world.npc and avatar.mapId and avatar.id then
    handle = mod.world:npc(avatar.mapId, avatar.id)
    if handle then
      avatar.handle = handle
    end
  end

  if type(handle) == "table" then
    -- Keep these mirrored for tests/debug visibility even when runtime NPC exists.
    handle.movement = movement
    handle.range = range
    local npc = handle.npc
    if applyRuntimeNpcBehavior(npc, movement, range) then
      return true
    end
    return true
  end

  if applyRuntimeNpcBehavior(avatar, movement, range) then
    return true
  end

  return false
end

function AvatarFactory.despawn(mod, avatar)
  if not avatar then
    return
  end

  if mod and mod.world and mod.world.removeNpc then
    local npcId = type(avatar) == "table" and avatar.id or avatar
    if npcId then
      mod.world:removeNpc(npcId)
      return
    end
  end

  if type(avatar) == "table" and avatar.handle and mod and mod.engine_internals and mod.engine_internals.removeNpc then
    mod.engine_internals.removeNpc(avatar.handle)
    return
  end

  if mod and mod.engine_internals and mod.engine_internals.removeNpc then
    mod.engine_internals.removeNpc(avatar)
  end
end

return AvatarFactory
