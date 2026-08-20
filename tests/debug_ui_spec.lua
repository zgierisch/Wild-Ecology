local Config = require("src.core.config")

local function assertEquals(actual, expected, message)
	if actual ~= expected then
		error((message or "assertEquals failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
end

local function assertContains(lines, fragment, message)
	for _, line in ipairs(lines) do
		if tostring(line):find(fragment, 1, true) then
			return
		end
	end
	message = message or ("expected to find fragment '" .. fragment .. "'")
	error(message)
end

local function unloadModule(name)
	package.loaded[name] = nil
end

unloadModule("main")
unloadModule("src.core.save")
unloadModule("src.population.manager")
unloadModule("src.world.avatar_factory")
unloadModule("src.behavior.controller")

local storedState = nil
local currentMapId = Config.phase0.testMapId
local registeredScreens = {}
local wrappedHooks = {}
local handlesById = {}
local nextNpcSerial = 0
local definedOptions = nil
local optionValues = {
	phase0_behavior_mode = "force_flee",
	phase0_debug_log = true,
	dev_log_view = "events",
	dev_log_lifecycle = true,
	dev_log_behavior = true,
	dev_log_relationships = false
}

local mod = {
	storage = {
		get = function(_)
			return storedState
		end,
		set = function(_, value)
			storedState = value
		end
	},
	world = {
		current = function(_)
			return { mapId = currentMapId }
		end,
		spawnNpc = function(_, mapId, _objDef)
			nextNpcSerial = nextNpcSerial + 1
			return mapId .. "_obj_" .. tostring(nextNpcSerial)
		end,
		npc = function(_, _mapId, npcId)
			handlesById[npcId] = handlesById[npcId] or {}
			return handlesById[npcId]
		end,
		removeNpc = function(_, _npcId)
			return true
		end
	},
	content = {
		screens = {
			register = function(_, id, factory)
				registeredScreens[id] = factory
			end
		}
	},
	hooks = {
		wrap = function(_, id, wrapper)
			wrappedHooks[id] = wrapper
		end
	},
	options = {
		define = function(_, rows)
			definedOptions = rows
		end,
		get = function(_, key)
			return optionValues[key]
		end
	},
	ui = {
		Font = {
			drawBox = function() end,
			draw = function() end
		}
	}
}

local entry = require("main")
local WildEcology = entry(mod)
if not WildEcology then
	error("main entry should return WildEcology module API")
end

assertEquals(type(definedOptions), "table", "behavior mode option should be defined")
local firstDefinedOption = type(definedOptions) == "table" and definedOptions[1] or nil
if not firstDefinedOption then
	error("behavior option definition should include at least one row")
end
assertEquals(firstDefinedOption.key, "phase0_behavior_mode", "behavior option key should be registered")
local secondDefinedOption = type(definedOptions) == "table" and definedOptions[2] or nil
if not secondDefinedOption then
	error("log toggle definition should include a second row")
end
assertEquals(secondDefinedOption.key, "phase0_debug_log", "log toggle key should be registered")
assertEquals(secondDefinedOption.type, "toggle", "log visibility should be registered as a toggle")
local thirdDefinedOption = type(definedOptions) == "table" and definedOptions[3] or nil
if not thirdDefinedOption then
	error("log view definition should include a third row")
end
assertEquals(thirdDefinedOption.key, "dev_log_view", "log view key should be registered")
local fourthDefinedOption = type(definedOptions) == "table" and definedOptions[4] or nil
if not fourthDefinedOption then
	error("lifecycle category toggle should be defined")
end
assertEquals(fourthDefinedOption.key, "dev_log_lifecycle", "lifecycle toggle key should be registered")
local fifthDefinedOption = type(definedOptions) == "table" and definedOptions[5] or nil
if not fifthDefinedOption then
	error("behavior category toggle should be defined")
end
assertEquals(fifthDefinedOption.key, "dev_log_behavior", "behavior toggle key should be registered")
local sixthDefinedOption = type(definedOptions) == "table" and definedOptions[6] or nil
if not sixthDefinedOption then
	error("relationship category toggle should be defined")
end
assertEquals(sixthDefinedOption.key, "dev_log_relationships", "relationship toggle key should be registered")
assertEquals(type(wrappedHooks["render.hud"]), "function", "render.hud hook should be registered")

local drawn = {}
mod.ui.Font.drawBox = function(tx, ty, tw, th)
	drawn[#drawn + 1] = { kind = "box", tx = tx, ty = ty, tw = tw, th = th }
end
mod.ui.Font.draw = function(text, x, y)
	drawn[#drawn + 1] = { kind = "text", text = tostring(text), x = x, y = y }
end

local okDraw, drawErr = pcall(function()
	wrappedHooks["render.hud"](function() end, { stack = {} }, {
		width = 640,
		height = 576,
		gameX = 0,
		gameY = 0,
		gameWidth = 640,
		gameHeight = 576,
		scale = 4,
		dpiX = 1,
		dpiY = 1
	})
end)
assertEquals(okDraw, true, "debug log overlay draw should not raise an error: " .. tostring(drawErr))

local renderedLines = {}
local overlayBox = nil
for _, item in ipairs(drawn) do
	if item.kind == "box" and not overlayBox then
		overlayBox = item
	end
	if item.kind == "text" then
		renderedLines[#renderedLines + 1] = item.text
	end
end

if not overlayBox then
	error("debug overlay should draw a box")
end
assertEquals(overlayBox.tx, 0, "debug overlay should start at the left edge of the viewport")
assertEquals(overlayBox.tw, 80, "debug overlay should span the full viewport width")

assertContains(renderedLines, "VIEW MODE: EVENTS", "debug overlay should render the selected log view")
assertContains(renderedLines, "ENABLED LOGS:", "debug overlay should render the enabled category heading")
assertContains(renderedLines, "LIFECYCLE", "debug overlay should render lifecycle as an enabled category")
assertContains(renderedLines, "BEHAVIOR", "debug overlay should render behavior as an enabled category")
assertContains(renderedLines, "LIFECYCLE #", "debug overlay should render lifecycle entries with sequence numbers")
assertContains(renderedLines, "BEHAVIOR #", "debug overlay should render behavior entries with sequence numbers")

return true
