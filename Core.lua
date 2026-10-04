-- LockoutTracker - Track raid/dungeon lockouts
local addonName = ...

-- Create addon namespace
LockoutTracker = {}
local LOT = LockoutTracker

-- Keybinding display names
BINDING_HEADER_LOCKOUTTRACKER = "Lockout Tracker"
BINDING_NAME_LOCKOUTTRACKER_TOGGLE = "LockoutTracker Window"

-- Debug mode (will be loaded from saved variables)
local DEBUG = false
local function DebugPrint(...)
    if DEBUG then
        print("|cff00ff00[LockoutTracker]|r", ...)
    end
end

-- Expose debug function for UI.lua
function LOT:DebugPrint(...)
    DebugPrint(...)
end

-- Expose debug flag setter
function LOT:SetDebug(enabled)
    DEBUG = enabled
end

-- Defaults
local defaults = {
    characters = {},
    framePos = {
        point = "CENTER",
        x = 0,
        y = 0
    },
    debugMode = false,
    levelFilter = ""
}

-- Difficulty names for display
local DIFFICULTY_NAMES = {
    [1] = "Normal",
    [2] = "Heroic",
    [3] = "10 Player",
    [4] = "25 Player",
    [5] = "10 Player (Heroic)",
    [6] = "25 Player (Heroic)",
    [7] = "LFR",
    [14] = "Normal",
    [15] = "Heroic",
    [16] = "Mythic",
    [17] = "LFR",
    [23] = "Mythic",
    [33] = "Timewalking"
}

-- Initialize database
local function InitDB()
    if not LockoutTrackerDB then
        LockoutTrackerDB = CopyTable(defaults)
    end

    -- Ensure structure exists
    LockoutTrackerDB.characters = LockoutTrackerDB.characters or {}
    LockoutTrackerDB.framePos = LockoutTrackerDB.framePos or CopyTable(defaults.framePos)
    LockoutTrackerDB.debugMode = LockoutTrackerDB.debugMode ~= nil and LockoutTrackerDB.debugMode or defaults.debugMode
    LockoutTrackerDB.levelFilter = LockoutTrackerDB.levelFilter or defaults.levelFilter

    -- Load debug state from saved variables
    DEBUG = LockoutTrackerDB.debugMode

    -- Now we can use debug prints
    DebugPrint("InitDB called")
    if LockoutTrackerDB.debugMode then
        DebugPrint("Loaded existing database")
    end
end

-- Get current character key
local function GetCharacterKey()
    local name = UnitName("player")
    local realm = GetRealmName()
    local faction = UnitFactionGroup("player") or "Neutral" -- "Horde" or "Alliance"
    return name .. "-" .. realm .. "-" .. faction
end

-- Expose for UI.lua
function LOT:GetCharacterKey()
    return GetCharacterKey()
end

-- Get character name and realm (stored fields; realm names can contain dashes)
function LOT:GetCharacterNameRealm(charKey)
    local char = LockoutTrackerDB.characters[charKey]
    local name = char and char.name or charKey:match("^([^-]+)")
    local realm = char and char.realm or charKey:match("^[^-]+-(.+)-[^-]+$")
    return name, realm
end

-- Get character display name (short form if unique, otherwise show realm)
function LOT:GetCharacterDisplayName(charKey)
    local name, realm = LOT:GetCharacterNameRealm(charKey)

    -- Check if name is unique across all characters
    local count = 0
    for key in pairs(LockoutTrackerDB.characters) do
        if LOT:GetCharacterNameRealm(key) == name then
            count = count + 1
        end
    end

    if count == 1 then
        return name
    else
        -- Show abbreviated realm
        return name .. "-" .. (realm or ""):sub(1, 4)
    end
end

-- Cleanup expired lockouts from all characters
local function CleanupExpiredLockouts()
    DebugPrint("CleanupExpiredLockouts called")
    local currentTime = time()
    local cleanedCount = 0

    for charKey, char in pairs(LockoutTrackerDB.characters) do
        local charCleanedCount = 0

        -- Cleanup regular instance lockouts
        if char.instances then
            for instanceKey, data in pairs(char.instances) do
                if data.expires and data.expires <= currentTime then
                    DebugPrint("  Removing expired instance:", charKey, instanceKey, "expired", currentTime - data.expires, "seconds ago")
                    char.instances[instanceKey] = nil
                    cleanedCount = cleanedCount + 1
                    charCleanedCount = charCleanedCount + 1
                end
            end
        end

        if charCleanedCount > 0 then
            DebugPrint("Cleaned", charCleanedCount, "expired lockouts from", charKey)
        end
    end

    if cleanedCount > 0 then
        DebugPrint("Total cleaned:", cleanedCount, "instances")
    else
        DebugPrint("No expired lockouts to clean")
    end
end

