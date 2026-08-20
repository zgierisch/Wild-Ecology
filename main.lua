local Config = nil
local Save = nil
local PopulationManager = nil
local AvatarFactory = nil
local Controller = nil
local DebugLogger = nil

local WildEcology = {
  activeAvatars = {},
  mod = nil,
  saveReady = false,
  updateHookInstalled = false,
  debugUiInstalled = false
}

local OriginalRequire = require
local ActiveModRequirePrefix = nil
local ActiveModRootPath = nil
local RequireShimInstalled = false

local function loadModuleFromFilePath(moduleName)
  if type(moduleName) ~= "string" then
    return false, "module name must be a string"
  end
  if not ActiveModRootPath then
    return false, "mod root path unavailable"
  end
  if not loadfile then
    return false, "loadfile unavailable in this runtime"
  end

  if package and package.loaded and package.loaded[moduleName] ~= nil then
    return true, package.loaded[moduleName]
  end

  local relativePath = moduleName:gsub("%.", "/") .. ".lua"
  local absolutePath = ActiveModRootPath .. "/" .. relativePath

  local chunk, loadErr = loadfile(absolutePath)
  if not chunk then
    return false, loadErr
  end

  local okExec, result = pcall(chunk)
  if not okExec then
    return false, result
  end

  if result == nil then
    result = true
  end
  if package and package.loaded then
    package.loaded[moduleName] = result
  end

  return true, result
end

local function installRequireShim(mod)
  if RequireShimInstalled then
    return
  end

  local modPath = mod and mod.path
  if modPath then
    local normalizedPath = tostring(modPath):gsub("\\", "/")
    ActiveModRootPath = normalizedPath
    ActiveModRequirePrefix = normalizedPath:gsub("[/\\]", ".")
  end

  require = function(moduleName)
    local okDirect, loadedDirect = pcall(OriginalRequire, moduleName)
    if okDirect then
      return loadedDirect
    end

    if type(moduleName) ~= "string" then
      error(loadedDirect)
    end
    if not ActiveModRequirePrefix then
      error(loadedDirect)
    end
    if moduleName:sub(1, 4) ~= "src." then
      error(loadedDirect)
    end

    local prefixedError = nil
    if ActiveModRequirePrefix then
      local prefixedName = ActiveModRequirePrefix .. "." .. moduleName
      local okPrefixed, loadedPrefixed = pcall(OriginalRequire, prefixedName)
      if okPrefixed then
        return loadedPrefixed
      end
      prefixedError = loadedPrefixed
    end

    local okFilePath, loadedFromFilePath = loadModuleFromFilePath(moduleName)
    if okFilePath then
      return loadedFromFilePath
    end

    local details = tostring(loadedDirect)
    if prefixedError then
      details = details .. "\n[prefixed require] " .. tostring(prefixedError)
    end
    details = details .. "\n[file path load] " .. tostring(loadedFromFilePath)
    error(details)
  end

  RequireShimInstalled = true
end

local function requireFromMod(_mod, moduleSuffix)
  return pcall(require, moduleSuffix)
end

local function loadModules(mod)
  if Config and Save and PopulationManager and AvatarFactory and Controller and DebugLogger then
    return true
  end

  local okConfig, loadedConfig = requireFromMod(mod, "src.core.config")
  if not okConfig then
    return false, loadedConfig
  end
  local okSave, loadedSave = requireFromMod(mod, "src.core.save")
  if not okSave then
    return false, loadedSave
  end
  local okPop, loadedPop = requireFromMod(mod, "src.population.manager")
  if not okPop then
    return false, loadedPop
  end
  local okAvatar, loadedAvatar = requireFromMod(mod, "src.world.avatar_factory")
  if not okAvatar then
    return false, loadedAvatar
  end
  local okController, loadedController = requireFromMod(mod, "src.behavior.controller")
  if not okController then
    return false, loadedController
  end
  local okLogger, loadedLogger = requireFromMod(mod, "src.debug.logger")
  if not okLogger then
    return false, loadedLogger
  end

  Config = loadedConfig
  Save = loadedSave
  PopulationManager = loadedPop
  AvatarFactory = loadedAvatar
  Controller = loadedController
  DebugLogger = loadedLogger
  return true
