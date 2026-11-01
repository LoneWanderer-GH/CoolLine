local addonName = ...
local CoolLineApp = LibStub("AceAddon-3.0"):GetAddon(addonName)
local CoolLine = CoolLineApp.MainFrame
local AceConfig = LibStub("AceConfig-3.0")
local AceConfigDialog = LibStub("AceConfigDialog-3.0")
local smed = LibStub("LibSharedMedia-3.0")

local function mediaValues(kind)
    local values = {}
    for _, name in ipairs(smed:List(kind)) do
        values[name] = name
    end
    return values
end

local function refresh(rescanSources)
    if CoolLine.updatelook then
        CoolLine.updatelook()
    end
    if CoolLine.SPELL_UPDATE_COOLDOWN then
        CoolLine:SPELL_UPDATE_COOLDOWN()
    end
    if rescanSources and CoolLine.BAG_UPDATE_COOLDOWN and CoolLine.db
        and not (CoolLine.db.hidebag and CoolLine.db.hideinv) then
        CoolLine:BAG_UPDATE_COOLDOWN()
    end
    if rescanSources and CoolLine.PET_BAR_UPDATE_COOLDOWN
        and CoolLine.db and not CoolLine.db.hidepet then
        CoolLine:PET_BAR_UPDATE_COOLDOWN()
    end
end

