-- Server-side notification handler
-- This file handles server-triggered notifications to clients

RegisterNetEvent('devkit_chopshopSV:notify', function(target, message, type)
    TriggerClientEvent('devkit_chopshopCL:notify', target, message, type)
end)

-- Helper function to notify a specific player
function NotifyPlayer(playerId, message, type)
    TriggerClientEvent('devkit_chopshopCL:notify', playerId, message, type or 'inform')
end

-- Helper function to notify all players
function NotifyAll(message, type)
    TriggerClientEvent('devkit_chopshopCL:notify', -1, message, type or 'inform')
end