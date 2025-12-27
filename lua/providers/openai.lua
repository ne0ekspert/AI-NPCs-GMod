local openAiProvider = {}

openAiProvider.modelOrder = {
    "gpt-5",
    "gpt-5-mini",
    "gpt-5-nano",
    "gpt-5-pro",
    "gpt-4o",
    "gpt-4o-mini",
    "gpt-4-turbo",
    "gpt-4",
    "gpt-3.5-turbo"
}

openAiProvider.models = {
    ["gpt-5"] = {
        label = "GPT-5",
        max_tokens = { min = 128, max = 4096, default = 2048 },
        temperature = { min = 1, max = 1, default = 1 },
        reasoning = { "minimal", "low", "medium", "high" },
    },
    ["gpt-5-mini"] = {
        label = "GPT-5 Mini",
        max_tokens = { min = 128, max = 4096, default = 2048 },
        temperature = { min = 1, max = 1, default = 1 },
        reasoning = { "minimal", "low", "medium", "high" },
    },
    ["gpt-5-nano"] = {
        label = "GPT-5 Nano",
        max_tokens = { min = 128, max = 4096, default = 2048 },
        temperature = { min = 1, max = 1, default = 1 },
        reasoning = { "minimal", "low", "medium", "high" },
    },
    ["gpt-5-pro"] = {
        label = "GPT-5 Pro",
        max_tokens = { min = 128, max = 4096, default = 2048 },
        temperature = { min = 1, max = 1, default = 1 },
        reasoning = { "minimal", "low", "medium", "high" },
    },
    ["gpt-4o"] = {
        label = "GPT-4o",
        max_tokens = { min = 128, max = 4096, default = 2048 },
        temperature = { min = 0, max = 2, default = 1 },
    },
    ["gpt-4o-mini"] = {
        label = "GPT-4o Mini",
        max_tokens = { min = 128, max = 4096, default = 2048 },
        temperature = { min = 0, max = 2, default = 1 },
    },
    ["gpt-4-turbo"] = {
        label = "GPT-4 Turbo",
        max_tokens = { min = 128, max = 4096, default = 2048 },
        temperature = { min = 0, max = 2, default = 1 },
    },
    ["gpt-4"] = {
        label = "GPT-4",
        max_tokens = { min = 128, max = 4096, default = 2048 },
        temperature = { min = 0, max = 2, default = 1 },
    },
    ["gpt-3.5-turbo"] = {
        label = "GPT-3.5 Turbo",
        max_tokens = { min = 128, max = 4096, default = 2048 },
        temperature = { min = 0, max = 2, default = 1 },
    },
}

if SERVER then
    function openAiProvider.request(npc, callback)
        local requestBody = {
            model = npc["model"],
            messages = npc["history"],
            max_completion_tokens = npc["max_tokens"], 
        }

        if AINPCS and AINPCS.GetToolDefinitions then
            local tools = AINPCS.GetToolDefinitions()
            if istable(tools) and #tools > 0 then
                requestBody.tools = tools
                requestBody.tool_choice = "auto"
            end
        end

        if npc["reasoning"] ~= nil and npc["reasoning"] ~= "" then
            requestBody.reasoning_effort = npc["reasoning"]
        end

        if npc["temperature"] ~= nil then
            requestBody.temperature = npc["temperature"]
        end

        HTTP({
            url = "https://api.openai.com/v1/chat/completions",
            type = "application/json; charset=utf-8",
            method = "post",
            headers = {
                ["Authorization"] = "Bearer " .. npc["apiKey"] -- Access the API key from the Global table
            },
            body = util.TableToJSON(requestBody), -- tableToJSON changes integers to float

            success = function(code, body, headers)
                local loggedBody = body or "<empty response>"
                AINPCS.DebugPrint("[AI-NPCs][OpenAI] Response code: " .. tostring(code))
                AINPCS.DebugPrint("[AI-NPCs][OpenAI] Response body: " .. loggedBody)
                -- Parse the JSON response from the GPT-3 API
                local response = util.JSONToTable(body)

                callback(nil, response)
            end,
            failed = function(err)
                -- Print an error message if the HTTP request fails
                callback("HTTP Error: " .. err, nil)
            end
        })
    end
end

return openAiProvider
