local Fear = require("src.behavior.fear")
local TelemetryPolicy = require("src.debug.telemetry_policy")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected)
      .. ", got " .. tostring(actual))
  end
end

local function assertTrue(value, message)
  if not value then error(message or "assertion failed") end
end

local function oldRouteSignature(execution)
  return table.concat({
    tostring(execution.routeEstablishedTick or "none"),
    tostring(execution.routeThreatSourceId or "none"),
    tostring(execution.routeThreatReferenceKind or "none"),
    tostring(execution.routeCommitment == true),
    tostring(execution.routeTemporaryRegressionActive == true),
    tostring(execution.routeRegressionDebt or 0),
    tostring(execution.routeRevalidated == true),
    tostring(execution.routeRevalidationReason or "none"),
    tostring(execution.routeInvalidationReason or "none"),
    tostring(execution.routeInvalidationTick or "none")
  }, ":")
end

local function normalRouteLine(semantic, event, suppressed)
  return string.format(
    "[behavior] FLEE route actor=stable-route event=%s suppressedUnchanged=%d lifecycle=%s mode=%s routeEstablishedTick=%s threat=%s reference=%s invalidation=%s suspension=%s congestion=%s endpoint=%s,%s\n",
    event, suppressed, semantic.lifecycleState, semantic.mode,
    tostring(semantic.establishedTick or "none"),
    tostring(semantic.threatSourceId or "none"),
    tostring(semantic.referenceKind or "none"),
    tostring(semantic.invalidationReason or "none"),
    semantic.suspensionState, semantic.congestionState,
    tostring(semantic.endpointX or "none"), tostring(semantic.endpointY or "none"))
end

local function detailedRouteLine(execution)
  local endpoint = execution.escapeEndpoint or {}
  return string.format(
    "[behavior] FLEE route actor=stable-route routeThreatSourceId=%s routeThreatReferenceKind=%s routeEstablishedTick=%s routeTemporaryRegressionActive=%s routeRegressionDebt=%s routeExpectedSource=none,none routeNextAction=RIGHT routeEndpoint=%s,%s routeEndpointThreatDistance=4 currentThreatSourceId=%s sameThreatSource=true routeRevalidated=%s routeRevalidationReason=%s routeInvalidated=false routeInvalidationReason=none localGreedyCandidate=LEFT localGreedySuppressedByRoute=true\n",
    tostring(execution.routeThreatSourceId or "none"),
    tostring(execution.routeThreatReferenceKind or "none"),
    tostring(execution.routeEstablishedTick or "none"),
    tostring(execution.routeTemporaryRegressionActive == true),
    tostring(execution.routeRegressionDebt or 0),
    tostring(endpoint.cellX or "none"), tostring(endpoint.cellY or "none"),
    tostring(execution.routeThreatSourceId or "none"),
    tostring(execution.routeRevalidated == true),
    tostring(execution.routeRevalidationReason or "none"))
end

local routeExecution = {
  route = { actions = {}, index = 1 },
  routeEstablishedTick = 1391,
  fleeMode = "ESCAPE_ROUTE",
  routeThreatSourceId = "player",
  routeThreatReferenceKind = "CURRENT_THREAT_POSITION",
  routeCommitment = true,
  routeTemporaryRegressionActive = false,
  routeRegressionDebt = 0,
  routeRevalidated = false,
  routeRevalidationReason = "PENDING",
  planningState = "FOLLOWING_ROUTE",
  routeSuspended = false,
  escapeEndpoint = { cellX = 18, cellY = 9 }
}
local oldSignature, newSignature, previousSemantic
local oldRecords, oldBytes, normalRecords, normalBytes = 0, 0, 0, 0
local suppressed, traceRecords, traceBytes = 0, 0, 0
for tick = 1, 300 do
  routeExecution.route.index = tick % 4 + 1
  routeExecution.routeRevalidated = tick % 2 == 0
  routeExecution.routeRevalidationReason = routeExecution.routeRevalidated
    and "MATCHED_CURRENT_SOURCE" or "PENDING"
  routeExecution.routeRegressionDebt = tick % 3 == 0 and 1 or 0
  local nextOldSignature = oldRouteSignature(routeExecution)
  if nextOldSignature ~= oldSignature then
    oldRecords = oldRecords + 1
    oldBytes = oldBytes + #detailedRouteLine(routeExecution)
  end
  oldSignature = nextOldSignature

  local semantic = TelemetryPolicy.fleeRouteSemantic(routeExecution)
  if semantic.signature ~= newSignature then
    local event = TelemetryPolicy.fleeRouteEvent(previousSemantic, semantic)
    local line = normalRouteLine(semantic, event, suppressed)
    normalRecords = normalRecords + 1
    normalBytes = normalBytes + #line
    suppressed = 0
    newSignature = semantic.signature
    previousSemantic = semantic
  else
    suppressed = suppressed + 1
  end
  traceRecords = traceRecords + 1
  traceBytes = traceBytes + #detailedRouteLine(routeExecution)
