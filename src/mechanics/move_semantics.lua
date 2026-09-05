local MoveSemantics = {}

local SEMANTICS = {
	DIG = { { id = "BURROW", domain = "TRAVERSAL" },
		{ id = "EXCAVATE_SHELTER", domain = "ENVIRONMENT" } },
	TELEPORT = { { id = "TELEPORT", domain = "TRAVERSAL" } },
	FLY = { { id = "FLY", domain = "TRAVERSAL" } },
	SURF = { { id = "SWIM", domain = "TRAVERSAL" } },
	WHIRLWIND = { { id = "FORCED_DISPLACEMENT", domain = "INTERACTION" } },
	ROAR = { { id = "FORCED_DISPLACEMENT", domain = "INTERACTION" },
		{ id = "LOUD_SIGNAL", domain = "COMMUNICATION" } },
	RECOVER = { { id = "SELF_RECOVERY", domain = "PHYSIOLOGY" } },
	FLASH = { { id = "ILLUMINATION", domain = "ENVIRONMENT" } }
}

local function copy(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, item in pairs(value) do result[key] = copy(item) end
	return result
end

function MoveSemantics.forMove(move, context)
	context = context or {}
	local options = {}
	for _, semantic in ipairs(SEMANTICS[move and move.canonicalKey] or {}) do
		local possible = context.semanticAvailability
			and context.semanticAvailability[semantic.id] == true or false
		local executable = context.executableAffordances
			and context.executableAffordances[semantic.id] == true or false
		options[#options + 1] = {
			id = semantic.id, domain = semantic.domain,
			known = move and move.known == true,
			usableNow = move and move.usableNow == true,
			semanticallyPossible = possible,
			executable = executable,
			available = move and move.known == true and move.usableNow == true
				and possible and executable
		}
	end
	return options
end

function MoveSemantics.analyze(snapshot, context)
	local result = { options = {}, declaredCapabilities = {} }
	for _, move in ipairs(snapshot and snapshot.moves or {}) do
		for _, option in ipairs(MoveSemantics.forMove(move, context)) do
			option.moveKey = move.canonicalKey
			option.moveSlot = move.slot
			result.options[#result.options + 1] = option
			if option.domain == "TRAVERSAL" and option.known then
				result.declaredCapabilities[option.id] = true
			end
		end
	end
	return result
end

function MoveSemantics.inspect(snapshot, context)
	local lines = { "MOVE SEMANTICS" }
	for _, option in ipairs(MoveSemantics.analyze(snapshot, context).options) do
		lines[#lines + 1] = string.format(
			"move=%s option=%s known=%s usable=%s possible=%s executable=%s available=%s",
			tostring(option.moveKey), tostring(option.id), tostring(option.known),
			tostring(option.usableNow), tostring(option.semanticallyPossible),
			tostring(option.executable), tostring(option.available))
	end
	return table.concat(lines, "\n")
end

function MoveSemantics.definition(moveKey)
	return copy(SEMANTICS[moveKey] or {})
end

return MoveSemantics