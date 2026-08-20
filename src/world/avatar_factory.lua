local AvatarFactory = {}

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
