local DormantCohort = require("src.dormant.dormant_cohort")
local DormantCohortSimulator = require("src.dormant.dormant_cohort_simulator")
local FoodOpportunities = require("src.needs.food_opportunities")
local NavigationPlanner = require("src.navigation.navigation_planner")
local SpatialGoal = require("src.behavior.spatial_goal")
local WorldSemantics = require("src.world.world_semantics")

local DormantLifecycle = {}

local function entitiesById(state, mapId)
  local population = state.populations and state.populations[mapId]
  return population and population.members or {}
end

function DormantLifecycle.capture(state, mapId, entities, clockSample, options)
  options = options or {}
  local semantics = options.worldSemantics
  if semantics and options.positions then
    options.opportunityEvidence = options.opportunityEvidence or {}
    for _, driveId in ipairs({ "THIRST", "HUNGER" }) do
      options.opportunityEvidence[driveId]
        = options.opportunityEvidence[driveId] or {}
      for _, entity in ipairs(entities or {}) do
        local position = entity and options.positions[entity.id]
        if position and options.opportunityEvidence[driveId][entity.id] == nil then
          local evidence = DormantLifecycle.opportunityEvidence(
            entity, driveId, semantics, position)
          if evidence then
            options.opportunityEvidence[driveId][entity.id] = evidence
          end
        end
      end
    end
  end
  state.dormantCohorts = state.dormantCohorts or {}
  local cohort = DormantCohort.capture(mapId, entities,
    clockSample and clockSample.monotonicEcologyTime or 0, options)
  cohort.clockSource = clockSample and clockSample.source or "SIMULATION"
  cohort.dormant = true
  state.dormantCohorts[mapId] = cohort
  return cohort
end

function DormantLifecycle.catchUpBeforeMaterialization(state, mapId, clockSample)
  local cohort = state.dormantCohorts and state.dormantCohorts[mapId]
  if not cohort or cohort.dormant ~= true then return nil end
  if cohort.clockSource ~= clockSample.source then
    cohort.lastEcologyTime = clockSample.monotonicEcologyTime
    cohort.clockSource = clockSample.source
  end
  local result = DormantCohortSimulator.advance(cohort,
    entitiesById(state, mapId), clockSample.monotonicEcologyTime,
    { simulationTick = state.simulationTick })
  cohort.dormant = false
  return result
end

function DormantLifecycle.advanceLive(mapId, entities, clockSample, options)
  local cohort = DormantCohort.capture(mapId, entities,
    clockSample.monotonicEcologyTime - math.max(0, clockSample.elapsed or 0), options)
  cohort.clockSource = clockSample.source
  local byId = {}
  for _, entity in ipairs(entities or {}) do byId[entity.id] = entity end
  return DormantCohortSimulator.advance(cohort, byId,
    clockSample.monotonicEcologyTime)
end

function DormantLifecycle.setDiagnosticSink(sink)
  DormantCohortSimulator.setDiagnosticSink(sink)
end

function DormantLifecycle.opportunityEvidence(entity, driveId, semantics, position)
  if not entity or not semantics or not position then return false end
  local radius = math.max(semantics.width or 0, semantics.height or 0)
  local candidates
  if driveId == "THIRST" then
    candidates = WorldSemantics.findNearbyFeature(
      semantics, position, "WATER_ADJACENT", radius)
  elseif driveId == "HUNGER" then
    candidates = FoodOpportunities.findNearby(entity, {
      worldSemantics = semantics, position = position, mapId = semantics.mapId,
      needSearchRadius = radius
    }, 0)
  else
    return false
  end
  for _, candidate in ipairs(candidates) do
    local cellX, cellY = candidate.cellX or candidate.x, candidate.cellY or candidate.y
    local goal = SpatialGoal.position({ cellX = cellX, cellY = cellY }, {
      mapId = semantics.mapId, traversalMode = "WALK",
      source = "dormant:" .. driveId .. "_evidence"
    })
    local route = NavigationPlanner.plan(entity, semantics, position, goal, {
      maxDepth = math.max(12, radius * 2),
      maxExpansions = 2048,
      allowedModes = { WALK = true }
    })
    if route and route.reachedGoal == true then
      return { proven = true,
        opportunityType = candidate.opportunityType or "WATER_ADJACENT",
        provenance = candidate.provenance or "WORLD_SEMANTIC" }
    end
  end
  return false
end

function DormantLifecycle.reachableWaterEvidence(entity, semantics, position)
  return DormantLifecycle.opportunityEvidence(
    entity, "THIRST", semantics, position) ~= false
end

return DormantLifecycle