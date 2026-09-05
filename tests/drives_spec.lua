local DriveDefinitions = require("src.needs.drive_definitions")
local Drives = require("src.needs.drives")
local RuntimeState = require("src.core.runtime_state")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "assertEquals failed") .. ": expected "
      .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local function assertNear(actual, expected, tolerance, message)
  if math.abs(actual - expected) > tolerance then
    error((message or "assertNear failed") .. ": expected "
      .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

DriveDefinitions.register("TEST_DRIVE", {
  initialMin = 0.1,
  initialMax = 0.1,
  accumulationPerTick = 0.1,
  activationThreshold = 0.5,
  satisfactionThreshold = 0.2,
  satisfactionAmount = 0.3
})

local events = {}
Drives.setDiagnosticSink(function(event) events[#events + 1] = event end)
local actor = { id = "drive-test", personalitySeed = 12 }
Drives.ensure(actor, 10)
assertNear(actor.drives.TEST_DRIVE.value, 0.1, 0.000001,
  "new drives should begin at their calm baseline")
assertNear(Drives.status(actor, "TEST_DRIVE", 14).value, 0.5, 0.000001,
  "drive accumulation should depend on elapsed ticks")
assertEquals(Drives.status(actor, "TEST_DRIVE", 14).motivating, true,
  "activation threshold should make the drive motivating")
assertNear(Drives.status(actor, "TEST_DRIVE", 14).value, 0.5, 0.000001,
  "repeated calls at one tick must not accelerate a drive")

local partial = Drives.satisfy(actor, "TEST_DRIVE", 0.2, 14, "TEST")
assertNear(partial.value, 0.3, 0.000001,
  "partial satisfaction should reduce rather than zero a drive")
assertEquals(partial.motivating, true,
  "hysteresis should retain motivation above the satisfaction threshold")
local full = Drives.satisfy(actor, "TEST_DRIVE", 0.15, 14, "TEST")
assertNear(full.value, 0.15, 0.000001,
  "a later satisfaction action should reduce the same drive further")
assertEquals(full.motivating, false,
  "motivation should release below the separate satisfaction threshold")

local persistedDrives = actor.drives
RuntimeState.reset(actor)
assertEquals(actor.drives, persistedDrives,
  "runtime reset must preserve biological drive state")
assertEquals(actor.runtimeState.drives, nil,
  "runtime reset must discard drive behavior bookkeeping")
assertEquals(Drives.inspect(actor, 14):find("TEST_DRIVE", 1, true) ~= nil, true,
  "drive inspector should expose registered drive state")
assertEquals(#events >= 3, true,
  "threshold crossings and satisfaction should emit low-volume semantic events")

Drives.setDiagnosticSink(nil)
return true