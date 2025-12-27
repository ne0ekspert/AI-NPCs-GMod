-- Add network strings for communication between client and server
util.AddNetworkString("GetNPCModel")
util.AddNetworkString("RespondNPCModel")
util.AddNetworkString("SendNPCInfo")
util.AddNetworkString("SayTTS")
util.AddNetworkString("TTSPositionUpdate")
util.AddNetworkString("AINPCS_RequestNPCSelection")
util.AddNetworkString("AINPCS_SelectNPC")
util.AddNetworkString("AINPCS_SelectNPCFailed")
util.AddNetworkString("AINPCS_UpdateNPC")
util.AddNetworkString("AINPCS_UpdateNPCMemory")

include("autorun/sh_ainpcs_debug.lua")

local providers = include('providers/providers.lua')

local FREE_API_KEY = "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"

local spawnedNPC = {} -- Variable to store the reference to the spawned NPC

local function clearPlayerSelection(ply)
    if not IsValid(ply) then return end
    ply.AINPCS_SelectedEnt = nil
    ply.AINPCS_SelectedKey = nil
end

local function buildPersonalityPrompt(personality)
    return "it is your job to act like this personality: " ..
               (personality or "") ..
               "if you understand, respond with a hello in character.\n\n" ..
               "You can control your movement with tools. " ..
               "If the user asks you to follow them or wander, call the appropriate tool. " ..
               "If you need nearby player info, call scan_players."
end

local function getToolDefinitions()
    return {
        {
            type = "function",
            ["function"] = {
                name = "follow_player",
                description = "Make the NPC follow its owner.",
                parameters = {
                    type = "object",
                    properties = {
                        speed = {
                            type = "string",
                            enum = { "walk", "run" }
                        },
                        target = {
                            type = "string",
                            description = "Who to follow: owner, speaker, player name, or SteamID."
                        },
                        distance = {
                            type = "number",
                            description = "Desired follow distance in Source units (~39.4 units = 1 meter)."
                        }
                    },
                    additionalProperties = false
                }
            }
        },
        {
            type = "function",
            ["function"] = {
                name = "wander",
                description = "Make the NPC wander around its current position.",
                parameters = {
                    type = "object",
                    properties = {
                        radius = {
                            type = "number",
                            description = "Wander radius in Source units (~39.4 units = 1 meter)."
                        },
                        interval = {
                            type = "number",
                            description = "Seconds between wander targets."
                        }
                    },
                    additionalProperties = false
                }
            }
        },
        {
            type = "function",
            ["function"] = {
                name = "stop_moving",
                description = "Stop any follow or wander behavior.",
                parameters = {
                    type = "object",
                    properties = {
                        reason = {
                            type = "string",
                            description = "Optional note for why movement stopped."
                        }
                    },
                    required = {},
                    additionalProperties = false
                }
            }
        },
        {
            type = "function",
            ["function"] = {
                name = "scan_players",
                description = "List nearby players from the NPC's position, optionally requiring visibility.",
                parameters = {
                    type = "object",
                    properties = {
                        radius = {
                            type = "number",
                            description = "Search radius in units."
                        },
                        visible_only = {
                            type = "boolean",
                            description = "Only include players visible to the NPC."
                        },
                        include_owner = {
                            type = "boolean",
                            description = "Include the NPC owner in the results."
                        },
                        limit = {
                            type = "number",
                            description = "Maximum number of players to return."
                        }
                    },
                    additionalProperties = false
                }
            }
        }
    }
end

function AINPCS.GetToolDefinitions()
    return getToolDefinitions()
end

local function parseToolArguments(raw)
    if raw == nil then return {} end
    if istable(raw) then return raw end
    if isstring(raw) and raw ~= "" then
        local decoded = util.JSONToTable(raw)
        if istable(decoded) then
            return decoded
        end
    end
    return {}
end

local function isSequentialArray(tbl)
    if not istable(tbl) then return false end
    local count = 0
    for key in pairs(tbl) do
        if type(key) ~= "number" or key <= 0 or key % 1 ~= 0 then
            return false
        end
        count = count + 1
    end
    return count == #tbl
