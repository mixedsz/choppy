
fx_version 'adamant'
game 'gta5'

author 'Devkit'
description 'Chopshop Script'

lua54 'yes'

shared_scripts {
   '@ox_lib/init.lua',
   'config/*.lua',
}

client_scripts {
   'client/*.lua',
}

server_scripts {
   '@oxmysql/lib/MySQL.lua',
   'server/*.lua',
}

escrow_ignore{
   'client/cl_notifications.lua',
   'server/sv_notifications.lua',
   'config/*.lua',
}
dependency '/assetpacks'
