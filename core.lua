local addonName = ...
local CoolLineApp = LibStub("AceAddon-3.0"):GetAddon(addonName)

local _, _, _, build_toc_version = GetBuildInfo()
local major_version                           = floor(build_toc_version / 10000)
local IS_RETAIL_RELEASE                       = (WOW_PROJECT_ID and WOW_PROJECT_MAINLINE and WOW_PROJECT_ID == WOW_PROJECT_MAINLINE) or major_version >= 10

local AddonBackdropTemplate = 42
if WOW_PROJECT_ID == WOW_PROJECT_CLASSIC then
    AddonBackdropTemplate = nil
else
    AddonBackdropTemplate = "BackdropTemplate"
end

local CoolLine = CoolLineApp.MainFrame
CoolLine.IS_RETAIL_RELEASE = IS_RETAIL_RELEASE

-- Single source of truth for the client family. "retail" and "forever" can return secret values;
-- "forever" also covers any non-retail client that exposes issecretvalue, so the secret-value
-- handling and the Forever-only behaviors (combat snapshots, shared-end-time dedup) cannot diverge.
local IS_FOREVER_BUILD = build_toc_version >= 16000 and build_toc_version < 20000
local HAS_SECRET_VALUE_API = type(_G.issecretvalue) == "function"
CoolLine.CLIENT = (IS_RETAIL_RELEASE and "retail")
    or ((IS_FOREVER_BUILD or HAS_SECRET_VALUE_API) and "forever")
    or "classic"
CoolLine.IS_FOREVER = CoolLine.CLIENT == "forever"

CoolLine:SetScript("OnEvent", function(this, event, ...)
    if event == "SPELL_UPDATE_COOLDOWN" then
        this[event](this, true)
    else
        this[event](this, ...)
    end
end)

local smed                                                  = LibStub("LibSharedMedia-3.0")

local _G, pairs, strmatch, tinsert, tremove, random         = _G, pairs, string.match, table.insert, table.remove, math.random
local GetTime                                               = GetTime
local UnitExists, HasPetUI                                  = UnitExists, HasPetUI


local db, block
function CoolLine:IsBlocked(name, id)
    return (name and block[name]) or (id and (block[id] or block[tostring(id)]))
end

function CoolLine:LogCooldownDebug(key, message)
    if not self.cooldownDebugEnabled then
        return
    end
    self.cooldownDebugMessages = self.cooldownDebugMessages or {}
    if self.cooldownDebugMessages[key] == message then
        return
    end
    self.cooldownDebugMessages[key] = message
    local category = key:match("^timeline:") and "Timeline"
        or key:match("^options:") and "Options"
        or (key:match("^create:") or key:match("^config:")) and "Core"
        or "Spellbook"
    CoolLineApp:Debug(category, message)
end

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
CoolLine.BOOKTYPE_SPELL, CoolLine.BOOKTYPE_PET = BOOKTYPE_SPELL, BOOKTYPE_PET

local MINIMUM_COOLDOWN_DURATION_MS                          = 2499
local DEFAULT_RETAIL_GCD_DURATION_S                         = 1.5 -- 0.749
local DEFAULT_RETAIL_MAX_DURATION_S                         = 3601
-- An estimated cooldown that the game has not confirmed for this long after its estimated end is dropped.
local ESTIMATE_STALE_S                                      = 20
-- A cooldown routed to Blizzard's timeline is dropped this long after its end if no scan has cleared it.
local EXPIRED_GRACE_S                                       = 1
CoolLine.MINIMUM_COOLDOWN_DURATION_MS = MINIMUM_COOLDOWN_DURATION_MS
CoolLine.DEFAULT_RETAIL_GCD_DURATION_S = DEFAULT_RETAIL_GCD_DURATION_S
CoolLine.DEFAULT_RETAIL_MAX_DURATION_S = DEFAULT_RETAIL_MAX_DURATION_S

