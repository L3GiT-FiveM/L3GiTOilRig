fx_version 'cerulean'
game 'gta5'

name 'L3GiTOilRig'
author 'L3GiT'
description 'Modular Oil Rig Operator Job w/Ccustom UI & Notifications'
version '1.0.1'

lua54 'yes'

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/terminal.css',
    'html/script.js'
}

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/persistence.lua',
    'server/main.lua'
}

dependencies {
    'ox_lib',
    'ox_target',
    'ox_inventory',
    'oxmysql'
}

