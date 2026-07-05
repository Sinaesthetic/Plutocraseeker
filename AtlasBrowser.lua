local ADDON_NAME, Plutocraseeker = ...

Plutocraseeker.AtlasBrowser = Plutocraseeker.AtlasBrowser or {}

local Browser = Plutocraseeker.AtlasBrowser
local ATLAS_MODULE = "AtlasLootClassic_DungeonsAndRaids"
local WowGetItemInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
local WowGetItemIcon = C_Item and C_Item.GetItemIconByID or _G.GetItemIcon
local WowGetItemStats = _G.GetItemStats
local instanceRows = {}
local bossRows = {}
local itemRows = {}
local frame
local filterFrame
local dataCache
local selectedInstance
local selectedBoss
local selectedDifficulty
local contentFilter = "RAID"
local instanceOffset = 0
local bossOffset = 0
local itemOffset = 0
local ScrollList
local StripColor
local SetStatus
local AddNpcId
local NormalizeNpcIDs
local indexBuilder
local indexSearchCache = {}
local requestedItems = {}
local npcIdsByItemCache = {}
local filteredInstancesCache
local filteredBossesCache
local currentItemsCache
local filterRevision = 0
local starRevision = 0
local pendingBrowserItemRefresh = false
local INDEX_VERSION = 2
local INDEX_BATCH_SIZE = 2
local INDEX_TICK_SECONDS = 0.15
local INDEX_STATUS_SECONDS = 0.5
local INDEX_MAX_ATTEMPTS = 6
local TOOLTIP_HOVER_DELAY = 0.25
local BROWSER_WIDTH = 970
local BROWSER_HEIGHT = 520
local SOURCE_PANEL_WIDTH = 260
local ENCOUNTER_PANEL_WIDTH = 220
local ITEM_PANEL_WIDTH = 450
local LIST_PANEL_HEIGHT = 390
local ITEM_ROW_TOP = -66
local ITEM_ROW_WIDTH = ITEM_PANEL_WIDTH - 36

local GEAR_FILTERS = {
    { key = "cloth", label = "Cloth" },
    { key = "leather", label = "Leather" },
    { key = "mail", label = "Mail" },
    { key = "plate", label = "Plate" },
}

local SLOT_FILTERS = {
    { key = "head", label = "Head" },
    { key = "neck", label = "Neck" },
    { key = "shoulder", label = "Shoulder" },
    { key = "back", label = "Back" },
    { key = "chest", label = "Chest" },
    { key = "wrist", label = "Wrist" },
    { key = "hands", label = "Hands" },
    { key = "waist", label = "Waist" },
    { key = "legs", label = "Legs" },
    { key = "feet", label = "Feet" },
    { key = "finger", label = "Finger" },
    { key = "trinket", label = "Trinket" },
    { key = "weapon", label = "Weapon" },
    { key = "offhand", label = "Off Hand" },
    { key = "other", label = "Other" },
}

local PRIMARY_STAT_FILTERS = {
    { key = "strength", label = "Strength", stats = { "ITEM_MOD_STRENGTH_SHORT" } },
    { key = "agility", label = "Agility", stats = { "ITEM_MOD_AGILITY_SHORT" } },
    { key = "intellect", label = "Intellect", stats = { "ITEM_MOD_INTELLECT_SHORT" } },
    { key = "spirit", label = "Spirit", stats = { "ITEM_MOD_SPIRIT_SHORT" } },
}

local SECONDARY_STAT_FILTERS = {
    { key = "hit", label = "Hit", stats = { "ITEM_MOD_HIT_RATING_SHORT" } },
    { key = "crit", label = "Crit", stats = { "ITEM_MOD_CRIT_RATING_SHORT" } },
    { key = "haste", label = "Haste", stats = { "ITEM_MOD_HASTE_RATING_SHORT" } },
    { key = "mastery", label = "Mastery", stats = { "ITEM_MOD_MASTERY_RATING_SHORT" } },
    { key = "expertise", label = "Expertise", stats = { "ITEM_MOD_EXPERTISE_RATING_SHORT" } },
    { key = "dodge", label = "Dodge", stats = { "ITEM_MOD_DODGE_RATING_SHORT" } },
    { key = "parry", label = "Parry", stats = { "ITEM_MOD_PARRY_RATING_SHORT" } },
}

local lootFilters = {
    gear = {},
    slots = {},
    primaryStats = {},
    secondaryStats = {},
}

local colors = {
    bg = { 0.055, 0.065, 0.075, 0.98 },
    panel = { 0.085, 0.095, 0.11, 0.96 },
    row = { 0.065, 0.074, 0.084, 1 },
    hover = { 0.13, 0.16, 0.18, 1 },
    selected = { 0.11, 0.32, 0.28, 1 },
    border = { 0.22, 0.28, 0.30, 1 },
    accent = { 0.31, 0.82, 0.62, 1 },
    text = { 0.9, 0.95, 0.93, 1 },
    muted = { 0.58, 0.66, 0.64, 1 },
    warn = { 0.95, 0.67, 0.28, 1 },
}

local function Template()
    return BackdropTemplateMixin and "BackdropTemplate" or nil
end

local function RegisterEscapeFrame(name)
    if not name or not UISpecialFrames then
        return
    end

    for _, frameName in ipairs(UISpecialFrames) do
        if frameName == name then
            return
        end
    end

    UISpecialFrames[#UISpecialFrames + 1] = name
end

local function ApplyBackdrop(region, color)
    if not region.SetBackdrop then
        return
    end

    region:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    region:SetBackdropColor(unpack(color or colors.panel))
    region:SetBackdropBorderColor(unpack(colors.border))
end

local function SetBackdropColor(region, color)
    if region and region.SetBackdropColor then
        region:SetBackdropColor(unpack(color))
    end
end

local function CreateText(parent, text, size, color)
    local fontString = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontString:SetText(text or "")
    fontString:SetTextColor(unpack(color or colors.text))
    fontString:SetFont(STANDARD_TEXT_FONT, size or 12, "")
    fontString:SetJustifyH("LEFT")
    return fontString
end

local function CreateButton(parent, text, width, height)
    local button = CreateFrame("Button", nil, parent, Template())
    button:SetSize(width or 90, height or 28)
    ApplyBackdrop(button, colors.panel)

    button.text = CreateText(button, text, 12)
    button.text:SetPoint("CENTER")

    button:SetScript("OnEnter", function(self)
        SetBackdropColor(self, colors.hover)
    end)
    button:SetScript("OnLeave", function(self)
        SetBackdropColor(self, self._selected and colors.selected or colors.panel)
    end)

    return button
end

local function CreateCheckbox(parent, text, width)
    local button = CreateFrame("Button", nil, parent, Template())
    button:SetSize(width or 130, 28)

    button.box = CreateFrame("Frame", nil, button, Template())
    button.box:SetSize(16, 16)
    button.box:SetPoint("LEFT", 0, 0)
    ApplyBackdrop(button.box, { 0.045, 0.052, 0.06, 1 })

    button.check = button.box:CreateTexture(nil, "ARTWORK")
    button.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    button.check:SetAllPoints(button.box)
    button.check:Hide()

    button.text = CreateText(button, text, 11, colors.text)
    button.text:SetPoint("LEFT", button.box, "RIGHT", 6, 0)

    button.checked = false
    function button:SetChecked(checked)
        self.checked = checked and true or false
        if self.checked then
            self.check:Show()
        else
            self.check:Hide()
        end
    end
    function button:GetChecked()
        return self.checked
    end

    button:SetScript("OnEnter", function(self)
        self.text:SetTextColor(unpack(colors.accent))
    end)
    button:SetScript("OnLeave", function(self)
        self.text:SetTextColor(unpack(colors.text))
    end)
    button:SetScript("OnClick", function(self)
        self:SetChecked(not self:GetChecked())
        if self.OnValueChanged then
            self:OnValueChanged(self:GetChecked())
        end
    end)

    return button
end

local function CreateScrollBar(parent, kind, height)
    local bar = CreateFrame("Frame", nil, parent, Template())
    bar:SetSize(12, height)
    ApplyBackdrop(bar, { 0.045, 0.052, 0.06, 1 })

    bar.up = CreateButton(bar, "^", 12, 18)
    bar.up:SetPoint("TOP", 0, 0)
    bar.up:SetScript("OnClick", function()
        if ScrollList then
            ScrollList(kind, 1)
        end
    end)

    bar.down = CreateButton(bar, "v", 12, 18)
    bar.down:SetPoint("BOTTOM", 0, 0)
    bar.down:SetScript("OnClick", function()
        if ScrollList then
            ScrollList(kind, -1)
        end
    end)

    bar.thumb = CreateFrame("Frame", nil, bar, Template())
    bar.thumb:SetSize(8, 34)
    ApplyBackdrop(bar.thumb, colors.selected)

    function bar:SetRange(total, visible, offset)
        total = total or 0
        visible = visible or 0
        offset = offset or 0

        if total <= visible then
            self.thumb:Hide()
            self.up.text:SetText("|cff3f4947^|r")
            self.down.text:SetText("|cff3f4947v|r")
            return
        end

        self.thumb:Show()
        self.up.text:SetText(offset > 0 and "^" or "|cff3f4947^|r")
        self.down.text:SetText(offset < total - visible and "v" or "|cff3f4947v|r")

        local trackHeight = height - 42
        local thumbHeight = math.max(24, math.floor(trackHeight * (visible / total)))
        local travel = math.max(trackHeight - thumbHeight, 1)
        local y = -21 - math.floor(travel * (offset / math.max(total - visible, 1)))

        self.thumb:SetHeight(thumbHeight)
        self.thumb:ClearAllPoints()
        self.thumb:SetPoint("TOP", self, "TOP", 0, y)
    end

    return bar
end

local function CreateEditBox(parent, width, height)
    local editBox = CreateFrame("EditBox", nil, parent, Template())
    editBox:SetSize(width, height or 28)
    ApplyBackdrop(editBox, { 0.045, 0.052, 0.06, 1 })
    editBox:SetAutoFocus(false)
    editBox:SetFont(STANDARD_TEXT_FONT, 12, "")
    editBox:SetTextColor(unpack(colors.text))
    editBox:SetJustifyH("LEFT")
    editBox:SetTextInsets(8, 8, 0, 0)
    editBox:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    return editBox
end

local function SetSelected(button, selected)
    button._selected = selected
    SetBackdropColor(button, selected and colors.selected or colors.panel)
end

local function GetAddOnLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name)
    end
    return IsAddOnLoaded and IsAddOnLoaded(name)