local function optionGet(info)
    return CoolLine.db[info[#info]]
end

local function optionSet(info, value)
    local key = info[#info]
    if key == "vertical" and CoolLine.db.vertical ~= value then
        CoolLine.db.w, CoolLine.db.h = CoolLine.db.h, CoolLine.db.w
    end
    CoolLine.db[key] = value
    if key == "perchar" then
        if value then
            CoolLineCharDB = CoolLineCharDB or CoolLineDB
        else
            CoolLineCharDB = nil
        end
        ReloadUI()
        return
    end
    refresh()
end

local function colorGet(info)
    local color = CoolLine.db[info[#info]]
    return color.r, color.g, color.b, color.a
end

local function colorSet(info, red, green, blue, alpha)
    local color = CoolLine.db[info[#info]]
    color.r, color.g, color.b, color.a = red, green, blue, alpha or 1
    refresh()
end

function CoolLine:SetBlockedFilter(name, blocked)
    if type(name) ~= "string" or name == "" then
        return
    end
    name = name:match("^%s*(.-)%s*$")
    local linkName = name:match("|h%[(.+)%]|h")
    name = linkName or name
    if name == "" then
        return
    end
    if blocked then
        self.db.block[name] = true
    else
        self.db.block[name] = nil
    end
    --@debug@
    CoolLineApp:Debug("Options", "Updated cooldown blacklist")
    --@end-debug@
    refresh(true)
end

function CoolLine:OpenOptions()
    AceConfigDialog:Open("CoolLineOptions")
end

function CoolLine:ToggleUnlock()
    if not self.resizer then
        self:SetResizable(true)
        local wrapperLoaded = self:IsAddonLoadedCompat("ElvUI_CoolLine_Wrapper")
        self:SetMovable(not wrapperLoaded)
        if not wrapperLoaded then
            self:RegisterForDrag("LeftButton")
        end
        self:SetScript("OnMouseUp", function(_, button)
            if button == "RightButton" then
                self:OpenOptions()
            end
        end)
        if not wrapperLoaded then
            self:SetScript("OnDragStart", function(frame)
                frame:StartMoving()
            end)
            self:SetScript("OnDragStop", function(frame)
                frame:StopMovingOrSizing()
                local x, y = frame:GetCenter()
                local parentX, parentY = UIParent:GetCenter()
                self.db.x, self.db.y = floor(x - parentX + 0.5), floor(y - parentY + 0.5)
                frame:ClearAllPoints()
                self.updatelook()
            end)
        end

        self:SetMinResize(6, 6)
        self.resizer = CreateFrame("Button", nil, self.border, "UIPanelButtonTemplate")
        self.resizer:SetSize(8, 8)
        self.resizer:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", 2, -2)
        self.resizer:SetScript("OnMouseDown", function()
            self:StartSizing("BOTTOMRIGHT")
        end)
        self.resizer:SetScript("OnMouseUp", function()
            self:StopMovingOrSizing()
            self.db.w, self.db.h = floor(self:GetWidth() + 0.5), floor(self:GetHeight() + 0.5)
            self.updatelook()
        end)
    end

    self.unlock = not self.unlock
    self:EnableMouse(self.unlock)
    if self.unlock then
        self.resizer:Show()
        self:SetAlpha(self.db.activealpha)
        print("CoolLine: drag to move; drag the corner to resize")
    else
        self.resizer:Hide()
        self.updatelook()
    end
end

function CoolLine:SetupOptions()
    local timelineDisabled = function()
        return not (C_EncounterTimeline and C_EncounterTimeline.IsFeatureAvailable
            and C_EncounterTimeline.IsFeatureAvailable())
    end
    local options = {
        type = "group",
        name = "CoolLine",
        desc = "Compatibility reports and bug reports: https://github.com/LoneWanderer-GH/CoolLine/issues",
        args = {
            timeline = {
                type = "group",
                name = "Timeline",
                order = 1,
                args = {
                    legacyTimeline = {
                        type = "toggle",
                        name = "Show CoolLine timeline",
                        desc = "Show cooldowns in CoolLine's original bar when they are not routed to Blizzard's timeline.",
                        get = optionGet,
                        set = optionSet,
                        order = 1,
                    },
                    blizzardTimeline = {
                        type = "toggle",
                        name = "Use Blizzard encounter timeline",
                        desc = "Route selected cooldown sources to Blizzard's encounter timeline when it is available and enabled.",
                        get = optionGet,
                        set = optionSet,
                        disabled = timelineDisabled,
                        order = 2,
                    },
                    timelinePlayer = {
                        type = "toggle",
                        name = "Player spells",
                        desc = "Route player spell cooldowns to the Blizzard timeline.",
                        get = optionGet,
                        set = optionSet,
                        disabled = function()
                            return timelineDisabled() or not CoolLine.db.blizzardTimeline
                        end,
                        order = 3,
                    },
                    timelinePet = {
                        type = "toggle",
                        name = "Pet spells",
                        desc = "Route pet spellbook cooldowns to the Blizzard timeline when a spell ID is available.",
                        get = optionGet,
                        set = optionSet,
                        disabled = function()
                            return timelineDisabled() or not CoolLine.db.blizzardTimeline
                        end,
                        order = 4,
                    },
                    timelineItem = {
                        type = "toggle",
                        name = "Items",
                        desc = "Route item cooldowns to the Blizzard timeline when the item's use spell can be identified.",
                        get = optionGet,
                        set = optionSet,
                        disabled = function()
                            return timelineDisabled() or not CoolLine.db.blizzardTimeline
                        end,
                        order = 5,
                    },
                },
            },
            display = {
                type = "group",
                name = "Display",
                order = 2,
                args = {
                    statusbar = {
                        type = "select",
                        name = "Texture",
                        values = function() return mediaValues("statusbar") end,
                        get = optionGet,
                        set = optionSet,
                        order = 1,
                    },
                    border = {
                        type = "select",
                        name = "Border",
                        values = function() return mediaValues("border") end,
                        get = optionGet,
                        set = optionSet,
                        order = 2,
                    },
                    font = {
                        type = "select",
                        name = "Font",
                        values = function() return mediaValues("font") end,
                        get = optionGet,
                        set = optionSet,
                        order = 3,
                    },
                    width = {
                        type = "range",
                        name = "Width",
                        min = 50,
                        max = 1000,
                        step = 1,
                        get = function() return CoolLine.db.w end,
                        set = function(_, value)
                            CoolLine.db.w = value
                            refresh()
                        end,
                        order = 4,
                    },
                    height = {
                        type = "range",
                        name = "Height",
                        min = 6,
                        max = 200,
                        step = 1,
                        get = function() return CoolLine.db.h end,
                        set = function(_, value)
                            CoolLine.db.h = value
                            refresh()
                        end,
                        order = 5,
                    },
                    fontsize = {
                        type = "range",
                        name = "Font size",
                        min = 5,
                        max = 28,
                        step = 1,
                        get = optionGet,
                        set = optionSet,
                        order = 6,
                    },
                    iconplus = {
                        type = "range",
                        name = "Icon size adjustment",
                        min = 0,
                        max = 24,
                        step = 2,
                        get = optionGet,
                        set = optionSet,
                        order = 7,
                    },
                    bordersize = {
                        type = "range",
                        name = "Border size",
                        min = 1,
                        max = 16,
                        step = 1,
                        get = optionGet,
                        set = optionSet,
                        order = 8,
                    },
                    borderinset = {
                        type = "range",
                        name = "Border inset",
                        min = -10,
                        max = 10,
                        step = 1,
                        get = optionGet,
                        set = optionSet,
                        order = 9,
                    },
                    inactivealpha = {
                        type = "range",
                        name = "Inactive opacity",
                        min = 0,
                        max = 1,
                        step = 0.1,
                        get = optionGet,
                        set = optionSet,
                        order = 10,
                    },
                    activealpha = {
                        type = "range",
                        name = "Active opacity",
                        min = 0,
                        max = 1,
                        step = 0.1,
                        get = optionGet,
                        set = optionSet,
                        order = 11,
                    },
                    vertical = {
                        type = "toggle",
                        name = "Vertical",
                        get = optionGet,
                        set = optionSet,
                        order = 12,
                    },
                    reverse = {
                        type = "toggle",
                        name = "Reverse direction",
                        get = optionGet,
                        set = optionSet,
                        order = 13,
                    },
                    bgcolor = {
                        type = "color",
                        name = "Texture color",
                        hasAlpha = true,
                        get = colorGet,
                        set = colorSet,
                        order = 14,
                    },
                    bordercolor = {
                        type = "color",
                        name = "Border color",
                        hasAlpha = true,
                        get = colorGet,
                        set = colorSet,
                        order = 15,
                    },
                    fontcolor = {
                        type = "color",
                        name = "Font color",
                        hasAlpha = true,
                        get = colorGet,
                        set = colorSet,
                        order = 16,
                    },
                    spellcolor = {
                        type = "color",
                        name = "Spell color",
                        hasAlpha = true,
                        get = colorGet,
                        set = colorSet,
                        order = 17,
                    },
                    nospellcolor = {
                        type = "color",
                        name = "Item/pet color",
                        hasAlpha = true,
                        get = colorGet,
                        set = colorSet,
                        order = 18,
                    },
                },
            },
            filters = {
                type = "group",
                name = "Cooldown blacklist",
                order = 3,
                args = {
                    description = {
                        type = "description",
                        name = "Blocked cooldowns are hidden from the CoolLine bar and are not routed to the Blizzard timeline.",
                        order = 1,
                    },
                    add = {
                        type = "input",
                        name = "Add spell or item name/ID",
                        get = function() return CoolLine.pendingFilter or "" end,
                        set = function(_, value)
                            CoolLine:SetBlockedFilter(value, true)
                            CoolLine.pendingFilter = ""
                        end,
                        order = 2,
                    },
                    entries = {
                        type = "multiselect",
                        name = "Blocked entries",
                        values = function()
                            local values = {}
                            for name in pairs(CoolLine.db.block) do
                                values[name] = name
                            end
                            return values
                        end,
                        get = function(_, name)
                            return CoolLine.db.block[name] == true
                        end,
                        set = function(_, name, blocked)
                            CoolLine:SetBlockedFilter(name, blocked)
                        end,
                        order = 3,
                    },
                },
            },
            behavior = {
                type = "group",
                name = "Behavior",
                order = 4,
                args = {
                    hidefail = {
                        type = "toggle",
                        name = "Disable cast-fail flash",
                        get = optionGet,
                        set = optionSet,
                        order = 1,
                    },
                    hideinv = {
                        type = "toggle",
                        name = "Hide equipped-item cooldowns",
                        get = optionGet,
                        set = optionSet,
                        order = 2,
                    },
                    hidebag = {
                        type = "toggle",
                        name = "Hide bag-item cooldowns",
                        get = optionGet,
                        set = optionSet,
                        order = 3,
                    },
                    hidepet = {
                        type = "toggle",
                        name = "Hide pet cooldowns",
                        get = optionGet,
                        set = optionSet,
                        order = 4,
                    },
                    perchar = {
                        type = "toggle",
                        name = "Save settings per character",
                        get = optionGet,
                        set = optionSet,
                        order = 5,
                    },
                    unlock = {
                        type = "execute",
                        name = "Unlock / resize",
                        func = function() CoolLine:ToggleUnlock() end,
                        order = 6,
                    },
                    reset = {
                        type = "execute",
                        name = RESET_TO_DEFAULT,
                        confirm = true,
                        func = function()
                            CoolLineCharDB, CoolLineDB = nil, nil
                            ReloadUI()
                        end,
                        order = 7,
                    },
                },
            },
        },
    }

    AceConfig:RegisterOptionsTable("CoolLineOptions", options)
    AceConfigDialog:AddToBlizOptions("CoolLineOptions", "CoolLine")
end
