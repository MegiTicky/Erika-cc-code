# Lieyu Phase 2 Event Runbook

This document covers deploying, configuring, starting, updating, and operating
the unified `lieyu_phase_2` Grandop event.

## What Runs On The Event Computer

One Command Computer runs the complete event:

- The staged-capture objective and bossbar.
- The chat-button infantry and tank respawn menus.
- Infantry class loadouts and teleports.
- Tank deployment, stock, and cooldown tracking.
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
reinforcement quotas, vehicle stock, retreat flags, and paused state. It is
checkpointed after deployments, operator changes, stage changes, and every 15
seconds. Restarting the controller restores this state automatically.

Writes use ComputerCraft table serialization, verify the temporary write by
reading it back, and retain the previous snapshot as `.bak`. If the snapshot
is corrupt or does not match its mission ID/schema, startup fails
closed instead of silently overwriting live match progress. Investigate it, or
perform an intentional reset, before starting the controller again.

Use `Stop for new-match reset` on the operator terminal before a fresh match.
It clears the snapshot, legacy vehicle stock, and configured scoreboards after
the controller stops. The reset flags below remain available for unattended
ROM-started deployments.

The mission deliberately preserves persistent state by default:

- `spawnCount` preserves troop consumption between controller restarts.
- `tanksList.txt` preserves current tank stock between controller restarts.

For a brand-new match or an intentional full reset, edit
`missions/lieyu_phase_2.lua` on the event computer and temporarily change:

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

The reset initializes these counters:

| Counter | Initial value | Meaning |
| --- | --- | --- |
| `USMC spawnCount` | 0 | USMC deployments consumed |
| `TownX_JP spawnCount` | 0 | Japan Town X deployments consumed |
| `TownY_JP spawnCount` | 0 | Japan Town Y deployments consumed |
| `TownZ_JP spawnCount` | 0 | Japan Town Z deployments consumed |

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

The menu uses chat buttons, not written books or `/trigger` objectives. The
player should click each menu option once and wait for the next menu message.

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

- USMC starts with three `sherman75usmc` tanks.
- Japan starts with two `chinu` tanks and one `horo` tank.
- Tank cooldowns are 180 seconds.
- Tank stock is stored in `tanksList.txt` on the event computer.

## Tickets And Troop Strength

The capture objective starts with 500 tickets for each team. Capturing an
objective awards the attacker 200 tickets and removes 50 defender tickets.

The sidebar objective is `Troops_Strength`:

- `USMCSpawn` starts at 100 and decreases once for each successful USMC infantry
  or tank deployment.
- `TownX_JPSpawn`, `TownY_JPSpawn`, and `TownZ_JPSpawn` start at 30, 30, and 40.
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

### Steve's Army Spawn Eggs

Steve's Army soldier eggs can be added directly to a class loadout:

```json
{ "item": "steves_army:soldier_spawn_egg", "count": 1 }
```

The player must place the egg themselves. This is intentional: the current
Steve's Army spawn egg assigns the player as owner, assigns the selected fire
team, and adds the soldier to that player's squad. Do not replace this with a
plain `/summon steves_army:soldier`; a plain summon bypasses that player-owned
squad setup.

A basic spawn egg creates a default soldier. A pre-equipped NPC requires a
tested egg `EntityTag` inventory preset from Steve's Army. Test those presets in
a separate world before adding them to the event loadout.

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
- Check the matching `spawnCount` scoreboard entry.
- Confirm the current event computer has the updated
  `missions/lieyu_phase_2.lua` and `lib/respawn/book.lua` from the event bundle.
- Restart the event after installing updates.

### Tank Deployment Fails

- Confirm `sp_radar` is attached and working.
- Check that a tank remains in `tanksList.txt`.
- Wait for the 180-second tank cooldown if the menu says it is active.
- Verify the selected vehicle spawn location is valid and unobstructed.

## Important Files

| Path | Purpose |
| --- | --- |
| `run` | Grandop launcher on the ComputerCraft computer |
| `programs/event_controller.lua` | Unified event runner |
| `missions/lieyu_phase_2.lua` | Map locations, quotas, vehicles, stages, and features |
| `data/loadouts/lieyu_phase_2.json` | Infantry class items and armor |
| `lib/respawn/book.lua` | Chat-button respawn state machine |
| `lib/respawn/vehicles.lua` | Tank deployment and stock handling |
| `tanksList.txt` | Persistent current tank stock on the event computer |
| `/logs/event_lieyu_phase_2_*.log` | Runtime event logs |
| `Grandop/manifests/phase_2_event.txt` | GitHub installation bundle manifest |
