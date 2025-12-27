local ollamaProvider = {}

ollamaProvider.models = {}

if SERVER then
    function ollamaProvider.request(npc, callback)
        if not npc["hostname"] or npc["hostname"] == "" then
            ErrorNoHalt("Hostname not defined")
            if callback then
                callback("Hostname not defined", nil)
            end
            return
        end

        local baseUrl = npc["hostname"]
        if not string.match(baseUrl, "^https?://") then
            baseUrl = "http://" .. baseUrl
        end
        baseUrl = string.gsub(baseUrl, "/+$", "")
        local url = baseUrl
        if not string.find(url, "/api/chat", 1, true) then
            url = url .. "/api/chat"
        end

        local requestBody = {
            model = npc["model"],
            messages = npc["history"],
            max_tokens = npc["max_tokens"], 
            temperature = npc["temperature"],
            stream = false
        }

        local headers = {
            ["Content-Type"] = "application/json"
        }

        if npc["apiKey"] and npc["apiKey"] ~= "" then
            headers["Authorization"] = "Bearer " .. npc["apiKey"]
        end

        HTTP({
            url = url,
            type = "application/json",
            method = "post",
            headers = headers,
            body = util.TableToJSON(requestBody),

            success = function(code, body, headers)
                local loggedBody = body or "<empty response>"
                AINPCS.DebugPrint("[AI-NPCs][Ollama] Response code: " .. tostring(code))
                AINPCS.DebugPrint("[AI-NPCs][Ollama] Response body: " .. loggedBody)
                -- Parse the JSON response from the GPT-3 API
                local response = util.JSONToTable(body)

                -- Add choices list to match ollama output to GPT output
                response.choices = {
                    {
                        message = {
                            role = response.message.role,
                            content = response.message.content
                        }
                    }
                }

                callback(nil, response)
            end,
            failed = function(err)
                -- Print an error message if the HTTP request fails
                callback("HTTP Error: " .. err, nil)
            end
        })
    end
end

return ollamaProvider
