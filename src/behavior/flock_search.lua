local SpeciesEcology = require("src.species.species_ecology")

local FlockSearch = {}

local DEFAULT_GRACE_TICKS = 90
local DEFAULT_PRESSURE_RAMP_TICKS = 180
local DEFAULT_LAST_SEEN_TICKS = 600
local DEFAULT_SIGNAL_RANGE = 16
local DEFAULT_SIGNAL_REFRESH_TICKS = 120
local DEFAULT_SIGNAL_DISTANCE = 6
local DEFAULT_DESIRED_GROUP_SIZE = 2
local DEFAULT_REASSEMBLY_COOLDOWN_TICKS = 30
local DEFAULT_REASSEMBLY_RAMP_TICKS = 180

local function clamp(value, minValue, maxValue)
  return math.max(minValue, math.min(maxValue, value))
end

local function familyId(entity)
  return entity and ((entity.ecology and entity.ecology.family) or entity.familyId) or nil
end

local function distanceBetween(left, right)
  if not left or not right then
    return nil
  end
  return math.max(math.abs(left.cellX - right.cellX), math.abs(left.cellY - right.cellY))
end

local function copyPosition(position)
  return position and { cellX = position.cellX, cellY = position.cellY } or nil
end

local function cardinalCue(origin, target, distance)
  if not origin or not target then
    return nil, nil
  end
  local dx = target.cellX - origin.cellX
  local dy = target.cellY - origin.cellY
  if dx == 0 and dy == 0 then
    return nil, nil
  end
  local direction
  if math.abs(dx) >= math.abs(dy) then
    direction = dx < 0 and "LEFT" or "RIGHT"
  else
    direction = dy < 0 and "UP" or "DOWN"
  end
  local cueDistance = distance or DEFAULT_SIGNAL_DISTANCE
  return direction, {
    cellX = origin.cellX + (direction == "LEFT" and -cueDistance or direction == "RIGHT" and cueDistance or 0),
    cellY = origin.cellY + (direction == "UP" and -cueDistance or direction == "DOWN" and cueDistance or 0)
  }
end

local function candidateScore(entity, candidate)
  local relationship = entity.relationships and entity.relationships[candidate.id] or {}
  return (relationship.trust or 0) * 0.3
    + (relationship.affinity or 0) * 0.3
    + (relationship.familiarity or 0) * 0.2
    - (candidate.distance or 0) * 0.25
end

