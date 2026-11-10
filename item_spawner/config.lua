Config = {}

-- Commands that open the spawner. The first one is also used for the permission check.
Config.Commands = { 'itemspawner', 'spawnitem' }

-- ACE principals allowed to use it. Checked again on the server for every request.
Config.AdminGroups = { 'group.admin' }

-- Biggest amount that can be given in one click.
Config.MaxAmount = 1000

-- Buttons next to the amount field.
Config.QuickAmounts = { 1, 5, 10, 50, 100 }

-- Allow giving items to another player by server ID (otherwise only to yourself).
Config.AllowGiveToOthers = true

-- Optional Discord log of every spawned item. Set it in server.cfg rather than here:
--   set itemspawner:webhook "https://discord.com/api/webhooks/..."
Config.Webhook = ''
