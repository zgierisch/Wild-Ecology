local Environment = {}

-- Vanilla Gen1 cumulative slot thresholds out of 256
-- (FieldDefaults.CONSTANTS.encounterBuckets); last-resort fallback only,
-- used when the constants registry itself is unreachable.
local DEFAULT_ENCOUNTER_BUCKETS = { 51, 102, 141, 166, 191, 216, 229, 242, 253, 256 }

function Environment.getCellTags(_mapId, _x, _y)
  return { "PATH" }
end

-- Mirrors src/world/Encounter.lua's roll (engine-internal, not in the
-- supported-requires list) using only the documented `encounters`/
-- `constants` registries, so no engine_internals permission is needed.
local function rollGrassSlot(grass, buckets, roll)
  for index, threshold in ipairs(grass.buckets or buckets or DEFAULT_ENCOUNTER_BUCKETS) do
    if roll < threshold then
      local slot = grass.slots and grass.slots[index]
      if slot then
        return { species = slot.species, level = slot.level }
      end
      return nil
    end
  end
  return nil
 end

-- Real Gen1Recomp wild encounter data via mod.content.encounters:get(mapId)
-- (verified against gen1recomp wiki Reference-Registries/Reference-Mod-Object,
-- 2026-08-21). Returns nil when `mod` is unavailable (headless tests) or the
-- map has no grass table, so callers fall back to their own configured
-- template instead of the generator hardcoding what spawns.
--
-- `grass.rate` is vanilla's PER-STEP chance that a wild battle starts at
-- all (out of 256) -- it answers "does an encounter happen on this step",
-- not "which species lives here". Population generation asks a different
-- question ("what would live in this slot"), so it must NOT re-roll that
-- step chance (doing so made ~90% of every generated slot report a MISS
-- and fall back to the species pool, even though real ROUTE_1 data was
-- available) -- it only checks that grass encounters exist on this map at
-- all, then always resolves a real slot.
function Environment.getWildEncounterTable(mod, mapId, rng)
  if not mod or not mod.content or not mod.content.encounters or not mod.content.encounters.get then
    return nil
  end

  local ok, encounterDef = pcall(mod.content.encounters.get, mod.content.encounters, mapId)
  if not ok or not encounterDef or not encounterDef.grass then
    return nil
  end

  local grass = encounterDef.grass
  if not grass.rate or grass.rate <= 0 then
    return nil
  end

  local roller = rng or math.random
  local buckets = nil
  if mod.content.constants and mod.content.constants.get then
    local okBuckets, fetched = pcall(mod.content.constants.get, mod.content.constants, "encounterBuckets")
    if okBuckets then
      buckets = fetched
    end
  end

  return rollGrassSlot(grass, buckets, roller(0, 255))
end

function Environment.evaluateTraversal(actor, mapId, fromX, fromY, toX, toY, direction, world, movementAvailable)
  local _ = actor
  if type(world) == "table" and type(world.isWalkable) == "function" then
    local ok, walkable = pcall(world.isWalkable, world, mapId, toX, toY)
    if ok and walkable == true then
      return {
        allowed = true,
        traversalMode = "WALK",
        destinationX = toX,
        destinationY = toY,
        direction = direction
      }
    end
    return { allowed = false, reason = "BLOCKED" }
  end

  if movementAvailable == true then
    return {
      allowed = true,
      traversalMode = "WALK",
      destinationX = toX,
      destinationY = toY,
      direction = direction,
      collisionDeferredToExecutor = true
    }
  end

  return { allowed = false, reason = "COLLISION_UNAVAILABLE" }
end

return Environment
