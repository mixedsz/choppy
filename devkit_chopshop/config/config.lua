Config = {}

Config.QBCoreGetCoreObject = 'qb-core'
Config.ESXgetSharedObject = 'es_extended'

Config.AdminGroups = { 'admin', 'superadmin', 'owner', 'god' }
Config.AdminChopShopCommand = 'chopshops'

Config.System = 'textui'  -- 'textui' | 'ox_target'

Config.CarBlacklist = {
    'police',
    'police2',
    'police3',
    'police4',
    'policeb',
    'sheriff',
    'sheriff2',
}

Config.ChoppingTime = 5 -- (in seconds)
Config.FallbackCooldown = 30 -- Fallback cooldown in minutes if shop doesn't have one set

--------------------------------------------------------------------------
-- REWARDS
--------------------------------------------------------------------------
Config.Rewards = {
    Enabled = true,

    Items = {
        -- Each item has a single table: { probability=?, min=?, max=? }
        -- probability is a percentage (0-100)
        iron  = { probability=30, min=2, max=6 },
        steel = { probability=10, min=1, max=1 },
        copper = { probability=25, min=1, max=4 },
        aluminum = { probability=20, min=1, max=3 },
    },

    Currency = {
        type    = 'item',        -- 'item' or 'account'
        payment = 'black_money', -- ESX = 'black_money', QBCore = 'markedbills'
        amount  = { min=35000, max=50000 },
        split   = 50 -- % to business stash, remainder to player
    }
}


--#Vehicle Options
Config.DeleteVehicle = false  -- true = player cars will be deleted from the database | false = it'll just despawn the cars, won't delete them players cars