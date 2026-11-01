local addonName, addonTable = ...
-- local CoolLine = LibStub("AceAddon-3.0"):NewAddon("CoolLine",
--                                                                              "AceConsole-3.0",
--                                                                              "AceEvent-3.0"
--                                                                              --@debug@
--                                                                              ,"LoggingLib-0.1"
--                                                                              --@end-debug@
-- )
-- --@debug@
-- local LoggingLib = LibStub("LoggingLib-0.1")
-- --@end-debug@

local ORANGEY, LIGHTRED                       = '|cffFF4500', '|cffff6060'
local version, build, date, build_toc_version = GetBuildInfo()
local major_version                           = floor(build_toc_version / 10000)
local IS_RETAIL_RELEASE                       = (WOW_PROJECT_ID and WOW_PROJECT_MAINLINE and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) or major_version >= 10

local MAX_SUPPORTED_VERSION_TABLE = {
    [WOW_PROJECT_MAINLINE]                = 120105,
    [WOW_PROJECT_CLASSIC]                 =  19999,
    -- provision [WOW_PROJECT_FOREVER]                 =  16001,
    -- provision [WOW_PROJECT_BURNING_CRUSADE_CLASSIC] =  20599,
    -- provision [WOW_PROJECT_WRATH_CLASSIC]           =  30405,
    -- provision [WOW_PROJECT_CATACLYSM_CLASSIC]       =  40402,
    -- provision [WOW_PROJECT_MISTS_CLASSIC]           =  50504,
}

local AddonBackdropTemplate = 42
if WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
    AddonBackdropTemplate = nil
else
    AddonBackdropTemplate = "BackdropTemplate"
end

local MAX_SUPPORTED_VERSION                   = MAX_SUPPORTED_VERSION_TABLE[WOW_PROJECT_ID]
local MAX_MAJOR_VERSION                       = floor(MAX_SUPPORTED_VERSION / 10000)

local CoolLine                                = CreateFrame("Frame", "CoolLine", UIParent)
CoolLine.MainFrame                            = CoolLine
if addonTable.CoolLine then
    for k, v in pairs(addonTable.CoolLine) do
        CoolLine[k] = v
    end
end
addonTable.CoolLine = CoolLine

CoolLine:SetScript("OnEvent", function(this, event, ...)
    this[event](this, ...)
end)

if build_toc_version > MAX_SUPPORTED_VERSION or (major_version < MAX_MAJOR_VERSION) then
    print(format("!!! %sBEWARE %s!!!!", LIGHTRED, "|r"))
    local coolline_version = "@project-version@"
    print(format("%sCoolLine v%s hasn't been updated to support WoW v |r%s - %sbuild|r %s- %sdate|r %s - %sversion number|r %s",
                 ORANGEY, coolline_version, version,
                 ORANGEY, build,
                 ORANGEY, date,
                 ORANGEY, build_toc_version))
    print(format("%sPlease file any bugs you find @ https://github.com/LoneWanderer-GH/CoolLine/issues", ORANGEY))
    print(format("%sPlease be precise and provide as much intel as needed (PTR realm, release, beta etc.)", ORANGEY))
    print(format("%sMax supported version is |r%s", ORANGEY, MAX_SUPPORTED_VERSION))
end

local smed                                                  = LibStub("LibSharedMedia-3.0")

local _G, pairs, strmatch, tinsert, tremove, random         = _G, pairs, string.match, table.insert, table.remove, math.random
local GetTime                                               = GetTime
local UnitExists, HasPetUI                                  = UnitExists, HasPetUI


local db, block
local backdrop                                              = { edgeSize = 16 } -- Left Unchanged
local section, iconsize                                     = 0, 0
local tick0, tick1, tick3, tick10, tick30, tick120, tick300
local spellBookBanks                                        = Enum and Enum.SpellBookSpellBank
local BOOKTYPE_SPELL                                        = BOOKTYPE_SPELL or (spellBookBanks and spellBookBanks.Player) or "spell"
local BOOKTYPE_PET                                          = BOOKTYPE_PET or (spellBookBanks and spellBookBanks.Pet) or "pet"
local spells                                                = { [BOOKTYPE_SPELL] = { }, [BOOKTYPE_PET] = { }, }
local chargespells                                          = { [BOOKTYPE_SPELL] = { }, [BOOKTYPE_PET] = { }, }
local frames, cooldowns, specialspells                      = { }, { }, { }

CoolLine.spells, CoolLine.chargespells                      = spells, chargespells
CoolLine.frames, CoolLine.cooldowns, CoolLine.specialspells = frames, cooldowns, specialspells

local NO_RELOCATE                                           = "NO_RELOCATE"
CoolLine.NO_RELOCATE                                        = NO_RELOCATE

local MINIMUM_COOLDOWN_DURATION_MS                          = 2499
local DEFAULT_RETAIL_GCD_DURATION_S                         = 1.5 -- 0.749
local DEFAULT_RETAIL_MAX_DURATION_S                         = 3601

local SetValue, updatelook, createfs, ShowOptions, RuneCheck
local SyncTimelineEvent, NativeTimelineEnabled, RefreshCooldownDisplay

local function SetValueH(this, v, just)
    this:SetPoint(just or "CENTER", CoolLine, "LEFT", v, 0)
end

local function SetValueHR(this, v, just)
    this:SetPoint(just or "CENTER", CoolLine, "LEFT", db.w - v, 0)
end

local function SetValueV(this, v, just)
    this:SetPoint(just or "CENTER", CoolLine, "BOTTOM", 0, v)
end

local function SetValueVR(this, v, just)
    this:SetPoint(just or "CENTER", CoolLine, "BOTTOM", 0, db.h - v)
end

--------------------------------
-- For 3rd party addons such as ElvUI
function CoolLine:SetConfig(w, h, x, y, font, fontsize, inactivealpha, activealpha, statusbar, updateOption)
    --------------------------------
    if db then
        db.w             = w or db.w
        db.h             = h or db.h
        -- db.x             = x         or db.x
        -- db.y             = y         or db.y
        db.font          = font or db.font
        db.fontsize      = fontsize or db.fontsize
        db.statusbar     = statusbar or db.statusbar
        db.activealpha   = activealpha or db.activealpha
        db.inactivealpha = inactivealpha or db.inactivealpha
    else
        -- ?
        print("CoolLine SetConfig called but no db loaded")
    end
    self.updatelook(updateOption)
end

function CoolLine:getConfig()
    return db.w, db.h, db.x, db.y, db.font, db.fontsize, db.inactivealpha, db.activealpha, db.statusbar
end

