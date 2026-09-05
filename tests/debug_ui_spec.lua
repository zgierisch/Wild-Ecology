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
local writtenFiles = {}
local optionValues = {
	phase0_behavior_mode = "force_flee",
	phase2_social_fear = true,
	phase2_social_reassurance = false
}
local saveValues = {
	phase0_debug_log = true,
	dev_log_view = "both",
	dev_log_lifecycle = true,
	dev_log_behavior = true,
	dev_log_relationships = false
}

local mod = {
	storage = {
		read = function(_, _game, _key)
			return storedState, storedState == nil and "not_found" or nil
		end,
		write = function(_, _game, _key, value)
			storedState = value
			return true
		end,
		writeBytes = function(_, _game, key, bytes)
			writtenFiles[key] = bytes
			return true
		end
	},
	game = {},
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
	save = {
		get = function(_, key, default)
			local value = saveValues[key]
			if value == nil then
				return default
			end
			return value
		end,
		set = function(_, key, value)
			saveValues[key] = value
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
assertEquals(WildEcology.getRelationshipAuditSnapshot(), nil,
	"relationship audit should be off by default")
assertEquals(WildEcology.getAgentAuditSnapshot(), nil,
	"agent audit should be off by default")
WildEcology.init(mod)
WildEcology.focusedEntityId = Config.phase0.testEntityId
local relationshipSnapshot = WildEcology.getFocusedRelationshipSnapshot(2)
assertEquals(type(relationshipSnapshot), "table",
	"focused relationship snapshot should be queryable")
assertEquals(relationshipSnapshot.relationshipCount >= 1, true,
	"focused relationship snapshot should report persistent record count")
assertEquals(#relationshipSnapshot.relationships <= 2, true,
	"focused relationship snapshot should honor its bounded limit")
local snapshotRelationship = relationshipSnapshot.relationships[1]
if not snapshotRelationship then
	error("focused relationship snapshot should include a relevant relationship")
end
for _, field in ipairs({ "targetId", "familiarity", "trust", "affinity",
	"threatMemory", "directThreatMemory", "hostility", "lastSeenTick" }) do
	assertEquals(snapshotRelationship[field] ~= nil, true,
		"focused relationship snapshot should expose " .. field)
end

assertEquals(type(definedOptions), "table", "behavior mode option should be defined")
local firstDefinedOption = type(definedOptions) == "table" and definedOptions[1] or nil
if not firstDefinedOption then
	error("behavior option definition should include at least one row")
end
assertEquals(firstDefinedOption.key, "phase0_behavior_mode", "behavior option key should be registered")
local behaviorChoices = firstDefinedOption.choices or {}
local sawForceApproach = false
for _, choice in ipairs(behaviorChoices) do
	if choice[2] == "force_approach" then
		sawForceApproach = true
	end
end
assertEquals(sawForceApproach, true, "behavior option should expose force approach")
local sawForceInvestigate = false
for _, choice in ipairs(behaviorChoices) do
	if choice[2] == "force_investigate" then
		sawForceInvestigate = true
	end
end
assertEquals(sawForceInvestigate, true, "behavior option should expose force investigate")
local sawForceTarget = false
for _, choice in ipairs(behaviorChoices) do
	if choice[2] == "force_target" then
		sawForceTarget = true
	end
end
assertEquals(sawForceTarget, true, "behavior option should expose force target")
local sawIgnorePlayer = false
for _, choice in ipairs(behaviorChoices) do
	if choice[2] == "ignore_player" then
		sawIgnorePlayer = true
	end
end
assertEquals(sawIgnorePlayer, true, "behavior option should expose ignore player")
local secondDefinedOption = type(definedOptions) == "table" and definedOptions[2] or nil
if not secondDefinedOption then
	error("phase2 fear toggle definition should include a second row")
end
assertEquals(secondDefinedOption.key, "phase2_social_fear", "phase2 fear toggle key should be registered")
local thirdDefinedOption = type(definedOptions) == "table" and definedOptions[3] or nil
if not thirdDefinedOption then
	error("phase2 reassurance toggle should be defined")
end
assertEquals(thirdDefinedOption.key, "phase2_social_reassurance", "phase2 reassurance toggle key should be registered")
local fourthDefinedOption = type(definedOptions) == "table" and definedOptions[4] or nil
if not fourthDefinedOption then
	error("phase5 diagnostics toggle should be defined")
end
assertEquals(fourthDefinedOption.key, "phase5_diagnostics", "phase5 diagnostics toggle key should be registered")
assertEquals(#definedOptions, 6, "the flat options menu should carry gameplay and clock settings; log toggles remain in the nested LOG SETTINGS screen")
assertEquals(type(registeredScreens["WildEcologyLogSettings"]), "table", "the nested log settings screen should be registered")
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
assertEquals(overlayBox.tw, 52, "debug overlay should be capped below the full viewport width")
assertEquals(overlayBox.th <= 44, true, "debug overlay should remain well below full viewport height")

assertContains(renderedLines, "VIEW MODE: BOTH", "debug overlay should render the selected log view")
assertContains(renderedLines, "ENABLED LOGS:", "debug overlay should render the enabled category heading")
assertContains(renderedLines, "LIFECYCLE", "debug overlay should render lifecycle as an enabled category")
assertContains(renderedLines, "BEHAVIOR", "debug overlay should render behavior as an enabled category")
assertContains(renderedLines, "LIFECYCLE #", "debug overlay should render lifecycle entries with sequence numbers")
assertContains(renderedLines, "BEHAVIOR #", "debug overlay should render behavior entries with sequence numbers")
assertContains(renderedLines, "PLAYER DISTANCE:", "debug overlay should render player distance when available")
assertContains(renderedLines, "FLEE RADIUS:", "debug overlay should render flee radius when available")
assertContains(renderedLines, "PIPELINE", "debug overlay should render the spawn pipeline as a labeled section")
assertContains(renderedLines, "persistent", "debug overlay should render persistent population counts as separate diagnostics")
assertContains(renderedLines, "selected", "debug overlay should render the selected cohort count in the pipeline")
assertContains(renderedLines, "SPAWN", "debug overlay should render a dedicated spawn section")
assertContains(renderedLines, "SPAWN result=", "debug overlay should expose the exact engine spawn result value")
assertContains(renderedLines, "SPAWN reason=", "debug overlay should expose the exact engine spawn refusal reason")

local pressed = {}
local popCount = 0
local settingsGame = {
	input = {
		wasPressed = function(_, key)
			return pressed[key] == true
		end
	},
	stack = {
		pop = function()
			popCount = popCount + 1
		end
	}
}
local settingsScreen = registeredScreens["WildEcologyLogSettings"].new(settingsGame)
drawn = {}
settingsScreen:draw()
local highestTextBottom = 0
assertContains((function()
	local text = {}
	for _, item in ipairs(drawn) do
		if item.kind == "text" then
			text[#text + 1] = item.text
			highestTextBottom = math.max(highestTextBottom, item.y + 8)
		end
	end
	return text
end)(), "B CLOSE", "log settings should display an explicit close control")
local settingsLines = {}
for _, item in ipairs(drawn) do
	if item.kind == "text" then settingsLines[#settingsLines + 1] = item.text end
end
assertContains(settingsLines, "REL AUDIT",
	"log settings should expose the relationship audit toggle")
assertContains(settingsLines, "AGENT AUDIT",
	"log settings should expose the agent audit toggle")
assertEquals(highestTextBottom <= 144, true, "all log settings controls should fit inside the native viewport")

for _ = 1, 6 do
	pressed.down = true
	settingsScreen:update(0)
	pressed.down = nil
end
pressed.a = true
settingsScreen:update(0)
pressed.a = nil
assertEquals(saveValues.relationship_audit_enabled, true,
	"REL AUDIT should persist its enabled state")
assertEquals(type(WildEcology.getRelationshipAuditSnapshot()), "table",
	"REL AUDIT should start telemetry immediately")
assertEquals(writtenFiles.relationship_audit ~= nil, true,
	"enabling REL AUDIT should initialize a fresh base file")

pressed.a = true
settingsScreen:update(0)
pressed.a = nil
assertEquals(saveValues.relationship_audit_enabled, false,
	"REL AUDIT should persist its disabled state")
assertEquals(WildEcology.getRelationshipAuditSnapshot(), nil,
	"disabling REL AUDIT should release telemetry immediately")

pressed.down = true
settingsScreen:update(0)
pressed.down = nil
pressed.a = true
settingsScreen:update(0)
pressed.a = nil
assertEquals(saveValues.agent_audit_enabled, true,
	"AGENT AUDIT should persist its enabled state")
assertEquals(type(WildEcology.getAgentAuditSnapshot()), "table",
	"AGENT AUDIT should start telemetry immediately")
assertEquals(writtenFiles.agent_audit ~= nil, true,
	"enabling AGENT AUDIT should initialize a fresh base file")

pressed.a = true
settingsScreen:update(0)
pressed.a = nil
assertEquals(saveValues.agent_audit_enabled, false,
	"AGENT AUDIT should persist its disabled state")
assertEquals(WildEcology.getAgentAuditSnapshot(), nil,
	"disabling AGENT AUDIT should flush and release telemetry immediately")

for _ = 1, 2 do
	pressed.down = true
	settingsScreen:update(0)
	pressed.down = nil
end
pressed.a = true
settingsScreen:update(0)
pressed.a = nil
assertEquals(saveValues.dev_log_console, true,
	"LOG TO FILE should persist its enabled state")
for _ = 1, 31 do WildEcology.init(mod) end
local firstFileEpoch = writtenFiles.wildecology_log
assertEquals(type(firstFileEpoch), "string",
	"enabling LOG TO FILE should create its first output epoch")
local firstEpochTick = firstFileEpoch:match("auditEpochStartTick=(%d+)")
assertEquals(firstEpochTick ~= nil, true,
	"ordinary file output should identify its epoch start")

pressed.a = true
settingsScreen:update(0)
pressed.a = nil
assertEquals(saveValues.dev_log_console, false,
	"LOG TO FILE should persist its disabled state")
for _ = 1, 60 do WildEcology.init(mod) end
pressed.a = true
settingsScreen:update(0)
pressed.a = nil
for _ = 1, 31 do WildEcology.init(mod) end
local secondFileEpoch = writtenFiles.wildecology_log
local secondEpochTick = secondFileEpoch
	and secondFileEpoch:match("auditEpochStartTick=(%d+)")
assertEquals(secondEpochTick ~= nil and secondEpochTick ~= firstEpochTick, true,
	"reenabling LOG TO FILE should begin a distinct epoch")
assertEquals(secondFileEpoch:find(
	"auditEpochStartTick=" .. tostring(firstEpochTick), 1, true), nil,
	"reenabling LOG TO FILE must not replay the prior file buffer")

drawn = {}
wrappedHooks["render.hud"](function() end, settingsGame, {
	width = 160, height = 144, gameX = 0, gameY = 0, gameWidth = 160, gameHeight = 144
})
assertEquals(#drawn, 0, "debug overlay should not obscure the log settings screen")

pressed.b = true
settingsScreen:update(0)
assertEquals(popCount, 1, "B should close the log settings screen")
drawn = {}
wrappedHooks["render.hud"](function() end, settingsGame, {
	width = 160, height = 144, gameX = 0, gameY = 0, gameWidth = 160, gameHeight = 144
})
assertEquals(#drawn > 0, true, "debug overlay should resume after the settings screen closes")

return true
