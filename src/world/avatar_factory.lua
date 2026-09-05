local AvatarFactory = {}
local spawnDiagnosticSink = nil
local Collision = nil
local CollisionLoadAttempted = false
local BaseRanges = require("src.species.base_ranges")
local SpeciesSprites = require("src.world.species_sprites")
local DebugLogger = require("src.debug.logger")

-- Shares main.lua's "dev_log_generation" LOG SETTINGS toggle (see
-- species_sprites.lua's identical gate).
local function generationLogEnabled(mod)
  local save = mod and mod.save
  if save and save.get then
    local ok, value = pcall(function()
      return save:get("dev_log_generation", false)
    end)
    if ok then
      return value == true
    end
  end
  return false
end

local function loadCollision()
  if CollisionLoadAttempted then
    return Collision
  end

  CollisionLoadAttempted = true
  local ok, loaded = pcall(require, "src.world.Collision")
  if ok then
    Collision = loaded
  end
  return Collision
end

local function resolveRuntimeContext(mod, avatar)
  local handle = avatar and avatar.handle
  if type(handle) ~= "table" then
    return nil, nil
  end

  if type(handle.npc) == "table" and type(handle.ow) == "table" and type(handle.ow.map) == "table" then
    return handle.ow, handle.npc
  end

  local overworld = mod and mod.game and mod.game.overworld or nil
  if not overworld then
    local ok, Game = pcall(require, "src.core.Game")
    overworld = ok and Game and Game.overworld or nil
  end
  if type(overworld) ~= "table" or type(overworld.map) ~= "table" then
    return nil, nil
  end

  for _, collection in ipairs({ overworld.npcs or {}, overworld.entities or {} }) do
    for _, npc in ipairs(collection) do
      if npc == handle or npc.id == avatar.id or npc.entityId == avatar.entityId then
        handle.npc = npc
        handle.ow = overworld
        return overworld, npc
      end
    end
  end

  return nil, nil
end

local function stockEntityBlockers(entities, mover, destinationX, destinationY)
  local blockers = {}
  for _, candidate in pairs(entities or {}) do
    if candidate ~= mover and candidate.cellX == destinationX
      and candidate.cellY == destinationY then
      blockers[#blockers + 1] = {
        id = candidate.entityId or candidate.id or candidate.name,
        kind = candidate.kind or candidate.type or "NPC",
        cellX = candidate.cellX,
        cellY = candidate.cellY,
        moving = candidate.moving == true,
        targetX = candidate.targetX,
        targetY = candidate.targetY,
        runtimeObject = true,
        materialized = true
      }
    end
  end
  table.sort(blockers, function(left, right)
    return tostring(left.id or "") < tostring(right.id or "")
  end)
  return blockers
end

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

local function spriteForEntity(entity)
  local avatar = entity.avatar or {}
  if avatar.sprite then
    return avatar.sprite
  end
  return SpeciesSprites.get(entity.species) or BaseRanges.get(entity.species).defaultSprite or "SPRITE_BIRD"
end

local function buildObjectDef(entity, mod, spawnCell)
  local home = entity.home or {}
  local avatar = entity.avatar or {}
  local sprite = spriteForEntity(entity)

  if generationLogEnabled(mod) then
    DebugLogger.log("generation", string.format("sprite resolved id=%s species=%s -> %s (registered=%s)", tostring(entity.id), tostring(entity.species), tostring(sprite), tostring(SpeciesSprites.get(entity.species) ~= nil)))
  end

  return {
    name = avatar.name or normalizeNameForObjectId(entity.id),
    x = spawnCell and spawnCell.cellX or avatar.x or home.spawnX or 6,
    y = spawnCell and spawnCell.cellY or avatar.y or home.spawnY or 6,
    sprite = sprite,
    movement = avatar.autonomousMovement and "STAY" or avatar.movement or "STAY",
    range = avatar.range or "DOWN"
  }
end

