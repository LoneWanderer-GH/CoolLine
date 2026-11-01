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
    print("CoolLine: LoggingLib-0.1 is missing; debug logging is disabled.")
    CoolLineApp.Debug = function() end
    CoolLineApp.Trace = function() end
end
--@end-debug@

local CoolLine = CreateFrame("Frame", "CoolLine", UIParent)
CoolLine.MainFrame = CoolLine
CoolLineApp.MainFrame = CoolLine

function CoolLineApp:OnInitialize()
    --@debug@
    if LoggingLib then
        self:InitializeLogging(addonName, nil, {
            Core = "|r",
            Timeline = "|r",
            Options = "|r",
        }, LoggingLib.TRACE)
    end
    --@end-debug@
end
