# item_creator

Create ox_inventory items in-game. Admins fill in a form (`/createitem` or `/create item`),
and the item exists on the server immediately – no server or resource restart. It can be
given with `/giveitem`, used by players and referenced by other scripts right away.

## What the form asks for

| Field | Result |
| --- | --- |
| スポーン名 | item name (`a-z`, `0-9`, `_`) |
| 表示名 | label shown in the inventory |
| 重さ | weight in grams |
| スタック | whether the item stacks |
| 画像URL | downloaded once and saved on the server |
| 体力 / 空腹 / 喉の渇き / ストレス | effect when the item is used (percent of the bar) |
| エクスポート | optional client or server export, `resource.function` |

Created items appear in the list on the right; click one to edit it.

## How it works

ox_inventory keeps its item list in memory and has no way to add to it from another resource.
This resource therefore installs a small **bridge** into ox_inventory:

- `ox_inventory/creator/server.lua` and `creator/client.lua` (new files)
- two lines appended to `ox_inventory/fxmanifest.lua`
- `ox_inventory/data/created_items.lua` – the created items, in normal ox_inventory format

No existing ox_inventory code is changed. The bridge adds each new item to the live item
list on the server and on every client, and loads the saved items on start.

Images are saved to `ox_inventory/web/images/<name>.png`. Until the next restart the picture
is sent to players directly; after a restart it is a normal ox_inventory image.

A copy of the created items and their images is kept in `item_creator/backup/`. If you update
ox_inventory by replacing its folder, the bridge and your items are restored on the next start.

## Installation

1. Put `item_creator` in your `resources` folder.
2. `server.cfg`:

   ```cfg
   ensure ox_lib
   ensure ox_inventory
   ensure item_creator
   ```

3. Start the server **with `item_creator` running**. The console prints
   `The bridge was installed into ox_inventory`. At this point ox_inventory was already
   running, so it has not loaded the bridge yet.
4. **After that message**, restart the server once more (or type `refresh` and then
   `ensure ox_inventory` in the server console). The console then prints
   `[item_creator] ready`. This is the only time a restart is needed.

If it is not active, the console line `[item_creator] not active: ...` says which of the
three cases applies: files missing, ox_inventory not reloaded yet, or the bridge failed to start.
5. Admins need the `group.admin` principal (change in `config.lua`):

   ```cfg
   add_principal identifier.license:xxxxxxxx group.admin
   ```

To install the bridge by hand instead, set `Config.AutoInstall = false`, copy `bridge/server.lua`
and `bridge/client.lua` to `ox_inventory/creator/`, create `ox_inventory/data/created_items.lua`
containing `return {}`, and add to the end of `ox_inventory/fxmanifest.lua`:

```lua
server_script 'creator/server.lua'
client_script 'creator/client.lua'
```

## Discord log

Every created or edited item is posted to Discord with all its settings and who made it.
Use a webhook **or** a bot token + channel id, set in `server.cfg`:

```cfg
set itemcreator:webhook "https://discord.com/api/webhooks/..."
# or
set itemcreator:botToken "your-bot-token"
set itemcreator:channelId "123456789012345678"
```

## Notes

- Hunger, thirst and stress use ox_inventory's `status` field with percentage values, which is
  what Qbox expects.
- An item with a **client** export is handled by that export: it is consumed and its effects
  apply when the export calls `exports.ox_inventory:useItem`.
- Names of existing ox_inventory items cannot be reused.
- After editing an item, players who already saw it keep the old name / picture in their
  inventory window until they reconnect. Weight, effects and exports change immediately.
- Any image format is stored with a `.png` name because ox_inventory only ships `*.png`;
  browsers detect the real format.