-- Expert settings, stored in db.expert[key]. Only values that differ from the default are saved; a missing or
-- invalid value falls back to the default and the others are clamped to [min, max]. They only matter for
-- cooldowns whose timing the game hides (restricted values), where the bar has to estimate.
local EXPERT_SETTINGS = {
    hold = {
        default = 0.5, min = 0, max = 3, step = 0.05, name = "Estimate hold point (s)",
        desc = "An estimated cooldown stops at this remaining time while the game still reports it as active. "
            .. "Lower values let the icon get closer to the end of the bar before it waits.",
    },
    confirm = {
        default = 2.5, min = 0.5, max = 5, step = 0.1, name = "Confirmation delay (s)",
        desc = "How long a new restricted cooldown must stay active before it is shown. It filters out the "
            .. "global cooldown, so values below about 1.5 can display short global-cooldown blips.",
    },
    orphan = {
        default = 5, min = 1, max = 15, step = 1, name = "Drop unconfirmed icons after (s)",
        desc = "An estimated icon is removed this long after its estimated end when the game no longer says "
            .. "whether the cooldown is active (for example after a talent change).",
    },
    fallback = {
        default = 30, min = 5, max = 300, step = 1, name = "Fallback duration (s)",
        desc = "Estimated duration of a restricted cooldown that was never seen with readable timing, when "
            .. "its base cooldown is unknown. Base cooldowns ignore talents and haste.",
    },
    recheck = {
        default = 0.25, min = 0.1, max = 2, step = 0.05, name = "Recheck interval (s)",
        desc = "How often a waiting icon asks the game whether the cooldown is over. Lower values "
            .. "remove icons sooner but scan the spellbook more often (scans are also throttled to about 0.3 s).",
    },
}
CoolLine.EXPERT_SETTINGS = EXPERT_SETTINGS
CoolLine.EXPERT_ORDER = { "hold", "confirm", "orphan", "fallback", "recheck" }

function CoolLine:GetExpert(key)
    local setting = EXPERT_SETTINGS[key]
    if not setting then
        return nil
    end
    local value = db and db.expert and db.expert[key]
    if type(value) ~= "number" or value ~= value then
        return setting.default
    end
    return math.min(setting.max, math.max(setting.min, value))
end

