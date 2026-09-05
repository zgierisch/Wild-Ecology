package.path = package.path .. ";./?.lua;./?/init.lua"

local PokemonMechanics = require("src.adapters.pokemon_mechanics")
local Gen1 = require("src.adapters.gen1.pokemon_mechanics")

local mon = {
	species = "RATTATA", level = 12, exp = 1000, hp = 30,
	dvs = { attack = 15, defense = 8, speed = 14, special = 7 },
	statExp = { hp = 0, attack = 16384, defense = 65535, speed = 4096, special = 256 },
	stats = { hp = 32, attack = 24, defense = 18, speed = 28, special = 16 },
	moves = { { id = "DIG", pp = 5, ppUps = 1 }, { id = "ROAR", pp = 0 } }
}
local entity = { species = "RATTATA", level = 12,
	mechanics = { adapter = "GEN1", pokemon = mon } }
local moves = {
	DIG = { name = "Dig", type = "GROUND", power = 100, accuracy = 100, pp = 10 },
	ROAR = { name = "Roar", type = "NORMAL", power = 0, accuracy = 100, pp = 20 }
}
PokemonMechanics.register(Gen1)
local snapshot = PokemonMechanics.snapshot(entity, {
	speciesDefinition = { baseStats = { hp = 30, attack = 56, defense = 35,
		speed = 72, special = 25 } },
	moveResolver = function(id) return moves[id] end
})
assert(snapshot.adapter == "GEN1" and snapshot.available,
	"facade should expose a normalized Gen I snapshot")
assert(snapshot.innatePotential.hp == 9 / 15,
	"HP potential must be derived from the low bits of stored innate values")
assert(snapshot.innatePotential.specialAttack == snapshot.innatePotential.specialDefense,
	"unified Special must normalize without leaking a downstream branch")
assert(snapshot.trainingDevelopment.attack == 128 / 255,
	"development should represent nonlinear mechanical stat contribution")
assert(snapshot.moves[1].canonicalKey == "DIG" and snapshot.moves[1].mechanical.maxPP == 12,
	"ordered moves should normalize canonical identity and PP Ups")
assert(snapshot.moves[2].known and snapshot.moves[2].usableNow == false,
	"known and currently usable must remain separate")
assert(snapshot.moves[1].mechanical.damaging == true
	and snapshot.moves[1].mechanical.statusLike == false,
	"move metadata booleans must preserve explicit false values")
assert(snapshot.mechanicsCapabilities.hasSplitSpecial == false,
	"Gen I capability flags must report actual mechanics")

snapshot.stats.speed = 999
assert(PokemonMechanics.snapshot(entity, {
	speciesDefinition = { baseStats = {} }, moveResolver = function(id) return moves[id] end
}).stats.speed == 28, "callers must receive defensive snapshots")

local Future = {
	id = "FUTURE_TEST",
	snapshot = function(actor)
		return { speciesId = actor.species, level = actor.level,
			stats = { speed = actor.future.speed },
			innatePotential = { speed = actor.future.genetic / 31 },
			trainingDevelopment = { speed = actor.future.training },
			relativeToSpecies = { speed = 1.1 },
			moves = { { slot = 1, canonicalKey = actor.future.moveToken,
				known = true, usableNow = true, mechanical = {} } },
			mechanicsCapabilities = { hasSplitSpecial = true, hasModernIVs = true } }
	end
}
PokemonMechanics.register(Future)
local future = PokemonMechanics.snapshot({ species = "PIDGEY", level = 12,
	future = { speed = 31, genetic = 31, training = 0.5, moveToken = "DIG" } })
assert(future.innatePotential.speed == 1 and future.moves[1].canonicalKey == "DIG",
	"the same facade must accept a different underlying stat and move layout")

return true