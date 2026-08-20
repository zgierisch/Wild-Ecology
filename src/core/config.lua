local Config = {}

Config.phase0 = {
  testMapId = "ROUTE_1",
  testEntityId = "wild:route01:0001",
  testSpecies = "PIDGEY",
  testLevel = 4,
  defaultRelationshipTrust = 10,
  calmProximityCooldownTicks = 3
}

Config.relationships = {
  familiarityDecayPerDay = 0,
  trustDecayPerDay = 0
}

return Config
