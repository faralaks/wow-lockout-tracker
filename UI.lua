-- LockoutTracker UI
local addonName = ...
local LOT = LockoutTracker

-- Version (from .toc)
local VERSION = "v" .. (C_AddOns.GetAddOnMetadata(addonName, "Version") or "")

-- UI State
local mainFrame
local activeTab = "instances" -- "instances" or "characters"
local selectedInstance
local selectedCharacter
local updateTabAppearance -- Function to update tab visuals
local levelFilter = "" -- Level filter for Characters tab

-- Class colors
local CLASS_COLORS = RAID_CLASS_COLORS

-- Default frame size
local DEFAULT_FRAME_WIDTH = 1025
local DEFAULT_FRAME_HEIGHT = 600
local ASPECT_RATIO = DEFAULT_FRAME_WIDTH / DEFAULT_FRAME_HEIGHT -- 1.708

-- Layout constants
local COLUMN_TOP_OFFSET = -70 -- Offset from top of frame to columns
local COLUMN_HEIGHT = 485 -- Height of columns (adjusted for footer)
local LEFT_COLUMN_WIDTH = 435
local LEFT_COLUMN_X = 20
local CONTENT_INSET = 62 -- Left column width minus row content width (rows end just before the scrollbar)

-- Scale factor for proportional resizing
local currentScale = 1.0

-- Forward declarations
local RefreshUI
local ClearColumn
local AdjustColumnSizes
local UpdateColumnLayout
local PopulateRightCharacterDetails

