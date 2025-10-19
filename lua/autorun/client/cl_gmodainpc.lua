local providers = include('providers/providers.lua')

-- Context menu button
local inputapikey = ""
list.Set("DesktopWindows", "ai_menu", {
    title = "AI NPCs",
    icon = "materials/gptlogo/ChatGPT_logo.svg.png",
    init = function(icon, window) drawaihud() end
})

local modelPanel
function drawaihud()
    local frame = vgui.Create("DFrame") -- Create a frame for the character selection panel
    frame:SetSize(460, 580) -- Set the size of the frame with extra space for sliders
    frame:SetTitle("Character Selection") -- Set the title of the frame
    frame:Center() -- Center the frame on the screen
    frame:MakePopup() -- Make the frame a popup
    frame:SetDraggable(true) -- Make the frame draggable
    frame:SetBackgroundBlur(true) -- Enable background blur 
    frame:SetScreenLock(true) -- Lock the mouse to the frame
    frame:SetIcon("materials/gptlogo/ChatGPT_logo.svg.png") -- Set the icon of the frame

    -- Left: 3D model display
    modelPanel = vgui.Create("DModelPanel", frame)
    modelPanel:Dock(LEFT)
    modelPanel:SetSize(220, 0)
    modelPanel:SetModel("models/humans/group01/male_07.mdl")
    modelPanel:SetFOV(48)
    modelPanel.LayoutEntity = function(self, ent)
        self:RunAnimation()
        ent:SetAngles(Angle(0, RealTime() * 100, 0))
    end

    -- Right: Controls
    local rightPanel = vgui.Create("DPanel", frame)
    rightPanel:Dock(FILL)
    rightPanel:SetBackgroundColor(Color(116, 170, 156))

    local currentProviderId = "openai"
    local currentProviderData = nil
    local currentModelChoice = nil
    local currentReasoningChoice = nil

    local defaultLimits = {
        max_tokens = { min = 128, max = 4096, default = 2048 },
        temperature = { min = 0, max = 2, default = 1 },
    }

    local providerDropdown
    local modelDropdown
    local modelTextEntry
    local maxTokensSlider
    local temperatureSlider
    local reasoningLabel
    local reasoningDropdown

    -- AI Personality
    local nameLabel = vgui.Create("DLabel", rightPanel)
    nameLabel:SetText("AI Personality:")
    nameLabel:SetPos(10, 10)
    nameLabel:SetSize(170, 20)
    local aiLinkEntry = vgui.Create("DTextEntry", rightPanel)
    aiLinkEntry:SetPos(10, 30)
    aiLinkEntry:SetSize(170, 20)

    -- Provider selection
    local providerLabel = vgui.Create("DLabel", rightPanel)
    providerLabel:SetText("Provider:")
    providerLabel:SetPos(10, 60)
    providerDropdown = vgui.Create("DComboBox", rightPanel)
    providerDropdown:SetPos(10, 80)
    providerDropdown:SetSize(170, 20)
    providerDropdown:AddChoice("OpenAI", "openai", true)
    providerDropdown:AddChoice("OpenRouter", "openrouter")
    providerDropdown:AddChoice("Groq", "groq")
    providerDropdown:AddChoice("Ollama", "ollama")

    -- Hostname entry
    local hostnameLabel = vgui.Create("DLabel", rightPanel)
    hostnameLabel:SetText("Hostname:")
    hostnameLabel:SetPos(10, 110)
    local hostnameEntry = vgui.Create("DTextEntry", rightPanel)
    hostnameEntry:SetPos(10, 130)
    hostnameEntry:SetSize(170, 20)

    -- Model selection or input
    local modelLabel = vgui.Create("DLabel", rightPanel)
    modelLabel:SetText("Model:")
    modelLabel:SetPos(10, 160)
    modelDropdown = vgui.Create("DComboBox", rightPanel)
    modelDropdown:SetPos(10, 180)
    modelDropdown:SetSize(170, 20)
    modelTextEntry = vgui.Create("DTextEntry", rightPanel)
    modelTextEntry:SetPos(10, 180)
    modelTextEntry:SetSize(170, 20)
    modelTextEntry:SetVisible(false)

    -- NPC selection
    local npcLabel = vgui.Create("DLabel", rightPanel)
    npcLabel:SetText("Select NPC:")
    npcLabel:SetPos(10, 210)
    local npcDropdown = vgui.Create("DComboBox", rightPanel)
    npcDropdown:SetPos(10, 230)
    npcDropdown:SetSize(170, 20)
    npcDropdown:SetValue("npc_citizen")
    local selectedNPCData
    function npcDropdown:OnSelect(index, value, data)
        selectedNPCData = data
        net.Start("GetNPCModel")
        net.WriteTable(data)
        net.SendToServer()
    end
    for npcId, npcData in pairs(list.Get("NPC")) do
        npcData.Id = npcId
        npcDropdown:AddChoice(npcId, npcData)
    end
    npcDropdown:ChooseOptionID(1)
    if not selectedNPCData then
        local selectedPanel = npcDropdown:GetSelected()
        selectedNPCData = selectedPanel and selectedPanel.Data
    end

    -- API key
    local apiKeyLabel = vgui.Create("DLabel", rightPanel)
    apiKeyLabel:SetText("API Key:")
    apiKeyLabel:SetPos(10, 260)
    local apiKeyEntry = vgui.Create("DTextEntry", rightPanel)
    apiKeyEntry:SetPos(10, 280)
    apiKeyEntry:SetSize(170, 20)
    apiKeyEntry:SetText(inputapikey)

    -- Free API toggle
    local freeAPIButton = vgui.Create("DCheckBoxLabel", rightPanel)
    freeAPIButton:SetText("Free API")
    freeAPIButton:SetPos(10, 310)
    freeAPIButton:SetSize(170, 20)
    freeAPIButton.OnChange = function(self, value)
        apiKeyEntry:SetText(value and "" or apiKeyEntry:GetText())
        apiKeyEntry:SetEditable(not value)
    end

    -- Text-to-speech toggle
    local TTSButton = vgui.Create("DCheckBoxLabel", rightPanel)
    TTSButton:SetText("Text to Speech")
    TTSButton:SetPos(10, 330)
    TTSButton:SetSize(210, 20)
    TTSButton:SetValue(0)

    -- Generation controls
    maxTokensSlider = vgui.Create("DNumSlider", rightPanel)
    maxTokensSlider:SetText("Max Tokens")
    maxTokensSlider:SetPos(10, 360)
    maxTokensSlider:SetSize(210, 40)
    maxTokensSlider:SetMin(128)
    maxTokensSlider:SetMax(4096)
    maxTokensSlider:SetDecimals(0)
    maxTokensSlider:SetValue(2048)

    temperatureSlider = vgui.Create("DNumSlider", rightPanel)
    temperatureSlider:SetText("Temperature")
    temperatureSlider:SetPos(10, 400)
    temperatureSlider:SetSize(210, 40)
    temperatureSlider:SetMin(0)
    temperatureSlider:SetMax(2)
    temperatureSlider:SetDecimals(2)
    temperatureSlider:SetValue(1)

    reasoningLabel = vgui.Create("DLabel", rightPanel)
    reasoningLabel:SetText("Reasoning Effort:")
    reasoningLabel:SetPos(10, 440)
    reasoningLabel:SetSize(210, 20)
    reasoningLabel:SetVisible(false)

    reasoningDropdown = vgui.Create("DComboBox", rightPanel)
    reasoningDropdown:SetPos(10, 460)
    reasoningDropdown:SetSize(210, 20)
    reasoningDropdown:SetVisible(false)

    local function toTitleCase(value)
        if not value or value == "" then return "" end
        return string.upper(string.sub(value, 1, 1)) .. string.sub(value, 2)
    end

    local function clampValue(value, minValue, maxValue)
        if value == nil then
            if minValue and maxValue then
                return math.Clamp((minValue + maxValue) * 0.5, minValue, maxValue)
            end
            return minValue or maxValue or 0
        end

        if minValue and value < minValue then value = minValue end
        if maxValue and value > maxValue then value = maxValue end
        return value
    end

    local function applyMaxTokens(range)
        local limits = range or defaultLimits.max_tokens
        local minValue = limits.min or defaultLimits.max_tokens.min
        local maxValue = limits.max or defaultLimits.max_tokens.max
        local defaultValue = limits.default or defaultLimits.max_tokens.default

        maxTokensSlider:SetMin(minValue)
        maxTokensSlider:SetMax(maxValue)
        maxTokensSlider:SetDecimals(0)

        local currentValue = maxTokensSlider:GetValue()
        if currentValue < minValue or currentValue > maxValue then
            currentValue = defaultValue
        end
        maxTokensSlider:SetValue(clampValue(currentValue, minValue, maxValue))
    end

    local function applyTemperature(range)
        local limits = range or defaultLimits.temperature
        local minValue = limits.min or defaultLimits.temperature.min
        local maxValue = limits.max or defaultLimits.temperature.max
        local defaultValue = limits.default or defaultLimits.temperature.default
        local decimals = limits.decimals or 2

        temperatureSlider:SetMin(minValue)
        temperatureSlider:SetMax(maxValue)
        temperatureSlider:SetDecimals(decimals)

        local currentValue = temperatureSlider:GetValue()
        if currentValue < minValue or currentValue > maxValue then
            currentValue = defaultValue
        end
        temperatureSlider:SetValue(clampValue(currentValue, minValue, maxValue))

        local locked = minValue == maxValue
        temperatureSlider:SetVisible(not locked)
        temperatureSlider:SetEnabled(not locked)
        if locked then
            temperatureSlider:SetValue(minValue)
        end
    end

    local function applyReasoning(options)
        if istable(options) and #options > 0 then
            reasoningLabel:SetVisible(true)
            reasoningDropdown:SetVisible(true)
            reasoningDropdown:Clear()

            local matched = false
            for idx, effort in ipairs(options) do
                local label = toTitleCase(effort)
                reasoningDropdown:AddChoice(label, effort)
                if effort == currentReasoningChoice then
                    reasoningDropdown:ChooseOptionID(idx)
                    matched = true
                end
            end

            if not matched then
                reasoningDropdown:ChooseOptionID(1)
                local selectedPanel = reasoningDropdown:GetSelected()
                currentReasoningChoice = selectedPanel and selectedPanel.Data or options[1]
            end
        else
            reasoningLabel:SetVisible(false)
            reasoningDropdown:SetVisible(false)
            reasoningDropdown:Clear()
            currentReasoningChoice = nil
        end
    end

    local function applyModelSettings(choice)
        currentModelChoice = choice
        local info = choice and choice.settings or nil
        applyMaxTokens(info and info.max_tokens or nil)
        applyTemperature(info and info.temperature or nil)
        applyReasoning(info and info.reasoning or nil)
    end

    local function buildModelChoices(providerData)
        local choices = {}
        if not providerData then return choices end

        if providerData.modelOrder and providerData.models then
            for _, key in ipairs(providerData.modelOrder) do
                local info = providerData.models[key]
                if info then
                    table.insert(choices, {
                        id = key,
                        label = info.label or key,
                        settings = info
                    })
                end
            end
            return choices
        end

        if istable(providerData.models) then
            if #providerData.models > 0 then
                for _, entry in ipairs(providerData.models) do
                    if isstring(entry) then
                        table.insert(choices, { id = entry, label = entry })
                    elseif istable(entry) then
                        local id = entry.id or entry.name or entry.label
                        if id then
                            table.insert(choices, {
                                id = id,
                                label = entry.label or id,
                                settings = entry
                            })
                        end
                    end
                end
            else
                for key, entry in pairs(providerData.models) do
                    if istable(entry) then
                        table.insert(choices, {
                            id = key,
                            label = entry.label or key,
                            settings = entry
                        })
                    elseif isstring(entry) then
                        table.insert(choices, { id = key, label = entry })
                    end
                end
                table.sort(choices, function(a, b) return a.label < b.label end)
            end
        end

        return choices
    end

    local function populateModels(providerId)
        currentProviderData = providers.get(providerId)
        modelDropdown:Clear()

        local choices = currentProviderData and buildModelChoices(currentProviderData) or {}
        if #choices > 0 then
            modelDropdown:SetVisible(true)
            modelTextEntry:SetVisible(false)
            for _, choice in ipairs(choices) do
                modelDropdown:AddChoice(choice.label, choice)
            end
            modelDropdown:ChooseOptionID(1)
        else
            modelDropdown:SetVisible(false)
            modelTextEntry:SetVisible(true)
            modelTextEntry:SetValue("")
            applyModelSettings(nil)
        end
    end

    function providerDropdown:OnSelect(index, value, data)
        currentProviderId = data or value
        if currentProviderId == "ollama" then
            hostnameEntry:SetEditable(true)
        else
            hostnameEntry:SetEditable(false)
        end
        populateModels(currentProviderId)
    end

    function modelDropdown:OnSelect(index, value, data)
        if istable(data) then
            applyModelSettings(data)
        else
            applyModelSettings({ id = value })
        end
    end

    function reasoningDropdown:OnSelect(index, value, data)
        currentReasoningChoice = data or value
    end

    hostnameEntry:SetEditable(false)
    populateModels(currentProviderId)

    -- Create NPC button
    local createButton = vgui.Create("DButton", rightPanel)
    createButton:SetText("Create NPC")
    createButton:SetPos(10, 500)
    createButton:SetSize(210, 60)
    createButton.DoClick = function()
        inputapikey = apiKeyEntry:GetValue()
        local APIKEY = freeAPIButton:GetChecked() and
            "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" or
            apiKeyEntry:GetValue()

        local selectedNPCPanel = npcDropdown:GetSelected()
        local selectedNPC = selectedNPCPanel and selectedNPCPanel.Data or selectedNPCData

        local chosenModel
        if modelDropdown:IsVisible() then
            chosenModel = currentModelChoice and currentModelChoice.id or modelDropdown:GetValue()
        else
            chosenModel = modelTextEntry:GetValue()
        end

        local requestBody = {
            apiKey = APIKEY,
            hostname = hostnameEntry:GetValue(),
            personality = aiLinkEntry:GetValue(),
            NPCData = selectedNPC,
            enableTTS = TTSButton:GetChecked(),
            provider = currentProviderId,
            model = chosenModel,
            max_tokens = math.floor(maxTokensSlider:GetValue()),
        }

        if temperatureSlider:IsVisible() then
            requestBody.temperature = temperatureSlider:GetValue()
        end

        PrintTable(requestBody)
        net.Start("SendNPCInfo")
        net.WriteTable(requestBody)
        net.SendToServer()
    end