end

local DEBUG_MODE_OPTION_KEY = "phase0_behavior_mode"
local DEBUG_LOG_OPTION_KEY = "phase0_debug_log"
local DEBUG_LOG_VIEW_OPTION_KEY = "dev_log_view"
local DEBUG_LOG_LIFECYCLE_OPTION_KEY = "dev_log_lifecycle"
local DEBUG_LOG_BEHAVIOR_OPTION_KEY = "dev_log_behavior"
local DEBUG_LOG_RELATIONSHIPS_OPTION_KEY = "dev_log_relationships"

local DEBUG_CATEGORY_PREFIX = {
  lifecycle = "L",
  behavior = "B",
  relationships = "R"
}

local function defineOptions(mod)
  if not (mod and mod.options and mod.options.define) then
    return
  end

  mod.options:define({
    {
      key = DEBUG_MODE_OPTION_KEY,
      type = "choice",
      label = "PHASE0 BEHAVIOR",
      default = "normal",
      choices = {
        { "NORMAL", "normal" },
        { "FORCE IDLE", "force_idle" },
        { "FORCE FLEE", "force_flee" }
      }
    },
    {
      key = DEBUG_LOG_OPTION_KEY,
      type = "toggle",
      label = "PHASE0 LOG",
      default = false
    },
    {
      key = DEBUG_LOG_VIEW_OPTION_KEY,
      type = "choice",
      label = "LOG VIEW",
      default = "both",
      choices = {
        { "SUMMARY", "summary" },
        { "EVENTS", "events" },
        { "BOTH", "both" }
      }
    },
    {
      key = DEBUG_LOG_LIFECYCLE_OPTION_KEY,
      type = "toggle",
      label = "LOG LIFECYCLE",
      default = true
    },
    {
      key = DEBUG_LOG_BEHAVIOR_OPTION_KEY,
      type = "toggle",
      label = "LOG BEHAVIOR",
      default = true
    },
    {
      key = DEBUG_LOG_RELATIONSHIPS_OPTION_KEY,
      type = "toggle",
      label = "LOG RELATIONSHIPS",
      default = false
    }
  })
end

local function normalizeMapId(value)
  if value == nil then
    return nil
  end

  local mapId = tostring(value):upper():gsub("%s+", "_")
  mapId = mapId:gsub("^ROUTE0+([0-9]+)$", "ROUTE_%1")
  mapId = mapId:gsub("^ROUTE([0-9]+)$", "ROUTE_%1")
  return mapId
end

local function isPhase0Map(mapId)
  local normalizedCurrent = normalizeMapId(mapId)
  local phase0 = (Config and Config.phase0) or {}
  local normalizedTarget = normalizeMapId(phase0.testMapId)
  if normalizedCurrent == nil or normalizedTarget == nil then
    return false
  end
  if normalizedCurrent == normalizedTarget then
    return true
  end

  if normalizedTarget == "ROUTE_1" and normalizedCurrent == "1" then
    return true
  end

  return false
end

local function readCurrentMapId(mod)
  local world = mod and mod.world
  local current = world and world.current and world:current() or nil
  if not current then
    return nil
  end

  return current.mapId or current.id or current.name
end

local function ensureSave(mod)
  if not WildEcology.saveReady or WildEcology.mod ~= mod then
    WildEcology.mod = mod
    if not Save or not Save.init then
      return
    end
    Save.init(mod)
    WildEcology.saveReady = true
  end
end

local function applyDebugRelationshipOverrides(rel)
  local phase0 = (Config and Config.phase0) or {}

  if phase0.debugForceTrust ~= nil then
    rel.trust = phase0.debugForceTrust
  end
  if phase0.debugForceThreatMemory ~= nil then
    rel.threatMemory = phase0.debugForceThreatMemory
  end
  if phase0.debugForceHostility ~= nil then
    rel.hostility = phase0.debugForceHostility
  end
end

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