end

local function sanitizeHistory(raw)
    if not isSequentialArray(raw) then return {} end
    local cleaned = {}
    for _, entry in ipairs(raw) do
        if istable(entry) and isstring(entry.role) then
            local message = {
                role = entry.role
            }
            if entry.content == nil then
                message.content = ""
            elseif isstring(entry.content) then
                message.content = entry.content
            else
                message.content = tostring(entry.content)
            end

            if isstring(entry.name) then
                message.name = entry.name
            end
            if entry.tool_call_id ~= nil then
                message.tool_call_id = entry.tool_call_id
            end
            if istable(entry.tool_calls) then
                message.tool_calls = entry.tool_calls
            end
            if istable(entry.function_call) then
                message.function_call = entry.function_call
            end

            table.insert(cleaned, message)
        end
    end
    return cleaned
end

local function setMovementMode(record, mode, options)
    record.moveMode = mode
    record.moveOptions = options or {}
    record.nextMoveAt = 0
    if mode ~= "follow" then
        record.followTarget = nil
    end

    if mode == "idle" and IsValid(record.npc) then
        record.npc:SetSchedule(SCHED_IDLE_STAND)
    end
end

local function findPlayerByName(query)
    if not isstring(query) or query == "" then return nil end
    local lowered = string.Trim(string.lower(query))
    if lowered == "" then return nil end

    local partialMatch = nil
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) then
            local nick = ply:Nick() or ""
            local nickLower = string.lower(nick)
            if nickLower == lowered then
                return ply
            end
            if not partialMatch and string.find(nickLower, lowered, 1, true) then
                partialMatch = ply
            end
        end
    end

    return partialMatch
end

local function findPlayerBySteamId(query)
    if not isstring(query) or query == "" then return nil end
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) then
            if ply:SteamID() == query or ply:SteamID64() == query then
                return ply
            end
        end
    end
    return nil
end

local function resolveFollowTarget(record, args)
    local owner = record.owner
    local targetText = args and (args.target or args.player or args.name or args.steamid)
    if not targetText or targetText == "" then
        return owner
    end

    local lowered = string.Trim(string.lower(tostring(targetText)))
    if lowered == "" or lowered == "owner" or lowered == "self" then
        return owner
    end

    if lowered == "speaker" or lowered == "user" or lowered == "player" then
        if IsValid(record.lastSpeaker) then
            return record.lastSpeaker
        end
        return owner
    end

    local bySteam = findPlayerBySteamId(targetText)
    if IsValid(bySteam) then return bySteam end

    local byName = findPlayerByName(targetText)
    if IsValid(byName) then return byName end

    return owner
end

