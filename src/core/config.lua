local Config = {}

Config.phase0 = {
  testMapId = "ROUTE_1",
  testEntityId = "wild:route01:0001",
  testSpecies = "PIDGEY",
  testLevel = 4,
  defaultRelationshipTrust = 10,
  calmProximityCooldownTicks = 3,

  -- Optional in-game verification knobs for Phase 0. Keep nil for normal behavior.
  debugForceTrust = nil,
  debugForceThreatMemory = nil,
  debugForceHostility = nil
}

Config.relationships = {
  familiarityDecayPerDay = 0,
  trustDecayPerDay = 0
}

Config.phase2 = {
  demoAssociateId = "wild:route01:ally",
  defaultAssociateTrust = 60,
  socialFearSignal = 2
}

return Config
