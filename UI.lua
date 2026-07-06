local ADDON_NAME, Plutocraseeker = ...

Plutocraseeker.UI = Plutocraseeker.UI or {}

local UI = Plutocraseeker.UI
local mainFrame
local configFrame
local alertFrame
local mentionAlertFrame
local anchorOverlay
local importFrame
local wowheadImportFrame
local characterImportFrame
local exportFrame
local confirmDeleteFrame
local receivedItemFrame
local receivedItemQueue = {}
local receivedItemHandledAt = {}
local setRows = {}
local itemRows = {}
local itemOffset = 0
local ScrollItems
local RefreshAlertTooltipRows
local TOOLTIP_HOVER_DELAY = 0.25
local MAIN_FRAME_HEIGHT = 520
local MAIN_PANEL_HEIGHT = 396
local ALERT_MAX_HEIGHT = 420
local ALERT_FRAME_WIDTH = 500
local ALERT_ITEM_VIEW_HEIGHT = 184
local ALERT_DEFAULT_TOP_OFFSET = -180
local RECEIVED_ITEM_DEDUPE_SECONDS = 5
local colors = {
    bg = { 0.055, 0.065, 0.075, 0.96 },
    panel = { 0.085, 0.095, 0.11, 0.96 },
    hover = { 0.13, 0.16, 0.18, 1 },
    selected = { 0.11, 0.32, 0.28, 1 },
    border = { 0.22, 0.28, 0.30, 1 },
    accent = { 0.31, 0.82, 0.62, 1 },
    text = { 0.9, 0.95, 0.93, 1 },
    muted = { 0.58, 0.66, 0.64, 1 },
}

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

local function Template()
    return BackdropTemplateMixin and "BackdropTemplate" or nil
end

local function ApplyBackdrop(frame, color)
    if not frame.SetBackdrop then
        return
    end

    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(unpack(color or colors.panel))
    frame:SetBackdropBorderColor(unpack(colors.border))
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
    button:SetSize(width or 92, height or 28)
    ApplyBackdrop(button, colors.panel)

    button.text = CreateText(button, text, 12)
    button.text:SetPoint("CENTER")

    button:SetScript("OnEnter", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(unpack(colors.hover))
        end
        if self.tooltipTitle or self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if self.tooltipTitle then
                GameTooltip:AddLine(self.tooltipTitle, 0.31, 0.82, 0.62)
            end
            if self.tooltipText then
                GameTooltip:AddLine(self.tooltipText, 0.9, 0.95, 0.93, true)
            end
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        if self.SetBackdropColor then
            self:SetBackdropColor(unpack(self._selected and colors.selected or colors.panel))
        end
        if self.tooltipTitle or self.tooltipText then
            GameTooltip:Hide()
        end
    end)

    return button
end

local function SetButtonTooltip(button, title, text)
    if not button then
        return
    end

    button.tooltipTitle = title
    button.tooltipText = text
end

local function CreateScrollBar(parent, height)
    local bar = CreateFrame("Frame", nil, parent, Template())
    bar:SetSize(12, height)
    ApplyBackdrop(bar, { 0.045, 0.052, 0.06, 1 })

    bar.up = CreateButton(bar, "^", 12, 18)
    bar.up:SetPoint("TOP", 0, 0)
    bar.up:SetScript("OnClick", function()
        if ScrollItems then
            ScrollItems(1)
        end
    end)

    bar.down = CreateButton(bar, "v", 12, 18)
    bar.down:SetPoint("BOTTOM", 0, 0)
    bar.down:SetScript("OnClick", function()
        if ScrollItems then
            ScrollItems(-1)
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

local function SetAlertItemScroll(frame, offset)
    if not frame or not frame.itemScroll then
        return
    end

    local maxScroll = frame.itemMaxScroll or 0
    offset = math.max(0, math.min(offset or 0, maxScroll))
    frame.itemScroll:SetVerticalScroll(offset)
    frame.itemScrollOffset = offset

    local bar = frame.itemScrollBar
    if not bar then
        return
    end

    if maxScroll <= 0 then
        bar:Hide()
        return
    end

    bar:Show()
    bar.up.text:SetText(offset > 0 and "^" or "|cff3f4947^|r")
    bar.down.text:SetText(offset < maxScroll and "v" or "|cff3f4947v|r")

    local trackHeight = bar.height - 42
    local contentHeight = frame.itemContentHeight or ALERT_ITEM_VIEW_HEIGHT
    local viewHeight = frame.itemViewHeight or ALERT_ITEM_VIEW_HEIGHT
    local thumbHeight = math.max(24, math.floor(trackHeight * (viewHeight / math.max(contentHeight, 1))))
    local travel = math.max(trackHeight - thumbHeight, 1)
    local y = -21 - math.floor(travel * (offset / math.max(maxScroll, 1)))

    bar.thumb:SetHeight(thumbHeight)
    bar.thumb:ClearAllPoints()
    bar.thumb:SetPoint("TOP", bar, "TOP", 0, y)
end

local function CreateAlertScrollBar(parent, height)
    local bar = CreateFrame("Frame", nil, parent, Template())
    bar:SetSize(12, height)
    bar.height = height
    ApplyBackdrop(bar, { 0.045, 0.052, 0.06, 1 })

    bar.up = CreateButton(bar, "^", 12, 18)
    bar.up:SetPoint("TOP", 0, 0)
    bar.up:SetScript("OnClick", function()
        SetAlertItemScroll(parent, (parent.itemScrollOffset or 0) - 24)
    end)

    bar.down = CreateButton(bar, "v", 12, 18)
    bar.down:SetPoint("BOTTOM", 0, 0)
    bar.down:SetScript("OnClick", function()
        SetAlertItemScroll(parent, (parent.itemScrollOffset or 0) + 24)
    end)

    bar.thumb = CreateFrame("Frame", nil, bar, Template())
    bar.thumb:SetSize(8, 34)
    ApplyBackdrop(bar.thumb, colors.selected)
    bar:Hide()

    return bar
end

local function CreateCheckbox(parent, text, width)
    local button = CreateFrame("Button", nil, parent, Template())
    button:SetSize(width or 300, 28)

    button.box = CreateFrame("Frame", nil, button, Template())
    button.box:SetSize(18, 18)
    button.box:SetPoint("LEFT", 0, 0)
    ApplyBackdrop(button.box, { 0.045, 0.052, 0.06, 1 })

    button.check = button.box:CreateTexture(nil, "ARTWORK")
    button.check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    button.check:SetAllPoints(button.box)
    button.check:Hide()

    button.text = CreateText(button, text, 12, colors.text)
    button.text:SetPoint("LEFT", button.box, "RIGHT", 8, 0)

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
    function button:SetEnabledVisual(enabled)
        self.visualEnabled = enabled ~= false
        self.text:SetTextColor(unpack(self.visualEnabled and colors.text or colors.muted))
        if self.box.SetBackdropBorderColor then
            self.box:SetBackdropBorderColor(unpack(self.visualEnabled and colors.border or { 0.12, 0.15, 0.16, 1 }))
        end
    end

    button:SetScript("OnEnter", function(self)
        self.text:SetTextColor(unpack(self.visualEnabled == false and colors.muted or colors.accent))
    end)
    button:SetScript("OnLeave", function(self)
        self.text:SetTextColor(unpack(self.visualEnabled == false and colors.muted or colors.text))
    end)
    button:SetScript("OnClick", function(self)
        if self.visualEnabled == false then
            return
        end
        self:SetChecked(not self:GetChecked())
        if self.OnValueChanged then
            self:OnValueChanged(self:GetChecked())
        end
    end)
    button:SetEnabledVisual(true)

    return button
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

local function SetButtonSelected(button, selected)
    button._selected = selected
    if button.SetBackdropColor then
        button:SetBackdropColor(unpack(selected and colors.selected or colors.panel))
    end
end

local function PlayAlertSound()
    local sound = SOUNDKIT and (SOUNDKIT.UI_GUILD_INVITE or SOUNDKIT.LEVEL_UP)
    if sound and PlaySound then
        PlaySound(sound, "Master")
    elseif PlaySoundFile then
        PlaySoundFile("Sound\\Interface\\LevelUp.ogg", "Master")
    end
end

local function GetAlertAnchorConfig()
    if not Plutocraseeker.db then
        return nil
    end

    Plutocraseeker.db.config = Plutocraseeker.db.config or {}
    Plutocraseeker.db.config.alertAnchor = Plutocraseeker.db.config.alertAnchor or {}
    return Plutocraseeker.db.config.alertAnchor
end

local function ApplyAlertAnchor(frame)
    if not frame then
        return
    end

    frame:ClearAllPoints()
    local anchor = GetAlertAnchorConfig()
    if anchor and anchor.x and anchor.y then
        frame:SetPoint("CENTER", UIParent, "CENTER", anchor.x, anchor.y)
    else
        frame:SetPoint("TOP", UIParent, "TOP", 0, ALERT_DEFAULT_TOP_OFFSET)
    end
end

local function GetAlertMatchKey(match)
    if not match then
        return nil
    end
    return match.cooldownKey or (tostring(match.itemId or "") .. ":" .. tostring(match.setText or ""))
end

local function IsAlertKeyVisible(key)
    if not key or key == ":" then
        return false
    end
    if alertFrame and alertFrame:IsShown() and alertFrame.alertKeys and alertFrame.alertKeys[key] then
        return true
    end
    if mentionAlertFrame and mentionAlertFrame:IsShown() and mentionAlertFrame.alertKeys and mentionAlertFrame.alertKeys[key] then
        return true
    end
    return false
end

local function FilterVisibleAlertMatches(matches)
    local filtered = {}
    for _, match in ipairs(matches or {}) do
        local key = GetAlertMatchKey(match)
        if not IsAlertKeyVisible(key) then
            filtered[#filtered + 1] = match
        end
    end
    return filtered
end

local function PositionAlertStack()
    local previousFrame

    if alertFrame and alertFrame:IsShown() then
        ApplyAlertAnchor(alertFrame)
        previousFrame = alertFrame
    end

    if mentionAlertFrame and mentionAlertFrame:IsShown() then
        mentionAlertFrame:ClearAllPoints()
        if previousFrame then
            mentionAlertFrame:SetPoint("TOP", previousFrame, "BOTTOM", 0, 0)
        else
            ApplyAlertAnchor(mentionAlertFrame)
        end
        previousFrame = mentionAlertFrame
    end

    if receivedItemFrame and receivedItemFrame:IsShown() then
        receivedItemFrame:ClearAllPoints()
        if previousFrame then
            receivedItemFrame:SetPoint("TOP", previousFrame, "BOTTOM", 0, 0)
        else
            ApplyAlertAnchor(receivedItemFrame)
        end
    end
end

local function SaveAlertAnchorFromFrame(frame)
    local anchor = GetAlertAnchorConfig()
    if not anchor or not frame then
        return
    end

    local frameCenterX, frameCenterY = frame:GetCenter()
    local uiCenterX, uiCenterY = UIParent:GetCenter()
    if not frameCenterX or not frameCenterY or not uiCenterX or not uiCenterY then
        return
    end

    anchor.x = math.floor((frameCenterX - uiCenterX) + 0.5)
    anchor.y = math.floor((frameCenterY - uiCenterY) + 0.5)
end

local function ResetAlertAnchor()
    local anchor = GetAlertAnchorConfig()
    if anchor then
        anchor.x = nil
        anchor.y = nil
    end

    PositionAlertStack()
end

local function CreateAlertFrame(frameName)
    local frame = CreateFrame("Frame", frameName, UIParent, Template())
    frame:SetSize(ALERT_FRAME_WIDTH, 220)
    ApplyAlertAnchor(frame)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    if frame.SetClampedToScreen then
        frame:SetClampedToScreen(true)
    end
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    frame:SetScript("OnHide", function(self)
        self.alertKeys = nil
        PositionAlertStack()
    end)
    ApplyBackdrop(frame, colors.bg)
    RegisterEscapeFrame(frameName)

    frame.title = CreateText(frame, "Plutocraseeker Loot Match", 18, colors.accent)
    frame.title:SetPoint("TOPLEFT", 18, -16)

    frame.context = CreateText(frame, "", 12, colors.muted)
    frame.context:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -10)
    frame.context:SetWidth(390)

    frame.motivation = CreateText(frame, "This mob possesses wealth that you wish to acquire.", 12, { 1.0, 0.82, 0.18, 1 })
    frame.motivation:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -10)
    frame.motivation:SetWidth(450)
    frame.motivation:Hide()

    frame.earnIt = CreateText(frame, "GO EARN IT!", 13, { 1.0, 0.82, 0.18, 1 })
    frame.earnIt:SetPoint("TOPLEFT", frame.motivation, "BOTTOMLEFT", 0, -2)
    frame.earnIt:SetWidth(110)
    frame.earnIt:Hide()

    frame.earnItPulse = frame.earnIt:CreateAnimationGroup()
    frame.earnItPulse:SetLooping("BOUNCE")
    frame.earnItPulse.fade = frame.earnItPulse:CreateAnimation("Alpha")
    frame.earnItPulse.fade:SetFromAlpha(1)
    frame.earnItPulse.fade:SetToAlpha(0.35)
    frame.earnItPulse.fade:SetDuration(0.55)

    frame.itemScroll = CreateFrame("ScrollFrame", nil, frame)
    frame.itemScroll:SetPoint("TOPLEFT", frame.context, "BOTTOMLEFT", 0, -12)
    frame.itemScroll:SetSize(450, ALERT_ITEM_VIEW_HEIGHT)
    frame.itemScroll:EnableMouseWheel(true)
    frame.itemScroll:SetScript("OnMouseWheel", function(_, delta)
        SetAlertItemScroll(frame, (frame.itemScrollOffset or 0) - (delta * 24))
    end)

    frame.itemScrollChild = CreateFrame("Frame", nil, frame.itemScroll)
    frame.itemScrollChild:SetSize(450, 1)
    frame.itemScroll:SetScrollChild(frame.itemScrollChild)

    frame.itemScrollBar = CreateAlertScrollBar(frame, ALERT_ITEM_VIEW_HEIGHT)
    frame.itemScrollBar:SetPoint("TOPLEFT", frame.itemScroll, "TOPRIGHT", 6, 0)

    frame.close = CreateButton(frame, "X", 28, 26)
    frame.close:SetPoint("TOPRIGHT", -12, -12)
    frame.close:SetScript("OnClick", function()
        frame:Hide()
    end)

    frame.dismiss = CreateButton(frame, "Dismiss", 82, 28)
    frame.dismiss:SetPoint("BOTTOMRIGHT", -14, 14)
    frame.dismiss:SetScript("OnClick", function()
        frame:Hide()
    end)

    return frame
