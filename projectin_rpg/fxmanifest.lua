fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'projectin_rpg'
author 'Project IN'
description 'Project IN ダンジョン & ボスレイド (Qbox / ox_inventory / oxmysql)'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
    'shared/utils.lua',
    'shared/items.lua',
    'shared/schema.lua',
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'data/default_content.lua',
    'server/bridge.lua',
    'server/db.lua',
    'server/characters.lua',
    'server/rpg_inventory.lua',
    'server/holding.lua',
    'server/parties.lua',
    'server/instances.lua',
    'server/combat.lua',
    'server/events.lua',
    'server/editor.lua',
    'server/admin.lua',
    'server/main.lua',
}

client_scripts {
    'client/nui.lua',
    'client/main.lua',
    'client/instance.lua',
    'client/combat.lua',
    'client/editor.lua',
}

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
}

dependencies {
    'oxmysql',
    'ox_lib',
    'ox_inventory',
    'qbx_core',
}
