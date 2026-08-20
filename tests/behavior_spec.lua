local Entity = require("src.entities.entity")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local pidgeyA = Entity.newWildPokemon({
	id = "wild:test:0001",
	species = "PIDGEY",
	level = 4,
	personalitySeed = 847219
})

local pidgeyB = Entity.newWildPokemon({
	id = "wild:test:0002",
	species = "PIDGEY",
	level = 4,
	personalitySeed = 847219
})

local pidgeyC = Entity.newWildPokemon({
	id = "wild:test:0003",
	species = "PIDGEY",
	level = 4,
	personalitySeed = 777777
})

assertEquals(pidgeyA.temperament.boldness, pidgeyB.temperament.boldness, "same seed should produce same boldness")
assertEquals(pidgeyA.temperament.sociability, pidgeyB.temperament.sociability, "same seed should produce same sociability")

if pidgeyA.temperament.boldness == pidgeyC.temperament.boldness
and pidgeyA.temperament.sociability == pidgeyC.temperament.sociability then
	error("different seeds should vary at least one temperament trait")
end

return true