local function preferredSourceTier(candidates)
  local recent = {}
  local coarse = {}
  for _, candidate in ipairs(candidates) do
    if candidate.cueSource == "perceived" or candidate.cueSource == "last_seen" then
      recent[#recent + 1] = candidate
    else
      coarse[#coarse + 1] = candidate
    end
  end
  return #recent > 0 and recent or coarse
end

local function chooseTieredCandidate(entity, candidates)
  local ownFamily = familyId(entity)
  local preferred = {}
  local fallback = {}
  for _, candidate in ipairs(candidates) do
    if candidate.familyId ~= nil and candidate.familyId == ownFamily then
      preferred[#preferred + 1] = candidate
    else
      fallback[#fallback + 1] = candidate
    end
  end
  local familyTier = #preferred > 0 and preferred or fallback
  local tier = preferredSourceTier(familyTier)
  local best, bestScore = nil, -math.huge
  for _, candidate in ipairs(tier) do
    local score = candidateScore(entity, candidate)
    if score > bestScore or (score == bestScore and tostring(candidate.id) < tostring(best and best.id or "~")) then
      best = candidate
      bestScore = score
    end
  end
  return best
end

function FlockSearch.update(entity, position, activeCandidates, nowTick, options)
  local settings = options or {}
  local tick = nowTick or 0
  entity.runtimeState = entity.runtimeState or {}
  local runtime = entity.runtimeState
  runtime.flockSearch = runtime.flockSearch or { sightings = {}, signals = {} }
  local search = runtime.flockSearch
  search.sightings = search.sightings or {}
  search.signals = search.signals or {}

  local perceptionRadius = settings.perceptionRadius or 5
  local lastSeenTicks = settings.lastSeenTicks or DEFAULT_LAST_SEEN_TICKS
  local signalRange = settings.signalRange or DEFAULT_SIGNAL_RANGE
  local signalRefreshTicks = settings.signalRefreshTicks or DEFAULT_SIGNAL_REFRESH_TICKS
  local signalDistance = settings.signalDistance or DEFAULT_SIGNAL_DISTANCE
  local nearbySameSpecies = 0
  local nearbyFamily = 0
  local viable = {}
  local considered = {}
  local ownFamily = familyId(entity)

  for _, record in ipairs(activeCandidates or {}) do
    local other = record.entity or record
    if other and other.id and other.id ~= entity.id and other.species == entity.species then
      considered[other.id] = true
      local otherPosition = record.position
      local distance = record.distance or distanceBetween(position, otherPosition)
      local perceived = record.perceived == true or (distance ~= nil and distance <= perceptionRadius)
      local otherFamily = familyId(other)
      if perceived and otherPosition then
        nearbySameSpecies = nearbySameSpecies + 1
        if ownFamily ~= nil and otherFamily == ownFamily then
          nearbyFamily = nearbyFamily + 1
        end
        search.sightings[other.id] = {
          tick = tick,
          position = copyPosition(otherPosition),
          familyId = otherFamily,
          species = other.species
        }
        search.signals[other.id] = nil
        viable[#viable + 1] = {
          id = other.id,
          familyId = otherFamily,
          cueSource = "perceived",
          cuePosition = copyPosition(otherPosition),
          distance = distance
        }
      else
        local sighting = search.sightings[other.id]
        if sighting and tick - (sighting.tick or 0) <= lastSeenTicks and sighting.position then
          viable[#viable + 1] = {
            id = other.id,
            familyId = otherFamily,
            cueSource = "last_seen",
            cuePosition = copyPosition(sighting.position),
            distance = distanceBetween(position, sighting.position)
          }
        elseif distance ~= nil and distance <= signalRange and otherPosition then
          local signal = search.signals[other.id]
          if not signal or tick >= (signal.refreshTick or 0) then
            local cueDirection, cuePosition = cardinalCue(position, otherPosition, signalDistance)
            signal = cuePosition and {
              direction = cueDirection,
              position = cuePosition,
              refreshTick = tick + signalRefreshTicks
            } or nil
            search.signals[other.id] = signal
          end
          if signal and signal.position then
            viable[#viable + 1] = {
              id = other.id,
              familyId = otherFamily,
              cueSource = "social_signal",
              cueDirection = signal.direction,
              cuePosition = copyPosition(signal.position),
              distance = distance
            }
          end
        end
      end
    end
  end

  for targetId, sighting in pairs(search.sightings) do
    if not considered[targetId]
      and sighting.species == entity.species
      and tick - (sighting.tick or 0) <= lastSeenTicks
      and sighting.position then
      viable[#viable + 1] = {
        id = targetId,
        familyId = sighting.familyId,
        cueSource = "last_seen",
        cuePosition = copyPosition(sighting.position),
        distance = distanceBetween(position, sighting.position)
      }
    end
  end

  if nearbySameSpecies > 0 then
    search.lastCompatibleSeenTick = tick
    search.isolationSinceTick = nil
  else
    search.isolationSinceTick = search.isolationSinceTick or tick
  end
  if nearbyFamily > 0 then
    search.familySeparatedSinceTick = nil
  else
    search.familySeparatedSinceTick = search.familySeparatedSinceTick or tick
  end

  local graceTicks = settings.graceTicks or DEFAULT_GRACE_TICKS
  local rampTicks = settings.pressureRampTicks or DEFAULT_PRESSURE_RAMP_TICKS
  local isolatedElapsed = search.isolationSinceTick and tick - search.isolationSinceTick or 0
  local familyElapsed = search.familySeparatedSinceTick and tick - search.familySeparatedSinceTick or 0
  local isolationPressure = nearbySameSpecies == 0
    and clamp((isolatedElapsed - graceTicks) / rampTicks, 0, 1)
    or 0
  local familyPressure = nearbyFamily == 0
    and clamp((familyElapsed - graceTicks) / rampTicks, 0, 1)
    or 0
  local speciesEcology = SpeciesEcology.getResolved(entity.species)
  local desiredGroupSize = settings.desiredGroupSize
    or speciesEcology.social.desiredGroupSize or DEFAULT_DESIRED_GROUP_SIZE
  local groupDeficit = clamp((desiredGroupSize - nearbySameSpecies) / desiredGroupSize, 0, 1)
  local independence = entity.rawStats and entity.rawStats.independence or 0.5
  local sociability = entity.temperament and entity.temperament.sociability or 0
  local socialModifier = speciesEcology.social.modifier
  local flocking = clamp(sociability * socialModifier, 0, 1)
  local dependence = clamp(1 - independence, 0, 1)
  local calmElapsed = runtime.lastFleeEndTick and math.max(0, tick - runtime.lastFleeEndTick) or 0
  local activeAlarm = runtime.state == "FLEE" or runtime.directThreatId ~= nil
    or (runtime.fearSocial or 0) >= 0.12
  local reassemblyCooldown = settings.reassemblyCooldownTicks or DEFAULT_REASSEMBLY_COOLDOWN_TICKS
  local reassemblyRampTicks = settings.reassemblyRampTicks or DEFAULT_REASSEMBLY_RAMP_TICKS
  local reassemblyPressure = runtime.lastFleeEndTick and not activeAlarm and nearbySameSpecies == 0
    and clamp((calmElapsed - reassemblyCooldown) / reassemblyRampTicks, 0, 1)
    or 0
  local reunionWeight = nearbySameSpecies > 0 and 0.3 or 0.2
  local pressure = isolationPressure * groupDeficit + familyPressure * reunionWeight
    + reassemblyPressure * groupDeficit * 0.65
  local utility = clamp(120 * flocking * dependence * pressure, 0, 120)
  local selected = chooseTieredCandidate(entity, viable)

  search.isolationPressure = isolationPressure
  search.familyPressure = familyPressure
  search.nearbySameSpecies = nearbySameSpecies
  search.nearbyFamily = nearbyFamily
  search.postFleeCalmTicks = calmElapsed
  search.reassemblyPressure = reassemblyPressure
  search.cueSource = selected and selected.cueSource or "search"
  search.cueDirection = selected and selected.cueDirection or nil
  search.targetEntityId = selected and selected.id or nil
  search.cuePosition = selected and copyPosition(selected.cuePosition) or nil

  return {
    utility = utility,
    isolationPressure = isolationPressure,
    familyPressure = familyPressure,
    groupDeficit = groupDeficit,
    independence = independence,
    sociability = sociability,
    dependence = dependence,
    activeAlarm = activeAlarm,
    nearbySameSpecies = nearbySameSpecies,
    nearbyFamily = nearbyFamily,
    postFleeCalmTicks = calmElapsed,
    reassemblyPressure = reassemblyPressure,
    reacquired = nearbySameSpecies > 0,
    cueSource = search.cueSource,
    cueDirection = search.cueDirection,
    targetEntityId = search.targetEntityId,
    cuePosition = copyPosition(search.cuePosition)
  }
end

function FlockSearch.consumeLastSeen(entity, targetEntityId)
  local search = entity and entity.runtimeState and entity.runtimeState.flockSearch
  if not search or not targetEntityId then
    return false
  end
  search.sightings[targetEntityId] = nil
  if search.targetEntityId == targetEntityId then
    search.targetEntityId = nil
    search.cuePosition = nil
    search.cueDirection = nil
    search.cueSource = "search"
  end
  return true
end

return FlockSearch