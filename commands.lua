local addonName = ...
local CoolLineApp = LibStub("AceAddon-3.0"):GetAddon(addonName)
local CoolLine = CoolLineApp.MainFrame

local configPreviews = {
    { duration = 5, icon = "Interface\\Icons\\Spell_Frost_FrostBolt02" },
    { duration = 30, icon = "Interface\\Icons\\Spell_Nature_Rejuvenation" },
    { duration = 120, icon = "Interface\\Icons\\Ability_Warrior_Charge" },
    { duration = 300, icon = "Interface\\Icons\\Spell_Holy_BorrowedTime" },
}
local configPreviewsActive = false
local configPreviewTicker = CreateFrame("Frame")
local configPreviewElapsed = 0

local function Color(text, color)
    return "|cff" .. color .. text .. "|r"
end

local function AddConfigPreview(preview)
    CoolLine.NewCooldownClassic(
        "CoolLine Preview " .. preview.duration .. "s",
        preview.icon,
        GetTime() + preview.duration,
        true,
        nil,
        "config"
    )
end

function CoolLine:SetConfigPreviews(enabled)
    if configPreviewsActive == enabled then
        return
    end
    configPreviewsActive = enabled

    if enabled then
        for _, preview in ipairs(configPreviews) do
            AddConfigPreview(preview)
        end
        configPreviewElapsed = 0
        configPreviewTicker:SetScript("OnUpdate", function(_, elapsed)
            configPreviewElapsed = configPreviewElapsed + elapsed
            if configPreviewElapsed < 1 then
                return
            end
            configPreviewElapsed = 0

            local now = GetTime()
            for _, preview in ipairs(configPreviews) do
                local name = "CoolLine Preview " .. preview.duration .. "s"
                local active
                for _, frame in ipairs(CoolLine.cooldowns) do
                    if frame.name == name and frame.source == "config" then
                        active = frame.endtime and frame.endtime - now > 1
                        break
                    end
                end
                if not active then
                    AddConfigPreview(preview)
                end
            end
        end)
    else
        configPreviewTicker:SetScript("OnUpdate", nil)
        for _, preview in ipairs(configPreviews) do
            self.ClearCooldown(
                nil,
                "CoolLine Preview " .. preview.duration .. "s",
                "config"
            )
        end
        self.RefreshCooldownDisplay()
    end
end

local function ShowOptions(input)
    input = type(input) == "string" and input:match("^%s*(.-)%s*$") or ""
    if input == "" or input == "menu" or input == "options" then
        CoolLine:OpenOptions()
    elseif input == "help" or input == "h" then
        local command = Color("/cl", "00b3ff")
        local option = Color("unlock||move||resize||lock||toggle||debug", "ffd100")
        CoolLineApp:Print(command .. " opens options.")
        CoolLineApp:Print(command .. " " .. option .. " controls moving/resizing; " .. command
            .. " debug toggles cooldown diagnostics; " .. command
            .. " <spell or item> toggles its blacklist entry.")
        CoolLineApp:Print(Color("Report compatibility issues: ", "bbbbbb")
            .. Color("https://github.com/LoneWanderer-GH/CoolLine/issues", "00b3ff"))
    elseif input == "unlock" or input == "move" or input == "resize" then
        CoolLine:SetUnlocked(true)
        if CoolLine.canDrag and CoolLine.canResize then
            CoolLineApp:Print("Unlocked; drag to move and use the lower-right corner to resize.")
        elseif CoolLine.canDrag then
            CoolLineApp:Print("Unlocked for dragging; resizing is not supported by this client.")
        elseif CoolLine.canResize and CoolLine:IsAddonLoadedCompat("ElvUI_CoolLine_Wrapper") then
            CoolLineApp:Print("Unlocked for resizing; use ElvUI's mover to reposition it.")
        elseif CoolLine.canResize then
            CoolLineApp:Print("Unlocked for resizing; dragging is not supported by this client.")
        elseif CoolLine:IsAddonLoadedCompat("ElvUI_CoolLine_Wrapper") then
            CoolLineApp:Print("Use ElvUI's mover to reposition it; resizing is not supported by this client.")
        else
            CoolLineApp:Print("This client does not expose the APIs needed to move or resize the frame.")
        end
    elseif input == "lock" then
        CoolLine:SetUnlocked(false)
        CoolLineApp:Print("Locked.")
    elseif input == "toggle" then
        CoolLine:ToggleUnlock()
        CoolLineApp:Print(CoolLine.unlock and "Unlocked." or "Locked.")
    elseif input == "debug" then
        CoolLine.cooldownDebugEnabled = not CoolLine.cooldownDebugEnabled
        CoolLine.cooldownDebugMessages = {}
        --@debug@
        CoolLineApp:SetCooldownDebugEnabled(CoolLine.cooldownDebugEnabled)
        --@end-debug@
        CoolLineApp:Print(CoolLine.cooldownDebugEnabled
            and "CoolLine: cooldown diagnostics enabled; rescanning the spellbook."
            or "CoolLine: cooldown diagnostics disabled.")
        if CoolLine.cooldownDebugEnabled then
            CoolLine:SPELLS_CHANGED()
            CoolLine:SPELL_UPDATE_COOLDOWN()
        end
    elseif input == "list" or input == "l" then
        CoolLineApp:Print("Blacklisted cooldowns:")
        for name in pairs(CoolLine.db.block) do
            CoolLineApp:Print("  " .. tostring(name))
        end
    else
        local linkName = input:match("|h%[(.+)%]|h")
        input = linkName or input
        local blocked = not CoolLine.db.block[input]
        CoolLine:SetBlockedFilter(input, blocked)
        CoolLineApp:Print(input .. (blocked and " added to" or " removed from") .. " the blacklist.")
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
