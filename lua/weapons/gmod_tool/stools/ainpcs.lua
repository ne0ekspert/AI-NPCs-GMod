AddCSLuaFile()

include("autorun/sh_ainpcs_debug.lua")

TOOL.Category = "AI NPCs"
TOOL.Name = "#tool.ainpcs.name"
TOOL.Command = nil
TOOL.ConfigName = ""
TOOL.Information = {
    { name = "left" },
    { name = "right" },
    { name = "reload" }
}

local FREE_API_KEY = "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"

if CLIENT then
    print("[AINPCS] toolgun script loaded")
end


TOOL.ClientConVar = {
    personality = "",
    provider = "openai",
    hostname = "http://127.0.0.1:11434",
    model = "gpt-4o-mini",
    api_key = "",
    use_free_key = "0",
    enable_tts = "0",
    max_tokens = "2048",
    temperature = "1",
    reasoning = "",
    npc_id = "npc_citizen",
    npc_class = "npc_citizen",
    npc_model = ""
}

TOOL.RequiresTraceHit = true

local function getTableKeys(tbl)
    local keys = {}
    if not istable(tbl) then return keys end
    for k, _ in pairs(tbl) do
        table.insert(keys, k)
    end
    return keys
end

local function isAINPCEntity(ent)
    return IsValid(ent) and ent:IsNPC() and ent:GetNWBool("AINPCS_IsAINPC", false)
end

local function sanitizeNPCData(npcId, fallbackClass, overrideModel)
    local data = {}

    if CLIENT then
        local npcList = list.Get("NPC") or {}
        local original = npcList[npcId]

        if istable(original) then
            data.Class = original.Class or original.Entity or original.Name or npcId
            if not data.Class and isstring(npcId) and npcId ~= "" then
                data.Class = npcId
            end

            if original.Model ~= nil and original.Model ~= "" then
                data.Model = original.Model
            elseif istable(original.KeyValues) and isstring(original.KeyValues.model) and original.KeyValues.model ~= "" then
                data.Model = original.KeyValues.model
            end
        end
    end

    if not data.Class or data.Class == "" then
        if fallbackClass and fallbackClass ~= "" then
            data.Class = fallbackClass
        else
            data.Class = npcId ~= "" and npcId or "npc_citizen"
        end
    end

    if overrideModel and overrideModel ~= "" then
        data.Model = overrideModel
    end

    return data
end

