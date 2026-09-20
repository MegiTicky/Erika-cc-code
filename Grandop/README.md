# Lieyu Phase 2 Event Runbook

This document covers deploying, configuring, starting, updating, and operating
the unified `lieyu_phase_2` Grandop event.

## What Runs On The Event Computer

One Command Computer runs the complete event:

- The staged-capture objective and bossbar.
- The chat-button infantry and tank respawn menus.
- Infantry class loadouts and teleports.
- Tank deployment via VMod server schematics, availability, and respawn
  cooldown tracking.
- The `Troops_Strength` sidebar and reinforcement quotas.
- Japan town retreat handling as objectives advance.

The event command is:

```text
run event lieyu_phase_2
```

## Requirements

### Computer And Peripherals

- A Command Computer. The program uses Minecraft commands through `commands.exec`.
- An `sp_radar` peripheral attached to the event computer. Tanks are enabled, so
  the event refuses to start without it.
- A monitor is optional. The unified event uses chat menus; it does not require a
  monitor for player respawns.
- HTTP must be enabled in ComputerCraft to use the GitHub installer.

### World Setup

- The computer must be in the same dimension as the Lieyu battlefield. The
  configured positions and Minecraft selectors are dimension-local.
- Players must be assigned to these Minecraft scoreboard teams before entering a
  staging room:

```text
team join Blue <player>
team join Red <player>
```

- `Blue` is USMC and attacks.
- `Red` is Japan and defends.
- The Steve's Army mod is optional for the base event. It is required only if
  a loadout includes Steve's Army items, such as soldier spawn eggs.

### Configured Staging Rooms

| Team | Faction | Center | Radius |
| --- | --- | --- | --- |
| Blue | USMC | `4243, 308, 6653` | 10 blocks |
| Red | japan | `4237, 308, 6653` | 10 blocks |

Players in a staging room receive the respawn menu in chat. Leaving the room
clears their incomplete selection session.

## First-Time Installation

On the new event computer, download the installer once:

```text
wget https://raw.githubusercontent.com/MegiTicky/Erika-cc-code/main/install.lua install
```

Start the interactive installer:

```text
install
```

Choose:

```text
1. Lieyu Phase 2 - Complete Event System
```

The installer asks once before replacing existing files. It installs the event,
the loadout generator, and this runbook as `README_LIEYU_PHASE_2.md`.

The equivalent non-interactive command is:

```text
install event lieyu_phase_2 --force
```

The older runtime-only bundle remains available for advanced use:

```text
install bundle Grandop/manifests/phase_2_event.txt --force
```

Validate the installed files before starting the event:

```text
run event lieyu_phase_2 --validate
```

Expected output:

```text
Mission configuration valid: lieyu_phase_2
```

## Fresh Match Initialization

### Mission Snapshot Recovery

The unified event controller writes `/data/mission_state_<mission>.state` for
each running match. The snapshot contains objective progress, stage, tickets,
reinforcement quotas, vehicle availability state (active tanks, respawn
cooldowns, name counters), retreat flags, and paused state. It is
checkpointed after deployments, operator changes, stage changes, and every 15
seconds. Restarting the controller restores this state automatically.

Writes use ComputerCraft table serialization, verify the temporary write by
reading it back, and retain the previous snapshot as `.bak`. If the snapshot
is corrupt or does not match its mission ID/schema, startup fails
closed instead of silently overwriting live match progress. Investigate it, or
perform an intentional reset, before starting the controller again.

Use `Stop and reset new match` on the operator terminal before a fresh match.
After the controller stops, it clears the snapshot (including vehicle
availability state), removes the complete `Troops_Strength` objective
(including stale entries such as `USReinforcement` and `JPSpawn`), removes old
quota teams, and recreates the current Phase 2 quota defaults. The reset flags
below remain available for unattended ROM-started deployments.

The mission deliberately preserves persistent state by default:

- `Troops_Strength` preserves troop consumption between controller restarts.
- Vehicle availability state (active tanks, cooldowns, name counters) is
  preserved inside the mission snapshot. Tanks added to or removed from the
  mission's `vehiclePools` take effect on the next start without wiping that
  state.

