local EscapeHeading = require("src.behavior.escape_heading")
local Steering = require("src.behavior.steering")

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local function simulate(seed, independence)
  local entity = {
    id = "fan-" .. seed,
    personalitySeed = seed,
    temperament = { sociability = 0.8 },
    rawStats = { independence = independence },
    runtimeState = {}
  }
  local threat = { cellX = 0, cellY = 0 }
  local position = { cellX = 3, cellY = 0 }
  local origin = { cellX = position.cellX, cellY = position.cellY }
  local heading = EscapeHeading.update(entity, position, threat, {
    neighbors = {},
    socialAlignment = { dx = 1, dy = 0 }
  }, 1)
  local first = { dx = heading.dx, dy = heading.dy }
  local path = {}
  local previousDirection = nil
  for step = 1, 12 do
    heading = EscapeHeading.update(entity, position, threat, {
      neighbors = {},
      socialAlignment = { dx = 1, dy = 0 },
      completedDirection = previousDirection
    }, step)
    local request = Steering.request(position, {
      objective = "AWAY",
      targetEntityId = "threat",
      targetPosition = threat,
      radius = 99
    }, {
      desiredHeading = heading,
      headingResidual = {
        dx = heading.residualX,
        dy = heading.residualY
      }
    })
    position = { cellX = request.destinationX, cellY = request.destinationY }
    path[#path + 1] = request.direction
    previousDirection = request.direction
  end
  return entity, first, position, table.concat(path, ",")
end

local low, lowFirst, lowEnd, lowPath = simulate(101, 0.1)
local lowAgain, lowAgainFirst, _, lowAgainPath = simulate(101, 0.1)
local high, highFirst, highEnd, highPath = simulate(102, 0.9)

assertTrue(lowFirst.dx == lowAgainFirst.dx and lowFirst.dy == lowAgainFirst.dy and lowPath == lowAgainPath,
  "same personality and context should produce a stable deterministic escape tendency")
assertTrue(lowPath ~= highPath and lowFirst.dy * highFirst.dy <= 0,
  "different personalities should produce distinct lateral escape tendencies")
assertTrue(lowEnd.cellX > 3 and highEnd.cellX > 3,
  "all fan-out trajectories should make meaningful net progress away from danger")
assertTrue(lowEnd.cellY ~= 0 and highEnd.cellY ~= 0,
  "conceptual non-cardinal headings should use lateral grid steps over time")
assertTrue(math.abs(highFirst.dy) > math.abs(lowFirst.dy),
  "higher independence should permit stronger individual lateral dispersion")
assertTrue(low.runtimeState.escapeHeading ~= nil and high.runtimeState.escapeHeading ~= nil,
  "escape heading should remain transient actor-local runtime state")

local function rasterize(heading, steps)
  local position = { cellX = 0, cellY = 0 }
  local residual = { dx = 0, dy = 0 }
  local directions = {}
  local previousDirection = nil
  for _ = 1, steps do
    if previousDirection == "RIGHT" then residual.dx = residual.dx - 1
    elseif previousDirection == "LEFT" then residual.dx = residual.dx + 1
    elseif previousDirection == "DOWN" then residual.dy = residual.dy - 1
    elseif previousDirection == "UP" then residual.dy = residual.dy + 1 end
    residual.dx = residual.dx + heading.dx
    residual.dy = residual.dy + heading.dy
    local request = Steering.request(position, {
      objective = "AWAY",
      targetPosition = { cellX = -20, cellY = 0 },
      radius = 99
    }, { desiredHeading = heading, headingResidual = residual })
    previousDirection = request.direction
    directions[#directions + 1] = previousDirection
    position = { cellX = request.destinationX, cellY = request.destinationY }
  end
  return position, directions
end

local diagonalEnd, diagonalPath = rasterize({ dx = 0.85, dy = 0.35 }, 20)
local diagonalVertical = 0
for _, direction in ipairs(diagonalPath) do
  if direction == "UP" or direction == "DOWN" then diagonalVertical = diagonalVertical + 1 end
end
assertTrue(diagonalVertical >= 4 and diagonalVertical <= 8,
  "meaningful minor-axis demand should accumulate into proportional lateral WALK steps")
assertTrue(diagonalEnd.cellX > math.abs(diagonalEnd.cellY),
  "rasterized displacement should retain the dominant continuous-heading axis")
local pureEnd, purePath = rasterize({ dx = 0.995, dy = 0.05 }, 12)
local pureLateral = 0
for _, direction in ipairs(purePath) do
  if direction == "UP" or direction == "DOWN" then pureLateral = pureLateral + 1 end
end
assertTrue(pureEnd.cellX >= 10 and pureLateral <= 1,
  "a near-pure heading should legitimately retain a long straight run")

local semantics = {
  width = 9,
  height = 7,
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
local openEntity = {
  id = "open-space", personalitySeed = 2,
  temperament = { sociability = 0.4 }, rawStats = { independence = 0.5 },
  runtimeState = { fearCurrent = 0.25 }
}
local openHeading = EscapeHeading.update(openEntity, { cellX = 4, cellY = 3 }, { cellX = 1, cellY = 3 }, {
  isWalkable = function(from, destination)
    local WorldSemantics = require("src.world.world_semantics")
    return WorldSemantics.isLandingAllowed(semantics, destination.cellX, destination.cellY, "WALK")
      and WorldSemantics.isEdgeAllowed(
        semantics, from.cellX, from.cellY, destination.cellX, destination.cellY, "WALK"
      )
  end,
  recoveryProgress = 0.7, threatPositionConfidence = 0.3
}, 1)
assertTrue(openHeading.openSpaceY < 0,
  "moderate recovery should detect and gently favor nearby opening terrain before collision")

local separating = {
  id = "separating", personalitySeed = 2,
  temperament = { sociability = 0.4 }, rawStats = { independence = 0.5 },
  runtimeState = { fearCurrent = 0.6 }
}
local neighbor = {
  entity = { id = "neighbor", runtimeState = { state = "FLEE" } },
  position = { cellX = 4, cellY = 1 }
}
local separated = EscapeHeading.update(separating, { cellX = 4, cellY = 2 }, { cellX = 1, cellY = 2 }, {
  neighbors = { neighbor }
}, 1)
local rememberedSeparation = EscapeHeading.update(separating, { cellX = 5, cellY = 2 }, { cellX = 1, cellY = 2 }, {
  neighbors = {}, completedDirection = "RIGHT"
}, 2)
assertTrue(separated.separationY > 0 and rememberedSeparation.separationY > 0,
  "fan-out separation should decay over several decisions instead of disappearing after one tile")

return true