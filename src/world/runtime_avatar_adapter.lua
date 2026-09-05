local RuntimeAvatarAdapter = {}
local AvatarFactory = nil

function RuntimeAvatarAdapter.setAvatarFactory(factory)
  AvatarFactory = factory
end

local function cloneCell(cell)
  if type(cell) ~= "table" then
    return nil
  end
  return {
    cellX = cell.cellX,
    cellY = cell.cellY
  }
end

local function resolveHandle(mod, avatar)
  if type(avatar) ~= "table" then
    return nil
  end

  local handle = avatar.handle
  if type(handle) == "table" then
    return handle
  end

  local world = mod and mod.world
  if not world or type(world.npc) ~= "function" then
    return nil
  end

  if type(avatar.id) ~= "string" and type(avatar.id) ~= "number" then
    return nil
  end

  local mapId = avatar.mapId or (avatar.home and avatar.home.mapId)
  if not mapId then
    return nil
  end

  local resolved = world:npc(mapId, avatar.id)
  if type(resolved) == "table" then
    avatar.handle = resolved
    return resolved
  end

  return nil
end

function RuntimeAvatarAdapter.materialize(mod, entity, spawnCell, requestedMapId)
  if type(entity) ~= "table" then
    return nil
  end

  if not AvatarFactory then
    return nil
  end
  local avatar = AvatarFactory.spawn(mod, entity, spawnCell, requestedMapId)
  if not avatar then
    return nil
  end

  avatar.runtimeAdapter = "RuntimeAvatarAdapter"
  return avatar
end

function RuntimeAvatarAdapter.resolve(mod, avatar)
  return resolveHandle(mod, avatar)
end

function RuntimeAvatarAdapter.readPosition(mod, avatar)
  local handle = resolveHandle(mod, avatar)
  if type(handle) ~= "table" then
    return nil
  end

  local npc = handle.npc or handle
  if type(npc) ~= "table" then
    return nil
  end

  if npc.cellX ~= nil or npc.cellY ~= nil then
    return { cellX = npc.cellX, cellY = npc.cellY }
  end

  if handle.ow and type(handle.ow.map) == "table" then
    return { cellX = handle.ow.map.x or handle.ow.x, cellY = handle.ow.map.y or handle.ow.y }
  end

  return nil
end

function RuntimeAvatarAdapter.requestMovement(mod, avatar, entity)
  if not AvatarFactory or not AvatarFactory.applyMovementRequest then
    return false
  end
  return AvatarFactory.applyMovementRequest(mod, avatar, entity) or false
end

function RuntimeAvatarAdapter.destroy(mod, avatar)
  if not avatar then
    return false
  end

  if AvatarFactory and AvatarFactory.despawn then
    AvatarFactory.despawn(mod, avatar)
    return true
  end

  if mod and mod.world and mod.world.removeNpc then
    local npcId = type(avatar) == "table" and avatar.id or avatar
    if npcId then
      mod.world:removeNpc(npcId)
      return true
    end
  end

  return false
end

return RuntimeAvatarAdapter
