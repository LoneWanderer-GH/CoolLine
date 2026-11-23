-- Récupération de l'environnement de l'addon (fourni par WoW au chargement)
local addonName = ...
local CoolLine = LibStub("AceAddon-3.0"):GetAddon(addonName).MainFrame

local _G = _G

function CoolLine:IsSecretValueCompat(value)
    local isSecretValue = _G.issecretvalue
    return isSecretValue and isSecretValue(value) or false
end

-- compat functions for mutiple clients
function CoolLine:GetSpellCooldownCompat(spellID)
    if GetSpellCooldown then
        return GetSpellCooldown(spellID)
    end
    if C_Spell and C_Spell.GetSpellCooldown then
        local info = C_Spell.GetSpellCooldown(spellID)
        if info then
            local isEnabled = info.isEnabled
            if not self:IsSecretValueCompat(isEnabled) then
                isEnabled = isEnabled and 1 or 0
            end
            return info.startTime, info.duration, isEnabled
        end
    end
end

function CoolLine:GetSpellChargesCompat(spellID)
    if GetSpellCharges then
        return GetSpellCharges(spellID)
    end

    local info = C_Spell and C_Spell.GetSpellCharges and C_Spell.GetSpellCharges(spellID)
    if info then
        -- return info.currentCharges, info.maxCharges, info.cooldownStartTime, info.cooldownDuration
        return info.currentCharges, info.maxCharges, info.cooldownStartTime, info.cooldownDuration
    end
end

function CoolLine:GetSpellBaseCooldownCompat(spellID)
    if GetSpellBaseCooldown then
        return GetSpellBaseCooldown(spellID)
    end
    if C_Spell and C_Spell.GetSpellBaseCooldown then
        return C_Spell.GetSpellBaseCooldown(spellID)
    end
    -- print("WTF: GetSpellBaseCooldown not found for spellID", spellID)
    return nil
end

function CoolLine:GetItemSpellIDCompat(itemID)
    local getItemSpell = C_Item and C_Item.GetItemSpell or _G.GetItemSpell
    if not itemID or not getItemSpell then
        return nil
    end
    local _, spellID = getItemSpell(itemID)
    return spellID
end

function CoolLine:GetContainerItemIDCompat(bagID, slotID)
    if C_Container and C_Container.GetContainerItemID then
        return C_Container.GetContainerItemID(bagID, slotID)
    end
    if GetContainerItemID then
        return GetContainerItemID(bagID, slotID)
    end
end

function CoolLine:GetItemNameCompat(itemInfo)
    if GetItemInfo then
        local itemName = GetItemInfo(itemInfo)
        if itemName then
            return itemName
        end
    end

    if C_Item and C_Item.GetItemInfo then
        -- C_Item.GetItemInfo renvoie une liste (le nom est le 1er argument)
        local itemName = C_Item.GetItemInfo(itemInfo)
        if itemName then
            return itemName
        end
    end
    if C_Item and C_Item.GetItemInfoInstant then
        local itemID = C_Item.GetItemInfoInstant(itemInfo)
        if itemID and C_Item.GetItemNameByID then
            return C_Item.GetItemNameByID(itemID)
        end
    end
end

function CoolLine:GetAddOnMetadataCompat(addonName, field)
    if GetAddOnMetadata then
        return GetAddOnMetadata(addonName, field)
    end
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        local success, result = pcall(C_AddOns.GetAddOnMetadata, addonName, field)
        if success then
            return result
        end
    end
end


function CoolLine:IsAddonLoadedCompat(addonName)
    if IsAddOnLoaded then
        return IsAddOnLoaded(addonName)
    end

    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(addonName)
    end
end

function CoolLine:GetSpellInfoCompat(spellID)
    if GetSpellInfo then
        return GetSpellInfo(spellID) -- name, rank, icon, castTime, minRange, maxRange, id
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local spellInfo = C_Spell.GetSpellInfo(spellID)
        if spellInfo then
            -- nil is for compat with API who return rank
            return spellInfo.name, nil, spellInfo.iconID, spellInfo.castTime,
                spellInfo.minRange, spellInfo.maxRange, spellInfo.spellID
        else
            -- print("WTF: GetSpellInfo not found for spellID (no spell info for spellID)", spellID)
        end
    else
        -- print("WTF: GetSpellInfo not found for spellID (no spell info API)", spellID)
    end
    -- local spellInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    -- if spellInfo then
    --     -- nil is for compat with API who return rank
    --     return spellInfo.name, nil, spellInfo.iconDataID, spellInfo.castTime,
    --         spellInfo.minRange, spellInfo.maxRange, spellInfo.spellID
    -- end
    --print("WTF: GetSpellInfo not found for spellID", spellID)
    -- return nil
end