local function scanNearbyPlayers(record, args)
    if not record or not IsValid(record.npc) then
        return "[]"
    end

    args = args or {}
    local radius = tonumber(args.radius) or 1200
    if radius <= 0 then radius = 1200 end

    local limit = tonumber(args.limit) or 8
    if limit < 1 then limit = 1 end

    local visibleOnly = args.visible_only == true
    local includeOwner = args.include_owner == true

    local origin = record.npc:GetPos()
    local results = {}
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() then
            if includeOwner or record.owner ~= ply then
                local dist = origin:Distance(ply:GetPos())
                if dist <= radius then
                    local visible = record.npc:Visible(ply)
                    if not visibleOnly or visible then
                        table.insert(results, {
                            name = ply:Nick(),
                            steamid = ply:SteamID(),
                            steamid64 = ply:SteamID64(),
                            distance = math.floor(dist),
                            visible = visible,
                            is_owner = record.owner == ply
                        })
                    end
                end
            end
        end
    end

    table.sort(results, function(a, b)
        return a.distance < b.distance
    end)

    local trimmed = {}
    for i = 1, math.min(#results, limit) do
        trimmed[i] = results[i]
    end

    return util.TableToJSON(trimmed) or "[]"
end

local function executeToolCall(record, toolName, args)
    if toolName == "follow_player" then
        local target = resolveFollowTarget(record, args or {})
        local desiredDistance = tonumber(args.distance)
        if desiredDistance ~= nil and desiredDistance <= 0 then
            desiredDistance = nil
        end
        setMovementMode(record, "follow", {
            speed = args.speed,
            distance = desiredDistance
        })
        record.followTarget = target
        if IsValid(target) then
            return "NPC now following " .. target:Nick() .. "."
        end
        return "NPC now following the player."
    end

    if toolName == "wander" then
        setMovementMode(record, "wander", {
            radius = tonumber(args.radius),
            interval = tonumber(args.interval)
        })
        return "NPC now wandering."
    end

    if toolName == "stop_moving" then
        setMovementMode(record, "idle", {})
        return "NPC stopped moving."
    end

    if toolName == "scan_players" then
        return scanNearbyPlayers(record, args or {})
    end

    return "Unknown tool: " .. tostring(toolName)
end

local function updateNPCMovement(record)
    if not record or not IsValid(record.npc) then return end

    local mode = record.moveMode
    if mode == "follow" then
        local target = record.followTarget or record.owner
        if not IsValid(target) then return end

        local now = CurTime()
        local interval = record.moveOptions and record.moveOptions.interval or 0.4
        if record.nextMoveAt and now < record.nextMoveAt then return end
        record.nextMoveAt = now + interval

        local desiredDistance = record.moveOptions and record.moveOptions.distance or 120
        if desiredDistance < 32 then
            desiredDistance = 32
        end

        local npcPos = record.npc:GetPos()
        local targetPos = target:GetPos()
        local offset = targetPos - npcPos
        local dist = offset:Length()
        if dist <= desiredDistance then
            record.npc:SetSchedule(SCHED_IDLE_STAND)
            return
        end

        local approach = targetPos
        if dist > 0 then
            approach = targetPos - offset:GetNormalized() * desiredDistance
        end

        record.npc:SetLastPosition(approach)
        local speed = record.moveOptions and record.moveOptions.speed or "run"
        if speed == "walk" then
            record.npc:SetSchedule(SCHED_FORCED_GO)
        else
            record.npc:SetSchedule(SCHED_FORCED_GO_RUN)
        end
        return
    end

    if mode == "wander" then
        local now = CurTime()
        local interval = record.moveOptions and record.moveOptions.interval or 6
        if record.nextMoveAt and now < record.nextMoveAt then return end
        record.nextMoveAt = now + interval

        local radius = record.moveOptions and record.moveOptions.radius or 600
        local origin = record.npc:GetPos()
        local offset = VectorRand() * radius
        offset.z = 0
        local target = origin + offset

        record.npc:SetLastPosition(target)
        record.npc:SetSchedule(SCHED_FORCED_GO)
    end
end

function AINPCS.HandleNPCSpawn(ply, data)
    if not IsValid(ply) or not istable(data) then
        AINPCS.DebugPrint("Spawn failed: invalid player or data payload")
        return
    end

    local ok, json = pcall(util.TableToJSON, data)
    if ok then
        AINPCS.DebugPrint("Data received: " .. json)
    end

    local apiKey = data["apiKey"] or ""
    local providerId = data["provider"]
    -- Please dont steal our API key, we are poor
    -- TODO Add Encrpytion Decrpytion crap to obfuscate api key
    if apiKey == FREE_API_KEY then
        AINPCS.DebugPrint("Free API key received")
    else
        AINPCS.DebugPrint("API key received: " .. apiKey)
    end

    if apiKey == "" and providerId ~= "ollama" then
        AINPCS.DebugPrint("Spawn failed: missing API key for provider " .. tostring(providerId))
        ply:ChatPrint("Invalid API key.")
        return
    end

    -- Ensure NPCData is provided (fall back to defaults when missing)
    local npcData = data["NPCData"] or data["npcData"]
    if not istable(npcData) then
        AINPCS.DebugPrint("Spawn warning: NPCData missing, falling back to defaults")
        npcData = {}
    end

    -- Fallback to set default class if not present
    local fallbackClass = data.npc_class or data.npc_id or "npc_citizen"
    if not npcData.Class or npcData.Class == "" then
        npcData.Class = fallbackClass
        AINPCS.DebugPrint("Spawn warning: npcData.Class missing, defaulted to " .. tostring(fallbackClass))
    end

    if (not npcData.Model or npcData.Model == "") and isstring(data.npc_model) and data.npc_model ~= "" then
        npcData.Model = data.npc_model
    end

    if not isstring(npcData.Class) or npcData.Class == "" then
        AINPCS.DebugPrint("Spawn failed: npcData.Class invalid (" .. tostring(npcData.Class) .. ")")
        ply:ChatPrint("Error: NPC class invalid.")
        return
    end

    if isstring(npcData.Model) and npcData.Model == "" then
        npcData.Model = nil
    end

    -- Generate a unique key for the NPC
    table.insert(spawnedNPC, {})
    local key = #spawnedNPC

    local record = spawnedNPC[key]
    record.key = key
    record.history = {}
    record.provider = data["provider"]
    record.hostname = data["hostname"]
    record.apiKey = apiKey
    record.usingFreeKey = data["use_free_key"] or apiKey == FREE_API_KEY
    local maxTokens = tonumber(data["max_tokens"])
    record.max_tokens = maxTokens or 2048
    local temperature = tonumber(data["temperature"])
    record.temperature = temperature
    record.reasoning = data["reasoning"]
    record.enableTTS = data["enableTTS"]
    record.model = data["model"]
    record.owner = ply
    record.npcPreset = {
        id = data["npc_id"] or (data.npcPreset and data.npcPreset.id) or npcData.Id,
        class = npcData.Class,
        model = data["npc_model"] or (data.npcPreset and data.npcPreset.model) or npcData.Model,
        name = npcData.Name or npcData.PrintName or npcData.Title or nil
    }
    record.npcData = table.Copy(npcData)
    record.moveMode = "idle"
    record.moveOptions = {}

    local personality = data["personality"]
    AINPCS.DebugPrint("Personality received: " .. tostring(personality))
    record.personalityPrompt = personality
    record.personality = buildPersonalityPrompt(personality)

    -- Calculate spawn position in front of the player
    local spawnPosition = ply:GetEyeTrace().HitPos
    if data.spawnPos and isvector(data.spawnPos) then
        spawnPosition = data.spawnPos
    end

    -- Generate a random angle for the NPC
    local spawnAngle = Angle(0, math.random(0, 360), 0)
    if data.spawnAng and isangle(data.spawnAng) then
        spawnAngle = data.spawnAng
    end

    -- Spawn the selected NPC with the random angle
    AINPCS.DebugPrint("Spawning NPC class: " .. tostring(npcData.Class) .. " model: " .. tostring(npcData.Model))
    record.npc = SpawnNPC(spawnPosition, spawnAngle, npcData, key)

    if record and IsValid(record.npc) then
        AINPCS.DebugPrint("NPC spawned successfully!")

        -- Enable navigation for the NPC
        record.npc:SetNPCState(NPC_STATE_SCRIPT)
        record.npc:SetSchedule(SCHED_IDLE_STAND)

        -- Walk to the player
        record.npc:SetLastPosition(ply:GetPos())
        record.npc:SetSchedule(SCHED_FORCED_GO_RUN)

        ply:sendGPTRequest(key, 'system', record.personality)
    else
        AINPCS.DebugPrint("Spawn failed: SpawnNPC returned invalid entity for class " .. tostring(npcData.Class))
        ply:ChatPrint("Failed to spawn NPC. Check server console for details.")
        table.remove(spawnedNPC, key)
        AINPCS.DebugPrint("Failed to spawn NPC.")
    end
end

function AINPCS.HandleNPCUpdate(ply, ent, data)
    if not istable(data) then data = {} end

    if not IsValid(ent) then
        if IsValid(ply) then
            ply:ChatPrint("No NPC targeted for update.")
        end
        return
    end

    local key, record = findNPCRecordByEntity(ent)
    if not key or not record then
        if IsValid(ply) then
            ply:ChatPrint("That NPC is not managed by AI NPCs.")
        end
        return
    end

    if data.targetKey and data.targetKey ~= key then
        ply:ChatPrint("Selected NPC has changed. Please select it again.")
        return
    end

    if record.owner ~= ply then
        ply:ChatPrint("You do not own this AI NPC.")
        return
    end

    AINPCS.DebugPrint("Updating NPC settings for key " .. tostring(key))
    AINPCS.DebugPrintTable(data)

    record.provider = data.provider or record.provider
    record.hostname = data.hostname or record.hostname

    if record.provider == "ollama" then
        record.usingFreeKey = false
        record.apiKey = data.apiKey or record.apiKey or ""
    else
        record.usingFreeKey = data.use_free_key and true or false
        if record.usingFreeKey then
            record.apiKey = FREE_API_KEY
        elseif data.apiKey and data.apiKey ~= "" then
            record.apiKey = data.apiKey
        end
    end

    local maxTokens = tonumber(data.max_tokens)
    if maxTokens and maxTokens > 0 then
        record.max_tokens = maxTokens
    end

    local temperature = tonumber(data.temperature)
    if temperature then
        record.temperature = temperature
    end

    if data.reasoning ~= nil then
        if data.reasoning == "" then
            record.reasoning = nil
        else
            record.reasoning = data.reasoning
        end
    end

    record.enableTTS = data.enableTTS and true or false
    record.model = data.model or record.model

    local npcData = data.NPCData or data.npcData
    if istable(npcData) then
        record.npcData = table.Copy(npcData)
        if record.npcData.Model and record.npcData.Model ~= "" and IsValid(record.npc) then
            record.npc:SetModel(record.npcData.Model)
        end
    end

    record.npcPreset = record.npcPreset or {}
    if data.npc_id then
        record.npcPreset.id = data.npc_id
    elseif data.npcPreset and data.npcPreset.id then
        record.npcPreset.id = data.npcPreset.id
    end

    if npcData and npcData.Class then
        if IsValid(record.npc) and npcData.Class ~= record.npc:GetClass() then
            ply:ChatPrint("Changing NPC class requires spawning a new NPC.")
        end
        record.npcPreset.class = npcData.Class
    elseif data.npc_class then
        record.npcPreset.class = data.npc_class
    end

    if npcData and npcData.Model then
        record.npcPreset.model = npcData.Model
    elseif data.npc_model then
        record.npcPreset.model = data.npc_model
    end

    if data.npc_model and data.npc_model ~= "" and IsValid(record.npc) then
        record.npc:SetModel(data.npc_model)
    end

    local newPersonality = data.personality or ""
    local personalityChanged = (record.personalityPrompt or "") ~= newPersonality
    record.personalityPrompt = newPersonality
    record.personality = buildPersonalityPrompt(newPersonality)

    if personalityChanged then
        record.history = {}
        ply:sendGPTRequest(key, 'system', record.personality)
    end

    if IsValid(record.npc) then
        local label = record.npcPreset and (record.npcPreset.name or record.npcPreset.id) or record.npc:GetClass()
        if label and label ~= "" then
            record.npc:SetNWString("AINPCS_Name", label)
        end
    end

    ply:ChatPrint("Updated AI NPC settings.")
end

local function clearNPCRecord(key)
    local record = spawnedNPC[key]
    if not record then return end

    local npc = record.npc
    if IsValid(npc) then
        npc:SetNWBool("AINPCS_IsAINPC", false)
        npc:SetNWInt("AINPCS_Key", -1)
        npc:SetNWEntity("AINPCS_Owner", NULL)
    end

    spawnedNPC[key] = nil
end

local function findNPCRecordByEntity(ent)
    if not IsValid(ent) then return nil, nil end

    for key, record in pairs(spawnedNPC) do
        if record and IsValid(record.npc) and record.npc == ent then
            return key, record
        end
    end

    return nil, nil
end

net.Receive("GetNPCModel", function(len, ply)
    local NPCData = net.ReadTable()
    if not istable(NPCData) then return end

    local model

    if not NPCData.Model then
        local class = NPCData.Class
        if not class or class == "" then return end

        local entity = ents.Create(class)
        if not IsValid(entity) then return end
        entity:Spawn()
        
        -- Hide NPC everywhere except inside model panel
        entity:SetSaveValue("m_takedamage", 0)
        entity:SetMoveType(MOVETYPE_NONE)
        entity:SetSolid(SOLID_NONE)
        entity:SetRenderMode(RENDERMODE_TRANSALPHA)
        entity:SetColor(Color(255, 255, 255, 0))

        model = entity:GetModel()
        
        entity:Remove()
    else
        model = NPCData.Model
    end

    if not model or model == "" then return end

    net.Start("RespondNPCModel")
    net.WriteString(model)
    net.Send(ply)
end)

net.Receive("SendNPCInfo", function(len, ply)
    local data = net.ReadTable()
    if AINPCS and AINPCS.HandleNPCSpawn then
        AINPCS.HandleNPCSpawn(ply, data)
    end
end)

net.Receive("AINPCS_RequestNPCSelection", function(_, ply)
    local ent = net.ReadEntity()
    if not IsValid(ent) then
        clearPlayerSelection(ply)
        net.Start("AINPCS_SelectNPCFailed")
        net.WriteString("No NPC targeted.")
        net.Send(ply)
        return
    end

    local key, record = findNPCRecordByEntity(ent)
    if not key or not record then
        clearPlayerSelection(ply)
        net.Start("AINPCS_SelectNPCFailed")
        net.WriteString("That NPC is not managed by AI NPCs.")
        net.Send(ply)
        return
    end

    if record.owner ~= ply then
        clearPlayerSelection(ply)
        net.Start("AINPCS_SelectNPCFailed")
        net.WriteString("You do not own this AI NPC.")
        net.Send(ply)
        return
    end

    ply.AINPCS_SelectedEnt = ent
    ply.AINPCS_SelectedKey = key

    local payload = {
        npcPreset = table.Copy(record.npcPreset or {}),
        personality = record.personalityPrompt or "",
        provider = record.provider,
        hostname = record.hostname,
        model = record.model,
        max_tokens = record.max_tokens,
        temperature = record.temperature,
        reasoning = record.reasoning or "",
        enable_tts = record.enableTTS,
        use_free_key = record.usingFreeKey or false,
        npc_id = record.npcPreset and record.npcPreset.id,
        npc_class = record.npcPreset and record.npcPreset.class,
        npc_model = record.npcPreset and record.npcPreset.model,
        history = table.Copy(record.history or {})
    }

    if not payload.npc_model and IsValid(record.npc) then
        payload.npc_model = record.npc:GetModel()
    end

    if not payload.use_free_key then
        payload.api_key = record.apiKey
    end

    net.Start("AINPCS_SelectNPC")
    net.WriteEntity(ent)
    net.WriteUInt(key, 16)
    net.WriteTable(payload)
    net.Send(ply)
end)

net.Receive("AINPCS_UpdateNPC", function(_, ply)
    local ent = net.ReadEntity()
    local data = net.ReadTable() or {}
    if AINPCS and AINPCS.HandleNPCUpdate then
        AINPCS.HandleNPCUpdate(ply, ent, data)
    end
end)

net.Receive("AINPCS_UpdateNPCMemory", function(_, ply)
    local ent = net.ReadEntity()
    local raw = net.ReadString() or ""

    if not IsValid(ent) then
        if IsValid(ply) then
            ply:ChatPrint("No NPC targeted for memory update.")
        end
        return
    end

    local key, record = findNPCRecordByEntity(ent)
    if not key or not record then
        if IsValid(ply) then
            ply:ChatPrint("That NPC is not managed by AI NPCs.")
        end
        return
    end

    if record.owner ~= ply then
        if IsValid(ply) then
            ply:ChatPrint("You do not own this AI NPC.")
        end
        return
    end

    if raw == "" then
        record.history = {}
        if IsValid(ply) then
            ply:ChatPrint("Cleared AI NPC memory.")
        end
        return
    end

    local decoded = util.JSONToTable(raw)
    if not istable(decoded) or not isSequentialArray(decoded) then
        if IsValid(ply) then
            ply:ChatPrint("Memory update failed: invalid JSON array.")
        end
        return
    end

    record.history = sanitizeHistory(decoded)
    if IsValid(ply) then
        ply:ChatPrint("Updated AI NPC memory.")
    end
end)

-- Define SpawnNPC function
function SpawnNPC(pos, ang, npcData, key)
    if not istable(npcData) then
        AINPCS.DebugPrint("Spawn failed: npcData not a table")
        return
    end
    if not npcData.Class or npcData.Class == "" then
        AINPCS.DebugPrint("Spawn failed: npcData.Class missing")
        return
    end

    local npc = ents.Create(npcData.Class)
    if not IsValid(npc) then
        AINPCS.DebugPrint("Spawn failed: ents.Create returned invalid entity for " .. tostring(npcData.Class))
        return
    end

    npc:SetPos(pos)
    npc:SetAngles(ang)
    npc:Spawn()
    if isstring(npcData.Model) and npcData.Model ~= "" then
        npc:SetModel(npcData.Model)
    end

    npc:SetNWBool("AINPCS_IsAINPC", true)
    npc:SetNWInt("AINPCS_Key", key or -1)

    local record = spawnedNPC[key]
    if record then
        if IsValid(record.owner) then
            npc:SetNWEntity("AINPCS_Owner", record.owner)
        end
        local displayName = npcData.Name or npcData.PrintName or npcData.Class
        if displayName then
            npc:SetNWString("AINPCS_Name", displayName)
        end
    end

    -- Set up a hook for the NPC's death event
    hook.Add("OnNPCKilled", "OnAIDeath_" .. key, function(deadNPC, attacker, inflictor)
        if IsValid(deadNPC) and spawnedNPC[key] and deadNPC == spawnedNPC[key].npc then
            AINPCS.DebugPrint("AI NPC died or was despawned")
            clearNPCRecord(key) -- Remove NPC from list
            hook.Remove("OnNPCKilled", "OnAIDeath_" .. key) -- Remove the hook after processing
        end
    end)

    -- Set up a hook for the NPC's despawn event
    hook.Add("EntityRemoved", "OnAIDespawn_" .. key, function(removedEnt)
        if IsValid(removedEnt) and spawnedNPC[key] and removedEnt == spawnedNPC[key].npc then
            AINPCS.DebugPrint("AI NPC was despawned.")
            clearNPCRecord(key) -- Remove NPC from list
            hook.Remove("EntityRemoved", "OnAIDespawn_" .. key) -- Remove the hook after processing
        end
    end)
    return npc
end

-- Find the metatable for the Player type
local meta = FindMetaTable("Player")

local function appendToolResult(record, toolCallId, content)
    local message = {
        role = "tool",
        content = content or ""
    }
    if toolCallId then
        message.tool_call_id = toolCallId
    end
    table.insert(record.history, message)
end

local function buildToolCallsFromMessage(message)
    if not message then return nil end
    if istable(message.tool_calls) then
        return message.tool_calls
    end
    if istable(message.function_call) then
        return {
            {
                id = "ainpcs_" .. tostring(CurTime()) .. "_" .. tostring(math.random(1000, 9999)),
                type = "function",
                ["function"] = message.function_call
            }
        }
    end
    return nil
end

local function requestProviderWithTools(record, this, depth)
    local ok, provider = pcall(providers.get, record.provider)
    if not ok or not provider or not provider.request then
        ErrorNoHalt("Unsupported provider: " .. tostring(record.provider))
        return
    end

    provider.request(record, function(err, response)
        if not spawnedNPC[record.key] or spawnedNPC[record.key] ~= record then return end
        if err then
            ErrorNoHalt("Error: " .. err)
            return
        end

        local message = response and response.choices and response.choices[1] and response.choices[1].message
        if not message then
            if IsValid(this) then
                this:ChatPrint("Unknown error! Invalid response.")
            end
            return
        end

        local toolCalls = buildToolCallsFromMessage(message)
        if toolCalls and depth < 2 then
            local assistantMessage = {
                role = "assistant",
                content = message.content or ""
            }
            if message.tool_calls then
                assistantMessage.tool_calls = message.tool_calls
            elseif message.function_call then
                assistantMessage.function_call = message.function_call
            end
            table.insert(record.history, assistantMessage)

            for _, call in ipairs(toolCalls) do
                local fn = call["function"] or {}
                local toolName = fn.name or call.name
                local args = parseToolArguments(fn.arguments or call.arguments)
                local toolId = call.id or ("ainpcs_" .. tostring(CurTime()) .. "_" .. tostring(math.random(1000, 9999)))
                local result = executeToolCall(record, toolName, args)
                appendToolResult(record, toolId, result)
            end

            requestProviderWithTools(record, this, depth + 1)
            return
        end

        -- Check if the response contains valid data
        if message.content then
            -- Extract the GPT response content
            local gptResponse = message.content

            table.insert(record.history, {
                role = "assistant",
                content = gptResponse
            })

            -- Print the GPT response to the player's voice chat through tts
            if record.enableTTS and IsValid(record.npc) then
                net.Start("SayTTS")
                net.WriteString(tostring(record.key))
                net.WriteString(gptResponse)
                net.WriteEntity(record.npc)
                net.Broadcast()
            elseif IsValid(this) then
                local text = "[AI]: " .. gptResponse

                local chunks = {}
                local chunkSize = 200

                for i = 1, #text, chunkSize do
                    local startIndex = i
                    local endIndex = math.min(i + chunkSize - 1, #text)
                    table.insert(chunks, text:sub(startIndex, endIndex))
                end

                for _, chunk in ipairs(chunks) do
                    if IsValid(this) then
                        this:ChatPrint(chunk)
                    end
                end
            end
        elseif IsValid(this) then
            this:ChatPrint("Unknown error! Empty response.")
        end
    end)
end

-- Extend the Player metatable to add a custom function for sending requests to GPT-3
meta.sendGPTRequest = function(this, key, author, text)
    local record = spawnedNPC[key]
    if not record then return end
    record.key = key
    if IsValid(this) then
        record.lastSpeaker = this
    end

    record.history = record.history or {}
    table.insert(record.history, {
        role = author,
        content = text
    })
    requestProviderWithTools(record, this, 0)
end

hook.Add("PlayerSay", "PlayerChatHandler", function(ply, text, team)
    local cmd = string.sub(text, 1, 4)
    local txt = string.sub(text, 5)
    if cmd == "/say" then
        ply:ChatPrint("One moment, please...")
        for key, _ in pairs(spawnedNPC) do
            ply:sendGPTRequest(key, 'user', txt) -- Send the player's message to GPT-3
        end
        return ""
    end
end)

hook.Add("Think", "FollowNPCSound", function()
    for k, v in pairs(spawnedNPC) do
        if v then
            updateNPCMovement(v)
        end
        if v and v.enableTTS and IsValid(v.npc) then
            net.Start("TTSPositionUpdate")
            net.WriteString(tostring(k))
            net.WriteVector(v.npc:GetPos())
            net.Broadcast()
        end
    end
end)

-- Reset isAISpawned flag on cleanup
hook.Add("OnCleanup", "ResetAISpawnedFlag", function()
    for key in pairs(spawnedNPC) do
        clearNPCRecord(key)
    end
end)
-- Reset isAISpawned flag on admin cleanup
hook.Add("AdminCleanup", "ResetAISpawnedFlagAdmin", function()
    for key in pairs(spawnedNPC) do
        clearNPCRecord(key)
    end
end)

-- Function to encode the API key
function encode_key(api_key)
    local encoded_key = ""
    for i = 1, #api_key do
        encoded_key = encoded_key .. string.char(string.byte(api_key, i) + 1)
    end
    return encoded_key
end

-- Function to decode the API key
function decode_key(encoded_key)
    local decoded_key = ""
    for i = 1, #encoded_key do
        decoded_key = decoded_key ..
                          string.char(string.byte(encoded_key, i) - 1)
    end
    return decoded_key
end