end
assertEquals(oldRecords, 300,
  "the prior bookkeeping signature should reproduce per-execution duplicate emission")
assertEquals(normalRecords, 1,
  "one semantically stable route should emit one NORMAL establishment")
assertEquals(suppressed, 299,
  "unchanged stable-route observations should be aggregated")
assertEquals(traceRecords, 300,
  "TRACE should retain every stable-route execution observation")

local function fearLine(event, runtime)
  return string.format(
    "[behavior] Fear actor=calm-social event=%s current=%.2f direct=%.2f social=%.2f threat=%s sources=%s strongest=%s socialOnly=%s\n",
    tostring(event), runtime.fearCurrent or 0, runtime.fearDirect or 0,
    runtime.fearSocial or 0, tostring(runtime.directThreatId or "none"),
    tostring(runtime.nearbyFearSources or 0),
    tostring(runtime.strongestFearSource or "none"),
    tostring((runtime.fearDirect or 0) < 0.05 and (runtime.fearSocial or 0) > 0))
end

local calmActors = {}
for index = 1, 4 do
  calmActors[index] = {
    state = "IDLE", fearCurrent = 0, fearDirect = 0, fearSocial = 0,
    nearbyFearSources = 0, alarmGroundedness = 0
  }
  Fear.diagnosticEvent(calmActors[index], false)
end
local fearBeforeRecords, fearBeforeBytes = 0, 0
local fearAfterRecords, fearAfterBytes, calmSuppressed = 0, 0, 0
local function observeFear(runtime)
  local event = Fear.diagnosticEvent(runtime, false)
  if not event then return nil end
  local line = fearLine(event, runtime)
  fearBeforeRecords = fearBeforeRecords + 1
  fearBeforeBytes = fearBeforeBytes + #line
  if TelemetryPolicy.suppressFearNormal(event, runtime, false) then
    calmSuppressed = calmSuppressed + 1
  else
    fearAfterRecords = fearAfterRecords + 1
    fearAfterBytes = fearAfterBytes + #line
  end
  return event
end

for tick = 1, 50 do
  for index, actor in ipairs(calmActors) do
    actor.nearbyFearSources = (tick + index) % 2
    actor.alarmGroundedness = (tick + index) % 3 == 0 and 0.2 or 0
    observeFear(actor)
  end
end
assertEquals(fearAfterRecords, 0,
  "fully calm social-source and groundedness bookkeeping should stay out of NORMAL")

local calm = calmActors[1]
calm.fearCurrent = 0.24
calm.fearSocial = 0.24
calm.nearbyFearSources = 1
calm.strongestFearSource = "alarm-a"
local fearEntryEvent = observeFear(calm)
assertTrue(fearEntryEvent ~= nil and fearAfterRecords == 1,
  "meaningful social fear entry should remain visible in NORMAL")
local socialOnlyLine = fearLine(fearEntryEvent, calm)
assertTrue(socialOnlyLine:find("socialOnly=true", 1, true) ~= nil
    and socialOnlyLine:find("threat=none", 1, true) ~= nil,
  "social-only Fear telemetry must remain targetless and explicit")

calm.state = "FLEE"
local fleeEvent = observeFear(calm)
assertEquals(fleeEvent, "FLEE_STATE_CHANGED",
  "social-only transition into FLEE should remain visible")
assertEquals(TelemetryPolicy.suppressFearNormal(fleeEvent, calm, false), false,
  "FLEE state transitions must never be calm-bookkeeping suppressed")

calm.state = "IDLE"
calm.fearCurrent = 0
calm.fearSocial = 0
calm.nearbyFearSources = 0
calm.strongestFearSource = nil
local calmEvent = observeFear(calm)
assertTrue(calmEvent ~= nil and fearAfterRecords >= 3,
  "fear resolving completely should remain visible in NORMAL")

local recordsAfterCalm = fearAfterRecords
for tick = 1, 20 do
  for index, actor in ipairs(calmActors) do
    actor.nearbyFearSources = (tick + index) % 2
    actor.alarmGroundedness = (tick + index) % 2 == 0 and 0.3 or 0
    observeFear(actor)
  end
end
assertEquals(fearAfterRecords, recordsAfterCalm,
  "bookkeeping after calm is established should be suppressed again")
assertTrue(calmSuppressed >= 190,
  "the workload should exercise substantial calm bookkeeping suppression")
assertEquals(TelemetryPolicy.suppressFearNormal("DIRECT_THREAT_CHANGED", calm, false), false,
  "direct threat changes must remain visible while values are calm")
assertEquals(TelemetryPolicy.suppressFearNormal("FEAR_BAND_CHANGED", calm, false), false,
  "fear band transitions must remain visible while values reach calm")

