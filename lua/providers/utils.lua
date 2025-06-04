local utils = {}

function utils.correctFloatToInt(jsonString)
    return string.gsub(jsonString, '(%d+)%.0', '%1')
end

return utils
