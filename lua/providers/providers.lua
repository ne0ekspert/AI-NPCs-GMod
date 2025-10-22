local providers = {}

function providers.get(name)
    AINPCS.DebugPrint("Loading provider: " .. tostring(name))
    local provider
    if name == "openai" then
        provider = include("providers/openai.lua")
    elseif name == "ollama" then
        provider = include("providers/ollama.lua")
    elseif name == "groq" then
        provider = include("providers/groq.lua")
    elseif name == "openrouter" then
        provider = include("providers/openrouter.lua")
    else
        error("Unsupported provider: " .. name) 
    end

    return provider
end

return providers
