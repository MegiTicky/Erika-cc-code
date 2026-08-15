# TODO

## Mission State Persistence

- [x] Decide the mission state schema and recovery semantics.
- [x] Store mission progress in a versioned JSON state file.
- [x] Persist the current stage and capture progress.
- [x] Persist objective ownership and other mode-specific state.
- [x] Persist tickets and reinforcement quotas.
- [x] Save state after important changes and periodically for crash recovery.
- [x] Write state atomically through a temporary file and replacement.
- [x] Validate state version, fields, ranges, and mission ID before loading.
- [x] Restore the saved state automatically after a server or computer crash.
- [x] Add a deliberate new-match reset that clears saved state safely.

## Operator Backend

- [x] Define operator permissions and command safety rules.
- [x] Implement a terminal-based operator interface on a dedicated operator computer.
- [x] Add an operator status view for stage, tickets, and quotas.
- [ ] Add commands to set or advance the current stage.
- [ ] Add commands to set, increase, or decrease capture progress.
- [ ] Add commands to inspect, reset, set, or adjust faction and town quotas.
- [ ] Add commands to inspect and adjust tickets.
- [x] Add pause, resume, and graceful shutdown commands.
- [x] Add a deliberate full mission reset command with confirmation.
- [ ] Consider optional authorized chat access for simple operator commands.
- [x] Add confirmation prompts for destructive operations.
- [x] Add operator audit logging with operator computer identity, command, and timestamp.

## Newcomer Onboarding

- [x] Detect players who are not assigned to a mission team.
- [x] Send newcomers a clear chat prompt explaining how to join a team.
- [x] Add secure chat buttons for joining the available teams.
- [x] Validate team selection before changing the player's team.
- [x] Add the player to the selected Minecraft team.
- [x] Teleport the player to that team's current staging-area spawn.
- [x] Apply the correct faction and mission-side setup after joining.
- [x] Prevent onboarding prompts from repeatedly spamming the same player.
- [x] Clear onboarding state when the player joins a team or leaves the server.
- [x] Handle stage changes by moving newly joined players to the current staging area.
- [ ] Add an operator option to enable, disable, or reset newcomer onboarding.

## Artillery Integration

- [ ] Review the existing artillery server protocol and available peripherals.
- [ ] Define how artillery batteries identify their faction and owning team.
- [ ] Define how artillery requests are submitted and authorized.
- [ ] Connect artillery availability to mission stage and team state where appropriate.
- [ ] Add artillery status to the operator backend.
- [ ] Add operator controls for artillery enable, disable, reset, and cooldowns.
- [ ] Integrate artillery events with mission tickets, objectives, or reinforcement rules if required.
- [ ] Add safe handling for disconnected artillery computers and unavailable peripherals.
- [ ] Add artillery command and event logging.
- [ ] Test artillery integration independently before enabling it in a live mission.

## Documentation And Testing

- [x] Document crash recovery and state-file behavior.
- [ ] Document terminal operator commands and safety procedures.
- [ ] Test state recovery after a server crash.
- [ ] Test state recovery after a ComputerCraft computer restart.
- [ ] Test deliberate mission reset and saved-state replacement.
- [ ] Test operator controls in a separate world before live deployment.
