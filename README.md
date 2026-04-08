# TTS Guild Contribution Manager

A World of Warcraft addon for guild officers to track weekly consumable
contributions and raid attendance / DKP for the **Three Tank Strat**
guild — and any other guild that wants the same workflow.

Two independent trackers in one addon, sharing a single roster:

- **Consumable Contribution** — weekly minimum gold dues with automatic
  guild-bank deposit detection, manual mark for off-bank payments
  (mail / trade), per-week minimums you can edit retroactively, a
  compounding 1.5× penalty for unpaid weeks, hiatus mode for raid
  breaks, and a separate higher tier ("Alchemist Min") for crafters.

- **Assistance Tracking** — per-raid-day attendance (Tue/Wed/Thu),
  one-click "scan current raid group", configurable handling of
  missing players, color-coded weekly grid, DKP balances with manual
  +5/-5 adjustments, automatic gold fines (5,000g for late no-notice,
  10,000g for absent no-notice, escalating +1,000g for repeat offenders,
  1,000g per missing enchant), DKP audit log, and `/raid` chat post.

---

## Installation

1. Download the addon as a folder named exactly **`TTSGuildContributionManager`**
   (the folder name MUST match the `.toc` file name without the extension).

2. Drop the folder into your retail AddOns directory:

   - **Windows:** `C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns\`
   - **macOS:**   `/Applications/World of Warcraft/_retail_/Interface/AddOns/`

   The final path should look like:
   ```
   .../Interface/AddOns/TTSGuildContributionManager/
       TTSGuildContributionManager.toc
       Core.lua
       UI.lua
       AssistanceTracker.lua
       ... etc ...
       Libs/
   ```

3. Launch WoW. At the character select screen, click **AddOns** in the
   bottom-left and verify "TTS Guild Contribution Manager" appears and
   is enabled.

4. Log in. You should see `TTSGuildContributionManager: loaded.` in chat.

### Compatibility

- **WoW Retail (Midnight)** — Interface version `120000`
- Tested on patch 12.0.x

If your client is on a slightly different build, the addon will still
load (you may see an "out of date" warning that you can ignore by
ticking "Load out of date AddOns" at the addons screen).

---

## Quick start

After installing, the minimum setup to start tracking:

1. Open the main window with **`/gcm`** (or click the coin minimap icon).
2. On the **Consumable Contribution** tab:
   - Pick **First week** from the dropdown (e.g. "This Tuesday")
   - Type your weekly minimum in the **Min (gold)** box and press Enter
   - Optionally type the **Alchemist Min (gold)** for crafters
   - Click **Add Players...** and check the players you want to track
3. Walk to the guild bank in-game and open it. The addon auto-scans the
   money log and credits each tracked player's deposits.
4. Switch to the **Assistance Tracking** tab.
5. When raid starts at 19:30 server time, click **Mark Raid Group** at
   ~20:45 server time. Pick how to handle missing players from the
   "Missing players" dropdown (Leave empty / Absent notified / Absent
   no notice).
6. Click any player's **Edit** button to override individual day
   statuses, adjust DKP, or record manually-paid fines.

---

## The two tabs in detail

### Consumable Contribution

Tracks per-week gold dues. Each tracked player owes the configured
weekly minimum (alchemists owe a separate, usually higher amount).

| Status | Color | Meaning |
|---|---|---|
| `[PAID]` | green | They've met or exceeded the minimum this week |
| `[PARTIAL]` | yellow | They've paid some but not the full minimum |
| `[UNPAID]` | red | They owe the full minimum |
| `[—]` | gray | No minimum has been set yet |

Each row shows: status pill, name (with `[A]` for alchemists), paid /
owed / remaining, and an Edit button.

Bottom bar: **Add Players...**, **Scan Bank Now**, **Past Weeks**,
**Start/End Hiatus**, **Prune History**, **Refresh**.

**Penalty rule:** unpaid balance from week W carries to week W+1
multiplied by **1.5×**, then the new week's minimum is added on top.
Example with 1000g/week minimum, player pays nothing:

| End of week | Owed at start of next week |
|---|---|
| W1 | 1000 × 1.5 + 1000 = **2500** |
| W2 | 2500 × 1.5 + 1000 = **4750** |
| W3 | 4750 × 1.5 + 1000 = **8125** |

**Bank scan** is automatic when you open the guild bank UI. The addon
hooks `PLAYER_INTERACTION_MANAGER_FRAME_SHOW` for the GuildBanker
interaction type and queries the money log on tab 9. Player names from
the bank log are matched case-insensitively against tracked names with
the realm suffix stripped, so cross-realm guilds work correctly.

**Past Weeks editor** lets you edit minimums and per-player marks for
the last 5 weeks (or any older week with outstanding debt). Useful if
the bank log rolled over before you scanned, or someone paid via mail.

**Hiatus mode** freezes debt accrual during raid breaks. While active:
- Hiatus weeks have an effective minimum of 0
- The 1.5× penalty multiplier becomes 1.0× (debt freezes, not compounds)
- When you toggle hiatus off, normal accrual resumes from whatever
  balance was carried in

### Assistance Tracking

Tracks per-raid-day attendance for the Tue/Wed/Thu raid schedule.

**Status codes** (collapsed from the original Excel):

| Code | Internal | DKP | Gold fine | Notes |
|---|---|---|---|---|
| `K` (green) | OK | 0 | 0 | On time |
| `T` (red) | LATE (no notice) | -5 | 5,000g + escalation | Late, didn't tell raid leader |
| `O` (yellow) | Late (notified) | -5 | 0 | Late but notified ahead |
| `A` (yellow) | Absent (notified) | -5 | 0 | Absent, notified ahead |
| `AS` (red) | ABSENT (no notice) | -10 | 10,000g | Absent, no notice |
| `V` (blue) | Vacation | -10 per week | 0 | -10 once per week even if multiple V days |
| `C` (gray) | Cancelled | 0 | 0 | Raid was cancelled |
| `-` (gray) | (unset) | — | — | Not yet marked |

**Tardy escalation:** the 1st `T` of the tier is 5,000g flat. The 2nd
adds +1,000g (6,000g total), the 3rd adds +2,000g (7,000g), etc. The
escalation only counts no-notice tardies — `O` (notified) doesn't
contribute to it and is never fined.

**Mark Raid Group** is non-destructive. It scans the player's current
raid group and only fills in *missing* slots — never overwrites a
status that was already set, manually or otherwise. The dropdown next
to it controls what missing players get marked as:

- **Leave empty** — only fill in present players, leave missing alone
- **Absent (notified)** — fill missing players with `A`
- **Absent (no notice)** — fill missing players with `AS`

You can re-press the button as people trickle in throughout the raid.
It's safe and idempotent.

**Edit per-player:** click any row's Edit button to open the per-player
detail view. Inside you can:
- Change the status of any of the three raid days via dropdown
- Adjust DKP by `+5`, `-5`, `+10`, or `-10`
- Set the missing-enchant count for that week (0-42, multiplied by
  1,000g per missing enchant)
- Mark a custom amount of fine debt as paid (or clear paid)

**DKP Standings** view (button in the action bar) lists every tracked
player's DKP balance, lowest first. Each row has a `Post to /raid`
button so you can broadcast a single player's DKP to the raid channel.
A `Post all to /raid` button at the top batches everyone into a few
chat lines.

**Audit Log** view shows every DKP change with timestamp, player,
signed delta, source (`[auto]` for status-driven, `[manual]` for
button-driven), and reason. Capped at 200 entries.

**Past Weeks** view (in the assistance tab too) lets you go back up to
12 weeks within the current tier. Open any week to see / edit its grid.

**Reset Tier** wipes all DKP, raid events, and assistance fines. Use
when a new content tier launches and the slate should be cleaned. The
audit log is preserved (with a "tier reset" marker).

### Settings tab

Currently informational only:
- Tells you where your data is saved (see below)
- Shows the addon version

The earlier paste-based import/export was removed by request. All data
lives locally in your SavedVariables file.

---

## Data storage

WoW saves the addon's state to:

- **Windows:**  
  `WTF/Account/<account>/SavedVariables/TTSGuildContributionManager.lua`
- **macOS:**  
  `WTF/Account/<account>/SavedVariables/TTSGuildContributionManager.lua`

Inside your WoW install folder. The file is rewritten when you log out
or `/reload` the UI.

**To back up:** copy that single file. To restore on another machine,
drop it in the same `SavedVariables/` directory before launching WoW.

---

## Slash commands

The bare `/gcm` command toggles the main window. Type `/gcm help` for
the full reference. Below is a digest:

### General

| Command | Description |
|---|---|
| `/gcm` | Toggle main window |
| `/gcm show` | Open main window |
| `/gcm help` | Print full help |
| `/gcm minimap` | Toggle the minimap button |
| `/gcm debug` | Toggle verbose bank-scan diagnostics |

### Consumable Contribution

| Command | Description |
|---|---|
| `/gcm setmin <gold>` | Set this week's regular minimum |
| `/gcm setalchmin <gold>` | Set this week's alchemist minimum |
| `/gcm alchemist <name>` | Toggle alchemist status for a tracked player |
| `/gcm setfirstweek <0-5>` | Pick week 1 (0 = current Tue, max 5 weeks back) |
| `/gcm hiatus` | Toggle raid hiatus (debt stops accruing) |
| `/gcm scan` | Manually request the guild bank money log (must be at the bank) |
| `/gcm history [N]` | Print the last N weeks of contributions to chat |
| `/gcm dumpweek` | Print raw current-week DB contents (debugging) |
| `/gcm prune` | Delete eligible old weeks now |
| `/gcm track <name>` | Add a player to the tracked list |
| `/gcm untrack <name>` | Remove a tracked player |
| `/gcm tracked` | List currently tracked players |
| `/gcm roster [rank] [search]` | Inspect the guild roster |
| `/gcm ranks` | List guild ranks |
| `/gcm mark <player> <gold>` | Manually credit a player this week |
| `/gcm clearmark <player>` | Clear this week's manual mark for a player |
| `/gcm unpaid` | List unpaid tracked players for this week |
| `/gcm owed <player>` | Show one player's owed/paid/remaining |

### Assistance Tracking

| Command | Description |
|---|---|
| `/gcm raid mark` | Scan raid; missing players left empty |
| `/gcm raid mark abs_w` | Scan raid; missing players → absent (notified) |
| `/gcm raid mark abs_no` | Scan raid; missing players → absent (no notice) |
| `/gcm raid show` | Print today's attendance + DKP per tracked player |
| `/gcm raid set <player> <status>` | Manual override (status = `ok`, `late_no`, `late_w`, `abs_w`, `abs_no`, `vac`, `cancel`) |
| `/gcm raid dkp <player> <delta>` | Adjust DKP by ±N (e.g. `+5`, `-10`) |
| `/gcm raid resettier [label]` | Wipe DKP + attendance for a new tier |
| `/gcm dkp <player>` | Post one player's DKP to /raid (or /party) |
| `/gcm dkp all` | Post every current raid member's DKP to /raid |

---

## Common workflows

### Setting up a new week's minimum

1. Open `/gcm`, Consumable tab
2. Type the new amount in **Min (gold)** and press Enter
3. (Optional) Type the alchemist amount in **Alchemist Min (gold)**

The minimum is stamped on the current week and becomes the sticky
default for future weeks until you change it again.

### Recording a mail/trade payment for consumables

1. Open `/gcm`
2. Click the player's **Edit** button
3. In **Manual mark**, type the amount in gold (or leave empty to mark
   exactly the remaining balance) and click **Mark Paid**

### Recording a mail/trade payment for assistance fines

1. Open `/gcm`, Assistance tab
2. Click the player's **Edit** button
3. In the **Fines this week** block, type the amount in gold (blank =
   remaining) and click **Mark Paid**

### Marking the raid roster mid-raid

1. Open `/gcm`, Assistance tab
2. Pick "Leave empty" / "Absent (notified)" / "Absent (no notice)" from
   the **Missing players** dropdown
3. Click **Mark Raid Group**
4. As more people join, click **Mark Raid Group** again — only the
   newly-arrived players will be added as OK; already-marked players
   are untouched

### Posting DKP to /raid

- **One player:** `/gcm dkp PlayerName` or click their `Post to /raid`
  button on the DKP Standings view
- **All raid members:** `/gcm dkp all` or click `Post all to /raid` on
  the DKP Standings view

### Starting a new tier

1. Open `/gcm`, Assistance tab
2. Click **Reset Tier** in the action bar (confirm in the popup)

This wipes all DKP balances, raid events, and assistance fines for the
new tier. Tracked players and consumable data are unaffected.

---

## Author

**Nachorizo** — built for the Three Tank Strat guild on Ragnaros.

---

## License

Personal use. Source available on GitHub.
