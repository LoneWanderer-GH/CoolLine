local addonName = ...

local CoolLineApp = LibStub("AceAddon-3.0"):NewAddon(
    addonName,
    "AceConsole-3.0"
)

--@debug@
local LoggingLib = LibStub("LoggingLib-0.1", true)
if LoggingLib then
    LoggingLib:Embed(CoolLineApp)
else
    CoolLineApp:Print("LoggingLib-0.1 is missing; debug logging is disabled.")
    CoolLineApp.Debug = function() end
    CoolLineApp.Trace = function() end
    CoolLineApp.SetCooldownDebugEnabled = function() end
end
--@end-debug@

local CoolLine = CreateFrame("Frame", "CoolLine", UIParent)
CoolLine.MainFrame = CoolLine
CoolLineApp.MainFrame = CoolLine

--@debug@
function CoolLineApp:OnInitialize()
    if LoggingLib then
        self:InitializeLogging(addonName, nil, {
            Core = "|r",
            Spellbook = "|r",
            Timeline = "|r",
            Options = "|r",
        }, LoggingLib.INACTIVE)
    end
end

function CoolLineApp:SetCooldownDebugEnabled(enabled)
    self:SetLogLevel(enabled and LoggingLib.TRACE or LoggingLib.INACTIVE)
end
--@end-debug@