local SetValue, updatelook, createfs, RuneCheck
local RefreshCooldownDisplay

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
                                  ["6948"] = true, -- Hearthstone item ID
                                  ["8690"] = true, -- Hearthstone use spell ID
                              },
                          }) do
            db[k] = (db[k] ~= nil and db[k]) or v
        end
    end
    if db.blizzardTimeline == nil then
        db.blizzardTimeline = false
    end
    if db.legacyTimeline == nil then
        db.legacyTimeline = true
    end
    if db.timelinePlayer == nil then
        db.timelinePlayer = true
    end
    if db.timelinePet == nil then
        db.timelinePet = false
    end
    if db.timelineItem == nil then
        db.timelineItem = false
    end
    if db.showConfigPreviews == nil then
        db.showConfigPreviews = false
    end
    block          = db.block
    if block[hearthstoneName or "Hearthstone"] or block.Hearthstone then
        block["6948"], block["8690"] = true, true
        block[hearthstoneName or "Hearthstone"], block.Hearthstone = nil, nil
    end
    CoolLine.db    = db
    
    CoolLineApp:Debug("Core", "Loaded CoolLine configuration")
    

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
    CoolLine.RuneCheck = RuneCheck
    CoolLine.specialspells = specialspells

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

    updatelook          = function()
        self:SetWidth(db.w or 130)
        self:SetHeight(db.h or 18)

        if not self.ElvUIMoverCreated then
            self:ClearAllPoints()
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
        tick120  = createfs(tick120, "2 m", section * 5)
        tick300  = createfs(tick300, "6 m", section * 6, "RIGHT")

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
        end
        if RefreshCooldownDisplay then
            RefreshCooldownDisplay()
        end
    end
    CoolLine.updatelook = updatelook
    self:SetupOptions()

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
    if self.CLIENT ~= "classic" then
        -- Cooldown timing can turn secret when a restriction starts; keep exact snapshots around that moment.
        self:RegisterEvent("PLAYER_REGEN_DISABLED")
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
        if C_RestrictedActions and C_RestrictedActions.GetAddOnRestrictionState then
            pcall(self.RegisterEvent, self, "ADDON_RESTRICTION_STATE_CHANGED")
        end
    end
    self:SPELL_UPDATE_COOLDOWN()
    if C_EncounterTimeline and C_EncounterTimeline.IsFeatureAvailable then
        self:RegisterEvent("ENCOUNTER_TIMELINE_STATE_UPDATED")
    end

    --@version-retail@
    self:RegisterEvent("PET_BATTLE_OPENING_START")
    self:RegisterEvent("PET_BATTLE_CLOSE")
    self.PET_BATTLE_OPENING_START = function(frame)
        frame.inPetBattle = true
        frame:UpdateTimelineFrameVisibility()
    end
    self.PET_BATTLE_CLOSE = function(frame)
        frame.inPetBattle = false
        frame:UpdateTimelineFrameVisibility()
    end
    self.inPetBattle = C_PetBattles.IsInBattle()

    self:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
    if UnitHasVehicleUI("player") then
        self:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
        self:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    end
    --@end-version-retail@

    updatelook()
    if db.showConfigPreviews and CoolLine.SetConfigPreviews then
        CoolLine:SetConfigPreviews(true)
    end
    if self.UpdateAutoHide then
        self:UpdateAutoHide()
    end
    self:UpdateTimelineFrameVisibility()
    self:RegisterEvent("PLAYER_LEAVING_WORLD")
end

function CoolLine:PLAYER_REGEN_DISABLED()
    self:ScanCooldownsNow()
end

function CoolLine:PLAYER_REGEN_ENABLED()
    self:ScanCooldownsNow()
    if not (db.hidebag and db.hideinv) then
        self:BAG_UPDATE_COOLDOWN()
    end
    if not db.hidepet and UnitExists("pet") then
        self:PET_BAR_UPDATE_COOLDOWN()
    end
end

-- "Activating" is dispatched while values are still readable, just before the restriction is enforced:
-- take a last exact snapshot. "Inactive" means timings are readable again: reconcile estimates at once.
function CoolLine:ADDON_RESTRICTION_STATE_CHANGED(_, state)
    local states = Enum and Enum.AddOnRestrictionState
    if states and state == states.Active then
        return
    end
    self:ScanCooldownsNow()
end

function CoolLine:UpdateTimelineFrameVisibility()
    if db.legacyTimeline ~= false and not self.inPetBattle and not self.autoHidden then
        self:Show()
    else
        self:Hide()
    end
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

local function ClearCooldown(f, name, source)
    name = name or (f and f.name)
    source = source or (f and f.source)
    for i = 1, #cooldowns do
        local frame = cooldowns[i]
        if frame.name == name and (not source or frame.source == source) then
            CoolLine:CancelTimelineEvent(frame)
            frame:Hide()
            if frame.secretCooldown then
                frame.secretCooldown:Hide()
            end
            if frame.estimateLabel then
                frame.estimateLabel:Hide()
            end
            frame.name    = nil
            frame.endtime = nil
            frame.remaining_duration = nil
            frame.source = nil
            frame.estimated = nil
            frame.confirmedAt = nil
            frame.pinned = nil
            frame.pinOffset = nil
            tinsert(frames, tremove(cooldowns, i))
            break
        end
    end
end

local function SyncTimelineEvent(frame)
    CoolLine:SyncTimelineEvent(frame)
end

local function NativeTimelineEnabled()
    return CoolLine:IsNativeTimelineEnabled()
end