-- Initialize current character
local function InitCharacter()
    local key = GetCharacterKey()
    local name = UnitName("player")
    local _, class = UnitClass("player")
    local level = UnitLevel("player")
    local realm = GetRealmName()
    local faction = UnitFactionGroup("player") or "Neutral"

    DebugPrint("InitCharacter:", key, class, level, faction)

    if not LockoutTrackerDB.characters[key] then
        DebugPrint("Creating new character entry")
        LockoutTrackerDB.characters[key] = {
            name = name,
            class = class,
            level = level,
            realm = realm,
            faction = faction,
            instances = {}
        }
    else
        DebugPrint("Updating existing character")
        -- Update info
        LockoutTrackerDB.characters[key].name = name
        LockoutTrackerDB.characters[key].class = class
        LockoutTrackerDB.characters[key].level = level
        LockoutTrackerDB.characters[key].realm = realm
        LockoutTrackerDB.characters[key].faction = faction
    end
end

-- Update raid/dungeon lockouts
local function UpdateLockouts()
    DebugPrint("UpdateLockouts called")
    local key = GetCharacterKey()
    local char = LockoutTrackerDB.characters[key]
    if not char then
        DebugPrint("No character data found for", key)
        return
    end

    local currentTime = time()

    -- Clear expired lockouts first
    for instanceKey, data in pairs(char.instances) do
        if data.expires and data.expires < currentTime then
            DebugPrint("Clearing expired lockout:", instanceKey)
            char.instances[instanceKey] = nil
        end
    end

    -- Get saved instances (data requested via RequestRaidInfo, arrives with UPDATE_INSTANCE_INFO)
    local numSaved = GetNumSavedInstances()
    DebugPrint("Found", numSaved, "saved instances")

    for i = 1, numSaved do
        local name, id, reset, difficulty, locked, extended,
              instanceIDMostSig, isRaid, maxPlayers, difficultyName,
              numEncounters, encounterProgress = GetSavedInstanceInfo(i)

        DebugPrint("Instance", i, ":", name, "locked:", tostring(locked), "difficulty:", tostring(difficulty))
        DebugPrint("  encounterProgress:", tostring(encounterProgress), "numEncounters:", tostring(numEncounters))

        if locked and name then
            DebugPrint("  -> Saving this lockout")

            local success, err = pcall(function()
                -- Handle encounterProgress - can be a number (Midnight) or string (older versions)
                local killed = 0
                local progressStr = nil

                if encounterProgress then
                    if type(encounterProgress) == "number" then
                        -- Midnight API: encounterProgress is a number
                        killed = encounterProgress
                        if numEncounters and numEncounters > 0 then
                            progressStr = killed .. "/" .. numEncounters
                        else
                            progressStr = tostring(killed)
                        end
                    elseif type(encounterProgress) == "string" then
                        -- Older API: encounterProgress is a string like "3/8"
                        killed = tonumber(encounterProgress:match("^(%d+)")) or 0
                        progressStr = encounterProgress
                    end
                end

                local expires = currentTime + reset

                -- Ensure instances table exists
                char.instances = char.instances or {}

                -- Create unique key combining name and difficulty
                local instanceKey = name .. ":" .. (difficulty or 0)

                -- Store lockout with unique key
                char.instances[instanceKey] = {
                    name = name, -- Store the base name for reference
                    difficulty = difficulty,
                    difficultyName = difficultyName or DIFFICULTY_NAMES[difficulty] or "Unknown",
                    size = maxPlayers,
                    expires = expires,
                    bossesKilled = killed, -- Keep for backward compatibility
                    bossProgress = progressStr, -- Full progress string like "3/7"
                    isRaid = isRaid
                }

                DebugPrint("  -> Stored bossProgress:", tostring(progressStr), "bossesKilled:", tostring(killed))
            end)

            if success then
                DebugPrint("  -> Stored lockout:", name, "expires in", reset, "seconds")
            else
                DebugPrint("  -> ERROR storing lockout:", err)
            end
        elseif not locked then
            DebugPrint("  -> Skipped: not locked")
        elseif not name then
            DebugPrint("  -> Skipped: no name")
        end
    end

    -- Count stored instances
    local storedCount = 0
    for _ in pairs(char.instances) do storedCount = storedCount + 1 end
    DebugPrint("Total instances stored for this character:", storedCount)
end


-- Event frame
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("UPDATE_INSTANCE_INFO")
frame:RegisterEvent("BOSS_KILL")
frame:RegisterEvent("ENCOUNTER_END")

