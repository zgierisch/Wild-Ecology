local LocomotionPolicy = {}

local LOCOMOTOR = {
  TARGET = true,
  INVESTIGATE = true,
  APPROACH = true,
  SEEK_FLOCK = true,
  SATISFY_NEED = true,
  RETURN_HOME = true,
  REST = true
}

function LocomotionPolicy.decide(entity, behavior, context, tick, stepCompleted)
  local runtime = entity.runtimeState
  if context.locomotionPacing ~= true then
    runtime.locomotionDecision = "MOVE_NOW"
    runtime.locomotionDecisionReason = "PACING_DISABLED"
    return true, "PACING_DISABLED"
  end
  if behavior == "FLEE" then
    runtime.locomotionPolicy = nil
    runtime.locomotionDecision = "MOVE_NOW"
    runtime.locomotionDecisionReason = "FLEE_URGENCY"
    return true, "FLEE_URGENCY"
  end
  if not LOCOMOTOR[behavior] then
    runtime.locomotionPolicy = nil
    runtime.locomotionDecision = "WAIT"
    runtime.locomotionDecisionReason = "NON_LOCOMOTOR_BEHAVIOR"
    return false, "NON_LOCOMOTOR_BEHAVIOR"
  end
  if behavior == "REST" and runtime.restTraveling ~= true then
    runtime.locomotionPolicy = nil
    runtime.locomotionDecision = "WAIT"
    runtime.locomotionDecisionReason = "REST_SITE_REACHED"
    return false, "REST_SITE_REACHED"
  end
  runtime.locomotionPolicy = {
    behavior = behavior,
    style = "CONTINUOUS",
    lastEvaluatedTick = tick,
    stepCompleted = stepCompleted == true
  }
  runtime.locomotionDecision = "MOVE_NOW"
  runtime.locomotionDecisionReason = "COHERENT_EXECUTION"
  return true, "COHERENT_EXECUTION"
end

function LocomotionPolicy.defaults()
  return { style = "CONTINUOUS", locomotorBehaviors = LOCOMOTOR }
end

return LocomotionPolicy