CoolLine:RegisterEvent("ADDON_LOADED")
function CoolLine:ADDON_LOADED(a1)
    if a1 ~= "CoolLine" then
        return
    end
    self:UnregisterEvent("ADDON_LOADED")
    self.ADDON_LOADED = nil

    CoolLineDB        = CoolLineDB or {}
    if CoolLineDB.perchar then
        CoolLineCharDB = CoolLineCharDB or CoolLineDB
        db             = CoolLineCharDB
    else
        CoolLineCharDB = nil
        db             = CoolLineDB
    end

    -- local hearthstoneName = GetItemInfo and GetItemInfo(6948)
    -- if not hearthstoneName and C_Item and C_Item.GetItemNameByID then
    --     hearthstoneName = C_Item.GetItemNameByID(6948)
    -- end
    local hearthstoneName = self:GetItemNameCompat(6948)

    if db.dbinit ~= 3 then
        db.dbinit = 3
        for k, v in pairs({
                              w             = 360, h = 18, x = 0, y = -240,
                              statusbar     = "Blizzard",
                              bgcolor       = { r = 0, g = 0, b = 0, a = 0.5, },
                              border        = "Blizzard Dialog",
                              bordersize    = 16, -- Added defaults
                              borderinset   = 4, -- Added defaults
                              bordercolor   = { r = 1, g = 1, b = 1, a = 1, },
                              font          = "Friz Quadrata TT",
                              fontsize      = 10,
                              iconplus      = 4,
                              fontcolor     = { r = 1, g = 1, b = 1, a = 0.8, },
                              spellcolor    = { r = 0.8, g = 0.4, b = 0, a = 1, },
                              nospellcolor  = { r = 0, g = 0, b = 0, a = 1, },
                              inactivealpha = 0.5,
                              activealpha   = 1.0,
                              block         = {  -- [spell or item name] = true,
                                  [hearthstoneName or "Hearthstone"] = true, -- Hearthstone
                              },
                          }) do
            db[k] = (db[k] ~= nil and db[k]) or v
        end
    end
    if db.blizzardTimeline == nil then
        db.blizzardTimeline = false
    end
    block          = db.block

    local _, class = UnitClass("player")
    if class == "DEATHKNIGHT" then
        local runecd = {  -- fix by NeoSyrex
            [self:GetSpellInfoCompat(50977) or "Death Gate"]       = 11,
            [self:GetSpellInfoCompat(43265) or "Death and Decay"]  = 11,
            [self:GetSpellInfoCompat(42650) or "Army of the Dead"] = 11,
            --			[self:GetSpellInfoCompat(47476) or "Strangulate"] = 11,
            --			[self:GetSpellInfoCompat(51052) or "Anti-Magic Zone"] = 11,
            --			[self:GetSpellInfoCompat(63560) or "Dark Transformation"] = 10,
            [self:GetSpellInfoCompat(49184) or "Howling Blast"]    = 8,
            --			[self:GetSpellInfoCompat(51271) or "Pillar of Frost"] = 11,
            --			[self:GetSpellInfoCompat(55233) or "Vampiric Blood"] = 11,
        }
        RuneCheck    = function(name, duration)
            local rc = runecd[name]
            if not rc or (rc <= duration and (rc > 10 or rc >= duration)) then
                return true
            end
        end
    elseif class == "PRIEST" then
        specialspells = {
            [self:GetSpellInfoCompat(81209) or "blah"] = 81209, -- Chakra: Chastise
            [self:GetSpellInfoCompat(88684) or "blah"] = 88684, -- Holy Word: Serenity
            [self:GetSpellInfoCompat(88685) or "blah"] = 88685, -- Holy Word: Sanctuary
            [self:GetSpellInfoCompat(88625) or "blah"] = 88625, -- Holy Word: Chastise
            [self:GetSpellInfoCompat(88625) or "blah"] = 88625, -- Holy Word: Chastise
        }
    end

    SlashCmdList.COOLLINE = ShowOptions
    SLASH_COOLLINE1       = "/coolline"
    SLASH_COOLLINE2       = "/cl"

    HELP_TEXT_FORMAT = {
        "Notes: %s\nAuthor: %s\nVersion: %s\n" ..
        "Hint: |cffffff00/coolline|r to open menu; |cffffff00/coolline SpellOrItemNameOrLink|r to add/remove filter\n"..
        "Hint: |cffffff00/coolline"..ORANGEY.." list |r lists filtered out spells/items",
        CoolLine:GetAddOnMetadataCompat("CoolLine", "Notes") or "N/A",
        CoolLine:GetAddOnMetadataCompat("CoolLine", "Author") or "N/A",
        CoolLine:GetAddOnMetadataCompat("CoolLine", "Version") or "N/A"}

    local panel           = CreateFrame("Frame")
    panel.name            = "CoolLine"
    panel:SetScript("OnShow", function(this)
        local t1 = this:CreateFontString(nil, "ARTWORK")
        t1:SetJustifyH("LEFT")
        t1:SetJustifyV("TOP")
        t1:SetFontObject(GameFontNormalLarge)
        t1:SetPoint("TOPLEFT", 16, -16)
        t1:SetText(this.name)

        local t2 = this:CreateFontString(nil, "ARTWORK")
        t2:SetJustifyH("LEFT")
        t2:SetJustifyV("TOP")
        t2:SetFontObject(GameFontHighlightSmall)
        t2:SetHeight(43)
        t2:SetPoint("TOPLEFT", t1, "BOTTOMLEFT", 0, -8)
        t2:SetPoint("RIGHT", this, "RIGHT", -32, 0)
        t2:SetNonSpaceWrap(true)
        t2:SetFormattedText(unpack(HELP_TEXT_FORMAT))

        local b = CreateFrame("Button", nil, this, "UIPanelButtonTemplate")
        b:SetWidth(120)
        b:SetHeight(20)
        b:SetText("Options Menu")
        b:SetScript("OnClick", ShowOptions)
        b:SetPoint("TOPLEFT", t2, "BOTTOMLEFT", -2, -8)
        this:SetScript("OnShow", nil)
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end

    createfs            = function(f, text, offset, just)
        local fs = f or self.overlay:CreateFontString(nil, "OVERLAY")
        fs:SetFont(smed:Fetch("font", db.font), db.fontsize)
        fs:SetTextColor(db.fontcolor.r, db.fontcolor.g, db.fontcolor.b, db.fontcolor.a)
        fs:SetText(text)
        fs:SetWidth(db.fontsize * 3)
        fs:SetHeight(db.fontsize + 2)
        fs:SetShadowColor(db.bgcolor.r, db.bgcolor.g, db.bgcolor.b, db.bgcolor.a)
        fs:SetShadowOffset(1, -1)

        if just then
            fs:ClearAllPoints()
            if db.vertical then
                fs:SetJustifyH("CENTER")
                just = db.reverse and ((just == "LEFT" and "TOP") or "BOTTOM") or ((just == "LEFT" and "BOTTOM") or "TOP")
            elseif db.reverse then
                just   = (just == "LEFT" and "RIGHT") or "LEFT"
                offset = offset + ((just == "LEFT" and 1) or -1)
                fs:SetJustifyH(just)
            else
                offset = offset + ((just == "LEFT" and 1) or -1)
                fs:SetJustifyH(just)
            end
        else
            fs:SetJustifyH("CENTER")
        end

        SetValue(fs, offset, just)
        return fs
    end

    updatelook          = function(option)
        self:SetWidth(db.w or 130)
        self:SetHeight(db.h or 18)

        if option ~= NO_RELOCATE then
            self:SetPoint("CENTER", UIParent, "CENTER", db.x or 0, db.y or -240)
        end

        self.bg = self.bg or self:CreateTexture(nil, "ARTWORK")
        self.bg:SetTexture(smed:Fetch("statusbar", db.statusbar))
        self.bg:SetVertexColor(db.bgcolor.r, db.bgcolor.g, db.bgcolor.b, db.bgcolor.a)
        self.bg:SetAllPoints(self)
        if db.vertical then
            self.bg:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
        else
            self.bg:SetTexCoord(0, 1, 0, 1)
        end

        self.border = self.border or CreateFrame("Frame", nil, self, AddonBackdropTemplate)
        self.border:SetPoint("TOPLEFT", -db.borderinset, db.borderinset) -- Implemented 'insets'
        self.border:SetPoint("BOTTOMRIGHT", db.borderinset, -db.borderinset) -- Implemented 'insets'

        backdrop = {
            edgeFile = smed:Fetch("border", db.border),
            edgeSize = db.bordersize,
        } -- Updated backdrop table
        self.border:SetBackdrop(backdrop)
        self.border:SetBackdropBorderColor(db.bordercolor.r, db.bordercolor.g, db.bordercolor.b, db.bordercolor.a)

        self.overlay = self.overlay or CreateFrame("Frame", nil, self.border)
        self.overlay:SetFrameLevel(24)
        --CoolLine.Overlay = self.overlay

        section  = (db.vertical and db.h or db.w) / 6
        iconsize = ((db.vertical and db.w) or db.h) + (db.iconplus or 4)
        SetValue = (db.vertical and (db.reverse and SetValueVR or SetValueV)) or (db.reverse and SetValueHR or SetValueH)

        tick0    = createfs(tick0, "0", 0, "LEFT")
        tick1    = createfs(tick1, "1", section)
        tick3    = createfs(tick3, "3", section * 2)
        tick10   = createfs(tick10, "10", section * 3)
        tick30   = createfs(tick30, "30", section * 4)
        tick120  = createfs(tick120, "2m", section * 5)
        tick300  = createfs(tick300, "6m", section * 6, "RIGHT")

        if not self.cb and (not smed:IsValid("font", db.font) or not smed:IsValid("border", db.border) or not smed:IsValid("statusbar", db.statusbar)) then
            smed.RegisterCallback(self, "LibSharedMedia_Registered", updatelook)
            self.cb = true
        end

        if db.hidepet then
            self:UnregisterEvent("UNIT_PET")
            self:UnregisterEvent("PET_BAR_UPDATE_COOLDOWN")
        else
            self:RegisterUnitEvent("UNIT_PET", "player")
            self:UNIT_PET()
        end

        if db.hidebag and db.hideinv then
            self:UnregisterEvent("BAG_UPDATE_COOLDOWN")
        else
            self:RegisterEvent("BAG_UPDATE_COOLDOWN")
            self:BAG_UPDATE_COOLDOWN()
        end

        if db.hidefail then
            self:UnregisterEvent("UNIT_SPELLCAST_FAILED")
        else
            self:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
        end

        CoolLine:SetAlpha((CoolLine.unlock or #cooldowns > 0) and db.activealpha or db.inactivealpha)

        for i = 1, #cooldowns do
            cooldowns[i]:SetSize(iconsize, iconsize)
            if SyncTimelineEvent then
                SyncTimelineEvent(cooldowns[i])
            end
        end
        if RefreshCooldownDisplay then
            RefreshCooldownDisplay()
        end
    end
    CoolLine.updatelook = updatelook

    if IsLoggedIn() then
        CoolLine:PLAYER_LOGIN()
    else
        self:RegisterEvent("PLAYER_LOGIN")
    end
end

--------------------------------
function CoolLine:PLAYER_LOGIN()
    --------------------------------
    self.PLAYER_LOGIN = nil
    self:RegisterEvent("SPELLS_CHANGED")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    self:RegisterEvent("SPELL_UPDATE_CHARGES")
    self.SPELL_UPDATE_CHARGES = self.SPELL_UPDATE_COOLDOWN
    self:SPELL_UPDATE_COOLDOWN()
    if C_EncounterTimeline and C_EncounterTimeline.IsFeatureAvailable then
        self:RegisterEvent("ENCOUNTER_TIMELINE_STATE_UPDATED")
    end

    --@version-retail@
    self:RegisterEvent("PET_BATTLE_OPENING_START")
    self:RegisterEvent("PET_BATTLE_CLOSE")
    self.PET_BATTLE_OPENING_START = self.Hide
    self.PET_BATTLE_CLOSE         = self.Show
    if C_PetBattles.IsInBattle() then
        self:Hide()
    end

    self:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
    if UnitHasVehicleUI("player") then
        self:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
        self:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    end
    --@end-version-retail@

    updatelook()
    self:SetAlpha((#cooldowns == 0 and db.inactivealpha) or db.activealpha)
    self:RegisterEvent("PLAYER_LEAVING_WORLD")
end

-----------------------------------------
function CoolLine:PLAYER_ENTERING_WORLD()
    -----------------------------------------
    self:RegisterEvent("SPELLS_CHANGED")
    self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
    self:SPELLS_CHANGED()
    self:SPELL_UPDATE_COOLDOWN()
end

----------------------------------------
function CoolLine:PLAYER_LEAVING_WORLD()
    ----------------------------------------
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:UnregisterEvent("SPELLS_CHANGED")
    self:UnregisterEvent("SPELL_UPDATE_COOLDOWN")
end

local iconback                        = { bgFile = "Interface\\AddOns\\CoolLine\\backdrop.tga" }
local elapsed, throt, ptime, isactive = 0, 1.5, 0, false

local function ClearCooldown(f, name)
    name = name or (f and f.name)
    for i = 1, #cooldowns do
        local frame = cooldowns[i]
        if frame.name == name then
            if SyncTimelineEvent then
                frame.spellID = nil
                SyncTimelineEvent(frame)
            end
            frame:Hide()
            frame.name    = nil
            frame.endtime = nil
            frame.remaining_duration = nil
            tinsert(frames, tremove(cooldowns, i))
            break
        end
    end
end

local function CancelTimelineEvent(frame)
    local timeline = C_EncounterTimeline
    if frame.timelineEventID and timeline and timeline.CancelScriptEvent then
        timeline.CancelScriptEvent(frame.timelineEventID)
    end
    frame.timelineEventID = nil
    frame.timelineEventEndTime = nil
    frame.timelineEventSpellID = nil
end

local NativeTimelineEnabled = function()
    local timeline = C_EncounterTimeline
    return db.blizzardTimeline and timeline and timeline.IsFeatureAvailable
        and timeline.IsFeatureAvailable() and timeline.IsFeatureEnabled and timeline.IsFeatureEnabled()
    and timeline.GetViewType and Enum and Enum.EncounterTimelineViewType
    and timeline.GetViewType() ~= Enum.EncounterTimelineViewType.None
end

local SyncTimelineEvent = function(frame)
    local timeline = C_EncounterTimeline
    local enabled = NativeTimelineEnabled() and frame.isplayer and frame.spellID
        and type(frame.iconTexture) == "number"
        and timeline.AddScriptEvent and timeline.CancelScriptEvent

    if not enabled then
        CancelTimelineEvent(frame)
        return
    end

    if frame.timelineEventID and frame.timelineEventEndTime == frame.endtime
        and frame.timelineEventSpellID == frame.spellID then
        return
    end

    CancelTimelineEvent(frame)

    local severity = Enum and Enum.EncounterEventSeverity and Enum.EncounterEventSeverity.Medium
    if not severity then
        return
    end

    local eventID = timeline.AddScriptEvent({
        spellID = frame.spellID,
        iconFileID = frame.iconTexture,
        duration = math.max(0, frame.endtime - GetTime()),
        maxQueueDuration = 0,
        overrideName = frame.name,
        severity = severity,
        paused = false,
    })

    if eventID and eventID ~= 0 then
        frame.timelineEventID = eventID
        frame.timelineEventEndTime = frame.endtime
        frame.timelineEventSpellID = frame.spellID
    end
end

local function SetupIcon(frame, position, tthrot, active, fl)
    throt    = (throt < tthrot and throt) or tthrot
    isactive = active or isactive
    if fl then
        frame:SetFrameLevel(random(1, 5) * 2 + 2)
    end
    SetValue(frame, position)
end

local function IsLegacyCooldown(frame)
    return not (frame.isplayer and frame.timelineEventID)
end

local function OnUpdate(this, a1, ctime, dofl)
    elapsed = elapsed + a1
    if elapsed < throt then
        return
    end
    elapsed = 0

    local hasLegacyCooldowns = false
    for _, frame in pairs(cooldowns) do
        if IsLegacyCooldown(frame) then
            hasLegacyCooldowns = true
            break
        end
    end

    if not hasLegacyCooldowns then
        CoolLine:SetScript("OnUpdate", nil)
        CoolLine:SetAlpha(CoolLine.unlock and db.activealpha or (NativeTimelineEnabled() and 0 or db.inactivealpha))
        return
    end

    ctime = ctime or GetTime()
    if ctime > ptime then
        dofl, ptime = true, ctime + 0.4
    end
    isactive, throt = false, 1.5

    for index, frame in pairs(cooldowns) do
        local remain
        if frame.endtime then
            remain = frame.endtime - ctime
        elseif frame.remaining_duration then
            remain = frame.remaining_duration
        else
            --
        end
        if remain < 3 then
            if remain > 1 then
                SetupIcon(frame, section * (remain + 1) * 0.5, 0.02, true, dofl)  -- 1 + (remain - 1) / 2
            elseif remain > 0.3 then
                SetupIcon(frame, section * remain, 0, true, dofl)
            elseif remain > 0 then
                local size = iconsize * (0.5 - remain) * 5  -- iconsize + iconsize * (0.3 - remain) / 0.2
                frame:SetWidth(size)
                frame:SetHeight(size)
                SetupIcon(frame, section * remain, 0, true, dofl)
            elseif remain > -1 then
                SetupIcon(frame, 0, 0, true, dofl)
                frame:SetAlpha(1 + remain)  -- fades
            else
                throt    = (throt < 0.2 and throt) or 0.2
                isactive = true
                ClearCooldown(frame)
            end
        elseif remain < 10 then
            SetupIcon(frame, section * (remain + 11) * 0.14286, remain > 4 and 0.05 or 0.02, true, dofl)  -- 2 + (remain - 3) / 7
        elseif remain < 30 then
            SetupIcon(frame, section * (remain + 50) * 0.05, 0.06, true, dofl)  -- 3 + (remain - 10) / 20
        elseif remain < 120 then
            SetupIcon(frame, section * (remain + 330) * 0.011111, 0.18, true, dofl)  -- 4 + (remain - 30) / 90
        elseif remain < 360 then
            SetupIcon(frame, section * (remain + 1080) * 0.0041667, 1.2, true, dofl)  -- 5 + (remain - 120) / 240
            frame:SetAlpha(1)
        else
            SetupIcon(frame, 6 * section, 2, false, dofl)
        end
    end

    if not isactive and not CoolLine.unlock then
        CoolLine:SetAlpha(db.inactivealpha)
    end
end

local RefreshCooldownDisplay = function()
    local hasLegacyCooldowns = false
    for _, frame in pairs(cooldowns) do
        SyncTimelineEvent(frame)
        if IsLegacyCooldown(frame) then
            frame:Show()
            hasLegacyCooldowns = true
        else
            frame:Hide()
        end
    end

    if hasLegacyCooldowns then
        CoolLine:SetScript("OnUpdate", OnUpdate)
        CoolLine:SetAlpha(db.activealpha)
        OnUpdate(CoolLine, 2)
    else
        CoolLine:SetScript("OnUpdate", nil)
        CoolLine:SetAlpha(CoolLine.unlock and db.activealpha or (NativeTimelineEnabled() and 0 or db.inactivealpha))
    end
end

local function NewCooldownClassic(name, icon, endtime, isplayer, spellID)
    if not name or not icon or not endtime then
        print("CoolLine: NewCooldownClassic called with missing parameters:", name, icon, endtime, isplayer, spellID)
        return
    end
    -- print("CoolLine: NewCooldownClassic called with parameters:", name, icon, endtime, isplayer, spellID)
    local frame
    for index, existing_frame in pairs(cooldowns) do
        if existing_frame.name == name and existing_frame.isplayer == isplayer then
            frame = existing_frame
            break
        elseif existing_frame.endtime == endtime then
            return
        -- ROBUSTNESS ? elseif existing_frame.remaining_duration == 0 then
        --     return
        end
    end

    if not frame then
        frame = frame or tremove(frames)
        if not frame then
            frame = CreateFrame("Frame", nil, CoolLine.border, AddonBackdropTemplate)
            frame:SetBackdrop(iconback)
            frame.icon = frame:CreateTexture(nil, "ARTWORK")
            frame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            frame.icon:SetPoint("TOPLEFT", 1, -1)
            frame.icon:SetPoint("BOTTOMRIGHT", -1, 1)
            -- print("CoolLine: Created new cooldown frame with parameters:", name, icon, endtime, isplayer, spellID)
        end
        tinsert(cooldowns, frame)
    end

    local ctime = GetTime()
    frame:SetWidth(iconsize)
    frame:SetHeight(iconsize)
    frame:SetAlpha((endtime - ctime > 360) and 0.6 or 1)

    frame.name, frame.endtime, frame.isplayer, frame.spellID, frame.iconTexture = name, endtime, isplayer, spellID, icon
    frame.icon:SetTexture(icon)
    SyncTimelineEvent(frame)

    local c = db[isplayer and "spellcolor" or "nospellcolor"]
    frame:SetBackdropColor(c.r, c.g, c.b, c.a)
    RefreshCooldownDisplay()
end

local function NewCooldownRetail(name, icon, remaining_duration, isplayer, spellID)
    --name, id, duration, btype == BOOKTYPE_SPELL
    if not name or not icon or not remaining_duration then
        print("CoolLine: NewCooldownRetail called with missing parameters:", name, icon, remaining_duration, isplayer, spellID)
        return
    end
    -- print("CoolLine: NewCooldownRetail called with parameters:", name, icon, endtime, isplayer, spellID)
    local f
    for index, frame in pairs(cooldowns) do
        if frame.name == name and frame.isplayer == isplayer then
            f = frame
            break
        -- elseif frame.endtime == endtime then
        --     return
        end
    end
    if not f then
        f = f or tremove(frames)
        if not f then
            f = CreateFrame("Frame", nil, CoolLine.border, AddonBackdropTemplate)
            f:SetBackdrop(iconback)
            f.icon = f:CreateTexture(nil, "ARTWORK")
            f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            f.icon:SetPoint("TOPLEFT", 1, -1)
            f.icon:SetPoint("BOTTOMRIGHT", -1, 1)
            -- print("CoolLine: Created new cooldown frame with parameters:", name, icon, endtime, isplayer, spellID)
        end
        tinsert(cooldowns, f)
    end
    f:SetWidth(iconsize)
    f:SetHeight(iconsize)
    f:SetAlpha((remaining_duration > 360.) and 0.6 or 1)

    f.name, f.remaining_duration, f.isplayer, f.spellID, f.iconTexture = name, remaining_duration, isplayer, spellID, icon
    f.icon:SetTexture(icon)
    SyncTimelineEvent(f)

    local c = db[isplayer and "spellcolor" or "nospellcolor"]
    f:SetBackdropColor(c.r, c.g, c.b, c.a)
    RefreshCooldownDisplay()
end

CoolLine.NewCooldownClassic, CoolLine.ClearCooldown, CoolLine.NewCooldownRetail = NewCooldownClassic, ClearCooldown, NewCooldownRetail

do
    -- cache spells that have a cooldown
    --local GetSpellBookItemName, GetSpellBookItemInfo, GetSpellBaseCooldown, GetSpellCharges = GetSpellBookItemName, GetSpellBookItemInfo, GetSpellBaseCooldown, GetSpellCharges

    
    local function CacheBook(btype)
        local spellBook = C_SpellBook
        if spellBook and spellBook.GetNumSpellBookSkillLines and spellBook.GetSpellBookSkillLineInfo
            and spellBook.GetSpellBookItemInfo then
            local function CacheSpell(spellID, spellName)
                if not spellID then -- or not spellName then
                    -- print("CacheSpell called with nil spellID or spellName:", spellID, spellName)
                    return
                end
                if C_Spell and C_Spell.RequestLoadSpellData then
                    C_Spell.RequestLoadSpellData(spellID)
                    -- print("Requested spell data for spellID", spellID)
                end
                if not spellName then
                    spellName = CoolLine:GetSpellInfoCompat(spellID)
                    -- print("Got spell name from GetSpellInfoCompat for spellID", spellID, ":", spellName)
                end

                -- local resolvedName, _, _, _, _, _, resolvedSpellID = GetSpellInfo(spellID)
                local resolvedName, _, _, _, _, _, resolvedSpellID = CoolLine:GetSpellInfoCompat(spellID)
                spellID = resolvedSpellID or spellID
                spellName = resolvedName or spellName

                local _, maxCharges = CoolLine:GetSpellChargesCompat(spellID)
                if maxCharges and maxCharges > 0 then
                    chargespells[btype][spellID] = spellName or tostring(spellID)
                    -- print("Cached charge spell:", spellID, spellName, "maxCharges:", maxCharges)
                else
                    local cooldown = CoolLine:GetSpellBaseCooldownCompat(spellID)
                    if cooldown == nil or cooldown > MINIMUM_COOLDOWN_DURATION_MS then
                        spells[btype][spellID] = spellName or tostring(spellID)
                        -- print("Cached spell with cooldown:", spellID, spellName, "cooldown:", cooldown, "maxCharges:", maxCharges)
                    end
                end
            end

            local function CacheSlot(slot)
                local itemInfo = spellBook.GetSpellBookItemInfo(slot, btype)
                if itemInfo and itemInfo.spellID then
                    -- print("Caching spell from slot", slot, "spellID:", itemInfo.spellID, "name:", itemInfo.name)
                    CacheSpell(itemInfo.spellID, itemInfo.name)
                    -- print("Cached spells for slot", slot, ":", spells[btype])
                end
            end

            if btype == BOOKTYPE_PET then
                local numPetSpells = spellBook.HasPetSpells and spellBook.HasPetSpells() or 0
                for slot = 1, numPetSpells do
                    CacheSlot(slot)
                    -- print("Cached pet spell for slot", slot, ":", spells[btype])
                end
            else
                for skillLine = 1, spellBook.GetNumSpellBookSkillLines() do
                    local skillLineInfo = spellBook.GetSpellBookSkillLineInfo(skillLine)
                    if skillLineInfo and not skillLineInfo.shouldHide then
                        local firstSlot = skillLineInfo.itemIndexOffset + 1
                        local lastSlot = skillLineInfo.itemIndexOffset + skillLineInfo.numSpellBookItems
                        for slot = firstSlot, lastSlot do
                            CacheSlot(slot)
                            -- print("Cached spell for slot", slot, ":", spells[btype])
                        end
                    end
                end
            end
            return
        end

        local lastID
        local sb = spells[btype]

        local _, numTabs
        numTabs  = GetNumSpellTabs()
        for i = 1, numTabs do
            local _, _, offset, numSpells = GetSpellTabInfo(i)
            for j = 1, offset + numSpells do
                -- local spellName = GetSpellBookItemName(j, btype)
                local spellName = CoolLine:GetSpellBookItemNameCompat(j, btype)
                if not spellName then
                    break
                end
                -- local spellType, spellID = GetSpellBookItemInfo(j, btype)
                local spellType, spellID = CoolLine:GetSpellBookItemInfoCompat(j, btype)
                if IS_RETAIL_RELEASE and spellID and spellType == "FLYOUT" then
                    local _, _, numSlots, isKnown = GetFlyoutInfo(spellID)
                    if isKnown then
                        for k = 1, numSlots do
                            local flyID, _, _, flyName = GetFlyoutSlotInfo(spellID, k)
                            lastID                     = flyID
                            if flyID then
                                local flyCD = CoolLine:GetSpellBaseCooldownCompat(flyID)
                                if flyCD and flyCD > MINIMUM_COOLDOWN_DURATION_MS then
                                    sb[flyID] = flyName -- specialspells[flyID] or flyName
                                end
                            end
                        end
                    end
                elseif spellID and (spellType == "SPELL" or spellType == "PETACTION") and spellID ~= lastID then
                    -- Base spell = slot ID + name from slot ID
                    -- Real spell = ID from slot name + name from slot name
                    -- For the purposes of CoolLine we only care about the real spell.
                    lastID                            = spellID
                    -- spellName, _, _, _, _, _, spellID = GetSpellInfo(spellName)
                    spellName, _, _, _, _, _, spellID = CoolLine:GetSpellInfoCompat (spellName)
                    if spellID then
                        -- Special spells like warlock Cauterize Master can be in
                        -- a limbo state during loading. Just ignore them in that
                        -- case. The spellbook will update again momentarily and
                        -- they will correctly resolve then.
                        -- local _, maxCharges = GetSpellCharges(spellID)
                        local _, maxCharges = CoolLine:GetSpellChargesCompat(spellID)
                        if maxCharges and maxCharges > 0 then
                            chargespells[btype][spellID] = spellName
                        else
                            -- local cd = GetSpellBaseCooldown(spellID)
                            local cd = CoolLine:GetSpellBaseCooldownCompat(spellID)
                            if cd and cd > MINIMUM_COOLDOWN_DURATION_MS then
                                sb[spellID] = spellName
                                --			if specialspells[spellName] then
                                --				sb[ specialspells[spellName] ] = spellName
                                --			end
                            end
                        end
                    end
                end
            end
        end
    end

    ----------------------------------
    function CoolLine:SPELLS_CHANGED()
        ----------------------------------
        CacheBook(BOOKTYPE_SPELL)
        if not db.hidepet then
            CacheBook(BOOKTYPE_PET)
        end
    end
end

do
    -- scans spellbook to update cooldowns, throttled since the event fires a lot
    local selap                                              = 0
    local spellthrot                                         = CreateFrame("Frame", nil, CoolLine)
    -- local GetSpellCooldown, GetSpellTexture, GetSpellCharges = GetSpellCooldown, GetSpellTexture, GetSpellCharges
    -- local GetSpellTexture = GetSpellTexture

    local function CheckSpellBookLegacy(btype)
        for id, name in pairs(spells[btype]) do
            local start, duration, enable = CoolLine:GetSpellCooldownCompat(id)
            if enable == 1 and start > 0 and not block[name] and (not RuneCheck or RuneCheck(name, duration)) then
                if duration > DEFAULT_RETAIL_GCD_DURATION_S then
                    local _, _, texture = CoolLine:GetSpellInfoCompat(id)
                    NewCooldownClassic(name, texture, start + duration, btype == BOOKTYPE_SPELL, id)
                else
                    for i = 1, #cooldowns do
                        local frame = cooldowns[i]
                        if frame.name == name then
                            if frame.endtime > start + duration + 0.1 then
                                frame.endtime = start + duration
                                    if duration > DEFAULT_RETAIL_GCD_DURATION_S then
                                        SyncTimelineEvent(frame)
                                    else
                                        frame.spellID = nil
                                        SyncTimelineEvent(frame)
                                    end
                            end
                            break
                        end
                    end
                end
            else
                ClearCooldown(nil, name)
            end
        end

        for id, name in pairs(chargespells[btype]) do
            local currentCharges, maxCharges, cooldownStart, cooldownDuration = CoolLine:GetSpellChargesCompat(id)
            if cooldownStart and cooldownDuration and currentCharges < maxCharges and not block[name] then
                --local _, _, texture = GetSpellInfo(id)
                local _, _, texture = CoolLine:GetSpellInfoCompat(id)
                -- print("CoolLine: Adding cooldown for charge spell:", name, "ID:", id, "Texture:", texture, "Cooldown Start:", cooldownStart, "Cooldown Duration:", cooldownDuration)
                NewCooldownClassic(name, texture, cooldownStart + cooldownDuration, btype == BOOKTYPE_SPELL, id)
            else
                ClearCooldown(nil, name)
            end
        end
    end

    local function CheckSpellBookRetail(btype)
        for id, name in pairs(spells[btype]) do
            local info = C_Spell.GetSpellCooldown(id)

            if info and info.isActive and not block[name] then
                local remaining_duration = CoolLine:GetSpellCooldownDurationCompat(id)
                
                if remaining_duration then
                    local _, _, texture = CoolLine:GetSpellInfoCompat(id)
                    -- name, icon, remaining_time, isplayer, spellID
                    NewCooldownRetail(name, texture, remaining_duration, btype == BOOKTYPE_SPELL, id)
                else
                    for i = 1, #cooldowns do
                        local frame = cooldowns[i]
                        if frame.name == name then
                            if frame.duration > remaining_duration + 0.1 then
                                frame.duration = remaining_duration
                                    if remaining_duration > DEFAULT_RETAIL_GCD_DURATION_S then
                                        SyncTimelineEvent(frame)
                                    else
                                        frame.spellID = nil
                                        SyncTimelineEvent(frame)
                                    end
                            end
                            break
                        end
                    end
                end
            else
                ClearCooldown(nil, name)
            end
        end
    end

    local function CheckSpellBook(btype)
        if IS_RETAIL_RELEASE then
            CheckSpellBookRetail(btype)
        else
            CheckSpellBookLegacy(btype)
        end
    end
    spellthrot:SetScript("OnUpdate", function(this, a1)
        selap = selap + a1
        if selap < 0.3 then
            return
        end
        selap = 0
        this:Hide()
        CheckSpellBook(BOOKTYPE_SPELL)
        if not db.hidepet and HasPetUI() then
            CheckSpellBook(BOOKTYPE_PET)
        end
    end)

    spellthrot:Hide()

    -----------------------------------------
    function CoolLine:SPELL_UPDATE_COOLDOWN()
    -----------------------------------------
        spellthrot:Show()
    end
    ----------------------------------------------------
    function CoolLine:ENCOUNTER_TIMELINE_STATE_UPDATED()
    ----------------------------------------------------
        RefreshCooldownDisplay()
    end
end

do
    -- scans equipments and bags for item cooldowns
    local GetItemInfo                                       = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
    -- local GetInventoryItemCooldown, GetInventoryItemTexture = GetInventoryItemCooldown, GetInventoryItemTexture
    -- local GetContainerItemCooldown                          = C_Container and C_Container.GetItemCooldown or _G.GetContainerItemCooldown
    local GetContainerNumSlots                              = C_Container and C_Container.GetContainerNumSlots or _G.GetContainerNumSlots
    local GetContainerItemLink                                 = C_Container and C_Container.GetContainerItemLink or _G.GetContainerItemLink
    
    local maxBagSlots = NUM_BAG_SLOTS or (Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumBagSlots) or 4

    ---------------------------------------
    function CoolLine:BAG_UPDATE_COOLDOWN()
    ---------------------------------------
        -- scan equipped objects
        for i = 1, (db.hideinv and 0) or 18 do
            local start, duration, enable = GetInventoryItemCooldown("player", i)
            if enable == 1 then
                --local name = GetItemInfo(GetInventoryItemLink("player", i))
                local link = GetInventoryItemLink("player", i)
                local name = link and GetItemInfo(link)
                if start > 0 and not block[name] then -- 'and name' ?
                    if duration > DEFAULT_RETAIL_GCD_DURATION_S and duration < DEFAULT_RETAIL_MAX_DURATION_S then
                        local texture = GetInventoryItemTexture("player", i)
                        -- print("CoolLine: Adding cooldown for item:", name, "Texture:", texture, "Start:", start, "Duration:", duration)
                        NewCooldownClassic(name, texture, start + duration)
                    end
                else
                    ClearCooldown(nil, name)
                end

            end
        end
        -- scan bags
        for i = 0, (db.hidebag and -1) or maxBagSlots do
            local numSlots = GetContainerNumSlots(i) or 0
            for j = 1, numSlots do
                local start, duration, enable = CoolLine:GetContainerItemCooldownCompat(i, j)
                if enable == 1 then
                    --local name = GetItemInfo(GetContainerItemLink(i, j))
                    local link = GetContainerItemLink(i, j)
                    local name = link and GetItemInfo(link)
                    if start > 0 and not block[name] then
                        if duration > DEFAULT_RETAIL_GCD_DURATION_S and duration < DEFAULT_RETAIL_MAX_DURATION_S then
                            -- NewCooldown(name, GetContainerItemInfo(i, j), start + duration)
                            local texture = CoolLine:GetContainerItemIconCompat(i, j)
                            -- print("CoolLine: Adding cooldown for bag item:", name, "Texture:", texture, "Start:", start, "Duration:", duration) 
                            NewCooldownClassic(name, texture, start + duration)
                        end
                    else
                        ClearCooldown(nil, name)
                    end
                end
            end
        end
    end
end

-------------------------------------------
function CoolLine:PET_BAR_UPDATE_COOLDOWN()
-------------------------------------------
    for i = 1, 10 do
        local start, duration, enable = GetPetActionCooldown(i)
        if enable == 1 then
            local name, _, texture
            if IS_RETAIL_RELEASE then
                name, texture = GetPetActionInfo(i)
            else
                name, _, texture = GetPetActionInfo(i)
            end
            if name then
                if start > 0 and not block[name] then
                    if duration > DEFAULT_RETAIL_GCD_DURATION_S then
                        -- print("CoolLine: Adding cooldown for pet action:", name, "Texture:", texture, "Start:", start, "Duration:", duration)
                        NewCooldownClassic(name, texture, start + duration)
                    end
                else
                    ClearCooldown(nil, name)
                end
            end
        end
    end
end

------------------------------
function CoolLine:UNIT_PET()
------------------------------
    if UnitExists("pet") and not HasPetUI() then
        self:RegisterEvent("PET_BAR_UPDATE_COOLDOWN")
    else
        self:UnregisterEvent("PET_BAR_UPDATE_COOLDOWN")
    end
end

local GetActionCooldown, HasAction = GetActionCooldown, HasAction
---------------------------------------------
function CoolLine:ACTIONBAR_UPDATE_COOLDOWN()
-- used only for vehicles
---------------------------------------------
    for i = 1, 8 do
        local b = _G["OverrideActionBarButton" .. i]
        if b and HasAction(b.action) then
            local start, duration, enable = GetActionCooldown(b.action)
            if enable == 1 then
                if start > 0 and not block[GetActionInfo(b.action)] then
                    if duration > DEFAULT_RETAIL_GCD_DURATION_S then
                        NewCooldownClassic("vehicle" .. i, GetActionTexture(b.action), start + duration)
                    end
                else
                    ClearCooldown(nil, "vehicle" .. i)
                end
            end
        end
    end
end

------------------------------------------
function CoolLine:UNIT_ENTERED_VEHICLE()
    ------------------------------------------
    if not UnitHasVehicleUI("player") then
        return
    end
    self:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    self:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    self:ACTIONBAR_UPDATE_COOLDOWN()
end

-----------------------------------------
function CoolLine:UNIT_EXITED_VEHICLE()
    -----------------------------------------
    self:UnregisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
    for i = 1, #cooldowns do
        local frame = cooldowns[i]
        if frame and strmatch(frame.name, "vehicle") then
            -- print("CoolLine: Clearing cooldown for vehicle action:", frame.name)
            ClearCooldown(nil, frame.name)
        end
    end
end

local failborder
----------------------------------------------------
function CoolLine:UNIT_SPELLCAST_FAILED(unit, spell, id8)
    ----------------------------------------------------
    if IS_RETAIL_RELEASE then
        spell = self:GetSpellInfoCompat(id8) -- TEMPORARY, need to switch to using spell IDs throughout
    end

    if #cooldowns == 0 then
        return
    end

    for index, frame in pairs(cooldowns) do
        if frame.name == spell then
            if (frame.endtime and frame.endtime - GetTime() > 1) or frame.remaining_duration and frame.remaining_duration > 1 then
                if not failborder then
                    failborder = CreateFrame("Frame", nil, CoolLine.border, AddonBackdropTemplate)
                    failborder:SetBackdrop(iconback)
                    failborder:SetBackdropColor(1, 0, 0, 0.9)
                    failborder:Hide()
                    failborder:SetScript("OnUpdate", function(this, a1)
                        this.alp = this.alp - a1
                        if this.alp < 0 then
                            return this:Hide()
                        end
                        this:SetAlpha(this.alp > 1 and 1 or this.alp)
                    end)
                end

                failborder.alp = 1.2
                failborder:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 2)
                failborder:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
                failborder:Show()
            end
            break
        end
    end
end

local CoolLineDD, Set
local info = { }

function ShowOptions(a1)
    if type(a1) == "string" and a1 ~= "" and a1 ~= "menu" and a1 ~= "options" and a1 ~= "help" and a1 ~= "list" then
        if strmatch(a1, "|H") then
            a1 = strmatch(a1, "|h%[(.+)%]|h")
        end
        if a1 then
            if block[a1] then
                block[a1] = nil
                print("|cff88ffffCool|r|cff88ff88Line|r: |cffffff00" .. a1 .. "|r removed from filter.")
            else
                block[a1] = true
                print("|cff88ffffCool|r|cff88ff88Line|r: |cffffff00" .. a1 .. "|r added to filter.")
            end
        end
        return
    end
    if a1 == "help" or a1 =="h" then
        print(format(unpack(HELP_TEXT_FORMAT)))
        return
    elseif a1 == "list" or a1 =="l" then
        print("|cff88ffffCool|r|cff88ff88Line|r: |cffffff00 List of ignored spells |r")
        for k,v in pairs(block) do
            local name, _, iconID, castTime, minRange, maxRange, spellID = CoolLine:GetSpellInfoCompat(k)
            if not name then
                name = CoolLine:GetItemNameCompat(k)
            else
                name = "(name not found ?!)"
            end
            print("|cff88ffffCool|r|cff88ff88Line|r: id=|cffffff00" .. k .. " (" .. name .. ") |r blocked")
            return
        end
    end

    if not CoolLineDD then
        CoolLineDD             = CreateFrame("Frame", "CoolLineDD", UIParent)
        CoolLineDD.displayMode = "MENU"

        Set                    = function(b, a1)
            if a1 == "unlock" then
                if not CoolLine.resizer then
                    CoolLine:SetResizable(true)
                    local wrapperLoaded = CoolLine:IsAddonLoadedCompat("ElvUI_CoolLine_Wrapper")
                    CoolLine:SetMovable(not wrapperLoaded)
                    if not wrapperLoaded then
                        CoolLine:RegisterForDrag("LeftButton")
                    end
                    CoolLine:SetScript("OnMouseUp", function(this, a1)
                        if a1 == "RightButton" then
                            ShowOptions()
                        end
                    end)
                    if not wrapperLoaded then
                        CoolLine:SetScript("OnDragStart", function(this)
                            this:StartMoving()
                        end)
                        CoolLine:SetScript("OnDragStop", function(this)
                            this:StopMovingOrSizing()
                            local x, y   = this:GetCenter()
                            local ux, uy = UIParent:GetCenter()
                            db.x, db.y   = floor(x - ux + 0.5), floor(y - uy + 0.5)
                            this:ClearAllPoints()
                            updatelook()
                        end)
                    end

                    CoolLine:SetMinResize(6, 6)
                    CoolLine.resizer = CreateFrame("Button", nil, CoolLine.border, "UIPanelButtonTemplate")
                    local resize     = CoolLine.resizer
                    resize:SetWidth(8)
                    resize:SetHeight(8)
                    resize:SetPoint("BOTTOMRIGHT", CoolLine, "BOTTOMRIGHT", 2, -2)
                    resize:SetScript("OnMouseDown", function(this)
                        CoolLine:StartSizing("BOTTOMRIGHT")
                    end)
                    resize:SetScript("OnMouseUp", function(this)
                        CoolLine:StopMovingOrSizing()
                        db.w, db.h = floor(CoolLine:GetWidth() + 0.5), floor(CoolLine:GetHeight() + 0.5)
                        updatelook()
                    end)
                end
                if not CoolLine.unlock then
                    CoolLine.unlock = true
                    CoolLine:EnableMouse(true)
                    CoolLine.resizer:Show()
                    CoolLine:SetAlpha(db.activealpha)
                    print("CoolLine - drag frame to reposition or drag red corner to resize")
                else
                    CoolLine.unlock = nil
                    CoolLine:EnableMouse(false)
                    CoolLine.resizer:Hide()
                    OnUpdate(CoolLine, 2)
                end
            elseif a1 then
                if a1 == "vertical" then
                    local pw, ph = db.w, db.h
                    db.w, db.h   = ph, pw
                elseif a1 == "resetall" then
                    CoolLineCharDB, CoolLineDB = nil, nil
                    return ReloadUI()
                end
                db[a1] = not db[a1]
                if a1 == "perchar" then
                    if db.perchar then
                        CoolLineCharDB = CoolLineCharDB or CoolLineDB
                    else
                        CoolLineCharDB = nil
                    end
                    ReloadUI()
                end
                updatelook()
            end
        end

        local function SetSelect(b, a1)
            db[a1]           = tonumber(b.value) or b.value
            local level, num = strmatch(b:GetName(), "DropDownList(%d+)Button(%d+)")
            level, num       = tonumber(level) or 0, tonumber(num) or 0
            for i = 2, level do
                for j = 1, UIDROPDOWNMENU_MAXBUTTONS do
                    local check = _G["DropDownList" .. i .. "Button" .. j .. "Check"]
                    if check and i == level and j == num then
                        check:Show()
                    elseif b then
                        check:Hide()
                    end
                end
            end
            updatelook()
        end

        local function SetColor(a1)
            local dbc = db[UIDROPDOWNMENU_MENU_VALUE]
            if not dbc then
                return
            end
            local r, g, b, a
            if a1 then
                local pv   = ColorPickerFrame.previousValues
                r, g, b, a = pv.r, pv.g, pv.b, 1 - pv.opacity
            else
                r, g, b = ColorPickerFrame:GetColorRGB()
                a       = 1 - OpacitySliderFrame:GetValue()
            end
            dbc.r, dbc.g, dbc.b, dbc.a = r, g, b, a
            updatelook()
        end

        local function HideCheck(b)
            if b and b.GetName and _G[b:GetName() .. "Check"] then
                _G[b:GetName() .. "Check"]:Hide()
            end
        end

        local function AddButton(lvl, text, keepshown)
            info.text             = text
            info.keepShownOnClick = keepshown
            UIDropDownMenu_AddButton(info, lvl)
            wipe(info)
        end

        local function AddToggle(lvl, text, value)
            info.arg1 = value
            info.func = Set
            if value == "unlock" then
                info.checked = CoolLine.unlock
            else
                info.checked = db[value]
            end
            AddButton(lvl, text, 1)
        end

        local function AddList(lvl, text, value)
            info.value        = value
            info.hasArrow     = true
            info.func         = HideCheck
            info.notCheckable = 1
            AddButton(lvl, text, 1)
        end

        local function AddSelect(lvl, text, arg1, value)
            info.arg1  = arg1
            info.func  = SetSelect
            info.value = value
            if tonumber(value) and tonumber(db[arg1] or "blah") then
                if floor(100 * tonumber(value)) == floor(100 * tonumber(db[arg1])) then
                    info.checked = true
                end
            else
                info.checked = db[arg1] == value
            end
            AddButton(lvl, text, 1)
        end

        local function AddColor(lvl, text, value)
            local dbc = db[value]
            if not dbc then
                return
            end
            info.hasColorSwatch                                = true
            info.hasOpacity                                    = 1
            info.r, info.g, info.b, info.opacity               = dbc.r, dbc.g, dbc.b, 1 - (dbc.a or 0)
            info.swatchFunc, info.opacityFunc, info.cancelFunc = SetColor, SetColor, SetColor
            info.value                                         = value
            info.func                                          = UIDropDownMenuButton_OpenColorPicker
            info.notCheckable                                  = 1
            AddButton(lvl, text, nil)
        end

        CoolLineDD.initialize = function(self, lvl)
            if lvl == 1 then
                info.isTitle      = true
                info.notCheckable = 1
                AddButton(lvl, "|cff88ffffCool|r|cff88ff88Line|r")
                AddList(lvl, "Texture", "statusbar")
                AddColor(lvl, "Texture Color", "bgcolor")
                AddList(lvl, "Border", "border")
                AddList(lvl, "Border Size", "bordersize") -- Added Options
                AddList(lvl, "Border Inset", "borderinset") -- Added Options
                AddColor(lvl, "Border Color", "bordercolor")
                AddList(lvl, "Font", "font")
                AddColor(lvl, "Font Color", "fontcolor")
                AddList(lvl, "Font Size", "fontsize")
                AddColor(lvl, "My Spell Color", "spellcolor")
                AddColor(lvl, "Item/Pet Color", "nospellcolor")
                AddList(lvl, "Inactive Opacity", "inactivealpha")
                AddList(lvl, "Active Opacity", "activealpha")
                AddList(lvl, "Icon Size", "iconplus")
                AddList(lvl, "More", "More")
                AddToggle(lvl, "Unlock", "unlock")
            elseif lvl and lvl > 1 then
                local sub = UIDROPDOWNMENU_MENU_VALUE
                if sub == "font" or sub == "statusbar" or sub == "border" then
                    local t      = smed:List(sub)
                    local starti = 20 * (lvl - 2) + 1
                    local endi   = 20 * (lvl - 1)
                    for i = starti, endi do
                        if not t[i] then
                            break
                        end
                        AddSelect(lvl, t[i], sub, t[i])
                        if i == endi and t[i + 1] then
                            AddList(lvl, "More", sub)
                        end
                    end
                elseif sub == "fontsize" then
                    for i = 5, 12 do
                        AddSelect(lvl, i, "fontsize", i)
                    end
                    for i = 14, 28, 2 do
                        AddSelect(lvl, i, "fontsize", i)
                    end
                elseif sub == "bordersize" then
                    -- Added options limits
                    for i = 1, 16 do
                        AddSelect(lvl, i, "bordersize", i)
                    end
                elseif sub == "borderinset" then
                    -- Added options limits
                    for i = -10, 10 do
                        AddSelect(lvl, i, "borderinset", i)
                    end
                elseif sub == "inactivealpha" or sub == "activealpha" then
                    for i = 0, 1, 0.1 do
                        AddSelect(lvl, format("%.1f", i), sub, i)
                    end
                elseif sub == "iconplus" then
                    for i = 0, 24, 2 do
                        AddSelect(lvl, format("+%d", i), sub, i)
                    end
                elseif sub == "More" then
                    AddToggle(lvl, "Vertical", "vertical")
                    AddToggle(lvl, "Reverse", "reverse")
                    AddToggle(lvl, "Use Blizzard encounter timeline for spells", "blizzardTimeline")
                    AddToggle(lvl, "Disable Cast Fail", "hidefail")
                    AddToggle(lvl, "Disable Equipped", "hideinv")
                    AddToggle(lvl, "Disable Bags", "hidebag")
                    AddToggle(lvl, "Disable Pet", "hidepet")
                    AddToggle(lvl, "Save Per Char", "perchar")
                    AddToggle(lvl, _G.RESET_TO_DEFAULT, "resetall")
                end
            end
        end
    end

    ToggleDropDownMenu(1, nil, CoolLineDD, "cursor")
end

CONFIGMODE_CALLBACKS          = CONFIGMODE_CALLBACKS or {}
CONFIGMODE_CALLBACKS.CoolLine = function(action, mode)
    if action == "ON" then
        if not CoolLineDD then
            ShowOptions()
            ToggleDropDownMenu(1, nil, CoolLineDD, "cursor")
        end
        if CoolLineDD and not CoolLine.unlock then
            Set(nil, "unlock")
        end
    elseif action == "OFF" then
        if CoolLineDD and CoolLine.unlock then
            Set(nil, "unlock")
        end
    end
end
