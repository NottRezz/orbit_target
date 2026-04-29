fx_version 'cerulean'
game 'gta5'

name        'orbit_target'
description 'Advanced dual-mode targeting system for superhero scripts'
author      'Orbit'
version     '1.0.0'

shared_scripts {
    'shared/config.lua',
}

client_scripts {
    'client/targeting.lua',
    'client/exports.lua',
}

server_scripts {
    'server/main.lua',
}

ui_page 'html/index.html'

files {
    'html/index.html',
    'html/style.css',
    'html/app.js',
}
