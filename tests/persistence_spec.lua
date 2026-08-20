local Save = require("src.core.save")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local storedState = nil
local mockMod = {
	storage = {
		get = function(_)
			return storedState
		end,
		set = function(_, value)
			storedState = value
		end
	}
}

-- Migrate a legacy-shaped state that is missing fields.
storedState = { schemaVersion = 1 }
Save.init(mockMod)
local migrated = Save.getState()
if not migrated then
	error("Save.getState should return a state table")
end
assertEquals(type(migrated.populations), "table", "migrated state should include populations")
assertEquals(migrated.nextEntitySerial, 1, "migrated state should include nextEntitySerial")

-- Persist route population content and ensure roundtrip reload works.
migrated.populations.ROUTE_1 = {
	members = {
		["wild:route01:0001"] = {
			id = "wild:route01:0001",
			species = "PIDGEY",
			level = 4
		}
	}
}
Save.flush()

Save.init(mockMod)
local reloaded = Save.getState()
if not reloaded or not reloaded.populations or not reloaded.populations.ROUTE_1 then
	error("reloaded state should include ROUTE_1 population")
end
assertEquals(reloaded.populations.ROUTE_1.members["wild:route01:0001"].species, "PIDGEY", "species should survive storage roundtrip")

return true
