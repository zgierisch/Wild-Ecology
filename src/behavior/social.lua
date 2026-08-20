local Social = {}

function Social.shouldFollowAssociate(rel)
  return rel and rel.trust >= 40 and rel.affinity >= 20
end

return Social
