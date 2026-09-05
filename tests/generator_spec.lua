local Save = require("src.core.save")
local Entity = require("src.entities.entity")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

Save.init(nil)
local Generator = require("src.population.generator")

-- Regression: personalitySeed = base + serial*13 previously fed a
-- single-pass affine hash, so consecutive serials produced a slowly
-- drifting fraction instead of real variation -- every generated Pidgey
-- landed in the same family and the species pool never picked RATTATA
-- across dozens of individuals in a row.
local poolConfig = {
	speciesPool = {
		{ species = "PIDGEY", weight = 3, levelRange = { min = 4, max = 5 } },
		{ species = "RATTATA", weight = 2, levelRange = { min = 3, max = 4 } }
	},
	zoneOrder = { "south_grass", "north_grass", "east_grass", "west_grass", "center_grass" }
}

local population = Generator.makeRoutePopulation("ROUTE_1", "route01", poolConfig, 40, 21, nil, 0)
assertEquals(#population.order, 40, "should generate the requested batch size")

local speciesCounts = {}
local familyCounts = {}
for _, id in ipairs(population.order) do
	local entity = population.members[id]
	speciesCounts[entity.species] = (speciesCounts[entity.species] or 0) + 1
	local family = entity.ecology and entity.ecology.family
	if family then
		familyCounts[family] = (familyCounts[family] or 0) + 1
	end
end

if not speciesCounts.RATTATA or speciesCounts.RATTATA == 0 then
	error("species pool should produce some RATTATA across 40 consecutive serials, not just PIDGEY")
end
if not speciesCounts.PIDGEY or speciesCounts.PIDGEY == 0 then
	error("species pool should still produce PIDGEY (the heavier weight)")
end

local distinctFamilies = 0
for _ in pairs(familyCounts) do
	distinctFamilies = distinctFamilies + 1
end
if distinctFamilies < 2 then
	error("individuals across 40 consecutive serials should not all land in the same family")
end

-- Same drift bug, isolated to Entity.assignFamily directly.
local seenFamilies = {}
for serial = 1, 40 do
	local seed = 847219 + serial * 13
	local family = Entity.assignFamily("PIDGEY", seed)
	seenFamilies[family] = (seenFamilies[family] or 0) + 1
end
local distinctAssigned = 0
for _ in pairs(seenFamilies) do
	distinctAssigned = distinctAssigned + 1
end
if distinctAssigned < 2 then
	error("Entity.assignFamily should vary across consecutive personality seeds, not drift on one family")
end

return true
