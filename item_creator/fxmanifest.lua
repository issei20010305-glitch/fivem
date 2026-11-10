fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'item_creator'
description 'In-game item creator for ox_inventory (no restart needed)'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_scripts {
    'server/files.js',
    'server/main.lua',
}

client_script 'client/main.lua'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'images/*.png',
}

dependencies {
    'ox_lib',
    'ox_inventory',
}