local function SetupIcon(frame, position, tthrot, active, fl)
    throt    = (throt < tthrot and throt) or tthrot
    isactive = active or isactive
    -- Icons waiting at the hold point keep a stable order: shuffling them would make overlapping icons blink.
    if fl and not frame.pinned then
        frame:SetFrameLevel(random(1, 5) * 2 + 2)
    end
    SetValue(frame, position + (frame.pinOffset or 0))
end

local function IsLegacyCooldown(frame)
    return frame.source == "config" or not frame.timelineEventID
end

local function FrameEndTime(frame, ctime)
    if frame.endtime then
        return frame.endtime
    end
    if frame.remaining_duration then
        return (frame.cooldownSampleTime or ctime) + frame.remaining_duration
    end
end

-- Frames routed to Blizzard's timeline have no OnUpdate-driven display, so nothing else would notice that
-- their cooldown ended if the scan that reports it never comes (for example after a loading screen).
local function SweepExpiredCooldowns(ctime)
    for i = #cooldowns, 1, -1 do
        local frame = cooldowns[i]
        local endTime = FrameEndTime(frame, ctime)
        if endTime and frame.source ~= "config" then
            -- Exact bar frames are removed by the display loop; only estimates and native ones need this.
            local limit
            if frame.estimated then
                limit = ESTIMATE_STALE_S
                -- Scans keep confirmedAt fresh while the game reports the cooldown as active.
                endTime = math.max(endTime, frame.confirmedAt or 0)
            elseif not IsLegacyCooldown(frame) then
                limit = EXPIRED_GRACE_S
            end
            if limit and ctime - endTime > limit then
                ClearCooldown(frame)
            end
        end
    end
end

local function OnUpdate(this, a1, ctime, dofl)
    elapsed = elapsed + a1
    if elapsed < throt then
        return
    end
    elapsed = 0
    ctime = ctime or GetTime()

    SweepExpiredCooldowns(ctime)

    local hasLegacyCooldowns = false
    for _, frame in pairs(cooldowns) do
        if IsLegacyCooldown(frame) then
            hasLegacyCooldowns = true
            break
        end
    end

    if not hasLegacyCooldowns then
        if #cooldowns == 0 then
            CoolLine:SetScript("OnUpdate", nil)
        end
        throt = 1.5
        CoolLine:SetAlpha(CoolLine.unlock and db.activealpha
            or (NativeTimelineEnabled() and 0 or db.inactivealpha))
        return
    end

    if ctime > ptime then
        dofl, ptime = true, ctime + 0.4
    end
    isactive, throt = false, 1.5

    local hold = CoolLine:GetExpert("hold")
    local pinnedCount = 0
    for index, frame in pairs(cooldowns) do
        local remain
        if frame.endtime then
            remain = frame.endtime - ctime
        elseif frame.remaining_duration then
            remain = frame.remaining_duration - (ctime - (frame.cooldownSampleTime or ctime))
        else
            remain = -2
        end
        local pinned = false
        if frame.estimated and remain < hold then
            -- The estimate is exhausted but the game still reports the cooldown: wait at the hold point
            -- (fanned out so several waiting icons stay visible) until a scan says it is over.
            remain, pinned = hold, true
            if (frame.recheckAt or 0) <= ctime and CoolLine.RequestCooldownRecheck then
                frame.recheckAt = ctime + CoolLine:GetExpert("recheck")
                CoolLine:RequestCooldownRecheck()
            end
        end
        frame.pinned = pinned
        if pinned then
            frame.pinOffset = pinnedCount * iconsize * 0.75
            pinnedCount = pinnedCount + 1
        else
            frame.pinOffset = nil
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
        if pinned then
            -- The end-of-bar animation resizes and fades icons; a waiting icon must stay normal-sized and opaque.
            frame:SetWidth(iconsize)
            frame:SetHeight(iconsize)
            frame:SetAlpha(1)
        end
    end

    if not isactive and not CoolLine.unlock then
        CoolLine:SetAlpha(db.inactivealpha)
    end
end

