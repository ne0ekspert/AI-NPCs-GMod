local groqProvider = {}

groqProvider.models = {
    ["llama-3.3-70b-versatile"] = {
        label = "LLaMA 3.3 70B",
        max_tokens = { min = 1, max = 32768, default = 2048 },
        temperature = { min = 0, max = 2, default = 1 },
    },
    ["llama-3.1-8b-instant"] = {
        label = "LLaMA 3.1 8B",
        max_tokens = { min = 1, max = 131072, default = 2048 },
        temperature = { min = 0, max = 2, default = 1 },
    },
    ["openai/gpt-oss-120b"] = {
        label = "GPT OSS 120B",
        max_tokens = { min = 1, max = 65536, default = 2048 },
        temperature = { min = 0, max = 2, default = 1 },
    },
    ["openai/gpt-oss-20b"] = {
        label = "GPT OSS 20B",
        max_tokens = { min = 1, max = 65536, default = 2048 },
        temperature = { min = 0, max = 2, default = 1 },
    },
    ["meta-llama/llama-4-maverick-17b-128e-instruct"] = {
        label = "LLaMA 4 Maverick 17B 128E",
        max_tokens = { min = 1, max = 8192, default = 2048 },
        temperature = { min = 0, max = 2, default = 1 },
    },
    ["meta-llama/llama-4-scout-17b-16e-instruct"] = {
        label = "LLaMA 4 Scout 17B 16E",
        max_tokens = { min = 1, max = 8192, default = 2048 },
        temperature = { min = 0, max = 2, default = 1 },
    },
    ["qwen/qwen3-32b"] = {
        label = "Qwen3-32B",
        max_tokens = { min = 1, max = 40960, default = 2048 },
        temperature = { min = 0, max = 2, default = 1 }
    }
}

if SERVER then
    function groqProvider.request(npc, callback)
        local requestBody = {
            model = npc["model"],
            messages = npc["history"],
            max_tokens = npc["max_tokens"], 
            temperature = npc["temperature"]
        }

        HTTP({
            url = "https://api.groq.com/openai/v1/chat/completions",
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

return groqProvider
