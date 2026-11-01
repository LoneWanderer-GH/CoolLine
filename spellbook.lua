local addonName = ...
local CoolLine = LibStub("AceAddon-3.0"):GetAddon(addonName).MainFrame

local IS_RETAIL_RELEASE = CoolLine.IS_RETAIL_RELEASE
local BOOKTYPE_SPELL = CoolLine.BOOKTYPE_SPELL
local BOOKTYPE_PET = CoolLine.BOOKTYPE_PET
local DEFAULT_RETAIL_GCD_DURATION_S = CoolLine.DEFAULT_RETAIL_GCD_DURATION_S
local MINIMUM_COOLDOWN_DURATION_MS = CoolLine.MINIMUM_COOLDOWN_DURATION_MS
local spells = CoolLine.spells
local chargespells = CoolLine.chargespells
local cooldowns = CoolLine.cooldowns
local ClearCooldown = function(...)
    return CoolLine.ClearCooldown(...)
end
local NewCooldownClassic = function(...)
    return CoolLine.NewCooldownClassic(...)
end
local NewCooldownRetail = function(...)
    return CoolLine.NewCooldownRetail(...)
end

do
    local function CacheBook(btype)
        local spellBook = C_SpellBook
        if spellBook and spellBook.GetNumSpellBookSkillLines and spellBook.GetSpellBookSkillLineInfo
            and spellBook.GetSpellBookItemInfo then
            local function CacheSpell(spellID, spellName)
                if not spellID then
                    return
                end
                if C_Spell and C_Spell.RequestLoadSpellData then
                    C_Spell.RequestLoadSpellData(spellID)
                end
                if not spellName then
                    spellName = CoolLine:GetSpellInfoCompat(spellID)
                end

                local resolvedName, _, _, _, _, _, resolvedSpellID = CoolLine:GetSpellInfoCompat(spellID)
                spellID = resolvedSpellID or spellID
                spellName = resolvedName or spellName

                local _, maxCharges = CoolLine:GetSpellChargesCompat(spellID)
                if maxCharges and maxCharges > 0 then
                    chargespells[btype][spellID] = spellName or tostring(spellID)
                else
                    local cooldown = CoolLine:GetSpellBaseCooldownCompat(spellID)
                    if cooldown == nil or cooldown > MINIMUM_COOLDOWN_DURATION_MS then
                        spells[btype][spellID] = spellName or tostring(spellID)
                    end
                end
            end

            local function CacheSlot(slot)
                local itemInfo = spellBook.GetSpellBookItemInfo(slot, btype)
                if itemInfo and itemInfo.spellID then
                    CacheSpell(itemInfo.spellID, itemInfo.name)
                end
            end

            if btype == BOOKTYPE_PET then
                local numPetSpells = spellBook.HasPetSpells and spellBook.HasPetSpells() or 0
                for slot = 1, numPetSpells do
                    CacheSlot(slot)
                end
            else
                for skillLine = 1, spellBook.GetNumSpellBookSkillLines() do
                    local skillLineInfo = spellBook.GetSpellBookSkillLineInfo(skillLine)
                    if skillLineInfo and not skillLineInfo.shouldHide then
                        local firstSlot = skillLineInfo.itemIndexOffset + 1
                        local lastSlot = skillLineInfo.itemIndexOffset + skillLineInfo.numSpellBookItems
                        for slot = firstSlot, lastSlot do
                            CacheSlot(slot)
                        end
                    end
                end
            end
            return
        end

        local lastID
        local sb = spells[btype]
        local _, numTabs
        numTabs = GetNumSpellTabs()
        for i = 1, numTabs do
            local _, _, offset, numSpells = GetSpellTabInfo(i)
            for j = 1, offset + numSpells do
                local spellName = CoolLine:GetSpellBookItemNameCompat(j, btype)
                if not spellName then
                    break
                end
                local spellType, spellID = CoolLine:GetSpellBookItemInfoCompat(j, btype)
                if IS_RETAIL_RELEASE and spellID and spellType == "FLYOUT" then
                    local _, _, numSlots, isKnown = GetFlyoutInfo(spellID)
                    if isKnown then
                        for k = 1, numSlots do
                            local flyID, _, _, flyName = GetFlyoutSlotInfo(spellID, k)
                            lastID = flyID
                            if flyID then
                                local flyCD = CoolLine:GetSpellBaseCooldownCompat(flyID)
                                if flyCD and flyCD > MINIMUM_COOLDOWN_DURATION_MS then
                                    sb[flyID] = flyName
                                end
                            end
                        end
                    end
                elseif spellID and (spellType == "SPELL" or spellType == "PETACTION") and spellID ~= lastID then
                    lastID = spellID
                    spellName, _, _, _, _, _, spellID = CoolLine:GetSpellInfoCompat(spellName)
                    if spellID then
                        local _, maxCharges = CoolLine:GetSpellChargesCompat(spellID)
                        if maxCharges and maxCharges > 0 then
                            chargespells[btype][spellID] = spellName
                        else
                            local cooldown = CoolLine:GetSpellBaseCooldownCompat(spellID)
                            if cooldown and cooldown > MINIMUM_COOLDOWN_DURATION_MS then
                                sb[spellID] = spellName
                            end
                        end
                    end
                end
            end
        end
    end

    function CoolLine:SPELLS_CHANGED()
        CacheBook(BOOKTYPE_SPELL)
        if not self.db.hidepet then
            CacheBook(BOOKTYPE_PET)
        end
    end
