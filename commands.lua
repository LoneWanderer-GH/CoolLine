local addonName = ...
local CoolLineApp = LibStub("AceAddon-3.0"):GetAddon(addonName)
local CoolLine = CoolLineApp.MainFrame

local function Color(text, color)
    return "|cff" .. color .. text .. "|r"
end

local function ShowOptions(input)
    input = type(input) == "string" and input:match("^%s*(.-)%s*$") or ""
    if input == "" or input == "menu" or input == "options" then
        CoolLine:OpenOptions()
    elseif input == "help" or input == "h" then
        local title = Color("CoolLine", "22b14c")
        local command = Color("/cl", "00b3ff")
        local option = Color("unlock|move|resize|lock|toggle", "ffd100")
        print(title .. ": " .. command .. " opens options.")
        print(command .. " " .. option .. " controls moving/resizing; " .. command
            .. " <spell or item> toggles its blacklist entry.")
        print(Color("Report compatibility issues: ", "bbbbbb")
            .. Color("https://github.com/LoneWanderer-GH/CoolLine/issues", "00b3ff"))
    elseif input == "unlock" or input == "move" or input == "resize" then
        CoolLine:SetUnlocked(true)
        if CoolLine:IsAddonLoadedCompat("ElvUI_CoolLine_Wrapper") then
            print("CoolLine: unlocked for resizing; use ElvUI's mover to reposition it.")
        else
            print("CoolLine: unlocked; drag to move and drag the lower-right corner to resize.")
        end
    elseif input == "lock" then
        CoolLine:SetUnlocked(false)
        print("CoolLine: locked.")
    elseif input == "toggle" then
        CoolLine:ToggleUnlock()
        print(CoolLine.unlock and "CoolLine: unlocked." or "CoolLine: locked.")
    elseif input == "list" or input == "l" then
        print("CoolLine: blacklisted cooldowns:")
        for name in pairs(CoolLine.db.block) do
            print("  " .. tostring(name))
        end
    else
        local linkName = input:match("|h%[(.+)%]|h")
        input = linkName or input
        local blocked = not CoolLine.db.block[input]
        CoolLine:SetBlockedFilter(input, blocked)
        print("CoolLine: " .. input .. (blocked and " added to" or " removed from") .. " the blacklist.")
    end
end

CONFIGMODE_CALLBACKS = CONFIGMODE_CALLBACKS or {}
CONFIGMODE_CALLBACKS.CoolLine = function(action)
    if action == "ON" then
        CoolLine:OpenOptions()
        CoolLine:SetUnlocked(true)
    elseif action == "OFF" then
        CoolLine:SetUnlocked(false)
    end
end

CoolLineApp:RegisterChatCommand("coolline", ShowOptions)
CoolLineApp:RegisterChatCommand("cl", ShowOptions)
