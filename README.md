# CoolLine (for retail, classic and ElvUI_CoolLine_Wrapper compatible)

[![](http://cf.way2muchnoise.eu/title/356973.svg)](https://www.curseforge.com/wow/addons/coolline-classic-updated)
[![](http://cf.way2muchnoise.eu/versions/356973.svg)](https://www.curseforge.com/wow/addons/coolline-classic-updated)
[![](http://cf.way2muchnoise.eu/full_356973_downloads.svg)](https://www.curseforge.com/wow/addons/coolline-classic-updated)
![](https://github.com/LoneWanderer-GH/CoolLine/actions/workflows/feature-branch-build.yaml/badge.svg)

Shows cooldowns on a single bar for World of Warcraft classic and retail.

Download [Curse page](https://www.curseforge.com/wow/addons/coolline-classic-updated)

It is the original CoolLine modified to be compatible with an addon I made: [ElvUI_CoolLine_Wrapper](https://www.curseforge.com/wow/addons/elvui-coolline-wrapper)
[![](http://cf.way2muchnoise.eu/title/356978.svg)](https://www.curseforge.com/wow/addons/coolline-classic-updated)
[![](http://cf.way2muchnoise.eu/versions/356978.svg)](https://www.curseforge.com/wow/addons/coolline-classic-updated)
[![](http://cf.way2muchnoise.eu/full_356978_downloads.svg)](https://www.curseforge.com/wow/addons/coolline-classic-updated)
![](https://github.com/LoneWanderer-GH/CoolLine/actions/workflows/build.yml/badge.svg)

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
options. When `ElvUI_CoolLine_Wrapper` is loaded, use its mover to reposition
CoolLine; the unlock control still enables resizing. `/coolline <spell/item
name or ID>` toggles an entry in the dedicated cooldown blacklist;
`/coolline list` shows the current entries.

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