RefreshCooldownDisplay = function()
    local hasLegacyCooldowns = false
    for _, frame in pairs(cooldowns) do
        CoolLine:SyncTimelineEvent(frame)
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
        -- Native-only cooldowns keep a slow OnUpdate for their expiry sweep.
        CoolLine:SetScript("OnUpdate", #cooldowns > 0 and OnUpdate or nil)
        CoolLine:SetAlpha(CoolLine.unlock and db.activealpha
            or (NativeTimelineEnabled() and 0 or db.inactivealpha))
    end
end
CoolLine.RefreshCooldownDisplay = RefreshCooldownDisplay

local function NewCooldownClassic(name, icon, endtime, isplayer, spellID, source, estimated, durationObject)
    if not name or not icon or not endtime then
        
        CoolLine:LogCooldownDebug("create:classic-invalid:" .. tostring(spellID or name),
            "NewCooldownClassic received missing parameters (name: " .. tostring(name)
                .. ", icon: " .. tostring(icon) .. ", end time: " .. tostring(endtime)
                .. ", is player: " .. tostring(isplayer) .. ", spell ID: "
                .. tostring(spellID) .. ").")
        
        return
    end
    -- print("CoolLine: NewCooldownClassic called with parameters:", name, icon, endtime, isplayer, spellID)
    source = source or (isplayer and "player") or (spellID and "pet") or "item"
    local frame
    for index, existing_frame in pairs(cooldowns) do
        if existing_frame.name == name and existing_frame.source == source then
            frame = existing_frame
            break
        elseif not CoolLine.IS_FOREVER and not estimated
            and existing_frame.endtime == endtime and existing_frame.source == source then
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

    frame.name, frame.endtime, frame.isplayer, frame.spellID, frame.iconTexture =
        name, endtime, isplayer, spellID, icon
    frame.source = source
    frame.estimated = estimated or nil
    if not estimated then
        frame.confirmedAt = nil
    end
    frame.icon:SetTexture(icon)
    if estimated then
        if not frame.estimateLabel then
            frame.estimateLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            frame.estimateLabel:SetPoint("TOPLEFT", frame, "TOPLEFT")
            frame.estimateLabel:SetText("?")
        end
        frame.estimateLabel:Show()
        if durationObject then
            if not frame.secretCooldown then
                frame.secretCooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
                frame.secretCooldown:SetAllPoints(frame)
                frame.secretCooldown:SetDrawEdge(false)
                frame.secretCooldown:SetDrawBling(false)
                -- The estimated position and the game's exact countdown would disagree.
                frame.secretCooldown:SetHideCountdownNumbers(true)
                frame.secretCooldown:SetScript("OnCooldownDone", function()
                    -- The game's own countdown just ended: ask it right away instead of waiting for the throttle,
                    -- but never faster than every 0.2 s in case the game keeps reporting the cooldown as active.
                    local ctime = GetTime()
                    if CoolLine.ScanCooldownsNow and ctime - (CoolLine.lastDoneScan or 0) >= 0.2 then
                        CoolLine.lastDoneScan = ctime
                        CoolLine:ScanCooldownsNow()
                    elseif CoolLine.RequestCooldownRecheck then
                        CoolLine:RequestCooldownRecheck()
                    end
                end)
            end
            frame.secretCooldown:SetCooldownFromDurationObject(durationObject)
            frame.secretCooldown:Show()
        elseif frame.secretCooldown then
            frame.secretCooldown:Hide()
        end
    else
        if frame.estimateLabel then
            frame.estimateLabel:Hide()
        end
        if frame.secretCooldown then
            frame.secretCooldown:Hide()
        end
    end
    SyncTimelineEvent(frame)

    local c = db[isplayer and "spellcolor" or "nospellcolor"]
    frame:SetBackdropColor(c.r, c.g, c.b, c.a)
    RefreshCooldownDisplay()
end

local function NewCooldownRetail(name, icon, remaining_duration, isplayer, spellID, source)
    --name, id, duration, btype == BOOKTYPE_SPELL
    source = source or (isplayer and "player") or (spellID and "pet") or "item"
    if CoolLine:IsSecretValueCompat(remaining_duration) then
        
        CoolLine:LogCooldownDebug("create:" .. source .. ":" .. tostring(spellID or name),
            "Skipped " .. source .. " cooldown with a secret remaining duration (spell ID: "
                .. tostring(spellID or "unknown") .. ").")
        
        return
    end
    
    CoolLine:LogCooldownDebug("create:" .. source .. ":" .. tostring(spellID or name),
        "Received a readable " .. source .. " cooldown (spell ID: "
            .. tostring(spellID or "unknown") .. ").")
    
    if not name or not icon or not remaining_duration then
        
        CoolLine:LogCooldownDebug("create:invalid:" .. tostring(spellID or name),
            "NewCooldownRetail received missing parameters (name: " .. tostring(name)
                .. ", icon: " .. tostring(icon) .. ", remaining duration: "
                .. tostring(remaining_duration) .. ", is player: " .. tostring(isplayer)
                .. ", spell ID: " .. tostring(spellID) .. ").")
        
        return
    end
    -- print("CoolLine: NewCooldownRetail called with parameters:", name, icon, endtime, isplayer, spellID)
    local f
    for index, frame in pairs(cooldowns) do
        if frame.name == name and frame.source == source then
            f = frame
            break
        -- elseif frame.endtime == endtime then
        --     return
        end
    end
    local previousRemaining = f and f.remaining_duration
    local previousSample = f and f.cooldownSampleTime
    if previousRemaining and previousSample then
        local expectedRemaining = previousRemaining - (GetTime() - previousSample)
        if remaining_duration > expectedRemaining + 2 then
            
            CoolLine:LogCooldownDebug("timeline-restart:" .. source .. ":" .. tostring(spellID or name),
                "Cooldown for " .. tostring(name) .. " restarted or was extended; replacing its Blizzard timeline event.")
            
            CoolLine:CancelTimelineEvent(f)
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

    f.name, f.remaining_duration, f.isplayer, f.spellID, f.iconTexture =
        name, remaining_duration, isplayer, spellID, icon
    f.source = source
    f.estimated = nil
    if f.estimateLabel then
        f.estimateLabel:Hide()
    end
    if f.secretCooldown then
        f.secretCooldown:Hide()
    end
    f.cooldownSampleTime = GetTime()
    f.icon:SetTexture(icon)
    SyncTimelineEvent(f)

    local c = db[isplayer and "spellcolor" or "nospellcolor"]
    f:SetBackdropColor(c.r, c.g, c.b, c.a)
    RefreshCooldownDisplay()
end

CoolLine.NewCooldownClassic, CoolLine.ClearCooldown, CoolLine.NewCooldownRetail = NewCooldownClassic, ClearCooldown, NewCooldownRetail
CoolLine.IconBackdrop = iconback

local function CooldownTimingReadable(source, start, duration, enabled)
    if CoolLine:IsSecretValueCompat(start) or CoolLine:IsSecretValueCompat(duration)
        or CoolLine:IsSecretValueCompat(enabled) then
        --@debug@
        CoolLine:LogCooldownDebug("secret-" .. source,
            "Cannot update " .. source .. " cooldown: timing or enabled state is secret.")
        --@end-debug@
        return false
    end
    return true
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
            if CooldownTimingReadable("equipped-item", start, duration, enable)
                and enable == 1 and start and duration then
                --local name = GetItemInfo(GetInventoryItemLink("player", i))
                local link = GetInventoryItemLink("player", i)
                local name = link and GetItemInfo(link)
                if start > 0 and not self:IsBlocked(name, GetInventoryItemID and GetInventoryItemID("player", i)) then -- 'and name' ?
                    if duration > DEFAULT_RETAIL_GCD_DURATION_S and duration < DEFAULT_RETAIL_MAX_DURATION_S then
                        local texture = GetInventoryItemTexture("player", i)
                        -- print("CoolLine: Adding cooldown for item:", name, "Texture:", texture, "Start:", start, "Duration:", duration)
                        local itemID = GetInventoryItemID and GetInventoryItemID("player", i)
                        NewCooldownClassic(name, texture, start + duration, false,
                            self:GetItemSpellIDCompat(itemID), "item")
                    end
                else
                    ClearCooldown(nil, name, "item")
                end

            end
        end
        -- scan bags
        for i = 0, (db.hidebag and -1) or maxBagSlots do
            local numSlots = GetContainerNumSlots(i) or 0
            for j = 1, numSlots do
                local start, duration, enable = CoolLine:GetContainerItemCooldownCompat(i, j)
                if CooldownTimingReadable("bag-item", start, duration, enable)
                    and enable == 1 and start and duration then
                    --local name = GetItemInfo(GetContainerItemLink(i, j))
                    local link = GetContainerItemLink(i, j)
                    local name = link and GetItemInfo(link)
                    if start > 0 and not self:IsBlocked(name, self:GetContainerItemIDCompat(i, j)) then
                        if duration > DEFAULT_RETAIL_GCD_DURATION_S and duration < DEFAULT_RETAIL_MAX_DURATION_S then
                            -- NewCooldown(name, GetContainerItemInfo(i, j), start + duration)
                            local texture = CoolLine:GetContainerItemIconCompat(i, j)
                            -- print("CoolLine: Adding cooldown for bag item:", name, "Texture:", texture, "Start:", start, "Duration:", duration) 
                            local itemID = self:GetContainerItemIDCompat(i, j)
                            NewCooldownClassic(name, texture, start + duration, false,
                                self:GetItemSpellIDCompat(itemID), "item")
                        end
                    else
                        ClearCooldown(nil, name, "item")
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
        if CooldownTimingReadable("pet-action", start, duration, enable)
            and enable == 1 and start and duration then
            -- Every declared client returns name, texture, isToken (checked in each client's PetActionBar source).
            local name, texture, isToken = GetPetActionInfo(i)
            if isToken and texture then
                texture = _G[texture] or texture
            end
            if name then
                if start > 0 and not self:IsBlocked(name) then
                    if duration > DEFAULT_RETAIL_GCD_DURATION_S then
                        -- print("CoolLine: Adding cooldown for pet action:", name, "Texture:", texture, "Start:", start, "Duration:", duration)
                        NewCooldownClassic(name, texture, start + duration, false, nil, "pet")
                    end
                else
                    ClearCooldown(nil, name, "pet")
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
            if CooldownTimingReadable("vehicle-action", start, duration, enable)
                and enable == 1 and start and duration then
                local _, actionID = GetActionInfo(b.action)
                if start > 0 and not self:IsBlocked(nil, actionID) then
                    if duration > DEFAULT_RETAIL_GCD_DURATION_S then
                        NewCooldownClassic("vehicle" .. i, GetActionTexture(b.action), start + duration,
                            false, nil, "vehicle")
                    end
                else
                    ClearCooldown(nil, "vehicle" .. i, "vehicle")
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
    -- Backwards: ClearCooldown removes the frame from the list being walked.
    for i = #cooldowns, 1, -1 do
        local frame = cooldowns[i]
        if frame and frame.source == "vehicle" then
            ClearCooldown(nil, frame.name, "vehicle")
        end
    end
end

local failborder
----------------------------------------------------
-- Every declared client sends (unit, castGUID, spellID): the second argument is a GUID, never a spell name.
function CoolLine:UNIT_SPELLCAST_FAILED(unit, castGUID, spellID)
    ----------------------------------------------------
    if #cooldowns == 0 or type(spellID) ~= "number" then
        return
    end
    local spell = self:GetSpellInfoCompat(spellID)
    if not spell then
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
