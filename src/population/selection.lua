local Selection = {}

function Selection.pickVisibleSubset(population, maxCount)
  local subset = {}
  for i = 1, math.min(#population, maxCount) do
    subset[#subset + 1] = population[i]
  end
  return subset
end

return Selection
