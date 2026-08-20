local AvatarFactory = {}

local function spawnViaPublicApi(mod, entity)
  local world = mod and mod.world
  if not world or not world.spawnNpc then
    return nil
  end

  local npc = world.spawnNpc({
    species = entity.species,
    level = entity.level,
    movement = "WALK"
  })

  if npc then
    npc.entityId = entity.id
  end

  return npc
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
    mod.world.removeNpc(avatar)
    return
  end

  if mod and mod.engine_internals and mod.engine_internals.removeNpc then
    mod.engine_internals.removeNpc(avatar)
  end
end

return AvatarFactory
