fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'Heist Creator'
description 'In-game heist creator with party system, Heist XP and the Heist HUD (Qbox / ox)'
author 'Heist Creator'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'shared/config.lua',
    'shared/locale.lua',
    'shared/utils.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/framework.lua',
    'server/database.lua',
    'server/cooldowns.lua',
    'server/xp.lua',
    'server/heists.lua',
    'server/settings.lua',
    'server/party.lua',
    'server/session.lua',
    'server/main.lua',
}

client_scripts {
    'client/nui.lua',
    'client/interact.lua',
    'client/minigames.lua',
    'client/guidance.lua',
    'client/npc.lua',
    'client/hud.lua',
    'client/creator.lua',
    'client/heist.lua',
    'client/main.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/css/*.css',
    'web/js/*.js',
}

dependencies {
    '/onesync',
    'ox_lib',
    'oxmysql',
    'qbx_core',
    'ox_inventory',
    'ox_target',
}
