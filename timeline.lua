local addonName = ...
local CoolLineApp = LibStub("AceAddon-3.0"):GetAddon(addonName)
local CoolLine = CoolLineApp.MainFrame

local function cancelEvent(frame)
    local timeline = C_EncounterTimeline
    if frame.timelineEventID and timeline and timeline.CancelScriptEvent then
        timeline.CancelScriptEvent(frame.timelineEventID)
    end
    frame.timelineEventID = nil
    frame.timelineEventEndTime = nil
    frame.timelineEventSpellID = nil
end

function CoolLine:IsNativeTimelineEnabled()
    local timeline = C_EncounterTimeline
    if not (self.db and self.db.blizzardTimeline and timeline
        and timeline.IsFeatureAvailable and timeline.IsFeatureAvailable()
        and timeline.IsFeatureEnabled and timeline.IsFeatureEnabled()) then
        return false
    end
    local viewType = timeline.GetViewType and Enum and Enum.EncounterTimelineViewType
    return not viewType or timeline.GetViewType() ~= viewType.None
end

function CoolLine:SyncTimelineEvent(frame)
    local timeline = C_EncounterTimeline
    local sourceEnabled = self.db and (
        (frame.source == "player" and self.db.timelinePlayer)
        or (frame.source == "pet" and self.db.timelinePet)
        or (frame.source == "item" and self.db.timelineItem)
    )
    local enabled = self:IsNativeTimelineEnabled() and sourceEnabled and frame.spellID
        and type(frame.iconTexture) == "number"
        and timeline.AddScriptEvent and timeline.CancelScriptEvent

    if not enabled then
        cancelEvent(frame)
        return
    end

    if frame.timelineEventID and frame.timelineEventEndTime == frame.endtime
        and frame.timelineEventSpellID == frame.spellID then
        return
    end

    cancelEvent(frame)
    local severity = Enum and Enum.EncounterEventSeverity and Enum.EncounterEventSeverity.Medium
    if not severity then
        return
    end

    local duration = frame.endtime and math.max(0, frame.endtime - GetTime())
        or math.max(0, frame.remaining_duration or 0)
    local eventID = timeline.AddScriptEvent({
        spellID = frame.spellID,
        iconFileID = frame.iconTexture,
        duration = duration,
        maxQueueDuration = 0,
        overrideName = frame.name,
        severity = severity,
        paused = false,
    })

    if eventID and eventID ~= 0 then
        frame.timelineEventID = eventID
        frame.timelineEventEndTime = frame.endtime
        frame.timelineEventSpellID = frame.spellID
        --@debug@
        CoolLineApp:Trace("Timeline", "Routed cooldown to Blizzard timeline")
        --@end-debug@
    end
end

function CoolLine:CancelTimelineEvent(frame)
    cancelEvent(frame)
end
