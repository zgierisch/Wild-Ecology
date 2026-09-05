local Config = require("src.core.config")

local function assertContains(lines, fragment, message)
	for _, line in ipairs(lines) do
		if tostring(line):find(fragment, 1, true) then
			return
		end
	end
	error((message or "expected to find '" .. fragment .. "'"))
end

local storedState = nil
local mod = {
	storage = {
		read = function(_, _) return storedState, storedState==nil and 'not_found' or nil end,
		write = function(_, _, _, value) storedState=value; return true end,
		writeBytes = function() return true end
	},
	game = {},
	world = {
		current = function() return { mapId = Config.phase0.testMapId } end,
		spawnNpc = function(_, mapId) return mapId..'_obj_1' end,
		npc = function() return {} end,
		removeNpc = function() return true end
	},
	content = { screens = { register = function() end } },
	hooks = { wrap = function() end },
	options = { define = function() end, get = function() return true end },
	save = {
		get = function(_, key, default) 
			local vals = {phase0_debug_log=true,dev_log_view='both',dev_log_lifecycle=true,dev_log_behavior=true}
			local v = vals[key]
			return v or default
		end,
		set = function() end
	},
	ui = { Font = { drawBox = function() end, draw = function() end } }
}

local entry = require("main")
local WildEcology = entry(mod)
WildEcology.init(mod)

local drawn = {}
mod.ui.Font.draw = function(text, x, y)
	drawn[#drawn + 1] = tostring(text)
end

local wrappedHooks = {}
mod.hooks.wrap = function(_, id, wrapper)
	wrappedHooks[id] = wrapper
end

entry(mod)

local hudCallback = wrappedHooks["render.hud"]
if hudCallback then
	local context = { stack = {} }
	local args = {
		width = 640, height = 576, gameX = 0, gameY = 0,
		gameWidth = 640, gameHeight = 576, scale = 4, dpiX = 1, dpiY = 1
	}
	hudCallback(context, args)
end

print("=== Dispatch Diagnostics in HUD ===")
for i, line in ipairs(drawn) do
	if tostring(line):find("phase3") or tostring(line):find("DISPATCH") or tostring(line):find("blocker") then
		print(i, line)
	end
end

print()
print("=== Assertions ===")
assertContains(drawn, "DISPATCH", "HUD should show DISPATCH section")
assertContains(drawn, "phase3 entered", "HUD should show phase3Entered")
assertContains(drawn, "dispatch", "HUD should show phase3DispatchAttempts")
assertContains(drawn, "blocker", "HUD should show phase3LastBlocker")
assertContains(drawn, "SPAWN", "HUD should show SPAWN section")
assertContains(drawn, "PIPELINE", "HUD should show PIPELINE section")
print("✓ All dispatch diagnostics visible in HUD")
