# CoolLine (for Retail and Classic)

[![](http://cf.way2muchnoise.eu/title/356973.svg)](https://www.curseforge.com/wow/addons/coolline-classic-updated)
[![](http://cf.way2muchnoise.eu/versions/356973.svg)](https://www.curseforge.com/wow/addons/coolline-classic-updated)
[![](http://cf.way2muchnoise.eu/full_356973_downloads.svg)](https://www.curseforge.com/wow/addons/coolline-classic-updated)
![](https://github.com/LoneWanderer-GH/CoolLine/actions/workflows/feature-branch-build.yaml/badge.svg)

Shows cooldowns on a single bar for World of Warcraft classic and retail.

Download [Curse page](https://www.curseforge.com/wow/addons/coolline-classic-updated)

## Blizzard encounter timeline

Retail can optionally route player-spell cooldowns to Blizzard's encounter
timeline. Pet spellbook cooldowns and item cooldowns can also be routed when
their spell IDs are available. The Blizzard API exposes one shared timeline; it
does not let addons create independent instances. The original CoolLine bar and
the Blizzard timeline can be enabled together or independently in `/coolline`;
cooldowns without a usable native event stay on CoolLine's bar when it is on.

Use `/coolline` or `/cl` to open settings. Use `/cl unlock` (or `/cl move`) to
enable dragging and resizing, and `/cl lock` to finish. `/cl toggle` toggles
that mode. The same unlock control is available in the Behavior section of the
options. When ElvUI is loaded, CoolLine registers its frame as an ElvUI mover;
use ElvUI's Movers configuration to reposition it. CoolLine's own drag-to-move
behavior is disabled in that case, though resizing remains available.
`/coolline <spell/item name or ID>` toggles an entry in the dedicated cooldown blacklist;
`/coolline list` shows the current entries. The options list displays localized
names and icons when available; IDs that match both a spell and an item show
both, and unknown entries remain visible by their original value.
Use `/cl debug` to toggle in-game cooldown diagnostics. It reports spells
filtered by base cooldown, charge cooldowns found or missing recharge timing,
active cooldowns found or blacklisted, and secret durations that prevent
CoolLine from reading a cooldown. If the charge-duration API returns no value
or a value below the display threshold while charges are missing, CoolLine
falls back to readable charge timing from the charge-info API. Secret values
are never printed.

On WoW Forever, restricted spell cooldowns remain on the bar with a `?`:
their position is estimated from the observed cast time (when known), and
previously observed or base cooldown timing (or 30 seconds if neither is
available). If the game still reports the cooldown as active after the estimate
has elapsed, the estimate is extended and the cooldown is rechecked every
half second, and when the native cooldown completes, so icons do not remain
stuck at one second. When available, the native cooldown swipe shows the game's
actual progress; its countdown numbers are hidden because they would disagree
with the estimated position. Newly
detected secret cooldowns are confirmed for approximately 2.5 seconds before
being displayed, to avoid showing transient global-cooldown activity. Short
cooldowns may end before they can be confirmed. Estimated
cooldowns are not submitted to Blizzard's encounter timeline. Item and pet
action cooldowns with secret timing cannot currently be updated this way.
The Forever regression scripts can be run with a Lua interpreter from the
repository root: `lua tests/forever-cooldowns.lua.test`,
`lua tests/forever-display.lua.test`, and `lua tests/forever-timeline.lua.test`.

Enable **Show example cooldowns** in the Behavior section of CoolLine's
options to display four temporary cooldowns with different durations. They
remain visible until the option is disabled and are never routed to Blizzard's
encounter timeline.

![](./docs/img/BlizzardTimeLineIntegration.png)

## Maintenance

Compatibility findings, development setup, CI details, and the per-patch update
workflow are documented in [MAINTENANCE.md](MAINTENANCE.md). Compatibility is
not claimed for a game flavor until it has been checked against that client.

## Disclaimer
The original CoolLine license is indicated as "All Rights Reserved unless otherwise explicitly stated."
Hence this project might be discontinued in the future until decision from original authors.
They are free to shut this down.

Original project and rights owner https://github.com/phanx-wow/CoolLine

Official wow retail wowinterface addon http://www.wowinterface.com/downloads/info12467-CoolLine.html

----
custom shields.io badge ...
![](https://img.shields.io/badge/dynamic/json?label=Curse%20downloads&color=orange&query=downloadCount&url=https://addons-ecs.forgesvc.net/api/v2/addon/356973/)
