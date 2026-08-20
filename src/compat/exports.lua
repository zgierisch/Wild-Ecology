local Exports = {}

function Exports.getApi()
  return {
    ping = function()
      return "wild_ecology"
    end
  }
end

return Exports
