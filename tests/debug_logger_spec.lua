local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function unloadModule(name)
	package.loaded[name] = nil
end

unloadModule("src.core.save")
unloadModule("src.debug.logger")

local Save = require("src.core.save")
local Logger = require("src.debug.logger")

Save.init(nil)

for index = 1, 30 do
	Logger.log(index % 2 == 0 and "behavior" or "lifecycle", "entry-" .. tostring(index))
end

local logState = Save.getDevLog()
if not logState then
	error("logger should initialize development log state")
end

assertEquals(#logState.entries, 24, "logger should keep a bounded ring of recent entries")
assertEquals(logState.entries[1].message, "entry-7", "logger should trim oldest entries first")
assertEquals(logState.entries[#logState.entries].message, "entry-30", "logger should keep the newest entry")

local filtered = Logger.filteredEntries(function(entry)
	return entry.category == "behavior"
end, 3)
assertEquals(#filtered, 3, "filteredEntries should respect the requested limit")
assertEquals(filtered[1].message, "entry-26", "filteredEntries should return the newest matching entries in order")
assertEquals(filtered[3].message, "entry-30", "filteredEntries should include the newest matching entry")

return true