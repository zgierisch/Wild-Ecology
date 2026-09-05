local Controller = require("src.behavior.controller")

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local originalRequire = require
require = function(moduleName)
  if type(moduleName) == "string" and moduleName:sub(1, 4) == "src." then
    error("hostile loader rejected runtime import: " .. moduleName)
  end
  return originalRequire(moduleName)
end

local semantics = {
  width = 9, height = 7,
  rows = {
    "#########",
    "#.......#",
    "#.......#",
    "#....####",
    "#....####",
    "#....####",
    "#########"
  },
  cellOverrides = {}, edgeOverrides = {}, transitions = {},
  connectionSourceCells = {}, usableConnectionSourceCells = {}
}
local actor = {
  id = "forced-hostile-loader",
  personalitySeed = 12,
  temperament = { sociability = 0.5 },
  rawStats = { independence = 0.5 },
  runtimeState = { fearCurrent = 0.8 }
}
local ok, failure = pcall(function()
  Controller.tick(actor, { trust = 0, threatMemory = 80, hostility = 10 }, 2, {
    targetEntityId = "trainer",
    threatAssessment = {
      primaryThreatId = "trainer",
      primaryThreatScore = 10,
      primaryThreatReason = "HOSTILITY",
      primaryThreatDistance = 2
    },
    targetPositions = { trainer = { cellX = 1, cellY = 3 } },
    position = { cellX = 4, cellY = 3 },
    currentFear = 0.8,
    worldSemantics = semantics
  }, 1)
end)
require = originalRequire

assertTrue(ok, failure)
assertTrue(actor.runtimeState.state == "FLEE", "legitimate threat evidence should select FLEE through utility")
assertTrue(actor.runtimeState.escapeHeading and actor.runtimeState.escapeHeading.openSpaceWeight,
  "forced FLEE should execute adaptive heading and local openness")
assertTrue(actor.runtimeState.escapeHeading.openSpaceY < 0,
  "asymmetric terrain should prove the supplied local-openness query executed")
assertTrue(actor.runtimeState.movementRequest
    and actor.runtimeState.movementRequest.traversalMode == "WALK",
  "forced FLEE should produce a legitimate WALK under the hostile loader")

return true