-- Static Popup Dialogs
-- Selection dialog for wiping data (Escape = Cancel)
StaticPopupDialogs["LOCKOUTTRACKER_WIPE_SELECT"] = {
    text = "Wipe lockout data?\n\nCurrent character: %s\n\nThis action cannot be undone!",
    button1 = "Current Character",
    button2 = "Cancel",
    button3 = "All Characters",
    OnAccept = function()
        StaticPopup_Show("LOCKOUTTRACKER_WIPE_CHAR_CONFIRM", UnitName("player") .. "-" .. GetRealmName())
    end,
    OnAlt = function()
        StaticPopup_Show("LOCKOUTTRACKER_WIPE_ALL_CONFIRM")
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Confirmation dialog for wiping current character data
StaticPopupDialogs["LOCKOUTTRACKER_WIPE_CHAR_CONFIRM"] = {
    text = "Are you sure you want to wipe data for %s?\n\nThis will delete all saved lockouts for this character and cannot be undone.",
    button1 = "Yes, Wipe Character Data",
    button2 = "Cancel",
    OnAccept = function()
        local key = LOT:GetCharacterKey()
        if LockoutTrackerDB.characters[key] then
            LockoutTrackerDB.characters[key] = nil
            print("|cff00ff00LockoutTracker|r Character data wiped for " .. UnitName("player") .. ".")
            LOT:DebugPrint("Character data deleted for key:", key)
        else
            print("|cff00ff00LockoutTracker|r No data found for current character.")
        end
        RefreshUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    exclusive = 1,
    preferredIndex = 3,
}

-- Confirmation dialog for wiping all data
StaticPopupDialogs["LOCKOUTTRACKER_WIPE_ALL_CONFIRM"] = {
    text = "Are you sure you want to wipe ALL lockout data?\n\nThis will delete all saved lockouts for ALL characters and cannot be undone.",
    button1 = "Yes, Wipe All Data",
    button2 = "Cancel",
    OnAccept = function()
        LockoutTrackerDB.characters = {}
        print("|cff00ff00LockoutTracker|r All data wiped.")
        RefreshUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    exclusive = 1,
    preferredIndex = 3,
}

-- Helper: Get difficulty color code and letter
local function GetDifficultyInfo(difficulty)
    if not difficulty then return "", "" end

    -- Map difficulty IDs to colors and letters
    if difficulty == 1 or difficulty == 14 then
        -- Normal - Green
        return "|cff00ff00", "N"
    elseif difficulty == 2 or difficulty == 15 then
        -- Heroic - Hot Pink (bright red-pink)
        return "|cffff4499", "H"
    elseif difficulty == 16 or difficulty == 23 then
        -- Mythic - Purple (epic color)
        return "|cffa335ee", "M"
    elseif difficulty == 7 or difficulty == 17 then
        -- LFR - Orange
        return "|cffff8000", "L"
    elseif difficulty == 33 then
        -- Timewalking - Blue
        return "|cff0070dd", "T"
    else
        -- Unknown - Grey
        return "|cff888888", "?"
    end
end

-- Helper: Get colored difficulty letter prefix and format instance name (for left column)
local function FormatInstanceName(instanceName, difficulty)
    local colorCode, letter = GetDifficultyInfo(difficulty)
    if colorCode == "" then
        return instanceName
    end
    -- Return: colored letter + space + colored instance name + reset
    return colorCode .. letter .. " " .. instanceName .. "|r"
end

-- Style constants for reusability (base values, will be scaled)
local STYLE_BASE = {
    -- Instance list row (left column big entries)
    INSTANCE_ROW_HEIGHT = 50,
    INSTANCE_FONT_SIZE = 16,
    INSTANCE_FONT_FLAGS = "OUTLINE",

    -- Detail row (middle/right columns)
    DETAIL_ROW_HEIGHT = 40,
}

-- Get scaled style values
local function GetScaledStyle()
    return {
        INSTANCE_ROW_HEIGHT = STYLE_BASE.INSTANCE_ROW_HEIGHT * currentScale,
        INSTANCE_FONT_SIZE = STYLE_BASE.INSTANCE_FONT_SIZE * currentScale,
        INSTANCE_FONT_FLAGS = STYLE_BASE.INSTANCE_FONT_FLAGS,
        DETAIL_ROW_HEIGHT = STYLE_BASE.DETAIL_ROW_HEIGHT * currentScale,
    }
end

-- Current style (updated on resize)
local STYLE = GetScaledStyle()

-- Update column layout based on current frame size
UpdateColumnLayout = function(frame)
    local width = frame:GetWidth()
    local height = frame:GetHeight()

    -- Calculate scaled dimensions
    local leftColWidth = LEFT_COLUMN_WIDTH * currentScale
    local leftColX = LEFT_COLUMN_X * currentScale
    local colHeight = COLUMN_HEIGHT * currentScale
    local colYOffset = COLUMN_TOP_OFFSET * currentScale

    -- Update title position
    if frame.title then
        frame.title:ClearAllPoints()
        frame.title:SetPoint("TOP", 0, -15 * currentScale)
    end

    -- Update resize button size and position
    if frame.resizeButton then
        frame.resizeButton:SetSize(16 * currentScale, 16 * currentScale)
        frame.resizeButton:ClearAllPoints()
        frame.resizeButton:SetPoint("BOTTOMRIGHT", -5 * currentScale, 5 * currentScale)
    end

    -- Update left column
    frame.leftColumn:SetSize(leftColWidth, colHeight)
    frame.leftColumn:ClearAllPoints()
    frame.leftColumn:SetPoint("TOPLEFT", frame, "TOPLEFT", leftColX, colYOffset)
    frame.leftColumn.content:SetWidth(leftColWidth - CONTENT_INSET * currentScale)
    frame.leftColumn.scrollFrame:ClearAllPoints()
    frame.leftColumn.scrollFrame:SetPoint("TOPLEFT", 5 * currentScale, -35 * currentScale)
    frame.leftColumn.scrollFrame:SetPoint("BOTTOMRIGHT", -65 * currentScale, 5 * currentScale)

    -- Update left column header frame
    if frame.leftColumn.headerFrame then
        frame.leftColumn.headerFrame:SetSize(leftColWidth - CONTENT_INSET * currentScale, 18 * currentScale)
        frame.leftColumn.headerFrame:ClearAllPoints()
        frame.leftColumn.headerFrame:SetPoint("TOPLEFT", 10 * currentScale, -15 * currentScale)
    end

    -- Update footer size
    if frame.footer then
        frame.footer:SetSize(frame:GetWidth(), 35 * currentScale)
        frame.footer:ClearAllPoints()
        frame.footer:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
    end

    -- Update main filter frame position
    if frame.filterFrame then
        frame.filterFrame:SetSize(200 * currentScale, 25 * currentScale)
        frame.filterFrame:ClearAllPoints()
        frame.filterFrame:SetPoint("CENTER", frame.footer, "CENTER", 30 * currentScale, 0)
    end

    -- Update tabs position and size (above left column)
    if frame.tabs then
        frame.tabs:SetSize(360 * currentScale, 32 * currentScale)
        frame.tabs:ClearAllPoints()
        frame.tabs:SetPoint("TOPLEFT", frame.leftColumn, "TOPLEFT", 10 * currentScale, 35 * currentScale)

        -- Scale individual tab buttons
        if frame.tabs.instancesTab then
            frame.tabs.instancesTab:SetSize(175 * currentScale, 30 * currentScale)
            frame.tabs.instancesTab:ClearAllPoints()
            frame.tabs.instancesTab:SetPoint("LEFT", 0, 0)
        end
        if frame.tabs.charactersTab then
            frame.tabs.charactersTab:SetSize(175 * currentScale, 30 * currentScale)
            frame.tabs.charactersTab:ClearAllPoints()
            frame.tabs.charactersTab:SetPoint("LEFT", 180 * currentScale, 0)
        end
    end

    -- Call AdjustColumnSizes to position middle and right columns correctly
    AdjustColumnSizes()
end

-- Create main UI frame
local function CreateMainFrame()
    local frame = CreateFrame("Frame", "LockoutTrackerFrame", UIParent, "BackdropTemplate")
    frame:SetSize(DEFAULT_FRAME_WIDTH, DEFAULT_FRAME_HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)

    -- Set resize bounds (min and max size, maintaining aspect ratio)
    local minWidth = 600
    local minHeight = minWidth / ASPECT_RATIO -- ~363
    local maxWidth = 1400
    local maxHeight = maxWidth / ASPECT_RATIO -- ~848
    frame:SetResizeBounds(minWidth, minHeight, maxWidth, maxHeight)

    -- Backdrop with golden border
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 8, right = 8, top = 8, bottom = 8 }
    })
    frame:SetBackdropColor(0, 0, 0, 0.9)
    frame:SetBackdropBorderColor(0.8, 0.7, 0.3, 1) -- Golden border

    -- Title bar
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("Lockout Tracker " .. VERSION)
    frame.title = title

    -- Make draggable
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        -- Save position and size
        local point, _, relativePoint, x, y = self:GetPoint()
        LockoutTrackerDB.framePos = LockoutTrackerDB.framePos or {}
        LockoutTrackerDB.framePos.point = point
        LockoutTrackerDB.framePos.x = x
        LockoutTrackerDB.framePos.y = y
        LockoutTrackerDB.framePos.width = self:GetWidth()
        LockoutTrackerDB.framePos.height = self:GetHeight()
    end)

    -- Save size when resized and enforce aspect ratio
    local isResizing = false
    frame:SetScript("OnSizeChanged", function(self, width, height)
        if isResizing then return end

        -- Enforce aspect ratio (maintain proportions)
        local targetHeight = width / ASPECT_RATIO

        if math.abs(height - targetHeight) > 1 then
            isResizing = true
            self:SetHeight(targetHeight)
            height = targetHeight
            isResizing = false
        end

        -- Calculate scale factor
        currentScale = width / DEFAULT_FRAME_WIDTH

        -- Update style values with new scale
        STYLE = GetScaledStyle()

        -- Update column sizes and positions
        if self.leftColumn then
            UpdateColumnLayout(self)
            -- Refresh UI to recreate rows with new sizes
            RefreshUI()
        end

        -- Save size
        LockoutTrackerDB.framePos = LockoutTrackerDB.framePos or {}
        LockoutTrackerDB.framePos.width = width
        LockoutTrackerDB.framePos.height = height
    end)

    -- Create resize button (bottom-right corner grip)
    local resizeButton = CreateFrame("Button", nil, frame)
    resizeButton:SetSize(16, 16)
    resizeButton:SetPoint("BOTTOMRIGHT", -5, 5)
    resizeButton:EnableMouse(true)
    resizeButton:RegisterForDrag("LeftButton")
    frame.resizeButton = resizeButton

    -- Resize grip texture
    local texture = resizeButton:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    texture:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")

    -- Highlight on hover
    local highlight = resizeButton:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")

    -- Handle resize dragging
    resizeButton:SetScript("OnDragStart", function(self)
        frame:StartSizing("BOTTOMRIGHT")
    end)

    resizeButton:SetScript("OnDragStop", function(self)
        frame:StopMovingOrSizing()
        -- Save the new size
        local width, height = frame:GetWidth(), frame:GetHeight()
        LockoutTrackerDB.framePos = LockoutTrackerDB.framePos or {}
        LockoutTrackerDB.framePos.width = width
        LockoutTrackerDB.framePos.height = height
    end)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -5, -5)

    -- Debug checkbox
    local debugCheckbox = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    debugCheckbox:SetSize(24, 24)
    debugCheckbox:SetPoint("TOPRIGHT", closeBtn, "TOPLEFT", -10, 0)
    debugCheckbox:SetChecked(LockoutTrackerDB.debugMode)

    -- Debug label
    local debugLabel = debugCheckbox:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    debugLabel:SetPoint("RIGHT", debugCheckbox, "LEFT", -5, 0)
    debugLabel:SetText("Debug")
    debugLabel:SetTextColor(0.9, 0.9, 0.9)

    debugCheckbox:SetScript("OnClick", function(self)
        local enabled = self:GetChecked()
        LOT:SetDebug(enabled)
        LockoutTrackerDB.debugMode = enabled
        print("|cff00ff00LockoutTracker|r Debug mode:", enabled and "|cff00ff00ON|r" or "|cffff0000OFF|r")
    end)

    frame.debugCheckbox = debugCheckbox

    -- Wipe data button (left of debug label)
    local wipeBtn = CreateFrame("Button", nil, frame)
    wipeBtn:SetSize(14, 14)
    wipeBtn:SetPoint("TOPRIGHT", debugLabel, "TOPLEFT", -5, 1)

    -- Use a trash can icon texture
    local wipeIcon = wipeBtn:CreateTexture(nil, "ARTWORK")
    wipeIcon:SetAllPoints()
    wipeIcon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    wipeIcon:SetVertexColor(0.9, 0.3, 0.3) -- Reddish tint

    -- Highlight texture
    local wipeHighlight = wipeBtn:CreateTexture(nil, "HIGHLIGHT")
    wipeHighlight:SetAllPoints()
    wipeHighlight:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
    wipeHighlight:SetVertexColor(1, 0.5, 0.5)

    wipeBtn:SetScript("OnClick", function()
        StaticPopup_Show("LOCKOUTTRACKER_WIPE_SELECT", UnitName("player"))
    end)

    -- Tooltip
    wipeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Wipe Data", 1, 1, 1)
        GameTooltip:AddLine("Delete stored lockout data", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    wipeBtn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Footer frame (bottom of main frame)
    local footer = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    footer:SetSize(frame:GetWidth(), 35)
    footer:SetPoint("BOTTOM", frame, "BOTTOM", 0, 0)
    footer:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        tile = true,
        tileSize = 32,
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    footer:SetBackdropColor(0.1, 0.1, 0.1, 0.8)
    footer:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.5)
    frame.footer = footer

    -- Level filter frame (centered in footer, offset right)
    local filterFrame = CreateFrame("Frame", nil, footer)
    filterFrame:SetSize(200, 25)
    filterFrame:SetPoint("CENTER", footer, "CENTER", 30, 0)

    -- "Min level" label (shows characters at or above this level)
    local filterLabel = filterFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    filterLabel:SetPoint("LEFT", 0, 0)
    filterLabel:SetText("Minimum level:")
    filterLabel:SetTextColor(0.9, 0.9, 0.9)

    -- Level input box
    local filterInput = CreateFrame("EditBox", nil, filterFrame, "InputBoxTemplate")
    filterInput:SetSize(35, 20)
    filterInput:SetPoint("LEFT", filterLabel, "RIGHT", 5, 0)
    filterInput:SetAutoFocus(false)
    filterInput:SetNumeric(true)
    filterInput:SetMaxLetters(3)
    filterInput:SetScript("OnTextChanged", function(self)
        levelFilter = self:GetText()
        -- Save to database
        LockoutTrackerDB.levelFilter = levelFilter
        -- Show/hide clear button
        if levelFilter ~= "" then
            filterFrame.clearButton:Show()
        else
            filterFrame.clearButton:Hide()
        end
        RefreshUI()
    end)
    filterInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    filterInput:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    -- Clear button (X)
    local clearButton = CreateFrame("Button", nil, filterFrame)
    clearButton:SetSize(20, 20)
    clearButton:SetPoint("LEFT", filterInput, "RIGHT", 5, 0)
    clearButton:Hide() -- Hidden until there's text

    -- Create X text
    local clearText = clearButton:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    clearText:SetPoint("CENTER")
    clearText:SetText("X")
    clearText:SetTextColor(0.8, 0.3, 0.3)
    clearButton.text = clearText

    -- Hover effect
    clearButton:SetScript("OnEnter", function(self)
        self.text:SetTextColor(1, 0.5, 0.5)
    end)
    clearButton:SetScript("OnLeave", function(self)
        self.text:SetTextColor(0.8, 0.3, 0.3)
    end)

    clearButton:SetScript("OnClick", function()
        filterInput:SetText("")
        levelFilter = ""
        LockoutTrackerDB.levelFilter = ""
        clearButton:Hide()
        RefreshUI()
    end)

    filterFrame.clearButton = clearButton
    filterFrame.filterInput = filterInput
    frame.filterFrame = filterFrame

    -- Hide on ESC (UISpecialFrames handles this properly)
    tinsert(UISpecialFrames, "LockoutTrackerFrame")

    return frame
