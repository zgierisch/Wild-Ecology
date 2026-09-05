local Archetypes = {
  flocking_bird = {
    socialFearSusceptibility = 0.85,
    alarmBroadcastStrength = 1.0,
    conspecificAlarmSensitivity = 1.0,
    heterospecificAlarmSensitivity = 0.6
  },
  small_forager = {
    socialFearSusceptibility = 0.45,
    alarmBroadcastStrength = 0.8,
    conspecificAlarmSensitivity = 0.9,
    heterospecificAlarmSensitivity = 0.55
  },
  solitary = {
    socialFearSusceptibility = 0.25,
    alarmBroadcastStrength = 0.65,
    conspecificAlarmSensitivity = 0.65,
    heterospecificAlarmSensitivity = 0.4
  },
  small_skittish_forager = {
    baseBoldness = 0.2,
    baseSociability = 0.6,
    baseAggression = 0.1,
    socialFearSusceptibility = 0.7,
    alarmBroadcastStrength = 0.9,
    conspecificAlarmSensitivity = 0.85,
    heterospecificAlarmSensitivity = 0.55
  },
  sheltered_grazer = {
    socialFearSusceptibility = 0.75,
    alarmBroadcastStrength = 0.7,
    conspecificAlarmSensitivity = 0.9,
    heterospecificAlarmSensitivity = 0.5
  },
  cave_flyer = {
    socialFearSusceptibility = 0.8,
    alarmBroadcastStrength = 0.9,
    conspecificAlarmSensitivity = 0.95,
    heterospecificAlarmSensitivity = 0.45
  },
  rocky_solitary = {
    socialFearSusceptibility = 0.2,
    alarmBroadcastStrength = 0.5,
    conspecificAlarmSensitivity = 0.55,
    heterospecificAlarmSensitivity = 0.3
  },
  aquatic_schooler = {
    socialFearSusceptibility = 0.8,
    alarmBroadcastStrength = 0.8,
    conspecificAlarmSensitivity = 0.95,
    heterospecificAlarmSensitivity = 0.5
  },
  elusive_solitary = {
    socialFearSusceptibility = 0.35,
    alarmBroadcastStrength = 0.4,
    conspecificAlarmSensitivity = 0.55,
    heterospecificAlarmSensitivity = 0.25
  },
  weak_circadian_construct = {
    socialFearSusceptibility = 0.3,
    alarmBroadcastStrength = 0.55,
    conspecificAlarmSensitivity = 0.7,
    heterospecificAlarmSensitivity = 0.35
  }
}

function Archetypes.get(name)
  return Archetypes[name] or Archetypes.solitary
end

return Archetypes
