local Gen1PokemonMechanics = { id = "GEN1" }

local STAT_KEYS = { "hp", "attack", "defense", "speed", "special" }
local MAX_STAT_EXPERIENCE = 65535

local function clamp(value, minimum, maximum)
	return math.max(minimum, math.min(maximum, value))
end

local function hpPotential(dvs)
	return ((dvs.attack or 0) % 2) * 8 + ((dvs.defense or 0) % 2) * 4
		+ ((dvs.speed or 0) % 2) * 2 + ((dvs.special or 0) % 2)
end

local function development(value)
	local contribution = math.min(255, math.ceil(math.sqrt(
		clamp(value or 0, 0, MAX_STAT_EXPERIENCE))))
	return contribution / 255
end

local function normalizedPotential(value)
	return clamp(value or 0, 0, 15) / 15
end

local function maxPP(definition, move)
	if not definition then return nil end
	return (definition.pp or 0)
		+ (move.ppUps or 0) * math.floor((definition.pp or 0) / 5)
end

local function moveSnapshot(move, slot, definition, disabledSlot)
	local hasMetadata = type(definition) == "table"
	local currentPP = type(move.pp) == "number" and move.pp or nil
	local disabled = disabledSlot == slot
	local usableNow = nil
	if currentPP ~= nil then usableNow = currentPP > 0 and not disabled end
	local damaging, statusLike = nil, nil
	if hasMetadata then
		damaging = (definition.power or 0) > 0
		statusLike = not damaging
	end
	return {
		slot = slot,
		canonicalKey = tostring(move.id),
		displayName = hasMetadata and definition.name or tostring(move.id),
		known = true,
		usableNow = usableNow,
		unusableReason = disabled and "TEMPORARILY_DISABLED"
			or currentPP ~= nil and currentPP <= 0 and "NO_PP" or nil,
		metadataAvailability = hasMetadata and "AVAILABLE" or "UNAVAILABLE",
		mechanical = {
			type = hasMetadata and definition.type or nil,
			damaging = damaging,
			statusLike = statusLike,
			power = hasMetadata and definition.power or nil,
			accuracy = hasMetadata and definition.accuracy or nil,
			currentPP = currentPP,
			maxPP = maxPP(definition, move)
		}
	}
end

local function sourceRecord(entity, options)
	if options and options.pokemon then return options.pokemon end
	local partyIndex = entity and entity.ownership and entity.ownership.partyIndex
	local party = options and options.game and options.game.save
		and options.game.save.party
	if partyIndex and party then return party[partyIndex] end
	return entity and entity.mechanics and entity.mechanics.adapter == "GEN1"
		and entity.mechanics.pokemon or nil
end

function Gen1PokemonMechanics.signature(entity, options)
	local mon = sourceRecord(entity, options)
	if not mon then return "MISSING" end
	local parts = {}
	local function add(value) parts[#parts + 1] = tostring(value) end
	add(mon.species); add(mon.level); add(mon.exp); add(mon.hp); add(mon.status)
	for _, key in ipairs(STAT_KEYS) do
		add(mon.dvs and mon.dvs[key])
		add(mon.statExp and mon.statExp[key])
		add(mon.stats and mon.stats[key])
	end
	for _, move in ipairs(mon.moves or {}) do
		add(move.id); add(move.pp); add(move.ppUps)
	end
	add(options and options.disabledSlot)
	return table.concat(parts, "|")
end

local function expectedStat(base, level, hp)
	if type(base) ~= "number" or type(level) ~= "number" then return nil end
	local value = math.floor(((base + 7.5) * 2) * level / 100)
	return value + (hp and level + 10 or 5)
end

local function relativeStat(current, base, level, hp)
	local expected = expectedStat(base, level, hp)
	return current and expected and current / math.max(1, expected) or nil
end

function Gen1PokemonMechanics.snapshot(entity, options)
	local mon = sourceRecord(entity, options)
	if not mon then return nil, "GEN1_POKEMON_RECORD_UNAVAILABLE" end
	local dvs, statExp, stats = mon.dvs or {}, mon.statExp or {}, mon.stats or {}
	local hpDV = hpPotential(dvs)
	local innate = {
		hp = normalizedPotential(hpDV), attack = normalizedPotential(dvs.attack),
		defense = normalizedPotential(dvs.defense), speed = normalizedPotential(dvs.speed),
		specialAttack = normalizedPotential(dvs.special),
		specialDefense = normalizedPotential(dvs.special)
	}
	local training = {
		hp = development(statExp.hp), attack = development(statExp.attack),
		defense = development(statExp.defense), speed = development(statExp.speed),
		specialAttack = development(statExp.special),
		specialDefense = development(statExp.special)
	}
	local normalizedStats = {
		hp = mon.hp, maxHp = stats.hp, attack = stats.attack,
		defense = stats.defense, speed = stats.speed,
		specialAttack = stats.special, specialDefense = stats.special
	}
	local data = options.game and options.game.data or nil
	local species = options.speciesDefinition
		or options.speciesResolver and options.speciesResolver(mon.species)
		or data and data.pokemon and data.pokemon[mon.species]
	local base = species and species.baseStats or {}
	local relative = {
		hp = relativeStat(stats.hp, base.hp, mon.level, true),
		attack = relativeStat(stats.attack, base.attack, mon.level),
		defense = relativeStat(stats.defense, base.defense, mon.level),
		speed = relativeStat(stats.speed, base.speed, mon.level),
		specialAttack = relativeStat(stats.special, base.special, mon.level),
		specialDefense = relativeStat(stats.special, base.special, mon.level)
	}
	local moves = {}
	for slot, move in ipairs(mon.moves or {}) do
		local definition = options.moveResolver and options.moveResolver(move.id)
			or data and data.moves and data.moves[move.id]
		moves[#moves + 1] = moveSnapshot(move, slot, definition, options.disabledSlot)
	end
	return {
		available = true, adapter = Gen1PokemonMechanics.id,
		speciesId = mon.species, level = mon.level, experience = mon.exp,
		status = mon.status, stats = normalizedStats,
		innatePotential = innate, trainingDevelopment = training,
		relativeToSpecies = relative, moves = moves,
		provenance = { hpInnatePotential = "DERIVED_FROM_STORED_INNATE_BITS",
			specialAttack = "SHARED_UNIFIED_SPECIAL",
			specialDefense = "SHARED_UNIFIED_SPECIAL" },
		mechanicsCapabilities = {
			hasSplitSpecial = false, hasModernIVs = false, hasModernEVs = false,
			hasNatures = false, hasAbilities = false, hasGender = false,
			hasHeldItems = false, hasMoveCategories = false
		}
	}
end

return Gen1PokemonMechanics