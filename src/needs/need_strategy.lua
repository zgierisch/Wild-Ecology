local DriveDefinitions = require("src.needs.drive_definitions")
local Drives = require("src.needs.drives")
local FoodOpportunities = require("src.needs.food_opportunities")
local NavigationPlanner = require("src.navigation.navigation_planner")
local SpatialGoal = require("src.behavior.spatial_goal")
local WorldSemantics = require("src.world.world_semantics")

local NeedStrategy = {}

local strategies = {}
local counters = { plannerCalls = 0, suppressedPlans = 0, opportunities = 0,
  evaluations = 0, foodSearches = 0, waterSearches = 0 }
local FAILED_GOAL_COOLDOWN = 180

function NeedStrategy.register(driveId, strategy)
  assert(DriveDefinitions.get(driveId), "unknown drive " .. tostring(driveId))
  strategies[driveId] = strategy
end

local function routeExists(entity, context, goal, tick)
  if SpatialGoal.isSatisfied(goal, context.position) then return true end
  entity.runtimeState = entity.runtimeState or {}
  local failures = entity.runtimeState.needSearchFailures or {}
  entity.runtimeState.needSearchFailures = failures
  local signature = SpatialGoal.signature(goal)
  if (failures[signature] or 0) > (tick or 0) then
    counters.suppressedPlans = counters.suppressedPlans + 1
    return false
  end
  counters.plannerCalls = counters.plannerCalls + 1
  local route = NavigationPlanner.plan(entity, context.worldSemantics,
    context.position, goal, {
      maxDepth = context.needSearchRadius or 12,
      maxExpansions = 256,
      allowedModes = { WALK = true }
    })
  local reachable = route ~= nil and route.reachedGoal == true
  if reachable then
    failures[signature] = nil
  else
    failures[signature] = (tick or 0) + FAILED_GOAL_COOLDOWN
  end
  return reachable
end

function NeedStrategy.getCounters()
  return {
    plannerCalls = counters.plannerCalls,
    suppressedPlans = counters.suppressedPlans,
    opportunities = counters.opportunities,
    evaluations = counters.evaluations,
    foodSearches = counters.foodSearches,
    waterSearches = counters.waterSearches
  }
end

function NeedStrategy.resetCounters()
  for key in pairs(counters) do counters[key] = 0 end
end

function NeedStrategy.evaluate(entity, context, tick)
  counters.evaluations = counters.evaluations + 1
  if not context or not context.position or not context.worldSemantics then return nil end
  local best
  for driveId, strategy in pairs(strategies) do
    local status = Drives.status(entity, driveId, tick)
    if status.motivating then
      if driveId == "HUNGER" then
        counters.foodSearches = counters.foodSearches + 1
      elseif driveId == "THIRST" then
        counters.waterSearches = counters.waterSearches + 1
      end
      local candidates = strategy.candidates
        and strategy.candidates(entity, context, tick)
        or WorldSemantics.findNearbyFeature(context.worldSemantics,
          context.position, strategy.semantic, context.needSearchRadius or 12)
      for _, candidate in ipairs(candidates) do
        local semantic = candidate.semantic or strategy.semantic
        local cellX, cellY = candidate.cellX or candidate.x, candidate.cellY or candidate.y
        local goal = SpatialGoal.position({ cellX = cellX, cellY = cellY }, {
          mapId = context.mapId or context.worldSemantics.mapId,
          traversalMode = "WALK",
          source = "need:" .. driveId .. ":" .. semantic
        })
        if routeExists(entity, context, goal, tick) then
          local definition = DriveDefinitions.get(driveId)
          local opportunity = {
            driveId = driveId,
            semantic = semantic,
            goal = goal,
            goalSignature = SpatialGoal.signature(goal),
            distance = candidate.distance,
            score = (definition.motivatingScoreBase or 24)
              + status.urgency * (definition.motivatingScoreScale or 40),
            status = status,
            opportunity = candidate.kind == "FOOD_OPPORTUNITY" and candidate or nil
          }
          if not best or opportunity.score > best.score
            or opportunity.score == best.score and opportunity.goalSignature < best.goalSignature then
            best = opportunity
          end
          counters.opportunities = counters.opportunities + 1
          break
        end
      end
    end
  end
  return best
end

NeedStrategy.register("THIRST", { semantic = "WATER_ADJACENT" })
NeedStrategy.register("HUNGER", { candidates = FoodOpportunities.findNearby })

return NeedStrategy