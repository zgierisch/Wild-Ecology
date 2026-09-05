local EcologicalPhenotype = {}

local cache = setmetatable({}, { __mode = "k" })

local function clamp(value, minimum, maximum)
	return math.max(minimum, math.min(maximum, value))
end

local function boundedRelative(value)
	if type(value) ~= "number" or value < 0 then return 0.5 end
	return value / (1 + value)
end

local function component(snapshot, key)
	local relative = boundedRelative(snapshot.relativeToSpecies
		and snapshot.relativeToSpecies[key])
	local innate = snapshot.innatePotential and snapshot.innatePotential[key] or 0.5
	local development = snapshot.trainingDevelopment
		and snapshot.trainingDevelopment[key] or 0
	return clamp(relative * 0.5 + innate * 0.3 + development * 0.2, 0, 1)
end

local function average(...)
	local values, total = { ... }, 0
	for _, value in ipairs(values) do total = total + value end
	return total / #values
end

function EcologicalPhenotype.derive(snapshot)
	if not snapshot or snapshot.available == false then
		return { available = false, mobility = 0.5, endurance = 0.5,
			robustness = 0.5, physicalPower = 0.5, recoveryCapacity = 0.5,
			movementScale = 1, sourceSignature = "UNAVAILABLE" }
	end
	local hp = component(snapshot, "hp")
	local attack = component(snapshot, "attack")
	local defense = component(snapshot, "defense")
	local speed = component(snapshot, "speed")
	local specialDefense = component(snapshot, "specialDefense")
	return {
		available = true,
		mobility = speed,
		endurance = average(hp, defense, speed),
		robustness = average(hp, defense),
		physicalPower = attack,
		recoveryCapacity = average(hp, specialDefense),
		movementScale = 0.85 + speed * 0.3,
		sourceSignature = tostring(snapshot.adapter) .. ":" .. tostring(snapshot.speciesId)
	}
end

function EcologicalPhenotype.forEntity(entity, mechanics, signature)
	local cached = entity and cache[entity]
	if cached and cached.signature == signature then return cached.value end
	local phenotype = EcologicalPhenotype.derive(mechanics)
	if entity then cache[entity] = { signature = signature, value = phenotype } end
	return phenotype
end

function EcologicalPhenotype.invalidate(entity)
	if entity then cache[entity] = nil else cache = setmetatable({}, { __mode = "k" }) end
end

function EcologicalPhenotype.inspect(phenotype)
	phenotype = phenotype or EcologicalPhenotype.derive(nil)
	return string.format(
		"ECOLOGICAL PHENOTYPE available=%s mobility=%.3f endurance=%.3f robustness=%.3f physicalPower=%.3f recovery=%.3f movementScale=%.3f",
		tostring(phenotype.available), phenotype.mobility, phenotype.endurance,
		phenotype.robustness, phenotype.physicalPower,
		phenotype.recoveryCapacity, phenotype.movementScale)
end

return EcologicalPhenotype