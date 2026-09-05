local PokemonMechanics = {}

local adapter = nil
local cache = setmetatable({}, { __mode = "k" })

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in pairs(value) do result[key] = copy(item) end
	return result
end

local function unavailable(entity, reason)
	return {
		available = false,
		reason = reason or "MECHANICS_ADAPTER_UNAVAILABLE",
		adapter = adapter and adapter.id or "NONE",
		speciesId = entity and entity.species or nil,
		level = entity and entity.level or nil,
		stats = {}, innatePotential = {}, trainingDevelopment = {},
		relativeToSpecies = {}, moves = {}, mechanicsCapabilities = {}
	}
end

function PokemonMechanics.register(implementation)
	assert(type(implementation) == "table", "mechanics adapter is required")
	assert(type(implementation.id) == "string", "mechanics adapter id is required")
	assert(type(implementation.snapshot) == "function",
		"mechanics adapter snapshot function is required")
	adapter = implementation
	cache = setmetatable({}, { __mode = "k" })
	return implementation
end

function PokemonMechanics.currentAdapterId()
	return adapter and adapter.id or nil
end

function PokemonMechanics.create(spec)
	if not adapter or type(adapter.create) ~= "function" then
		return nil, "MECHANICS_CREATION_UNAVAILABLE"
	end
	return adapter.create(spec or {})
end

function PokemonMechanics.signature(entity, options)
	if not adapter then return "NONE" end
	if type(adapter.signature) == "function" then
		return adapter.signature(entity, options or {})
	end
	return tostring(entity and entity.mechanicsRevision or 0)
end

function PokemonMechanics.snapshot(entity, options)
	if not adapter then return unavailable(entity) end
	options = options or {}
	local signature = PokemonMechanics.signature(entity, options)
	local optionDependent = next(options) ~= nil
	local cacheable = entity and (not optionDependent or options.cacheKey ~= nil)
	if options.cacheKey ~= nil then signature = signature .. "|" .. tostring(options.cacheKey) end
	local cached = cacheable and cache[entity] or nil
	if cached and cached.signature == signature then return copy(cached.snapshot) end
	local normalized, reason = adapter.snapshot(entity, options)
	if type(normalized) ~= "table" then
		return unavailable(entity, reason or "MECHANICS_DATA_UNAVAILABLE")
	end
	normalized.available = normalized.available ~= false
	normalized.adapter = normalized.adapter or adapter.id
	if cacheable then cache[entity] = { signature = signature, snapshot = copy(normalized) } end
	return copy(normalized)
end

function PokemonMechanics.invalidate(entity)
	if entity then cache[entity] = nil else cache = setmetatable({}, { __mode = "k" }) end
end

function PokemonMechanics.inspect(entity, options)
	local snapshot = PokemonMechanics.snapshot(entity, options)
	local lines = { string.format("POKEMON MECHANICS adapter=%s available=%s reason=%s",
		tostring(snapshot.adapter), tostring(snapshot.available),
		tostring(snapshot.reason or "none")), string.format("species=%s level=%s",
		tostring(snapshot.speciesId or "unknown"), tostring(snapshot.level or "unknown")) }
	for _, key in ipairs({ "hp", "attack", "defense", "speed",
		"specialAttack", "specialDefense" }) do
		lines[#lines + 1] = string.format(
			"%s stat=%s innate=%s development=%s relative=%s", key,
			tostring(snapshot.stats[key] or "unknown"),
			tostring(snapshot.innatePotential[key] or "unknown"),
			tostring(snapshot.trainingDevelopment[key] or "unknown"),
			tostring(snapshot.relativeToSpecies[key] or "unknown"))
	end
	for _, move in ipairs(snapshot.moves or {}) do
		lines[#lines + 1] = string.format(
			"move[%d]=%s known=true usable=%s pp=%s/%s metadata=%s",
			move.slot or 0, tostring(move.canonicalKey),
			tostring(move.usableNow), tostring(move.mechanical.currentPP or "unknown"),
			tostring(move.mechanical.maxPP or "unknown"),
			tostring(move.metadataAvailability or "unknown"))
	end
	return table.concat(lines, "\n")
end

return PokemonMechanics