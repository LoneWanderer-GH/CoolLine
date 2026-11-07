local ElvUI = _G.ElvUI
if not ElvUI then
    return
end

local addonName = ...
local CoolLineApp = LibStub("AceAddon-3.0"):GetAddon(addonName)
local CoolLine = CoolLineApp.MainFrame
local E, L = unpack(ElvUI)
if not E or type(E.CreateMover) ~= "function" or type(E.NewModule) ~= "function" then
    CoolLineApp:Print("ElvUI is missing the API required to create the CoolLine mover.")
    return
end

local module = E:NewModule("CoolLineMover", "AceEvent-3.0")
local moverName = "CoolLineMover"
local plugin = LibStub("LibElvUIPlugin-1.0", true)
local smed = LibStub("LibSharedMedia-3.0")

function module:ApplyElvUIMedia()
    local db = CoolLine.db
    local general = E.db and E.db.general
    local privateGeneral = E.private and E.private.general
    if not db then
        return
    end

    local changed
    local statusbar = privateGeneral and privateGeneral.normTex
    if db.statusbar == "Blizzard" and statusbar and smed:IsValid("statusbar", statusbar) then
        db.statusbar = statusbar
        changed = true
    end

    local border = "ElvUI GlowBorder"
    if db.border == "Blizzard Dialog" and smed:IsValid("border", border) then
        db.border = border
        changed = true
    end

    local font = general and general.font
    if db.font == "Friz Quadrata TT" and font and smed:IsValid("font", font) then
        db.font = font
        changed = true
    end

    if changed and CoolLine.updatelook then
        CoolLine.updatelook()
    end
end

function module:InsertOptions()
    if not CoolLine.OptionsTable or not E.Options or not E.Options.args then
        return
    end

    E.Options.args.ElvUI_CoolLine = {
        order = 1000,
        type = "group",
        name = "CoolLine",
        args = CoolLine.OptionsTable.args,
    }
end

function CoolLine:UpdateElvUIOptions()
    module:InsertOptions()
end

function CoolLine:SyncElvUIMover()
    local holder = E.CreatedMovers and E.CreatedMovers[moverName]
    if not holder then
        return
    end

    if E.SetMoverPoints then
        E:SetMoverPoints(moverName, self)
    end
    if holder.mover then
        holder.mover:SetSize(self:GetSize())
    end
end

function module:CreateMover()
    self:ApplyElvUIMedia()

    if E.CreatedMovers[moverName] then
        CoolLine.ElvUIMoverCreated = true
        CoolLine:SetMovable(false)
        CoolLine:SyncElvUIMover()
        return
    end

    if not CoolLine:GetPoint() then
        local db = CoolLine.db or {}
        CoolLine:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or -240)
    end

    CoolLine:SetMovable(false)
    E:CreateMover(
        CoolLine,
        moverName,
        L["CoolLine"] or "CoolLine",
        nil,
        nil,
        nil,
        "ALL,SOLO,ACTIONSBARS,PARTY,ARENA,RAID"
    )
    CoolLine.ElvUIMoverCreated = true
end

function module:PLAYER_ENTERING_WORLD()
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    self:CreateMover()
end

if plugin then
    plugin:RegisterPlugin(addonName, function()
        module:InsertOptions()
    end)
else
    CoolLineApp:Print("ElvUI's plugin library is unavailable; the CoolLine mover will work without its options entry.")
end

module:RegisterEvent("PLAYER_ENTERING_WORLD")

if IsLoggedIn() then
    C_Timer.After(0, function()
        module:CreateMover()
    end)
end