end

-- Create a scrollable column
local function CreateColumn(parent, width, xOffset, title)
    local column = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    column:SetSize(width, COLUMN_HEIGHT)
    column:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, COLUMN_TOP_OFFSET)

    -- Title
    local titleText = column:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("TOP", 0, 10)
    titleText:SetText(title)
    column.title = titleText

    -- Scroll frame (moved down to make room for headers)
    local scrollFrame = CreateFrame("ScrollFrame", nil, column, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 5, -35)
    scrollFrame:SetPoint("BOTTOMRIGHT", -65, 5)

    -- Make scroll bar semi-transparent
    if scrollFrame.ScrollBar then
        scrollFrame.ScrollBar:SetAlpha(0.5)
    end

    -- Content frame
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(width - CONTENT_INSET, 1)
    content.rowPool = {}
    content.separatorPool = {}
    scrollFrame:SetScrollChild(content)
    column.content = content
    column.scrollFrame = scrollFrame

    -- Rows container
    column.rows = {}

    -- Column headers frame (sits above scroll content)
    local headerFrame = CreateFrame("Frame", nil, column)
    headerFrame:SetSize(width - CONTENT_INSET, 18)
    headerFrame:SetPoint("TOPLEFT", 10, -15)

    -- Left header text
    local leftHeader = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    leftHeader:SetPoint("LEFT", 0, 0)
    leftHeader:SetTextColor(0.7, 0.7, 0.7)
    headerFrame.leftHeader = leftHeader

    -- Right header text
    local rightHeader = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rightHeader:SetPoint("RIGHT", -5, 0)
    rightHeader:SetTextColor(0.7, 0.7, 0.7)
    headerFrame.rightHeader = rightHeader

    column.headerFrame = headerFrame

    return column
end

