# ShaguDPS 4.0 for WoW 1.18.1 Clients

A very small and lightweight damage and healing meter, updated for 1.18.1 clients.
It reads structured combat events from **ClassicAPI** or **Nampower** when they are
loaded, and falls back to parsing the chat combat log on a plain client.

Based on [ShaguDPS](https://github.com/shagu/ShaguDPS) by Shagu and the Nampower
parser from [Duciel's fork](https://github.com/Duciel/ShaguDPS).

## What's new in 4.0

**Data sources**
- **ClassicAPI** (preferred): reads `COMBAT_LOG_EVENT_UNFILTERED`. Units come with
  GUIDs and group/pet flags, so group members, pets, guardians and totems are found
  without scanning names on every hit, and nothing depends on the client language.
- **Nampower**: reads `SPELL_DAMAGE_EVENT_*`, `AUTO_ATTACK_*`, `DAMAGE_SHIELD_*` and
  `SPELL_HEAL_BY_*`. Turns on Nampower's auto attack and heal events
  (`NP_EnableAutoAttackEvents`, `NP_EnableSpellHealEvents`) when it is used.
  Needs GUID unit tokens, which SuperWoW or ClassicAPI provide; without them it
  isn't used (it used to take over and record nothing).
- **Chat combat log**: the original text parser, used when neither is available.
- Pick one in the settings or with `/sdps source`; "Auto" takes the best one loaded.
  The settings show which source is in use.
- Unit lookups are cached per GUID, so busy raids cost less.
- Pets and totems of group members are matched to their owner through the GUID
  (`UnitOwnerGUID` with ClassicAPI, the owner token with SuperWoW).

**Per second time**
- *Active Time* (default, as before): each unit's own time spent dealing damage.
- *Fight Duration*: the time the whole segment lasted, the same for everyone, like
  most raid parses. Windows keep ticking while a fight runs.
- Bar tooltips show the active time, and in fight duration mode the fight time and
  the share of it the unit was active.

**Classic theme** (default; switch back with *Theme: Flat* or `/sdps theme 0`)
- Tooltip-style window in a neutral dark fill with the silver border.
- Gold title buttons and icons that light up on hover, no boxes.
- Silver rule under the title, quest-log glow on hovered bars and menu entries.
- Dropdown lists as tooltip panels.
- Shadowed text instead of outlines, a dark track behind each bar.
- Settings in the stock dialog box with the gold header plate, stock checkboxes,
  page arrows and close button.

**Fixes**
- New windows start with the size and view of the first window.
- Long names no longer run into the numbers on the bars.
- Unmerged pets show as "Owner - Pet" instead of "Owner - Pet (Owner)".
- Fixed the best effective heal value used for the heal bar scale.
- Bars of different windows no longer share global frame names.
- The settings window closes with Escape.

## Installation
1. Download the latest version and unpack it.
2. Make sure the folder is named `ShaguDPS` (not `ShaguDPS-master`).
3. Copy `ShaguDPS` into `Wow-Directory\Interface\AddOns`.
4. Restart the game.

Optional client mods: [ClassicAPI](https://github.com/brues-code/ClassicAPI),
[Nampower](https://github.com/pepopo978/nampower), SuperWoW.

## Commands

`/shagudps`, `/sdps` or `/sd`:

```
/sdps config           Open the settings
/sdps visible 1        Show main window (0 or 1)
/sdps height 15        Bar height (any number)
/sdps spacing 0        Bar spacing
/sdps trackall 0       Track all nearby units (0 or 1)
/sdps mergepet 1       Merge pets into owner data (0 or 1)
/sdps source 1         Data source (1 auto, 2 ClassicAPI, 3 Nampower, 4 chat log)
/sdps time 0           Per second time (0 active time, 1 fight duration)
/sdps texture 2        Statusbar texture (1 to 4)
/sdps pastel 0         Use pastel colors (0 or 1)
/sdps backdrop 1       Show window backdrop and border (0 or 1)
/sdps theme 1          Theme (0 flat, 1 classic), needs a reload
/sdps lock 0           Lock windows
/sdps toggle           Toggle visibility of the main window
```

## Combat Log Range

ShaguDPS has no raid-syncing between players: it sees what your client is told about,
which is limited by the combat log range (40 yards by default). This applies to every
data source. To raise it to 200:

    /run for _,n in pairs({"Party", "PartyPet", "FriendlyPlayers", "FriendlyPlayersPets", "HostilePlayers", "HostilePlayersPets", "Creature" }) do SetCVar("CombatLogRange"..n, 200) end

Or in your Config.wtf:

    SET CombatLogRangeParty "200"
    SET CombatLogRangePartyPet "200"
    SET CombatLogRangeFriendlyPlayers "200"
    SET CombatLogRangeFriendlyPlayersPets "200"
    SET CombatLogRangeHostilePlayers "200"
    SET CombatLogRangeHostilePlayersPets "200"
    SET CombatLogRangeCreature "200"

Some unitframe addons rely on the range being exactly "40" for their range checks,
and some reset it back to "40".