end

local function LoadAddon(name)
    if GetAddOnLoaded(name) then
        return true
    end

    if InCombatLockdown and InCombatLockdown() then
        return false, "combat"
    end

    local ok, reason
    if C_AddOns and C_AddOns.LoadAddOn then
        ok, reason = pcall(C_AddOns.LoadAddOn, name)
    elseif LoadAddOn then
        ok, reason = pcall(LoadAddOn, name)
    end

    if ok and GetAddOnLoaded(name) then
        return true
    end

    return false, reason
end

local function GetItemInfo(itemId)
    if WowGetItemInfo then
        return WowGetItemInfo(itemId)
    end
end

local function GetItemIcon(itemId)
    if WowGetItemIcon then
        return WowGetItemIcon(itemId)
    end
end

local function ClearBrowserCaches()
    filteredInstancesCache = nil
    filteredBossesCache = nil
    currentItemsCache = nil
end

local function InvalidateSearchCaches()
    indexSearchCache = {}
    ClearBrowserCaches()
end

local function RequestItem(itemId)
    itemId = tonumber(itemId)
    if not itemId or not C_Item or not C_Item.RequestLoadItemDataByID then
        return
    end

    if GetItemInfo(itemId) then
        return
    end

    local now = time and time() or 0
    if requestedItems[itemId] and now - requestedItems[itemId] < 30 then
        return
    end

    requestedItems[itemId] = now
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemId)
    end
end

local function GetDifficultyPrefixFromName(name)
    name = tostring(name or ""):lower()
    if name:find("celestial", 1, true) then
        return "C"
    elseif name:find("mythic", 1, true) then
        return "M"
    elseif name:find("heroic", 1, true) then
        return "H"
    elseif name:find("normal", 1, true) then
        return "N"
    end
    return nil
end

local function NormalizeSearchText(text)
    text = StripColor(text or ""):lower()
    text = text:gsub("[%'`]", "")
    text = text:gsub("[^%w]+", " ")
    text = text:gsub("^%s+", ""):gsub("%s+$", "")
    text = text:gsub("%s+", " ")
    return text
end

