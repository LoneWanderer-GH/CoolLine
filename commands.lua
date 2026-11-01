local addonName = ...
local CoolLineApp = LibStub("AceAddon-3.0"):GetAddon(addonName)
local CoolLine = CoolLineApp.MainFrame

local function ShowOptions(input)
    input = type(input) == "string" and input:match("^%s*(.-)%s*$") or ""
    if input == "" or input == "menu" or input == "options" then
        CoolLine:OpenOptions()
    elseif input == "help" or input == "h" then
        print("CoolLine: /coolline opens options; /coolline <spell or item> toggles its blacklist entry.")
        print("Report compatibility issues: https://github.com/LoneWanderer-GH/CoolLine/issues")
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
        if not CoolLine.unlock then
            CoolLine:ToggleUnlock()
        end
    elseif action == "OFF" and CoolLine.unlock then
        CoolLine:ToggleUnlock()
    end
end

CoolLineApp:RegisterChatCommand("coolline", ShowOptions)
CoolLineApp:RegisterChatCommand("cl", ShowOptions)
