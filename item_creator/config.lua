Config = {}

-- Commands that open the creator. The first one is also used for the permission check.
Config.Commands = { 'createitem' }

-- Also register "/create item" (a command named "create" with the argument "item").
-- Turn this off if another resource already uses /create.
Config.CreateSubcommand = true

-- ACE principals allowed to create items. Checked again on the server for every request.
Config.AdminGroups = { 'group.admin' }

-- Copy the bridge files into ox_inventory and add them to its fxmanifest automatically.
-- After the first install the server has to be restarted ONCE.
Config.AutoInstall = true

Config.Image = {
    maxBytes = 512 * 1024, -- biggest image that will be downloaded
    timeoutMs = 15000,
}

-- Discord logging. Use EITHER a webhook OR a bot token + channel id.
-- Recommended: keep secrets out of this file and set them in server.cfg instead:
--   set itemcreator:webhook "https://discord.com/api/webhooks/..."
--   set itemcreator:botToken "your bot token"
--   set itemcreator:channelId "123456789012345678"
Config.Discord = {
    webhook   = '',
    botToken  = '',
    channelId = '',
    username  = 'Item Creator',
    colour    = 0x263141,
}

-- Time (ms) it takes to use an item that heals / feeds.
Config.UseTime = 2500

Config.Limits = {
    name        = 50,
    label       = 50,
    description = 200,
    weight      = 1000000, -- grams
}