end

do
    local elapsed = 0
    local spellThrottle = CreateFrame("Frame", nil, CoolLine)

    local function SyncTimelineEvent(frame)
        CoolLine:SyncTimelineEvent(frame)
    end

    local function CheckSpellBookLegacy(btype)
        local source = btype == BOOKTYPE_SPELL and "player" or "pet"
        for id, name in pairs(spells[btype]) do
            local start, duration, enable = CoolLine:GetSpellCooldownCompat(id)
            if enable == 1 and start > 0 and not CoolLine:IsBlocked(name, id)
                and (not CoolLine.RuneCheck or CoolLine.RuneCheck(name, duration)) then
                if duration > DEFAULT_RETAIL_GCD_DURATION_S then
                    local _, _, texture = CoolLine:GetSpellInfoCompat(id)
                    NewCooldownClassic(name, texture, start + duration, btype == BOOKTYPE_SPELL, id, source)
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
                ClearCooldown(nil, name, source)
            end
        end

        for id, name in pairs(chargespells[btype]) do
            local currentCharges, maxCharges, cooldownStart, cooldownDuration = CoolLine:GetSpellChargesCompat(id)
            if cooldownStart and cooldownDuration and currentCharges < maxCharges and not CoolLine:IsBlocked(name, id) then
                local _, _, texture = CoolLine:GetSpellInfoCompat(id)
                NewCooldownClassic(name, texture, cooldownStart + cooldownDuration, btype == BOOKTYPE_SPELL, id, source)
            else
                ClearCooldown(nil, name, source)
            end
        end
    end

    local function CheckSpellBookRetail(btype)
        local source = btype == BOOKTYPE_SPELL and "player" or "pet"
        for id, name in pairs(spells[btype]) do
            local remaining = CoolLine:GetSpellCooldownDurationCompat(id)
            if not CoolLine:IsSecretValueCompat(remaining) then
                if remaining and remaining > DEFAULT_RETAIL_GCD_DURATION_S and not CoolLine:IsBlocked(name, id) then
                    local _, _, texture = CoolLine:GetSpellInfoCompat(id)
                    NewCooldownRetail(name, texture, remaining, btype == BOOKTYPE_SPELL, id, source)
                else
                    ClearCooldown(nil, name, source)
                end
            end
        end

        for id, name in pairs(chargespells[btype]) do
            local remaining = CoolLine:GetSpellChargeDurationCompat(id)
            if not CoolLine:IsSecretValueCompat(remaining) then
                if remaining and remaining > DEFAULT_RETAIL_GCD_DURATION_S and not CoolLine:IsBlocked(name, id) then
                    local _, _, texture = CoolLine:GetSpellInfoCompat(id)
                    NewCooldownRetail(name, texture, remaining, btype == BOOKTYPE_SPELL, id, source)
                else
                    ClearCooldown(nil, name, source)
                end
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

    spellThrottle:SetScript("OnUpdate", function(this, delta)
        elapsed = elapsed + delta
        if elapsed < 0.3 then
            return
        end
        elapsed = 0
        this:Hide()
        CheckSpellBook(BOOKTYPE_SPELL)
        if not CoolLine.db.hidepet and HasPetUI() then
            CheckSpellBook(BOOKTYPE_PET)
        end
    end)

    spellThrottle:Hide()

    function CoolLine:SPELL_UPDATE_COOLDOWN()
        spellThrottle:Show()
    end

    function CoolLine:ENCOUNTER_TIMELINE_STATE_UPDATED()
        CoolLine.RefreshCooldownDisplay()
    end
end