For a brand-new match or an intentional full reset without the operator
backend, edit `missions/lieyu_phase_2.lua` on the event computer and
temporarily change:

```lua
resetTanks = false,
resetSpawns = false,
```

to:

```lua
resetTanks = true,
resetSpawns = true,
```

Start the event once, then stop it with `Ctrl+T`. Change both values back to
`false` before the normal event start. Leaving either value set to `true` will
reset the relevant persistent state every time the event starts.

The reset initializes these reinforcement counters:

| Counter | Initial value | Meaning |
| --- | --- | --- |
| `USMCSpawn Troops_Strength` | 20 | Remaining USMC deployments |
| `TownX_JPSpawn Troops_Strength` | 6 | Remaining Japan Town X deployments |
| `TownY_JPSpawn Troops_Strength` | 6 | Remaining Japan Town Y deployments |
| `TownZ_JPSpawn Troops_Strength` | 8 | Remaining Japan Town Z deployments |

## Starting And Stopping

## Newcomer Onboarding

When onboarding is enabled, the event controller checks team requests once per
second. Every 30 seconds, players who are not on either configured event team
receive a chat prompt with `Join Red` and `Join Blue` buttons. Players already
assigned to Red or Blue are ignored.

The buttons submit protected Minecraft `trigger` scoreboard requests. The
command computer validates the request, assigns the fixed configured team, and
teleports the player to that team's staging area for the current mission stage.
The normal respawn book then appears at staging.

Each reminder also shows the current online player count for Red and Blue. A
player joining after a stage change is sent to the current stage's staging area.

The service uses the `g_join_red` and `g_join_blue` trigger objectives. Players
must use the buttons rather than provide arbitrary team commands; the command
computer performs the privileged team assignment.

The launcher has an interactive menu. Run this with no arguments when you do
not want to remember service names or mission IDs:

```text
run
```

The menu only shows services whose program files are installed. It discovers
mission files from `/missions` and loadout JSON files from `/data/loadouts`.
For the complete Phase 2 profile, choose `Start unified event`, then select
`lieyu_phase_2`.

Start the event from the event computer terminal:

```text
run event lieyu_phase_2
```

Stop it from that same computer terminal:

```text
Ctrl+T
```

### Dedicated Operator Computer

The first operator-backend release provides status, pause/resume, reinforcement
quota changes, ticket changes, and graceful event shutdown from a separate
ComputerCraft computer. It does not yet provide state recovery, stage changes,
artillery controls, chat commands, or newcomer onboarding.

The complete Phase 2 install includes the operator UI. Pick-block clone the
event computer, attach a modem on `right`, and use the clone for backend access.
On the cloned Computer `19`, run:

```text
run
```

Both computers need a modem on the configured side, `right` by default. The
included `/data/operator_config.lua` uses that side:

```lua
return {
    rednet_side = "right",
}
```

Anyone able to access the event computer or its cloned operator computer can
use the backend. No computer-ID allowlist is required. Restart the event
computer after installing updates. On the clone, choose `Open operator terminal`
from `run`, or run this directly:

```text
run operator
```

Every accepted operator action is written to the event log. The terminal asks
for `YES` before changing a value, pausing/resuming, or shutting down the event.

Always stop the previous event before starting another instance. Running two
event controllers at the same time causes duplicate menu handling, deployment,
and objective updates.

Each start writes a log under:

```text
/logs/event_lieyu_phase_2_<timestamp>.log
```

The terminal prints the exact log filename when the event starts.

## Player Respawn Flow

1. Assign the player to `Blue` or `Red`.
2. Send the player to that team's staging room.
3. The player clicks a chat button for `Infantry` or `Tank`.
4. Infantry players select a class and an available spawn location.
5. Tank players select a tank and a vehicle spawn location.
6. The event applies the loadout, teleports/deploys the player, consumes the
   deployment quota, and updates the sidebar.