function CoolLine:GetSpellTextureCompat(spellID)
    if C_Spell and C_Spell.GetSpellTexture then
        local texture = C_Spell.GetSpellTexture(spellID)
        if texture then
            return texture
        end
    end
    if GetSpellTexture then
        local texture = GetSpellTexture(spellID)
        if texture then
            return texture
        end
    end
    local _, _, texture = self:GetSpellInfoCompat(spellID)
    return texture
end

function CoolLine:GetSpellBookItemNameCompat(index, bookType)
    if _G.GetSpellBookItemName then
        return _G.GetSpellBookItemName(index, bookType)
    end
    if C_SpellBook and C_SpellBook.GetSpellBookItemName then
        -- index and enum
        return C_SpellBook.GetSpellBookItemName(index, bookType)
    end
end

-- GetSpellBookItemInfoCompat
function CoolLine:GetSpellBookItemInfoCompat(index, bookType)
    if _G.GetSpellBookItemInfo then
        return _G.GetSpellBookItemInfo(index, bookType) -- return : type, id
    end
    if C_SpellBook and C_SpellBook.GetSpellBookItemInfo then
        local info = C_SpellBook.GetSpellBookItemInfo(index, bookType)
        if info then
            -- Convertit l'objet moderne au format des anciens addons (ex: "SPELL", spellID)
            local legacyType = "SPELL"
            if info.itemType == Enum.SpellBookItemType.PetAction then legacyType = "PETACTION"
            elseif info.itemType == Enum.SpellBookItemType.Flyout then legacyType = "FLYOUT"
            elseif info.itemType == Enum.SpellBookItemType.FutureSpell then legacyType = "FUTURESPELL" end
            
            return legacyType, info.actionID or info.spellID
        end
    end
end

function CoolLine:GetContainerItemInfoCompat(bagID, slotID)
    -- 1. Classic (old global API)
    if _G.GetContainerItemInfo then
        return _G.GetContainerItemInfo(bagID, slotID)
    end

    -- 2. Modern / Midnight (Namespace C_Container)
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bagID, slotID)
        if info then
            -- Extract and oprder data to mimic old function :
            -- 1: iconFileID, 2: stackCount, 3: isLocked, 4: quality, 5: readable, 
            -- 6: hasLoot, 7: hyperlink, 8: isFiltered, 9: hasNoValue, 10: itemID, 11: isBound
            return info.iconFileID, info.stackCount, info.isLocked, info.quality, info.isReadable,
                   info.hasLoot, info.hyperlink, info.isFiltered, info.hasNoValue, info.itemID, info.isBound
        end
    end
    
    return nil
end


function CoolLine:GetContainerItemCooldownCompat(bagID, slotID)
    if _G.GetContainerItemCooldown then
        return _G.GetContainerItemCooldown(bagID, slotID)
    end
    if C_Container and C_Container.GetItemCooldown and C_Container.GetContainerItemID then
        -- Retail/Midnight, C_Container.GetItemCooldown takes itemID as param
        local itemID = C_Container.GetContainerItemID(bagID, slotID)
        if itemID then
            return C_Container.GetItemCooldown(itemID)
        end
    end
    --print("WTF: GetContainerItemCooldown not found for bagID", bagID, "slotID", slotID, "returning 0,0,0")
    return 0, 0, 0
end

function CoolLine:GetContainerItemIconCompat(bagID, slotID)
    if _G.GetContainerItemInfo then
        local texture = _G.GetContainerItemInfo(bagID, slotID)
        return texture -- Classic returns texture as 1st arg
    end
    if C_Container and C_Container.GetContainerItemInfo then
        local info = C_Container.GetContainerItemInfo(bagID, slotID)
        return info and info.iconFileID -- Retail returns table with an iconFileID key
    end
end




-- Midnight: Secret-safe spell cooldown (the API may return nothing for an unknown spell)
function CoolLine:GetSpellCooldownDurationCompat(spellID)
    if C_Spell and C_Spell.GetSpellCooldownDuration then
        local duration = C_Spell.GetSpellCooldownDuration(spellID)
        return duration and duration:GetRemainingDuration()
    end
    return nil
end

-- True when the client reports that cooldown queries currently return secret values.
function CoolLine:AreCooldownsRestrictedCompat()
    local secrets = _G.C_Secrets
    return secrets and secrets.ShouldCooldownsBeSecret and secrets.ShouldCooldownsBeSecret() == true or false
end

-- Midnight: Secret-safe spell charge cooldown
function CoolLine:GetSpellChargeDurationCompat(spellID)
    if C_Spell and C_Spell.GetSpellChargeDuration then
        local duration = C_Spell.GetSpellChargeDuration(spellID)
        return duration and duration:GetRemainingDuration()
    end

    return nil
end
