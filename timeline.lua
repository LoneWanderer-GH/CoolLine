local addonName = ...
local CoolLineApp = LibStub("AceAddon-3.0"):GetAddon(addonName)
local CoolLine = CoolLineApp.MainFrame
local EVENT_EXPIRATION_TOLERANCE = 0.5

--@debug@
local function logTimelineStatus(frame, status)
    local spellID = tostring(frame.spellID or frame.name or "unknown")
    local message = "Blizzard timeline: " .. tostring(frame.name or "Unknown spell")
        .. " (ID " .. spellID .. ", " .. tostring(frame.source or "unknown") .. "): "
        .. status .. "."
    CoolLine:LogCooldownDebug("timeline:" .. tostring(frame.source) .. ":" .. spellID, message)
end

local function getTimelinePlacement(timeline, eventID)
    if not timeline.GetEventTrack then
        return "track details unavailable"
    end
    local track = timeline.GetEventTrack(eventID)
    if not track then
        return "track unavailable"
    end
    local trackName = tostring(track)
    local trackTypes = Enum and Enum.EncounterTimelineTrack
    if trackTypes then
        for name, value in pairs(trackTypes) do
            if value == track then
                trackName = name
                break
            end
        end
    end
    local trackInfo = timeline.GetTrackInfo and timeline.GetTrackInfo(track)
    if not trackInfo or not trackInfo.minimumEventIntroDuration then
        return "track " .. trackName
    end
    return "track " .. trackName .. ", minimum intro "
        .. tostring(trackInfo.minimumEventIntroDuration) .. " s"
end
--@end-debug@

local function cancelEvent(frame)
    local timeline = C_EncounterTimeline
    if frame.timelineEventID and timeline and timeline.CancelScriptEvent then
        timeline.CancelScriptEvent(frame.timelineEventID)
    end
    frame.timelineEventID = nil
    frame.timelineEventSpellID = nil
    frame.timelineEventEndTime = nil
end

function CoolLine:IsNativeTimelineEnabled()
    local timeline = C_EncounterTimeline
    if not (self.db and self.db.blizzardTimeline) then
        return false, "CoolLine integration is disabled in settings"
    end
    if not timeline then
        return false, "Blizzard timeline API is unavailable"
    end
    if not timeline.IsFeatureAvailable then
        return false, "Blizzard timeline availability check is unavailable"
    end
    if not timeline.IsFeatureAvailable() then
        return false, "Blizzard timeline feature is unavailable"
    end
    if not timeline.IsFeatureEnabled then
        return false, "Blizzard timeline enabled check is unavailable"
    end
    if not timeline.IsFeatureEnabled() then
        return false, "Blizzard timeline feature is disabled"
    end
    local viewType = timeline.GetViewType and Enum and Enum.EncounterTimelineViewType
    if viewType and timeline.GetViewType() == viewType.None then
        return false, "Blizzard timeline is not open"
    end
    return true
end

function CoolLine:SyncTimelineEvent(frame)
    local timeline = C_EncounterTimeline
    local timelineEnabled, timelineDisabledReason = self:IsNativeTimelineEnabled()
    local iconFileID = frame.iconTexture
    if type(iconFileID) ~= "number" and frame.spellID then
        iconFileID = self:GetSpellTextureCompat(frame.spellID)
    end
    local sourceEnabled = self.db and (
        (frame.source == "player" and self.db.timelinePlayer)
        or (frame.source == "pet" and self.db.timelinePet)
        or (frame.source == "item" and self.db.timelineItem)
    )
    local reason
    if not timelineEnabled then
        reason = timelineDisabledReason
    elseif not sourceEnabled then
        reason = "this cooldown source is disabled in settings"
    elseif not frame.spellID then
        reason = "cooldown has no spell ID"
    elseif type(iconFileID) ~= "number" then
        reason = "spell icon file ID is unavailable"
    elseif not timeline.AddScriptEvent or not timeline.CancelScriptEvent then
        reason = "Blizzard timeline event API is unavailable"
    end

    if reason then
        cancelEvent(frame)
        --@debug@
        logTimelineStatus(frame, "not sent: " .. reason)
        --@end-debug@
        return
    end

    local now = GetTime()
    local eventEndTime = frame.endtime or (now + math.max(0, frame.remaining_duration or 0))
    if frame.timelineEventID and frame.timelineEventSpellID == frame.spellID then
        if frame.timelineEventEndTime
            and now < frame.timelineEventEndTime - EVENT_EXPIRATION_TOLERANCE then
            --@debug@
            logTimelineStatus(frame, "already registered (event ID "
                .. tostring(frame.timelineEventID) .. ")")
            --@end-debug@
            return
        end
        -- Blizzard events expire on their own; discard the stale local handle before re-adding.
        --@debug@
        logTimelineStatus(frame, "previous event expired; replacing local event handle")
        --@end-debug@
    end

    cancelEvent(frame)
    local severity = Enum and Enum.EncounterEventSeverity and Enum.EncounterEventSeverity.Medium
    if not severity then
        --@debug@
        logTimelineStatus(frame, "not sent: Blizzard event severity is unavailable")
        --@end-debug@
        return
    end

    local eventID = timeline.AddScriptEvent({
        spellID = frame.spellID,
        iconFileID = iconFileID,
        duration = math.max(0, eventEndTime - GetTime()),
        maxQueueDuration = 0,
        overrideName = frame.name,
        severity = severity,
        paused = false,
    })

    if eventID and eventID ~= 0 then
        frame.timelineEventID = eventID
        frame.timelineEventSpellID = frame.spellID
        frame.timelineEventEndTime = eventEndTime
        --@debug@
        logTimelineStatus(frame, "accepted by Blizzard (event ID " .. tostring(eventID)
            .. "; " .. getTimelinePlacement(timeline, eventID) .. ")")
        CoolLineApp:Trace("Timeline", "Routed cooldown to Blizzard timeline")
        --@end-debug@
    else
        --@debug@
        logTimelineStatus(frame, "not accepted by Blizzard (returned " .. tostring(eventID) .. ")")
        --@end-debug@
    end
end

function CoolLine:CancelTimelineEvent(frame)
    cancelEvent(frame)
end