local traceCalm = {
  state = "IDLE", fearCurrent = 0, fearDirect = 0, fearSocial = 0
}
local calmTraceRecords, calmTraceBytes = 0, 0
for tick = 1, 200 do
  traceCalm.nearbyFearSources = tick % 2
  traceCalm.alarmGroundedness = tick % 2 == 0 and 0.3 or 0
  local event = Fear.diagnosticEvent(traceCalm, true)
  assertEquals(TelemetryPolicy.suppressFearNormal(event, traceCalm, true), false,
    "TRACE must never suppress calm bookkeeping")
  calmTraceRecords = calmTraceRecords + 1
  calmTraceBytes = calmTraceBytes + #fearLine(event, traceCalm)
end
assertEquals(calmTraceRecords, 200,
  "TRACE should retain every calm bookkeeping integration")

local socialRoute = TelemetryPolicy.fleeRouteSemantic({
  route = { actions = {}, index = 1 },
  routeEstablishedTick = 77,
  fleeMode = "ESCAPE_ROUTE",
  routeThreatSourceId = nil,
  routeThreatReferenceKind = "SOCIAL_ESCAPE_VECTOR",
  planningState = "FOLLOWING_ROUTE"
})
assertEquals(socialRoute.threatSourceId, nil,
  "social-only route telemetry must not invent hidden threat identity")
assertEquals(socialRoute.referenceKind, "SOCIAL_ESCAPE_VECTOR",
  "NORMAL route telemetry must retain social escape reference provenance")

local routeBase = {
  route = { actions = {}, index = 1 }, routeEstablishedTick = 10,
  fleeMode = "ESCAPE_ROUTE", routeThreatSourceId = "player",
  routeThreatReferenceKind = "CURRENT_THREAT_POSITION",
  planningState = "FOLLOWING_ROUTE"
}
local established = TelemetryPolicy.fleeRouteSemantic(routeBase)
assertEquals(TelemetryPolicy.fleeRouteEvent(nil, established), "ROUTE_ESTABLISHED",
  "NORMAL should classify route establishment")
routeBase.routeSuspended = true
routeBase.planningState = "WAITING_FOR_ROUTE_CELL"
local suspendedRoute = TelemetryPolicy.fleeRouteSemantic(routeBase)
assertEquals(TelemetryPolicy.fleeRouteEvent(established, suspendedRoute), "ROUTE_SUSPENDED",
  "NORMAL should classify route suspension")
routeBase.routeSuspended = false
routeBase.planningState = "FOLLOWING_ROUTE"
local resumedRoute = TelemetryPolicy.fleeRouteSemantic(routeBase)
assertEquals(TelemetryPolicy.fleeRouteEvent(suspendedRoute, resumedRoute), "ROUTE_RESUMED",
  "NORMAL should classify route resumption")
routeBase.route = nil
routeBase.planningState = "PLAN_BLOCKED_UNCHANGED"
local congestedRoute = TelemetryPolicy.fleeRouteSemantic(routeBase)
assertEquals(TelemetryPolicy.fleeRouteEvent(resumedRoute, congestedRoute),
  "PERSISTENT_CONGESTION_ENTERED", "NORMAL should classify persistent congestion")
routeBase.planningState = "LOCAL_STEERING"
local resolvedRoute = TelemetryPolicy.fleeRouteSemantic(routeBase)
assertEquals(TelemetryPolicy.fleeRouteEvent(congestedRoute, resolvedRoute),
  "PERSISTENT_CONGESTION_RESOLVED", "NORMAL should classify congestion resolution")
routeBase.routeInvalidationReason = "THREAT_MOVED"
local invalidatedRoute = TelemetryPolicy.fleeRouteSemantic(routeBase)
assertEquals(TelemetryPolicy.fleeRouteEvent(resolvedRoute, invalidatedRoute),
  "ROUTE_INVALIDATED", "NORMAL should classify route invalidation")
routeBase.routeInvalidationReason = "ROUTE_COMPLETE"
local completedRoute = TelemetryPolicy.fleeRouteSemantic(routeBase)
assertEquals(TelemetryPolicy.fleeRouteEvent(invalidatedRoute, completedRoute),
  "ROUTE_COMPLETED", "NORMAL should classify route completion")

print(string.format(
  "STABLE_ROUTE oldNormalRecords=%d oldNormalBytes=%d newNormalRecords=%d newNormalBytes=%d traceRecords=%d traceBytes=%d suppressed=%d",
  oldRecords, oldBytes, normalRecords, normalBytes, traceRecords, traceBytes, suppressed))
print(string.format(
  "CALM_BOOKKEEPING oldNormalRecords=%d oldNormalBytes=%d newNormalRecords=%d newNormalBytes=%d suppressed=%d traceRecords=%d traceBytes=%d",
  fearBeforeRecords, fearBeforeBytes, fearAfterRecords, fearAfterBytes,
  calmSuppressed, calmTraceRecords, calmTraceBytes))

return true