frame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        DebugPrint("Addon loading...")
        InitDB()
    elseif event == "PLAYER_LOGIN" then
        DebugPrint("Player login - initializing character")
        CleanupExpiredLockouts()
        InitCharacter()
        UpdateLockouts()
        RequestRaidInfo()
    elseif event == "PLAYER_ENTERING_WORLD" then
        DebugPrint("Entering world - requesting raid info")
        RequestRaidInfo()
    elseif event == "UPDATE_INSTANCE_INFO" then
        DebugPrint("Instance info updated")
        UpdateLockouts()
        if LOT.RefreshUI then
            LOT:RefreshUI()
        end
    elseif event == "BOSS_KILL" or event == "ENCOUNTER_END" then
        DebugPrint("Boss kill/encounter end - requesting raid info")
        -- Lockout is saved by the server shortly after the kill
        C_Timer.After(2, RequestRaidInfo)
    end
end)

-- Slash commands
SLASH_LOCKOUTTRACKER1 = "/lt"
SLASH_LOCKOUTTRACKER2 = "/lockouttracker"
SlashCmdList["LOCKOUTTRACKER"] = function(msg)
    local cmd = strtrim(msg:lower())

    if cmd == "debug" then
        DEBUG = not DEBUG
        LockoutTrackerDB.debugMode = DEBUG -- Save to saved variables
        print("|cff00ff00LockoutTracker|r Debug mode:", DEBUG and "|cff00ff00ON|r" or "|cffff0000OFF|r")
    elseif cmd == "reset" then
        -- Reset frame position and size to defaults
        LockoutTrackerDB.framePos = {
            point = "CENTER",
            x = 0,
            y = 0,
            width = nil,
            height = nil
        }
        print("|cff00ff00LockoutTracker|r Window position and size reset to default.")
        -- Close and destroy the frame so it gets recreated with defaults
        if LOT.ResetUI then
            LOT:ResetUI()
        end
    elseif cmd == "char" then
        -- Update current character data first
        UpdateLockouts()

        -- List all active lockouts for current character
        local key = GetCharacterKey()
        local char = LockoutTrackerDB.characters[key]
        if not char then
            print("|cff00ff00LockoutTracker|r No data found for current character.")
            return
        end

        local currentTime = time()
        local lockoutCount = 0
        local lockoutLines = {}

        -- Collect regular instance lockouts
        for instanceKey, data in pairs(char.instances) do
            if data.expires and data.expires > currentTime then
                local timeLeft = LOT:FormatTimeRemaining(data.expires)
                local progress = data.bossProgress or (data.bossesKilled or "?")
                table.insert(lockoutLines, "  " .. (data.name or instanceKey) .. " (" .. (data.difficultyName or "?") .. ") - " .. progress .. " - " .. timeLeft)
                lockoutCount = lockoutCount + 1
            end
        end

        -- Print header with count
        if lockoutCount > 0 then
            print("|cff00ff00LockoutTracker|r Active lockouts for " .. UnitName("player") .. ": " .. lockoutCount)
            for _, line in ipairs(lockoutLines) do
                print(line)
            end
        else
            print("|cff00ff00LockoutTracker|r Active lockouts for " .. UnitName("player") .. " - No active lockouts")
        end
    elseif LOT.ToggleUI then
        DebugPrint("Opening UI")
        LOT:ToggleUI()
    else
        DebugPrint("ERROR: ToggleUI function not found!")
    end
end

-- Utility: Format time remaining
function LOT:FormatTimeRemaining(expires)
    local remaining = expires - time()
    if remaining <= 0 then
        return "Expired"
    end

    local days = math.floor(remaining / 86400)
    local hours = math.floor((remaining % 86400) / 3600)

    if days > 0 then
        return string.format("%dd %dh", days, hours)
    else
        return string.format("%dh", hours)
    end
end

-- Get all instances with active lockouts
function LOT:GetActiveInstances()
    DebugPrint("GetActiveInstances called")
    local instances = {}
    local currentTime = time()

    -- Collect all unique instance names + difficulty from all characters
    for charKey, char in pairs(LockoutTrackerDB.characters) do
        DebugPrint("Checking character:", charKey)
        local count = 0
        for instanceKey, data in pairs(char.instances) do
            count = count + 1
            DebugPrint("  Found instance:", instanceKey, "expires:", data.expires, "current:", currentTime)
            if data.expires and data.expires > currentTime then
                -- instanceKey is already "name:difficulty" format
                if not instances[instanceKey] then
                    instances[instanceKey] = {
                        name = data.name or instanceKey:match("^([^:]+)"), -- Use stored name or extract from key
                        difficulty = data.difficulty,
                        difficultyName = data.difficultyName,
                        characters = {},
                        earliestExpiry = data.expires
                    }
                end

                table.insert(instances[instanceKey].characters, charKey)

                -- Track earliest expiry for this instance
                if data.expires < instances[instanceKey].earliestExpiry then
                    instances[instanceKey].earliestExpiry = data.expires
                end
            end
        end
        DebugPrint("  Total instances for this char:", count)
    end

    local totalInstances = 0
    for _ in pairs(instances) do totalInstances = totalInstances + 1 end
    DebugPrint("GetActiveInstances returning", totalInstances, "instances")

    return instances
end

