package.path = package.path .. ";./?.lua;./?/init.lua"

local EcologyClock = require("src.time.ecology_clock")

local function assertEquals(actual, expected, message)
  assert(actual == expected, (message or "values differ")
    .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local state = { simulationTick = 0 }
local noon = EcologyClock.now(state, { dayDurationSeconds = 60 })
assertEquals(noon.source, "SIMULATION", "simulation is the default")
assertEquals(noon.hour, 12, "simulation clock starts at noon")

state.simulationTick = 3600
local nextNoon = EcologyClock.now(state, { dayDurationSeconds = 60 })
assertEquals(nextNoon.dayIndex, 1, "one configured day advances analytically")
assertEquals(nextNoon.hour, 12, "simulation phase wraps without drift")

EcologyClock.setMode(state, "REAL_TIME")
local real = EcologyClock.now(state, {
  hostNow = function() return 200000 end,
  hostDate = function() return { hour = 5, min = 30, sec = 15 } end
})
assertEquals(real.source, "REAL_TIME", "real mode uses host source")
assertEquals(real.hour, 5, "host local hour is normalized")
assertEquals(real.minute, 30, "host local minute is normalized")

local backward = EcologyClock.now(state, {
  hostNow = function() return 196400 end,
  hostDate = function() return { hour = 4, min = 30, sec = 15 } end
})
assertEquals(backward.elapsed, 0, "backward clock movement never reverses ecology")
assertEquals(backward.discontinuity, "BACKWARD", "backward movement is diagnosed")

EcologyClock.setMode(state, "FIXED")
local fixed = EcologyClock.now(state, { fixedPhase = 0.75 })
assertEquals(fixed.hour, 18, "fixed phase is deterministic")
assertEquals(fixed.band, "DUSK", "fixed phase exposes semantic band")
assertEquals(state.ecologyClock.lastObservedByMode.FIXED, nil,
  "fixed time does not mutate persisted observations")
assertEquals(EcologyClock.leaveFixed(state), "REAL_TIME",
  "fixed mode returns to the previous source")

EcologyClock.setMode(state, "SIMULATION")
assertEquals(state.ecologyClock.simulationEcologyTime, 129600,
  "source switching preserves simulation clock position")

local forward = EcologyClock.now(state, {
  mode = "REAL_TIME",
  hostNow = function() return 300000 end,
  hostDate = function() return { hour = 11, min = 20, sec = 0 } end,
  forwardJumpThreshold = 7200
})
assertEquals(forward.discontinuity, "FORWARD", "large forward jump is diagnosed")
assert(forward.elapsed > 0, "forward elapsed remains available for coarse catch-up")