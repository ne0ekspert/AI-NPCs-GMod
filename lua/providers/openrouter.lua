local openrouterProvider = {}

openrouterProvider.models = {
    
}

if SERVER then
    function openrouterProvider.request(npc, callback)
        local requestBody = {
            model = npc["model"],
            messages = npc["history"],
            max_tokens = npc["max_tokens"], 
            temperature = npc["temperature"]
        }

        if AINPCS and AINPCS.GetToolDefinitions then
            local tools = AINPCS.GetToolDefinitions()
            if istable(tools) and #tools > 0 then
                requestBody.tools = tools
                requestBody.tool_choice = "auto"
            end
        end

        HTTP({
            url = "https://openrouter.ai/api/v1/chat/completions",
            type = "application/json",
            method = "post",
            headers = {
                ["Content-Type"] = "application/json",
                ["Authorization"] = "Bearer " .. npc["apiKey"] -- Access the API key from the Global table
            },
            body = util.TableToJSON(requestBody),

            success = function(code, body, headers)
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

-- 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

return openrouterProvider
