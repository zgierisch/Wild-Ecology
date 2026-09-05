local ActivityProfiles = {}

local profiles = {
  DIURNAL = {
    id = "DIURNAL", baseline = 0.12, activityAmplitude = 0.88,
    restAmplitude = 0.92, transitionWidth = 0.12,
    peaks = { { phase = 0.50, width = 0.34 } }
  },
  NOCTURNAL = {
    id = "NOCTURNAL", baseline = 0.12, activityAmplitude = 0.88,
    restAmplitude = 0.92, transitionWidth = 0.12,
    peaks = { { phase = 0.00, width = 0.34 } }
  },
  CREPUSCULAR = {
    id = "CREPUSCULAR", baseline = 0.10, activityAmplitude = 0.90,
    restAmplitude = 0.80, transitionWidth = 0.08,
    peaks = {
      { phase = 0.25, width = 0.12 },
      { phase = 0.75, width = 0.12 }
    }
  },
  FLEXIBLE = {
    id = "FLEXIBLE", baseline = 0.58, activityAmplitude = 0.18,
    restAmplitude = 0.35, transitionWidth = 0.20,
    peaks = { { phase = 0.50, width = 0.45 } }
  },
  WEAK_CIRCADIAN = {
    id = "WEAK_CIRCADIAN", baseline = 0.48, activityAmplitude = 0.16,
    restAmplitude = 0.18, transitionWidth = 0.20,
    peaks = { { phase = 0.50, width = 0.38 } }
  }
}

function ActivityProfiles.get(id)
  return profiles[id] or profiles.FLEXIBLE
end

function ActivityProfiles.register(id, profile)
  assert(type(id) == "string" and id ~= "", "activity profile id is required")
  assert(type(profile) == "table", "activity profile is required")
  profile.id = id
  profiles[id] = profile
  return profile
end

function ActivityProfiles.each()
  local ids = {}
  for id in pairs(profiles) do ids[#ids + 1] = id end
  table.sort(ids)
  local index = 0
  return function()
    index = index + 1
    local id = ids[index]
    if id then return id, profiles[id] end
  end
end

return ActivityProfiles