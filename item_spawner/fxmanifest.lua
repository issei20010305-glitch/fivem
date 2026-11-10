fx_version 'cerulean'
game 'gta5'
lua54 'yes'

name 'item_spawner'
description 'Admin item spawner for ox_inventory with images, search and amount chooser'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua',
}

server_script 'server.lua'
client_script 'client.lua'

ui_page 'web/index.html'

files {
    'web/index.html',
    'web/style.css',
    'web/app.js',
}

dependencies {
    'ox_lib',
    'ox_inventory',
}
