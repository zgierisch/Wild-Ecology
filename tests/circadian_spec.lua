package.path = package.path .. ";./?.lua;./?/init.lua"

local CircadianSystem = require("src.circadian.circadian_system")

local function actor(id, seed, profile)
  return { id = id, personalitySeed = seed,
    ecology = { activityProfile = profile } }
end

local phases = { dawn = 0.25, noon = 0.50, dusk = 0.75, midnight = 0.00 }
local diurnal = actor("diurnal", 10, "DIURNAL")
local nocturnal = actor("nocturnal", 10, "NOCTURNAL")
local crepuscular = actor("crepuscular", 10, "CREPUSCULAR")
local flexible = actor("flexible", 10, "FLEXIBLE")
local weak = actor("weak", 10, "WEAK_CIRCADIAN")

assert(CircadianSystem.evaluate(diurnal, phases.noon).activityBias
  > CircadianSystem.evaluate(diurnal, phases.midnight).activityBias,
  "diurnal activity should favor noon")
assert(CircadianSystem.evaluate(nocturnal, phases.midnight).activityBias
  > CircadianSystem.evaluate(nocturnal, phases.noon).activityBias,
  "nocturnal activity should favor midnight")
assert(CircadianSystem.evaluate(crepuscular, phases.dawn).activityBias
  > CircadianSystem.evaluate(crepuscular, phases.noon).activityBias,
  "crepuscular activity should favor dawn")
assert(CircadianSystem.evaluate(crepuscular, phases.dusk).activityBias
  > CircadianSystem.evaluate(crepuscular, phases.midnight).activityBias,
  "crepuscular activity should favor dusk")

local flexibleRange = math.abs(CircadianSystem.evaluate(flexible, phases.noon).activityBias
  - CircadianSystem.evaluate(flexible, phases.midnight).activityBias)
local weakRange = math.abs(CircadianSystem.evaluate(weak, phases.noon).activityBias
  - CircadianSystem.evaluate(weak, phases.midnight).activityBias)
assert(flexibleRange < 0.5, "flexible profile should remain broadly available")
assert(weakRange < 0.25, "weak circadian modulation should remain shallow")

local first = actor("first", 100, "DIURNAL")
local second = actor("second", 101, "DIURNAL")
local firstResult = CircadianSystem.evaluate(first, phases.dawn)
local secondResult = CircadianSystem.evaluate(second, phases.dawn)
assert(firstResult.activityBias ~= secondResult.activityBias,
  "individuals sharing a profile should not switch in lockstep")
local savedOffset = first.ecology.circadian.phaseOffset
CircadianSystem.ensure(first)
assert(first.ecology.circadian.phaseOffset == savedOffset,
  "identity variation should be stable when reloaded")

local sameOverlap = CircadianSystem.overlap(
  actor("day-a", 1, "DIURNAL"), actor("day-b", 2, "DIURNAL"))
local oppositeOverlap = CircadianSystem.overlap(
  actor("day-c", 1, "DIURNAL"), actor("night-a", 2, "NOCTURNAL"))
assert(sameOverlap.active > oppositeOverlap.active,
  "matching profiles should have more active social overlap")