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

On WoW Forever, spell cooldowns can be restricted: the game then hides their
start time and duration but still says whether they are active. CoolLine copes
as follows:

- A cooldown whose end time was read exactly before the restriction keeps that
  exact end (no `?`, and it stays on Blizzard's timeline when routed there). It
  only becomes an estimate if the game still reports it as active after that end.
- A cooldown first seen while restricted stays on the bar with a `?`. Its
  position is estimated from the observed cast time (when known) and from the
  duration observed when the same spell last ended, or else its base cooldown
  (or 30 seconds if neither is available). Observed durations are forgotten
  when the spellbook changes (talents, respec), and a much shorter observation
  (typically a cooldown reset) is not learned.
- If a cast of the same spell is seen well after the icon started, the cooldown
  is considered restarted and the estimate restarts from that cast.
- If the game still reports the cooldown as active after the estimated end, the
  icon waits at a hold point (0.5 second before the end of the bar by default;
  several waiting icons are fanned out so none hides another) and the game is
  asked again every 0.25 second, and as soon as the native cooldown completes. The
  estimate is no longer pushed back, so the icon does not bounce. An icon the
  game stops reporting at all (for example after a respec) is dropped shortly
  after its estimated end (and in any case 20 seconds after it, even if no scan
  runs), and icons of spells that left the spellbook are removed when it
  changes.
- Combat and addon-restriction transitions trigger an immediate scan: one just
  before the restriction is enforced (the last moment timing is readable), and
  one when it ends, so estimates are replaced by exact timing at once.
- When available, the native cooldown swipe shows the game's actual progress
  for estimated icons; its countdown numbers are hidden because they would
  disagree with the estimated position.
- Newly detected secret cooldowns are confirmed for approximately 2.5 seconds
  before being displayed, to avoid showing transient global-cooldown activity.
  Short cooldowns may end before they can be confirmed. Estimated cooldowns are
  not submitted to Blizzard's encounter timeline. Item and pet action cooldowns
  with secret timing cannot currently be updated this way.

The **Expert** section of the options exposes the thresholds used for these
estimates (all of them only matter while the game hides cooldown timing):

| Setting | Default | Range | Effect |
| --- | --- | --- | --- |
| Estimate hold point | 0.5 s | 0-3 s | Remaining time at which an exhausted estimate waits for the game |
| Confirmation delay | 2.5 s | 0.5-5 s | How long a new restricted cooldown must stay active before it is shown; below about 1.5 s, global-cooldown blips can appear |
| Drop unconfirmed icons after | 5 s | 1-15 s | Removal delay once the game no longer reports the cooldown |
| Fallback duration | 30 s | 5-300 s | Duration assumed when neither an observation nor the base cooldown is known |
| Recheck interval | 0.25 s | 0.1-2 s | How often a waiting icon asks the game whether the cooldown is over (scans are also throttled to about 0.3 s) |

Cooldowns of 1.5 seconds or less (the global cooldown) are never displayed and
that limit is not configurable.

On Retail, cooldowns whose remaining time is secret are handled like on
Forever (exact timing read earlier is kept, new ones are confirmed and
estimated, shown with a `?`), using the same rules as above. While timing is
secret, Retail also scans immediately on cooldown events so the global cooldown
can be told apart from a real cooldown. This Retail behavior is covered by
simulated tests only and still needs an in-game check.

The regression scripts in `tests/` can be run with a Lua 5.1 interpreter from
the repository root, for example
`for t in tests/*.lua.test; do lua5.1 "$t" || break; done`.

Enable **Show example cooldowns** in the Behavior section of CoolLine's
options to display four temporary cooldowns with different durations. They
remain visible until the option is disabled and are never routed to Blizzard's
encounter timeline.

The **Auto-hide** section of the options hides the bar while you travel (all
off by default; it is always shown while unlocked):

- **Hide on flight paths (taxi):** from losing control to a flight path until
  the game stops reporting it (`UnitOnTaxi`), even in combat.
- **Hide while mounted:** `IsMounted`. Mounted druid forms are not mounts.
- **Hide while flying:** `IsFlying` (flying mounts and druid flight forms in
  the air) and, where the client has it, dynamic flight (`C_PlayerInfo`
  gliding). Not offered in Classic Era, which has no flying.

The mounted and flying modes never hide the bar in combat, so the cooldowns are
there when you have to land and fight. The game has no flight-path or flying
event: CoolLine reacts to losing/regaining control, unit-flag, mount, form and
glide events, and polls twice a second only while flying hiding is enabled,
while the bar is hidden, or briefly after a control change. This only affects
CoolLine's own bar: no other UI addon checked (ElvUI and its plugins, Tukui,
EllesmereUI, DaylightUI) publishes a taxi event to subscribe to.

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
