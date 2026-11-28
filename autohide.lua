-- Auto-hide: hides the bar while the player is carried along a flight path (taxi) and, optionally, while
-- mounted or flying. This file only decides CoolLine.autoHidden; core.lua's UpdateTimelineFrameVisibility
-- applies it together with the other reasons to hide the bar.
local addonName = ...
local CoolLine = LibStub("AceAddon-3.0"):GetAddon(addonName).MainFrame

local _G = _G
local GetTime = GetTime

local POLL_INTERVAL_S = 0.5
-- The game's flag can lag behind PLAYER_CONTROL_* and PLAYER_ENTERING_WORLD, so keep polling for a moment.
local SETTLE_S = 2

local KEYS = { "hideOnTaxi", "hideMounted", "hideFlying" }
-- There is no taxi or flying event: the game only signals losing/regaining control, mount, form and glide
-- changes. The taxi flag itself is set and cleared with a unit-flags update (UNIT_FLAGS, registered for the
-- player below), which can trail PLAYER_CONTROL_LOST at takeoff: EllesmereUI and DaylightUI both look again
-- shortly after. Events that a client does not know are skipped.
local EVENTS = {
    "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
    "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED",
    "PLAYER_MOUNT_DISPLAY_CHANGED", "UPDATE_SHAPESHIFT_FORM",
    "PLAYER_IS_GLIDING_CHANGED", "PLAYER_CAN_GLIDE_CHANGED",
}

local AVAILABLE = {
    hideOnTaxi = function()
        return type(_G.UnitOnTaxi) == "function"
    end,
    hideMounted = function()
        return type(_G.IsMounted) == "function"
    end,
    -- Classic Era has neither flying mounts nor flight forms.
    hideFlying = function()
        local classicEra = _G.WOW_PROJECT_CLASSIC ~= nil and _G.WOW_PROJECT_ID == _G.WOW_PROJECT_CLASSIC
        return type(_G.IsFlying) == "function" and not classicEra
    end,
}

function CoolLine:IsAutoHideAvailable(key)
    local available = AVAILABLE[key]
    return available ~= nil and available()
end

local function IsEnabled(key)
    local db = CoolLine.db
    return db ~= nil and db[key] == true and CoolLine:IsAutoHideAvailable(key)
end

-- The booleans below are documented as never secret; a secret value is still treated as "no" instead of tested.
local function ReadFlag(fn, ...)
    if type(fn) ~= "function" then
        return false
    end
    local value = fn(...)
    if CoolLine:IsSecretValueCompat(value) then
        return false
    end
    return value and true or false
end

-- Dynamic flight (skyriding) glides: only clients that have the API report it.
local function IsGliding()
    local playerInfo = _G.C_PlayerInfo
    if not (playerInfo and playerInfo.GetGlidingInfo) then
        return false
    end
    return ReadFlag(playerInfo.GetGlidingInfo)
end

local aux = CreateFrame("Frame")
local registered, inCombat, settleUntil, polled = false, false, 0, 0

-- Taxi hides the bar even in combat (the player cannot act); the other modes never hide it in combat, so the
-- cooldowns stay visible when the player has to land and fight.
local function ComputeHidden()
    if CoolLine.unlock then
        return false
    end
    if IsEnabled("hideOnTaxi") and ReadFlag(_G.UnitOnTaxi, "player") then
        return true
    end
    if inCombat then
        return false
    end
    if IsEnabled("hideMounted") and ReadFlag(_G.IsMounted) then
        return true
    end
    return IsEnabled("hideFlying") and (ReadFlag(_G.IsFlying) or IsGliding()) or false
end

local function Evaluate()
    if not CoolLine.db then
        return
    end
    local hidden = ComputeHidden()
    if hidden ~= (CoolLine.autoHidden or false) then
        CoolLine.autoHidden = hidden
        CoolLine:UpdateTimelineFrameVisibility()
    end
    -- Poll where no event exists (flying) or where the end of the state may be missed (a hidden bar).
    if hidden or IsEnabled("hideFlying") or GetTime() < settleUntil then
        aux:Show()
    else
        aux:Hide()
    end
end

aux:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
    elseif event == "PLAYER_CONTROL_LOST" or event == "PLAYER_CONTROL_GAINED"
        or event == "PLAYER_ENTERING_WORLD" then
        settleUntil = GetTime() + SETTLE_S
    end
    Evaluate()
end)

aux:SetScript("OnUpdate", function(_, elapsed)
    polled = polled + elapsed
    if polled < POLL_INTERVAL_S then
        return
    end
    polled = 0
    Evaluate()
end)
aux:Hide()

-- Applies the saved options: registers the events only while an auto-hide option is on, then re-evaluates.
function CoolLine:UpdateAutoHide()
    if not self.db then
        return
    end
    local anyEnabled = false
    for _, key in ipairs(KEYS) do
        if IsEnabled(key) then
            anyEnabled = true
            break
        end
    end

    if anyEnabled and not registered then
        registered = true
        inCombat = _G.InCombatLockdown and _G.InCombatLockdown() or false
        for _, event in ipairs(EVENTS) do
            pcall(aux.RegisterEvent, aux, event)
        end
        pcall(aux.RegisterUnitEvent, aux, "UNIT_FLAGS", "player")
    elseif not anyEnabled and registered then
        registered = false
        aux:UnregisterAllEvents()
    end

    if anyEnabled then
        Evaluate()
    else
        aux:Hide()
        if self.autoHidden then
            self.autoHidden = false
            self:UpdateTimelineFrameVisibility()
        end
    end
end