-- Create tab buttons
local function CreateTabs(parent)
    local tabContainer = CreateFrame("Frame", nil, parent)
    tabContainer:SetSize(360, 32)
    tabContainer:SetPoint("TOPLEFT", parent.leftColumn, "TOPLEFT", 10, 35) -- Position above column

    local function CreateTabButton(text, index)
        local tab = CreateFrame("Button", nil, tabContainer, "BackdropTemplate")
        tab:SetSize(175, 30)
        tab:SetPoint("LEFT", (index - 1) * 180, 0)

        -- Simple solid background with border
        tab:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = true,
            tileSize = 32,
            edgeSize = 2,
            insets = { left = 1, right = 1, top = 1, bottom = 1 }
        })

        local tabText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        tabText:SetPoint("CENTER")
        tabText:SetText(text)
        tab.text = tabText

        return tab
    end

    local instancesTab = CreateTabButton("Lockouts", 1)
    local charactersTab = CreateTabButton("Characters", 2)

    -- Store references for scaling
    tabContainer.instancesTab = instancesTab
    tabContainer.charactersTab = charactersTab

    local function UpdateTabAppearance()
        if activeTab == "instances" then
            -- Active tab: golden border, brighter background
            instancesTab:SetBackdropColor(0.3, 0.27, 0.15, 0.95)
            instancesTab:SetBackdropBorderColor(0.8, 0.7, 0.3, 1)
            instancesTab.text:SetTextColor(1, 0.82, 0, 1) -- Golden text
            -- Inactive tab: grey with more transparent border
            charactersTab:SetBackdropColor(0.15, 0.15, 0.15, 0.7)
            charactersTab:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.25) -- More transparent
            charactersTab.text:SetTextColor(0.7, 0.7, 0.7, 1)
        else
            -- Inactive tab: grey with more transparent border
            instancesTab:SetBackdropColor(0.15, 0.15, 0.15, 0.7)
            instancesTab:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.25) -- More transparent
            instancesTab.text:SetTextColor(0.7, 0.7, 0.7, 1)
            -- Active tab: golden border, brighter background
            charactersTab:SetBackdropColor(0.3, 0.27, 0.15, 0.95)
            charactersTab:SetBackdropBorderColor(0.8, 0.7, 0.3, 1)
            charactersTab.text:SetTextColor(1, 0.82, 0, 1) -- Golden text
        end
    end

    instancesTab:SetScript("OnClick", function()
        if activeTab ~= "instances" then
            activeTab = "instances"
            selectedInstance = nil
            selectedCharacter = nil
            UpdateTabAppearance()
            AdjustColumnSizes()
            RefreshUI()
        end
    end)

    charactersTab:SetScript("OnClick", function()
        if activeTab ~= "characters" then
            activeTab = "characters"
            selectedInstance = nil
            selectedCharacter = nil
            UpdateTabAppearance()
            AdjustColumnSizes()
            RefreshUI()
        end
    end)

    -- Hover effects
    instancesTab:SetScript("OnEnter", function(self)
        if activeTab ~= "instances" then
            self:SetBackdropColor(0.25, 0.25, 0.25, 0.85)
            self:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
        end
    end)
    instancesTab:SetScript("OnLeave", function(self)
        UpdateTabAppearance()
    end)

    charactersTab:SetScript("OnEnter", function(self)
        if activeTab ~= "characters" then
            self:SetBackdropColor(0.25, 0.25, 0.25, 0.85)
            self:SetBackdropBorderColor(0.6, 0.6, 0.6, 0.8)
        end
    end)
    charactersTab:SetScript("OnLeave", function(self)
        UpdateTabAppearance()
    end)

    UpdateTabAppearance()

    -- Store reference so we can call it from ToggleUI
    updateTabAppearance = UpdateTabAppearance

    return tabContainer
end

-- Create a row with texture background (reuses released rows from the parent's pool)
local function CreateRow(parent, height, onClick)
    local row = table.remove(parent.rowPool)
    if not row then
        row = CreateFrame("Button", nil, parent, "BackdropTemplate")
        row:SetBackdrop({
            bgFile = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight",
            edgeFile = nil,
            tile = false
        })

        -- Text
        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetJustifyH("LEFT")
        row.text = text
        row.defaultFont = { text:GetFont() }

        -- Right text (for time/count)
        local rightText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        rightText:SetPoint("RIGHT", -10, 0)
        rightText:SetJustifyH("RIGHT")
        rightText:SetTextColor(0.7, 0.7, 0.7)
        row.rightText = rightText

        -- Hover effect
        row:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.4, 0.4, 0.4, 0.7)
        end)
        row:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.2, 0.2, 0.2, 0.5)
        end)
    end

    -- Reset state left over from previous use
    row:SetSize(parent:GetWidth() - 10, height)
    row:SetBackdropColor(0.2, 0.2, 0.2, 0.5)
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", 10, 0)
    row.text:SetFont(unpack(row.defaultFont))
    row.text:SetWidth(0)
    row.text:SetWordWrap(true)
    row.text:SetText("")
    row.rightText:SetText("")
    if row.factionIcon then
        row.factionIcon:Hide()
    end
    row:SetScript("OnClick", onClick)

    return row
end