if CLIENT then
    language.Add("tool.ainpcs.name", "AI NPC Spawner")
    language.Add("tool.ainpcs.desc", "Spawn AI-powered NPCs using your configured chat settings")
    language.Add("tool.ainpcs.left", "Spawn an AI NPC with the current settings")
    language.Add("tool.ainpcs.right", "Select an AI NPC to edit its settings")
    language.Add("tool.ainpcs.reload", "Open the AI NPC window")

    TOOL.SelectedNPCKey = nil
    TOOL.SelectedNPCEnt = nil
    TOOL.SelectedNPCData = nil
    TOOL.SelectedNPCMemory = {}

    local providers = include("providers/providers.lua")

    local providerLabels = {
        openai = "OpenAI",
        openrouter = "OpenRouter",
        groq = "Groq",
        ollama = "Ollama"
    }

    local function buildModelChoices(providerId)
        local provider = providers.get(providerId)
        if not provider then return {} end

        local choices = {}

        if istable(provider.modelOrder) then
            for _, key in ipairs(provider.modelOrder) do
                local entry = provider.models and provider.models[key]
                if entry then
                    table.insert(choices, {
                        id = key,
                        label = entry.label or key,
                        settings = entry
                    })
                end
            end
        elseif istable(provider.models) then
            for key, entry in pairs(provider.models) do
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

            table.sort(choices, function(a, b)
                return a.label < b.label
            end)
        end

        return choices
    end

    local function findInitialChoice(choices, wantedId)
        if not wantedId or wantedId == "" then return nil end
        for _, choice in ipairs(choices) do
            if choice.id == wantedId then
                return choice
            end
        end
        return nil
    end

    local function showSelectionNotice(message, isError)
        if notification then
            notification.AddLegacy(message, isError and NOTIFY_ERROR or NOTIFY_HINT, isError and 4 or 3)
        end
        if surface and surface.PlaySound then
            surface.PlaySound(isError and "buttons/button10.wav" or "buttons/button14.wav")
        end
    end

    local function normalizeHistory(raw)
        local normalized = {}
        if not istable(raw) then return normalized end
        if #raw > 0 then
            for _, entry in ipairs(raw) do
                if istable(entry) then
                    table.insert(normalized, entry)
                end
            end
            return normalized
        end
        for _, entry in pairs(raw) do
            if istable(entry) then
                table.insert(normalized, entry)
            end
        end
        return normalized
    end

    local function getActiveTool()
        local ply = LocalPlayer()
        if IsValid(ply) then
            local tool = ply:GetTool("ainpcs")
            if tool then
                return tool
            end
        end
        if TOOL then
            return TOOL
        end
        return nil
    end

    local function updateMemoryUI(tool)
        if not tool or not IsValid(tool.AINPCS_MemoryList) then return end

        local memoryList = tool.AINPCS_MemoryList
        memoryList:Clear()

        local history = tool.SelectedNPCMemory
        if istable(history) then
            for _, entry in ipairs(history) do
                if istable(entry) then
                    local line = memoryList:AddLine(entry.role or "", entry.content or "")
                    line.MemoryEntry = table.Copy(entry)
                end
            end
        end

        local hasSelection = IsValid(tool.SelectedNPCEnt)
        local controls = tool.AINPCS_MemoryControls or {}
        for _, control in ipairs(controls) do
            if IsValid(control) then
                control:SetEnabled(hasSelection)
            end
        end
    end

    function TOOL.BuildCPanel(panel)
        local tool = getActiveTool()
        if tool then
            tool.Panel = panel
        end
        panel:ClearControls()
        panel:Help("Configure the AI NPC then left click to spawn it.")

        local modelPreview = vgui.Create("DModelPanel", panel)
        modelPreview:SetModel(GetConVar("ainpcs_npc_model"):GetString())
        modelPreview:SetFOV(48)
        modelPreview:SetCamPos(Vector(50, 0, 45))
        modelPreview:SetLookAt(Vector(0, 0, 40))
	modelPreview:SetHeight(700)
        modelPreview.LayoutEntity = function(self, ent)
            if not IsValid(ent) then return end
            ent:SetAngles(Angle(0, RealTime() * 30 % 360, 0))
            ent:FrameAdvance(FrameTime())
        end
        panel:AddPanel(modelPreview)

        local npcList = list.Get("NPC") or {}
        local storedModel = GetConVar("ainpcs_npc_model"):GetString()
        if storedModel and storedModel ~= "" then
            modelPreview:SetModel(storedModel)
        end

        local npcSelector = panel:ComboBox("NPC Preset", "ainpcs_npc_id")
        npcSelector:SetSortItems(false)

        local sortedKeys = getTableKeys(npcList)
        table.sort(sortedKeys, function(a, b)
            local nameA = npcList[a] and (npcList[a].Name or a) or a
            local nameB = npcList[b] and (npcList[b].Name or b) or b
            return string.lower(nameA) < string.lower(nameB)
        end)

        local currentNpcId = GetConVar("ainpcs_npc_id"):GetString()
        for _, id in ipairs(sortedKeys) do
            local data = npcList[id]
            if istable(data) then
                data = table.Copy(data)
                data.Id = id
                npcSelector:AddChoice(data.Name or id, data, id == currentNpcId)
            else
                npcSelector:AddChoice(id, { Id = id }, id == currentNpcId)
            end
        end

        local function applyNpcSelection(selection)
            if not istable(selection) then return end

            RunConsoleCommand("ainpcs_npc_id", selection.Id or selection.Class or "npc_citizen")

            if selection.Class and selection.Class ~= "" then
                RunConsoleCommand("ainpcs_npc_class", selection.Class)
            end

            local model = selection.Model
            if not model and istable(selection.KeyValues) then
                model = selection.KeyValues.model
            end

            if model and model ~= "" then
                RunConsoleCommand("ainpcs_npc_model", model)
                if IsValid(modelPreview) then
                    modelPreview:SetModel(model)
                end
            elseif IsValid(modelPreview) then
                modelPreview:SetModel("models/humans/group01/male_07.mdl")
            end
        end

        local selected = npcSelector:GetSelected()
        if selected and selected.Data then
            applyNpcSelection(selected.Data)
        end

        function npcSelector:OnSelect(index, value, data)
            if not istable(data) then return end
            applyNpcSelection(data)
        end

        panel:TextEntry("Override NPC Model", "ainpcs_npc_model")
        panel:Help("Leave empty to use the preset's default model.")

        panel:TextEntry("AI Personality Prompt", "ainpcs_personality")

        local providerCombo = panel:ComboBox("Provider", "ainpcs_provider")
        providerCombo:SetSortItems(false)

        local currentProvider = GetConVar("ainpcs_provider"):GetString()
        for id, label in pairs(providerLabels) do
            providerCombo:AddChoice(label, id, currentProvider == id)
        end

        local apiKeyEntry = panel:TextEntry("API Key", "ainpcs_api_key")
        local freeKeyCheckbox = panel:CheckBox("Use built-in free test key", "ainpcs_use_free_key")
        local ttsCheckbox = panel:CheckBox("Enable text-to-speech", "ainpcs_enable_tts")
        local hostnameEntry = panel:TextEntry("Ollama Hostname", "ainpcs_hostname")
        hostnameEntry:SetEnabled(currentProvider == "ollama")
        hostnameEntry:SetTooltip("Only used with the Ollama provider.")

        local modelCombo = panel:ComboBox("Model", "ainpcs_model")
        local modelTextEntry = panel:TextEntry("Custom Model", "ainpcs_model")

        local function setFormControlVisible(control, isVisible)
            if not IsValid(control) then return end
            control:SetVisible(isVisible)
            if control.Label and IsValid(control.Label) then
                control.Label:SetVisible(isVisible)
            end
        end

        setFormControlVisible(modelTextEntry, false)

        local function setModelConVar(choice)
            if not choice then return end
            RunConsoleCommand("ainpcs_model", choice.id or choice)
        end

        local function applyProviderVisuals(providerId)
            local isOllama = providerId == "ollama"

            hostnameEntry:SetEnabled(isOllama)

            apiKeyEntry:SetDisabled(isOllama and false or freeKeyCheckbox:GetChecked())
            freeKeyCheckbox:SetVisible(not isOllama)

            if isOllama and freeKeyCheckbox:GetChecked() then
                freeKeyCheckbox:SetChecked(false)
            end
        end

        local maxTokensSlider = panel:NumSlider("Max Tokens", "ainpcs_max_tokens", 128, 4096, 0)
        maxTokensSlider:SetDecimals(0)

        local temperatureSlider = panel:NumSlider("Temperature", "ainpcs_temperature", 0, 2, 2)
        temperatureSlider:SetDecimals(2)

        local reasoningEntry = panel:TextEntry("Reasoning Effort", "ainpcs_reasoning")
        reasoningEntry:SetTooltip("Optional. Some models support values like minimal, low, medium, high.")

        local function applyModelSettings(choice)
            if not choice or not choice.settings then return end

            local settings = choice.settings

            if settings.max_tokens then
                local limits = settings.max_tokens
                if limits.min and limits.max then
                    maxTokensSlider:SetMinMax(limits.min, limits.max)
                end
                if limits.default then
                    maxTokensSlider:SetValue(limits.default)
                end
            else
                maxTokensSlider:SetMinMax(128, 4096)
            end

            if settings.temperature then
                local limits = settings.temperature
                if limits.min and limits.max then
                    temperatureSlider:SetMinMax(limits.min, limits.max)
                end
                if limits.default then
                    temperatureSlider:SetValue(limits.default)
                end
            else
                temperatureSlider:SetMinMax(0, 2)
            end

            if settings.reasoning and istable(settings.reasoning) then
                reasoningEntry:SetValue(settings.reasoning[1] or "")
                reasoningEntry:SetTooltip("Supported: " .. table.concat(settings.reasoning, ", "))
            else
                reasoningEntry:SetTooltip("Optional. Some models support values like minimal, low, medium, high.")
            end
        end

        local function populateModels(providerId)
            local choices = buildModelChoices(providerId)
            modelCombo:Clear()

            if #choices == 0 then
                setFormControlVisible(modelCombo, false)
                setFormControlVisible(modelTextEntry, true)
                return
            end

            setFormControlVisible(modelCombo, true)
            setFormControlVisible(modelTextEntry, false)

            local storedId = GetConVar("ainpcs_model"):GetString()
            local initialChoice = findInitialChoice(choices, storedId)

            for _, choice in ipairs(choices) do
                modelCombo:AddChoice(choice.label, choice, initialChoice == choice)
            end

            if initialChoice then
                applyModelSettings(initialChoice)
                setModelConVar(initialChoice)
            else
                local first = choices[1]
                if first then
                    applyModelSettings(first)
                    setModelConVar(first)
                end
            end
        end

        function modelCombo:OnSelect(index, value, data)
            if data then
                setModelConVar(data)
                applyModelSettings(data)
            end
        end

        function providerCombo:OnSelect(index, value, data)
            local providerId = data or value
            RunConsoleCommand("ainpcs_provider", providerId)
            applyProviderVisuals(providerId)
            populateModels(providerId)
        end

        function freeKeyCheckbox:OnChange(val)
            apiKeyEntry:SetDisabled(val)
        end

        applyProviderVisuals(currentProvider)
        populateModels(currentProvider)

        panel:Help("Reload (R) to open the full AI NPC window.")

        panel:Help("Memory (message list). Right click an AI NPC to load it.")
        local memoryList = vgui.Create("DListView", panel)
        memoryList:SetTall(220)
        memoryList:SetMultiSelect(false)
        memoryList:SetSortable(false)
        local roleColumn = memoryList:AddColumn("Role")
        roleColumn:SetFixedWidth(80)
        local contentColumn = memoryList:AddColumn("Content")
        panel:AddItem(memoryList)

        local function addMemoryRow(entry)
            local line = memoryList:AddLine(entry.role or "", entry.content or "")
            line.MemoryEntry = entry
            return line
        end

        local function loadMemoryList()
            updateMemoryUI(getActiveTool())
        end

        local roleCombo = panel:ComboBox("Role")
        roleCombo:SetSortItems(false)
        local roleChoiceIds = {}
        for _, role in ipairs({ "system", "user", "assistant", "tool" }) do
            roleChoiceIds[role] = roleCombo:AddChoice(role)
        end
        roleCombo:ChooseOptionID(roleChoiceIds.user)

        local contentEntry = vgui.Create("DTextEntry", panel)
        contentEntry:SetMultiline(true)
        contentEntry:SetTall(120)
        panel:AddItem(contentEntry)

        local function getSelectedLine()
            local selected = memoryList:GetSelected()
            if not selected or not selected[1] then return nil end
            return selected[1]
        end

        local function rebuildMemoryList(memory, selectIndex)
            memoryList:Clear()
            for _, entry in ipairs(memory) do
                addMemoryRow(entry)
            end
            if selectIndex then
                local lines = memoryList:GetLines() or {}
                local line = lines[selectIndex]
                if line then
                    memoryList:SelectItem(line)
                end
            end
        end

        local function gatherMemory()
            local memory = {}
            for _, line in ipairs(memoryList:GetLines()) do
                local entry = line.MemoryEntry
                if not istable(entry) then
                    entry = {}
                end
                entry.role = line:GetColumnText(1) or entry.role or ""
                entry.content = line:GetColumnText(2) or entry.content or ""
                table.insert(memory, entry)
            end
            return memory
        end

        function memoryList:OnRowSelected(_, line)
            if not IsValid(line) then return end
            local entry = line.MemoryEntry or {}
            local role = entry.role or ""
            if role ~= "" and roleChoiceIds[role] then
                roleCombo:ChooseOptionID(roleChoiceIds[role])
            end
            contentEntry:SetText(entry.content or "")
        end

        local addMessage = panel:Button("Add Message")
        addMessage.DoClick = function()
            local tool = getActiveTool()
            if not tool or not IsValid(tool.SelectedNPCEnt) then
                showSelectionNotice("No AI NPC selected.", true)
                return
            end

            local role = roleCombo:GetValue() or ""
            if role == "" then
                showSelectionNotice("Select a role.", true)
                return
            end

            local entry = {
                role = role,
                content = contentEntry:GetValue() or ""
            }

            local line = addMemoryRow(entry)
            memoryList:SelectItem(line)
        end

        local updateMessage = panel:Button("Update Selected")
        updateMessage.DoClick = function()
            local line = getSelectedLine()
            if not line then
                showSelectionNotice("Select a message to update.", true)
                return
            end

            local role = roleCombo:GetValue() or ""
            if role == "" then
                showSelectionNotice("Select a role.", true)
                return
            end

            line:SetColumnText(1, role)
            line:SetColumnText(2, contentEntry:GetValue() or "")
            line.MemoryEntry = line.MemoryEntry or {}
            line.MemoryEntry.role = role
            line.MemoryEntry.content = line:GetColumnText(2)
        end

        local removeMessage = panel:Button("Remove Selected")
        removeMessage.DoClick = function()
            local line = getSelectedLine()
            if not line then
                showSelectionNotice("Select a message to remove.", true)
                return
            end
            memoryList:RemoveLine(line:GetID())
        end

        local moveUp = panel:Button("Move Up")
        moveUp.DoClick = function()
            local line = getSelectedLine()
            if not line then
                showSelectionNotice("Select a message to move.", true)
                return
            end
            local index = line:GetID()
            if index <= 1 then return end
            local memory = gatherMemory()
            memory[index], memory[index - 1] = memory[index - 1], memory[index]
            rebuildMemoryList(memory, index - 1)
        end

        local moveDown = panel:Button("Move Down")
        moveDown.DoClick = function()
            local line = getSelectedLine()
            if not line then
                showSelectionNotice("Select a message to move.", true)
                return
            end
            local index = line:GetID()
            local memory = gatherMemory()
            if index >= #memory then return end
            memory[index], memory[index + 1] = memory[index + 1], memory[index]
            rebuildMemoryList(memory, index + 1)
        end

        local applyMemory = panel:Button("Apply Memory Edits")
        applyMemory.DoClick = function()
            local tool = getActiveTool()
            if not tool or not IsValid(tool.SelectedNPCEnt) then
                showSelectionNotice("No AI NPC selected.", true)
                return
            end

            local memory = gatherMemory()
            local json = util.TableToJSON(memory, true) or "[]"
            net.Start("AINPCS_UpdateNPCMemory")
            net.WriteEntity(tool.SelectedNPCEnt)
            net.WriteString(json)
            net.SendToServer()
            tool.SelectedNPCMemory = memory
        end

        local tool = getActiveTool()
        local hasSelection = tool and IsValid(tool.SelectedNPCEnt)
        memoryList:SetEnabled(hasSelection)
        roleCombo:SetEnabled(hasSelection)
        contentEntry:SetEnabled(hasSelection)
        addMessage:SetEnabled(hasSelection)
        updateMessage:SetEnabled(hasSelection)
        removeMessage:SetEnabled(hasSelection)
        moveUp:SetEnabled(hasSelection)
        moveDown:SetEnabled(hasSelection)
        applyMemory:SetEnabled(hasSelection)

        if tool then
            tool.AINPCS_MemoryList = memoryList
            tool.AINPCS_MemoryControls = {
                memoryList,
                roleCombo,
                contentEntry,
                addMessage,
                updateMessage,
                removeMessage,
                moveUp,
                moveDown,
                applyMemory
            }
        end

        loadMemoryList()
    end

    function TOOL:ClearSelection()
        self.SelectedNPCKey = nil
        self.SelectedNPCEnt = nil
        self.SelectedNPCData = nil
        self.SelectedNPCMemory = {}
        updateMemoryUI(self)
    end

    local function setToolConVar(name, value, defaultValue)
        local final = value
        if final == nil then final = defaultValue or "" end
        RunConsoleCommand("ainpcs_" .. name, tostring(final))
    end

    local function setToolBool(name, value)
        RunConsoleCommand("ainpcs_" .. name, value and "1" or "0")
    end

    local function refreshControlPanel()
        local tool = getActiveTool()
        if tool and tool.Panel and IsValid(tool.Panel) then
            tool.BuildCPanel(tool.Panel)
        end
    end

    net.Receive("AINPCS_SelectNPC", function()
        local ent = net.ReadEntity()
        local key = net.ReadUInt(16)
        local data = net.ReadTable() or {}

        local ply = LocalPlayer()
        if not IsValid(ply) then return end

        local tool = ply:GetTool("ainpcs")
        if not tool then
            if AINPCS and AINPCS.DebugPrint then
                AINPCS.DebugPrint("AINPCS tool: selection received but tool missing")
            end
            print("[AINPCS] tool selection received but tool missing")
            return
        end

        tool.SelectedNPCKey = key
        tool.SelectedNPCEnt = ent
        tool.SelectedNPCData = data
        local history = nil
        if isstring(data.history_json) and data.history_json ~= "" then
            history = util.JSONToTable(data.history_json)
        end
        if not istable(history) then
            history = data.history
        end
        tool.SelectedNPCMemory = normalizeHistory(history)
        updateMemoryUI(tool)
        if AINPCS and AINPCS.DebugPrint then
            AINPCS.DebugPrint("AINPCS tool: selection received for key " .. tostring(key) ..
                " history size " .. tostring(#tool.SelectedNPCMemory))
        end
        print("[AINPCS] tool selection received for key " .. tostring(key) ..
            " history size " .. tostring(#tool.SelectedNPCMemory))

        local preset = data.npcPreset or {}
        setToolConVar("personality", data.personality, "")
        setToolConVar("provider", data.provider or "openai")
        setToolConVar("hostname", data.hostname, "")
        setToolConVar("model", data.model, "")
        setToolConVar("max_tokens", data.max_tokens, 2048)
        setToolConVar("temperature", data.temperature, 1)
        setToolConVar("reasoning", data.reasoning, "")
        setToolBool("enable_tts", data.enable_tts)
        setToolBool("use_free_key", data.use_free_key)

        if data.use_free_key then
            RunConsoleCommand("ainpcs_api_key", "")
        elseif data.api_key then
            RunConsoleCommand("ainpcs_api_key", data.api_key)
        end

        local npcId = data.npc_id or preset.id or ""
        setToolConVar("npc_id", npcId)
        setToolConVar("npc_class", data.npc_class or preset.class or (IsValid(ent) and ent:GetClass()) or "npc_citizen")

        local modelValue = data.npc_model or preset.model or (IsValid(ent) and ent:GetModel()) or "models/humans/group01/male_07.mdl"
        setToolConVar("npc_model", modelValue)

        refreshControlPanel()

        local label = "AI NPC"
        if IsValid(ent) then
            if ent.GetNWString then
                label = ent:GetNWString("AINPCS_Name", ent:GetClass())
            else
                label = ent:GetClass()
            end
        end

        showSelectionNotice("Selected AI NPC: " .. label)
    end)

    net.Receive("AINPCS_SelectNPCFailed", function()
        local reason = net.ReadString() or "Unable to select AI NPC."

        local ply = LocalPlayer()
        if not IsValid(ply) then return end

        local tool = ply:GetTool("ainpcs")
        if tool and tool.ClearSelection then
            tool:ClearSelection()
            updateMemoryUI(tool)
        end

        if AINPCS and AINPCS.DebugPrint then
            AINPCS.DebugPrint("AINPCS tool: selection failed: " .. tostring(reason))
        end
        print("[AINPCS] tool selection failed: " .. tostring(reason))
        showSelectionNotice(reason ~= "" and reason or "Unable to select AI NPC.", true)
    end)
end

local function buildRequestBody(self, trace)
    local owner = self:GetOwner()
    if not IsValid(owner) then return nil end

    local provider = self:GetClientInfo("provider")
    local apiKey = self:GetClientInfo("api_key")
    local useFreeKey = self:GetClientNumber("use_free_key") == 1

    if provider == "ollama" then
        -- Ollama treats the API key as optional
        apiKey = apiKey or ""
        useFreeKey = false
    elseif useFreeKey then
        apiKey = FREE_API_KEY
    end

    local npcId = self:GetClientInfo("npc_id")
    local npcClass = self:GetClientInfo("npc_class")
    local npcModel = self:GetClientInfo("npc_model")

    local npcData = sanitizeNPCData(npcId, npcClass, npcModel)

    local requestBody = {
        apiKey = apiKey,
        hostname = self:GetClientInfo("hostname"),
        personality = self:GetClientInfo("personality"),
        NPCData = npcData,
        enableTTS = self:GetClientNumber("enable_tts") == 1,
        provider = provider,
        model = self:GetClientInfo("model"),
        max_tokens = math.floor(self:GetClientNumber("max_tokens")),
        temperature = tonumber(self:GetClientInfo("temperature")),
        use_free_key = useFreeKey,
        npcPreset = {
            id = npcId,
            class = npcData.Class or npcClass,
            model = npcModel
        },
        npc_id = npcId,
        npc_class = npcData.Class or npcClass,
        npc_model = npcModel,
        spawnPos = trace.HitNormal and (trace.HitPos + trace.HitNormal * 32) or trace.HitPos,
        spawnAng = Angle(0, owner:EyeAngles().y, 0)
    }

    local reasoning = self:GetClientInfo("reasoning")
    if reasoning ~= "" then
        requestBody.reasoning = reasoning
    end

    return requestBody
end

function TOOL:LeftClick(trace)
    if CLIENT then
        if not trace.Hit then return false end

        local selectedEnt = self.SelectedNPCEnt
        if IsValid(selectedEnt) and not isAINPCEntity(selectedEnt) then
            if self.ClearSelection then
                self:ClearSelection()
            end
        elseif not IsValid(selectedEnt) and self.SelectedNPCKey then
            self:ClearSelection()
        end
        return true
    end

    if not trace.Hit then return false end

    local requestBody = buildRequestBody(self, trace)
    if not requestBody then return false end

    local owner = self:GetOwner()
    if not IsValid(owner) then return false end

    if IsValid(trace.Entity) and isAINPCEntity(trace.Entity) and
        IsValid(owner.AINPCS_SelectedEnt) and owner.AINPCS_SelectedEnt == trace.Entity and owner.AINPCS_SelectedKey then
        requestBody.targetKey = owner.AINPCS_SelectedKey
        requestBody.isUpdate = true

        if AINPCS and AINPCS.HandleNPCUpdate then
            AINPCS.HandleNPCUpdate(owner, trace.Entity, requestBody)
        end
        return true
    end

    if AINPCS and AINPCS.HandleNPCSpawn then
        AINPCS.HandleNPCSpawn(owner, requestBody)
    end

    return true
end

function TOOL:RightClick(trace)
    if CLIENT then
        print("[AINPCS] tool right-click trace hit " .. tostring(trace.Hit) ..
            " ent " .. tostring(trace.Entity) ..
            " isnpc " .. tostring(IsValid(trace.Entity) and trace.Entity:IsNPC()) ..
            " isainpc " .. tostring(IsValid(trace.Entity) and trace.Entity:GetNWBool("AINPCS_IsAINPC", false)))
        if not trace.Hit or not IsValid(trace.Entity) then return false end

        if not isAINPCEntity(trace.Entity) then
            print("[AINPCS] tool right-click rejected: not an AI NPC")
            if self.ClearSelection then
                self:ClearSelection()
            end
            return false
        end

        return true
    end

    print("[AINPCS] tool right-click server trace hit " .. tostring(trace.Hit) ..
        " ent " .. tostring(trace.Entity))
    if not trace.Hit or not IsValid(trace.Entity) then return false end

    local owner = self:GetOwner()
    if not IsValid(owner) then return false end

    if AINPCS and AINPCS.HandleNPCSelection then
        AINPCS.HandleNPCSelection(owner, trace.Entity)
    else
        print("[AINPCS] tool right-click server missing HandleNPCSelection")
    end
    return true
end

function TOOL:Reload(trace)
    if CLIENT and drawaihud then
        drawaihud()
    end
    return true
end

function TOOL:Holster()
    if CLIENT and self.ClearSelection then
        self:ClearSelection()
    end
    return true
end
