local DormantCohort = {}

local function copyPosition(position)
  if not position then return nil end
  return { cellX = position.cellX, cellY = position.cellY }
end

local function distance(left, right)
  if not left or not right then return nil end
  return math.max(math.abs(left.cellX - right.cellX),
    math.abs(left.cellY - right.cellY))
end

function DormantCohort.capture(mapId, entities, ecologyTime, options)
  options = options or {}
  local members, snapshots = {}, {}
  local positionIndex = {}
  for _, entity in ipairs(entities or {}) do
    if entity and entity.id then
      members[#members + 1] = entity.id
      local position = options.positions and options.positions[entity.id] or nil
      snapshots[entity.id] = {
        lastPosition = copyPosition(position),
        region = entity.home and entity.home.zoneId or nil,
        groupId = entity.groupId,
        state = entity.runtimeState and entity.runtimeState.state or "SETTLED",
        closeContacts = {}
      }
      if position then
        local key = tostring(position.cellX) .. "," .. tostring(position.cellY)
        positionIndex[key] = positionIndex[key] or {}
        positionIndex[key][#positionIndex[key] + 1] = entity.id
      end
    end
  end
  table.sort(members, function(left, right) return tostring(left) < tostring(right) end)
  local contactRadius = options.contactRadius or 2
  for _, observerId in ipairs(members) do
    local observer = snapshots[observerId]
    if observer.lastPosition then
      for offsetY = -contactRadius, contactRadius do
        for offsetX = -contactRadius, contactRadius do
          local key = tostring(observer.lastPosition.cellX + offsetX) .. ","
            .. tostring(observer.lastPosition.cellY + offsetY)
          for _, subjectId in ipairs(positionIndex[key] or {}) do
            if subjectId ~= observerId then
              local separation = distance(observer.lastPosition,
                snapshots[subjectId].lastPosition)
              if separation and separation <= contactRadius then
                observer.closeContacts[#observer.closeContacts + 1] = subjectId
              end
            end
          end
        end
      end
    end
    table.sort(observer.closeContacts,
      function(left, right) return tostring(left) < tostring(right) end)
  end
  local opportunityEvidence = options.opportunityEvidence or {}
  if options.reachableWater ~= nil then
    opportunityEvidence.THIRST = opportunityEvidence.THIRST or {}
    for _, entityId in ipairs(members) do
      if opportunityEvidence.THIRST[entityId] == nil then
        opportunityEvidence.THIRST[entityId] = {
          proven = options.reachableWater == true,
          opportunityType = "WATER_ADJACENT",
          provenance = "LEGACY_REACHABLE_WATER"
        }
      end
    end
  end
  return {
    id = tostring(mapId) .. ":" .. tostring(math.floor(ecologyTime or 0)),
    mapId = mapId,
    memberIds = members,
    memberSnapshots = snapshots,
    lastEcologyTime = ecologyTime or 0,
    environment = {
      opportunityEvidence = opportunityEvidence
    },
    catchUpCount = 0
  }
end

function DormantCohort.inspect(cohort, now)
  local evidence = cohort and cohort.environment
    and cohort.environment.opportunityEvidence or {}
  local proven = 0
  for _, byEntity in pairs(evidence) do
    for _, record in pairs(byEntity) do
      if record and record.proven == true then proven = proven + 1 end
    end
  end
  return string.format(
    "DORMANT COHORT map=%s members=%d lastSimulated=%.0f elapsed=%.0f catches=%d opportunities=%d",
    tostring(cohort and cohort.mapId or "none"),
    #(cohort and cohort.memberIds or {}),
    cohort and cohort.lastEcologyTime or 0,
    math.max(0, (now or 0) - (cohort and cohort.lastEcologyTime or 0)),
    cohort and cohort.catchUpCount or 0, proven)
end

return DormantCohort