local EcologyClockAdapter = require("src.time.ecology_clock_adapter")

local EcologyClock = {}

local function ensureState(state)
  state.ecologyClock = state.ecologyClock or {
    mode = "SIMULATION",
    previousMode = "SIMULATION",
    simulationEcologyTime = 12 * 3600,
    lastSimulationTick = state.simulationTick or 0,
    lastObservedByMode = {}
  }
  local clock = state.ecologyClock
  clock.mode = clock.mode or "SIMULATION"
  clock.previousMode = clock.previousMode or clock.mode
  clock.simulationEcologyTime = clock.simulationEcologyTime or 12 * 3600
  clock.lastSimulationTick = clock.lastSimulationTick or state.simulationTick or 0
  clock.lastObservedByMode = clock.lastObservedByMode or {}
  return clock
end

local function band(phase)
  if phase >= 0.20 and phase < 0.30 then return "DAWN" end
  if phase >= 0.30 and phase < 0.70 then return "DAY" end
  if phase >= 0.70 and phase < 0.80 then return "DUSK" end
  return "NIGHT"
end

function EcologyClock.ensure(state)
  return ensureState(state)
end

function EcologyClock.setMode(state, mode)
  assert(mode == "REAL_TIME" or mode == "SIMULATION" or mode == "FIXED",
    "invalid ecology clock mode")
  local clock = ensureState(state)
  if mode == "FIXED" then
    if clock.mode ~= "FIXED" then clock.previousMode = clock.mode end
  elseif clock.mode ~= mode then
    clock.previousMode = mode
  end
  clock.mode = mode
  return clock
end

function EcologyClock.leaveFixed(state)
  local clock = ensureState(state)
  clock.mode = clock.previousMode or "SIMULATION"
  return clock.mode
end

function EcologyClock.now(state, options)
  options = options or {}
  local persistent = ensureState(state)
  local mode = options.mode or persistent.mode
  local source = {
    mode = mode,
    simulationTick = options.simulationTick or state.simulationTick or 0,
    dayDurationSeconds = options.dayDurationSeconds,
    ticksPerSecond = options.ticksPerSecond,
    initialEcologyTime = options.initialEcologyTime,
    fixedPhase = options.fixedPhase,
    fixedDayIndex = options.fixedDayIndex,
    fixedEcologyTime = options.fixedEcologyTime,
    hostNow = options.hostNow,
    hostDate = options.hostDate
  }
  local sample = EcologyClockAdapter.now(source, persistent)
  sample.band = band(sample.phase)

  local previous = persistent.lastObservedByMode[mode]
  local elapsed = previous and sample.monotonicEcologyTime - previous or 0
  if elapsed < 0 then
    sample.discontinuity = "BACKWARD"
    sample.elapsed = 0
  else
    sample.elapsed = elapsed
    if options.forwardJumpThreshold and elapsed > options.forwardJumpThreshold then
      sample.discontinuity = "FORWARD"
    end
  end
  if mode ~= "FIXED" then
    persistent.lastObservedByMode[mode] = sample.monotonicEcologyTime
  end
  return sample
end

function EcologyClock.elapsedSince(sample, timestamp)
  return math.max(0, (sample and sample.monotonicEcologyTime or 0)
    - (timestamp or 0))
end

function EcologyClock.inspect(sample)
  return string.format(
    "ECOLOGY CLOCK source=%s phase=%.4f time=%02d:%02d:%02d band=%s day=%s",
    tostring(sample.source), sample.phase or 0, sample.hour or 0,
    sample.minute or 0, sample.second or 0, tostring(sample.band),
    tostring(sample.dayIndex))
end

EcologyClock.band = band

return EcologyClock