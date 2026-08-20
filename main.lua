local Config = require("src.core.config")
local Save = require("src.core.save")
local PopulationManager = require("src.population.manager")
local AvatarFactory = require("src.world.avatar_factory")
local Controller = require("src.behavior.controller")

local WildEcology = {
  activeAvatars = {}
}

local function applyPhase0AvatarBehavior(entity, state)
  entity.avatar = entity.avatar or {}

  if state == "FLEE" then
    entity.avatar.movement = "WALK"
    entity.avatar.range = "ANY"
    return
  end

  entity.avatar.movement = "STAY"
  entity.avatar.range = "DOWN"
end

local function getPlayerEntity()
  return {
    id = "player",
    kind = "trainer"
  }
end

function WildEcology.init(mod)
  WildEcology.mod = mod
  Save.init(mod)

  local world = mod and mod.world
  local current = world and world.current and world:current() or nil
  local mapId = current and current.mapId or nil
  if mapId ~= Config.phase0.testMapId then
    return
  end

  local simulationTick = Save.nextTick()
  local entity = PopulationManager.getOrCreatePhase0Entity()
  local player = getPlayerEntity()
  local rel = PopulationManager.updatePhase0Relationship(entity, player, simulationTick)
  local state = Controller.tick(entity, rel)
  applyPhase0AvatarBehavior(entity, state)

  local avatar = AvatarFactory.spawn(mod, entity)
  if avatar then
    WildEcology.activeAvatars[entity.id] = avatar
  end

  Save.flush()
end

function WildEcology.shutdown()
  for id, avatar in pairs(WildEcology.activeAvatars) do
    AvatarFactory.despawn(WildEcology.mod, avatar)
    WildEcology.activeAvatars[id] = nil
  end

  Save.flush()
end

return WildEcology
