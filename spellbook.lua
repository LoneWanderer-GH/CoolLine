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
local estimatedDurations = { [BOOKTYPE_SPELL] = {}, [BOOKTYPE_PET] = {} }
-- Start time of the cooldown currently shown for a spell, when known (readable or observed cast).
local knownStarts = { [BOOKTYPE_SPELL] = {}, [BOOKTYPE_PET] = {} }
local GetTime = GetTime
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
    local lastSeen = { [BOOKTYPE_SPELL] = {}, [BOOKTYPE_PET] = {} }

    local function SameSet(a, b)
        for id in pairs(a) do
            if not b[id] then
                return false
            end
        end
        for id in pairs(b) do
            if not a[id] then
                return false
            end
        end
        return true
    end

    -- Drops tracking and cooldown icons of spells that left the spellbook (respec, talent swap), and
    -- invalidates observed durations since talents change them. An empty book is a transient state, and
    -- SPELLS_CHANGED also fires without any change of the spell set (forms, overrides): keep what was learned then.
    local function FinishCache(btype, seen)
        if not next(seen) then
            return
        end
        local source = btype == BOOKTYPE_SPELL and "player" or "pet"
        for id in pairs(spells[btype]) do
            if not seen[id] then
                spells[btype][id] = nil
            end
        end
        for id in pairs(chargespells[btype]) do
            if not seen[id] then
                chargespells[btype][id] = nil
            end
        end
        if not SameSet(seen, lastSeen[btype]) then
            for id in pairs(estimatedDurations[btype]) do
                estimatedDurations[btype][id] = nil
            end
            for id in pairs(knownStarts[btype]) do
                knownStarts[btype][id] = nil
            end
        end
        lastSeen[btype] = seen
        for i = #cooldowns, 1, -1 do
            local frame = cooldowns[i]
            local id = frame.spellID
            if id and frame.source == source and not spells[btype][id] and not chargespells[btype][id] then
                ClearCooldown(nil, frame.name, source)
            end
        end
    end

    local function CacheBook(btype)
        local seen = {}
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
                seen[spellID] = true

                spells[btype][spellID] = nil
                chargespells[btype][spellID] = nil
                local _, maxCharges = CoolLine:GetSpellChargesCompat(spellID)
                if CoolLine:IsSecretValueCompat(maxCharges) then
                    chargespells[btype][spellID] = spellName or tostring(spellID)
                    
                    CoolLine:LogCooldownDebug("cache:" .. btype .. ":" .. tostring(spellID),
                        "Tracking charge cooldown for " .. (spellName or tostring(spellID))
                            .. "; maximum charge count is secret (ID " .. tostring(spellID) .. ").")
                    
                elseif maxCharges and maxCharges > 0 then
                    chargespells[btype][spellID] = spellName or tostring(spellID)
                    
                    CoolLine:LogCooldownDebug("cache:" .. btype .. ":" .. tostring(spellID),
                        "Tracking charge cooldown for " .. (spellName or tostring(spellID))
                            .. " (ID " .. tostring(spellID) .. ", max charges "
                            .. tostring(maxCharges) .. ").")
                    
                else
                    local cooldown = CoolLine:GetSpellBaseCooldownCompat(spellID)
                    if CoolLine:IsSecretValueCompat(cooldown) then
                        spells[btype][spellID] = spellName or tostring(spellID)
                        
                        CoolLine:LogCooldownDebug("cache:" .. btype .. ":" .. tostring(spellID),
                            "Kept " .. (spellName or tostring(spellID))
                                .. " in the cooldown scan: base cooldown is secret (ID "
                                .. tostring(spellID) .. ").")
                        
                    elseif cooldown == nil or cooldown > MINIMUM_COOLDOWN_DURATION_MS then
                        spells[btype][spellID] = spellName or tostring(spellID)
                        
                        CoolLine:LogCooldownDebug("cache:" .. btype .. ":" .. tostring(spellID),
                            "Tracking " .. (spellName or tostring(spellID))
                                .. " (ID " .. tostring(spellID) .. "); base cooldown "
                                .. (cooldown == nil and "unknown." or tostring(cooldown) .. " ms."))
                        
                    else
                        
                        CoolLine:LogCooldownDebug("cache:" .. btype .. ":" .. tostring(spellID),
                            "Skipped " .. (spellName or tostring(spellID))
                                .. " from cooldown scan: base cooldown is "
                                .. tostring(cooldown) .. " ms (ID " .. tostring(spellID) .. ").")
                        
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
            FinishCache(btype, seen)
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
                                seen[flyID] = true
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
                        seen[spellID] = true
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
        FinishCache(btype, seen)
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
    local spellThrottle = CreateFrame("Frame")
    local secretCandidates = { [BOOKTYPE_SPELL] = {}, [BOOKTYPE_PET] = {} }
    -- A cast observed this long after the icon's start means the cooldown was reset and started again.
    local RESTART_MIN_CAST_GAP_S = 3
    local lastCasts = {}

    -- Expert setting (see core.lua); stubs without the accessor get the built-in default.
    local function expert(key, default)
        if CoolLine.GetExpert then
            return CoolLine:GetExpert(key)
        end
        return default
    end
    local function ConfirmationTime()
        return expert("confirm", MINIMUM_COOLDOWN_DURATION_MS / 1000)
    end

    local function SyncTimelineEvent(frame)
        CoolLine:SyncTimelineEvent(frame)
    end

    -- When an estimated cooldown ends while its start is known, the game's own end teaches the real duration.
    -- Much shorter values are ignored: they are most likely a reset, not a new duration.
    local function LearnObservedDuration(btype, id, existing, isCharge, now)
        local start = knownStarts[btype][id]
        if not existing or not existing.estimated or isCharge or not start then
            return
        end
        local observed = now - start
        local previous = estimatedDurations[btype][id]
        if observed > DEFAULT_RETAIL_GCD_DURATION_S and (not previous or observed >= previous * 0.5) then
            estimatedDurations[btype][id] = observed
        end
    end

    -- Retail frames carry a remaining duration sampled at a given time instead of an end time.
    local function FrameEndTime(frame)
        if frame.endtime then
            return frame.endtime
        end
        if frame.remaining_duration then
            return (frame.cooldownSampleTime or GetTime()) + frame.remaining_duration
        end
    end

    local function ShowSecretCooldown(btype, id, name, isCharge, isCooldownEvent)
        local source = btype == BOOKTYPE_SPELL and "player" or "pet"
        local candidates = secretCandidates[btype]
        local starts = knownStarts[btype]
        if CoolLine:IsBlocked(name, id) then
            candidates[id] = nil
            starts[id] = nil
            ClearCooldown(nil, name, source)
            return
        end

        local now = GetTime()
        local existing
        for _, frame in pairs(cooldowns) do
            if frame.name == name and frame.source == source then
                existing = frame
                break
            end
        end
        local spellAPI = C_Spell
        local info
        if spellAPI then
            if isCharge and spellAPI.GetSpellCharges then
                info = spellAPI.GetSpellCharges(id)
            elseif not isCharge and spellAPI.GetSpellCooldown then
                info = spellAPI.GetSpellCooldown(id)
            end
        end
        if not info or CoolLine:IsSecretValueCompat(info.isActive)
            or type(info.isActive) ~= "boolean" then
            candidates[id] = nil
            -- The old end time is not re-injected: an icon the game stopped confirming must age out.
            if existing and now - math.max(FrameEndTime(existing) or 0, existing.confirmedAt or 0)
                > expert("orphan", 5) then
                starts[id] = nil
                ClearCooldown(nil, name, source)
            end
            --@debug@
            CoolLine:LogCooldownDebug("secret-unknown:" .. source .. ":" .. tostring(id),
                "Cannot determine whether " .. name .. " is active (ID " .. tostring(id) .. ").")
            --@end-debug@
            return
        end
        if not info.isActive then
            candidates[id] = nil
            LearnObservedDuration(btype, id, existing, isCharge, now)
            starts[id] = nil
            ClearCooldown(nil, name, source)
            return
        end
        local restartedAt
        local cast = lastCasts[id]
        local knownStart = starts[id]
        if existing and not isCharge and cast and knownStart and cast <= now
            and cast - knownStart > RESTART_MIN_CAST_GAP_S then
            restartedAt = cast
        end
        local candidateStart
        if not existing then
            if not isCharge and isCooldownEvent and not CoolLine:IsSecretValueCompat(info.isOnGCD)
                and info.isOnGCD == true then
                candidates[id] = nil
                spellThrottle:Show()
                return
            end
            local started = candidates[id]
            if not started then
                candidates[id] = now
                spellThrottle:Show()
                return
            elseif now - started < ConfirmationTime() then
                spellThrottle:Show()
                return
            end
            candidateStart = started
        end
        candidates[id] = nil

        local duration = estimatedDurations[btype][id]
        if not duration then
            local base = CoolLine:GetSpellBaseCooldownCompat(id)
            if not CoolLine:IsSecretValueCompat(base) and type(base) == "number"
                and base > MINIMUM_COOLDOWN_DURATION_MS then
                duration = base / 1000
            end
        end
        local fallback = expert("fallback", 30)
        local endtime
        if restartedAt then
            starts[id] = restartedAt
            endtime = restartedAt + (duration or fallback)
        elseif existing then
            local existingEnd = FrameEndTime(existing)
            if existingEnd and existingEnd > now then
                if not existing.estimated then
                    -- Timing was read exactly before the restriction and is still in the future: keep
                    -- the exact icon (and its native timeline event) instead of downgrading it.
                    return
                end
                endtime = existingEnd
            else
                -- The game still reports the cooldown as active although the end is past. The end is kept
                -- (the bar holds the icon at its hold point instead of pushing it back and forth) and the
                -- scan is recorded so the icon is not dropped as unconfirmed.
                endtime = existingEnd or now
                existing.confirmedAt = now
                if isCharge and duration and duration >= 1 then
                    -- Charges recharge one after another: the next recharge began when the previous one ended.
                    repeat
                        endtime = endtime + duration
                    until endtime > now
                end
            end
        else
            local castBefore = lastCasts[id]
            if castBefore and castBefore <= candidateStart
                and candidateStart - castBefore <= ConfirmationTime() + 3 then
                candidateStart = castBefore
            end
            starts[id] = candidateStart
            endtime = candidateStart + (duration or fallback)
        end
        local durationObject
        if isCharge and spellAPI.GetSpellChargeDuration then
            durationObject = spellAPI.GetSpellChargeDuration(id)
        elseif not isCharge and spellAPI.GetSpellCooldownDuration then
            durationObject = spellAPI.GetSpellCooldownDuration(id, true)
        end
        local _, _, texture = CoolLine:GetSpellInfoCompat(id)
        NewCooldownClassic(name, texture, endtime, btype == BOOKTYPE_SPELL, id, source, true, durationObject)
        --@debug@
        CoolLine:LogCooldownDebug("secret-legacy:" .. source .. ":" .. tostring(id),
            "Tracking " .. name .. " with an estimated position; cooldown timing is secret (ID "
                .. tostring(id) .. ").")
        --@end-debug@
    end

    local function CheckSpellBookWithLegacyAPI(btype, checkSecretValues, isCooldownEvent)
        local source = btype == BOOKTYPE_SPELL and "player" or "pet"
        for id, name in pairs(spells[btype]) do
            local start, duration, enable = CoolLine:GetSpellCooldownCompat(id)
            if checkSecretValues and (CoolLine:IsSecretValueCompat(start)
                or CoolLine:IsSecretValueCompat(duration) or CoolLine:IsSecretValueCompat(enable)
                or start == nil or duration == nil or enable == nil) then
                
                ShowSecretCooldown(btype, id, name, false, isCooldownEvent)
            else
                secretCandidates[btype][id] = nil
                if enable == 1 and start and duration and start > 0 and not CoolLine:IsBlocked(name, id)
                    and (not CoolLine.RuneCheck or CoolLine.RuneCheck(name, duration)) then
                    if duration > DEFAULT_RETAIL_GCD_DURATION_S then
                        if checkSecretValues then
                            estimatedDurations[btype][id] = duration
                            knownStarts[btype][id] = start
                        end
                        local _, _, texture = CoolLine:GetSpellInfoCompat(id)
                        NewCooldownClassic(name, texture, start + duration, btype == BOOKTYPE_SPELL, id, source)
                    elseif not checkSecretValues then
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
        end

        for id, name in pairs(chargespells[btype]) do
            local currentCharges, maxCharges, cooldownStart, cooldownDuration = CoolLine:GetSpellChargesCompat(id)
            if checkSecretValues and (CoolLine:IsSecretValueCompat(currentCharges)
                or CoolLine:IsSecretValueCompat(maxCharges) or CoolLine:IsSecretValueCompat(cooldownStart)
                or CoolLine:IsSecretValueCompat(cooldownDuration) or currentCharges == nil
                or maxCharges == nil or cooldownStart == nil or cooldownDuration == nil) then
                ShowSecretCooldown(btype, id, name, true, isCooldownEvent)
            else
                secretCandidates[btype][id] = nil
                if cooldownStart and cooldownDuration and currentCharges and maxCharges and currentCharges < maxCharges
                    and not CoolLine:IsBlocked(name, id) then
                    if checkSecretValues then
                        estimatedDurations[btype][id] = cooldownDuration
                    end
                    local _, _, texture = CoolLine:GetSpellInfoCompat(id)
                    NewCooldownClassic(name, texture, cooldownStart + cooldownDuration, btype == BOOKTYPE_SPELL, id, source)
                else
                    ClearCooldown(nil, name, source)
                end
            end
        end
    end

    -- A frame that already carries an end time (it was estimated) stays in end-time mode: NewCooldownRetail would
    -- leave that end time in place and the display would keep following it instead of the exact remaining time.
    local function ShowReadableRetailCooldown(name, texture, remaining, isplayer, id, source)
        for _, frame in pairs(cooldowns) do
            if frame.name == name and frame.source == source and frame.endtime then
                NewCooldownClassic(name, texture, GetTime() + remaining, isplayer, id, source)
                return
            end
        end
        NewCooldownRetail(name, texture, remaining, isplayer, id, source)
    end

    -- True when the last Retail scan met a secret value: events then deserve an immediate scan, because the
    -- global-cooldown state used to reject transient activity is only reliable while handling the event.
    local retailSawSecret = false

    local function CheckSpellBookRetail(btype, isCooldownEvent)
        local source = btype == BOOKTYPE_SPELL and "player" or "pet"
        for id, name in pairs(spells[btype]) do
            local remaining = CoolLine:GetSpellCooldownDurationCompat(id)
            if CoolLine:IsSecretValueCompat(remaining) then
                retailSawSecret = true
                CoolLine:LogCooldownDebug("secret:" .. source .. ":" .. tostring(id),
                    "Cooldown remaining duration is secret for " .. name .. "; estimating it (ID "
                        .. tostring(id) .. ", source " .. source .. ").")
                ShowSecretCooldown(btype, id, name, false, isCooldownEvent)
            else
                secretCandidates[btype][id] = nil
                if remaining and remaining > DEFAULT_RETAIL_GCD_DURATION_S then
                    if CoolLine:IsBlocked(name, id) then
                        
                        CoolLine:LogCooldownDebug("blocked:" .. source .. ":" .. tostring(id),
                            "Found cooldown for blacklisted " .. name .. " (ID " .. tostring(id) .. ").")
                        
                    else
                        
                        CoolLine:LogCooldownDebug("active:" .. source .. ":" .. tostring(id),
                            "Found active cooldown for " .. name .. " (ID " .. tostring(id) .. ").")
                        
                    end
                end
                if remaining and remaining > DEFAULT_RETAIL_GCD_DURATION_S and not CoolLine:IsBlocked(name, id) then
                    local _, _, texture = CoolLine:GetSpellInfoCompat(id)
                    ShowReadableRetailCooldown(name, texture, remaining, btype == BOOKTYPE_SPELL, id, source)
                else
                    knownStarts[btype][id] = nil
                    ClearCooldown(nil, name, source)
                end
            end
        end

        for id, name in pairs(chargespells[btype]) do
            local remaining = CoolLine:GetSpellChargeDurationCompat(id)
            local durationSource = "charge-duration API"
            local currentCharges, maxCharges, cooldownStart, cooldownDuration =
                CoolLine:GetSpellChargesCompat(id)
            local chargeInfoSecret = CoolLine:IsSecretValueCompat(currentCharges)
                or CoolLine:IsSecretValueCompat(maxCharges)
                or CoolLine:IsSecretValueCompat(cooldownStart)
                or CoolLine:IsSecretValueCompat(cooldownDuration)
            if chargeInfoSecret then
                
                CoolLine:LogCooldownDebug("secret-charge-info:" .. source .. ":" .. tostring(id),
                    "Could not read charge count or cooldown timing for " .. name
                        .. " (ID " .. tostring(id) .. ").")
                
            else
                
                CoolLine:LogCooldownDebug("charge-state:" .. source .. ":" .. tostring(id),
                    name .. " charge state (ID " .. tostring(id) .. "): "
                        .. tostring(currentCharges) .. "/" .. tostring(maxCharges)
                        .. " charges; cooldown start " .. tostring(cooldownStart)
                        .. ", duration " .. tostring(cooldownDuration) .. " s.")
                
                if not CoolLine:IsSecretValueCompat(remaining)
                    and (remaining == nil or remaining <= DEFAULT_RETAIL_GCD_DURATION_S)
                    and currentCharges and maxCharges and currentCharges < maxCharges
                    and cooldownStart and cooldownDuration and cooldownStart > 0 and cooldownDuration > 0 then
                    local chargeRemaining = cooldownStart + cooldownDuration - GetTime()
                    if chargeRemaining > DEFAULT_RETAIL_GCD_DURATION_S then
                        remaining = chargeRemaining
                        durationSource = "charge-info fallback"
                        
                        CoolLine:LogCooldownDebug("charge-fallback:" .. source .. ":" .. tostring(id),
                            "Using charge-info fallback for " .. name .. " (ID " .. tostring(id)
                                .. ", " .. tostring(currentCharges) .. "/" .. tostring(maxCharges) .. " charges).")
                        
                    end
                end
            end
            if CoolLine:IsSecretValueCompat(remaining) then
                retailSawSecret = true
                CoolLine:LogCooldownDebug("secret-charge:" .. source .. ":" .. tostring(id),
                    "Charge cooldown remaining duration is secret for " .. name .. "; estimating it (ID "
                        .. tostring(id) .. ", source " .. source .. ").")
                ShowSecretCooldown(btype, id, name, true, isCooldownEvent)
            else
                secretCandidates[btype][id] = nil
                if remaining and remaining > DEFAULT_RETAIL_GCD_DURATION_S then
                    local blocked = CoolLine:IsBlocked(name, id)
                    
                    CoolLine:LogCooldownDebug((blocked and "blocked-charge:" or "active-charge:")
                            .. source .. ":" .. tostring(id),
                        (blocked and "Found cooldown for blacklisted " or "Found active charge cooldown for ")
                            .. name .. " (ID " .. tostring(id) .. ", via " .. durationSource .. ").")
                    
                elseif remaining then
                    
                    CoolLine:LogCooldownDebug("short-charge:" .. source .. ":" .. tostring(id),
                        "Charge cooldown for " .. name .. " is below the display threshold (ID "
                            .. tostring(id) .. ", remaining " .. tostring(remaining) .. " s).")
                    
                else
                    
                    CoolLine:LogCooldownDebug("missing-charge:" .. source .. ":" .. tostring(id),
                        "No readable charge cooldown for " .. name .. " (ID " .. tostring(id) .. ").")
                    
                end
                if remaining and remaining > DEFAULT_RETAIL_GCD_DURATION_S and not CoolLine:IsBlocked(name, id) then
                    local _, _, texture = CoolLine:GetSpellInfoCompat(id)
                    ShowReadableRetailCooldown(name, texture, remaining, btype == BOOKTYPE_SPELL, id, source)
                else
                    ClearCooldown(nil, name, source)
                end
            end
        end
    end

    local function CheckSpellBookClassic(btype)
        CheckSpellBookWithLegacyAPI(btype, false)
    end

    local function CheckSpellBookForever(btype, isCooldownEvent)
        CheckSpellBookWithLegacyAPI(btype, true, isCooldownEvent)
    end

    local checkSpellBookByClient = {
        retail = CheckSpellBookRetail,
        forever = CheckSpellBookForever,
        classic = CheckSpellBookClassic,
    }
    local client = CoolLine.CLIENT or "classic"

    local function CheckSpellBook(btype, isCooldownEvent)
        checkSpellBookByClient[client](btype, isCooldownEvent)
    end

    local function ScanSpellBooks(isCooldownEvent)
        retailSawSecret = false
        CheckSpellBook(BOOKTYPE_SPELL, isCooldownEvent)
        if not CoolLine.db.hidepet and HasPetUI() then
            CheckSpellBook(BOOKTYPE_PET, isCooldownEvent)
        end
        if client == "forever" then
            CoolLine.RefreshCooldownDisplay()
        end
    end

    spellThrottle:SetScript("OnUpdate", function(this, delta)
        elapsed = elapsed + delta
        if elapsed < 0.3 then
            return
        end
        elapsed = 0
        this:Hide()
        ScanSpellBooks(false)
    end)

    spellThrottle:Hide()

    function CoolLine:SPELL_UPDATE_COOLDOWN(isCooldownEvent)
        -- Retail only pays for immediate event scans while cooldown timing is secret; otherwise it stays throttled.
        local immediate = client == "forever"
            or (client == "retail" and (retailSawSecret or CoolLine:AreCooldownsRestrictedCompat()))
        if immediate and isCooldownEvent then
            spellThrottle:Hide()
            ScanSpellBooks(true)
        else
            spellThrottle:Show()
        end
    end

    function CoolLine:RequestCooldownRecheck()
        spellThrottle:Show()
    end

    -- Immediate, unthrottled scan used around combat and restriction transitions, where the exact timing is
    -- readable only for a short moment.
    function CoolLine:ScanCooldownsNow()
        spellThrottle:Hide()
        ScanSpellBooks(true)
    end

    -- Cast times are readable even when cooldown timing is secret, giving a better start estimate.
    function CoolLine:UNIT_SPELLCAST_SUCCEEDED(_, _, spellID)
        if type(spellID) == "number" and not CoolLine:IsSecretValueCompat(spellID) then
            lastCasts[spellID] = GetTime()
        end
    end
    if client ~= "classic" and CoolLine.RegisterUnitEvent then
        CoolLine:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    end

    function CoolLine:ENCOUNTER_TIMELINE_STATE_UPDATED()
        CoolLine.RefreshCooldownDisplay()
    end
end
