package.path = package.path .. ";./?.lua;./?/init.lua"

local HomeArea = require("src.world.home_area")
local WorldSemantics = require("src.world.world_semantics")

local function assertEquals(actual, expected, message)
  if actual ~= expected then
    error((message or "assertEquals failed") .. ": expected "
      .. tostring(expected) .. ", got " .. tostring(actual))
  end
end

local semantics = WorldSemantics.fromOverview({
  mapId = "HOME_MAP", width = 7, height = 3,
  rows = { ".......", ".......", "......+" }
}, {
  transitions = {
    [WorldSemantics.cellKey(6, 2)] = { kind = "MAP_WARP" }
  }
})
if not semantics then error("home test semantics should resolve") end

local entity = {
  home = { mapId = "HOME_MAP", spawnX = 3, spawnY = 1 },
  relationships = {}
}
local area, status = HomeArea.establish(entity, semantics, {
  radius = 2, establishedTick = 40
})
if not area then error("valid home area should establish") end
assertEquals(status, "ESTABLISHED", "valid persisted placement should establish home")
assertEquals(area.anchorCell.cellX, 3, "placement should seed the area anchor")
assertEquals(area.radius, 2, "home must retain bounded area radius")
assertEquals(HomeArea.isInside(entity, { cellX = 1, cellY = 0 }, "HOME_MAP"), true,
  "a non-anchor cell inside the area must satisfy home")
assertEquals(HomeArea.isInside(entity, { cellX = 0, cellY = 0 }, "HOME_MAP"), false,
  "a cell beyond the area must remain outside")

entity.home.spawnX = 0
entity.home.spawnY = 0
local existing, existingStatus = HomeArea.establish(entity, semantics, { radius = 5 })
if not existing then error("existing home area should remain available") end
assertEquals(existingStatus, "EXISTING", "establishment must never silently reassign home")
assertEquals(existing, area, "existing area identity must be retained")
assertEquals(existing.anchorCell.cellX, 3, "later spawn changes must not move home")

entity.locationState = {
  kind = "CONCEALED", mapId = "HOME_MAP",
  anchorCell = { cellX = 2, cellY = 1 }
}
local hiddenPosition, hiddenMapId = HomeArea.position(entity, nil)
assertEquals(HomeArea.isInside(entity, hiddenPosition, hiddenMapId), true,
  "concealed location must satisfy home without an avatar")

local destination = HomeArea.selectDestination(entity, semantics,
  { cellX = 6, cellY = 1 })
if not destination then error("legal home destination should resolve") end
assertEquals(destination.cellX, 5,
  "return destination should be the nearest acceptable area cell")
assertEquals(HomeArea.isInside(entity, destination, "HOME_MAP"), true,
  "return destination must be inside the home area")
assertEquals(destination.cellX == area.anchorCell.cellX
  and destination.cellY == area.anchorCell.cellY, false,
  "return destination must not force exact anchor occupancy")

local invalid = { home = { mapId = "HOME_MAP", spawnX = 6, spawnY = 2 } }
local invalidArea, invalidStatus = HomeArea.establish(invalid, semantics)
assertEquals(invalidArea, nil, "transition cells must not establish home")
assertEquals(invalidStatus, "INVALID_ANCHOR", "invalid provenance should remain unset")

print("All home-area domain tests passed")