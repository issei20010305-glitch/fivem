# Heist Creator

An in-game heist builder for **Qbox**. Admins create complete heists with `/createheist`
(no config editing needed), players pick them up from the **Heist HUD** at an NPC, form a
party and play them together. All in-game text is Japanese.

## Features

- **Admin creator** (`/createheist`): name, description, image, required Heist XP, XP reward,
  start point, any number of hack / minigame stages (Press E or ox_target, optional required
  item, minigame + difficulty per stage), NPC guards (model, weapon, health, armour, accuracy,
  behaviour), loot points, loot table (chance + min/max amount, guaranteed rewards, several
  rewards can drop from one loot point), required police, extraction point, server-wide and
  per-player cooldowns, time limit and party size.
- **Heist HUD**: available / locked heists, XP requirement, police requirement and current
  police count, cooldowns, difficulty, expected rewards, party members.
- **Party system**: create a party, invite nearby players or by server ID, shared progress.
- **Heist XP** with party bonus (1 = +0 %, 2 = +10 %, 3 = +20 %, 4+ = +30 %).
- **Guidance**: objective card and notification bubbles (bottom-right), blips and GPS waypoints
  that follow the current objective.
- **Server authoritative**: the whole heist state machine runs on the server.

## Dependencies

| Resource | Notes |
| --- | --- |
| [qbx_core](https://github.com/Qbox-project/qbx_core) | framework |
| [ox_lib](https://github.com/overextended/ox_lib) | callbacks, commands, UI helpers |
| [ox_inventory](https://github.com/overextended/ox_inventory) | items and rewards |
| [ox_target](https://github.com/overextended/ox_target) | NPC and stage interactions |
| [oxmysql](https://github.com/overextended/oxmysql) | database |
| OneSync | required (server-side position checks, guard cleanup) |

## Installation

1. Copy the `heist_creator` folder into your `resources` directory.
2. Import `sql/install.sql` into your database.
   (With `Config.Database.autoInstall = true`, the default, the tables are also created
   automatically on first start.)
3. Add to `server.cfg` **after** the dependencies:

   ```cfg
   ensure oxmysql
   ensure ox_lib
   ensure qbx_core
   ensure ox_inventory
   ensure ox_target
   ensure heist_creator
   ```

4. Admin access uses ACE. By default every principal in `group.admin` may use the creator
   (`Config.AdminGroups`). Example:

   ```cfg
   add_principal identifier.license:xxxxxxxxxxxxxxxx group.admin
   ```

5. Make sure the items you want to use in loot tables / as required items exist in
   `ox_inventory/data/items.lua` (for the example table: `diamond`, `ruby`, `gold`,
   `black_money`). Item names are validated when a heist is saved.
6. Restart the server, then use `/createheist` in-game.

## Creating a heist

1. `/createheist` opens the creator. The unsaved draft is kept when you close the window, so
   you can walk to the next spot and reopen it.
2. Fill the tabs from left to right:
   - **基本情報** – name, description, image URL, difficulty, required XP, XP reward.
   - **参加条件・クールダウン** – required police, party size, time limit, cooldowns.
   - **開始・脱出地点** – start point (+ radius) and extraction point.
   - **ステージ** – one card per stage: objective text, position, interaction
     (Press E / ox_target), minigame, difficulty, optional required item (and whether it is
     consumed).
   - **ガード** – NPC guards. "複製" copies a guard, then move it with "現在位置".
   - **物色ポイント** – lootable locations and how long looting takes.
   - **報酬テーブル** – the loot table. Every row is rolled separately for each loot point.
3. Positions: **現在位置** uses where you stand, **照準で指定** lets you aim with the camera
   and confirm with `E`, **TP** teleports you to a saved position.
4. Press **保存**. The heist is stored in the database and is immediately available.

Example loot table from the request:

| Item | 確定 | 確率 | Amount |
| --- | --- | --- | --- |
| diamond | – | 10 % | configurable |
| ruby | – | 20 % | configurable |
| gold | – | 20 % | configurable |
| black_money | – | 50 % | configurable |
| black_money | ✓ | 100 % | configurable |

The Heist HUD NPC is placed from the creator as well (**受付NPCの設定**).

## Playing

1. Talk to the heist NPC (ox_target) to open the Heist HUD.
2. Optionally create a party and invite players (nearby list or server ID). Invited players
   accept in the Heist HUD or with `/heistaccept`.
3. The party leader starts a heist. Flow: go to the start point → clear every stage in order →
   loot the marked locations → extract.
4. `/cancelheist` cancels the heist (leader) or leaves it (member).

## Commands

| Command | Who | Description |
| --- | --- | --- |
| `/createheist` | admin | open the Heist Creator |
| `/setheistxp [id] [amount]` | admin | set a player's Heist XP |
| `/cancelheist` | player | cancel (leader) / leave (member) the running heist |
| `/heistaccept`, `/heistdecline` | player | answer a party invite |

Command names can be changed in `Config.Commands`.

## Configuration (`shared/config.lua`)

| Section | What it controls |
| --- | --- |
| `Config.AdminGroups`, `Config.Commands` | permissions and command names |
| `Config.Police` | police job names, on-duty requirement |
| `Config.PoliceAlert` | built-in police alert / hook for a dispatch resource |
| `Config.XP` | party bonus, ranks, who needs the required XP, participation distance |
| `Config.Cooldowns` | whether failed / cancelled heists trigger cooldowns |
| `Config.Party` | party size, invite timeout, nearby radius |
| `Config.Notify` | Heist HUD bubbles or ox_lib notifications |
| `Config.Minigames` | minigame list – add your own with one entry |
| `Config.NuiMinigames` | difficulty of the built-in minigames |
| `Config.Guards`, `Config.Interaction`, `Config.Guidance` | guards, markers, blips, GPS |
| `Config.Security`, `Config.Limits` | validation tolerances and creator limits |

All texts are in `shared/locale.lua` (the UI texts are in `web/`).

### Adding a minigame

```lua
Config.Minigames.my_hack = {
    label = 'My Hack',
    run = function(difficulty)            -- 'easy' | 'medium' | 'hard', runs on the client
        return exports['my_hack']:Start() -- must return true on success
    end,
}
```

It then appears in the stage's minigame dropdown.

## Security model

- Clients only *request* actions; the server validates the session, phase, stage order,
  distance (server-side ped position), required items, police count, XP and cooldowns.
- Stage and loot attempts are locked per player; a loot point is marked as looted *before*
  rewards are handed out, so it can never pay out twice.
- Rewards and XP are rolled and granted only on the server, only to party members of the
  session. XP goes to members who are at the extraction point (`Config.XP.participationDistance`).
- Every creator action re-checks the admin ACE and sanitizes all input.
- Minigames run on the client by nature; the server enforces a minimum duration and position.

## Behaviour notes

- Only one crew can run a given heist at a time.
- Disconnecting or switching character removes the player from the party and the heist; if
  nobody is left the heist ends. Leadership passes to the next member.
- A resource restart ends running heists cleanly (guards removed, no cooldown applied).
  Heists, XP, cooldowns and NPC locations are stored in the database and survive restarts.
- If a player cannot carry a reward it is dropped at their feet instead of being lost.

## File structure

```
heist_creator/
├── fxmanifest.lua
├── sql/install.sql
├── shared/   config.lua, locale.lua, utils.lua
├── server/   framework.lua (Qbox / ox_inventory bridge), database.lua, cooldowns.lua, xp.lua,
│             heists.lua, settings.lua, party.lua, session.lua, main.lua
├── client/   nui.lua, interact.lua, minigames.lua, guidance.lua, npc.lua, hud.lua,
│             creator.lua, heist.lua, main.lua
└── web/      index.html, css/style.css, js/ (app, overlay, minigames, creator, hud)
```