local function getPhase0DebugState()
  if not Save or not Save.getState then
    return nil
  end

  local state = Save.getState()
  if not state then
    return nil
  end

  state.debug = state.debug or {}
  state.debug.phase0 = state.debug.phase0 or {
    lastEvent = nil,
    lastEntityId = nil,
    lastSpawnAvatarId = nil,
    lastDespawnAvatarId = nil,
    lastRespawnCount = 0,
    lastState = nil,
    lastTrust = 0,
    lastThreatMemory = 0,
    lastMapId = nil,
    lastContextMapId = nil,
    lastBehaviorMode = "normal"
  }
  return state.debug.phase0
end

local function readOptionValue(mod, key, defaultValue)
  local options = mod and mod.options
  if options and options.get then
    local ok, value = pcall(function()
      return options:get(key)
    end)
    if ok and value ~= nil then
      return value
    end
  end

  return defaultValue
end

local function readBehaviorMode(mod)
  local rawMode = readOptionValue(mod, DEBUG_MODE_OPTION_KEY, "normal")
  local normalized = tostring(rawMode or "normal"):lower():gsub("%s+", "_")

  if normalized == "force_idle" or normalized == "idle" then
    return "force_idle"
  end
  if normalized == "force_flee" or normalized == "flee" then
    return "force_flee"
  end

  return "normal"
end

local function readDebugLogEnabled(mod)
  return readOptionValue(mod, DEBUG_LOG_OPTION_KEY, false) == true
end

local function readDebugLogView(mod)
  return readOptionValue(mod, DEBUG_LOG_VIEW_OPTION_KEY, "both")
end

local function readDebugCategoryMask(mod)
  return {
    lifecycle = readOptionValue(mod, DEBUG_LOG_LIFECYCLE_OPTION_KEY, true) == true,
    behavior = readOptionValue(mod, DEBUG_LOG_BEHAVIOR_OPTION_KEY, true) == true,
    relationships = readOptionValue(mod, DEBUG_LOG_RELATIONSHIPS_OPTION_KEY, false) == true
  }
end

local function shouldCaptureDebugCategory(mod, category)
  local mask = readDebugCategoryMask(mod)
  return mask[category] == true
end

local function writeDebugLog(mod, category, message)
  if not DebugLogger or not shouldCaptureDebugCategory(mod, category) then
    return nil
  end

  return DebugLogger.log(category, message)
end

