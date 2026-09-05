local TelemetryPolicy = {}

local CALM_EPSILON = 0.005

function TelemetryPolicy.fleeRouteSemantic(execution)
  local fleeExecution = execution or {}
  local planningState = fleeExecution.planningState or "none"
  local congestionState = planningState == "PLAN_BLOCKED_UNCHANGED"
    and "PERSISTENT_CONGESTION" or "CLEAR"
  local suspensionState = fleeExecution.routeSuspended == true
    and "SUSPENDED" or "ACTIVE"
  local lifecycleState = fleeExecution.route and "ESTABLISHED"
    or fleeExecution.routeInvalidationReason == "ROUTE_COMPLETE" and "COMPLETED"
    or fleeExecution.routeInvalidationReason and "INVALIDATED"
    or congestionState == "PERSISTENT_CONGESTION" and "CONGESTED"
    or "LOCAL"
  local endpoint = fleeExecution.escapeEndpoint
  local semantic = {
    lifecycleState = lifecycleState,
    establishedTick = fleeExecution.routeEstablishedTick,
    mode = fleeExecution.fleeMode or "NORMAL",
    threatSourceId = fleeExecution.routeThreatSourceId,
    referenceKind = fleeExecution.routeThreatReferenceKind,
    invalidationReason = fleeExecution.routeInvalidationReason,
    suspensionState = suspensionState,
    congestionState = congestionState,
    endpointX = endpoint and endpoint.cellX or nil,
    endpointY = endpoint and endpoint.cellY or nil
  }
  semantic.signature = table.concat({
    tostring(semantic.lifecycleState),
    tostring(semantic.establishedTick or "none"),
    tostring(semantic.mode),
    tostring(semantic.threatSourceId or "none"),
    tostring(semantic.referenceKind or "none"),
    tostring(semantic.invalidationReason or "none"),
    tostring(semantic.suspensionState),
    tostring(semantic.congestionState),
    tostring(semantic.endpointX or "none"),
    tostring(semantic.endpointY or "none")
  }, ":")
  return semantic
end

function TelemetryPolicy.fleeRouteEvent(previous, current)
  local event = current.lifecycleState == "ESTABLISHED" and "ROUTE_ESTABLISHED"
    or current.lifecycleState == "COMPLETED" and "ROUTE_COMPLETED"
    or current.lifecycleState == "INVALIDATED" and "ROUTE_INVALIDATED"
    or current.lifecycleState == "CONGESTED" and "PERSISTENT_CONGESTION_ENTERED"
    or "ROUTE_STATE_CHANGED"
  if not previous then return event end
  if previous.suspensionState ~= current.suspensionState then
    return current.suspensionState == "SUSPENDED" and "ROUTE_SUSPENDED" or "ROUTE_RESUMED"
  end
  if previous.congestionState ~= current.congestionState then
    return current.congestionState == "PERSISTENT_CONGESTION"
      and "PERSISTENT_CONGESTION_ENTERED" or "PERSISTENT_CONGESTION_RESOLVED"
  end
  if previous.threatSourceId ~= current.threatSourceId then
    return "THREAT_SOURCE_CHANGED"
  end
  if previous.referenceKind ~= current.referenceKind then
    return "ESCAPE_REFERENCE_MODE_CHANGED"
  end
  if previous.establishedTick ~= current.establishedTick then
    return "MEANINGFUL_REPLAN"
  end
  if previous.endpointX ~= current.endpointX or previous.endpointY ~= current.endpointY then
    return "MEANINGFUL_REPLAN"
  end
  return event
end

function TelemetryPolicy.isCalmFear(runtimeState)
  local runtime = runtimeState or {}
  return (runtime.fearCurrent or 0) <= CALM_EPSILON
    and (runtime.fearDirect or 0) <= CALM_EPSILON
    and (runtime.fearSocial or 0) <= CALM_EPSILON
    and runtime.state ~= "FLEE"
end

function TelemetryPolicy.suppressFearNormal(event, runtimeState, trace)
  if trace or not TelemetryPolicy.isCalmFear(runtimeState) then return false end
  return event == "SOCIAL_SOURCE_BAND_CHANGED"
    or event == "GROUNDEDNESS_DELTA"
    or event == "STRONGEST_SOURCE_CHANGED"
end

return TelemetryPolicy