local function spawnViaPublicApi(mod, entity, spawnCell, requestedMapId)
  local world = mod and mod.world
  if not world or not world.spawnNpc then
    if spawnDiagnosticSink then
      pcall(spawnDiagnosticSink, "SPAWN_NPC_UNAVAILABLE", entity, spawnCell,
        requestedMapId, nil, "PUBLIC_API_UNAVAILABLE")
    end
    return nil
  end

  local mapId = requestedMapId or (entity.home and entity.home.mapId)
  if not mapId and world.current then
    local current = world:current()
    mapId = current and current.mapId or nil
  end
  if not mapId then
    if spawnDiagnosticSink then
      pcall(spawnDiagnosticSink, "SPAWN_NPC_UNAVAILABLE", entity, spawnCell,
        requestedMapId, nil, "MAP_ID_MISSING")
    end
    return nil
  end

  if spawnDiagnosticSink then
    pcall(spawnDiagnosticSink, "SPAWN_NPC_CALLED", entity, spawnCell, mapId)
  end
  local objectDefinition = buildObjectDef(entity, mod, spawnCell)
  local ok, npcId, refusalReason = pcall(function()
    return world:spawnNpc(mapId, objectDefinition)
  end)
  if spawnDiagnosticSink then
    pcall(spawnDiagnosticSink, "SPAWN_NPC_RESULT", entity, spawnCell, mapId,
      ok and npcId or nil,
      ok and (npcId and "PUBLIC_API_SUCCEEDED"
        or ("PUBLIC_API_RETURNED_NIL: " .. tostring(refusalReason or "NO_REASON"))
          :gsub("[\r\n]+", " "):sub(1, 120))
        or ("PUBLIC_API_ERROR: " .. tostring(npcId):gsub("[\r\n]+", " "):sub(1, 120)),
      objectDefinition)
  end
  if not ok then
    return nil
  end
  if not npcId then
    return nil
  end

  local avatar = {
    id = npcId,
    mapId = mapId,
    entityId = entity.id,
    species = entity.species,
    level = entity.level,
    requestedCell = spawnCell and {
      cellX = spawnCell.cellX,
      cellY = spawnCell.cellY
    } or nil
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

function AvatarFactory.setSpawnDiagnosticSink(sink)
  spawnDiagnosticSink = type(sink) == "function" and sink or nil
end

local function spawnViaEngineInternals(mod, entity, spawnCell, requestedMapId)
  local internals = mod and mod.engine_internals
  if not internals or not internals.spawnNpc then
    return nil
  end

  local npc = internals.spawnNpc({
    species = entity.species,
    level = entity.level,
    movement = "WALK",
    mapId = requestedMapId or (entity.home and entity.home.mapId),
    x = spawnCell and spawnCell.cellX or nil,
    y = spawnCell and spawnCell.cellY or nil
  })

  if npc then
    npc.entityId = entity.id
  end

  return npc
end

function AvatarFactory.spawn(mod, entity, spawnCell, mapId)
  return spawnViaPublicApi(mod, entity, spawnCell, mapId)
    or spawnViaEngineInternals(mod, entity, spawnCell, mapId)
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

local function applyLegacyNpcBehavior(npc, movement, range, motionActive)
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
  -- STAY disables stock wandering but must not cancel mod-driven motion.
  if not motionActive then
    npc.moving = false
    npc.targetX = nil
    npc.targetY = nil
    npc.progress = 0
  end
  npc.facing = FACING_FROM_RANGE[range] or npc.facing or "down"
  npc.frozen = false
  return true
end

local function applyGen2NpcBehavior(npc, movement, range, motionActive)
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
  if not motionActive then
    npc.moving = false
    npc.targetX = nil
    npc.targetY = nil
    npc.progress = 0
  end
  npc.facing = FACING_FROM_RANGE[range] or npc.facing or "down"
  npc.frozen = false
  return true
end

local function applyRuntimeNpcBehavior(npc, movement, range, motionActive)
  if type(npc) ~= "table" then
    return false
  end

  -- Gen 2 NPCs drive wander from kind/roamDirs/radius; Gen 1 uses wanders/roamDirs.
  if npc.kind ~= nil or npc.radiusX ~= nil or npc.radiusY ~= nil then
    return applyGen2NpcBehavior(npc, movement, range, motionActive)
  end

  return applyLegacyNpcBehavior(npc, movement, range, motionActive)
end

function AvatarFactory.applyBehavior(mod, avatar, entity)
  if type(avatar) ~= "table" or type(entity) ~= "table" then
    return false
  end

  local desired = entity.avatar or {}
  local movement = desired.movement or "STAY"
  local range = desired.range or "DOWN"
  local motionActive = entity.runtimeState and entity.runtimeState.motion and entity.runtimeState.motion.active or false
  if desired.autonomousMovement then
    movement = "STAY"
  end

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
    if applyRuntimeNpcBehavior(npc, movement, range, motionActive) then
      return true
    end
    return true
  end

  if applyRuntimeNpcBehavior(avatar, movement, range, motionActive) then
    return true
  end

  return false
end

function AvatarFactory.movementApiAvailable(mod, avatar)
  local overworld, npc = resolveRuntimeContext(mod, avatar)
  return overworld ~= nil and npc ~= nil and loadCollision() ~= nil
end

function AvatarFactory.evaluateWalk(mod, avatar, direction)
  if not AvatarFactory.movementApiAvailable(mod, avatar) then
    return { allowed = false, reason = "MOVEMENT_API_UNAVAILABLE" }
  end

  local overworld, npc = resolveRuntimeContext(mod, avatar)
  local collision = loadCollision()
  local allowed, reason = collision.canMove(overworld.map, overworld.entities, npc, direction)
  if not allowed then
    return { allowed = false, reason = reason or "BLOCKED" }
  end

  local tx, ty = collision.target(npc.cellX, npc.cellY, direction)
  return {
    allowed = true,
    traversalMode = "WALK",
    destinationX = tx,
    destinationY = ty,
    direction = direction
  }
end

function AvatarFactory.refreshMotionState(mod, avatar, entity)
  if type(entity) ~= "table" or type(entity.runtimeState) ~= "table" then
    return false
  end

  local motion = entity.runtimeState.motion
  if not motion or not motion.active then
    return false
  end

  local _, npc = resolveRuntimeContext(mod, avatar)
  if not npc then
    motion.active = false
    motion.recoveryReason = "NPC_CONTEXT_UNAVAILABLE"
    return true
  end
  if npc and npc.moving then
    motion.active = true
    motion.destinationX = npc.targetX
    motion.destinationY = npc.targetY
    return false
  end
  if npc and not npc.moving and npc.cellX == motion.destinationX and npc.cellY == motion.destinationY then
    motion.active = false
    motion.justCompleted = true
    motion.completedTick = entity.runtimeState.simulationTick
    return true
  end

  if npc and not npc.moving then
    motion.active = false
    motion.recoveryReason = "MOTION_DESTINATION_MISMATCH"
    return true
  end

  return false
end

function AvatarFactory.applyMovementRequest(mod, avatar, entity)
  if type(avatar) ~= "table" or type(entity) ~= "table" then
    return false
  end

  local request = entity.runtimeState and entity.runtimeState.movementRequest
  if type(request) ~= "table" then
    return false
  end

  entity.runtimeState = entity.runtimeState or {}
  entity.runtimeState.motion = entity.runtimeState.motion or { active = false }
  if entity.runtimeState.motion.active then
    local activeMotion = entity.runtimeState.motion
    local _, npc = resolveRuntimeContext(mod, avatar)
    if npc and not npc.moving and npc.cellX == activeMotion.destinationX and npc.cellY == activeMotion.destinationY then
      activeMotion.active = false
      activeMotion.completedTick = entity.runtimeState.simulationTick
    else
      request.rejectionReason = "MOVEMENT_ACTIVE"
      return false
    end
  end

  if request.traversalMode ~= "WALK" or request.direction == "STAY" then
    return false
  end

  local overworld, npc = resolveRuntimeContext(mod, avatar)
  local collision = loadCollision()
  if not AvatarFactory.movementApiAvailable(mod, avatar) then
    request.rejectionReason = "MOVEMENT_API_UNAVAILABLE"
    return false
  end

  local direction = string.lower(tostring(request.direction))
  if npc.moving then
    request.rejectionReason = "MOVEMENT_ACTIVE"
    return false
  end
  if request.sourceX ~= nil and request.sourceY ~= nil
    and (npc.cellX ~= request.sourceX or npc.cellY ~= request.sourceY) then
    request.rejectionReason = "SOURCE_POSITION_MISMATCH"
    return false
  end

  local candidateDirection = string.lower(tostring(request.direction))
  local tx, ty = collision.target(npc.cellX, npc.cellY, candidateDirection)
  local allowed, reason = collision.canMove(overworld.map, overworld.entities, npc, candidateDirection)

  if not allowed then
    entity.runtimeState.rejectedMoves = entity.runtimeState.rejectedMoves or {}
    if reason == "tile" or reason == "bounds" then
      entity.runtimeState.rejectedMoves[string.upper(candidateDirection)] = {
        mapId = overworld.map.id,
        cellX = npc.cellX,
        cellY = npc.cellY,
        reason = reason,
        tick = entity.runtimeState.simulationTick
      }
    end
    request.rejectionReason = reason or "MOVEMENT_REJECTED"
    if reason == "entity" then
      local blockers = stockEntityBlockers(overworld.entities, npc, tx, ty)
      request.blockingLayer = "STOCK_COLLISION"
      request.blockerId = blockers[1] and blockers[1].id or nil
      request.stockEntityBlockers = blockers
      request.falseEntityBlock = #blockers == 0
    end
    return false
  end

  local chosenDirection = candidateDirection
  entity.runtimeState.rejectedMoves = {}
  local motion = {
    active = true,
    direction = string.upper(chosenDirection),
    startedTick = entity.runtimeState.simulationTick,
    destinationX = tx,
    destinationY = ty
  }
  entity.runtimeState.motion = motion

  npc.facing = chosenDirection
  npc.targetX = tx
  npc.targetY = ty
  npc.moving = true
  npc.progress = 0

  entity.avatar = entity.avatar or {}
  entity.avatar.movementRequest = {
    direction = string.upper(chosenDirection),
    traversalMode = request.traversalMode,
    targetEntityId = request.targetEntityId,
    goalKind = request.goalKind,
    sourceX = request.sourceX,
    sourceY = request.sourceY,
    destinationX = request.destinationX,
    destinationY = request.destinationY,
    reason = request.reason,
    rejectionReason = nil
  }
  avatar.movementRequest = entity.avatar.movementRequest
  return true
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
