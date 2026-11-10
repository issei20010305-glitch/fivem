# item_spawner

Admin item spawner for ox_inventory. `/itemspawner` (or `/spawnitem`) opens a window that
shows every ox_inventory item with its picture, including items made with `item_creator`.

- Search bar (item label or spawn name, several words allowed)
- Filters: all / items / weapons / ammo / weapon parts / created items
- Amount chooser: −/＋, typed value, quick buttons
- Give to yourself, or to another player by server ID
- Double-click a card to give it straight away
- Optional Discord log of every spawn

## Install

1. Put `item_spawner` in your `resources` folder.
2. `server.cfg`, after ox_inventory:

   ```cfg
   ensure ox_lib
   ensure ox_inventory
   ensure item_spawner
   ```

3. Admins need the `group.admin` principal (change in `config.lua`).

No restart of ox_inventory is needed, and nothing in ox_inventory is changed.

## Config (`config.lua`)

| Setting | Meaning |
| --- | --- |
| `Config.Commands` | command names |
| `Config.AdminGroups` | who may use it |
| `Config.MaxAmount` | largest amount per click (default 1000) |
| `Config.QuickAmounts` | the quick amount buttons |
| `Config.AllowGiveToOthers` | allow giving to another player's ID |

Discord log (optional), in `server.cfg`:

```cfg
set itemspawner:webhook "https://discord.com/api/webhooks/..."
```

## Notes

- The server checks the admin permission, that the item exists, the amount and that the
  target can carry it; the window itself gives nothing.
- The item list is read from ox_inventory when the window opens and reused for up to a
  minute. Items created with `item_creator` appear the next time it is opened.
- An item without a picture shows a "?" placeholder.
