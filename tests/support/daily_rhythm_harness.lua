local Controller = require("src.behavior.controller")
local Drives = require("src.needs.drives")
local HomeArea = require("src.world.home_area")

local Harness = {}
Harness.__index = Harness

local function copyPosition(position)
  return { cellX = position.cellX, cellY = position.cellY }
end

local function increment(tableValue, key, amount)
  tableValue[key] = (tableValue[key] or 0) + (amount or 1)
end

local function phaseAt(tick, ticksPerDay)
  return (tick % ticksPerDay) / ticksPerDay
end

function Harness.new(options)
  local config = options or {}
  local entity = assert(config.entity, "daily-rhythm entity is required")
  local position = assert(config.position, "daily-rhythm position is required")
  return setmetatable({
    entity = entity,
    position = copyPosition(position),
    semantics = assert(config.semantics, "daily-rhythm semantics are required"),
    mapId = config.mapId or config.semantics.mapId,
    ticksPerDay = config.ticksPerDay or 7200,
    decisionCadence = config.decisionCadence or 15,
    context = config.context,
    lifecycle = config.lifecycle,
    afterStep = config.afterStep,
    timelineLimit = config.timelineLimit or 96,
    metrics = {
      behaviorTicks = {},
      episodes = {},
      transitions = 0,
      satisfactions = {},
      homeReturns = 0,
      concealmentIntervals = 0,
      emergencyInterruptions = 0,
      timeline = {},
      driveMinimum = {},
      driveMaximum = {}
    },
    previousState = entity.runtimeState and entity.runtimeState.state or "SETTLED",
    previousSatisfiedTick = {},
    previousConcealed = entity.locationState
      and entity.locationState.kind == "CONCEALED" or false,
    episodeStartTick = config.startTick or 0,
    tick = config.startTick or 0
  }, Harness)
end

function Harness:recordTransition(tick, state, reason)
  local metrics = self.metrics
  local duration = tick - self.episodeStartTick
  metrics.episodes[#metrics.episodes + 1] = {
    state = self.previousState,
    startedTick = self.episodeStartTick,
    endedTick = tick,
    duration = duration
  }
  metrics.transitions = metrics.transitions + 1
  if state == "RETURN_HOME" then metrics.homeReturns = metrics.homeReturns + 1 end
  if state == "FLEE" then metrics.emergencyInterruptions = metrics.emergencyInterruptions + 1 end
  if #metrics.timeline < self.timelineLimit then
    local home = HomeArea.isInside(self.entity, self.position, self.mapId)
    local drives = self.entity.drives or {}
    metrics.timeline[#metrics.timeline + 1] = {
      tick = tick,
      phase = phaseAt(tick, self.ticksPerDay),
      from = self.previousState,
      to = state,
      reason = reason,
      position = copyPosition(self.position),
      insideHome = home,
      hunger = drives.HUNGER and drives.HUNGER.value or 0,
      thirst = drives.THIRST and drives.THIRST.value or 0,
      fatigue = drives.FATIGUE and drives.FATIGUE.value or 0,
      concealed = self.entity.locationState
        and self.entity.locationState.kind == "CONCEALED" or false
    }
  end
  self.previousState = state
  self.episodeStartTick = tick
end

function Harness:observeDrives(tick)
  for id, record in pairs(self.entity.drives or {}) do
    local metrics = self.metrics
    metrics.driveMinimum[id] = math.min(metrics.driveMinimum[id] or 1,
      record.value or 0)
    metrics.driveMaximum[id] = math.max(metrics.driveMaximum[id] or 0,
      record.value or 0)
    if record.lastSatisfiedTick
      and record.lastSatisfiedTick ~= self.previousSatisfiedTick[id] then
      increment(metrics.satisfactions, id)
      self.previousSatisfiedTick[id] = record.lastSatisfiedTick
    end
  end
end

function Harness:baseContext(tick)
  local context = {
    tick = tick,
    ecologyPhase = phaseAt(tick, self.ticksPerDay),
    position = copyPosition(self.position),
    mapId = self.mapId,
    worldSemantics = self.semantics,
    locomotionPacing = true,
    occupiedCells = {},
    occupancyDetails = {},
    currentOccupiedCells = {},
    targetPositions = {},
    candidates = {},
    hasTarget = false,
    purposefulTarget = false,
    allowTargeting = true
  }
  if self.context then self.context(self, context, tick) end
  return context
end

function Harness:advanceOne(tick)
  self.tick = tick
  local context = self:baseContext(tick)
  local concealed = self.entity.locationState
    and self.entity.locationState.kind == "CONCEALED" or false
  local state
  if concealed and self.lifecycle then
    state = self.lifecycle(self, context, tick)
      or self.entity.runtimeState and self.entity.runtimeState.state
      or "CONCEALED"
  elseif tick == 1 or tick % self.decisionCadence == 0 then
    state = Controller.tick(self.entity, context.relationship, context.distance,
      context, tick)
  else
    state = Controller.executeCurrentIntent(self.entity, context, tick)
  end

  local request = self.entity.runtimeState
    and self.entity.runtimeState.movementRequest or nil
  if request and request.traversalMode == "WALK"
    and request.destinationX ~= nil and request.destinationY ~= nil then
    self.position = {
      cellX = request.destinationX,
      cellY = request.destinationY
    }
    self.entity.runtimeState.motion = { active = false, justCompleted = true }
  elseif self.entity.runtimeState then
    self.entity.runtimeState.motion = self.entity.runtimeState.motion or {}
    self.entity.runtimeState.motion.active = false
  end

  if self.afterStep then self.afterStep(self, context, tick, state) end
  increment(self.metrics.behaviorTicks, state or "NONE")
  self:observeDrives(tick)

  local nowConcealed = self.entity.locationState
    and self.entity.locationState.kind == "CONCEALED" or false
  if nowConcealed and not self.previousConcealed then
    self.metrics.concealmentIntervals = self.metrics.concealmentIntervals + 1
  end
  self.previousConcealed = nowConcealed
  if state ~= self.previousState then
    local reason = self.entity.runtimeState
      and self.entity.runtimeState.selectionReason or "LIFECYCLE"
    self:recordTransition(tick, state, reason)
  end
end

function Harness:run(duration)
  local finalTick = self.tick + duration
  for tick = self.tick + 1, finalTick do self:advanceOne(tick) end
  self.metrics.episodes[#self.metrics.episodes + 1] = {
    state = self.previousState,
    startedTick = self.episodeStartTick,
    endedTick = finalTick,
    duration = finalTick - self.episodeStartTick + 1
  }
  self.tick = finalTick
  return self.metrics
end

function Harness.occupancy(metrics, duration)
  local result = {}
  for behavior, ticks in pairs(metrics.behaviorTicks) do
    result[behavior] = ticks / duration
  end
  return result
end

return Harness