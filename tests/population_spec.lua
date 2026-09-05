local Save = require("src.core.save")
local PopulationManager = require("src.population.manager")
local Config = require("src.core.config")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local storedState = nil
local persistenceAdapter = {
	load = function()
		return storedState
	end,
	save = function(_, value)
		storedState = value
		return true
	end
}

Save.init(persistenceAdapter)
local entityA = PopulationManager.getOrCreatePhase0Entity()
entityA.level = 5
Save.flush()

Save.init(persistenceAdapter)
local entityB = PopulationManager.getOrCreatePhase0Entity()
assertEquals(entityB.id, "wild:route01:0001", "phase 0 should recreate the same stable entity id")
assertEquals(entityB.level, 5, "entity should persist through storage roundtrip")

local routePopulation = PopulationManager.getOrCreateRoutePopulation(Config.phase0.testMapId)
assertEquals(#routePopulation.order, Config.phase3.routePopulationSize, "phase 3 should build a small persistent route pool")
assertEquals(routePopulation.order[1], Config.phase0.testEntityId, "phase 3 route pool should keep the phase 0 anchor first")

local occupied = {}
for _, entityId in ipairs(routePopulation.order) do
	local entity = routePopulation.members[entityId]
	local cellKey = tostring(entity.home.spawnX) .. ":" .. tostring(entity.home.spawnY)
	assertEquals(occupied[cellKey] == nil, true, "phase 3 route pool members should not share spawn cells")
	occupied[cellKey] = true
end

local visibleAtTickOne = PopulationManager.getVisibleRoutePopulation(Config.phase0.testMapId, 1)
local visibleAtTickTwo = PopulationManager.getVisibleRoutePopulation(Config.phase0.testMapId, 2)
assertEquals(#visibleAtTickOne, Config.phase3.visibleSubsetSize, "phase 3 should return the configured visible subset size")
assertEquals(#visibleAtTickTwo, Config.phase3.visibleSubsetSize, "phase 3 visible subset should stay bounded")
assertEquals(visibleAtTickOne[1].id, Config.phase0.testEntityId, "phase 3 visible subset should keep the anchor visible")
local repeatVisible = PopulationManager.getVisibleRoutePopulation(Config.phase0.testMapId, 1)
assertEquals(visibleAtTickOne[2].id, repeatVisible[2].id, "the same seed should deterministically select the same companion")
local initiallySelected = {}
for _, entity in ipairs(visibleAtTickOne) do initiallySelected[entity.id] = true end
local hiddenId = nil
for _, entityId in ipairs(routePopulation.order) do
	if not initiallySelected[entityId] then
		hiddenId = entityId
		break
	end
end
if not hiddenId then error("route population should include a non-selected member") end
entityA.relationships[hiddenId] = {
	familiarity = 9, trust = 6, affinity = 3, threatMemory = 0,
	directThreatMemory = 0, hostility = 0, lastSeenTick = 25, importance = 0.2
}
assertEquals(routePopulation.members[hiddenId].id, hiddenId,
	"non-selected member should retain persistent identity in the route pool")
local laterSelected = false
for seed = 2, 100 do
	for _, entity in ipairs(PopulationManager.getVisibleRoutePopulation(Config.phase0.testMapId, seed)) do
		if entity.id == hiddenId then laterSelected = true end
	end
	if laterSelected then break end
end
assertEquals(laterSelected, true,
	"a currently hidden persistent individual should appear under a later selection seed")
assertEquals(entityA.relationships[hiddenId].familiarity, 9,
	"relationship to a hidden individual should not be recreated when it reappears")
local sawRelated = false
local sawUnrelated = false
for seed = 1, 24 do
	local visible = PopulationManager.getVisibleRoutePopulation(Config.phase0.testMapId, seed)
	if visible[2].species == visible[1].species then
		sawRelated = true
	else
		sawUnrelated = true
	end
end
assertEquals(sawRelated, true, "weighted selection should sometimes choose same-species companions")
assertEquals(sawUnrelated, true, "weighted selection should still allow unrelated companions")
assertEquals(
	tostring(visibleAtTickOne[1].home.spawnX) .. ":" .. tostring(visibleAtTickOne[1].home.spawnY)
	~= tostring(visibleAtTickOne[2].home.spawnX) .. ":" .. tostring(visibleAtTickOne[2].home.spawnY),
	true,
	"visible subset members should not share spawn cells"
)

return true
