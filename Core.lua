local ADDON_NAME, Plutocraseeker = ...

Plutocraseeker.name = ADDON_NAME
Plutocraseeker.version = "0.1.0"
Plutocraseeker.itemPattern = "item:(%d+)"
Plutocraseeker.alertCooldown = 30
Plutocraseeker.lastAlerts = {}
Plutocraseeker.playerItemCache = {}
Plutocraseeker.playerInventoryCache = nil
Plutocraseeker.tooltipStatusCache = {}
Plutocraseeker.playerItemCacheTTL = 1.5

local DEFAULT_DB = {
    sets = {},
    selectedSetId = nil,
    nextSetId = 1,
    minimap = {},
    starredSources = {},
    itemSearchIndex = {},
    targetNpcIndex = {},
    config = {
        alertOnMention = true,
        onlyLootMasterAlerts = true,
        showTargetLootAlerts = true,
        alertAnchor = {},
    },
}

local function CopyDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            CopyDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

local function Print(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cff6ee7b7Plutocraseeker|r " .. tostring(message))
end

Plutocraseeker.Print = Print

local function GetItemIdFromLinkOrText(value)
    if not value then
        return nil
    end

    local text = tostring(value)
    local linkedId = text:match(Plutocraseeker.itemPattern)
    if linkedId then
        return tonumber(linkedId)
    end

    local plainId = text:match("^%s*(%d+)%s*$")
    if plainId then
        return tonumber(plainId)
    end

    return nil
end

Plutocraseeker.GetItemIdFromLinkOrText = GetItemIdFromLinkOrText

function Plutocraseeker.GetItemIdFromWowheadLink(value)
    local text = tostring(value or "")
    local itemId = text:match("[?&/]item=(%d+)")
    if itemId then
        return tonumber(itemId)
    end

    return nil
end

local WOWHEAD_GEAR_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"

local function WowheadAlphabetIndex(char)
    local index = WOWHEAD_GEAR_ALPHABET:find(char, 1, true)
    return index and index - 1 or 0
end

local function NumberHasBit(value, bitValue)
    return value and (value % (bitValue * 2)) >= bitValue
end

local function ShiftRight(value, bits)
    return math.floor((value or 0) / (2 ^ bits))
end

local function BitAnd(value, mask)
    local result = 0
    local bitValue = 1
    value = value or 0
    mask = mask or 0

    while value > 0 and mask > 0 do
        if value % 2 == 1 and mask % 2 == 1 then
            result = result + bitValue
        end
        value = math.floor(value / 2)
        mask = math.floor(mask / 2)
        bitValue = bitValue * 2
    end

    return result
end

local function ReadWowheadBits(values)
    if not values or #values == 0 then
        return 0
    end

    local total = 0
    local byteCount = 1
    local marker = values[1]

    while NumberHasBit(marker, 32) do
        byteCount = byteCount + 1
        marker = marker * 2
    end

    local mask = ShiftRight(63, byteCount)
    local value = BitAnd(table.remove(values, 1), mask)
    byteCount = byteCount - 1

    for index = 1, byteCount do
        total = total + (2 ^ (5 * index))
        value = (value * 64) + (table.remove(values, 1) or 0)
    end

    return value + total
end

local function ParseWowheadTalentString(values)
    local talentString = ""
    local value = ReadWowheadBits(values)

    while value ~= 0 do
        talentString = talentString .. tostring(BitAnd(value, 3))
        value = ShiftRight(value, 2)
    end

    return talentString
end

local function ParseWowheadGearPlannerHash(path)
    local classId, raceId, encoded = tostring(path or ""):match("^([a-z%-]+)/([a-z%-]+)/([A-Za-z0-9_%-]+)")
    if not classId or not raceId or not encoded or encoded == "" then
        return nil
    end

    local version = WowheadAlphabetIndex(encoded:sub(1, 1))
    if version > 4 then
        return nil
    end

    local values = {}
    for index = 2, #encoded do
        values[#values + 1] = WowheadAlphabetIndex(encoded:sub(index, index))
    end

    if version >= 2 then
        ReadWowheadBits(values)
    end

    ReadWowheadBits(values) -- gender + 1
    ReadWowheadBits(values) -- level

    if version >= 4 then
        ReadWowheadBits(values) -- spec index
    end

    ParseWowheadTalentString(values)

    local extraStringCount = ReadWowheadBits(values)
    for _ = 1, extraStringCount do
        local length = ReadWowheadBits(values)
        for _ = 1, length do
            table.remove(values, 1)
        end
    end

    local itemCount = ReadWowheadBits(values)
    local items = {}

    for _ = 1, itemCount do
        local hasRandomEnchant = false
        local hasUpgradeRank = false
        local hasReforge = false
        local gemCount = 0
        local enchantCount = 0

        if version == 0 then
            local flags = table.remove(values, 1) or 0
            hasRandomEnchant = NumberHasBit(ShiftRight(flags, 5), 1)
            gemCount = BitAnd(ShiftRight(flags, 2), 7)
            enchantCount = BitAnd(flags, 3)
        elseif version == 1 or version == 2 then
            local flags = ReadWowheadBits(values)
            hasRandomEnchant = NumberHasBit(ShiftRight(flags, 6), 1)
            hasReforge = NumberHasBit(ShiftRight(flags, 5), 1)
            gemCount = BitAnd(ShiftRight(flags, 2), 7)
            enchantCount = BitAnd(flags, 3)
        else
            local flags = ReadWowheadBits(values)
            hasRandomEnchant = NumberHasBit(ShiftRight(flags, 7), 1)
            hasUpgradeRank = NumberHasBit(ShiftRight(flags, 6), 1)
            hasReforge = NumberHasBit(ShiftRight(flags, 5), 1)
            gemCount = BitAnd(ShiftRight(flags, 2), 7)
            enchantCount = BitAnd(flags, 3)
        end

        local item = {
            slotId = ReadWowheadBits(values),
            itemId = ReadWowheadBits(values),
        }

        if hasRandomEnchant then
            local randomEnchant = ReadWowheadBits(values)
            local isNegative = BitAnd(randomEnchant, 1) == 1
            randomEnchant = ShiftRight(randomEnchant, 1)
            if isNegative then
                randomEnchant = randomEnchant * -1
            end
            item.randomEnchantId = randomEnchant
        end

        if hasUpgradeRank then
            item.upgradeRank = ReadWowheadBits(values)
        end

        if hasReforge then
            item.reforge = ReadWowheadBits(values)
        end

        for _ = 1, gemCount do
            ReadWowheadBits(values)
        end

        for _ = 1, enchantCount do
            ReadWowheadBits(values)
        end

        if item.itemId and item.itemId > 0 then
            items[#items + 1] = item
        end
    end

    return {
        classId = classId,
        raceId = raceId,
        items = items,
    }
end

function Plutocraseeker.GetItemIdsFromWowheadGearPlannerLink(value)
    local text = tostring(value or "")
    local path = text:match("mop%-classic/gear%-planner/(.+)")
    if not path then
        path = text:match("^%s*([a-z%-]+/[a-z%-]+/[A-Za-z0-9_%-]+)%s*$")
    end

    local parsed = ParseWowheadGearPlannerHash(path)
    local itemIds = {}
    local seen = {}

    if not parsed or not parsed.items then
        return itemIds
    end

    for _, item in ipairs(parsed.items) do
        local itemId = tonumber(item.itemId)
        if itemId and not seen[itemId] then
            seen[itemId] = true
            itemIds[#itemIds + 1] = itemId
        end
    end

    return itemIds
end

local scanTooltip

local function GetScanTooltip()
    if not scanTooltip then
        scanTooltip = CreateFrame("GameTooltip", "PlutocraseekerScanTooltip", UIParent, "GameTooltipTemplate")
        scanTooltip:SetOwner(UIParent, "ANCHOR_NONE")
    end
    return scanTooltip
end

local function GetTooltipLine(tooltip, index)
    local line = tooltip and tooltip:GetName() and _G[tooltip:GetName() .. "TextLeft" .. tostring(index)]
    return line and line:GetText() or nil
end

local function GetDifficultyPrefixFromText(text)
    text = tostring(text or ""):lower()
    if text:find("celestial", 1, true) then
        return "C"
    elseif text:find("mythic", 1, true) then
        return "M"
    elseif text:find("heroic", 1, true) then
        return "H"
    end
    return nil
end

local function GetDifficultyPrefixFromTooltipData(data)
    if not data or not data.lines then
        return nil
    end

    for _, line in ipairs(data.lines) do
        local text = line and (line.leftText or line.text)
        local prefix = GetDifficultyPrefixFromText(text)
        if prefix then
            return prefix
        end
    end

    return nil
end

local function GetTooltipInfoData(itemId, link)
    if not C_TooltipInfo then
        return nil
    end

    if link and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
        if ok and data then
            return data
        end
    end

    if itemId and C_TooltipInfo.GetItemByID then
        local ok, data = pcall(C_TooltipInfo.GetItemByID, itemId)
        if ok and data then
            return data
        end
    end

    if itemId and C_TooltipInfo.GetHyperlink then
        local ok, data = pcall(C_TooltipInfo.GetHyperlink, "item:" .. tostring(itemId))
        if ok and data then
            return data
        end
    end

    return nil
end

function Plutocraseeker.GetItemInfo(itemId)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(itemId)
    end

    return GetItemInfo(itemId)
end

function Plutocraseeker.RequestItemInfo(itemId)
    if itemId and C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemId)
    end
end

function Plutocraseeker.GetItemName(itemId)
    local name, link = Plutocraseeker.GetItemInfo(itemId)
    if link and link ~= "" then
        return link
    end

    if name and name ~= "" then
        return name
    end

    Plutocraseeker.RequestItemInfo(itemId)
    return "Item " .. tostring(itemId)
end

function Plutocraseeker.GetDifficultyPrefixForItem(itemId, value, requestIfMissing)
    if not itemId then
        return nil
    end

    if requestIfMissing == nil then
        requestIfMissing = true
    end

    local inputLink = type(value) == "string" and value:match("(|c%x+|Hitem:[^|]+|h%[[^%]]+%]|h|r)") or nil
    local name, link = Plutocraseeker.GetItemInfo(itemId)
    if not inputLink and not name and not link then
        if requestIfMissing then
            Plutocraseeker.RequestItemInfo(itemId)
        end
        return nil
    end

    local tooltipData = GetTooltipInfoData(itemId, inputLink or link)
    local dataPrefix = GetDifficultyPrefixFromTooltipData(tooltipData)
    if dataPrefix then
        return dataPrefix
    end

    local tooltip = GetScanTooltip()
    tooltip:SetOwner(UIParent, "ANCHOR_NONE")
    tooltip:ClearLines()

    if inputLink then
        tooltip:SetHyperlink(inputLink)
    elseif link then
        tooltip:SetHyperlink(link)
    elseif tooltip.SetItemByID then
        tooltip:SetItemByID(itemId)
    else
        tooltip:SetHyperlink("item:" .. tostring(itemId))
    end

    local lineCount = tooltip:NumLines()
    if lineCount < 2 then
        tooltip:Hide()
        if requestIfMissing then
            Plutocraseeker.RequestItemInfo(itemId)
        end
        return nil
    end

    for index = 2, lineCount do
        local prefix = GetDifficultyPrefixFromText(GetTooltipLine(tooltip, index))
        if prefix then
            tooltip:Hide()
            return prefix
        end
    end

    tooltip:Hide()
    return "N"
end

local function EnsureDB()
    if not PlutocraseekerDB and BisSetDB then
        PlutocraseekerDB = BisSetDB
    end

    PlutocraseekerDB = PlutocraseekerDB or {}
    CopyDefaults(PlutocraseekerDB, DEFAULT_DB)
    Plutocraseeker.db = PlutocraseekerDB

    if #Plutocraseeker.db.sets == 0 then
        Plutocraseeker.CreateSet("Default")
    elseif not Plutocraseeker.db.selectedSetId then
        Plutocraseeker.db.selectedSetId = Plutocraseeker.db.sets[1].id
    end
end

local function FindSetIndex(setId)
    if not Plutocraseeker.db then
        return nil
    end

    for index, set in ipairs(Plutocraseeker.db.sets) do
        if set.id == setId then
            return index
        end
    end
    return nil
end

function Plutocraseeker.GetSet(setId)
    local index = FindSetIndex(setId or Plutocraseeker.db.selectedSetId)
    return index and Plutocraseeker.db.sets[index] or nil
end

function Plutocraseeker.GetSelectedSet()
    return Plutocraseeker.GetSet(Plutocraseeker.db.selectedSetId)
end

function Plutocraseeker.SelectSet(setId)
    if FindSetIndex(setId) then
        Plutocraseeker.db.selectedSetId = setId
        Plutocraseeker.RefreshUI()
    end
end

function Plutocraseeker.CreateSet(name)
    local cleanName = tostring(name or ""):match("^%s*(.-)%s*$")
    if cleanName == "" then
        cleanName = "New Set"
    end

    Plutocraseeker.db.nextSetId = Plutocraseeker.db.nextSetId or 1
    local set = {
        id = Plutocraseeker.db.nextSetId,
        name = cleanName,
        enabled = true,
        items = {},
    }
    Plutocraseeker.db.nextSetId = Plutocraseeker.db.nextSetId + 1
    table.insert(Plutocraseeker.db.sets, set)
    Plutocraseeker.db.selectedSetId = set.id
    Plutocraseeker.ClearTooltipStatusCache()
    Plutocraseeker.RefreshUI()
    return set
end

function Plutocraseeker.DeleteSelectedSet()
    local selectedId = Plutocraseeker.db.selectedSetId
    local index = FindSetIndex(selectedId)
    if not index then
        return
    end

    table.remove(Plutocraseeker.db.sets, index)

    if #Plutocraseeker.db.sets == 0 then
        Plutocraseeker.CreateSet("Default")
    else
        local nextSet = Plutocraseeker.db.sets[math.min(index, #Plutocraseeker.db.sets)]
        Plutocraseeker.db.selectedSetId = nextSet.id
    end

    Plutocraseeker.RebuildTargetNpcIndex()
    Plutocraseeker.ClearTooltipStatusCache()
    Plutocraseeker.RefreshUI()
end

function Plutocraseeker.SetSelectedSetName(name)
    local set = Plutocraseeker.GetSelectedSet()
    if not set then
        return
    end

    local cleanName = tostring(name or ""):match("^%s*(.-)%s*$")
    if cleanName ~= "" then
        set.name = cleanName
        Plutocraseeker.RefreshUI()
    end
end

function Plutocraseeker.ToggleSelectedSet(enabled)
    local set = Plutocraseeker.GetSelectedSet()
    if set then
        set.enabled = not not enabled
        Plutocraseeker.RebuildTargetNpcIndex()
        Plutocraseeker.ClearTooltipStatusCache()
        Plutocraseeker.RefreshUI()
    end
end

local function FindItem(set, itemId)
    if not set or not itemId then
        return nil
    end

    for index, item in ipairs(set.items) do
        if item.id == itemId then
            return index, item
        end
    end

    return nil
end

local function AddUniqueNumber(list, value)
    value = tonumber(value)
    if not value then
        return
    end

    for _, existing in ipairs(list) do
        if tonumber(existing) == value then
            return
        end
    end

    list[#list + 1] = value
end

local function AddNpcIds(target, source)
    if not target or not source then
        return
    end

    if type(source) == "table" then
        for _, value in ipairs(source) do
            AddUniqueNumber(target, value)
        end
    else
        AddUniqueNumber(target, source)
    end
end

local function MergeItemSourceMetadata(item, source)
    if not item or type(source) ~= "table" then
        return false
    end

    local changed = false
    item.source = item.source or {}

    if source.instanceKey and item.source.instanceKey ~= source.instanceKey then
        item.source.instanceKey = source.instanceKey
        changed = true
    end
    if source.instanceName and item.source.instanceName ~= source.instanceName then
        item.source.instanceName = source.instanceName
        changed = true
    end
    if source.bossIndex and item.source.bossIndex ~= source.bossIndex then
        item.source.bossIndex = source.bossIndex
        changed = true
    end
    if source.bossName and item.source.bossName ~= source.bossName then
        item.source.bossName = source.bossName
        changed = true
    end
    if source.difficultyId and item.source.difficultyId ~= source.difficultyId then
        item.source.difficultyId = source.difficultyId
        changed = true
    end
    if source.difficultyName and item.source.difficultyName ~= source.difficultyName then
        item.source.difficultyName = source.difficultyName
        changed = true
    end

    local npcIds = item.source.npcIDs or {}
    local before = #npcIds
    AddNpcIds(npcIds, source.npcIDs)
    AddNpcIds(npcIds, source.npcID)
    AddNpcIds(npcIds, source.npcId)
    if #npcIds ~= before then
        item.source.npcIDs = npcIds
        changed = true
    end

    return changed
end

local function GetIndexedItemSource(itemId)
    local index = Plutocraseeker.db and Plutocraseeker.db.itemSearchIndex
    local indexedItem = index and index.itemsById and index.itemsById[tonumber(itemId)]
    if not indexedItem or type(indexedItem.sources) ~= "table" then
        return nil
    end

    local result
    for _, source in ipairs(indexedItem.sources) do
        if type(source) == "table" then
            result = result or {
                instanceKey = source.instanceKey,
                instanceName = source.instanceName,
                bossIndex = source.bossIndex,
                bossName = source.bossName,
                difficultyId = source.difficultyId,
                difficultyName = source.difficultyName,
                npcIDs = {},
            }
            AddNpcIds(result.npcIDs, source.npcIDs)
            AddNpcIds(result.npcIDs, source.npcID)
            AddNpcIds(result.npcIDs, source.npcId)
        end
    end

    return result
end

function Plutocraseeker.MergeTrackedItemSourceMetadata(itemId, source)
    itemId = tonumber(itemId)
    if not itemId or not Plutocraseeker.db or type(source) ~= "table" then
        return 0
    end

    local changed = 0
    for _, set in ipairs(Plutocraseeker.db.sets or {}) do
        local _, item = FindItem(set, itemId)
        if item and MergeItemSourceMetadata(item, source) then
            changed = changed + 1
        end
    end

    if changed > 0 then
        Plutocraseeker.RebuildTargetNpcIndex()
    end

    return changed
end

function Plutocraseeker.EnrichTrackedItemSourcesFromIndex()
    if not Plutocraseeker.db then
        return 0
    end

    local changed = 0
    for _, set in ipairs(Plutocraseeker.db.sets or {}) do
        for _, item in ipairs(set.items or {}) do
            if item and item.id and MergeItemSourceMetadata(item, GetIndexedItemSource(item.id)) then
                changed = changed + 1
            end
        end
    end

    if changed > 0 then
        Plutocraseeker.RebuildTargetNpcIndex()
    end

    return changed
end

function Plutocraseeker.RebuildTargetNpcIndex()
    if not Plutocraseeker.db then
        return nil
    end

    local index = {}
    for _, set in ipairs(Plutocraseeker.db.sets or {}) do
        for _, item in ipairs(set.items or {}) do
            local itemId = tonumber(item and item.id)
            local source = item and item.source
            if itemId and source and type(source.npcIDs) == "table" then
                for _, npcId in ipairs(source.npcIDs) do
                    npcId = tonumber(npcId)
                    if npcId then
                        local bucket = index[npcId]
                        if not bucket then
                            bucket = {
                                itemIds = {},
                                items = {},
                                sources = {},
                            }
                            index[npcId] = bucket
                        end

                        if not bucket.items[itemId] then
                            bucket.items[itemId] = true
                            bucket.itemIds[#bucket.itemIds + 1] = itemId
                        end
                        bucket.sources[itemId] = bucket.sources[itemId] or {
                            instanceName = source.instanceName,
                            bossName = source.bossName,
                            difficultyId = source.difficultyId,
                            difficultyName = source.difficultyName,
                            difficultyPrefix = source.difficultyPrefix,
                        }
                    end
                end
            end
        end
    end

    Plutocraseeker.db.targetNpcIndex = index
    return index
end

local function GetTargetNpcIndex()
    if not Plutocraseeker.db then
        return {}
    end

    if type(Plutocraseeker.db.targetNpcIndex) ~= "table" then
        return Plutocraseeker.RebuildTargetNpcIndex() or {}
    end

    return Plutocraseeker.db.targetNpcIndex
end

function Plutocraseeker.IsTrackedItem(itemId)
    itemId = tonumber(itemId)
    if not itemId or not Plutocraseeker.db then
        return false
    end

    for _, set in ipairs(Plutocraseeker.db.sets or {}) do
        if FindItem(set, itemId) then
            return true
        end
    end

    return false
end

function Plutocraseeker.BackfillTrackedItemDifficulty(itemId, requestIfMissing)
    itemId = tonumber(itemId)
    if not itemId or not Plutocraseeker.db then
        return false
    end

    local prefix = Plutocraseeker.GetDifficultyPrefixForItem(itemId, nil, requestIfMissing)
    if not prefix then
        return false, nil
    end

    local changed = false
    for _, set in ipairs(Plutocraseeker.db.sets or {}) do
        local _, item = FindItem(set, itemId)
        local shouldUpdate = item and (not item.difficultyPrefix or (item.difficultyPrefix == "N" and prefix ~= "N"))
        if shouldUpdate then
            item.difficultyPrefix = prefix
            item.heroic = nil
            changed = true
        end
    end

    return changed, prefix
end

function Plutocraseeker.BackfillSetItemDifficulties(set, requestIfMissing)
    set = set or Plutocraseeker.GetSelectedSet()
    if not set then
        return 0, 0, 0, 0
    end

    local changed = 0
    local checked = 0
    local unresolved = 0
    local cached = 0

    for _, item in ipairs(set.items or {}) do
        if item and item.id and (not item.difficultyPrefix or item.difficultyPrefix == "N" or item.heroic) then
            checked = checked + 1
            local name, link = Plutocraseeker.GetItemInfo(item.id)
            if name or link then
                cached = cached + 1
            end

            local prefix = Plutocraseeker.GetDifficultyPrefixForItem(item.id, nil, requestIfMissing)
            if prefix then
                local nextPrefix = prefix
                if item.heroic and prefix == "N" then
                    nextPrefix = "H"
                end

                if not item.difficultyPrefix or item.difficultyPrefix ~= nextPrefix or item.heroic then
                    item.difficultyPrefix = nextPrefix
                    item.heroic = nil
                    changed = changed + 1
                end
            else
                unresolved = unresolved + 1
            end
        end
    end

    return changed, checked, unresolved, cached
end

function Plutocraseeker.RefreshSelectedSetDifficulties(requestIfMissing)
    local set = Plutocraseeker.GetSelectedSet()
    if not set then
        Print("No set selected.")
        return false
    end

    local changed, checked, unresolved, cached = Plutocraseeker.BackfillSetItemDifficulties(set, requestIfMissing)
    local tooltipApi = C_TooltipInfo and "yes" or "no"
    Print("Refresh checked " .. tostring(checked) .. " item(s), updated " .. tostring(changed) .. " marker(s), " .. tostring(unresolved) .. " unresolved, " .. tostring(cached) .. " cached. Tooltip API: " .. tooltipApi .. ".")
    Plutocraseeker.RefreshUI()
    return changed > 0
end

function Plutocraseeker.AddItemToSelectedSet(value, options)
    local itemId = GetItemIdFromLinkOrText(value)
    local set = Plutocraseeker.GetSelectedSet()
    if not set or not itemId then
        Print("Enter an item ID or paste an item link.")
        return false
    end

    local _, existingItem = FindItem(set, itemId)
    local sourceOptions = options and options.source or GetIndexedItemSource(itemId)
    if existingItem then
        local sourceChanged = MergeItemSourceMetadata(existingItem, sourceOptions)
        local detectedPrefix = Plutocraseeker.GetDifficultyPrefixForItem(itemId, value)
        local fallbackPrefix = options and options.difficultyPrefix or nil
        local correctedPrefix = detectedPrefix
        if fallbackPrefix and (not detectedPrefix or detectedPrefix == "N") then
            correctedPrefix = fallbackPrefix
        end
        if correctedPrefix and correctedPrefix ~= existingItem.difficultyPrefix then
            existingItem.difficultyPrefix = correctedPrefix
            existingItem.heroic = nil
            Plutocraseeker.RebuildTargetNpcIndex()
            Plutocraseeker.ClearTooltipStatusCache()
            Print(Plutocraseeker.GetItemName(itemId) .. " is already in " .. set.name .. " and its metadata was updated.")
            Plutocraseeker.RefreshUI()
            return true
        end
        if sourceChanged then
            Plutocraseeker.RebuildTargetNpcIndex()
            Plutocraseeker.ClearTooltipStatusCache()
            Print(Plutocraseeker.GetItemName(itemId) .. " is already in " .. set.name .. " and its source was updated.")
            Plutocraseeker.RefreshUI()
            return true
        end
        Print(Plutocraseeker.GetItemName(itemId) .. " is already in " .. set.name .. ".")
        return false
    end

    local detectedPrefix = Plutocraseeker.GetDifficultyPrefixForItem(itemId, value)
    local fallbackPrefix = options and options.difficultyPrefix or nil
    local difficultyPrefix = detectedPrefix
    if fallbackPrefix and (not detectedPrefix or detectedPrefix == "N") then
        difficultyPrefix = fallbackPrefix
    end

    local item = {
        id = itemId,
        difficultyPrefix = difficultyPrefix,
        heroic = nil,
        addedAt = time(),
    }
    MergeItemSourceMetadata(item, sourceOptions)
    table.insert(set.items, item)

    Plutocraseeker.RequestItemInfo(itemId)
    Plutocraseeker.BackfillTrackedItemDifficulty(itemId, false)
    Plutocraseeker.RebuildTargetNpcIndex()
    Plutocraseeker.ClearTooltipStatusCache()

    Print("Added " .. Plutocraseeker.GetItemName(itemId) .. " to " .. set.name .. ".")
    Plutocraseeker.RefreshUI()
    return true
end

function Plutocraseeker.RemoveItemFromSelectedSet(itemId)
    local set = Plutocraseeker.GetSelectedSet()
    local index = FindItem(set, itemId)
    if index then
        table.remove(set.items, index)
        Plutocraseeker.RebuildTargetNpcIndex()
        Plutocraseeker.ClearTooltipStatusCache()
        Plutocraseeker.RefreshUI()
    end
end

function Plutocraseeker.GetMatchingSets(itemId)
    local matches = {}
    for _, set in ipairs(Plutocraseeker.db.sets) do
        if set.enabled and FindItem(set, itemId) then
            table.insert(matches, set)
        end
    end
    return matches
end

local function GetBagItemId(bag, slot)
    if C_Container and C_Container.GetContainerItemID then
        return C_Container.GetContainerItemID(bag, slot)
    end

    if GetContainerItemID then
        return GetContainerItemID(bag, slot)
    end

    local link
    if C_Container and C_Container.GetContainerItemLink then
        link = C_Container.GetContainerItemLink(bag, slot)
    elseif GetContainerItemLink then
        link = GetContainerItemLink(bag, slot)
    end

    return GetItemIdFromLinkOrText(link)
end

local function BuildPlayerInventorySnapshot()
    local items = {}
    for slot = 1, 19 do
        local itemId = GetInventoryItemID("player", slot)
        if itemId then
            items[itemId] = true
        end
    end

    for bag = 0, 4 do
        local slots = 0
        if C_Container and C_Container.GetContainerNumSlots then
            slots = C_Container.GetContainerNumSlots(bag) or 0
        elseif GetContainerNumSlots then
            slots = GetContainerNumSlots(bag) or 0
        end

        for slot = 1, slots do
            local itemId = GetBagItemId(bag, slot)
            if itemId then
                items[itemId] = true
            end
        end
    end

    return items
end

function Plutocraseeker.PlayerHasItem(itemId)
    itemId = tonumber(itemId)
    if not itemId then
        return false
    end

    local now = GetTime and GetTime() or time()
    local inventory = Plutocraseeker.playerInventoryCache
    if not inventory or now - inventory.time >= Plutocraseeker.playerItemCacheTTL then
        inventory = {
            time = now,
            items = BuildPlayerInventorySnapshot(),
        }
        Plutocraseeker.playerInventoryCache = inventory
        Plutocraseeker.playerItemCache = {}
    end

    local cached = Plutocraseeker.playerItemCache[itemId]
    if cached and now - cached.time < Plutocraseeker.playerItemCacheTTL then
        return cached.hasItem
    end

    local hasItem = inventory.items[itemId] and true or false
    Plutocraseeker.playerItemCache[itemId] = {
        hasItem = hasItem,
        time = now,
    }
    return hasItem
end

function Plutocraseeker.ClearPlayerItemCache()
    Plutocraseeker.playerItemCache = {}
    Plutocraseeker.playerInventoryCache = nil
    Plutocraseeker.tooltipStatusCache = {}
end

function Plutocraseeker.ClearTooltipStatusCache()
    Plutocraseeker.tooltipStatusCache = {}
end

local function JoinSetNames(sets)
    local names = {}
    for _, set in ipairs(sets) do
        table.insert(names, set.name)
    end
    return table.concat(names, ", ")
end

local function ShortPlayerName(name)
    name = tostring(name or "")
    if Ambiguate then
        name = Ambiguate(name, "short")
    end
    name = name:match("^([^%-]+)") or name
    return name:lower()
end

local function NamesMatch(left, right)
    return ShortPlayerName(left) ~= "" and ShortPlayerName(left) == ShortPlayerName(right)
end

local function FullUnitName(unit)
    if not unit or not UnitExists or not UnitExists(unit) then
        return nil
    end

    if UnitFullName then
        local name, realm = UnitFullName(unit)
        if name and name ~= "" then
            if realm and realm ~= "" then
                return name .. "-" .. realm
            end
            return name
        end
    end

    return UnitName(unit)
end

local function GetMasterLooterFromRoster()
    if not GetRaidRosterInfo then
        return nil
    end

    local count = 0
    if GetNumGroupMembers then
        count = GetNumGroupMembers() or 0
    elseif GetNumRaidMembers then
        count = GetNumRaidMembers() or 0
    end

    for index = 1, count do
        local name, _, _, _, _, _, _, _, _, _, isMasterLooter = GetRaidRosterInfo(index)
        if isMasterLooter then
            return name
        end
    end

    return nil
end

function Plutocraseeker.GetMasterLooterName()
    local rosterMasterLooter = GetMasterLooterFromRoster()
    if rosterMasterLooter then
        return rosterMasterLooter
    end

    if not GetLootMethod then
        return nil
    end

    local method, partyId, raidId = GetLootMethod()
    if method ~= "master" and method ~= 2 then
        return nil
    end

    if raidId and raidId > 0 then
        return FullUnitName("raid" .. tostring(raidId))
    end

    if partyId == 0 then
        return FullUnitName("player")
    elseif partyId and partyId > 0 then
        return FullUnitName("party" .. tostring(partyId))
    end

    return nil
end

function Plutocraseeker.ShouldAlertForSender(sender)
    if not Plutocraseeker.db or not Plutocraseeker.db.config then
        return true
    end

    if Plutocraseeker.db.config.alertOnMention == false then
        return false
    end

    if not Plutocraseeker.db.config.onlyLootMasterAlerts then
        return true
    end

    local masterLooterName = Plutocraseeker.GetMasterLooterName()
    return masterLooterName and NamesMatch(sender, masterLooterName)
end

local function AddTooltipStatus(tooltip)
    if not tooltip or not tooltip.GetItem or not Plutocraseeker.db then
        return
    end

    local _, link = tooltip:GetItem()
    local itemId = GetItemIdFromLinkOrText(link)
    if not itemId then
        return
    end

    local now = GetTime and GetTime() or time()
    local cached = Plutocraseeker.tooltipStatusCache[itemId]
    if not cached or now - cached.time >= Plutocraseeker.playerItemCacheTTL then
        local matches = Plutocraseeker.GetMatchingSets(itemId)
        if #matches == 0 then
            cached = {
                time = now,
                hasMatches = false,
            }
        else
            cached = {
                time = now,
                hasMatches = true,
                setText = JoinSetNames(matches),
                hasItem = Plutocraseeker.PlayerHasItem(itemId),
            }
        end
        Plutocraseeker.tooltipStatusCache[itemId] = cached
    end

    if not cached.hasMatches then
        return
    end

    tooltip:AddLine(" ")
    tooltip:AddDoubleLine("|cff6ee7b7Plutocraseeker|r", cached.setText, 0.43, 0.91, 0.72, 0.58, 0.66, 0.64)

    if cached.hasItem then
        tooltip:AddLine("ACQUIRED", 0.25, 0.90, 0.35)
    else
        tooltip:AddLine("WANTED", 1.0, 0.18, 0.18)
    end
    tooltip:AddLine(" ")

    tooltip:Show()
end

local function HookTooltip(tooltip)
    if tooltip and not tooltip.PlutocraseekerHooked then
        tooltip:HookScript("OnTooltipSetItem", AddTooltipStatus)
        tooltip.PlutocraseekerHooked = true
    end
end

local function InitializeTooltipHooks()
    HookTooltip(GameTooltip)
    HookTooltip(ItemRefTooltip)
end

local function BuildAlertMatch(itemId, link, source)
    if Plutocraseeker.PlayerHasItem(itemId) then
        return nil
    end

    local matches = Plutocraseeker.GetMatchingSets(itemId)
    if #matches == 0 then
        return nil
    end

    local setText = JoinSetNames(matches)
    local alertSource = source
    if type(alertSource) ~= "table" then
        alertSource = {}
    end

    if not alertSource.difficultyPrefix then
        for _, set in ipairs(Plutocraseeker.db.sets or {}) do
            local _, item = FindItem(set, itemId)
            if item and item.difficultyPrefix then
                alertSource.difficultyPrefix = item.difficultyPrefix
                break
            end
        end
    end

    return {
        itemId = itemId,
        itemText = link or Plutocraseeker.GetItemName(itemId),
        setText = setText,
        source = alertSource,
        cooldownKey = tostring(itemId) .. ":" .. setText,
    }
end

local function JoinAlertItemNames(matches)
    local names = {}
    for index, match in ipairs(matches) do
        names[index] = match.itemText
    end
    return table.concat(names, ", ")
end

local function AlertForItems(items, context)
    if not items or #items == 0 then
        return
    end

    context = context or {}
    if context.source == "chat" and not Plutocraseeker.ShouldAlertForSender(context.sender) then
        return
    end

    local now = time()
    local seen = {}
    local alertMatches = {}

    for _, item in ipairs(items) do
        local itemId = tonumber(item.itemId)
        if itemId and not seen[itemId] then
            seen[itemId] = true
            local match = BuildAlertMatch(itemId, item.link, item.source)
            if match then
                local lastAlert = Plutocraseeker.lastAlerts[match.cooldownKey]
                if context.force or not lastAlert or now - lastAlert >= Plutocraseeker.alertCooldown then
                    Plutocraseeker.lastAlerts[match.cooldownKey] = now
                    alertMatches[#alertMatches + 1] = match
                end
            end
        end
    end

    if #alertMatches == 0 then
        return
    end

    local sender = context.sender
    local senderText = sender and sender ~= "" and (" from " .. sender) or ""
    local sourceText = context.source == "loot" and " found in loot window"
        or (context.source == "target" and (" from " .. tostring(context.bossName or context.targetName or "target")))
        or senderText
    local message
    if #alertMatches == 1 then
        local match = alertMatches[1]
        message = match.itemText .. " matched " .. match.setText .. sourceText .. "."
    else
        message = tostring(#alertMatches) .. " wanted items matched" .. sourceText .. ": " .. JoinAlertItemNames(alertMatches) .. "."
    end

    Print(message)

    if Plutocraseeker.UI and Plutocraseeker.UI.ShowLootAlert then
        Plutocraseeker.UI.ShowLootAlert(alertMatches, {
            source = context.source,
            sender = sender,
            bossName = context.bossName,
            targetName = context.targetName,
        })
    else
        StaticPopupDialogs["Plutocraseeker_LOOT_MATCH"] = StaticPopupDialogs["Plutocraseeker_LOOT_MATCH"] or {
            text = "%s",
            button1 = OKAY,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
        StaticPopup_Show("Plutocraseeker_LOOT_MATCH", "Plutocraseeker: " .. message)
    end
end

local function GetNpcIdFromGuid(guid)
    if not guid then
        return nil
    end

    local _, _, _, _, _, npcId = strsplit("-", tostring(guid))
    return tonumber(npcId)
end

local function ScanTargetForWantedLoot(options)
    options = options or {}
    local config = Plutocraseeker.db and Plutocraseeker.db.config or {}
    if config.showTargetLootAlerts == false and not options.force then
        return false, "Boss target loot alerts are disabled."
    end

    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        return false, "Boss target loot alerts are disabled in combat."
    end

    if not UnitExists or not UnitExists("target") then
        return false, "No target selected."
    end

    local npcId = GetNpcIdFromGuid(UnitGUID("target"))
    if not npcId then
        return false, "Current target is not a tracked NPC."
    end

    local bucket = GetTargetNpcIndex()[npcId]
    if options.force and (not bucket or type(bucket.items) ~= "table") and Plutocraseeker.AtlasBrowser and Plutocraseeker.AtlasBrowser.EnrichTrackedItemSourcesFromCache then
        Plutocraseeker.AtlasBrowser.EnrichTrackedItemSourcesFromCache()
        bucket = GetTargetNpcIndex()[npcId]
    end

    if not bucket or type(bucket.items) ~= "table" then
        return false, "No coveted loot is mapped to this target."
    end

    local items = {}
    local itemIds = type(bucket.itemIds) == "table" and bucket.itemIds or nil
    if itemIds then
        for _, itemId in ipairs(itemIds) do
            items[#items + 1] = {
                itemId = itemId,
                source = bucket.sources and bucket.sources[itemId] or nil,
            }
        end
    else
        for itemId in pairs(bucket.items) do
            items[#items + 1] = {
                itemId = itemId,
                source = bucket.sources and bucket.sources[itemId] or nil,
            }
        end
    end

    if #items == 0 then
        return false, "No coveted loot is mapped to this target."
    end

    local targetName = UnitName and UnitName("target") or nil
    local bossName
    for _, source in pairs(bucket.sources or {}) do
        bossName = source and source.bossName
        if bossName then
            break
        end
    end

    AlertForItems(items, {
        source = "target",
        targetName = targetName,
        bossName = targetName or bossName,
        force = options.force,
    })
    return true
end

local function ScanChatMessage(message, sender)
    if not message or message == "" then
        return
    end

    local seen = {}
    local items = {}
    for itemString in message:gmatch(Plutocraseeker.itemPattern) do
        local itemId = tonumber(itemString)
        if itemId and not seen[itemId] then
            seen[itemId] = true
            local link = message:match("(|c%x+|Hitem:" .. itemString .. ":[^|]+|h%[[^%]]+%]|h|r)")
            items[#items + 1] = {
                itemId = itemId,
                link = link,
            }
        end
    end

    AlertForItems(items, {
        source = "chat",
        sender = sender,
    })
end

local function ScanLootWindow()
    if not GetNumLootItems or not GetLootSlotLink then
        return
    end

    local items = {}
    for slot = 1, GetNumLootItems() do
        local link = GetLootSlotLink(slot)
        local itemId = GetItemIdFromLinkOrText(link)
        if itemId then
            items[#items + 1] = {
                itemId = itemId,
                link = link,
            }
        end
    end

    AlertForItems(items, {
        source = "loot",
    })
end

function Plutocraseeker.RefreshUI()
    if Plutocraseeker.UI and Plutocraseeker.UI.Refresh then
        Plutocraseeker.UI.Refresh()
    end
end

function Plutocraseeker.ToggleUI()
    if Plutocraseeker.UI and Plutocraseeker.UI.Toggle then
        Plutocraseeker.UI.Toggle()
    end
end

local pendingItemInfoRefresh = false
local pendingItemInfoIds = {}

local function RefreshResolvedItemInfo()
    local itemIds = pendingItemInfoIds
    pendingItemInfoIds = {}
    pendingItemInfoRefresh = false

    for itemId in pairs(itemIds) do
        Plutocraseeker.BackfillTrackedItemDifficulty(itemId, false)
    end

    Plutocraseeker.RefreshUI()
end

local function ScheduleItemInfoRefresh(itemId)
    itemId = tonumber(itemId)
    if itemId then
        pendingItemInfoIds[itemId] = true
    end

    if pendingItemInfoRefresh then
        return
    end

    pendingItemInfoRefresh = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, RefreshResolvedItemInfo)
    else
        RefreshResolvedItemInfo()
    end
end

function Plutocraseeker.OpenAtlasLoot()
    if IsAddOnLoaded and not IsAddOnLoaded("AtlasLootClassic") and LoadAddOn then
        pcall(LoadAddOn, "AtlasLootClassic")
    end

    if AtlasLoot and AtlasLoot.GUI and AtlasLoot.GUI.Toggle then
        AtlasLoot.GUI:Toggle()
        return true
    end

    if AtlasLoot and AtlasLoot.Toggle then
        AtlasLoot:Toggle()
        return true
    end

    if SlashCmdList and SlashCmdList.ATLASLOOT then
        SlashCmdList.ATLASLOOT("")
        return true
    end

    Print("AtlasLootClassic was not found. You can still paste item links or enter item IDs.")
    return false
end

function Plutocraseeker.OpenLootBrowser()
    if Plutocraseeker.UI and Plutocraseeker.UI.OpenLootBrowser then
        Plutocraseeker.UI.OpenLootBrowser()
    elseif Plutocraseeker.AtlasBrowser and Plutocraseeker.AtlasBrowser.Open then
        Plutocraseeker.AtlasBrowser.Open()
    else
        Print("Loot browser is not loaded.")
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("CHAT_MSG_RAID")
eventFrame:RegisterEvent("CHAT_MSG_RAID_LEADER")
eventFrame:RegisterEvent("CHAT_MSG_RAID_WARNING")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("PARTY_LOOT_METHOD_CHANGED")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
eventFrame:RegisterEvent("LOOT_OPENED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")

eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        local loadedName = ...
        if loadedName == ADDON_NAME then
            EnsureDB()
            Plutocraseeker.RebuildTargetNpcIndex()
            InitializeTooltipHooks()
            if Plutocraseeker.UI and Plutocraseeker.UI.Initialize then
                Plutocraseeker.UI.Initialize()
            end
            Print("loaded. Type /ps to manage loot sets.")
        end
        return
    end

    if event == "GET_ITEM_INFO_RECEIVED" then
        local itemId, success = ...
        if success ~= false and Plutocraseeker.IsTrackedItem(itemId) then
            ScheduleItemInfoRefresh(itemId)
        end
        return
    end

    if event == "LOOT_OPENED" then
        ScanLootWindow()
        if C_Timer and C_Timer.After then
            C_Timer.After(0.1, ScanLootWindow)
        end
        return
    end

    if event == "PLAYER_TARGET_CHANGED" then
        ScanTargetForWantedLoot()
        return
    end

    if event == "BAG_UPDATE_DELAYED" or event == "PLAYER_EQUIPMENT_CHANGED" then
        Plutocraseeker.ClearPlayerItemCache()
        return
    end

    if event == "PARTY_LOOT_METHOD_CHANGED" or event == "GROUP_ROSTER_UPDATE" then
        if Plutocraseeker.UI and Plutocraseeker.UI.RefreshConfig then
            Plutocraseeker.UI.RefreshConfig()
        elseif Plutocraseeker.RefreshUI then
            Plutocraseeker.RefreshUI()
        end
        return
    end

    local message, sender = ...
    ScanChatMessage(message, sender)
end)

SLASH_PLUTOCRASEEKER1 = "/plutocraseeker"
SLASH_PLUTOCRASEEKER2 = "/ps"
SlashCmdList.PLUTOCRASEEKER = function(input)
    local command, rest = tostring(input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command and command:lower() or ""

    if command == "add" and rest ~= "" then
        Plutocraseeker.AddItemToSelectedSet(rest)
    elseif command == "refresh" then
        Plutocraseeker.RefreshSelectedSetDifficulties(true)
    elseif command == "scanboss" then
        local ok, reason = ScanTargetForWantedLoot({ force = true })
        if not ok and reason then
            Print(reason)
        end
    elseif command == "browse" or command == "loot" then
        Plutocraseeker.OpenLootBrowser()
    elseif command == "atlasloot" or command == "al" then
        Plutocraseeker.OpenAtlasLoot()
    elseif command == "new" and rest ~= "" then
        Plutocraseeker.CreateSet(rest)
    else
        Plutocraseeker.ToggleUI()
    end
end
