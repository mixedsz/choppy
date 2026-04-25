--#Notifications
Config.Notifications = 'ox'  -- 'ox' | 'mythic' | 'custom'

Config.Notify = function(message, type)
    if Config.Notifications == 'ox' then
        lib.notify({
            title = 'Chop Shop',
            description = message,
            type = type,
            position = 'top',
            duration = 5000
        })
    elseif Config.Notifications == 'mythic' then
        exports["mythic_notify"]:SendAlert(type, message, 5000)
    elseif Config.Notifications == 'custom' then
        --enter your code
    end
end

Config.NotificationMessages = {
    no_drill         = "You don't have an Impact Drill!",
    equip_drill      = "You equipped the Impact Drill.",
    no_vehicle_nearby= "No vehicle nearby!",
    no_wheel_nearby  = "No wheel nearby!",
    wheel_removed    = "You removed the wheel!",
    tire_hand        = "You already have a wheel in your hand!",
    failed           = "You failed to remove the wheel!",
    drill_stored     = "You stored the Impact Drill.",
    drill_dropped    = "You dropped the Impact Drill!",
}

--#ProgressBar
Config.ProgressBar = {
    enabled = true, -- true = uses progress bar | false = doesn't use progress bar
    type = 'ox' -- 'ox' | 'mythic'
}



-- Dispatch Options
Config.Dispatch = 'cd_dispatch' -- 'cd_dispatch' | 'custom' | false
Config.AlertPercentage = 0 -- 0-100 (100 max)

Config.PoliceJobs = {
    'police',
    --'sheriff',
}

Config.Alerts = function(coords)
    if Config.Dispatch == 'cd_dispatch' then
        local data = exports['cd_dispatch']:GetPlayerInfo()
        local playerCoords = coords

        TriggerServerEvent('cd_dispatch:AddNotification', {
            job_table = Config.PoliceJobs,
            coords = playerCoords,
            title = '10-17 - Suspicious Person',
            message = ('A %s is selling drugs near %s'):format(data.sex, data.street),
            flash = 0,
            unique_id = data.unique_id,
            sound = 1,
            blip = {
                sprite  = 161,
                scale   = 1.0,
                colour  = 2,
                flashes = false,
                text    = '10-17 - Suspicious Person',
                time    = 5,
                radius  = 0,
            }
        })
    elseif Config.Dispatch == 'custom' then
        -- Add your own code
    end
end



--TEXT UI
Config.ShowTextUI = function(text)
    lib.showTextUI(text, {
        iconAnimation = 'fade',
        icon = 'fa-solid fa-car',
        iconColor = 'black',
    })
end

Config.HideTextUI = function()
    lib.hideTextUI()
end
