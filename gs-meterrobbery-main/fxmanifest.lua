fx_version 'cerulean'
game 'gta5'

name 'gs-meterrobbery'
author 'NRG Development'
description 'Parking Meter Robbery Script for FiveM - Compatible with QBCore and ESX'
version '1.0.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config/config.lua',
    'config/locales.lua'
}

client_scripts {
    'client/main.lua',
    'client/target.lua'
}

server_scripts {
    'server/main.lua'
}

dependencies {
    'ox_lib'
}

lua54 'yes'