end

local soundList = {}

net.Receive("RespondNPCModel", function()
    local modelPath = net.ReadString()
    if modelPanel and IsValid(modelPanel) then
        modelPanel:SetModel(modelPath)
    end
end)

-- TODO Convert this to serverside code so that audio can changed to follow NPC
net.Receive("SayTTS", function()
    local key = net.ReadString()
    local text = net.ReadString() -- Read the TTS text from the network
    local ply = net.ReadEntity() -- Read the player entity from the network
    text = string.sub(string.Replace(text, " ", "%20"), 1, 1000) -- Replace spaces with "%20" and limit the text length to 100 characters

    -- Play the TTS sound using the provided URL
    sound.PlayURL(
        "https://tetyys.com/SAPI4/SAPI4?voice=Sam&pitch=100&speed=150&text=" ..
            text, "3d", function(sound)
            if IsValid(sound) then
                sound:SetPos(ply:GetPos()) -- Set the sound position to the player's position
                sound:SetVolume(1) -- Set the sound volume to maximum
                sound:Play() -- Play the sound
                sound:Set3DFadeDistance(200, 1000) -- Set the 3D sound fade distance
                soundList[key] = sound -- Store the sound reference in the player entity
            end
        end)
end)

net.Receive("TTSPositionUpdate", function()
    local key = net.ReadString()
    local pos = net.ReadVector()

    soundList[key]:SetPos(pos)
end)
