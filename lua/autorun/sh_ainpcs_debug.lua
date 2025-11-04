if SERVER then
    AddCSLuaFile()
end

AINPCS = AINPCS or {}

local function isDeveloperEnabled()
    local conVar = GetConVar and GetConVar("developer")
    if not conVar then return false end
    return conVar:GetInt() == 1
end

function AINPCS.IsDeveloperEnabled()
    return isDeveloperEnabled()
end

function AINPCS.DebugPrint(...)
    if not isDeveloperEnabled() then return end
    print(...)
end

function AINPCS.DebugPrintTable(tbl, indent)
    if not isDeveloperEnabled() then return end
    if indent ~= nil then
        PrintTable(tbl, indent)
    else
        PrintTable(tbl)
    end
end