local function appendWrappedLine(lines, text, maxWidth, maxLines)
  if maxLines and #lines >= maxLines then
    return
  end

  local remaining = tostring(text or "")
  if remaining == "" then
    if not maxLines or #lines < maxLines then
      lines[#lines + 1] = ""
    end
    return
  end

  while #remaining > maxWidth do
    if maxLines and #lines >= maxLines then
      return
    end
    lines[#lines + 1] = remaining:sub(1, maxWidth)
    remaining = remaining:sub(maxWidth + 1)
  end
  if not maxLines or #lines < maxLines then
    lines[#lines + 1] = remaining
  end
end

local function appendField(lines, label, value, maxWidth, maxLines)
  if maxLines and #lines >= maxLines then
    return
  end

  local rendered = label .. tostring(value or "none")
  if #rendered <= maxWidth then
    lines[#lines + 1] = rendered
    return
  end

  lines[#lines + 1] = label
  appendWrappedLine(lines, value or "none", maxWidth, maxLines)
end

local function enabledCategorySummary(categoryMask)
  local labels = {}
  if categoryMask.lifecycle then
    labels[#labels + 1] = "LIFECYCLE"
  end
  if categoryMask.behavior then
    labels[#labels + 1] = "BEHAVIOR"
  end
  if categoryMask.relationships then
    labels[#labels + 1] = "RELATIONSHIPS"
  end

  if #labels == 0 then
    return "NONE"
  end

  return table.concat(labels, ", ")
end

local function buildDebugLines(maxWidth, maxLines)
  local debugState = getPhase0DebugState()
  if not debugState then
    return {
      "WILD ECOLOGY LOG",
      "No phase 0 debug state yet.",
      "Visit Route 1 once, then reopen this log."
    }
  end

  maxWidth = maxWidth or 18
  maxLines = maxLines or 16
  local lines = { "WILD ECOLOGY LOG" }
  local logView = readDebugLogView(WildEcology.mod)
  local categoryMask = readDebugCategoryMask(WildEcology.mod)
  local categorySummary = enabledCategorySummary(categoryMask)

  appendField(lines, "VIEW MODE: ", string.upper(tostring(logView or "both")), maxWidth, maxLines)
  appendField(lines, "ENABLED LOGS: ", categorySummary, maxWidth, maxLines)

  local wantsSummary = (logView == "summary" or logView == "both")
  local wantsEvents = (logView == "events" or logView == "both")

  if wantsSummary then
    appendField(lines, "LAST EVENT: ", debugState.lastEvent or "none", maxWidth, maxLines)
    appendField(lines, "CURRENT STATE: ", debugState.lastState or "unknown", maxWidth, maxLines)
    appendField(lines, "BEHAVIOR MODE: ", debugState.lastBehaviorMode or "normal", maxWidth, maxLines)
    appendField(lines, "RESPAWN COUNT: ", debugState.lastRespawnCount or 0, maxWidth, maxLines)
    appendField(lines, "CURRENT MAP: ", debugState.lastContextMapId or "none", maxWidth, maxLines)
    appendField(lines, "HOME MAP: ", debugState.lastMapId or "none", maxWidth, maxLines)
    appendField(lines, "TRUST: ", debugState.lastTrust or 0, maxWidth, maxLines)
    appendField(lines, "THREAT MEMORY: ", debugState.lastThreatMemory or 0, maxWidth, maxLines)
  end

  if wantsEvents and #lines < maxLines then
    lines[#lines + 1] = "RECENT EVENTS:"
    local eventSlots = math.max(0, maxLines - #lines)
    local entries = DebugLogger and DebugLogger.filteredEntries(function(entry)
      return categoryMask[entry.category] == true
    end, eventSlots) or {}

    if #entries == 0 then
      lines[#lines + 1] = "NO EVENTS CAPTURED"
    else
      for _, entry in ipairs(entries) do
        local prefix = entry.category and string.upper(entry.category) or "EVENT"
        appendWrappedLine(lines, prefix .. " #" .. tostring(entry.sequence or "?") .. ": " .. tostring(entry.message or ""), maxWidth, maxLines)
        if #lines >= maxLines then
          break
        end
      end
    end
  end

  return lines
end

local function registerDebugUi(mod)
  if WildEcology.debugUiInstalled then
    return
  end

  if mod and mod.hooks and mod.hooks.wrap and mod.ui and mod.ui.Font then
    mod.hooks:wrap("render.hud", function(next, game, viewport)
      next(game, viewport)
      if not readDebugLogEnabled(mod) then
        return
      end

      local Font = mod.ui.Font
      local viewportX = math.floor(((viewport and viewport.gameX) or 0) / 8)
      local viewportY = math.floor(((viewport and viewport.gameY) or 0) / 8)
      local viewportWidthPx = (viewport and (viewport.gameWidth or viewport.width)) or 160
      local tw = math.max(20, math.floor(viewportWidthPx / 8))
      local tx = viewportX
      local ty = viewportY
      local maxLines = math.max(10, math.min(24, math.floor((((viewport and viewport.gameHeight) or (viewport and viewport.height) or 144) / 8) - 2)))
      local lines = buildDebugLines(tw - 2, maxLines)
      local boxHeight = math.max(6, math.min(maxLines + 2, #lines + 2))
      Font.drawBox(tx, ty, tw, boxHeight)
      for index, line in ipairs(lines) do
        Font.draw(line, (tx + 1) * 8, (ty + index) * 8)
      end
    end)
  end

  WildEcology.debugUiInstalled = true
end

local function evaluatePhase0State(mod, mapId, countRespawn)
  local phase0 = (Config and Config.phase0) or {}
  local behaviorMode = readBehaviorMode(mod)

  ensureSave(mod)
  if not Save or not PopulationManager or not AvatarFactory or not Controller then
    return nil
  end

  local simulationTick = Save.nextTick()
  local entity = PopulationManager.getOrCreatePhase0Entity()
  entity.home = entity.home or {}
  entity.home.mapId = mapId or entity.home.mapId or phase0.testMapId
  entity.memory = entity.memory or {}
  entity.memory.debug = entity.memory.debug or { respawnCount = 0 }
  if countRespawn ~= false then
    entity.memory.debug.respawnCount = (entity.memory.debug.respawnCount or 0) + 1
  end

  local player = getPlayerEntity()
  local rel, gainedCalmTrust = PopulationManager.updatePhase0Relationship(entity, player, simulationTick)
  applyDebugRelationshipOverrides(rel)
  if behaviorMode == "force_idle" then
    rel.trust = math.max(rel.trust or 0, 10)
    rel.threatMemory = 0
    rel.hostility = 0
  elseif behaviorMode == "force_flee" then
    rel.trust = 0
    rel.threatMemory = math.max(rel.threatMemory or 0, 5)
    rel.hostility = math.max(rel.hostility or 0, 1)
  end

  if gainedCalmTrust then
    writeDebugLog(mod, "relationships", string.format("Calm proximity to player increased trust to %s and threat memory to %s", tostring(rel.trust or 0), tostring(rel.threatMemory or 0)))
  end

  local state = Controller.tick(entity, rel)
  applyPhase0AvatarBehavior(entity, state)

  return {
    behaviorMode = behaviorMode,
    entity = entity,
    rel = rel,
    state = state,
    mapId = mapId,
    gainedCalmTrust = gainedCalmTrust
  }
end

local function applyPhase0DebugState(debugState, payload, eventName, avatarId)
  if not debugState then
    return
  end

  debugState.lastEvent = eventName
  debugState.lastEntityId = payload.entity.id
  debugState.lastSpawnAvatarId = avatarId or debugState.lastSpawnAvatarId
  debugState.lastRespawnCount = payload.entity.memory.debug.respawnCount
  debugState.lastState = payload.state
  debugState.lastTrust = payload.rel.trust or 0
  debugState.lastThreatMemory = payload.rel.threatMemory or 0
  debugState.lastMapId = payload.entity.home.mapId
  debugState.lastContextMapId = payload.mapId or readCurrentMapId(WildEcology.mod)
  debugState.lastBehaviorMode = payload.behaviorMode
end

local function spawnPhase0Avatar(mod, mapId, eventName)
  local phase0 = (Config and Config.phase0) or {}

  if WildEcology.activeAvatars[phase0.testEntityId] then
    return
  end

  local payload = evaluatePhase0State(mod, mapId, true)
  if not payload or not AvatarFactory or not AvatarFactory.spawn then
    return
  end

  local avatar = AvatarFactory.spawn(mod, payload.entity)
  if avatar then
    avatar.spawnSequence = payload.entity.memory.debug.respawnCount
    WildEcology.activeAvatars[payload.entity.id] = avatar

    local debugState = getPhase0DebugState()
    applyPhase0DebugState(debugState, payload, eventName or "spawn", avatar.id)

    writeDebugLog(mod, "behavior", string.format("Behavior resolved to %s under mode %s with trust=%s and threat=%s", tostring(payload.state), tostring(payload.behaviorMode), tostring(payload.rel.trust or 0), tostring(payload.rel.threatMemory or 0)))
    writeDebugLog(mod, "lifecycle", string.format("Spawned avatar %s on %s with respawn count %s", tostring(avatar.id or "none"), tostring(payload.entity.home.mapId or "none"), tostring(payload.entity.memory.debug.respawnCount or 0)))

    if Save and Save.flush then
      Save.flush()
    end
  end
end

local function applyBehaviorModeToActiveAvatar(mod, mapId)
  local phase0 = (Config and Config.phase0) or {}
  local avatar = WildEcology.activeAvatars[phase0.testEntityId]
  if not avatar then
    return false
  end

  local payload = evaluatePhase0State(mod, mapId, false)
  if not payload then
    return false
  end

  local debugState = getPhase0DebugState()
  local previousMode = debugState and debugState.lastBehaviorMode or nil
  local previousState = debugState and debugState.lastState or nil
  local modeChanged = previousMode ~= payload.behaviorMode
  local stateChanged = previousState ~= payload.state
  if not modeChanged and not stateChanged then
    return false
  end

  avatar.behaviorMode = payload.behaviorMode
  avatar.runtimeState = payload.state

  local behaviorApplied = false
  if AvatarFactory and AvatarFactory.applyBehavior then
    behaviorApplied = AvatarFactory.applyBehavior(mod, avatar, payload.entity)
  elseif type(avatar.handle) == "table" then
    -- Legacy fallback for tests if the adapter seam is unavailable.
    avatar.handle.movement = payload.entity.avatar and payload.entity.avatar.movement or avatar.handle.movement
    avatar.handle.range = payload.entity.avatar and payload.entity.avatar.range or avatar.handle.range
    behaviorApplied = true
  end

  applyPhase0DebugState(debugState, {
    behaviorMode = payload.behaviorMode,
    entity = payload.entity,
    rel = payload.rel,
    state = payload.state,
    mapId = mapId,
    gainedCalmTrust = payload.gainedCalmTrust
  }, modeChanged and "mode_change" or "state_update", type(avatar) == "table" and avatar.id or nil)

  writeDebugLog(mod, "behavior", string.format("Applied live behavior update: mode=%s state=%s trust=%s threat=%s runtime=%s", tostring(payload.behaviorMode), tostring(payload.state), tostring(payload.rel.trust or 0), tostring(payload.rel.threatMemory or 0), tostring(behaviorApplied)))

  if Save and Save.flush then
    Save.flush()
  end

  return true
end

function WildEcology.init(mod)
  local mapId = readCurrentMapId(mod)
  if not isPhase0Map(mapId) then
    return
  end

  if applyBehaviorModeToActiveAvatar(mod, mapId) then
    return
  end

  spawnPhase0Avatar(mod, mapId)
end

function WildEcology.sync(mod)
  local mapId = readCurrentMapId(mod)
  if isPhase0Map(mapId) then
    WildEcology.init(mod)
    return
  end

  if next(WildEcology.activeAvatars) ~= nil then
    WildEcology.shutdown()
  end
end

function WildEcology.shutdown()
  if not AvatarFactory or not AvatarFactory.despawn then
    return
  end

  for id, avatar in pairs(WildEcology.activeAvatars) do
    local debugState = getPhase0DebugState()
    if debugState then
      debugState.lastEvent = "despawn"
      debugState.lastEntityId = id
      debugState.lastDespawnAvatarId = type(avatar) == "table" and avatar.id or avatar
      debugState.lastRespawnCount = type(avatar) == "table" and avatar.spawnSequence or debugState.lastRespawnCount
      debugState.lastContextMapId = readCurrentMapId(WildEcology.mod)
    end

    writeDebugLog(WildEcology.mod, "lifecycle", string.format("Despawned avatar %s after leaving to %s", tostring(type(avatar) == "table" and avatar.id or avatar or "none"), tostring(readCurrentMapId(WildEcology.mod) or "unknown")))

    AvatarFactory.despawn(WildEcology.mod, avatar)
    WildEcology.activeAvatars[id] = nil
  end

  if WildEcology.saveReady and Save and Save.flush then
    Save.flush()
  end
end

function WildEcology.start(mod)
  installRequireShim(mod)

  local loaded, loadErr = loadModules(mod)
  if not loaded then
    error(loadErr)
  end

  WildEcology.mod = mod
  defineOptions(mod)
  registerDebugUi(mod)
  WildEcology.sync(mod)

  if WildEcology.updateHookInstalled then
    return WildEcology
  end

  local ok, OverworldController = pcall(require, "src.world.OverworldController")
  if ok and OverworldController and type(OverworldController.update) == "function" then
    local originalUpdate = OverworldController.update
    OverworldController.update = function(self, dt)
      originalUpdate(self, dt)
      pcall(WildEcology.sync, mod)
    end
    WildEcology.updateHookInstalled = true
  end

  return WildEcology
end

return function(mod)
  return WildEcology.start(mod)
end