end

local function BuildAlertLine(match)
    return tostring(match.itemText or "Tracked item") .. " |cff9aa4a1(" .. tostring(match.setText or "Unknown set") .. ")|r"
end

local function IsHeroicAlertMatch(match)
    local source = match and match.source
    local difficultyText = ""
    local difficultyPrefix = ""
    if type(source) == "table" then
        difficultyText = tostring(source.difficultyName or "")
        difficultyPrefix = tostring(source.difficultyPrefix or "")
    end
    if difficultyPrefix == "H" then
        return true
    end
    return difficultyText:lower():find("heroic", 1, true) and true or false
end

local function BuildGroupedTargetAlertLines(matches)
    local normal = {}
    local heroic = {}

    for _, match in ipairs(matches or {}) do
        local target = IsHeroicAlertMatch(match) and heroic or normal
        target[#target + 1] = match
    end

    local lines = {}
    local lineData = {}
    lines[#lines + 1] = "|cff6ee7b7Normal|r"
    lineData[#lineData + 1] = {
        text = lines[#lines],
    }
    if #normal == 0 then
        lines[#lines + 1] = "|cff9aa4a1None|r"
        lineData[#lineData + 1] = {
            text = lines[#lines],
        }
    else
        for _, match in ipairs(normal) do
            lines[#lines + 1] = BuildAlertLine(match)
            lineData[#lineData + 1] = {
                text = lines[#lines],
                itemId = match.itemId,
            }
        end
    end

    lines[#lines + 1] = ""
    lineData[#lineData + 1] = {
        text = lines[#lines],
    }
    lines[#lines + 1] = "|cff6ee7b7Heroic|r"
    lineData[#lineData + 1] = {
        text = lines[#lines],
    }
    if #heroic == 0 then
        lines[#lines + 1] = "|cff9aa4a1None|r"
        lineData[#lineData + 1] = {
            text = lines[#lines],
        }
    else
        for _, match in ipairs(heroic) do
            lines[#lines + 1] = BuildAlertLine(match)
            lineData[#lineData + 1] = {
                text = lines[#lines],
                itemId = match.itemId,
            }
        end
    end

    return table.concat(lines, "\n"), #lines, lineData
end

local function BuildAlertLines(matches, context)
    if context and context.source == "target" then
        return BuildGroupedTargetAlertLines(matches)
    end

    local lines = {}
    local lineData = {}
    for index, match in ipairs(matches or {}) do
        lines[index] = BuildAlertLine(match)
        lineData[index] = {
            text = lines[index],
            itemId = match.itemId,
        }
    end
    return table.concat(lines, "\n"), #lines, lineData
end

function UI.ShowLootAlert(matchesOrItemText, setTextOrContext, sender)
    local matches
    local context = {}
    if type(matchesOrItemText) == "table" then
        matches = matchesOrItemText
        context = setTextOrContext or {}
    else
        matches = {
            {
                itemText = matchesOrItemText or "Tracked item",
                setText = setTextOrContext or "Unknown set",
            },
        }
        context.sender = sender
        context.source = sender and "chat" or "loot"
    end

    matches = FilterVisibleAlertMatches(matches)
    if #matches == 0 then
        return
    end

    local frame
    if context.source == "chat" then
        if not mentionAlertFrame then
            mentionAlertFrame = CreateAlertFrame("PlutocraseekerMentionAlertFrame")
        end
        frame = mentionAlertFrame
    else
        if not alertFrame then
            alertFrame = CreateAlertFrame("PlutocraseekerLootAlertFrame")
        end
        frame = alertFrame
    end

    if context.source == "loot" then
        frame.context:SetText("Found in loot window")
    elseif context.source == "roll" then
        frame.context:SetText("Available to roll")
    elseif context.source == "target" then
        frame.context:SetText("Targeted: " .. tostring(context.bossName or context.targetName or "tracked boss"))
    elseif context.sender and context.sender ~= "" then
        frame.context:SetText("Mentioned by: " .. context.sender)
    else
        frame.context:SetText("Wanted item matched")
    end

    frame.itemScroll:ClearAllPoints()
    if context.source == "target" then
        frame.motivation:Show()
        frame.earnIt:SetAlpha(1)
        frame.earnIt:Show()
        if frame.earnItPulse then
            frame.earnItPulse:Play()
        end
        frame.context:ClearAllPoints()
        frame.context:SetPoint("TOPLEFT", frame.earnIt, "BOTTOMLEFT", 0, -8)
        frame.itemScroll:SetPoint("TOPLEFT", frame.context, "BOTTOMLEFT", 0, -12)
    else
        if frame.earnItPulse then
            frame.earnItPulse:Stop()
        end
        frame.earnIt:SetAlpha(1)
        frame.earnIt:Hide()
        frame.motivation:Hide()
        frame.context:ClearAllPoints()
        frame.context:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -10)
        frame.itemScroll:SetPoint("TOPLEFT", frame.context, "BOTTOMLEFT", 0, -12)
    end

    local _, lineCount, lineData = BuildAlertLines(matches, context)
    local lineHeight = context.source == "chat" and 44 or 20
    local contentHeight = math.max((lineCount or #matches) * lineHeight, 1)
    local viewHeight = math.min(contentHeight, ALERT_ITEM_VIEW_HEIGHT)
    frame.itemContentHeight = contentHeight
    frame.itemViewHeight = viewHeight
    frame.itemMaxScroll = math.max(contentHeight - viewHeight, 0)
    frame.itemScroll:SetSize(450, viewHeight)
    frame.itemScrollChild:SetSize(450, contentHeight)
    frame.itemScrollBar:SetHeight(viewHeight)
    frame.itemScrollBar.height = viewHeight
    SetAlertItemScroll(frame, 0)
    if RefreshAlertTooltipRows then
        RefreshAlertTooltipRows(frame, lineData, lineHeight)
    end

    frame.alertKeys = {}
    for _, match in ipairs(matches) do
        local key = GetAlertMatchKey(match)
        if key then
            frame.alertKeys[key] = true
        end
    end

    local extraHeight = context.source == "target" and 42 or 0
    frame:SetHeight(math.min(160 + extraHeight + viewHeight, ALERT_MAX_HEIGHT))
    frame:Show()
    PositionAlertStack()
    PlayAlertSound()
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

    hoveredTooltipRow = row
    local link
    if Plutocraseeker.GetItemInfo then
        local _, itemLink = Plutocraseeker.GetItemInfo(row.itemId)
        link = itemLink
    end
    if not link then
        if Plutocraseeker.RequestItemInfo then
            Plutocraseeker.RequestItemInfo(row.itemId)
        end
        return
    end

    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetHyperlink(link)
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

RefreshAlertTooltipRows = function(frame, lineData, lineHeight)
    if not frame or not frame.itemScrollChild then
        return
    end

    frame.alertTooltipRows = frame.alertTooltipRows or {}
    lineHeight = lineHeight or 20
    lineData = lineData or {}
    HideItemTooltip()

    for index, data in ipairs(lineData) do
        local row = frame.alertTooltipRows[index]
        if not row then
            row = CreateFrame("Button", nil, frame.itemScrollChild)
            row:SetSize(430, lineHeight)
            row:EnableMouse(true)
            row:EnableMouseWheel(true)
            row.text = CreateText(row, "", 13, colors.text)
            row.text:SetPoint("LEFT", 0, 0)
            row.text:SetWidth(430)
            row:SetScript("OnEnter", function(self)
                if self.itemId then
                    ScheduleItemTooltip(self)
                end
            end)
            row:SetScript("OnLeave", function()
                HideItemTooltip()
            end)
            row:SetScript("OnMouseWheel", function(self, delta)
                SetAlertItemScroll(self.alertFrame, ((self.alertFrame and self.alertFrame.itemScrollOffset) or 0) - (delta * 24))
            end)
            frame.alertTooltipRows[index] = row
        end

        row.alertFrame = frame
        row.itemId = tonumber(data and data.itemId)
        row.pendingTooltipItemId = nil
        row.text:SetText(tostring(data and data.text or ""))
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", frame.itemScrollChild, "TOPLEFT", 0, -((index - 1) * lineHeight))
        row:SetSize(430, lineHeight)
        row:SetHeight(lineHeight)
        if data then
            row:Show()
        else
            row:Hide()
        end
    end

    for index = #lineData + 1, #frame.alertTooltipRows do
        local row = frame.alertTooltipRows[index]
        row.alertFrame = nil
        row.itemId = nil
        row.pendingTooltipItemId = nil
        if row.text then
            row.text:SetText("")
        end
        row:Hide()
    end
end

local function FindJsonArrayEnd(text, openIndex)
    local depth = 0
    local inString = false
    local escaped = false

    for index = openIndex, #text do
        local char = text:sub(index, index)
        if inString then
            if escaped then
                escaped = false
            elseif char == "\\" then
                escaped = true
            elseif char == "\"" then
                inString = false
            end
        elseif char == "\"" then
            inString = true
        elseif char == "[" then
            depth = depth + 1
        elseif char == "]" then
            depth = depth - 1
            if depth == 0 then
                return index
            end
        end
    end

    return nil
end

local function ExtractWowSimsItemIds(text)
    text = tostring(text or "")

    local equipmentStart = text:find('"equipment"', 1, true)
    if not equipmentStart then
        return {}
    end

    local itemsKeyStart = text:find('"items"', equipmentStart, true)
    if not itemsKeyStart then
        return {}
    end

    local arrayStart = text:find("%[", itemsKeyStart)
    if not arrayStart then
        return {}
    end

    local arrayEnd = FindJsonArrayEnd(text, arrayStart)
    if not arrayEnd then
        return {}
    end

    local itemArray = text:sub(arrayStart, arrayEnd)
    local itemIds = {}
    local seen = {}
    for itemId in itemArray:gmatch('%"id%"%s*:%s*(%d+)') do
        itemId = tonumber(itemId)
        if itemId and not seen[itemId] then
            seen[itemId] = true
            itemIds[#itemIds + 1] = itemId
        end
    end

    return itemIds
end

local function ImportWowSimsJson(text, setName)
    local itemIds = ExtractWowSimsItemIds(text)
    if #itemIds == 0 then
        if Plutocraseeker.Print then
            Plutocraseeker.Print("No equipment item IDs were found in the WoWSims export.")
        end
        return false
    end

    itemOffset = 0
    Plutocraseeker.CreateSet(setName)

    local added = 0
    for _, itemId in ipairs(itemIds) do
        if Plutocraseeker.AddItemToSelectedSet(itemId) then
            added = added + 1
        end
    end

    if Plutocraseeker.Print then
        Plutocraseeker.Print("Imported " .. tostring(added) .. " of " .. tostring(#itemIds) .. " WoWSims equipment items.")
    end

    return added > 0
end

local function ImportWowheadGearPlanner(text, setName)
    local itemIds = Plutocraseeker.GetItemIdsFromWowheadGearPlannerLink and Plutocraseeker.GetItemIdsFromWowheadGearPlannerLink(text) or {}
    if #itemIds == 0 then
        if Plutocraseeker.Print then
            Plutocraseeker.Print("No equipment item IDs were found in the Wowhead gear planner link.")
        end
        return false
    end

    itemOffset = 0
    Plutocraseeker.CreateSet(setName)

    local added = 0
    for _, itemId in ipairs(itemIds) do
        if Plutocraseeker.AddItemToSelectedSet(itemId) then
            added = added + 1
        end
    end

    if Plutocraseeker.Print then
        Plutocraseeker.Print("Imported " .. tostring(added) .. " of " .. tostring(#itemIds) .. " Wowhead gear planner items.")
    end

    return added > 0
end

local function JsonEscape(value)
    local text = tostring(value or "")
    text = text:gsub("\\", "\\\\")
    text = text:gsub('"', '\\"')
    text = text:gsub("\b", "\\b")
    text = text:gsub("\f", "\\f")
    text = text:gsub("\n", "\\n")
    text = text:gsub("\r", "\\r")
    text = text:gsub("\t", "\\t")
    return '"' .. text .. '"'
end

local function IsArrayTable(value)
    if type(value) ~= "table" then
        return false
    end

    local count = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false
        end
        count = count + 1
    end

    return count == #value
end

local EncodeJsonValue

local function EncodeJsonArray(value, depth)
    local parts = {}
    for index = 1, #value do
        parts[#parts + 1] = EncodeJsonValue(value[index], depth + 1)
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function EncodeJsonObject(value, depth)
    local keys = {}
    for key, child in pairs(value) do
        local childType = type(child)
        if (type(key) == "string" or type(key) == "number") and childType ~= "function" and childType ~= "userdata" and childType ~= "thread" then
            keys[#keys + 1] = key
        end
    end
    table.sort(keys, function(left, right)
        return tostring(left) < tostring(right)
    end)

    local parts = {}
    for _, key in ipairs(keys) do
        parts[#parts + 1] = JsonEscape(key) .. ":" .. EncodeJsonValue(value[key], depth + 1)
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

EncodeJsonValue = function(value, depth)
    depth = depth or 0
    if depth > 12 then
        return "null"
    end

    local valueType = type(value)
    if valueType == "nil" then
        return "null"
    elseif valueType == "string" then
        return JsonEscape(value)
    elseif valueType == "number" then
        if value ~= value or value == math.huge or value == -math.huge then
            return "null"
        end
        return tostring(value)
    elseif valueType == "boolean" then
        return value and "true" or "false"
    elseif valueType == "table" then
        if IsArrayTable(value) then
            return EncodeJsonArray(value, depth)
        end
        return EncodeJsonObject(value, depth)
    end

    return "null"
end

local function BuildCharacterSetsExport()
    local db = Plutocraseeker.db or {}
    local characterName = UnitName and UnitName("player") or nil
    local realmName = GetRealmName and GetRealmName() or nil
    local payload = {
        addon = "Plutocraseeker",
        export = "character",
        version = 1,
        character = {
            name = characterName,
            realm = realmName,
        },
        data = {
            selectedSetId = db.selectedSetId,
            nextSetId = db.nextSetId,
            sets = {},
        },
    }

    for _, set in ipairs(db.sets or {}) do
        local exportedSet = {
            id = set.id,
            name = set.name,
            enabled = set.enabled ~= false,
            items = {},
        }

        for _, item in ipairs(set.items or {}) do
            exportedSet.items[#exportedSet.items + 1] = {
                id = item.id,
                difficultyPrefix = item.difficultyPrefix,
                heroic = item.heroic,
                addedAt = item.addedAt,
                source = item.source,
            }
        end

        payload.data.sets[#payload.data.sets + 1] = exportedSet
    end

    return EncodeJsonValue(payload)
end

local function DecodeJsonError(message, position)
    return nil, tostring(message or "Invalid JSON") .. " near character " .. tostring(position or "?")
end

local function DecodeJson(text)
    text = tostring(text or "")
    local position = 1

    local function SkipWhitespace()
        local _, finish = text:find("^[ \n\r\t]*", position)
        position = (finish or position - 1) + 1
    end

    local ParseValue

    local function ParseString()
        if text:sub(position, position) ~= '"' then
            return DecodeJsonError("Expected string", position)
        end

        position = position + 1
        local result = {}
        while position <= #text do
            local char = text:sub(position, position)
            if char == '"' then
                position = position + 1
                return table.concat(result)
            elseif char == "\\" then
                local escaped = text:sub(position + 1, position + 1)
                if escaped == '"' or escaped == "\\" or escaped == "/" then
                    result[#result + 1] = escaped
                    position = position + 2
                elseif escaped == "b" then
                    result[#result + 1] = "\b"
                    position = position + 2
                elseif escaped == "f" then
                    result[#result + 1] = "\f"
                    position = position + 2
                elseif escaped == "n" then
                    result[#result + 1] = "\n"
                    position = position + 2
                elseif escaped == "r" then
                    result[#result + 1] = "\r"
                    position = position + 2
                elseif escaped == "t" then
                    result[#result + 1] = "\t"
                    position = position + 2
                elseif escaped == "u" then
                    local code = tonumber(text:sub(position + 2, position + 5), 16)
                    if not code then
                        return DecodeJsonError("Invalid unicode escape", position)
                    end
                    result[#result + 1] = code < 128 and string.char(code) or "?"
                    position = position + 6
                else
                    return DecodeJsonError("Invalid escape", position)
                end
            else
                result[#result + 1] = char
                position = position + 1
            end
        end

        return DecodeJsonError("Unterminated string", position)
    end

    local function ParseNumber()
        local start = position
        local _, finish = text:find("^-?%d+%.?%d*[eE]?[+-]?%d*", position)
        if not finish or finish < position then
            return DecodeJsonError("Expected number", position)
        end
        local value = tonumber(text:sub(start, finish))
        if value == nil then
            return DecodeJsonError("Invalid number", start)
        end
        position = finish + 1
        return value
    end

    local function ParseArray()
        position = position + 1
        local result = {}
        SkipWhitespace()
        if text:sub(position, position) == "]" then
            position = position + 1
            return result
        end

        while position <= #text do
            local value, errorMessage = ParseValue()
            if errorMessage then
                return nil, errorMessage
            end
            result[#result + 1] = value
            SkipWhitespace()
            local char = text:sub(position, position)
            if char == "]" then
                position = position + 1
                return result
            elseif char ~= "," then
                return DecodeJsonError("Expected comma or closing bracket", position)
            end
            position = position + 1
            SkipWhitespace()
        end

        return DecodeJsonError("Unterminated array", position)
    end

    local function ParseObject()
        position = position + 1
        local result = {}
        SkipWhitespace()
        if text:sub(position, position) == "}" then
            position = position + 1
            return result
        end

        while position <= #text do
            local key, keyError = ParseString()
            if keyError then
                return nil, keyError
            end
            SkipWhitespace()
            if text:sub(position, position) ~= ":" then
                return DecodeJsonError("Expected colon", position)
            end
            position = position + 1
            local value, valueError = ParseValue()
            if valueError then
                return nil, valueError
            end
            result[key] = value
            SkipWhitespace()
            local char = text:sub(position, position)
            if char == "}" then
                position = position + 1
                return result
            elseif char ~= "," then
                return DecodeJsonError("Expected comma or closing brace", position)
            end
            position = position + 1
            SkipWhitespace()
        end

        return DecodeJsonError("Unterminated object", position)
    end

    ParseValue = function()
        SkipWhitespace()
        local char = text:sub(position, position)
        if char == '"' then
            return ParseString()
        elseif char == "{" then
            return ParseObject()
        elseif char == "[" then
            return ParseArray()
        elseif char == "-" or char:match("%d") then
            return ParseNumber()
        elseif text:sub(position, position + 3) == "true" then
            position = position + 4
            return true
        elseif text:sub(position, position + 4) == "false" then
            position = position + 5
            return false
        elseif text:sub(position, position + 3) == "null" then
            position = position + 4
            return nil
        end
        return DecodeJsonError("Unexpected token", position)
    end

    local value, errorMessage = ParseValue()
    if errorMessage then
        return nil, errorMessage
    end
    SkipWhitespace()
    if position <= #text then
        return DecodeJsonError("Unexpected trailing content", position)
    end
    return value
end

local function SanitizeImportedSets(sets)
    local sanitized = {}
    local maxId = 0
    if type(sets) ~= "table" then
        return sanitized, maxId
    end

    for _, set in ipairs(sets) do
        if type(set) == "table" then
            local setId = tonumber(set.id) or (#sanitized + 1)
            maxId = math.max(maxId, setId)
            local nextSet = {
                id = setId,
                name = tostring(set.name or ("Imported " .. tostring(setId))),
                enabled = set.enabled ~= false,
                items = {},
            }

            for _, item in ipairs(set.items or {}) do
                if type(item) == "table" and tonumber(item.id) then
                    nextSet.items[#nextSet.items + 1] = {
                        id = tonumber(item.id),
                        difficultyPrefix = item.difficultyPrefix,
                        heroic = item.heroic,
                        addedAt = tonumber(item.addedAt) or (time and time() or 0),
                        source = type(item.source) == "table" and item.source or nil,
                    }
                end
            end

            sanitized[#sanitized + 1] = nextSet
        end
    end

    return sanitized, maxId
end

local function ImportCharacterSets(text)
    local payload, errorMessage = DecodeJson(text)
    if errorMessage then
        return false, errorMessage
    end
    if type(payload) ~= "table" or payload.addon ~= "Plutocraseeker" then
        return false, "This does not look like a Plutocraseeker export."
    end

    local data = type(payload.data) == "table" and payload.data or payload
    local sets, maxId = SanitizeImportedSets(data.sets)
    if #sets == 0 then
        return false, "No character sets were found in the export."
    end

    local selectedSetId = tonumber(data.selectedSetId)
    local hasSelectedSet = false
    for _, set in ipairs(sets) do
        if set.id == selectedSetId then
            hasSelectedSet = true
            break
        end
    end

    Plutocraseeker.db.sets = sets
    Plutocraseeker.db.nextSetId = math.max(tonumber(data.nextSetId) or 1, maxId + 1)
    Plutocraseeker.db.selectedSetId = hasSelectedSet and selectedSetId or sets[1].id
    itemOffset = 0

    if Plutocraseeker.RebuildTargetNpcIndex then
        Plutocraseeker.RebuildTargetNpcIndex()
    end
    if Plutocraseeker.ClearTooltipStatusCache then
        Plutocraseeker.ClearTooltipStatusCache()
    end
    if Plutocraseeker.RefreshUI then
        Plutocraseeker.RefreshUI()
    end

    return true, "Imported " .. tostring(#sets) .. " character set(s)."
end

local function RefreshConfigFrame()
    if not configFrame or not Plutocraseeker.db then
        return
    end

    local config = Plutocraseeker.db.config or {}
    local alertEnabled = config.alertOnMention ~= false
    configFrame.alertOnMention:SetChecked(alertEnabled)
    configFrame.onlyLootMasterAlerts:SetChecked(config.onlyLootMasterAlerts)
    configFrame.onlyLootMasterAlerts:SetEnabledVisual(alertEnabled)
    if configFrame.showTargetLootAlerts then
        configFrame.showTargetLootAlerts:SetChecked(config.showTargetLootAlerts ~= false)
    end

    if configFrame.lootMasterStatus then
        local masterLooterName = Plutocraseeker.GetMasterLooterName and Plutocraseeker.GetMasterLooterName()
        if masterLooterName and masterLooterName ~= "" then
            configFrame.lootMasterStatus:SetText("Current Loot Master: " .. masterLooterName)
        else
            configFrame.lootMasterStatus:SetText("No loot master detected")
        end
    end
end

local function ShowLootMasterOptionTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Ignore non-Loot Master mentions", 0.31, 0.82, 0.62)
    GameTooltip:AddLine("Uses the game's assigned Master Looter.", 0.9, 0.95, 0.93, true)
    GameTooltip:Show()
end

local function ShowTargetLootOptionTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Show coveted loot on boss target", 0.31, 0.82, 0.62)
    GameTooltip:AddLine("When you target a boss outside combat, Plutocraseeker checks known AtlasLoot sources for items on your monitored sets.", 0.9, 0.95, 0.93, true)
    GameTooltip:Show()
end

local function ShowAnchorOptionTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Show anchors", 0.31, 0.82, 0.62)
    GameTooltip:AddLine("Move the loot alert anchor to choose where Plutocraseeker alerts appear.", 0.9, 0.95, 0.93, true)
    GameTooltip:Show()
end

local function PositionAnchorPreview()
    if not anchorOverlay or not anchorOverlay.anchor then
        return
    end

    ApplyAlertAnchor(anchorOverlay.anchor)
end

local function CreateAnchorGrid(parent)
    local spacing = 80
    parent.gridLines = parent.gridLines or {}

    for index = -30, 30 do
        local vertical = parent:CreateTexture(nil, "BORDER")
        vertical:SetColorTexture(0.31, 0.82, 0.62, index == 0 and 0.32 or 0.16)
        vertical:SetSize(index == 0 and 2 or 1, 5000)
        vertical:SetPoint("CENTER", parent, "CENTER", index * spacing, 0)
        parent.gridLines[#parent.gridLines + 1] = vertical

        local horizontal = parent:CreateTexture(nil, "BORDER")
        horizontal:SetColorTexture(0.31, 0.82, 0.62, index == 0 and 0.32 or 0.16)
        horizontal:SetSize(5000, index == 0 and 2 or 1)
        horizontal:SetPoint("CENTER", parent, "CENTER", 0, index * spacing)
        parent.gridLines[#parent.gridLines + 1] = horizontal
    end
end

local function CreateAnchorOverlay()
    anchorOverlay = CreateFrame("Frame", "PlutocraseekerAnchorOverlay", UIParent, Template())
    anchorOverlay:SetAllPoints(UIParent)
    anchorOverlay:SetFrameStrata("FULLSCREEN_DIALOG")
    anchorOverlay:SetFrameLevel(250)
    anchorOverlay:EnableMouse(true)
    anchorOverlay:Hide()
    RegisterEscapeFrame("PlutocraseekerAnchorOverlay")

    anchorOverlay.dim = anchorOverlay:CreateTexture(nil, "BACKGROUND")
    anchorOverlay.dim:SetAllPoints(anchorOverlay)
    anchorOverlay.dim:SetColorTexture(0, 0, 0, 0.72)
    CreateAnchorGrid(anchorOverlay)

    anchorOverlay.title = CreateText(anchorOverlay, "Plutocraseeker Anchors", 18, colors.accent)
    anchorOverlay.title:SetPoint("TOP", UIParent, "TOP", 0, -36)

    anchorOverlay.hint = CreateText(anchorOverlay, "Drag the loot alert anchor. Click Done when it feels right.", 12, colors.text)
    anchorOverlay.hint:SetPoint("TOP", anchorOverlay.title, "BOTTOM", 0, -8)
    anchorOverlay.hint:SetWidth(520)
    anchorOverlay.hint:SetJustifyH("CENTER")

    anchorOverlay.anchor = CreateFrame("Frame", nil, anchorOverlay, Template())
    anchorOverlay.anchor:SetSize(500, 150)
    anchorOverlay.anchor:SetFrameLevel(anchorOverlay:GetFrameLevel() + 5)
    anchorOverlay.anchor:EnableMouse(true)
    anchorOverlay.anchor:SetMovable(true)
    if anchorOverlay.anchor.SetClampedToScreen then
        anchorOverlay.anchor:SetClampedToScreen(true)
    end
    anchorOverlay.anchor:RegisterForDrag("LeftButton")
    ApplyBackdrop(anchorOverlay.anchor, { 0.055, 0.065, 0.075, 0.82 })

    anchorOverlay.anchor.title = CreateText(anchorOverlay.anchor, "Loot Alert Anchor", 16, colors.accent)
    anchorOverlay.anchor.title:SetPoint("TOPLEFT", 16, -14)

    anchorOverlay.anchor.body = CreateText(anchorOverlay.anchor, "Future loot alerts will appear here.", 12, colors.text)
    anchorOverlay.anchor.body:SetPoint("TOPLEFT", anchorOverlay.anchor.title, "BOTTOMLEFT", 0, -10)
    anchorOverlay.anchor.body:SetWidth(460)

    anchorOverlay.anchor.dragHint = CreateText(anchorOverlay.anchor, "Drag me", 11, { 1.0, 0.82, 0.18, 1 })
    anchorOverlay.anchor.dragHint:SetPoint("BOTTOMLEFT", 16, 14)

    anchorOverlay.anchor:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    anchorOverlay.anchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveAlertAnchorFromFrame(self)
        PositionAlertStack()
    end)

    anchorOverlay.done = CreateButton(anchorOverlay.anchor, "Done", 82, 30)
    anchorOverlay.done:SetPoint("BOTTOMRIGHT", -14, 12)
    anchorOverlay.done:SetScript("OnClick", function()
        anchorOverlay:Hide()
    end)

    anchorOverlay.reset = CreateButton(anchorOverlay.anchor, "Reset", 82, 30)
    anchorOverlay.reset:SetPoint("RIGHT", anchorOverlay.done, "LEFT", -12, 0)
    anchorOverlay.reset:SetScript("OnClick", function()
        ResetAlertAnchor()
        PositionAnchorPreview()
    end)

    anchorOverlay.close = CreateButton(anchorOverlay, "X", 28, 26)
    anchorOverlay.close:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -18, -18)
    anchorOverlay.close:SetScript("OnClick", function()
        anchorOverlay:Hide()
    end)

    anchorOverlay:SetScript("OnShow", function()
        PositionAnchorPreview()
    end)
end

local function ShowAnchorOverlay()
    if not anchorOverlay then
        CreateAnchorOverlay()
    end

    anchorOverlay:Show()
    PositionAnchorPreview()
end

local function CreateImportFrame()
    importFrame = CreateFrame("Frame", "PlutocraseekerWowSimsImportFrame", UIParent, Template())
    importFrame:SetSize(560, 420)
    importFrame:SetPoint("CENTER")
    importFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    importFrame:SetFrameLevel(120)
    if importFrame.SetToplevel then
        importFrame:SetToplevel(true)
    end
    importFrame:EnableMouse(true)
    importFrame:SetMovable(true)
    importFrame:RegisterForDrag("LeftButton")
    importFrame:SetScript("OnDragStart", importFrame.StartMoving)
    importFrame:SetScript("OnDragStop", importFrame.StopMovingOrSizing)
    importFrame:Hide()
    ApplyBackdrop(importFrame, colors.bg)
    RegisterEscapeFrame("PlutocraseekerWowSimsImportFrame")

    importFrame.title = CreateText(importFrame, "Import WowSims", 18, colors.accent)
    importFrame.title:SetPoint("TOPLEFT", 18, -16)

    importFrame.subtitle = CreateText(importFrame, "Paste a WoWSims export JSON.", 11, colors.muted)
    importFrame.subtitle:SetPoint("TOPLEFT", importFrame.title, "BOTTOMLEFT", 0, -2)

    importFrame.close = CreateButton(importFrame, "X", 28, 26)
    importFrame.close:SetPoint("TOPRIGHT", -12, -12)
    importFrame.close:SetScript("OnClick", function()
        importFrame:Hide()
    end)

    local editPanel = CreateFrame("Frame", nil, importFrame, Template())
    editPanel:SetPoint("TOPLEFT", 18, -64)
    editPanel:SetSize(524, 286)
    ApplyBackdrop(editPanel, { 0.045, 0.052, 0.06, 1 })

    importFrame.scroll = CreateFrame("ScrollFrame", nil, editPanel, "UIPanelScrollFrameTemplate")
    importFrame.scroll:SetPoint("TOPLEFT", 8, -8)
    importFrame.scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    importFrame.edit = CreateFrame("EditBox", nil, importFrame.scroll)
    importFrame.edit:SetMultiLine(true)
    importFrame.edit:SetAutoFocus(false)
    importFrame.edit:SetFont(STANDARD_TEXT_FONT, 12, "")
    importFrame.edit:SetTextColor(unpack(colors.text))
    importFrame.edit:SetJustifyH("LEFT")
    importFrame.edit:SetJustifyV("TOP")
    importFrame.edit:SetWidth(480)
    importFrame.edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    importFrame.scroll:SetScrollChild(importFrame.edit)

    importFrame.import = CreateButton(importFrame, "Import", 90, 30)
    importFrame.import:SetPoint("BOTTOMRIGHT", -18, 18)
    importFrame.import:SetScript("OnClick", function()
        local setName = mainFrame and mainFrame.newSetName and mainFrame.newSetName:GetText() or "Imported WowSims"
        if ImportWowSimsJson(importFrame.edit:GetText(), setName) then
            importFrame.edit:SetText("")
            if mainFrame and mainFrame.newSetName then
                mainFrame.newSetName:SetText("New set")
            end
            importFrame:Hide()
        end
    end)

    importFrame.clear = CreateButton(importFrame, "Clear", 70, 30)
    importFrame.clear:SetPoint("RIGHT", importFrame.import, "LEFT", -8, 0)
    importFrame.clear:SetScript("OnClick", function()
        importFrame.edit:SetText("")
        importFrame.edit:SetFocus()
    end)
end

local function CreateWowheadImportFrame()
    wowheadImportFrame = CreateFrame("Frame", "PlutocraseekerWowheadImportFrame", UIParent, Template())
    wowheadImportFrame:SetSize(560, 220)
    wowheadImportFrame:SetPoint("CENTER")
    wowheadImportFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    wowheadImportFrame:SetFrameLevel(120)
    if wowheadImportFrame.SetToplevel then
        wowheadImportFrame:SetToplevel(true)
    end
    wowheadImportFrame:EnableMouse(true)
    wowheadImportFrame:SetMovable(true)
    wowheadImportFrame:RegisterForDrag("LeftButton")
    wowheadImportFrame:SetScript("OnDragStart", wowheadImportFrame.StartMoving)
    wowheadImportFrame:SetScript("OnDragStop", wowheadImportFrame.StopMovingOrSizing)
    wowheadImportFrame:Hide()
    ApplyBackdrop(wowheadImportFrame, colors.bg)
    RegisterEscapeFrame("PlutocraseekerWowheadImportFrame")

    wowheadImportFrame.title = CreateText(wowheadImportFrame, "Import Wowhead", 18, colors.accent)
    wowheadImportFrame.title:SetPoint("TOPLEFT", 18, -16)

    wowheadImportFrame.subtitle = CreateText(wowheadImportFrame, "Paste a MoP Classic gear planner link.", 11, colors.muted)
    wowheadImportFrame.subtitle:SetPoint("TOPLEFT", wowheadImportFrame.title, "BOTTOMLEFT", 0, -2)

    wowheadImportFrame.close = CreateButton(wowheadImportFrame, "X", 28, 26)
    wowheadImportFrame.close:SetPoint("TOPRIGHT", -12, -12)
    wowheadImportFrame.close:SetScript("OnClick", function()
        wowheadImportFrame:Hide()
    end)

    wowheadImportFrame.edit = CreateEditBox(wowheadImportFrame, 524, 30)
    wowheadImportFrame.edit:SetPoint("TOPLEFT", 18, -78)
    wowheadImportFrame.edit:SetScript("OnEnterPressed", function()
        wowheadImportFrame.import:Click()
    end)

    wowheadImportFrame.import = CreateButton(wowheadImportFrame, "Import", 90, 30)
    wowheadImportFrame.import:SetPoint("BOTTOMRIGHT", -18, 18)
    wowheadImportFrame.import:SetScript("OnClick", function()
        local setName = mainFrame and mainFrame.newSetName and mainFrame.newSetName:GetText() or "Imported Wowhead"
        if ImportWowheadGearPlanner(wowheadImportFrame.edit:GetText(), setName) then
            wowheadImportFrame.edit:SetText("")
            if mainFrame and mainFrame.newSetName then
                mainFrame.newSetName:SetText("New set")
            end
            wowheadImportFrame:Hide()
        end
    end)

    wowheadImportFrame.clear = CreateButton(wowheadImportFrame, "Clear", 70, 30)
    wowheadImportFrame.clear:SetPoint("RIGHT", wowheadImportFrame.import, "LEFT", -8, 0)
    wowheadImportFrame.clear:SetScript("OnClick", function()
        wowheadImportFrame.edit:SetText("")
        wowheadImportFrame.edit:SetFocus()
    end)
end

local function CreateCharacterImportFrame()
    characterImportFrame = CreateFrame("Frame", "PlutocraseekerCharacterImportFrame", UIParent, Template())
    characterImportFrame:SetSize(560, 420)
    characterImportFrame:SetPoint("CENTER")
    characterImportFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    characterImportFrame:SetFrameLevel(120)
    if characterImportFrame.SetToplevel then
        characterImportFrame:SetToplevel(true)
    end
    characterImportFrame:EnableMouse(true)
    characterImportFrame:SetMovable(true)
    characterImportFrame:RegisterForDrag("LeftButton")
    characterImportFrame:SetScript("OnDragStart", characterImportFrame.StartMoving)
    characterImportFrame:SetScript("OnDragStop", characterImportFrame.StopMovingOrSizing)
    characterImportFrame:Hide()
    ApplyBackdrop(characterImportFrame, colors.bg)
    RegisterEscapeFrame("PlutocraseekerCharacterImportFrame")

    characterImportFrame.title = CreateText(characterImportFrame, "Import Character Sets", 18, colors.accent)
    characterImportFrame.title:SetPoint("TOPLEFT", 18, -16)

    characterImportFrame.subtitle = CreateText(characterImportFrame, "Paste a Plutocraseeker character export. This replaces this character's current sets.", 11, colors.muted)
    characterImportFrame.subtitle:SetPoint("TOPLEFT", characterImportFrame.title, "BOTTOMLEFT", 0, -2)
    characterImportFrame.subtitle:SetWidth(480)

    characterImportFrame.close = CreateButton(characterImportFrame, "X", 28, 26)
    characterImportFrame.close:SetPoint("TOPRIGHT", -12, -12)
    characterImportFrame.close:SetScript("OnClick", function()
        characterImportFrame:Hide()
    end)

    local editPanel = CreateFrame("Frame", nil, characterImportFrame, Template())
    editPanel:SetPoint("TOPLEFT", 18, -64)
    editPanel:SetSize(524, 286)
    ApplyBackdrop(editPanel, { 0.045, 0.052, 0.06, 1 })

    characterImportFrame.scroll = CreateFrame("ScrollFrame", nil, editPanel, "UIPanelScrollFrameTemplate")
    characterImportFrame.scroll:SetPoint("TOPLEFT", 8, -8)
    characterImportFrame.scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    characterImportFrame.edit = CreateFrame("EditBox", nil, characterImportFrame.scroll)
    characterImportFrame.edit:SetMultiLine(true)
    characterImportFrame.edit:SetAutoFocus(false)
    characterImportFrame.edit:SetFont(STANDARD_TEXT_FONT, 12, "")
    characterImportFrame.edit:SetTextColor(unpack(colors.text))
    characterImportFrame.edit:SetJustifyH("LEFT")
    characterImportFrame.edit:SetJustifyV("TOP")
    characterImportFrame.edit:SetWidth(480)
    characterImportFrame.edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    characterImportFrame.scroll:SetScrollChild(characterImportFrame.edit)

    characterImportFrame.import = CreateButton(characterImportFrame, "Import", 90, 30)
    characterImportFrame.import:SetPoint("BOTTOMRIGHT", -18, 18)
    characterImportFrame.import:SetScript("OnClick", function()
        local ok, message = ImportCharacterSets(characterImportFrame.edit:GetText())
        if Plutocraseeker.Print and message then
            Plutocraseeker.Print(message)
        end
        if ok then
            characterImportFrame.edit:SetText("")
            characterImportFrame:Hide()
        end
    end)

    characterImportFrame.clear = CreateButton(characterImportFrame, "Clear", 70, 30)
    characterImportFrame.clear:SetPoint("RIGHT", characterImportFrame.import, "LEFT", -8, 0)
    characterImportFrame.clear:SetScript("OnClick", function()
        characterImportFrame.edit:SetText("")
        characterImportFrame.edit:SetFocus()
    end)
end

local function RefreshExportFrameText()
    if not exportFrame or not exportFrame.edit then
        return
    end

    exportFrame.edit:SetText(BuildCharacterSetsExport())
    exportFrame.edit:SetFocus()
    exportFrame.edit:HighlightText()
end

local function CreateExportFrame()
    exportFrame = CreateFrame("Frame", "PlutocraseekerExportFrame", UIParent, Template())
    exportFrame:SetSize(560, 420)
    exportFrame:SetPoint("CENTER")
    exportFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    exportFrame:SetFrameLevel(120)
    if exportFrame.SetToplevel then
        exportFrame:SetToplevel(true)
    end
    exportFrame:EnableMouse(true)
    exportFrame:SetMovable(true)
    exportFrame:RegisterForDrag("LeftButton")
    exportFrame:SetScript("OnDragStart", exportFrame.StartMoving)
    exportFrame:SetScript("OnDragStop", exportFrame.StopMovingOrSizing)
    exportFrame:Hide()
    ApplyBackdrop(exportFrame, colors.bg)
    RegisterEscapeFrame("PlutocraseekerExportFrame")

    exportFrame.title = CreateText(exportFrame, "Export Character Sets", 18, colors.accent)
    exportFrame.title:SetPoint("TOPLEFT", 18, -16)

    exportFrame.subtitle = CreateText(exportFrame, "Copy this text to back up or move this character's loot sets.", 11, colors.muted)
    exportFrame.subtitle:SetPoint("TOPLEFT", exportFrame.title, "BOTTOMLEFT", 0, -2)
    exportFrame.subtitle:SetWidth(460)

    exportFrame.close = CreateButton(exportFrame, "X", 28, 26)
    exportFrame.close:SetPoint("TOPRIGHT", -12, -12)
    exportFrame.close:SetScript("OnClick", function()
        exportFrame:Hide()
    end)

    local editPanel = CreateFrame("Frame", nil, exportFrame, Template())
    editPanel:SetPoint("TOPLEFT", 18, -64)
    editPanel:SetSize(524, 286)
    ApplyBackdrop(editPanel, { 0.045, 0.052, 0.06, 1 })

    exportFrame.scroll = CreateFrame("ScrollFrame", nil, editPanel, "UIPanelScrollFrameTemplate")
    exportFrame.scroll:SetPoint("TOPLEFT", 8, -8)
    exportFrame.scroll:SetPoint("BOTTOMRIGHT", -28, 8)

    exportFrame.edit = CreateFrame("EditBox", nil, exportFrame.scroll)
    exportFrame.edit:SetMultiLine(true)
    exportFrame.edit:SetAutoFocus(false)
    exportFrame.edit:SetFont(STANDARD_TEXT_FONT, 12, "")
    exportFrame.edit:SetTextColor(unpack(colors.text))
    exportFrame.edit:SetJustifyH("LEFT")
    exportFrame.edit:SetJustifyV("TOP")
    exportFrame.edit:SetWidth(480)
    exportFrame.edit:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    exportFrame.scroll:SetScrollChild(exportFrame.edit)

    exportFrame.selectAll = CreateButton(exportFrame, "Select All", 92, 30)
    exportFrame.selectAll:SetPoint("BOTTOMRIGHT", -18, 18)
    exportFrame.selectAll:SetScript("OnClick", function()
        exportFrame.edit:SetFocus()
        exportFrame.edit:HighlightText()
    end)

    exportFrame.refresh = CreateButton(exportFrame, "Refresh", 82, 30)
    exportFrame.refresh:SetPoint("RIGHT", exportFrame.selectAll, "LEFT", -8, 0)
    exportFrame.refresh:SetScript("OnClick", function()
        RefreshExportFrameText()
    end)

    exportFrame.done = CreateButton(exportFrame, "Close", 72, 30)
    exportFrame.done:SetPoint("RIGHT", exportFrame.refresh, "LEFT", -8, 0)
    exportFrame.done:SetScript("OnClick", function()
        exportFrame:Hide()
    end)

    exportFrame:SetScript("OnShow", function()
        RefreshExportFrameText()
    end)
end

local function CreateConfirmDeleteFrame()
    confirmDeleteFrame = CreateFrame("Frame", "PlutocraseekerConfirmDeleteFrame", UIParent, Template())
    confirmDeleteFrame:SetSize(380, 160)
    confirmDeleteFrame:SetPoint("CENTER")
    confirmDeleteFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    confirmDeleteFrame:SetFrameLevel(130)
    if confirmDeleteFrame.SetToplevel then
        confirmDeleteFrame:SetToplevel(true)
    end
    confirmDeleteFrame:EnableMouse(true)
    confirmDeleteFrame:SetMovable(true)
    confirmDeleteFrame:RegisterForDrag("LeftButton")
    confirmDeleteFrame:SetScript("OnDragStart", confirmDeleteFrame.StartMoving)
    confirmDeleteFrame:SetScript("OnDragStop", confirmDeleteFrame.StopMovingOrSizing)
    confirmDeleteFrame:Hide()
    ApplyBackdrop(confirmDeleteFrame, colors.bg)
    RegisterEscapeFrame("PlutocraseekerConfirmDeleteFrame")

    confirmDeleteFrame.title = CreateText(confirmDeleteFrame, "Delete Set?", 18, colors.accent)
    confirmDeleteFrame.title:SetPoint("TOPLEFT", 18, -16)

    confirmDeleteFrame.message = CreateText(confirmDeleteFrame, "", 12, colors.text)
    confirmDeleteFrame.message:SetPoint("TOPLEFT", confirmDeleteFrame.title, "BOTTOMLEFT", 0, -16)
    confirmDeleteFrame.message:SetWidth(330)

    confirmDeleteFrame.cancel = CreateButton(confirmDeleteFrame, "Cancel", 78, 28)
    confirmDeleteFrame.cancel:SetPoint("BOTTOMRIGHT", -18, 16)
    confirmDeleteFrame.cancel:SetScript("OnClick", function()
        confirmDeleteFrame:Hide()
    end)

    confirmDeleteFrame.delete = CreateButton(confirmDeleteFrame, "Delete", 78, 28)
    confirmDeleteFrame.delete:SetPoint("RIGHT", confirmDeleteFrame.cancel, "LEFT", -8, 0)
    confirmDeleteFrame.delete:SetScript("OnClick", function()
        confirmDeleteFrame:Hide()
        itemOffset = 0
        Plutocraseeker.DeleteSelectedSet()
    end)
end

local function GetReceivedItemPromptTime()
    if GetTime then
        return GetTime()
    end
    return time()
end

local function MarkReceivedItemHandled(itemId)
    itemId = tonumber(itemId)
    if itemId then
        receivedItemHandledAt[itemId] = GetReceivedItemPromptTime()
    end
end

local function MarkReceivedItemPromptsHandled(prompts)
    for _, prompt in ipairs(prompts or {}) do
        MarkReceivedItemHandled(prompt and prompt.itemId)
    end
end

local function WasReceivedItemRecentlyHandled(itemId)
    itemId = tonumber(itemId)
    if not itemId then
        return false
    end

    local handledAt = receivedItemHandledAt[itemId]
    if not handledAt then
        return false
    end

    return GetReceivedItemPromptTime() - handledAt < RECEIVED_ITEM_DEDUPE_SECONDS
end

local function GetCurrentReceivedItemSets(itemId, fallbackSets, itemText)
    if Plutocraseeker.GetSetsContainingItem then
        return Plutocraseeker.GetSetsContainingItem(itemId, true, itemText)
    end
    return fallbackSets or {}
end

local function IsReceivedItemPromptPending(itemId)
    itemId = tonumber(itemId)
    if not itemId then
        return false
    end

    if receivedItemFrame and receivedItemFrame:IsShown() then
        for _, prompt in ipairs(receivedItemFrame.prompts or {}) do
            if tonumber(prompt and prompt.itemId) == itemId then
                return true
            end
        end
    end

    for _, data in ipairs(receivedItemQueue) do
        if tonumber(data and data.itemId) == itemId then
            return true
        end
    end

    return false
end

local function CreateReceivedItemFrame()
    receivedItemFrame = CreateFrame("Frame", "PlutocraseekerReceivedItemFrame", UIParent, Template())
    receivedItemFrame:SetSize(ALERT_FRAME_WIDTH, 240)
    receivedItemFrame:SetPoint("CENTER")
    receivedItemFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    receivedItemFrame:SetFrameLevel(135)
    if receivedItemFrame.SetToplevel then
        receivedItemFrame:SetToplevel(true)
    end
    receivedItemFrame:EnableMouse(true)
    receivedItemFrame:SetMovable(true)
    receivedItemFrame:RegisterForDrag("LeftButton")
    receivedItemFrame:SetScript("OnDragStart", receivedItemFrame.StartMoving)
    receivedItemFrame:SetScript("OnDragStop", receivedItemFrame.StopMovingOrSizing)
    receivedItemFrame:Hide()
    receivedItemFrame:SetScript("OnHide", function(self)
        if self.suppressNextPrompt then
            self.suppressNextPrompt = nil
            return
        end
        MarkReceivedItemHandled(self.itemId)
        MarkReceivedItemPromptsHandled(self.prompts)
        if UI.ShowNextReceivedItemPrompt then
            UI.ShowNextReceivedItemPrompt()
        end
    end)
    ApplyBackdrop(receivedItemFrame, colors.bg)
    RegisterEscapeFrame("PlutocraseekerReceivedItemFrame")

    receivedItemFrame.title = CreateText(receivedItemFrame, "Received Watched Item", 18, colors.accent)
    receivedItemFrame.title:SetPoint("TOPLEFT", 18, -16)

    receivedItemFrame.close = CreateButton(receivedItemFrame, "X", 28, 26)
    receivedItemFrame.close:SetPoint("TOPRIGHT", -12, -12)
    receivedItemFrame.close:SetScript("OnClick", function()
        receivedItemFrame:Hide()
    end)

    receivedItemFrame.itemText = CreateText(receivedItemFrame, "", 13, colors.text)
    receivedItemFrame.itemText:SetPoint("TOPLEFT", receivedItemFrame.title, "BOTTOMLEFT", 0, -12)
    receivedItemFrame.itemText:SetWidth(450)

    receivedItemFrame.message = CreateText(receivedItemFrame, "Check the sets this loot satisfies. Checked sets will stop watching this item.", 11, colors.muted)
    receivedItemFrame.message:SetPoint("TOPLEFT", receivedItemFrame.itemText, "BOTTOMLEFT", 0, -8)
    receivedItemFrame.message:SetWidth(450)

    receivedItemFrame.rows = {}
    receivedItemFrame.itemLabels = {}
    receivedItemFrame.prompts = {}

    receivedItemFrame.keep = CreateButton(receivedItemFrame, "Keep Watching", 112, 30)
    receivedItemFrame.keep:SetPoint("BOTTOMRIGHT", -18, 18)
    receivedItemFrame.keep:SetScript("OnClick", function()
        receivedItemFrame:Hide()
    end)

    receivedItemFrame.remove = CreateButton(receivedItemFrame, "Remove Checked", 128, 30)
    receivedItemFrame.remove:SetPoint("RIGHT", receivedItemFrame.keep, "LEFT", -8, 0)
    receivedItemFrame.remove:SetScript("OnClick", function()
        local removed = 0
        for _, row in ipairs(receivedItemFrame.rows or {}) do
            if row:IsShown() and row.itemId and row.setId and row:GetChecked() then
                if Plutocraseeker.RemoveItemFromSet and Plutocraseeker.RemoveItemFromSet(row.setId, row.itemId) then
                    removed = removed + 1
                end
            end
        end

        if Plutocraseeker.Print then
            if removed > 0 then
                Plutocraseeker.Print("Removed watched item entries from " .. tostring(removed) .. " set(s).")
            else
                Plutocraseeker.Print("No sets were changed.")
            end
        end
        receivedItemFrame:Hide()
    end)
end

local function DisplayReceivedItemPrompts(prompts)
    if not receivedItemFrame then
        CreateReceivedItemFrame()
    end

    prompts = prompts or {}
    local checkedRows = {}
    if receivedItemFrame and receivedItemFrame.rows then
        for _, row in ipairs(receivedItemFrame.rows) do
            if row:IsShown() and row.itemId and row.setId and row:GetChecked() then
                checkedRows[tostring(row.itemId) .. ":" .. tostring(row.setId)] = true
            end
        end
    end

    receivedItemFrame.itemId = nil
    receivedItemFrame.itemName = nil
    receivedItemFrame.prompts = prompts

    if #prompts == 1 then
        receivedItemFrame.itemText:SetText("Received: " .. tostring(prompts[1].itemText or Plutocraseeker.GetItemName(prompts[1].itemId)))
    else
        receivedItemFrame.itemText:SetText("Received: " .. tostring(#prompts) .. " watched items")
    end
    receivedItemFrame.message:SetText("Check the sets this loot satisfies. Checked sets will stop watching those items.")

    local labelOffset = -92
    local rowHeight = 26
    local labelCount = 0
    local rowCount = 0
    local y = labelOffset
    for promptIndex, prompt in ipairs(prompts) do
        local itemId = tonumber(prompt and prompt.itemId)
        local sets = prompt and prompt.sets or {}
        if itemId and #sets > 0 then
            labelCount = labelCount + 1
            local label = receivedItemFrame.itemLabels[labelCount]
            if not label then
                label = CreateText(receivedItemFrame, "", 12, colors.text)
                label:SetWidth(450)
                receivedItemFrame.itemLabels[labelCount] = label
            end
            label:SetText(tostring(prompt.itemText or Plutocraseeker.GetItemName(itemId)))
            label:ClearAllPoints()
            label:SetPoint("TOPLEFT", 18, y)
            label:Show()
            y = y - 22

            for _, set in ipairs(sets) do
                rowCount = rowCount + 1
                local row = receivedItemFrame.rows[rowCount]
                if not row then
                    row = CreateCheckbox(receivedItemFrame, "", 440)
                    receivedItemFrame.rows[rowCount] = row
                end
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", 18, y)
                row.text:SetText(tostring(set.name or "Unnamed set"))
                row.itemId = itemId
                row.setId = set.id
                row:SetChecked(checkedRows[tostring(itemId) .. ":" .. tostring(set.id)] == true)
                row:Show()
                y = y - rowHeight
            end
            y = y - 8
        end
    end

    for index = labelCount + 1, #receivedItemFrame.itemLabels do
        receivedItemFrame.itemLabels[index]:Hide()
    end

    for index = rowCount + 1, #receivedItemFrame.rows do
        local row = receivedItemFrame.rows[index]
        row.itemId = nil
        row.setId = nil
        row:Hide()
    end

    local contentHeight = math.max(labelOffset - y, 0)
    receivedItemFrame:SetHeight(math.min(142 + contentHeight, 520))
    if receivedItemFrame.Raise then
        receivedItemFrame:Raise()
    end
    receivedItemFrame:Show()
    PositionAlertStack()
end

function UI.ShowNextReceivedItemPrompt()
    if not receivedItemFrame then
        CreateReceivedItemFrame()
    end

    if receivedItemFrame:IsShown() then
        return
    end

    local prompts = {}
    while #receivedItemQueue > 0 do
        local data = table.remove(receivedItemQueue, 1)
        local itemId = tonumber(data and data.itemId)
        if itemId and not WasReceivedItemRecentlyHandled(itemId) then
            data.sets = GetCurrentReceivedItemSets(itemId, data.sets, data.itemText)
            if #data.sets > 0 then
                prompts[#prompts + 1] = data
            end
        end
    end

    if #prompts > 0 then
        DisplayReceivedItemPrompts(prompts)
    end
end

function UI.ShowReceivedItemPrompt(itemId, itemText, sets)
    itemId = tonumber(itemId)
    if not itemId or WasReceivedItemRecentlyHandled(itemId) or IsReceivedItemPromptPending(itemId) then
        return
    end

    sets = GetCurrentReceivedItemSets(itemId, sets, itemText)
    if #sets == 0 then
        return
    end

    receivedItemQueue[#receivedItemQueue + 1] = {
        itemId = itemId,
        itemText = itemText,
        sets = sets,
    }

    if receivedItemFrame and receivedItemFrame:IsShown() then
        local prompts = receivedItemFrame.prompts or {}
        prompts[#prompts + 1] = receivedItemQueue[#receivedItemQueue]
        table.remove(receivedItemQueue, #receivedItemQueue)
        DisplayReceivedItemPrompts(prompts)
    elseif UI.ShowNextReceivedItemPrompt then
        UI.ShowNextReceivedItemPrompt()
    end
end

local function ShowDeleteSetConfirmation()
    local selectedSet = Plutocraseeker.GetSelectedSet and Plutocraseeker.GetSelectedSet()
    if not selectedSet then
        return
    end

    if not confirmDeleteFrame then
        CreateConfirmDeleteFrame()
    end

    confirmDeleteFrame.message:SetText("Delete \"" .. tostring(selectedSet.name or "this set") .. "\"? This cannot be undone.")
    confirmDeleteFrame:ClearAllPoints()
    confirmDeleteFrame:SetPoint("CENTER", mainFrame or UIParent, "CENTER", 0, 10)
    confirmDeleteFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    confirmDeleteFrame:SetFrameLevel(((mainFrame and mainFrame:GetFrameLevel()) or 1) + 130)
    if confirmDeleteFrame.Raise then
        confirmDeleteFrame:Raise()
    end
    confirmDeleteFrame:Show()
end

local function CreateMainFrame()
    mainFrame = CreateFrame("Frame", "PlutocraseekerFrame", UIParent, Template())
    mainFrame:SetSize(660, MAIN_FRAME_HEIGHT)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    mainFrame:SetScript("OnHide", function()
        if Plutocraseeker.AtlasBrowser and Plutocraseeker.AtlasBrowser.Hide then
            Plutocraseeker.AtlasBrowser.Hide()
        end
        if configFrame then
            configFrame:Hide()
        end
        if importFrame then
            importFrame:Hide()
        end
        if wowheadImportFrame then
            wowheadImportFrame:Hide()
        end
        if characterImportFrame then
            characterImportFrame:Hide()
        end
        if exportFrame then
            exportFrame:Hide()
        end
        if receivedItemFrame then
            if receivedItemFrame:IsShown() then
                receivedItemFrame.suppressNextPrompt = true
            end
            receivedItemFrame:Hide()
        end
        if confirmDeleteFrame then
            confirmDeleteFrame:Hide()
        end
    end)
    mainFrame:Hide()
    ApplyBackdrop(mainFrame, colors.bg)
    RegisterEscapeFrame("PlutocraseekerFrame")

    mainFrame.title = CreateText(mainFrame, "Plutocraseeker", 18, colors.accent)
    mainFrame.title:SetPoint("TOPLEFT", 18, -16)

    mainFrame.subtitle = CreateText(mainFrame, "Loot drop sets for raid chat links", 11, colors.muted)
    mainFrame.subtitle:SetPoint("TOPLEFT", mainFrame.title, "BOTTOMLEFT", 0, -2)

    mainFrame.close = CreateButton(mainFrame, "X", 28, 26)
    mainFrame.close:SetPoint("TOPRIGHT", -12, -12)
    mainFrame.close:SetScript("OnClick", function()
        mainFrame:Hide()
        if Plutocraseeker.AtlasBrowser and Plutocraseeker.AtlasBrowser.Hide then
            Plutocraseeker.AtlasBrowser.Hide()
        end
    end)

    mainFrame.config = CreateButton(mainFrame, "Config", 72, 26)
    mainFrame.config:SetPoint("RIGHT", mainFrame.close, "LEFT", -8, 0)
    mainFrame.config:SetScript("OnClick", function()
        if UI.ToggleConfig then
            UI.ToggleConfig()
        end
    end)

    local setPanel = CreateFrame("Frame", nil, mainFrame, Template())
    setPanel:SetPoint("TOPLEFT", 14, -58)
    setPanel:SetSize(205, MAIN_PANEL_HEIGHT)
    ApplyBackdrop(setPanel, colors.panel)

    local setHeader = CreateText(setPanel, "Sets", 12, colors.muted)
    setHeader:SetPoint("TOPLEFT", 10, -9)

    for index = 1, 8 do
        local row = CreateButton(setPanel, "", 185, 28)
        row:SetPoint("TOPLEFT", 10, -31 - ((index - 1) * 33))
        row:SetScript("OnClick", function(self)
            if self.setId then
                itemOffset = 0
                Plutocraseeker.SelectSet(self.setId)
            end
        end)
        setRows[index] = row
    end

    mainFrame.newSetName = CreateEditBox(mainFrame, 118, 28)
    mainFrame.newSetName:SetPoint("TOPLEFT", setPanel, "BOTTOMLEFT", 0, -12)
    mainFrame.newSetName:SetText("New set")

    mainFrame.newSet = CreateButton(mainFrame, "Create", 68, 28)
    mainFrame.newSet:SetPoint("LEFT", mainFrame.newSetName, "RIGHT", 7, 0)
    SetButtonTooltip(mainFrame.newSet, "Create", "Create a new loot set using the name in the field.")
    mainFrame.newSet:SetScript("OnClick", function()
        itemOffset = 0
        Plutocraseeker.CreateSet(mainFrame.newSetName:GetText())
        mainFrame.newSetName:SetText("New set")
    end)

    mainFrame.importWowSims = CreateButton(mainFrame, "Import WoWSims", 128, 28)
    mainFrame.importWowSims:SetPoint("LEFT", mainFrame.newSet, "RIGHT", 7, 0)
    SetButtonTooltip(mainFrame.importWowSims, "Import WowSims", "Paste a WoWSims JSON export and create a set from its equipped items.")
    mainFrame.importWowSims:SetScript("OnClick", function()
        if UI.ToggleWowSimsImport then
            UI.ToggleWowSimsImport()
        end
    end)

    mainFrame.importWowhead = CreateButton(mainFrame, "Import Wowhead", 142, 28)
    mainFrame.importWowhead:SetPoint("LEFT", mainFrame.importWowSims, "RIGHT", 7, 0)
    SetButtonTooltip(mainFrame.importWowhead, "Import Wowhead", "Paste a Wowhead gear planner link and create a set from its equipped items.")
    mainFrame.importWowhead:SetScript("OnClick", function()
        if UI.ToggleWowheadImport then
            UI.ToggleWowheadImport()
        end
    end)

    local detailPanel = CreateFrame("Frame", nil, mainFrame, Template())
    detailPanel:SetPoint("TOPLEFT", 232, -58)
    detailPanel:SetSize(414, MAIN_PANEL_HEIGHT)
    ApplyBackdrop(detailPanel, colors.panel)

    mainFrame.setName = CreateEditBox(detailPanel, 230, 28)
    mainFrame.setName:SetPoint("TOPLEFT", 10, -10)
    mainFrame.setName:SetScript("OnEnterPressed", function(self)
        Plutocraseeker.SetSelectedSetName(self:GetText())
        self:ClearFocus()
    end)

    mainFrame.enabled = CreateFrame("CheckButton", nil, detailPanel, "UICheckButtonTemplate")
    mainFrame.enabled:SetPoint("LEFT", mainFrame.setName, "RIGHT", 8, 0)
    mainFrame.enabled.text = CreateText(detailPanel, "Monitor", 12, colors.text)
    mainFrame.enabled.text:SetPoint("LEFT", mainFrame.enabled, "RIGHT", -2, 0)
    mainFrame.enabled:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Monitor", 0.31, 0.82, 0.62)
        GameTooltip:AddLine("When enabled, this set is checked for matching item links.", 0.9, 0.95, 0.93, true)
        GameTooltip:Show()
    end)
    mainFrame.enabled:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    mainFrame.enabled:SetScript("OnClick", function(self)
        Plutocraseeker.ToggleSelectedSet(self:GetChecked())
    end)

    mainFrame.deleteSet = CreateButton(detailPanel, "Delete", 66, 28)
    mainFrame.deleteSet:SetPoint("TOPRIGHT", -10, -10)
    SetButtonTooltip(mainFrame.deleteSet, "Delete", "Delete the selected loot set after confirmation.")
    mainFrame.deleteSet:SetScript("OnClick", function()
        ShowDeleteSetConfirmation()
    end)

    mainFrame.itemInput = CreateEditBox(detailPanel, 190, 28)
    mainFrame.itemInput:SetPoint("TOPLEFT", 10, -50)
    mainFrame.itemInput:SetScript("OnEnterPressed", function(self)
        if Plutocraseeker.AddItemToSelectedSet(self:GetText()) then
            self:SetText("")
        end
    end)

    mainFrame.itemInputHint = CreateText(detailPanel, "Item ID/link/URL", 11, colors.muted)
    mainFrame.itemInputHint:SetPoint("LEFT", mainFrame.itemInput, "LEFT", 8, 0)
    mainFrame.itemInputHint:SetWidth(160)
    mainFrame.itemInput:SetScript("OnEditFocusGained", function()
        mainFrame.itemInputHint:Hide()
    end)
    mainFrame.itemInput:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then
            mainFrame.itemInputHint:Show()
        end
    end)
    mainFrame.itemInput:SetScript("OnTextChanged", function(self)
        if self:GetText() == "" and not self:HasFocus() then
            mainFrame.itemInputHint:Show()
        else
            mainFrame.itemInputHint:Hide()
        end
    end)

    mainFrame.addItem = CreateButton(detailPanel, "Add", 50, 28)
    mainFrame.addItem:SetPoint("LEFT", mainFrame.itemInput, "RIGHT", 7, 0)
    SetButtonTooltip(mainFrame.addItem, "Add", "Add an item ID or in-game item link to the selected set.")
    mainFrame.addItem:SetScript("OnClick", function()
        if Plutocraseeker.AddItemToSelectedSet(mainFrame.itemInput:GetText()) then
            mainFrame.itemInput:SetText("")
            mainFrame.itemInputHint:Show()
        end
    end)

    mainFrame.addWowhead = CreateButton(detailPanel, "Add (wowhead)", 120, 28)
    mainFrame.addWowhead:SetPoint("LEFT", mainFrame.addItem, "RIGHT", 7, 0)
    SetButtonTooltip(mainFrame.addWowhead, "Add Wowhead", "Add one item from a Wowhead item URL in the input field.")
    mainFrame.addWowhead:SetScript("OnClick", function()
        local itemId = Plutocraseeker.GetItemIdFromWowheadLink and Plutocraseeker.GetItemIdFromWowheadLink(mainFrame.itemInput:GetText())
        if itemId and Plutocraseeker.AddItemToSelectedSet(itemId) then
            mainFrame.itemInput:SetText("")
            mainFrame.itemInputHint:Show()
        elseif Plutocraseeker.Print then
            Plutocraseeker.Print("Paste a Wowhead item URL like https://www.wowhead.com/mop-classic/item=104424/hood-of-swirling-senses.")
        end
    end)

    mainFrame.browseLoot = CreateButton(mainFrame, "Browse", 62, 28)
    mainFrame.browseLoot:SetPoint("TOPRIGHT", detailPanel, "BOTTOMRIGHT", 0, -12)
    SetButtonTooltip(mainFrame.browseLoot, "Browse", "Open the loot browser to add items from raid and dungeon loot tables.")
    mainFrame.browseLoot:SetScript("OnClick", function()
        Plutocraseeker.OpenLootBrowser()
    end)

    local itemHeader = CreateText(detailPanel, "Wanted items", 12, colors.muted)
    itemHeader:SetPoint("TOPLEFT", 10, -91)

    detailPanel:EnableMouseWheel(true)
    detailPanel:SetScript("OnMouseWheel", function(_, delta)
        if ScrollItems then
            ScrollItems(delta)
        end
    end)

    mainFrame.itemScroll = CreateScrollBar(detailPanel, 276)
    mainFrame.itemScroll:SetPoint("TOPRIGHT", -8, -112)

    for index = 1, 9 do
        local row = CreateFrame("Frame", nil, detailPanel, Template())
        row:SetSize(374, 27)
        row:SetPoint("TOPLEFT", 10, -112 - ((index - 1) * 29))
        ApplyBackdrop(row, { 0.065, 0.074, 0.084, 1 })
        row:EnableMouse(true)
        row:EnableMouseWheel(true)
        row:SetScript("OnMouseWheel", function(_, delta)
            if ScrollItems then
                ScrollItems(delta)
            end
        end)

        row.heroicBadge = CreateText(row, "H", 12, { 1.0, 0.82, 0.18, 1 })
        row.heroicBadge:SetPoint("LEFT", 8, 0)
        row.heroicBadge:SetWidth(14)

        row.name = CreateText(row, "", 12, colors.text)
        row.name:SetPoint("LEFT", 8, 0)
        row.name:SetWidth(320)

        row.remove = CreateButton(row, "X", 24, 22)
        row.remove:SetPoint("RIGHT", -3, 0)
        row.remove:SetScript("OnClick", function(self)
            if self:GetParent().itemId then
                Plutocraseeker.RemoveItemFromSelectedSet(self:GetParent().itemId)
            end
        end)

        row:SetScript("OnEnter", function(self)
            if self.SetBackdropColor then
                self:SetBackdropColor(unpack(colors.hover))
            end
            ScheduleItemTooltip(self)
        end)
        row:SetScript("OnLeave", function(self)
            self.pendingTooltipItemId = nil
            if self.SetBackdropColor then
                self:SetBackdropColor(0.065, 0.074, 0.084, 1)
            end
            HideItemTooltip()
        end)

        itemRows[index] = row
    end

    mainFrame.footer = CreateText(mainFrame, "Tip: paste an item link, type /ps add 105485, paste a Wowhead URL, or use Browse.", 11, colors.muted)
    mainFrame.footer:SetPoint("BOTTOMLEFT", 18, 10)
    mainFrame.footer:SetWidth(620)
end

local function CreateConfigPanel()
    configFrame = CreateFrame("Frame", "PlutocraseekerConfigFrame", UIParent, Template())
    configFrame:SetSize(470, 430)
    configFrame:SetPoint("CENTER")
    configFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    configFrame:SetFrameLevel(100)
    if configFrame.SetToplevel then
        configFrame:SetToplevel(true)
    end
    configFrame:EnableMouse(true)
    configFrame:SetMovable(true)
    configFrame:RegisterForDrag("LeftButton")
    configFrame:SetScript("OnDragStart", configFrame.StartMoving)
    configFrame:SetScript("OnDragStop", configFrame.StopMovingOrSizing)
    configFrame:Hide()
    ApplyBackdrop(configFrame, colors.bg)
    RegisterEscapeFrame("PlutocraseekerConfigFrame")

    local title = CreateText(configFrame, "Plutocraseeker Config", 18, colors.accent)
    title:SetPoint("TOPLEFT", 16, -16)

    configFrame.close = CreateButton(configFrame, "X", 28, 26)
    configFrame.close:SetPoint("TOPRIGHT", -12, -12)
    configFrame.close:SetScript("OnClick", function()
        configFrame:Hide()
    end)

    local alertsSection = CreateFrame("Frame", nil, configFrame, Template())
    alertsSection:SetPoint("TOPLEFT", 16, -58)
    alertsSection:SetSize(438, 220)
    ApplyBackdrop(alertsSection, colors.panel)

    alertsSection.title = CreateText(alertsSection, "Loot Alerts", 13, colors.accent)
    alertsSection.title:SetPoint("TOPLEFT", 12, -10)

    configFrame.alertOnMention = CreateCheckbox(alertsSection, "Alert me when my item is mentioned", 380)
    configFrame.alertOnMention:SetPoint("TOPLEFT", 12, -38)
    configFrame.alertOnMention.OnValueChanged = function(_, checked)
        Plutocraseeker.db.config = Plutocraseeker.db.config or {}
        Plutocraseeker.db.config.alertOnMention = checked and true or false
        configFrame.onlyLootMasterAlerts:SetEnabledVisual(checked)
    end

    configFrame.onlyLootMasterAlerts = CreateCheckbox(alertsSection, "Ignore non-Loot Master mentions", 380)
    configFrame.onlyLootMasterAlerts:SetPoint("TOPLEFT", configFrame.alertOnMention, "BOTTOMLEFT", 0, -8)
    configFrame.onlyLootMasterAlerts.OnValueChanged = function(_, checked)
        Plutocraseeker.db.config = Plutocraseeker.db.config or {}
        Plutocraseeker.db.config.onlyLootMasterAlerts = checked and true or false
    end
    configFrame.onlyLootMasterAlerts:SetScript("OnEnter", function(self)
        self.text:SetTextColor(unpack(self.visualEnabled == false and colors.muted or colors.accent))
        ShowLootMasterOptionTooltip(self)
    end)
    configFrame.onlyLootMasterAlerts:SetScript("OnLeave", function(self)
        self.text:SetTextColor(unpack(self.visualEnabled == false and colors.muted or colors.text))
        GameTooltip:Hide()
    end)

    configFrame.lootMasterStatus = CreateText(alertsSection, "", 11, colors.muted)
    configFrame.lootMasterStatus:SetPoint("TOPLEFT", configFrame.onlyLootMasterAlerts, "BOTTOMLEFT", 26, -8)
    configFrame.lootMasterStatus:SetWidth(380)

    configFrame.showTargetLootAlerts = CreateCheckbox(alertsSection, "Show coveted loot on boss target", 380)
    configFrame.showTargetLootAlerts:SetPoint("TOPLEFT", configFrame.lootMasterStatus, "BOTTOMLEFT", -26, -12)
    configFrame.showTargetLootAlerts.OnValueChanged = function(_, checked)
        Plutocraseeker.db.config = Plutocraseeker.db.config or {}
        Plutocraseeker.db.config.showTargetLootAlerts = checked and true or false
    end
    configFrame.showTargetLootAlerts:SetScript("OnEnter", function(self)
        self.text:SetTextColor(unpack(colors.accent))
        ShowTargetLootOptionTooltip(self)
    end)
    configFrame.showTargetLootAlerts:SetScript("OnLeave", function(self)
        self.text:SetTextColor(unpack(colors.text))
        GameTooltip:Hide()
    end)

    configFrame.showAnchors = CreateButton(alertsSection, "Show Anchors", 112, 28)
    configFrame.showAnchors:SetPoint("TOPLEFT", configFrame.showTargetLootAlerts, "BOTTOMLEFT", 26, -12)
    configFrame.showAnchors:SetScript("OnEnter", function(self)
        ShowAnchorOptionTooltip(self)
    end)
    configFrame.showAnchors:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    configFrame.showAnchors:SetScript("OnClick", function()
        ShowAnchorOverlay()
    end)

    local characterSection = CreateFrame("Frame", nil, configFrame, Template())
    characterSection:SetPoint("TOPLEFT", alertsSection, "BOTTOMLEFT", 0, -12)
    characterSection:SetSize(438, 104)
    ApplyBackdrop(characterSection, colors.panel)

    characterSection.title = CreateText(characterSection, "Character Sets", 13, colors.accent)
    characterSection.title:SetPoint("TOPLEFT", 12, -10)

    characterSection.description = CreateText(characterSection, "Back up or move this character's Plutocraseeker sets.", 11, colors.muted)
    characterSection.description:SetPoint("TOPLEFT", characterSection.title, "BOTTOMLEFT", 0, -6)
    characterSection.description:SetWidth(400)

    configFrame.importCharacterSets = CreateButton(characterSection, "Import", 82, 28)
    configFrame.importCharacterSets:SetPoint("BOTTOMLEFT", 12, 12)
    SetButtonTooltip(configFrame.importCharacterSets, "Import Character Sets", "Replace this character's sets from a Plutocraseeker character export.")
    configFrame.importCharacterSets:SetScript("OnClick", function()
        if UI.ToggleCharacterImport then
            UI.ToggleCharacterImport()
        end
    end)

    configFrame.exportCharacterSets = CreateButton(characterSection, "Export", 82, 28)
    configFrame.exportCharacterSets:SetPoint("LEFT", configFrame.importCharacterSets, "RIGHT", 8, 0)
    SetButtonTooltip(configFrame.exportCharacterSets, "Export Character Sets", "Copy this character's sets as portable backup text.")
    configFrame.exportCharacterSets:SetScript("OnClick", function()
        if UI.ToggleExport then
            UI.ToggleExport()
        end
    end)

    configFrame:SetScript("OnShow", function()
        RefreshConfigFrame()
    end)
end

function UI.Refresh()
    if not mainFrame or not Plutocraseeker.db then
        return
    end

    RefreshConfigFrame()

    local selectedSet = Plutocraseeker.GetSelectedSet()

    for index, row in ipairs(setRows) do
        local set = Plutocraseeker.db.sets[index]
        if set then
            row:Show()
            row.setId = set.id
            row.text:SetText((set.enabled and "|cff6ee7b7" or "|cff9aa4a1") .. set.name .. "|r")
            SetButtonSelected(row, selectedSet and selectedSet.id == set.id)
        else
            row.setId = nil
            row:Hide()
        end
    end

    if selectedSet then
        mainFrame.setName:SetText(selectedSet.name)
        mainFrame.enabled:SetChecked(selectedSet.enabled)
    else
        mainFrame.setName:SetText("")
        mainFrame.enabled:SetChecked(false)
    end

    local items = selectedSet and selectedSet.items or {}
    if selectedSet and Plutocraseeker.BackfillSetItemDifficulties then
        Plutocraseeker.BackfillSetItemDifficulties(selectedSet, false)
    end

    if itemOffset > math.max(#items - #itemRows, 0) then
        itemOffset = math.max(#items - #itemRows, 0)
    end

    if mainFrame.itemScroll then
        mainFrame.itemScroll:SetRange(#items, #itemRows, itemOffset)
    end

    for index, row in ipairs(itemRows) do
        local item = items[index + itemOffset]
        if item then
            if Plutocraseeker.BackfillTrackedItemDifficulty and (not item.difficultyPrefix or item.difficultyPrefix == "N" or item.heroic) then
                Plutocraseeker.BackfillTrackedItemDifficulty(item.id, false)
            end

            row:Show()
            row.itemId = item.id
            local difficultyPrefix = item.difficultyPrefix or (item.heroic and "H" or nil)
            if difficultyPrefix then
                row.heroicBadge:Show()
                row.heroicBadge:SetText(difficultyPrefix)
                row.name:ClearAllPoints()
                row.name:SetPoint("LEFT", row.heroicBadge, "RIGHT", 4, 0)
                row.name:SetWidth(282)
            else
                row.heroicBadge:Hide()
                row.name:ClearAllPoints()
                row.name:SetPoint("LEFT", 8, 0)
                row.name:SetWidth(300)
            end
            row.name:SetText(Plutocraseeker.GetItemName(item.id))
        else
            row.itemId = nil
            row.heroicBadge:Hide()
            row:Hide()
        end
    end
end

function UI.RefreshConfig()
    RefreshConfigFrame()
end

ScrollItems = function(delta)
    local selectedSet = Plutocraseeker.db and Plutocraseeker.GetSelectedSet and Plutocraseeker.GetSelectedSet()
    local items = selectedSet and selectedSet.items or {}
    itemOffset = math.max(0, math.min(itemOffset - delta, math.max(#items - #itemRows, 0)))
    UI.Refresh()
end

function UI.Toggle()
    if not mainFrame then
        UI.Initialize()
    end

    if mainFrame:IsShown() then
        mainFrame:Hide()
        if Plutocraseeker.AtlasBrowser and Plutocraseeker.AtlasBrowser.Hide then
            Plutocraseeker.AtlasBrowser.Hide()
        end
    else
        mainFrame:Show()
        UI.Refresh()
    end
end

function UI.GetMainFrame()
    if not mainFrame then
        UI.Initialize()
    end
    return mainFrame
end

function UI.ToggleConfig()
    if not mainFrame then
        UI.Initialize()
    end

    if not configFrame then
        CreateConfigPanel()
    end

    if configFrame:IsShown() then
        configFrame:Hide()
        return
    end

    configFrame:ClearAllPoints()
    configFrame:SetPoint("CENTER", mainFrame, "CENTER", 0, 10)
    configFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    configFrame:SetFrameLevel((mainFrame:GetFrameLevel() or 1) + 100)
    if configFrame.Raise then
        configFrame:Raise()
    end
    configFrame:Show()
end

function UI.ToggleWowSimsImport()
    if not mainFrame then
        UI.Initialize()
    end

    if not importFrame then
        CreateImportFrame()
    end

    if importFrame:IsShown() then
        importFrame:Hide()
        return
    end

    importFrame:ClearAllPoints()
    importFrame:SetPoint("CENTER", mainFrame, "CENTER", 0, 0)
    importFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    importFrame:SetFrameLevel((mainFrame:GetFrameLevel() or 1) + 120)
    if importFrame.Raise then
        importFrame:Raise()
    end
    importFrame:Show()
    importFrame.edit:SetFocus()
end

function UI.ToggleWowheadImport()
    if not mainFrame then
        UI.Initialize()
    end

    if not wowheadImportFrame then
        CreateWowheadImportFrame()
    end

    if wowheadImportFrame:IsShown() then
        wowheadImportFrame:Hide()
        return
    end

    wowheadImportFrame:ClearAllPoints()
    wowheadImportFrame:SetPoint("CENTER", mainFrame, "CENTER", 0, 0)
    wowheadImportFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    wowheadImportFrame:SetFrameLevel((mainFrame:GetFrameLevel() or 1) + 120)
    if wowheadImportFrame.Raise then
        wowheadImportFrame:Raise()
    end
    wowheadImportFrame:Show()
    wowheadImportFrame.edit:SetFocus()
end

function UI.ToggleCharacterImport()
    if not mainFrame then
        UI.Initialize()
    end

    if not characterImportFrame then
        CreateCharacterImportFrame()
    end

    if characterImportFrame:IsShown() then
        characterImportFrame:Hide()
        return
    end

    characterImportFrame:ClearAllPoints()
    characterImportFrame:SetPoint("CENTER", mainFrame, "CENTER", 0, 0)
    characterImportFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    characterImportFrame:SetFrameLevel((mainFrame:GetFrameLevel() or 1) + 120)
    if characterImportFrame.Raise then
        characterImportFrame:Raise()
    end
    characterImportFrame:Show()
    characterImportFrame.edit:SetFocus()
end

function UI.ToggleExport()
    if not mainFrame then
        UI.Initialize()
    end

    if not exportFrame then
        CreateExportFrame()
    end

    if exportFrame:IsShown() then
        exportFrame:Hide()
        return
    end

    exportFrame:ClearAllPoints()
    exportFrame:SetPoint("CENTER", mainFrame, "CENTER", 0, 0)
    exportFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    exportFrame:SetFrameLevel((mainFrame:GetFrameLevel() or 1) + 120)
    if exportFrame.Raise then
        exportFrame:Raise()
    end
    exportFrame:Show()
end

function UI.OpenLootBrowser()
    if not mainFrame then
        UI.Initialize()
    end
    mainFrame:Show()
    UI.Refresh()
    if Plutocraseeker.AtlasBrowser and Plutocraseeker.AtlasBrowser.Open then
        Plutocraseeker.AtlasBrowser.Open(mainFrame)
    end
end

function UI.Initialize()
    if not mainFrame then
        CreateMainFrame()
        CreateConfigPanel()
        CreateImportFrame()
        CreateWowheadImportFrame()
        CreateCharacterImportFrame()
        CreateExportFrame()
        CreateConfirmDeleteFrame()
        CreateReceivedItemFrame()
    end
    UI.Refresh()
end
