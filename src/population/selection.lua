local Selection = {}
local Config = require("src.core.config")

-- See src/entities/entity.lua's seededUnitInterval comment: the game
-- runtime is LuaJIT, so no bitwise operators and doubles-only precision.
-- This modular-multiplication mix (odd constants comparable in size to
-- MIX_MODULUS) fixes the same drift bug for the +1-per-pick `salt` step
-- within one selection call.
local MIX_MODULUS = 67108864 -- 2^26

local function seededUnit(seed, salt)
  local reduced = math.abs(math.floor(seed or 0)) % MIX_MODULUS
  local combined = (reduced * 40503199 + (salt or 0) * 40503) % MIX_MODULUS
  local mixed = (combined * 26146329 + 12345) % MIX_MODULUS
  return mixed / (MIX_MODULUS - 1)
end

local function normalizePopulation(population)
  if type(population) ~= "table" then
    return {}
  end

  if #population > 0 then
    return population
  end

  local items = {}
  for _, entity in pairs(population.members or population) do
    items[#items + 1] = entity
  end

  table.sort(items, function(left, right)
    return tostring(left and left.id or "") < tostring(right and right.id or "")
  end)

  return items
end

function Selection.pickVisibleSubset(population, maxCount, seed)
  local subset = {}

  local items = normalizePopulation(population)
  local count = #items
  local limit = math.min(count, maxCount or count)
  if count == 0 or limit == 0 then
    return subset
  end

  local offset = 0
  if seed ~= nil and count > 0 then
    offset = math.abs(math.floor(seed)) % count
  end

  for i = 1, limit do
    local index = ((offset + i - 1) % count) + 1
    subset[#subset + 1] = items[index]
  end
  return subset
end

function Selection.pickVisibleSubsetWithAnchor(population, maxCount, seed, anchorId)
  local items = normalizePopulation(population)
  local limit = math.min(#items, maxCount or #items)
  if limit == 0 then
    return {}
  end

  local subset = {}
  local anchorIndex = nil
  if anchorId ~= nil then
    for index = 1, #items do
      if items[index] and items[index].id == anchorId then
        anchorIndex = index
        break
      end
    end
  end

  if anchorIndex ~= nil then
    subset[#subset + 1] = items[anchorIndex]
  else
    subset[#subset + 1] = items[1]
    anchorIndex = 1
  end

  if limit == 1 then
    return subset
  end

  local remainder = {}
  for index = 1, #items do
    if index ~= anchorIndex then
      remainder[#remainder + 1] = items[index]
    end
  end

  local anchor = anchorIndex and items[anchorIndex] or nil
  local anchorEcology = anchor and anchor.ecology or {}
  local remaining = {}
  for index, entity in ipairs(remainder) do
    remaining[index] = entity
  end
  local weightSeed = math.abs(math.floor(seed or 0))

  for pick = 1, limit - 1 do
    local totalWeight = 0
    local weights = {}
    for index, entity in ipairs(remaining) do
      local ecology = entity and entity.ecology or {}
      local related = anchor
        and entity.species == anchor.species
        and ecology.family ~= nil
        and ecology.family == anchorEcology.family
      local weight = related
        and ((Config and Config.phase3 and Config.phase3.sameSpeciesFamilySpawnWeight) or 3)
        or ((Config and Config.phase3 and Config.phase3.unrelatedSpawnWeight) or 1)
      weights[index] = weight
      totalWeight = totalWeight + weight
    end

    if totalWeight <= 0 then
      break
    end
    local threshold = seededUnit(weightSeed, pick) * totalWeight
    local selectedIndex = #remaining
    local cumulative = 0
    for index, weight in ipairs(weights) do
      cumulative = cumulative + weight
      if threshold <= cumulative then
        selectedIndex = index
        break
      end
    end
    subset[#subset + 1] = table.remove(remaining, selectedIndex)
  end

  return subset
end

return Selection