The menu uses chat buttons backed by protected `/trigger` objectives. Players do
not need OP: the event computer enables the valid trigger for the current menu,
validates the selection, and performs the privileged tag, loadout, teleport, and
vehicle operations. The trigger objectives are `g_resp_mode`, `g_resp_class`,
`g_resp_spawn`, `g_resp_tank`, and `g_resp_tspawn`. The player should click each
menu option once and wait for the next menu message.

### Infantry Classes

- USMC: `anti_tank`, `assault`, `commander`, `engineer`, `machine_gunner`,
  and `medic`.
- Japan: classes are loaded from `data/loadouts/lieyu_phase_2.json`.

### Infantry Spawns

USMC:

| Stage | Spawn |
| --- | --- |
| 1 | `S1 Main Town`, `USCommander` |
| 2 | `S2 Town X`, `USCommander` |
| 3 | `S3 Town Y`, `USCommander` |

Japan can select Town X, Town Y, or Town Z. The event's retreat handling
exhausts Town X when stage 2 begins and Town Y when stage 3 begins.

### Tanks

Tanks spawn directly from VMod server schematics instead of teleporting
pre-placed ships out of a depot. Each deployment runs
`/vmod schem load-from-sever <schematic>` (the `sever` spelling is VMod's
actual command), then `/vmod schem place X Y Z (rotation) <shipName>` at the
selected vehicle spawn location. The rotation argument is required in
VMod 0.1.3 and must be parenthesized (e.g. `(0 0 0)` for identity); the
spawner always sends one. A
temporary chunk loader is placed at the
target so placement works in unloaded chunks, and the radar confirms the new
ship appeared. Do not trust the command status: VMod 0.1.3 returns a failure
code for load AND place even when they succeed (and soft-fails with a success
code when they don't) — the radar check is the only reliable signal.

The deploying tanker is teleported onto the new hull in **survival** mode —
there is no creative staging around the vehicle spawns anymore (the mission's
`creativeZones` returns an empty list, and both spawn paths force
`/gamemode survival`). The tanker's personal kit comes from a
`<faction>.tank` class in the loadout JSON, applied exactly like the infantry
classes: armor worn directly into the armor slots (tanker cap, chestplate,
leggings, boots), a sidearm with creative ammo, and utility items. The class's
`steves_army:soldier_spawn_egg` entries also give the tanker a full rifle
squad — the same 14 soldiers infantry gets (9 riflemen, 3 machine gunners,
2 anti-tank) — spawned in a ring of 20 blocks around the player (infantry
squads use 2) so the soldiers don't materialize on the vehicle deck.
Field-repair materials
still come from the JSON's `repair_kits` list.

Availability follows a Battlefield-style model configured in the mission's
`vehiclePools.initial`:

- The respawn `cooldown` (seconds) **starts at spawn time**, exactly like
  Battlefield. While it counts down the tank type cannot spawn at all —
  even if a slot is free. Once it has expired, the next destruction or
  abandonment frees the slot for an immediate respawn.
- `maxLive` caps how many tanks of that type may exist at once. There is no
  finite stock.
- A tank leaves the active set through any of these triggers (none of them
  touches the cooldown — the slot simply frees):
  - **Abandonment** (primary): when the owner (or any player) leaves the
    `abandonRadius` around the hull, the owner is warned once that the tank
    counts as destroyed in `abandonSeconds` (mission fields `abandonRadius`,
    default 20; `abandonSeconds`, default 30). If nobody returns in time,
    the whole vehicle — every ship of it — is recalled to the reserve depot
    (frozen and teleported there). Returning clears the timer and re-arms
    the warning for the next departure.
  - **Destruction marker** (owner tool): the owner permanently carries an
    unbreakable renamed carrot-on-a-stick (`markerLabel`, e.g. "Tank
    Destruction Marker"). Right-clicking it instantly recalls the vehicle
    to the depot. Detection is a `gptankmarker` scoreboard objective on the
    `minecraft.used:minecraft.carrot_on_a_stick` criterion, polled every
    second. A non-destructive presence check (NBT-exact `execute if data`
    against the player inventory) runs every second; the marker is only
    re-issued (clear-all + give-one) when it is actually missing — dropped,
    moved out of the inventory, or lost to a soldier respawn — so the item
    never flickers while carried. Losing the vehicle strips the
    marker and zeroes the score so a stale right-click can never kill a
    freshly spawned tank.
  - **Destruction** (secondary): if the hull fully breaks apart, its radar ID
    disappears and the vehicle is declared destroyed immediately; surviving
    sub-ships are recalled to the depot too. Sub-ships that break while the
    hull lives are only pruned from tracking.
- Optional per-tank fields: `schematic` (server schematic file name including
  the `.vschem` extension, defaults to `<tank>.vschem`), `rotation`
  (`{ pitch, yaw, roll }`), and `anchorOffset` (`{ x, y, z }` placement
  correction).
- Admin `+/-` buttons on the tank monitor adjust `maxLive`.

Current pools: `japan.chinu` and `USMC.sherman75usmc`, each `maxLive = 3`
with a 30-second respawn cooldown.

One-time world-side prerequisites per server:

1. Save each tank type as a server schematic named exactly like the tank:
   `/vmod schem save-to-server chinu`,
   `/vmod schem save-to-server sherman75usmc`. Multi-island schematics
   (a tank whose hull and wheel blocks form several disconnected ships)
   are supported — every island is tracked, recalled, and cleaned up
   together.
   The load name is the plain name plus the `.vschem` extension — VMod
   0.1.3 resolves the name literally, so the spawner sends `chinu.vschem`.
   A load failure logs `Failed to load file ... NoSuchFileException` in
   `logs/latest.log`.
2. Calibrate the placement once: the schematic anchor may not sit exactly on
   the spawn coordinates or face the intended direction. Adjust
   `anchorOffset` and `rotation` in the mission's `vehiclePools` to correct
   it.

For a quick isolated check, run `test_schematic_spawn chinu` on the event
computer: it spawns the schematic a few blocks from the computer with a
`test-chinu-N-` name base, reports EVERY ship the placement created (island
count, ids, masses), and prints the full feedback of every load/place
command.

Naming: the spawner passes VMod the vehicle slug `<tank>-<vehicleNumber>-`
(e.g. `chinu-5-`), and VMod renames every ship of a multi-island placement
to `<slug>0`, `<slug>1`, ... — so vehicle 5 spawns as `chinu-5-0` (hull,
heaviest island), `chinu-5-1`, etc. A single-island schematic keeps the
bare slug (`chinu-5-`). The vehicle number is our own monotonic counter
(persisted in the snapshot) and only advances after a confirmed spawn, so
failed placements never consume a number; names never collide with
reserve-parked tanks. VMod's ship index is never parsed — recall and
cleanup address the ships by trying the slug patterns. A player's previous
vehicle (all its ships) is moved (and frozen) to the `reserve` area.

### Field Items: Squad Refill Horn And Reset Menu Book

Two player-carried utility items are watched by the same one-second poller
that maintains the tank destruction marker (`lib/respawn/field_gear.lua`);
both are re-issued within a second whenever they are lost (death, drop, kit
change), and a click logged just before the item left the inventory is
ignored. Missions opt in per item by defining `respawn.squadRefill` and/or
`respawn.sessionReset` (see `missions/lieyu_phase_2.lua`).

**Squad Refill** — a renamed goat horn whose right-click calls in an NPC
squad:

- Detection is a per-player score on the `gpsquadrefill` objective
  (`minecraft.used:minecraft.goat_horn` criterion). The objective is fully
  disjoint from the carrot-on-a-stick marker, so the two items never
  interfere.
- One click spends **one deployment ticket** from the nearest infantry spawn
  pool of the player's faction that still has quota at the current stage
  (commander spawns are skipped) — for USMC the single global pool, for
  japan the nearest town with troops. Quota exhausted → the click is
  discarded with a red "Respawn quota exhausted" message and the ticket is
  not spent.
- The standard 14-soldier squad (9 rifle / 3 MG / 2 AT, from the faction's
  `.standard` class eggs) materializes `distance` blocks (default 50) from
  the player **in the direction away from the nearest enemy player** (radar
  scan + scoreboard team check), heightmap-snapped to the surface. With no
  enemy on radar the squad rings the player itself. The ticket is only spent
  once soldiers actually spawned.

**Reset Menu** — a written book whose page carries a `[ RESET MENU ]` button
running `/trigger g_tagreset set 1` (the same trigger mechanism as the chat
menus, so it cannot collide with the marker or horn criteria):

- The target scenario is a player in staging whose session is broken — no
  menu after a **relog** (chat menus die with the session while the
  `grandop_*` tags persist, so the staging scan skips them forever) or a
  frozen menu. The reset is **unconditional**: it wipes every `grandop_*`
  session tag, resets and re-enables all trigger objectives and the session
  age, and re-sends the mode menu (first page).
- Works anywhere on the map; a deployed player who uses it just gets a
  transient menu that the existing outside-staging cleanup removes next
  tick. In the book flow the reset runs through the book service; the
  standalone terminal uses an equivalent generic sweep.

### The respawn menu reset button

The `[ Reset menu ]` button on every book page zeroes and re-enables its
trigger, clears all session tags and re-sends the first page. The reset
processing pins the player with a tag and restarts the session by resolved
player name — restarting on the raw score-scoped selector used to kill the
selector mid-flight (score zeroed → selector matches nobody), which froze
the menu and permanently disabled the button. The service also re-enables
the reset trigger for all book holders every second, so the button can
never end up dead again.

## Tickets And Troop Strength

The capture objective starts with 500 tickets for each team. Capturing an
objective awards the attacker 200 tickets and removes 50 defender tickets.

The sidebar objective is `Troops_Strength`:

- `USMCSpawn` starts at 20 and decreases once for each successful USMC infantry
  or tank deployment.
- `TownX_JPSpawn`, `TownY_JPSpawn`, and `TownZ_JPSpawn` start at 6, 6, and 8.
- The sidebar refreshes immediately after a successful deployment.

The Phase 2 remaining-reinforcement counters are the displayed
`Troops_Strength` scores:

```text
scoreboard players get USMCSpawn Troops_Strength
scoreboard players get TownX_JPSpawn Troops_Strength
scoreboard players get TownY_JPSpawn Troops_Strength
scoreboard players get TownZ_JPSpawn Troops_Strength
```

## Updating The Event Computer

After new Grandop code is pushed to GitHub, use the same installed `install`
program. Run the interactive menu:

```text
install
```

or use the named profile directly:

```text
install event lieyu_phase_2 --force
```

Then stop and start the event so Lua reloads the updated files:

```text
Ctrl+T
run event lieyu_phase_2
```

`install.lua` itself does not need to be reinstalled for normal event updates.
It always downloads files from the repository's `main` branch. Reinstall it only
when `install.lua` itself changes.

## Editing Loadouts

Edit this file in the repository or on the event computer:

```text
data/loadouts/lieyu_phase_2.json
```

Each class has an `items` array. Standard item entries are given directly to the
player:

```json
{ "item": "minecraft:iron_shovel", "count": 1 }
```

Armor entries replace the corresponding equipment slot:

```json
{ "slot": "chest", "item": "combatgear:pacific_chestplate" }
```

### Exporting Chest Items

To export a chest's contents for a loadout, use the interactive `run` menu and
choose `Export chest items for a loadout`. It prompts only for the inventory
side; leave it blank to use the first attached inventory.

The direct command is:

```text
run gen
```

or, for a chest on a specific side:

```text
run gen left
```

The exporter does not edit any existing loadout JSON. It writes this file at the
computer root:

```text
/generated_loadout_items.json
```

Open the computer's folder from your PC, copy the entire JSON array from that
file, and replace the desired class's `items` array in
`data/loadouts/lieyu_phase_2.json`. The export includes item IDs, counts, and
full NBT when the chest is directly adjacent to a Command Computer. Add
armor-slot metadata manually when needed, for example
`"slot": "chest"`.

After editing the repository copy, commit and push it. Update the event computer
with the bundle command above, then restart the event.

### Steve's Army Squadmates

Steve's Army soldier kits live in a class loadout as `steves_army:soldier_spawn_egg`
entries. Mark each one with `"give": false` and a soldier type:

```json
{ "item": "steves_army:soldier_spawn_egg", "count": 9, "give": false, "soldier": "rifleman", "nbt": "{...}" }
{ "item": "steves_army:soldier_spawn_egg", "count": 3, "give": false, "soldier": "machine_gunner", "nbt": "{...}" }
```

The player no longer places eggs. When a player deploys through the book respawn
service, `lib/steves_army.lua` spawns those squadmates automatically with
`/stevesarmy spawn <type> <player> ...`, which assigns the player as owner and
adds each soldier to the player's squad and current fire team. Eggs marked
`"give": false` are not handed to the player, so no manual placement and no
double-spawns.

The `[loadout]` argument is the egg's `EntityTag.Inventory.Items` list, reused
verbatim, so the squadmate spawns with the same kit the egg carried. Do not
replace this with a plain `/summon steves_army:soldier`; a plain summon bypasses
the player-owned squad setup.

## Troubleshooting

### Event Refuses To Start: `tanks require an sp_radar peripheral`

Attach an `sp_radar` to the Command Computer, then start again. Alternatively,
disable tanks in the mission configuration only if the event is intentionally
infantry-only.

### No Respawn Menu Appears

- Confirm the player is on `Blue` or `Red`, not a faction or private team.
- Confirm the player is within 10 blocks of the correct staging-room center.
- Confirm the event is running and inspect the newest `/logs/event_...` file.
- Ensure another event controller is not already running.

### A Menu Works But Nothing Is Given Or Teleported

- Inspect the latest event log for `Mode selected`, `Class selected`, and
  `Infantry spawn selected` entries.
- Confirm the target class and spawn exist in the loadout and mission files.
- Confirm the Command Computer has command permissions.
- Restart the event after updating `book.lua`, the mission file, or loadouts.

### Troops Strength Does Not Change

- Confirm the deployment reached `Infantry spawn selected` or completed tank
  deployment in the event log.
- Check the matching `Troops_Strength` scoreboard entry.
- Confirm the current event computer has the updated
  `missions/lieyu_phase_2.lua` and `lib/respawn/book.lua` from the event bundle.
- Restart the event after installing updates.

### Tank Deployment Fails

- Confirm `sp_radar` is attached and working.
- Confirm the server schematic exists: `/vmod schem save-to-server <tank>`
  must have been run once for the tank type on that server. If
  `logs/latest.log` shows `NoSuchFileException: VMod-Schematics\<name>`, the
  schematic file is missing — the folder must contain `<name>.vschem`.
- `Incomplete (expected ... coordinates)` feedback on the place command means
  the rotation argument is missing or unparenthesized — VMod 0.1.3 requires
  a bracketed vector like `(0 0 0)`; the spawner always sends one.
- Run `test_schematic_spawn <tank>` on the computer to isolate the problem:
  it prints the raw feedback of every load/place command.
- Check the tank's availability in the menu: `in use` means the concurrent
  cap is reached (destroy the live tank or raise `maxLive`), `cooldown`
  counts down from the last destruction.
- Confirm the event computer may run `/vmod schem` commands (non-player
  command sources need permission level 4 for VMod commands).
- Verify the selected vehicle spawn location is valid and unobstructed.
- Watch the placement on the first run: if the tank lands offset or facing
  the wrong way, calibrate `anchorOffset`/`rotation` in the mission file.

## Important Files

| Path | Purpose |
| --- | --- |
| `run` | Grandop launcher on the ComputerCraft computer |
| `programs/event_controller.lua` | Unified event runner |
| `missions/lieyu_phase_2.lua` | Map locations, quotas, vehicles, stages, and features |
| `data/loadouts/lieyu_phase_2.json` | Infantry class items and armor |
| `lib/respawn/book.lua` | Chat-button respawn state machine |
| `lib/respawn/vehicles.lua` | Schematic tank deployment and availability handling |
| `/logs/event_lieyu_phase_2_*.log` | Runtime event logs |
| `Grandop/manifests/phase_2_event.txt` | GitHub installation bundle manifest |
