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
    frame:SetSize(960, 580) -- Expand the frame for the new column layout
    frame:SetTitle("Character Selection") -- Set the title of the frame
    frame:Center() -- Center the frame on the screen
    frame:MakePopup() -- Make the frame a popup
    frame:SetDraggable(true) -- Make the frame draggable
    frame:SetBackgroundBlur(true) -- Enable background blur 
    frame:SetScreenLock(true) -- Lock the mouse to the frame
    frame:SetIcon("materials/gptlogo/ChatGPT_logo.svg.png") -- Set the icon of the frame

    local labelColor = Color(255, 255, 255)

    local contentPanel = vgui.Create("DPanel", frame)
    contentPanel:Dock(FILL)
    contentPanel:DockPadding(10, 10, 10, 10)
    contentPanel.Paint = nil

    local modelColumn = vgui.Create("DPanel", contentPanel)
    modelColumn:Dock(LEFT)
    modelColumn:SetWide(220)
    modelColumn:DockMargin(0, 0, 10, 0)
    modelColumn:DockPadding(10, 10, 10, 10)
    modelColumn.Paint = nil

    local modelHeader = vgui.Create("DLabel", modelColumn)
    modelHeader:SetText("3D model view")
    modelHeader:SetFont("Trebuchet24")
    modelHeader:SetContentAlignment(4)
    modelHeader:Dock(TOP)
    modelHeader:SetTall(24)
    modelHeader:DockMargin(0, 0, 0, 8)
    modelHeader:SetTextColor(labelColor)

    modelPanel = vgui.Create("DModelPanel", modelColumn)
    modelPanel:Dock(FILL)
    modelPanel:SetModel("models/humans/group01/male_07.mdl")
    modelPanel:SetFOV(48)
    modelPanel.LayoutEntity = function(self, ent)
        self:RunAnimation()
        ent:SetAngles(Angle(0, RealTime() * 100, 0))
    end

    local function createColumn(title, width, marginRight)
        local container = vgui.Create("DPanel", contentPanel)
        container:Dock(LEFT)
        container:SetWide(width)
        container:DockMargin(0, 0, marginRight or 10, 0)
        container:DockPadding(10, 10, 10, 10)
        container.Paint = nil

        local header = vgui.Create("DLabel", container)
        header:SetText(title)
        header:SetFont("Trebuchet24")
        header:SetContentAlignment(4)
        header:Dock(TOP)
        header:SetTall(24)
        header:DockMargin(0, 0, 0, 8)
        header:SetTextColor(labelColor)

        local body = vgui.Create("DScrollPanel", container)
        body:Dock(FILL)
        body:SetPaintBackground(false)

        return body
    end

    local personalityBody = createColumn("AI Personality", 220)
    local providerBody = createColumn("Model selector", 220)
    local settingsBody = createColumn("Model settings", 240, 0)

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
    local nameLabel = personalityBody:Add("DLabel")
    nameLabel:SetText("AI Personality:")
    nameLabel:SetContentAlignment(4)
    nameLabel:SetTall(20)
    nameLabel:Dock(TOP)
    nameLabel:DockMargin(0, 0, 0, 4)
    nameLabel:SetTextColor(labelColor)

    local aiLinkEntry = personalityBody:Add("DTextEntry")
    aiLinkEntry:Dock(TOP)
    aiLinkEntry:SetTall(48)
    aiLinkEntry:DockMargin(0, 0, 0, 12)

    -- Provider selection
    local providerLabel = providerBody:Add("DLabel")
    providerLabel:SetText("Provider:")
    providerLabel:SetContentAlignment(4)
    providerLabel:SetTall(20)
    providerLabel:Dock(TOP)
    providerLabel:DockMargin(0, 0, 0, 4)
    providerLabel:SetTextColor(labelColor)

    providerDropdown = providerBody:Add("DComboBox")
    providerDropdown:Dock(TOP)
    providerDropdown:SetTall(24)
    providerDropdown:DockMargin(0, 0, 0, 12)
    providerDropdown:AddChoice("OpenAI", "openai", true)
    providerDropdown:AddChoice("OpenRouter", "openrouter")
    providerDropdown:AddChoice("Groq", "groq")
    providerDropdown:AddChoice("Ollama", "ollama")

    -- Hostname entry
    local hostnameLabel = providerBody:Add("DLabel")
    hostnameLabel:SetText("Hostname:")
    hostnameLabel:SetContentAlignment(4)
    hostnameLabel:SetTall(20)
    hostnameLabel:Dock(TOP)
    hostnameLabel:DockMargin(0, 0, 0, 4)
    hostnameLabel:SetTextColor(labelColor)

    local hostnameEntry = providerBody:Add("DTextEntry")
    hostnameEntry:Dock(TOP)
    hostnameEntry:SetTall(24)
    hostnameEntry:DockMargin(0, 0, 0, 12)

    -- Model selection or input
    local modelLabel = providerBody:Add("DLabel")
    modelLabel:SetText("Model:")
    modelLabel:SetContentAlignment(4)
    modelLabel:SetTall(20)
    modelLabel:Dock(TOP)
    modelLabel:DockMargin(0, 0, 0, 4)
    modelLabel:SetTextColor(labelColor)

    modelDropdown = providerBody:Add("DComboBox")
    modelDropdown:Dock(TOP)
    modelDropdown:SetTall(24)
    modelDropdown:DockMargin(0, 0, 0, 8)

    modelTextEntry = providerBody:Add("DTextEntry")
    modelTextEntry:Dock(TOP)
    modelTextEntry:SetTall(24)
    modelTextEntry:DockMargin(0, 0, 0, 8)
    modelTextEntry:SetVisible(false)

    -- NPC selection
    local npcLabel = providerBody:Add("DLabel")
    npcLabel:SetText("Select NPC:")
    npcLabel:SetContentAlignment(4)
    npcLabel:SetTall(20)
    npcLabel:Dock(TOP)
    npcLabel:DockMargin(0, 12, 0, 4)
    npcLabel:SetTextColor(labelColor)

    local npcDropdown = providerBody:Add("DComboBox")
    npcDropdown:Dock(TOP)
    npcDropdown:SetTall(24)
    npcDropdown:DockMargin(0, 0, 0, 12)
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
    local apiKeyLabel = settingsBody:Add("DLabel")
    apiKeyLabel:SetText("API Key:")
    apiKeyLabel:SetContentAlignment(4)
    apiKeyLabel:SetTall(20)
    apiKeyLabel:Dock(TOP)
    apiKeyLabel:DockMargin(0, 0, 0, 4)
    apiKeyLabel:SetTextColor(labelColor)

    local apiKeyEntry = settingsBody:Add("DTextEntry")
    apiKeyEntry:Dock(TOP)
    apiKeyEntry:SetTall(24)
    apiKeyEntry:DockMargin(0, 0, 0, 12)
    apiKeyEntry:SetText(inputapikey)

    -- Free API toggle
    local freeAPIButton = settingsBody:Add("DCheckBoxLabel")
    freeAPIButton:SetText("Free API")
    freeAPIButton:SetTall(20)
    freeAPIButton:Dock(TOP)
    freeAPIButton:DockMargin(0, 0, 0, 8)
    freeAPIButton:SetTextColor(labelColor)
    freeAPIButton.OnChange = function(self, value)
        apiKeyEntry:SetText(value and "" or apiKeyEntry:GetText())
        apiKeyEntry:SetEditable(not value)
    end

    -- Text-to-speech toggle
    local TTSButton = settingsBody:Add("DCheckBoxLabel")
    TTSButton:SetText("Text to Speech")
    TTSButton:SetTall(20)
    TTSButton:Dock(TOP)
    TTSButton:DockMargin(0, 0, 0, 12)
    TTSButton:SetValue(0)
    TTSButton:SetTextColor(labelColor)

    -- Generation controls
    maxTokensSlider = settingsBody:Add("DNumSlider")
    maxTokensSlider:SetText("Max Tokens")
    maxTokensSlider.Label:SetTextColor(labelColor)
    maxTokensSlider:SetTall(48)
    maxTokensSlider:Dock(TOP)
    maxTokensSlider:DockMargin(0, 0, 0, 12)
    maxTokensSlider:SetMin(128)
    maxTokensSlider:SetMax(4096)
    maxTokensSlider:SetDecimals(0)
    maxTokensSlider:SetValue(2048)

    temperatureSlider = settingsBody:Add("DNumSlider")
    temperatureSlider:SetText("Temperature")
    temperatureSlider.Label:SetTextColor(labelColor)
    temperatureSlider:SetTall(48)
    temperatureSlider:Dock(TOP)
    temperatureSlider:DockMargin(0, 0, 0, 12)
    temperatureSlider:SetMin(0)
    temperatureSlider:SetMax(2)
    temperatureSlider:SetDecimals(2)
    temperatureSlider:SetValue(1)

    reasoningLabel = settingsBody:Add("DLabel")
    reasoningLabel:SetText("Reasoning Effort:")
    reasoningLabel:SetContentAlignment(4)
    reasoningLabel:SetTall(20)
    reasoningLabel:Dock(TOP)
    reasoningLabel:DockMargin(0, 12, 0, 4)
    reasoningLabel:SetVisible(false)
    reasoningLabel:SetTextColor(labelColor)

    reasoningDropdown = settingsBody:Add("DComboBox")
    reasoningDropdown:Dock(TOP)
    reasoningDropdown:SetTall(24)
    reasoningDropdown:DockMargin(0, 0, 0, 12)
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
    local createButton = settingsBody:Add("DButton")
    createButton:SetText("Create NPC")
    createButton:SetTall(60)
    createButton:Dock(TOP)
    createButton:DockMargin(0, 20, 0, 0)
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