local function GetSearchTokens(text)
    local tokens = {}
    local seen = {}
    for token in tostring(text or ""):gmatch("%S+") do
        if #token >= 2 and not seen[token] then
            seen[token] = true
            tokens[#tokens + 1] = token
        end
    end
    return tokens
end

local function GetSearchGrams(text)
    text = tostring(text or ""):gsub("%s+", "")
    local grams = {}
    local seen = {}
    for index = 1, math.max(#text - 2, 0) do
        local gram = text:sub(index, index + 2)
        if not seen[gram] then
            seen[gram] = true
            grams[#grams + 1] = gram
        end
    end
    return grams
end

local function AddIdToIndexBucket(bucket, key, itemId)
    if not key or key == "" then
        return
    end

    bucket[key] = bucket[key] or {}
    bucket[key][itemId] = true
end

local function AddItemToSearchIndex(index, itemId, name)
    local searchName = NormalizeSearchText(name)
    if searchName == "" then
        return
    end

    local item = index.itemsById[itemId]
    if not item then
        return
    end

    item.name = name
    item.searchName = searchName

    local tokens = GetSearchTokens(searchName)
    for _, token in ipairs(tokens) do
        AddIdToIndexBucket(index.tokenIndex, token, itemId)
        for length = 2, math.min(#token, 8) do
            AddIdToIndexBucket(index.prefixIndex, token:sub(1, length), itemId)
        end
    end

    for _, gram in ipairs(GetSearchGrams(searchName)) do
        AddIdToIndexBucket(index.gramIndex, gram, itemId)
    end
end

local function AddIndexSource(index, itemId, instance, boss, difficulty)
    if type(itemId) ~= "number" then
        return
    end

    local item = index.itemsById[itemId]
    if not item then
        item = {
            id = itemId,
            sources = {},
        }
        index.itemsById[itemId] = item
        index.queue[#index.queue + 1] = itemId
    end

    item.sources[#item.sources + 1] = {
        instanceKey = instance.key,
        instanceName = instance.name,
        bossIndex = boss.index,
        bossName = boss.name,
        npcIDs = boss.npcIDs,
        objectID = boss.objectID,
        encounterJournalID = boss.encounterJournalID,
        difficultyId = difficulty.id,
        difficultyName = difficulty.name,
        difficultyPrefix = GetDifficultyPrefixFromName(difficulty.name),
    }
end

local function IsStarredSource(key)
    return Plutocraseeker.db and Plutocraseeker.db.starredSources and Plutocraseeker.db.starredSources[key] and true or false
end

local function ToggleStarredSource(key)
    if not key then
        return
    end

    Plutocraseeker.db.starredSources = Plutocraseeker.db.starredSources or {}
    Plutocraseeker.db.starredSources[key] = not Plutocraseeker.db.starredSources[key] or nil
    starRevision = starRevision + 1
    ClearBrowserCaches()
end

function StripColor(text)
    text = tostring(text or "")
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "")
    text = text:gsub("|r", "")
    return text
end

local function GetNameFromAtlas(methodTarget, methodName, fallback)
    if methodTarget and methodTarget[methodName] then
        local ok, result = pcall(methodTarget[methodName], methodTarget, true)
        if ok and result and result ~= "" then
            return StripColor(result)
        end
    end
    return fallback
end

local function GetBossName(content, bossIndex, bossTable)
    if content and content.GetNameForItemTable then
        local ok, result = pcall(content.GetNameForItemTable, content, bossIndex, true)
        if ok and result and result ~= "" then
            return StripColor(result)
        end
    end

    if bossTable and bossTable.name then
        return StripColor(bossTable.name)
    end

    if bossTable and bossTable.EncounterJournalID and EJ_GetEncounterInfo then
        return EJ_GetEncounterInfo(bossTable.EncounterJournalID) or ("Encounter " .. bossTable.EncounterJournalID)
    end

    return "Boss " .. tostring(bossIndex)
end

local function GetDifficultyName(moduleData, difficultyIndex)
    if moduleData and moduleData.GetDifficultyName then
        local ok, result = pcall(moduleData.GetDifficultyName, moduleData, difficultyIndex)
        if ok and result and result ~= "" then
            return StripColor(result)
        end
    end
    return "Difficulty " .. tostring(difficultyIndex)
end

local function GetContentType(content)
    if content and content.GetContentType then
        local ok, result = pcall(content.GetContentType, content)
        if ok and result then
            return StripColor(result)
        end
    end
    return ""
end

AddNpcId = function(target, value)
    value = tonumber(value)
    if not value then
        return
    end

    for _, existing in ipairs(target) do
        if tonumber(existing) == value then
            return
        end
    end

    target[#target + 1] = value
end

NormalizeNpcIDs = function(value)
    local ids = {}
    if type(value) == "table" then
        for _, id in ipairs(value) do
            AddNpcId(ids, id)
        end
    else
        AddNpcId(ids, value)
    end
    return ids
end

local function BuildSourceMetadata(instance, boss, difficulty)
    if not instance or not boss then
        return nil
    end

    return {
        instanceKey = instance.key,
        instanceName = instance.name,
        bossIndex = boss.index,
        bossName = boss.name,
        npcIDs = boss.npcIDs,
        objectID = boss.objectID,
        encounterJournalID = boss.encounterJournalID,
        difficultyId = difficulty and difficulty.id or nil,
        difficultyName = difficulty and difficulty.name or nil,
    }
end

local function GetAllNpcIdsForItem(itemId)
    itemId = tonumber(itemId)
    if not itemId or not dataCache then
        return {}
    end

    if npcIdsByItemCache[itemId] then
        return npcIdsByItemCache[itemId]
    end

    local ids = {}
    local seen = {}
    for _, instance in ipairs(dataCache.instances or {}) do
        for _, boss in ipairs(instance.bosses or {}) do
            local bossHasItem = false
            for _, difficulty in ipairs(boss.difficulties or {}) do
                local itemTable = boss.raw and boss.raw[difficulty.id]
                if type(itemTable) == "table" then
                    for _, entry in ipairs(itemTable) do
                        if entry and (tonumber(entry[2]) == itemId or tonumber(entry[3]) == itemId) then
                            bossHasItem = true
                            break
                        end
                    end
                end
                if bossHasItem then
                    break
                end
            end

            if bossHasItem then
                for _, npcId in ipairs(boss.npcIDs or {}) do
                    npcId = tonumber(npcId)
                    if npcId and not seen[npcId] then
                        ids[#ids + 1] = npcId
                        seen[npcId] = true
                    end
                end
            end
        end
    end

    npcIdsByItemCache[itemId] = ids
    return ids
end

local function MetadataHasItem(metadata, itemId)
    itemId = tonumber(itemId)
    if not metadata or not itemId or not dataCache then
        return metadata
    end

    local seen = {}
    for _, npcId in ipairs(metadata.npcIDs or {}) do
        seen[tonumber(npcId)] = true
    end

    for _, npcId in ipairs(GetAllNpcIdsForItem(itemId)) do
        npcId = tonumber(npcId)
        if npcId and not seen[npcId] then
            metadata.npcIDs = metadata.npcIDs or {}
            metadata.npcIDs[#metadata.npcIDs + 1] = npcId
            seen[npcId] = true
        end
    end

    return metadata
end

local function BuildExpandedSourceMetadata(itemId, instance, boss, difficulty)
    return MetadataHasItem(BuildSourceMetadata(instance, boss, difficulty), itemId)
end

local function FindSourceMetadataForItem(itemId)
    itemId = tonumber(itemId)
    if not itemId or not dataCache then
        return nil
    end

    for _, instance in ipairs(dataCache.instances or {}) do
        for _, boss in ipairs(instance.bosses or {}) do
            for _, difficulty in ipairs(boss.difficulties or {}) do
                local itemTable = boss.raw and boss.raw[difficulty.id]
                if type(itemTable) == "table" then
                    for _, entry in ipairs(itemTable) do
                        if entry and (tonumber(entry[2]) == itemId or tonumber(entry[3]) == itemId) then
                            return BuildExpandedSourceMetadata(itemId, instance, boss, difficulty)
                        end
                    end
                end
            end
        end
    end

    return nil
end

function Browser.EnrichTrackedItemSourcesFromCache()
    local ok = Browser.LoadData()
    if not ok or not Plutocraseeker.db or not Plutocraseeker.MergeTrackedItemSourceMetadata then
        return 0
    end

    local seen = {}
    local changed = 0
    for _, set in ipairs(Plutocraseeker.db.sets or {}) do
        for _, item in ipairs(set.items or {}) do
            local itemId = tonumber(item and item.id)
            if itemId and not seen[itemId] then
                seen[itemId] = true
                changed = changed + Plutocraseeker.MergeTrackedItemSourceMetadata(itemId, FindSourceMetadataForItem(itemId))
            end
        end
    end

    return changed
end

local function GetBossDifficultyById(boss, difficultyId)
    if not boss or not difficultyId then
        return nil
    end

    for _, difficulty in ipairs(boss.difficulties or {}) do
        if difficulty.id == difficultyId then
            return difficulty
        end
    end

    return nil
end

local function AddItemId(itemId, entry, items, seen, variantOf)
    if type(itemId) ~= "number" or seen[itemId] then
        return
    end

    seen[itemId] = true
    RequestItem(itemId)
    items[#items + 1] = {
        id = itemId,
        bonusId = type(entry[3]) == "number" and entry[3] or nil,
        extra = type(entry[3]) == "string" and entry[3] or nil,
        variantOf = variantOf,
    }
end

local function AddItem(entry, items, seen)
    if not entry then
        return
    end

    AddItemId(entry[2], entry, items, seen)
    AddItemId(entry[3], entry, items, seen, entry[2])
end

local function BuildItems(moduleData, instance, boss, difficultyIndex)
    local items = {}
    local seen = {}
    local itemTable

    if AtlasLoot and AtlasLoot.ItemDB and AtlasLoot.ItemDB.GetItemTable then
        local ok, result = pcall(AtlasLoot.ItemDB.GetItemTable, AtlasLoot.ItemDB, ATLAS_MODULE, instance.key, boss.index, difficultyIndex)
        if ok and type(result) == "table" then
            itemTable = result
        end
    end

    itemTable = itemTable or boss.raw[difficultyIndex]
    if type(itemTable) ~= "table" then
        return items
    end

    for _, entry in ipairs(itemTable) do
        AddItem(entry, items, seen)
    end

    return items
end

local function BuildIndexQueue()
    local ok, reason = Browser.LoadData()
    if not ok then
        return nil, reason
    end

    if not selectedInstance then
        return nil, "Select a raid or dungeon before building an index."
    end

    local index = {
        version = INDEX_VERSION,
        builtAt = date and date("%Y-%m-%d %H:%M:%S") or nil,
        sourceKey = selectedInstance.key,
        sourceName = selectedInstance.name,
        complete = false,
        total = 0,
        indexed = 0,
        skipped = 0,
        itemsById = {},
        tokenIndex = {},
        prefixIndex = {},
        gramIndex = {},
        queue = {},
    }

    for _, boss in ipairs(selectedInstance.bosses) do
        for _, difficulty in ipairs(boss.difficulties) do
            local itemTable = boss.raw[difficulty.id]
            if type(itemTable) == "table" then
                for _, entry in ipairs(itemTable) do
                    AddIndexSource(index, entry and entry[2], selectedInstance, boss, difficulty)
                    AddIndexSource(index, entry and entry[3], selectedInstance, boss, difficulty)
                end
            end
        end
    end

    index.total = #index.queue
    return index
end

local function UpdateIndexButton()
    if not frame or not frame.indexButton then
        return
    end

    if indexBuilder then
        frame.indexButton.text:SetText("Abort index")
        return
    end

    local index = Plutocraseeker.db and Plutocraseeker.db.itemSearchIndex
    if index and index.complete and selectedInstance and index.sourceKey == selectedInstance.key and index.version == INDEX_VERSION then
        frame.indexButton.text:SetText("Rebuild Index (slow)")
    else
        frame.indexButton.text:SetText("Build Index (slow)")
    end
end

local function AbortIndexBuild()
    if not indexBuilder then
        return
    end

    Plutocraseeker.db.itemSearchIndex = indexBuilder.previousIndex or {}
    indexBuilder = nil
    indexSearchCache = {}
    UpdateIndexButton()
    SetStatus("Item search index build aborted.", colors.warn)
end

local function FinishIndexBuild(index)
    index.complete = true
    index.queue = nil
    Plutocraseeker.db.itemSearchIndex = index
    indexBuilder = nil
    indexSearchCache = {}
    if Plutocraseeker.EnrichTrackedItemSourcesFromIndex then
        Plutocraseeker.EnrichTrackedItemSourcesFromIndex()
    elseif Plutocraseeker.RebuildTargetNpcIndex then
        Plutocraseeker.RebuildTargetNpcIndex()
    end
    UpdateIndexButton()
    SetStatus("Indexed " .. tostring(index.sourceName or "source") .. ": " .. tostring(index.indexed) .. " items" .. (index.skipped > 0 and ("; " .. index.skipped .. " skipped") or ""), index.skipped > 0 and colors.warn or colors.accent)
    Browser.Refresh()
end

local function ProcessIndexBuild(elapsed)
    if not indexBuilder then
        return
    end

    indexBuilder.elapsed = (indexBuilder.elapsed or 0) + (elapsed or 0)
    if indexBuilder.elapsed < INDEX_TICK_SECONDS then
        return
    end
    indexBuilder.elapsed = 0

    local index = indexBuilder.index
    local processed = 0

    while processed < INDEX_BATCH_SIZE and indexBuilder.position <= #index.queue do
        local itemId = index.queue[indexBuilder.position]
        indexBuilder.position = indexBuilder.position + 1
        local name = GetItemInfo(itemId)

        if name then
            AddItemToSearchIndex(index, itemId, name)
            index.indexed = index.indexed + 1
        else
            indexBuilder.attempts[itemId] = (indexBuilder.attempts[itemId] or 0) + 1
            if indexBuilder.attempts[itemId] == 1 then
                RequestItem(itemId)
            end

            if indexBuilder.attempts[itemId] < INDEX_MAX_ATTEMPTS then
                index.queue[#index.queue + 1] = itemId
            else
                index.skipped = index.skipped + 1
            end
        end

        processed = processed + 1
    end

    if indexBuilder.position > #index.queue then
        FinishIndexBuild(index)
    else
        indexBuilder.statusElapsed = (indexBuilder.statusElapsed or 0) + INDEX_TICK_SECONDS
        if indexBuilder.statusElapsed >= INDEX_STATUS_SECONDS then
            indexBuilder.statusElapsed = 0
            UpdateIndexButton()
            SetStatus("Indexing " .. tostring(index.sourceName or "source") .. ": " .. tostring(index.indexed) .. "/" .. tostring(index.total), colors.muted)
        end
    end
end

local function StartIndexBuild()
    if indexBuilder then
        AbortIndexBuild()
        return
    end

    local index, reason = BuildIndexQueue()
    if not index then
        SetStatus(tostring(reason), colors.warn)
        return
    end

    if index.total == 0 then
        SetStatus("No items were found to index.", colors.warn)
        return
    end

    indexBuilder = {
        index = index,
        previousIndex = Plutocraseeker.db and Plutocraseeker.db.itemSearchIndex or {},
        attempts = {},
        elapsed = INDEX_TICK_SECONDS,
        statusElapsed = INDEX_STATUS_SECONDS,
        position = 1,
    }
    Plutocraseeker.db.itemSearchIndex = index
    indexSearchCache = {}
    UpdateIndexButton()
    SetStatus("Indexing " .. tostring(index.sourceName or "source") .. ": 0/" .. tostring(index.total), colors.muted)
end

local function BuildCache()
    local moduleData = AtlasLoot and AtlasLoot.ItemDB and AtlasLoot.ItemDB:Get(ATLAS_MODULE)
    if not moduleData then
        return nil
    end

    local cache = {
        instances = {},
        difficulties = {},
    }

    if moduleData.GetDifficultys then
        local difficulties = moduleData:GetDifficultys() or {}
        for index, difficultyData in ipairs(difficulties) do
            cache.difficulties[index] = {
                id = index,
                name = StripColor((difficultyData and difficultyData.name) or GetDifficultyName(moduleData, index)),
            }
        end
    end

    for key, content in pairs(moduleData) do
        if type(content) == "table" and type(content.items) == "table" and not content.ExtraList then
            local instance = {
                key = key,
                name = GetNameFromAtlas(content, "GetName", content.name or key),
                contentType = GetContentType(content),
                raw = content,
                bosses = {},
            }

            for bossIndex, bossTable in ipairs(content.items) do
                if type(bossTable) == "table" and not bossTable.ExtraList then
                    local boss = {
                        index = bossIndex,
                        name = GetBossName(content, bossIndex, bossTable),
                        npcIDs = NormalizeNpcIDs(bossTable.npcID or bossTable.npcId),
                        objectID = bossTable.ObjectID,
                        encounterJournalID = bossTable.EncounterJournalID,
                        raw = bossTable,
                        difficulties = {},
                    }

                    for difficultyIndex, difficultyInfo in ipairs(cache.difficulties) do
                        if bossTable[difficultyIndex] then
                            boss.difficulties[#boss.difficulties + 1] = difficultyInfo
                        end
                    end

                    if #boss.difficulties > 0 then
                        instance.bosses[#instance.bosses + 1] = boss
                    end
                end
            end

            if #instance.bosses > 0 then
                cache.instances[#cache.instances + 1] = instance
            end
        end
    end

    table.sort(cache.instances, function(left, right)
        if left.contentType == right.contentType then
            return left.name < right.name
        end
        return left.contentType > right.contentType
    end)

    return cache
end

function Browser.LoadData()
    if dataCache then
        return true
    end

    local ok, reason = LoadAddon("AtlasLootClassic")
    if not ok then
        return false, reason or "AtlasLootClassic is not available."
    end

    ok, reason = LoadAddon(ATLAS_MODULE)
    if not ok and AtlasLoot and AtlasLoot.Loader and AtlasLoot.Loader.LoadModule then
        local loadState = AtlasLoot.Loader:LoadModule(ATLAS_MODULE)
        if loadState == true or GetAddOnLoaded(ATLAS_MODULE) then
            ok = true
        else
            reason = loadState or reason
        end
    end

    if not ok then
        return false, reason or (ATLAS_MODULE .. " is not available.")
    end

    dataCache = BuildCache()
    if not dataCache or #dataCache.instances == 0 then
        return false, "No AtlasLoot dungeon or raid tables were found."
    end

    npcIdsByItemCache = {}
    InvalidateSearchCaches()
    selectedInstance = dataCache.instances[1]
    selectedBoss = selectedInstance and selectedInstance.bosses[1]
    selectedDifficulty = selectedBoss and selectedBoss.difficulties[1] and selectedBoss.difficulties[1].id
    return true
end

local function AddCandidateScore(scores, itemId, score)
    scores[itemId] = (scores[itemId] or 0) + score
end

local function AddBucketScores(scores, bucket, score)
    if not bucket then
        return
    end

    for itemId in pairs(bucket) do
        AddCandidateScore(scores, itemId, score)
    end
end

local function IsItemSearchMode()
    return frame and frame.itemSearchCheck and frame.itemSearchCheck:GetChecked() and true or false
end

local function EnsureLootFilters()
    lootFilters.gear = lootFilters.gear or {}
    lootFilters.slots = lootFilters.slots or {}
    lootFilters.primaryStats = lootFilters.primaryStats or {}
    lootFilters.secondaryStats = lootFilters.secondaryStats or {}

    for _, option in ipairs(GEAR_FILTERS) do
        if lootFilters.gear[option.key] == nil then
            lootFilters.gear[option.key] = true
        end
    end

    for _, option in ipairs(SLOT_FILTERS) do
        if lootFilters.slots[option.key] == nil then
            lootFilters.slots[option.key] = true
        end
    end

    for _, option in ipairs(PRIMARY_STAT_FILTERS) do
        if lootFilters.primaryStats[option.key] == nil then
            lootFilters.primaryStats[option.key] = true
        end
    end

    for _, option in ipairs(SECONDARY_STAT_FILTERS) do
        if lootFilters.secondaryStats[option.key] == nil then
            lootFilters.secondaryStats[option.key] = true
        end
    end
end

local function IsFilterGroupAllSelected(options, values)
    for _, option in ipairs(options) do
        if values[option.key] ~= true then
            return false
        end
    end

    return true
end

local function IsFilterGroupAnySelected(options, values)
    for _, option in ipairs(options) do
        if values[option.key] == true then
            return true
        end
    end

    return false
end

local function AreAllLootFiltersSelected()
    EnsureLootFilters()

    return IsFilterGroupAllSelected(GEAR_FILTERS, lootFilters.gear)
        and IsFilterGroupAllSelected(SLOT_FILTERS, lootFilters.slots)
        and IsFilterGroupAllSelected(PRIMARY_STAT_FILTERS, lootFilters.primaryStats)
        and IsFilterGroupAllSelected(SECONDARY_STAT_FILTERS, lootFilters.secondaryStats)
end

local function GetSlotFilterKey(equipLoc)
    equipLoc = tostring(equipLoc or "")

    if equipLoc == "INVTYPE_HEAD" then
        return "head"
    elseif equipLoc == "INVTYPE_NECK" then
        return "neck"
    elseif equipLoc == "INVTYPE_SHOULDER" then
        return "shoulder"
    elseif equipLoc == "INVTYPE_CLOAK" then
        return "back"
    elseif equipLoc == "INVTYPE_CHEST" or equipLoc == "INVTYPE_ROBE" then
        return "chest"
    elseif equipLoc == "INVTYPE_WRIST" then
        return "wrist"
    elseif equipLoc == "INVTYPE_HAND" then
        return "hands"
    elseif equipLoc == "INVTYPE_WAIST" then
        return "waist"
    elseif equipLoc == "INVTYPE_LEGS" then
        return "legs"
    elseif equipLoc == "INVTYPE_FEET" then
        return "feet"
    elseif equipLoc == "INVTYPE_FINGER" then
        return "finger"
    elseif equipLoc == "INVTYPE_TRINKET" then
        return "trinket"
    elseif equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" or equipLoc == "INVTYPE_WEAPONOFFHAND" then
        return "offhand"
    elseif equipLoc == "INVTYPE_WEAPON" or equipLoc == "INVTYPE_WEAPONMAINHAND" or equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" or equipLoc == "INVTYPE_THROWN" then
        return "weapon"
    end

    return "other"
end

local function GetGearFilterKey(itemType, itemSubType, equipLoc)
    local subTypeText = tostring(itemSubType or ""):lower()

    if subTypeText:find("cloth", 1, true) then
        return "cloth"
    elseif subTypeText:find("leather", 1, true) then
        return "leather"
    elseif subTypeText:find("mail", 1, true) then
        return "mail"
    elseif subTypeText:find("plate", 1, true) then
        return "plate"
    end

    return nil
end

local function GetItemStatsForFilter(itemId)
    if not WowGetItemStats or not itemId then
        return nil
    end

    local ok, stats = pcall(WowGetItemStats, "item:" .. tostring(itemId))
    if ok then
        return stats
    end

    return nil
end

local function ItemHasStat(stats, option)
    if not stats or not option or not option.stats then
        return false
    end

    for _, statKey in ipairs(option.stats) do
        if (stats[statKey] or 0) > 0 then
            return true
        end
    end

    return false
end

local function ItemPassesStatGroup(stats, options, values)
    if IsFilterGroupAllSelected(options, values) then
        return true
    end

    if not IsFilterGroupAnySelected(options, values) then
        return false
    end

    for _, option in ipairs(options) do
        if values[option.key] == true and ItemHasStat(stats, option) then
            return true
        end
    end

    return false
end

local function ItemPassesLootFilters(item)
    if AreAllLootFiltersSelected() then
        return true
    end

    local itemId = type(item) == "table" and item.id or item
    if not itemId then
        return false
    end

    local _, _, _, _, _, itemType, itemSubType, _, equipLoc = GetItemInfo(itemId)
    if not itemType and not itemSubType and not equipLoc then
        RequestItem(itemId)
        return false
    end

    local gearKey = GetGearFilterKey(itemType, itemSubType, equipLoc)
    local slotKey = GetSlotFilterKey(equipLoc)
    EnsureLootFilters()
    if gearKey and lootFilters.gear[gearKey] ~= true then
        return false
    end
    if lootFilters.slots[slotKey] ~= true then
        return false
    end

    local needsPrimaryStats = not IsFilterGroupAllSelected(PRIMARY_STAT_FILTERS, lootFilters.primaryStats)
    local needsSecondaryStats = not IsFilterGroupAllSelected(SECONDARY_STAT_FILTERS, lootFilters.secondaryStats)
    if not needsPrimaryStats and not needsSecondaryStats then
        return true
    end

    local stats = GetItemStatsForFilter(itemId)
    if not stats then
        RequestItem(itemId)
        return false
    end

    return ItemPassesStatGroup(stats, PRIMARY_STAT_FILTERS, lootFilters.primaryStats)
        and ItemPassesStatGroup(stats, SECONDARY_STAT_FILTERS, lootFilters.secondaryStats)
end

local function FilterLootItems(items)
    if AreAllLootFiltersSelected() then
        return items
    end

    local filtered = {}
    for _, item in ipairs(items or {}) do
        if ItemPassesLootFilters(item) then
            filtered[#filtered + 1] = item
        end
    end

    return filtered
end

local function UpdateFilterButton()
    if frame and frame.filterButton then
        frame.filterButton.text:SetText(AreAllLootFiltersSelected() and "Filter" or "Filter *")
    end
end

local function SourcePassesContentFilter(instance)
    if contentFilter == "RAID" and not instance.contentType:lower():find("raid", 1, true) then
        return false
    elseif contentFilter == "DUNGEON" and not instance.contentType:lower():find("dungeon", 1, true) then
        return false
    end
    return true
end

local function BuildItemSearchResults(search)
    local index = Plutocraseeker.db and Plutocraseeker.db.itemSearchIndex
    if not index or not index.complete or index.version ~= INDEX_VERSION then
        return nil
    end

    local normalized = NormalizeSearchText(search)
    if normalized == "" then
        return {
            query = normalized,
            items = {},
            sources = index.sourceKey and { [index.sourceKey] = true } or {},
            bosses = {},
            empty = true,
        }
    end

    if indexSearchCache.query == normalized and indexSearchCache.filterRevision == filterRevision then
        return indexSearchCache.results
    end

    local scores = {}
    local tokens = GetSearchTokens(normalized)
    for _, token in ipairs(tokens) do
        AddBucketScores(scores, index.tokenIndex and index.tokenIndex[token], 100)
        AddBucketScores(scores, index.prefixIndex and index.prefixIndex[token], 70)
    end

    for itemId, item in pairs(index.itemsById or {}) do
        if item.searchName and item.searchName:find(normalized, 1, true) then
            AddCandidateScore(scores, itemId, 90)
        end
    end

    local grams = GetSearchGrams(normalized)
    if #grams > 0 then
        for _, gram in ipairs(grams) do
            AddBucketScores(scores, index.gramIndex and index.gramIndex[gram], 1)
        end
    end

    local minFuzzyScore = math.max(2, math.floor(#grams * 0.35))
    local items = {}
    local sources = {}
    local bosses = {}

    for itemId, score in pairs(scores) do
        if score >= 50 or score >= minFuzzyScore then
            local item = index.itemsById and index.itemsById[itemId]
            if item and item.sources and ItemPassesLootFilters(item) then
                local result = {
                    id = item.id or itemId,
                    name = item.name,
                    searchName = item.searchName,
                    sources = item.sources,
                    score = score,
                    searchResult = true,
                }
                items[#items + 1] = result

                for _, source in ipairs(item.sources) do
                    if source.instanceKey then
                        sources[source.instanceKey] = true
                        bosses[source.instanceKey] = bosses[source.instanceKey] or {}
                        bosses[source.instanceKey][source.bossIndex or source.bossName] = true
                    end
                end
            end
        end
    end

    table.sort(items, function(left, right)
        if left.score ~= right.score then
            return left.score > right.score
        end
        return tostring(left.name or left.id) < tostring(right.name or right.id)
    end)

    local results = {
        query = normalized,
        items = items,
        sources = sources,
        bosses = bosses,
    }

    indexSearchCache.query = normalized
    indexSearchCache.filterRevision = filterRevision
    indexSearchCache.results = results
    return results
end

local function ItemSearchMatchesInstance(instance, search)
    local results = BuildItemSearchResults(search)
    return results and results.sources and results.sources[instance.key] or false
end

local function ItemSearchMatchesBoss(instance, boss, search)
    local results = BuildItemSearchResults(search)
    local sourceBosses = results and results.bosses and instance and results.bosses[instance.key]
    return sourceBosses and boss and sourceBosses[boss.index or boss.name] or false
end

local function MatchesFilter(instance, search)
    if not SourcePassesContentFilter(instance) then
        return false
    end

    if IsItemSearchMode() then
        return search == "" or ItemSearchMatchesInstance(instance, search)
    end

    if search == "" then
        return true
    end

    local lowerSearch = search:lower()
    if instance.name:lower():find(lowerSearch, 1, true) then
        return true
    end

    for _, boss in ipairs(instance.bosses) do
        if boss.name:lower():find(lowerSearch, 1, true) then
            return true
        end
    end

    return false
end

function SetStatus(message, color)
    if frame and frame.status then
        frame.status:SetText(message or "")
        frame.status:SetTextColor(unpack(color or colors.muted))
    end
end

local function GetSearchText()
    local search = frame and frame.search and frame.search:GetText() or ""
    return tostring(search or ""):match("^%s*(.-)%s*$"):lower()
end

local function GetFilteredInstances()
    local search = GetSearchText()
    local cacheKey = table.concat({
        tostring(dataCache),
        tostring(contentFilter),
        tostring(IsItemSearchMode()),
        tostring(search),
        tostring(filterRevision),
        tostring(starRevision),
    }, "\031")
    if filteredInstancesCache and filteredInstancesCache.key == cacheKey then
        return filteredInstancesCache.instances
    end

    local instances = {}

    if dataCache then
        for _, instance in ipairs(dataCache.instances) do
            if MatchesFilter(instance, search) then
                instances[#instances + 1] = instance
            end
        end
    end

    table.sort(instances, function(left, right)
        local leftStarred = IsStarredSource(left.key)
        local rightStarred = IsStarredSource(right.key)
        if leftStarred ~= rightStarred then
            return leftStarred
        end
        if left.contentType == right.contentType then
            return left.name < right.name
        end
        return left.contentType > right.contentType
    end)

    filteredInstancesCache = {
        key = cacheKey,
        instances = instances,
    }
    return instances
end

local function GetFilteredBosses()
    local search = GetSearchText()
    local cacheKey = table.concat({
        tostring(selectedInstance and selectedInstance.key),
        tostring(IsItemSearchMode()),
        tostring(search),
        tostring(filterRevision),
    }, "\031")
    if filteredBossesCache and filteredBossesCache.key == cacheKey then
        return filteredBossesCache.bosses
    end

    local bosses = selectedInstance and selectedInstance.bosses or {}
    if not IsItemSearchMode() or search == "" then
        filteredBossesCache = {
            key = cacheKey,
            bosses = bosses,
        }
        return bosses
    end

    local filtered = {}
    for _, boss in ipairs(bosses) do
        if ItemSearchMatchesBoss(selectedInstance, boss, search) then
            filtered[#filtered + 1] = boss
        end
    end
    filteredBossesCache = {
        key = cacheKey,
        bosses = filtered,
    }
    return filtered
end

local function GetItemSearchItems()
    local search = GetSearchText()
    if search == "" then
        return {}
    end

    local results = BuildItemSearchResults(search)
    if not results or not results.items then
        return {}
    end

    local items = {}
    for _, item in ipairs(results.items) do
        for _, source in ipairs(item.sources or {}) do
            local sourceMatches = selectedInstance and source.instanceKey == selectedInstance.key
            local bossMatches = not selectedBoss or source.bossIndex == selectedBoss.index or source.bossName == selectedBoss.name
            if sourceMatches and bossMatches then
                items[#items + 1] = {
                    id = item.id,
                    name = item.name,
                    searchResult = true,
                    difficultyPrefix = source.difficultyPrefix,
                    sourceMetadata = MetadataHasItem({
                        instanceKey = source.instanceKey,
                        instanceName = source.instanceName,
                        bossIndex = source.bossIndex,
                        bossName = source.bossName,
                        npcIDs = source.npcIDs,
                        objectID = source.objectID,
                        encounterJournalID = source.encounterJournalID,
                        difficultyId = source.difficultyId,
                        difficultyName = source.difficultyName,
                    }, item.id),
                    meta = tostring(source.bossName or "Encounter") .. " - " .. tostring(source.difficultyName or "Difficulty"),
                }
                break
            end
        end
    end

    return items
end

local function GetDifficultyTabLabel(name)
    name = tostring(name or "")
    if name:lower() == "heroic" then
        return "(H)"
    end

    name = name:gsub("%s*%([Hh]eroic%)", " (H)")
    name = name:gsub("[Hh]eroic", "(H)")
    name = name:gsub("%s+", " ")
    return name
end

local function GetCurrentItems()
    local itemSearchMode = IsItemSearchMode()
    local cacheKey = table.concat({
        tostring(selectedInstance and selectedInstance.key),
        tostring(selectedBoss and (selectedBoss.index or selectedBoss.name)),
        tostring(selectedDifficulty),
        tostring(itemSearchMode),
        tostring(GetSearchText()),
        tostring(filterRevision),
    }, "\031")
    if currentItemsCache and currentItemsCache.key == cacheKey then
        return currentItemsCache.items
    end

    local items = {}
    if itemSearchMode then
        items = GetItemSearchItems()
    elseif dataCache and selectedInstance and selectedBoss and selectedDifficulty then
        items = FilterLootItems(BuildItems(dataCache, selectedInstance, selectedBoss, selectedDifficulty))
    end

    currentItemsCache = {
        key = cacheKey,
        items = items,
    }
    return items
end

local function RefreshItems()
    if not frame then
        return
    end

    local itemSearchMode = IsItemSearchMode()
    local difficulties = not itemSearchMode and selectedBoss and selectedBoss.difficulties or {}
    local tabRows = math.max(1, math.ceil(#difficulties / 4))
    local itemListTop = itemSearchMode and -68 or (ITEM_ROW_TOP - ((tabRows - 1) * 27))
    for index, button in ipairs(frame.difficultyButtons) do
        local difficulty = difficulties and difficulties[index] or nil
        if difficulty then
            local label = GetDifficultyTabLabel(difficulty.name)
            local rowIndex = math.floor((index - 1) / 4)
            local indexInRow = ((index - 1) % 4) + 1
            local remaining = math.max(#difficulties - (rowIndex * 4), 0)
            local rowCount = math.min(4, remaining)
            local tabWidth = math.floor((ITEM_PANEL_WIDTH - 20 - ((rowCount - 1) * 6)) / math.max(rowCount, 1))
            local tabX = 10 + ((indexInRow - 1) * (tabWidth + 6))
            local tabY = -31 - (rowIndex * 27)

            button:Show()
            button:ClearAllPoints()
            button:SetPoint("TOPLEFT", tabX, tabY)
            button:SetSize(tabWidth, 25)
            button.difficultyId = difficulty.id
            button.text:SetText(label)
            SetSelected(button, selectedDifficulty == difficulty.id)
            tabX = tabX + tabWidth + 6
        else
            button.difficultyId = nil
            button:Hide()
        end
    end

    local items = GetCurrentItems()

    if itemOffset > math.max(#items - #itemRows, 0) then
        itemOffset = math.max(#items - #itemRows, 0)
    end

    if frame.itemScroll then
        frame.itemScroll:ClearAllPoints()
        frame.itemScroll:SetPoint("TOPRIGHT", -8, itemListTop)
        frame.itemScroll:SetHeight(math.max(240, LIST_PANEL_HEIGHT + itemListTop - 14))
        frame.itemScroll:SetRange(#items, #itemRows, itemOffset)
    end

    for index, row in ipairs(itemRows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 10, itemListTop - ((index - 1) * 37))
        local item = items[index + itemOffset]
        if item then
            local sourceMetadata = item.sourceMetadata
            if not sourceMetadata and not itemSearchMode then
                sourceMetadata = BuildExpandedSourceMetadata(item.id, selectedInstance, selectedBoss, GetBossDifficultyById(selectedBoss, selectedDifficulty))
                item.sourceMetadata = sourceMetadata
            end
            local name, link, quality, _, _, _, _, _, _, icon = GetItemInfo(item.id)
            local r, g, b = 1, 1, 1
            if quality and GetItemQualityColor then
                r, g, b = GetItemQualityColor(quality)
            end

            row:Show()
            row.itemId = item.id
            row.itemLink = link
            row.difficultyPrefix = item.difficultyPrefix
            row.sourceMetadata = sourceMetadata
            row.icon:SetTexture(icon or GetItemIcon(item.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.name:SetText(name or item.name or ("item:" .. item.id))
            row.name:SetTextColor(r, g, b)
            row.meta:SetText(item.meta or (item.variantOf and ("Variant ID " .. item.id) or ("ID " .. item.id)))
        else
            row.itemId = nil
            row.itemLink = nil
            row.difficultyPrefix = nil
            row.sourceMetadata = nil
            row:Hide()
        end
    end

    if not indexBuilder then
        if itemSearchMode and GetSearchText() == "" then
            SetStatus("Enter an item search.", colors.muted)
        elseif itemSearchMode and not (Plutocraseeker.db and Plutocraseeker.db.itemSearchIndex and Plutocraseeker.db.itemSearchIndex.complete and Plutocraseeker.db.itemSearchIndex.version == INDEX_VERSION) then
            SetStatus("Build an item index before searching by item.", colors.warn)
        else
            SetStatus(#items .. (itemSearchMode and " matching items" or " items") .. (itemOffset > 0 and ("; showing " .. (itemOffset + 1)) or ""))
        end
    end
end

local function RefreshBosses()
    if not frame then
        return
    end

    local bosses = GetFilteredBosses()
    local selectedStillVisible
    for _, boss in ipairs(bosses) do
        if boss == selectedBoss then
            selectedStillVisible = true
            break
        end
    end

    if not selectedStillVisible then
        selectedBoss = bosses[1]
        selectedDifficulty = selectedBoss and selectedBoss.difficulties[1] and selectedBoss.difficulties[1].id or nil
        itemOffset = 0
    end

    if bossOffset > math.max(#bosses - #bossRows, 0) then
        bossOffset = math.max(#bosses - #bossRows, 0)
    end

    if frame.bossScroll then
        frame.bossScroll:SetRange(#bosses, #bossRows, bossOffset)
    end

    for index, row in ipairs(bossRows) do
        local boss = bosses[index + bossOffset]
        if boss then
            row:Show()
            row.boss = boss
            row.text:SetText(boss.name)
            SetSelected(row, selectedBoss == boss)
        else
            row.boss = nil
            row:Hide()
        end
    end

    if selectedBoss and not selectedDifficulty then
        selectedDifficulty = selectedBoss.difficulties[1] and selectedBoss.difficulties[1].id
    end

    RefreshItems()
end

local function RenderInstances(instances)
    instances = instances or GetFilteredInstances()
    if frame.instanceScroll then
        frame.instanceScroll:SetRange(#instances, #instanceRows, instanceOffset)
    end

    for index, row in ipairs(instanceRows) do
        local instance = instances[index + instanceOffset]
        if instance then
            local starred = IsStarredSource(instance.key)
            row:Show()
            row.instance = instance
            row.starIcon:SetVertexColor(starred and 1 or 0.32, starred and 0.82 or 0.40, starred and 0.18 or 0.38, 1)
            row.text:SetText(instance.name)
            row.meta:SetText(instance.contentType)
            SetSelected(row, selectedInstance == instance)
        else
            row.instance = nil
            row:Hide()
        end
    end
end

local function RenderBosses(bosses)
    bosses = bosses or GetFilteredBosses()
    if frame.bossScroll then
        frame.bossScroll:SetRange(#bosses, #bossRows, bossOffset)
    end

    for index, row in ipairs(bossRows) do
        local boss = bosses[index + bossOffset]
        if boss then
            row:Show()
            row.boss = boss
            row.text:SetText(boss.name)
            SetSelected(row, selectedBoss == boss)
        else
            row.boss = nil
            row:Hide()
        end
    end
end

local function RefreshInstances()
    if not frame then
        return
    end

    local instances = GetFilteredInstances()
    local selectedStillVisible
    for _, instance in ipairs(instances) do
        if instance == selectedInstance then
            selectedStillVisible = true
            break
        end
    end

    if not selectedStillVisible then
        selectedInstance = instances[1]
        selectedBoss = selectedInstance and selectedInstance.bosses[1] or nil
        selectedDifficulty = selectedBoss and selectedBoss.difficulties[1] and selectedBoss.difficulties[1].id or nil
    end

    if instanceOffset > math.max(#instances - #instanceRows, 0) then
        instanceOffset = math.max(#instances - #instanceRows, 0)
    end

    RenderInstances(instances)

    RefreshBosses()
end

function Browser.Refresh()
    if not frame then
        return
    end

    EnsureLootFilters()
    UpdateIndexButton()
    UpdateFilterButton()
    frame.filterAll.text:SetText(contentFilter == "ALL" and "All" or "|cff9aa4a1All|r")
    frame.filterRaids.text:SetText(contentFilter == "RAID" and "Raids" or "|cff9aa4a1Raids|r")
    frame.filterDungeons.text:SetText(contentFilter == "DUNGEON" and "Dungeons" or "|cff9aa4a1Dungeons|r")
    RefreshInstances()
end

ScrollList = function(kind, delta)
    if kind == "instances" then
        local instances = GetFilteredInstances()
        local nextOffset = math.max(0, math.min(instanceOffset - delta, math.max(#instances - #instanceRows, 0)))
        if nextOffset ~= instanceOffset then
            instanceOffset = nextOffset
            RenderInstances(instances)
        end
        return
    elseif kind == "bosses" then
        local bosses = GetFilteredBosses()
        local nextOffset = math.max(0, math.min(bossOffset - delta, math.max(#bosses - #bossRows, 0)))
        if nextOffset ~= bossOffset then
            bossOffset = nextOffset
            RenderBosses(bosses)
        end
        return
    elseif kind == "items" then
        local items = GetCurrentItems()
        local nextOffset = math.max(0, math.min(itemOffset - delta, math.max(#items - #itemRows, 0)))
        if nextOffset ~= itemOffset then
            itemOffset = nextOffset
            RefreshItems()
        end
        return
    end
end

local hoveredTooltipRow

local function HideComparisonTooltips()
    if ShoppingTooltip1 then
        ShoppingTooltip1:Hide()
    end
    if ShoppingTooltip2 then
        ShoppingTooltip2:Hide()
    end
    if ShoppingTooltip3 then
        ShoppingTooltip3:Hide()
    end
end

local function ShowItemTooltip(row)
    if not row.itemId or not row:IsMouseOver() then
        return
    end

    if not row.itemLink then
        local _, link = GetItemInfo(row.itemId)
        if link then
            row.itemLink = link
        else
            RequestItem(row.itemId)
            return
        end
    end

    hoveredTooltipRow = row
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    if row.itemLink then
        GameTooltip:SetHyperlink(row.itemLink)
    elseif GameTooltip.SetItemByID then
        GameTooltip:SetItemByID(row.itemId)
    else
        GameTooltip:SetHyperlink("item:" .. row.itemId)
    end
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Hold Shift to compare. Ctrl-click to preview. Click Add to track.", 0.58, 0.66, 0.64)
    GameTooltip:Show()

    if GameTooltip_ShowCompareItem and IsShiftKeyDown and IsShiftKeyDown() then
        GameTooltip_ShowCompareItem(GameTooltip)
    else
        HideComparisonTooltips()
    end
end

local function HideItemTooltip()
    hoveredTooltipRow = nil
    GameTooltip:Hide()
    HideComparisonTooltips()
end

local tooltipModifierFrame = CreateFrame("Frame")
tooltipModifierFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
tooltipModifierFrame:SetScript("OnEvent", function(_, _, key, state)
    if key ~= "LSHIFT" and key ~= "RSHIFT" then
        return
    end

    if state == 1 then
        if hoveredTooltipRow and hoveredTooltipRow:IsShown() and hoveredTooltipRow:IsMouseOver() and GameTooltip:IsShown() and GameTooltip_ShowCompareItem then
            GameTooltip_ShowCompareItem(GameTooltip)
        end
    else
        HideComparisonTooltips()
    end
end)

local function ScheduleItemTooltip(row)
    if not row or not row.itemId then
        return
    end

    row.pendingTooltipItemId = row.itemId
    if C_Timer and C_Timer.After then
        C_Timer.After(TOOLTIP_HOVER_DELAY, function()
            if row:IsShown() and row:IsMouseOver() and row.itemId == row.pendingTooltipItemId then
                ShowItemTooltip(row)
            end
        end)
    else
        ShowItemTooltip(row)
    end
end

local function DressItem(row)
    if row.itemLink then
        DressUpItemLink(row.itemLink)
    else
        DressUpItemLink("item:" .. row.itemId)
    end
end

local function GetSelectedDifficultyPrefix()
    if not selectedBoss or not selectedDifficulty then
        return nil
    end

    for _, difficulty in ipairs(selectedBoss.difficulties) do
        if difficulty.id == selectedDifficulty then
            local name = tostring(difficulty.name or ""):lower()
            if name:find("celestial", 1, true) then
                return "C"
            elseif name:find("mythic", 1, true) then
                return "M"
            elseif name:find("heroic", 1, true) then
                return "H"
            elseif name:find("normal", 1, true) then
                return "N"
            end
            return nil
        end
    end

    return nil
end

local function CreateItemRow(parent, index)
    local row = CreateFrame("Button", nil, parent, Template())
    row:SetSize(ITEM_ROW_WIDTH, 34)
    row:SetPoint("TOPLEFT", 10, ITEM_ROW_TOP - ((index - 1) * 37))
    ApplyBackdrop(row, colors.row)

    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetSize(28, 28)
    row.icon:SetPoint("LEFT", 5, 0)

    row.name = CreateText(row, "", 12, colors.text)
    row.name:SetPoint("TOPLEFT", row.icon, "TOPRIGHT", 8, -3)
    row.name:SetWidth(ITEM_ROW_WIDTH - 124)

    row.meta = CreateText(row, "", 10, colors.muted)
    row.meta:SetPoint("TOPLEFT", row.name, "BOTTOMLEFT", 0, -2)

    row.add = CreateButton(row, "Add", 48, 24)
    row.add:SetPoint("RIGHT", -5, 0)
    row.add:SetScript("OnClick", function(self)
        local parent = self:GetParent()
        local itemId = parent.itemId
        local value = parent.itemLink or itemId
        local prefix = parent.difficultyPrefix or GetSelectedDifficultyPrefix()
        if itemId and Plutocraseeker.AddItemToSelectedSet(value, { difficultyPrefix = prefix, heroic = prefix == "H", source = parent.sourceMetadata }) then
            SetStatus("Added item:" .. itemId .. " to the selected set.", colors.accent)
        end
    end)

    row:SetScript("OnEnter", function(self)
        SetBackdropColor(self, colors.hover)
        ScheduleItemTooltip(self)
    end)
    row:SetScript("OnLeave", function(self)
        self.pendingTooltipItemId = nil
        SetBackdropColor(self, colors.row)
        HideItemTooltip()
    end)
    row:SetScript("OnClick", function(self)
        if self.itemId and IsControlKeyDown and IsControlKeyDown() then
            DressItem(self)
        end
    end)

    return row
end

local function RefreshFilterFrame()
    if not filterFrame then
        return
    end

    EnsureLootFilters()
    for key, checkbox in pairs(filterFrame.gearChecks or {}) do
        checkbox:SetChecked(lootFilters.gear[key])
    end
    for key, checkbox in pairs(filterFrame.slotChecks or {}) do
        checkbox:SetChecked(lootFilters.slots[key])
    end
    for key, checkbox in pairs(filterFrame.primaryStatChecks or {}) do
        checkbox:SetChecked(lootFilters.primaryStats[key])
    end
    for key, checkbox in pairs(filterFrame.secondaryStatChecks or {}) do
        checkbox:SetChecked(lootFilters.secondaryStats[key])
    end
end

local function OnLootFilterChanged()
    itemOffset = 0
    filterRevision = filterRevision + 1
    InvalidateSearchCaches()
    UpdateFilterButton()
    Browser.Refresh()
end

local function CreateFilterCheckbox(parent, option, filterTable, x, y, width)
    local checkbox = CreateCheckbox(parent, option.label, width or 125)
    checkbox:SetPoint("TOPLEFT", x, y)
    checkbox:SetChecked(filterTable[option.key])
    checkbox.OnValueChanged = function(_, checked)
        filterTable[option.key] = checked and true or false
        OnLootFilterChanged()
    end
    return checkbox
end

local function CreateFilterFrame()
    filterFrame = CreateFrame("Frame", "PlutocraseekerAtlasBrowserFilterFrame", UIParent, Template())
    filterFrame:SetSize(670, 430)
    filterFrame:SetPoint("CENTER")
    filterFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    filterFrame:SetFrameLevel(140)
    if filterFrame.SetToplevel then
        filterFrame:SetToplevel(true)
    end
    filterFrame:EnableMouse(true)
    filterFrame:SetMovable(true)
    filterFrame:RegisterForDrag("LeftButton")
    filterFrame:SetScript("OnDragStart", filterFrame.StartMoving)
    filterFrame:SetScript("OnDragStop", filterFrame.StopMovingOrSizing)
    filterFrame:Hide()
    ApplyBackdrop(filterFrame, colors.bg)
    RegisterEscapeFrame("PlutocraseekerAtlasBrowserFilterFrame")

    filterFrame.title = CreateText(filterFrame, "Loot Filters", 18, colors.accent)
    filterFrame.title:SetPoint("TOPLEFT", 18, -16)

    filterFrame.subtitle = CreateText(filterFrame, "Narrow browser items by armor proficiency, slot, and stats.", 11, colors.muted)
    filterFrame.subtitle:SetPoint("TOPLEFT", filterFrame.title, "BOTTOMLEFT", 0, -2)

    filterFrame.close = CreateButton(filterFrame, "X", 28, 26)
    filterFrame.close:SetPoint("TOPRIGHT", -12, -12)
    filterFrame.close:SetScript("OnClick", function()
        filterFrame:Hide()
    end)

    local gearPanel = CreateFrame("Frame", nil, filterFrame, Template())
    gearPanel:SetPoint("TOPLEFT", 18, -64)
    gearPanel:SetSize(150, 310)
    ApplyBackdrop(gearPanel, colors.panel)

    local gearTitle = CreateText(gearPanel, "Gear type", 13, colors.accent)
    gearTitle:SetPoint("TOPLEFT", 12, -10)

    local slotPanel = CreateFrame("Frame", nil, filterFrame, Template())
    slotPanel:SetPoint("TOPLEFT", gearPanel, "TOPRIGHT", 12, 0)
    slotPanel:SetSize(190, 310)
    ApplyBackdrop(slotPanel, colors.panel)

    local slotTitle = CreateText(slotPanel, "Slots", 13, colors.accent)
    slotTitle:SetPoint("TOPLEFT", 12, -10)

    local statPanel = CreateFrame("Frame", nil, filterFrame, Template())
    statPanel:SetPoint("TOPLEFT", slotPanel, "TOPRIGHT", 12, 0)
    statPanel:SetSize(250, 310)
    ApplyBackdrop(statPanel, colors.panel)

    local statTitle = CreateText(statPanel, "Stats", 13, colors.accent)
    statTitle:SetPoint("TOPLEFT", 12, -10)

    local primaryTitle = CreateText(statPanel, "Primary", 11, colors.muted)
    primaryTitle:SetPoint("TOPLEFT", 12, -34)

    local secondaryTitle = CreateText(statPanel, "Secondary", 11, colors.muted)
    secondaryTitle:SetPoint("TOPLEFT", 12, -176)

    EnsureLootFilters()
    filterFrame.gearChecks = {}
    for index, option in ipairs(GEAR_FILTERS) do
        filterFrame.gearChecks[option.key] = CreateFilterCheckbox(gearPanel, option, lootFilters.gear, 12, -34 - ((index - 1) * 25), 120)
    end

    filterFrame.slotChecks = {}
    for index, option in ipairs(SLOT_FILTERS) do
        local column = index > 8 and 1 or 0
        local row = ((index - 1) % 8)
        filterFrame.slotChecks[option.key] = CreateFilterCheckbox(slotPanel, option, lootFilters.slots, 12 + (column * 88), -34 - (row * 25), 82)
    end

    filterFrame.primaryStatChecks = {}
    for index, option in ipairs(PRIMARY_STAT_FILTERS) do
        filterFrame.primaryStatChecks[option.key] = CreateFilterCheckbox(statPanel, option, lootFilters.primaryStats, 12, -56 - ((index - 1) * 25), 110)
    end

    filterFrame.secondaryStatChecks = {}
    for index, option in ipairs(SECONDARY_STAT_FILTERS) do
        local column = index > 4 and 1 or 0
        local row = ((index - 1) % 4)
        filterFrame.secondaryStatChecks[option.key] = CreateFilterCheckbox(statPanel, option, lootFilters.secondaryStats, 12 + (column * 112), -200 - (row * 25), 108)
    end

    filterFrame.reset = CreateButton(filterFrame, "Select All", 90, 28)
    filterFrame.reset:SetPoint("BOTTOMLEFT", 18, 18)
    filterFrame.reset:SetScript("OnClick", function()
        for _, option in ipairs(GEAR_FILTERS) do
            lootFilters.gear[option.key] = true
        end
        for _, option in ipairs(SLOT_FILTERS) do
            lootFilters.slots[option.key] = true
        end
        for _, option in ipairs(PRIMARY_STAT_FILTERS) do
            lootFilters.primaryStats[option.key] = true
        end
        for _, option in ipairs(SECONDARY_STAT_FILTERS) do
            lootFilters.secondaryStats[option.key] = true
        end
        RefreshFilterFrame()
        OnLootFilterChanged()
    end)

    filterFrame.clear = CreateButton(filterFrame, "Deselect All", 100, 28)
    filterFrame.clear:SetPoint("LEFT", filterFrame.reset, "RIGHT", 10, 0)
    filterFrame.clear:SetScript("OnClick", function()
        for _, option in ipairs(GEAR_FILTERS) do
            lootFilters.gear[option.key] = false
        end
        for _, option in ipairs(SLOT_FILTERS) do
            lootFilters.slots[option.key] = false
        end
        for _, option in ipairs(PRIMARY_STAT_FILTERS) do
            lootFilters.primaryStats[option.key] = false
        end
        for _, option in ipairs(SECONDARY_STAT_FILTERS) do
            lootFilters.secondaryStats[option.key] = false
        end
        RefreshFilterFrame()
        OnLootFilterChanged()
    end)
end

local function CreateBrowserFrame(owner)
    frame = CreateFrame("Frame", "PlutocraseekerAtlasBrowserFrame", owner or UIParent, Template())
    frame:SetSize(BROWSER_WIDTH, BROWSER_HEIGHT)
    if owner then
        frame:SetPoint("LEFT", owner, "RIGHT", -1, 0)
        frame:SetFrameStrata(owner:GetFrameStrata())
        frame:SetFrameLevel(owner:GetFrameLevel() + 1)
    else
        frame:SetPoint("CENTER", 40, 0)
        frame:SetFrameStrata("DIALOG")
    end
    frame:EnableMouse(true)
    frame:Hide()
    frame:SetScript("OnHide", function()
        if filterFrame then
            filterFrame:Hide()
        end
    end)
    ApplyBackdrop(frame, colors.bg)
    RegisterEscapeFrame("PlutocraseekerAtlasBrowserFrame")

    frame.title = CreateText(frame, "Loot Browser", 18, colors.accent)
    frame.title:SetPoint("TOPLEFT", 18, -16)

    frame.subtitle = CreateText(frame, "AtlasLoot tables, Plutocraseeker workflow", 11, colors.muted)
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -2)

    frame.close = CreateButton(frame, "<", 28, 26)
    frame.close:SetPoint("TOPRIGHT", -12, -12)
    frame.close:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame.search = CreateEditBox(frame, 250, 28)
    frame.search:SetPoint("TOPLEFT", 18, -54)
    frame.search:SetScript("OnTextChanged", function()
        instanceOffset = 0
        bossOffset = 0
        itemOffset = 0
        InvalidateSearchCaches()
        Browser.Refresh()
    end)
    frame.searchHint = CreateText(frame.search, "Search source or encounter", 11, colors.muted)
    frame.searchHint:SetPoint("LEFT", 8, 0)
    frame.search:SetScript("OnEditFocusGained", function()
        frame.searchHint:Hide()
    end)
    frame.search:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            frame.searchHint:Show()
        end
    end)

    frame.filterAll = CreateButton(frame, "All", 64, 28)
    frame.filterAll:SetPoint("LEFT", frame.search, "RIGHT", 8, 0)
    frame.filterAll:SetScript("OnClick", function()
        contentFilter = "ALL"
        instanceOffset = 0
        bossOffset = 0
        itemOffset = 0
        ClearBrowserCaches()
        Browser.Refresh()
    end)

    frame.filterRaids = CreateButton(frame, "Raids", 64, 28)
    frame.filterRaids:SetPoint("LEFT", frame.filterAll, "RIGHT", 6, 0)
    frame.filterRaids:SetScript("OnClick", function()
        contentFilter = "RAID"
        instanceOffset = 0
        bossOffset = 0
        itemOffset = 0
        ClearBrowserCaches()
        Browser.Refresh()
    end)

    frame.filterDungeons = CreateButton(frame, "Dungeons", 82, 28)
    frame.filterDungeons:SetPoint("LEFT", frame.filterRaids, "RIGHT", 6, 0)
    frame.filterDungeons:SetScript("OnClick", function()
        contentFilter = "DUNGEON"
        instanceOffset = 0
        bossOffset = 0
        itemOffset = 0
        ClearBrowserCaches()
        Browser.Refresh()
    end)

    frame.itemSearchCheck = CreateCheckbox(frame, "Search by item", 130)
    frame.itemSearchCheck:SetPoint("LEFT", frame.filterDungeons, "RIGHT", 12, 0)
    frame.itemSearchCheck.OnValueChanged = function()
        instanceOffset = 0
        bossOffset = 0
        itemOffset = 0
        InvalidateSearchCaches()
        frame.searchHint:SetText(IsItemSearchMode() and "Search indexed items" or "Search source or encounter")
        Browser.Refresh()
    end

    frame.filterButton = CreateButton(frame, "Filter", 62, 28)
    frame.filterButton:SetPoint("LEFT", frame.itemSearchCheck, "RIGHT", 6, 0)
    frame.filterButton:SetScript("OnClick", function()
        if not filterFrame then
            CreateFilterFrame()
        end
        if filterFrame:IsShown() then
            filterFrame:Hide()
            return
        end
        RefreshFilterFrame()
        filterFrame:ClearAllPoints()
        filterFrame:SetPoint("CENTER", frame, "CENTER", 0, 0)
        filterFrame:SetFrameStrata("FULLSCREEN_DIALOG")
        filterFrame:SetFrameLevel((frame:GetFrameLevel() or 1) + 120)
        if filterFrame.Raise then
            filterFrame:Raise()
        end
        filterFrame:Show()
    end)

    frame.indexButton = CreateButton(frame, "Build Index (slow)", 148, 28)
    frame.indexButton:SetPoint("TOPRIGHT", -18, -54)
    frame.indexButton:SetScript("OnClick", StartIndexBuild)

    local instancePanel = CreateFrame("Frame", nil, frame, Template())
    instancePanel:SetPoint("TOPLEFT", 14, -94)
    instancePanel:SetSize(SOURCE_PANEL_WIDTH, LIST_PANEL_HEIGHT)
    ApplyBackdrop(instancePanel, colors.panel)

    local bossPanel = CreateFrame("Frame", nil, frame, Template())
    bossPanel:SetPoint("TOPLEFT", instancePanel, "TOPRIGHT", 10, 0)
    bossPanel:SetSize(ENCOUNTER_PANEL_WIDTH, LIST_PANEL_HEIGHT)
    ApplyBackdrop(bossPanel, colors.panel)

    local itemPanel = CreateFrame("Frame", nil, frame, Template())
    itemPanel:SetPoint("TOPLEFT", bossPanel, "TOPRIGHT", 10, 0)
    itemPanel:SetSize(ITEM_PANEL_WIDTH, LIST_PANEL_HEIGHT)
    ApplyBackdrop(itemPanel, colors.panel)

    local instanceHeader = CreateText(instancePanel, "Sources", 12, colors.muted)
    instanceHeader:SetPoint("TOPLEFT", 10, -9)
    local bossHeader = CreateText(bossPanel, "Encounters", 12, colors.muted)
    bossHeader:SetPoint("TOPLEFT", 10, -9)
    local itemHeader = CreateText(itemPanel, "Items", 12, colors.muted)
    itemHeader:SetPoint("TOPLEFT", 10, -9)

    instancePanel:EnableMouseWheel(true)
    instancePanel:SetScript("OnMouseWheel", function(_, delta)
        ScrollList("instances", delta)
    end)
    bossPanel:EnableMouseWheel(true)
    bossPanel:SetScript("OnMouseWheel", function(_, delta)
        ScrollList("bosses", delta)
    end)
    itemPanel:EnableMouseWheel(true)
    itemPanel:SetScript("OnMouseWheel", function(_, delta)
        ScrollList("items", delta)
    end)

    frame.instanceScroll = CreateScrollBar(instancePanel, "instances", 350)
    frame.instanceScroll:SetPoint("TOPRIGHT", -8, -31)
    frame.bossScroll = CreateScrollBar(bossPanel, "bosses", 350)
    frame.bossScroll:SetPoint("TOPRIGHT", -8, -31)
    frame.itemScroll = CreateScrollBar(itemPanel, "items", 280)
    frame.itemScroll:SetPoint("TOPRIGHT", -8, ITEM_ROW_TOP)

    for index = 1, 10 do
        local row = CreateButton(instancePanel, "", SOURCE_PANEL_WIDTH - 34, 31)
        row:SetPoint("TOPLEFT", 10, -31 - ((index - 1) * 34))
        row.starIcon = row:CreateTexture(nil, "ARTWORK")
        row.starIcon:SetTexture("Interface\\Common\\ReputationStar")
        row.starIcon:SetSize(14, 14)
        row.starIcon:SetPoint("LEFT", 8, 0)
        row.text:ClearAllPoints()
        row.text:SetPoint("TOPLEFT", 28, -4)
        row.text:SetWidth(SOURCE_PANEL_WIDTH - 72)
        row.meta = CreateText(row, "", 10, colors.muted)
        row.meta:SetPoint("TOPLEFT", row.text, "BOTTOMLEFT", 0, -2)
        row:SetScript("OnClick", function(self)
            if self.instance then
                if IsShiftKeyDown and IsShiftKeyDown() then
                    ToggleStarredSource(self.instance.key)
                else
                    selectedInstance = self.instance
                    selectedBoss = selectedInstance.bosses[1]
                    selectedDifficulty = selectedBoss and selectedBoss.difficulties[1] and selectedBoss.difficulties[1].id
                    bossOffset = 0
                    itemOffset = 0
                    ClearBrowserCaches()
                end
                Browser.Refresh()
            end
        end)
        instanceRows[index] = row
    end

    for index = 1, 10 do
        local row = CreateButton(bossPanel, "", ENCOUNTER_PANEL_WIDTH - 34, 28)
        row:SetPoint("TOPLEFT", 10, -31 - ((index - 1) * 33))
        row.text:SetWidth(ENCOUNTER_PANEL_WIDTH - 52)
        row:SetScript("OnClick", function(self)
            if self.boss then
                selectedBoss = self.boss
                selectedDifficulty = selectedBoss.difficulties[1] and selectedBoss.difficulties[1].id
                itemOffset = 0
                currentItemsCache = nil
                Browser.Refresh()
            end
        end)
        bossRows[index] = row
    end

    frame.difficultyButtons = {}
    for index = 1, 8 do
        local button = CreateButton(itemPanel, "", 92, 25)
        button:SetPoint("TOPLEFT", 10, -31)
        button:SetScript("OnClick", function(self)
            if self.difficultyId then
                selectedDifficulty = self.difficultyId
                itemOffset = 0
                currentItemsCache = nil
                Browser.Refresh()
            end
        end)
        frame.difficultyButtons[index] = button
    end

    for index = 1, 8 do
        itemRows[index] = CreateItemRow(itemPanel, index)
    end

    frame.status = CreateText(frame, "", 11, colors.muted)
    frame.status:SetPoint("BOTTOMLEFT", 18, 16)

    frame:SetScript("OnUpdate", function(_, elapsed)
        ProcessIndexBuild(elapsed)
    end)

    UpdateIndexButton()
end

local function AttachToOwner(owner)
    if not frame or not owner then
        return
    end

    frame:SetParent(owner)
    frame:ClearAllPoints()
    frame:SetPoint("LEFT", owner, "RIGHT", -1, 0)
    frame:SetFrameStrata(owner:GetFrameStrata())
    frame:SetFrameLevel(owner:GetFrameLevel() + 1)
end

function Browser.Open(owner)
    if not frame then
        CreateBrowserFrame(owner)
    elseif owner then
        AttachToOwner(owner)
    end

    frame:Show()
    SetStatus("Loading AtlasLoot tables...")

    local ok, reason = Browser.LoadData()
    if not ok then
        SetStatus(tostring(reason), colors.warn)
        return
    end

    Browser.Refresh()
end

function Browser.Hide()
    if frame then
        frame:Hide()
    end
end

function Browser.Toggle(owner)
    if frame and frame:IsShown() then
        frame:Hide()
    else
        Browser.Open(owner)
    end
end

local refreshFrame = CreateFrame("Frame")
refreshFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
refreshFrame:SetScript("OnEvent", function()
    if indexBuilder then
        return
    end

    if not frame or not frame:IsShown() or pendingBrowserItemRefresh then
        return
    end

    pendingBrowserItemRefresh = true
    local function RefreshAfterItemInfo()
        pendingBrowserItemRefresh = false
        if not frame or not frame:IsShown() then
            return
        end

        InvalidateSearchCaches()
        Browser.Refresh()
    end

    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, RefreshAfterItemInfo)
    else
        RefreshAfterItemInfo()
    end
end)