-- Create a golden separator line (reuses released separators from the parent's pool)
local function CreateSeparator(parent, yOffset)
    local separator = table.remove(parent.separatorPool)
    if not separator then
        separator = parent:CreateTexture(nil, "ARTWORK")
        separator:SetColorTexture(0.8, 0.7, 0.3, 0.5) -- Golden line
        separator:SetHeight(2)
    end
    separator:SetPoint("TOPLEFT", 5, -yOffset)
    separator:SetPoint("TOPRIGHT", -5, -yOffset)
    separator:Show()
    return separator
end

-- Clear column (rows and separators go back to the pools)
ClearColumn = function(column)
    local content = column.content
    for _, item in ipairs(column.rows) do
        item:Hide()
        item:ClearAllPoints()
        if item:IsObjectType("Texture") then
            table.insert(content.separatorPool, item)
        else
            table.insert(content.rowPool, item)
        end
    end
    column.rows = {}

    -- Hide scrollbar when column is empty (except for left column which always shows scrollbar)
    if column.scrollFrame and column.scrollFrame.ScrollBar and column ~= mainFrame.leftColumn then
        column.scrollFrame.ScrollBar:Hide()
    end
end

-- Adjust column sizes based on active tab
AdjustColumnSizes = function()
    if not mainFrame then return end

    local colHeight = COLUMN_HEIGHT * currentScale
    local colYOffset = COLUMN_TOP_OFFSET * currentScale

    if activeTab == "instances" then
        -- Instances tab: middle shows characters (short), right shows instances (longer)
        -- Middle: narrower, Right: wider
        local midWidth = 250 * currentScale
        local midX = 435 * currentScale
        local rightWidth = 312 * currentScale
        local rightX = 683 * currentScale

        mainFrame.middleColumn:SetSize(midWidth, colHeight)
        mainFrame.middleColumn:ClearAllPoints()
        mainFrame.middleColumn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", midX, colYOffset)
        mainFrame.middleColumn.content:SetWidth(midWidth - 30 * currentScale)

        if mainFrame.middleColumn.headerFrame then
            mainFrame.middleColumn.headerFrame:SetSize(midWidth - 30 * currentScale, 18 * currentScale)
        end

        mainFrame.rightColumn:SetSize(rightWidth, colHeight)
        mainFrame.rightColumn:ClearAllPoints()
        mainFrame.rightColumn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", rightX, colYOffset)
        mainFrame.rightColumn.content:SetWidth(rightWidth - 30 * currentScale)

        if mainFrame.rightColumn.headerFrame then
            mainFrame.rightColumn.headerFrame:SetSize(rightWidth - 30 * currentScale, 18 * currentScale)
        end
    else
        -- Characters tab: middle shows instances (longer), right shows characters (short)
        -- Middle: wider, Right: narrower
        local midWidth = 300 * currentScale
        local midX = 435 * currentScale
        local rightWidth = 262 * currentScale
        local rightX = 733 * currentScale

        mainFrame.middleColumn:SetSize(midWidth, colHeight)
        mainFrame.middleColumn:ClearAllPoints()
        mainFrame.middleColumn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", midX, colYOffset)
        mainFrame.middleColumn.content:SetWidth(midWidth - 30 * currentScale)

        if mainFrame.middleColumn.headerFrame then
            mainFrame.middleColumn.headerFrame:SetSize(midWidth - 30 * currentScale, 18 * currentScale)
        end

        mainFrame.rightColumn:SetSize(rightWidth, colHeight)
        mainFrame.rightColumn:ClearAllPoints()
        mainFrame.rightColumn:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", rightX, colYOffset)
        mainFrame.rightColumn.content:SetWidth(rightWidth - 30 * currentScale)

        if mainFrame.rightColumn.headerFrame then
            mainFrame.rightColumn.headerFrame:SetSize(rightWidth - 30 * currentScale, 18 * currentScale)
        end
    end
end

-- Helper: Format instance details (just use Blizzard's difficulty name)
local function FormatInstanceDetails(data)
    -- Just use what Blizzard gives us - it's already correct
    if data.difficultyName and data.difficultyName ~= "" then
        return " (" .. data.difficultyName .. ")"
    end
    return ""
end

-- Modular: Create instance list row (for left column)
local function CreateInstanceListRow(parent, instanceName, instanceData, onClick)
    local row = CreateRow(parent, STYLE.INSTANCE_ROW_HEIGHT, onClick)

    -- Format instance name with colored difficulty prefix and colored name
    local displayText = FormatInstanceName(instanceName, instanceData.difficulty)

    -- Handle long instance names (left column has bigger font + time display)
    local textLen = string.len(instanceName)

    row.text:SetText(displayText)
    row.text:SetWordWrap(false)

    -- Reserve space for time and character count (add padding for prefix)
    row.text:SetWidth(parent:GetWidth() - 110)

    -- Adjust font size for long names (let SetWidth handle clipping)
    if textLen > 30 then
        row.text:SetFont(row.text:GetFont(), 14, STYLE.INSTANCE_FONT_FLAGS) -- Smaller font
    elseif STYLE.INSTANCE_FONT_SIZE then
        row.text:SetFont(row.text:GetFont(), STYLE.INSTANCE_FONT_SIZE, STYLE.INSTANCE_FONT_FLAGS)
    end

    -- Time and character count (filtered by level)
    local timeStr = LOT:FormatTimeRemaining(instanceData.earliestExpiry or instanceData.expires)
    local minLevel = tonumber(levelFilter) or 0
    local charCount = 0
    local totalChars = 0

    -- Count characters with lockout (filtered by level)
    for _, charKey in ipairs(instanceData.characters) do
        local charData = LockoutTrackerDB.characters[charKey]
        if charData then
            local charLevel = charData.level or 0
            if levelFilter == "" or charLevel >= minLevel then
                charCount = charCount + 1
            end
        end
    end

    -- Count total characters (filtered by level)
    for _, charData in pairs(LockoutTrackerDB.characters) do
        local charLevel = charData.level or 0
        if levelFilter == "" or charLevel >= minLevel then
            totalChars = totalChars + 1
        end
    end

    row.rightText:SetText(string.format("%s (%d/%d)", timeStr, charCount, totalChars))

    return row
end

-- Modular: Create detail row (for middle/right columns showing instance details)
local function CreateInstanceDetailRow(parent, instanceName, instanceData, onClick)
    local row = CreateRow(parent, STYLE.DETAIL_ROW_HEIGHT, onClick)

    -- Build colored text with difficulty details inside the color
    local colorCode = GetDifficultyInfo(instanceData.difficulty)
    local text
    if colorCode == "" then
        text = instanceName .. FormatInstanceDetails(instanceData)
    else
        text = colorCode .. instanceName .. FormatInstanceDetails(instanceData) .. "|r"
    end
    local textLen = string.len(text)

    row.text:SetText(text)
    row.text:SetWordWrap(false)

    -- Reserve space for boss progress
    local bossInfo = instanceData.bossProgress or instanceData.bossesKilled
    local reservedSpace = (bossInfo and bossInfo ~= "" and bossInfo ~= 0) and 60 or 20
    row.text:SetWidth(parent:GetWidth() - reservedSpace)

    -- Show boss progress on right side (grey text)
    if bossInfo and bossInfo ~= "" and bossInfo ~= 0 then
        row.rightText:SetText(tostring(bossInfo))
    end

    -- Adjust font size for long names (let SetWidth handle clipping)
    if textLen > 35 then
        local font, _, flags = row.text:GetFont()
        row.text:SetFont(font, 11, flags) -- Smaller font for long names
    end

    return row
end

-- Modular: Create character row
local function CreateCharacterRow(parent, charKey, charData, hasCD, showCDCount, onClick, bossCount)
    local row = CreateRow(parent, 40, onClick)

    -- Get faction from charData, fallback to parsing key (last part after final dash)
    local faction = charData.faction or charKey:match("%-([^%-]+)$")

    -- Faction icon
    if not row.factionIcon then
        row.factionIcon = row:CreateTexture(nil, "ARTWORK")
        row.factionIcon:SetSize(24, 24)
        row.factionIcon:SetPoint("TOPLEFT", 10, -11)
    end
    if faction == "Horde" then
        row.factionIcon:SetTexture("Interface\\TargetingFrame\\UI-PVP-Horde")
        row.factionIcon:Show()
    elseif faction == "Alliance" then
        row.factionIcon:SetTexture("Interface\\TargetingFrame\\UI-PVP-Alliance")
        row.factionIcon:Show()
    end

    local displayName = LOT:GetCharacterDisplayName(charKey)
    local classColor = CLASS_COLORS[charData.class]

    -- Adjust text position to make room for faction icon
    row.text:ClearAllPoints()
    row.text:SetPoint("LEFT", 30, 0)

    -- Make font bigger for character names
    local font, _, flags = row.text:GetFont()
    row.text:SetFont(font, 14, flags)

    if hasCD or hasCD == nil then
        -- Bright with class color
        if classColor then
            row.text:SetText(string.format("|c%s%s|r", classColor.colorStr, displayName))
        else
            row.text:SetText(displayName)
        end
    else
        -- Grey out
        row.text:SetText(string.format("|cff888888%s|r", displayName))
        row:SetBackdropColor(0.1, 0.1, 0.1, 0.3)
    end

    -- Show boss count if provided
    if bossCount then
        row.rightText:SetText(tostring(bossCount))
    -- Show CD count if requested
    elseif showCDCount then
        local count = 0
        local currentTime = time()
        for _, data in pairs(charData.instances) do
            if data.expires and data.expires > currentTime then
                count = count + 1
            end
        end
        row.rightText:SetText(tostring(count)) -- No brackets
    end

    return row
end

-- Setup column layout for character list (middle/right columns only)
local function SetupColumnForCharacterList(column)
    -- Position title to the left with width limit for truncation
    column.title:ClearAllPoints()
    column.title:SetPoint("TOPLEFT", -5, 10)
    column.title:SetWidth(230)
    column.title:SetWordWrap(false)

    -- Set column headers
    column.headerFrame.leftHeader:SetText("Character")
    column.headerFrame.rightHeader:SetText("Progress")
    column.headerFrame.rightHeader:SetJustifyH("RIGHT")
    column.headerFrame.rightHeader:ClearAllPoints()
    column.headerFrame.rightHeader:SetPoint("RIGHT", -24, 0)

    -- Adjust scrollbar position and show it
    if column.scrollFrame then
        column.scrollFrame:ClearAllPoints()
        column.scrollFrame:SetPoint("TOPLEFT", 5 * currentScale, -35 * currentScale)
        column.scrollFrame:SetPoint("BOTTOMRIGHT", -32 * currentScale, 5 * currentScale)
        if column.scrollFrame.ScrollBar then
            column.scrollFrame.ScrollBar:Show()
        end
    end
end

-- Setup column layout for instance list (middle/right columns only)
local function SetupColumnForInstanceList(column)
    -- Position title to the left with width limit for truncation
    column.title:ClearAllPoints()
    column.title:SetPoint("TOPLEFT", 24, 10)
    column.title:SetWidth(225)
    column.title:SetWordWrap(false)

    -- Set column headers
    column.headerFrame.leftHeader:SetText("Lockout")
    column.headerFrame.rightHeader:SetText("Progress")
    column.headerFrame.rightHeader:SetJustifyH("RIGHT")
    column.headerFrame.rightHeader:ClearAllPoints()
    column.headerFrame.rightHeader:SetPoint("RIGHT", -24, 0)

    -- Adjust scrollbar position and show it
    if column.scrollFrame then
        column.scrollFrame:ClearAllPoints()
        column.scrollFrame:SetPoint("TOPLEFT", 5 * currentScale, -35 * currentScale)
        column.scrollFrame:SetPoint("BOTTOMRIGHT", -32 * currentScale, 5 * currentScale)
        if column.scrollFrame.ScrollBar then
            column.scrollFrame.ScrollBar:Show()
        end
    end
end

-- Populate left column: Instances tab
local function PopulateLeftInstances()
    local column = mainFrame.leftColumn
    ClearColumn(column)
    column.title:SetText("") -- Hide title, tabs show what's displayed

    -- Set column headers
    column.headerFrame.leftHeader:SetText("Lockout")
    column.headerFrame.rightHeader:SetText("Resets")
    column.headerFrame.rightHeader:SetJustifyH("RIGHT")
    column.headerFrame.rightHeader:ClearAllPoints()
    column.headerFrame.rightHeader:SetPoint("RIGHT", -22, 0)

    local instances = LOT:GetActiveInstances()
    local currentTime = time()

    -- Build sorted list
    local sortedInstances = {}
    for instanceKey, data in pairs(instances) do
        if data.earliestExpiry > currentTime then
            table.insert(sortedInstances, {
                key = instanceKey, -- The full "name:difficulty" key
                name = data.name, -- Just the name for display
                data = data
            })
        end
    end

    table.sort(sortedInstances, function(a, b)
        -- Sort by name first, then by difficulty
        if a.name == b.name then
            return (a.data.difficulty or 0) < (b.data.difficulty or 0)
        end
        return a.name < b.name
    end)

    -- Create rows
    local yOffset = 0
    for _, entry in ipairs(sortedInstances) do
        local row = CreateInstanceListRow(column.content, entry.name, entry.data, function()
            selectedInstance = {
                key = entry.key, -- Full "name:difficulty" key
                name = entry.name,
                data = entry.data
            }
            selectedCharacter = nil
            RefreshUI()
        end)

        row:SetPoint("TOPLEFT", 0, -yOffset)
        table.insert(column.rows, row)
        row:Show()
        yOffset = yOffset + STYLE.INSTANCE_ROW_HEIGHT
    end

    column.content:SetHeight(math.max(yOffset, column:GetHeight()))
end

-- Populate left column: Characters tab
local function PopulateLeftCharacters()
    local column = mainFrame.leftColumn
    ClearColumn(column)
    column.title:SetText("") -- Hide title, tabs show what's displayed

    -- Set column headers
    column.headerFrame.leftHeader:SetText("Character")
    column.headerFrame.rightHeader:SetText("Lockouts")
    column.headerFrame.rightHeader:SetJustifyH("RIGHT")
    column.headerFrame.rightHeader:ClearAllPoints()
    column.headerFrame.rightHeader:SetPoint("RIGHT", -22, 0)

    local currentTime = time()
    local chars = {}
    local currentCharKey = LOT:GetCharacterKey()
    local minLevel = tonumber(levelFilter) or 0

    for charKey, charData in pairs(LockoutTrackerDB.characters) do
        local count = 0
        for _, data in pairs(charData.instances) do
            if data.expires and data.expires > currentTime then
                count = count + 1
            end
        end

        -- Apply level filter
        local charLevel = charData.level or 0
        local passesFilter = (levelFilter == "" or charLevel >= minLevel)

        -- Always include current character, even if no CDs
        if passesFilter and (count > 0 or charKey == currentCharKey) then
            table.insert(chars, {
                key = charKey,
                data = charData,
                cdCount = count,
                isCurrent = charKey == currentCharKey
            })
        end
    end

    -- Sort: current character first, then alphabetically
    table.sort(chars, function(a, b)
        if a.isCurrent ~= b.isCurrent then
            return a.isCurrent -- Current char comes first
        end
        return a.key < b.key
    end)

    -- Create rows
    local yOffset = 0
    for i, entry in ipairs(chars) do
        local row = CreateCharacterRow(column.content, entry.key, entry.data, true, true, function()
            selectedCharacter = entry.key
            selectedInstance = nil
            RefreshUI()
        end)

        row.text:SetFont(row.text:GetFont(), 14, "OUTLINE") -- Larger font
        row:SetPoint("TOPLEFT", 0, -yOffset)
        table.insert(column.rows, row)
        row:Show()
        yOffset = yOffset + 40

        -- Add separator after current character
        if entry.isCurrent then
            table.insert(column.rows, CreateSeparator(column.content, yOffset)) -- Track for cleanup
            yOffset = yOffset + 10 -- Space after separator
        end
    end

    column.content:SetHeight(math.max(yOffset, column:GetHeight()))
end

-- Populate middle column: Characters for selected instance
local function PopulateMiddleCharactersForInstance()
    local column = mainFrame.middleColumn
    ClearColumn(column)

    if not selectedInstance then
        column.title:SetText("Select an instance")
        column.title:ClearAllPoints()
        column.title:SetPoint("TOP", 0, 10)
        column.headerFrame.leftHeader:SetText("")
        column.headerFrame.rightHeader:SetText("")
        return
    end

    -- Setup column layout for character list
    SetupColumnForCharacterList(column)

    -- Format title with colored difficulty letter prefix
    local formattedTitle = FormatInstanceName(selectedInstance.name, selectedInstance.data.difficulty)
    column.title:SetText(formattedTitle)

    local currentCharKey = LOT:GetCharacterKey()
    local minLevel = tonumber(levelFilter) or 0
    local allChars = {}
    for charKey, char in pairs(LockoutTrackerDB.characters) do
        -- Apply level filter
        local charLevel = char.level or 0
        local passesFilter = (levelFilter == "" or charLevel >= minLevel)

        if passesFilter then
            table.insert(allChars, {
                key = charKey,
                char = char,
                isCurrent = charKey == currentCharKey
            })
        end
    end

    -- Sort by: has CD (bright first), then current character (only if has CD), then alphabetically
    table.sort(allChars, function(a, b)
        local aHasCD = tContains(selectedInstance.data.characters, a.key)
        local bHasCD = tContains(selectedInstance.data.characters, b.key)
        if aHasCD ~= bHasCD then
            return aHasCD
        end
        -- Within same CD status, current char first ONLY if they have the CD
        if aHasCD and a.isCurrent ~= b.isCurrent then
            return a.isCurrent
        end
        return a.key < b.key
    end)

    local yOffset = 0
    for _, entry in ipairs(allChars) do
        local hasCD = tContains(selectedInstance.data.characters, entry.key)

        -- Get boss progress for this character on this instance
        local bossCount = nil
        if hasCD and entry.char.instances and selectedInstance.key then
            -- Use the full key (name:difficulty) to look up instance data
            local instanceData = entry.char.instances[selectedInstance.key]
            if instanceData then
                -- Prefer new progress string, fallback to old killed count
                bossCount = instanceData.bossProgress or instanceData.bossesKilled
            end
        end

        local row = CreateCharacterRow(column.content, entry.key, entry.char, hasCD, false, function()
            selectedCharacter = entry.key
            RefreshUI()
        end, bossCount)

        row:SetPoint("TOPLEFT", 0, -yOffset)
        table.insert(column.rows, row)
        row:Show()
        yOffset = yOffset + 40

        -- Add separator after current character (only if they have the CD)
        if entry.isCurrent and hasCD then
            table.insert(column.rows, CreateSeparator(column.content, yOffset))
            yOffset = yOffset + 10
        end
    end

    column.content:SetHeight(math.max(yOffset, column:GetHeight()))

    -- Auto-select current character if they have CD (only set, don't refresh)
    if not selectedCharacter then
        if tContains(selectedInstance.data.characters, currentCharKey) then
            selectedCharacter = currentCharKey
            -- Just populate right column, don't refresh everything
            PopulateRightCharacterDetails()
        end
    end
end

-- Populate middle column: Instances for selected character
local function PopulateMiddleInstancesForCharacter()
    local column = mainFrame.middleColumn
    ClearColumn(column)

    if not selectedCharacter then
        column.title:SetText("Select a character")
        column.title:ClearAllPoints()
        column.title:SetPoint("TOP", 0, 10)
        column.headerFrame.leftHeader:SetText("")
        column.headerFrame.rightHeader:SetText("")
        return
    end

    local char = LockoutTrackerDB.characters[selectedCharacter]
    if not char then return end

    -- Setup column layout for instance list
    SetupColumnForInstanceList(column)

    local name, realm = LOT:GetCharacterNameRealm(selectedCharacter)
    column.title:SetText(string.format("%s - %s (%d)", name or "", realm or "", char.level or 0))

    local currentTime = time()
    local instances = {}

    for instanceKey, data in pairs(char.instances) do
        if data.expires and data.expires > currentTime then
            table.insert(instances, {
                name = data.name or instanceKey:match("^([^:]+)"), -- Use stored name or extract from key
                data = data
            })
        end
    end

    table.sort(instances, function(a, b)
        -- Sort by name first, then by difficulty
        if a.name == b.name then
            return (a.data.difficulty or 0) < (b.data.difficulty or 0)
        end
        return a.name < b.name
    end)

    local yOffset = 0
    for _, entry in ipairs(instances) do
        local row = CreateInstanceDetailRow(column.content, entry.name, entry.data, function()
            -- Get global instance data for right column using name:difficulty key
            local instanceKey = entry.name .. ":" .. (entry.data.difficulty or 0)
            local instanceData = LOT:GetActiveInstances()[instanceKey]
            if instanceData then
                selectedInstance = {
                    key = instanceKey, -- Full "name:difficulty" key
                    name = entry.name,
                    difficulty = entry.data.difficulty,
                    data = instanceData,
                    instanceData = entry.data -- Store the character's instance data for difficulty info
                }
                RefreshUI()
            end
        end)

        row:SetPoint("TOPLEFT", 0, -yOffset)
        table.insert(column.rows, row)
        row:Show()
        yOffset = yOffset + STYLE.DETAIL_ROW_HEIGHT
    end

    column.content:SetHeight(math.max(yOffset, column:GetHeight()))
end

-- Populate right column: All CDs for selected character
PopulateRightCharacterDetails = function()
    local column = mainFrame.rightColumn
    ClearColumn(column)

    if not selectedCharacter then
        column.title:SetText("Select a character")
        column.title:ClearAllPoints()
        column.title:SetPoint("TOP", 0, 10)
        column.headerFrame.leftHeader:SetText("")
        column.headerFrame.rightHeader:SetText("")
        return
    end

    local char = LockoutTrackerDB.characters[selectedCharacter]
    if not char then return end

    -- Setup column layout for instance list
    SetupColumnForInstanceList(column)

    local name, realm = LOT:GetCharacterNameRealm(selectedCharacter)
    column.title:SetText(string.format("%s - %s (%d)", name or "", realm or "", char.level or 0))

    local currentTime = time()
    local instances = {}

    for instanceKey, data in pairs(char.instances) do
        if data.expires and data.expires > currentTime then
            table.insert(instances, {
                name = data.name or instanceKey:match("^([^:]+)"), -- Use stored name or extract from key
                data = data
            })
        end
    end

    table.sort(instances, function(a, b)
        -- Sort by name first, then by difficulty
        if a.name == b.name then
            return (a.data.difficulty or 0) < (b.data.difficulty or 0)
        end
        return a.name < b.name
    end)

    local yOffset = 0
    for _, entry in ipairs(instances) do
        local row = CreateInstanceDetailRow(column.content, entry.name, entry.data)
        row:SetPoint("TOPLEFT", 0, -yOffset)
        table.insert(column.rows, row)
        row:Show()
        yOffset = yOffset + STYLE.DETAIL_ROW_HEIGHT
    end

    column.content:SetHeight(math.max(yOffset, column:GetHeight()))
end

-- Populate right column: All characters with CD on selected instance
local function PopulateRightCharactersForInstance()
    local column = mainFrame.rightColumn
    ClearColumn(column)

    if not selectedInstance then
        column.title:SetText("Select an instance")
        column.title:ClearAllPoints()
        column.title:SetPoint("TOP", 0, 10)
        column.headerFrame.leftHeader:SetText("")
        column.headerFrame.rightHeader:SetText("")
        return
    end

    -- Setup column layout for character list
    SetupColumnForCharacterList(column)

    -- Build full title with colored difficulty
    local colorCode = GetDifficultyInfo(selectedInstance.data.difficulty)
    local titleText
    if colorCode == "" then
        titleText = selectedInstance.name
        if selectedInstance.instanceData then
            titleText = titleText .. FormatInstanceDetails(selectedInstance.instanceData)
        end
    else
        titleText = colorCode .. selectedInstance.name
        if selectedInstance.instanceData then
            titleText = titleText .. FormatInstanceDetails(selectedInstance.instanceData)
        end
        titleText = titleText .. "|r"
    end
    column.title:SetText(titleText)

    local currentCharKey = LOT:GetCharacterKey()
    local minLevel = tonumber(levelFilter) or 0
    local chars = {}
    for _, charKey in ipairs(selectedInstance.data.characters) do
        local charData = LockoutTrackerDB.characters[charKey]
        if charData then
            -- Apply level filter
            local charLevel = charData.level or 0
            local passesFilter = (levelFilter == "" or charLevel >= minLevel)

            if passesFilter then
                table.insert(chars, {
                    key = charKey,
                    data = charData,
                    isCurrent = charKey == currentCharKey
                })
            end
        end
    end

    -- Sort: current character first, then alphabetically
    table.sort(chars, function(a, b)
        if a.isCurrent ~= b.isCurrent then
            return a.isCurrent
        end
        return a.key < b.key
    end)

    local yOffset = 0
    for _, entry in ipairs(chars) do
        -- Get boss progress for this character on this instance
        local bossCount = nil
        if entry.data.instances and selectedInstance.key then
            -- Use the full key (name:difficulty) to look up instance data
            local instanceData = entry.data.instances[selectedInstance.key]
            if instanceData then
                -- Prefer new progress string, fallback to old killed count
                bossCount = instanceData.bossProgress or instanceData.bossesKilled
            end
        end

        local row = CreateCharacterRow(column.content, entry.key, entry.data, true, false, nil, bossCount)
        row:SetPoint("TOPLEFT", 0, -yOffset)
        table.insert(column.rows, row)
        row:Show()
        yOffset = yOffset + 40

        -- Add separator after current character (always show in right column since all chars here have the CD)
        if entry.isCurrent then
            table.insert(column.rows, CreateSeparator(column.content, yOffset))
            yOffset = yOffset + 10
        end
    end

    column.content:SetHeight(math.max(yOffset, column:GetHeight()))
end

-- Main refresh function
RefreshUI = function()
    LOT:DebugPrint("RefreshUI called, mainFrame exists:", mainFrame ~= nil, "isShown:", mainFrame and mainFrame:IsShown() or "N/A")

    if not mainFrame then
        LOT:DebugPrint("RefreshUI: mainFrame is nil, returning")
        return
    end

    if not mainFrame:IsShown() then
        LOT:DebugPrint("RefreshUI: mainFrame is not shown, returning")
        return
    end

    LOT:DebugPrint("RefreshUI: Proceeding with activeTab:", activeTab)

    if activeTab == "instances" then
        -- Instances tab flow
        PopulateLeftInstances()

        if selectedInstance then
            PopulateMiddleCharactersForInstance()

            if selectedCharacter then
                PopulateRightCharacterDetails()
            else
                ClearColumn(mainFrame.rightColumn)
                mainFrame.rightColumn.title:SetText("Select a character")
                mainFrame.rightColumn.headerFrame.leftHeader:SetText("")
                mainFrame.rightColumn.headerFrame.rightHeader:SetText("")
            end
        else
            ClearColumn(mainFrame.middleColumn)
            ClearColumn(mainFrame.rightColumn)
            mainFrame.middleColumn.title:SetText("Select an instance")
            mainFrame.middleColumn.headerFrame.leftHeader:SetText("")
            mainFrame.middleColumn.headerFrame.rightHeader:SetText("")
            mainFrame.rightColumn.title:SetText("Select a character")
            mainFrame.rightColumn.headerFrame.leftHeader:SetText("")
            mainFrame.rightColumn.headerFrame.rightHeader:SetText("")
        end
    else
        -- Characters tab flow
        PopulateLeftCharacters()

        if selectedCharacter then
            PopulateMiddleInstancesForCharacter()

            if selectedInstance then
                PopulateRightCharactersForInstance()
            else
                ClearColumn(mainFrame.rightColumn)
                mainFrame.rightColumn.title:SetText("Select an instance")
                mainFrame.rightColumn.headerFrame.leftHeader:SetText("")
                mainFrame.rightColumn.headerFrame.rightHeader:SetText("")
            end
        else
            ClearColumn(mainFrame.middleColumn)
            ClearColumn(mainFrame.rightColumn)
            mainFrame.middleColumn.title:SetText("Select a character")
            mainFrame.middleColumn.headerFrame.leftHeader:SetText("")
            mainFrame.middleColumn.headerFrame.rightHeader:SetText("")
            mainFrame.rightColumn.title:SetText("Select an instance")
            mainFrame.rightColumn.headerFrame.leftHeader:SetText("")
            mainFrame.rightColumn.headerFrame.rightHeader:SetText("")
        end
    end
end

-- Refresh UI (method) - called by Core.lua when lockout data changes
function LOT:RefreshUI()
    RefreshUI()
end

-- Reset UI (method) - frame is recreated with defaults on next open
function LOT:ResetUI()
    if mainFrame then
        mainFrame:Hide()
        mainFrame = nil
    end
    currentScale = 1.0
    STYLE = GetScaledStyle()
end

-- Toggle UI (method)
function LOT:ToggleUI()
    LOT:DebugPrint("ToggleUI called, mainFrame exists:", mainFrame ~= nil)

    if not mainFrame then
        LOT:DebugPrint("Creating mainFrame...")
        mainFrame = CreateMainFrame()
        mainFrame:Hide() -- Explicitly hide on creation (frames are shown by default)
        LOT:DebugPrint("mainFrame created and hidden, exists:", mainFrame ~= nil)

        -- Create columns FIRST (wider left column)
        LOT:DebugPrint("Creating columns...")
        mainFrame.leftColumn = CreateColumn(mainFrame, LEFT_COLUMN_WIDTH, LEFT_COLUMN_X, "Instances")
        mainFrame.middleColumn = CreateColumn(mainFrame, 250, 435, "Characters")
        mainFrame.rightColumn = CreateColumn(mainFrame, 300, 695, "Character Details")
        LOT:DebugPrint("Columns created")

        -- Create tabs AFTER columns (tabs reference leftColumn)
        LOT:DebugPrint("Creating tabs...")
        mainFrame.tabs = CreateTabs(mainFrame)
        LOT:DebugPrint("Tabs created")

        -- Restore position and size
        if LockoutTrackerDB.framePos then
            local pos = LockoutTrackerDB.framePos
            if pos.width and pos.height then
                -- Calculate scale before setting size
                currentScale = pos.width / DEFAULT_FRAME_WIDTH
                STYLE = GetScaledStyle()
                mainFrame:SetSize(pos.width, pos.height)
                LOT:DebugPrint("Size restored:", pos.width, pos.height, "scale:", currentScale)
            end
            mainFrame:ClearAllPoints()
            mainFrame:SetPoint(pos.point or "CENTER", UIParent, pos.point or "CENTER", pos.x or 0, pos.y or 0)
            LOT:DebugPrint("Position restored")
        end
    end

    LOT:DebugPrint("Checking if frame is shown:", mainFrame:IsShown())
    if mainFrame:IsShown() then
        LOT:DebugPrint("Frame is shown, hiding it")
        mainFrame:Hide()
    else
        LOT:DebugPrint("Frame is not shown, preparing to show it")
        -- Reset state
        activeTab = "instances"
        selectedInstance = nil
        selectedCharacter = nil
        -- Load saved filter value
        levelFilter = LockoutTrackerDB.levelFilter or ""
        -- Set filter UI to saved value
        if mainFrame.filterFrame then
            mainFrame.filterFrame.filterInput:SetText(levelFilter)
            if levelFilter ~= "" then
                mainFrame.filterFrame.clearButton:Show()
            else
                mainFrame.filterFrame.clearButton:Hide()
            end
        end
        -- Update tab appearance to match reset state
        if updateTabAppearance then
            updateTabAppearance()
        end
        -- Adjust column sizes for initial tab
        AdjustColumnSizes()
        LOT:DebugPrint("Calling mainFrame:Show()")
        mainFrame:Show()
        LOT:DebugPrint("mainFrame:Show() completed, isShown:", mainFrame:IsShown())
        LOT:DebugPrint("Calling RefreshUI()")
        RefreshUI()
        LOT:DebugPrint("RefreshUI() completed")
    end
end

-- Global function for keybinding
function LockoutTracker_ToggleUI()
    LOT:ToggleUI()
end
