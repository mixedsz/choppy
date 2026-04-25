-- Framework Detection
local ESX = nil
local QBCore = nil
local attachedDrill = nil
local hasDrillEquipped = false

-- Initialize ESX
if GetResourceState("es_extended") == "started" then
    if exports.es_extended then
        ESX = exports.es_extended:getSharedObject()
    end
end

-- Initialize QBCore
if GetResourceState("qb-core") == "started" then
    if exports["qb-core"] then
        QBCore = exports["qb-core"]:GetCoreObject()
    end
end

-- Check if player has an item
function hasItem(itemName)
    if ESX then
        local hasItemResult = nil
        ESX.TriggerServerCallback("devkit_chopshop:server:hasitemesx", function(result)
            hasItemResult = result
        end, itemName)
        -- Wait for callback to complete
        while hasItemResult == nil do
            Wait(10)
        end
        return hasItemResult
    elseif QBCore then
        return QBCore.Functions.HasItem(itemName)
    end
    return false
end

-- Attach drill prop to player
function attachDrillToPlayer(ped)
    local propModel = "sf_prop_impact_driver_01a"
    local boneOffset = {x = 0.14, y = -0.14, z = -0.1}
    local boneRotation = {x = 82.0, y = -94.0, z = 155.0}
    
    local modelHash = GetHashKey(propModel)
    RequestModel(modelHash)
    
    while not HasModelLoaded(modelHash) do
        Wait(10)
    end
    
    attachedDrill = CreateObject(modelHash, 0, 0, 0, true, true, false)
    
    AttachEntityToEntity(
        attachedDrill,
        ped,
        GetPedBoneIndex(ped, 57005), -- Right hand bone
        boneOffset.x, boneOffset.y, boneOffset.z,
        boneRotation.x, boneRotation.y, boneRotation.z,
        true, true, false, true, 1, true
    )
end

-- Setup ox_target for wheel removal
function setupOxTarget()
    if Config.System ~= "ox_target" then
        return
    end

    if not exports.ox_target then
        return
    end

    -- Add target for each wheel bone
    local wheelBones = {"wheel_lf", "wheel_rf", "wheel_lr", "wheel_rr"}
    local wheelNames = {"Left Front Wheel", "Right Front Wheel", "Left Rear Wheel", "Right Rear Wheel"}

    for i, boneName in ipairs(wheelBones) do
        exports.ox_target:addGlobalVehicle({
            {
                name = "devkit_chopshop:removeWheel_" .. boneName,
                icon = "fas fa-screwdriver",
                label = "Remove " .. wheelNames[i],
                bone = boneName,
                distance = Config.WheelDistance or 2.0,
                canInteract = function(entity, distance, coords, name)
                    return hasDrillEquipped and hasItem(Config.RequiredItem)
                end,
                onSelect = function(data)
                    removeClosestWheel()
                end
            }
        })
    end
end

-- Remove ox_target
function removeOxTarget()
    if Config.System ~= "ox_target" then
        return
    end

    if exports.ox_target then
        local wheelBones = {"wheel_lf", "wheel_rf", "wheel_lr", "wheel_rr"}
        for i, boneName in ipairs(wheelBones) do
            exports.ox_target:removeGlobalVehicle("devkit_chopshop:removeWheel_" .. boneName)
        end
    end
end

-- Get closest vehicle (framework specific)
function getClosestVehicle()
    if ESX then
        if ESX.Game then
            return ESX.Game.GetClosestVehicle()
        end
    elseif QBCore then
        if QBCore.Functions then
            return QBCore.Functions.GetClosestVehicle()
        end
    end
end

-- Break off vehicle wheel
function breakVehicleWheel(vehicle, wheelIndex)
    BreakOffVehicleWheel(vehicle, wheelIndex, true, true, true, false)
    ApplyForceToEntity(vehicle, 0, 0, 100.0, 0, 0, 0, 0, 0, 0, true, true, true, true, true, true)
end

-- Main function to remove closest wheel
function removeClosestWheel()
    local playerPed = PlayerPedId()
    local playerCoords = GetEntityCoords(playerPed)
    local closestVehicle = getClosestVehicle()
    
    if not closestVehicle then
        Config.Notify(Config.NotificationMessages.no_vehicle_nearby, "error")
        return
    end
    
    -- Wheel indices and bone names
    local wheelIndices = {0, 1, 2, 3}
    local wheelBones = {"wheel_lf", "wheel_rf", "wheel_lr", "wheel_rr"}
    
    local closestWheelIndex = -1
    local closestDistance = Config.WheelDistance
    local closestWheelCoords = nil
    
    -- Find closest wheel
    for i, wheelIndex in ipairs(wheelIndices) do
        local boneIndex = GetEntityBoneIndexByName(closestVehicle, wheelBones[i])
        
        if boneIndex ~= -1 then
            local wheelCoords = GetWorldPositionOfEntityBone(closestVehicle, boneIndex)
            local distance = #(wheelCoords - playerCoords)
            
            if distance < closestDistance then
                closestDistance = distance
                closestWheelIndex = wheelIndex
                closestWheelCoords = wheelCoords
            end
        end
    end
    
    if closestWheelIndex == -1 then
        Config.Notify(Config.NotificationMessages.no_wheel_nearby, "error")
        return
    end
    
    -- Play animation
    local animDict = "amb@world_human_welding@male@base"
    local animName = "base"
    
    RequestAnimDict(animDict)
    while not HasAnimDictLoaded(animDict) do
        Wait(10)
    end
    
    TaskPlayAnim(playerPed, animDict, animName, 1.0, 1.0, -1, 49, 0, false, false, false)
    
    -- Progress bar
    local duration = Config.WheelDuration or 4000
    local progressLabel = "Removing Wheel..."
    local success = true
    
    if not Config.ProgressBar.enabled then
        Citizen.Wait(duration)
    else
        if Config.ProgressBar.type == "ox" then
            success = lib.progressBar({
                duration = duration,
                label = progressLabel,
                useWhileDead = false,
                canCancel = false,
                disable = {
                    move = true,
                    car = true,
                    combat = true
                }
            })
        elseif Config.ProgressBar.type == "mythic" then
            local mythicResult = false
            exports.mythic_progbar:Progress({
                name = "wheel_removal",
                duration = duration,
                label = progressLabel,
                useWhileDead = false,
                canCancel = false,
                controlDisables = {
                    disableMovement = true,
                    disableCarMovement = true,
                    disableCombat = true,
                    disableMouse = false
                }
            }, function(cancelled)
                mythicResult = cancelled
            end)
            
            while mythicResult == false do
                Wait(50)
            end
            success = mythicResult
        else
            Citizen.Wait(duration)
        end
    end
    
    ClearPedTasks(playerPed)
    
    if not success then
        return
    end
    
    -- Break the wheel
    breakVehicleWheel(closestVehicle, closestWheelIndex)
    Config.Notify(Config.NotificationMessages.wheel_removed, "success")
    
    -- Spawn wheel prop
    if closestWheelCoords then
        local wheelProp = "prop_wheel_03"
        local wheelHash = GetHashKey(wheelProp)
        
        RequestModel(wheelHash)
        while not HasModelLoaded(wheelHash) do
            Wait(10)
        end
        
        local spawnCoords = vector3(
            closestWheelCoords.x + 0.4,
            closestWheelCoords.y + 0.4,
            closestWheelCoords.z
        )
        
        local wheelObject = CreateObject(wheelHash, spawnCoords.x, spawnCoords.y, spawnCoords.z, true, true, false)
        SetEntityHeading(wheelObject, GetEntityHeading(closestVehicle))
        PlaceObjectOnGroundProperly(wheelObject)
        SetEntityAsMissionEntity(wheelObject, true, true)
    end
end

-- Event: Use Impact Drill
RegisterNetEvent('devkit_chopshop:client:useImpactDrill', function()
    if not hasItem(Config.RequiredItem) then
        Config.Notify(Config.NotificationMessages.no_drill, "error")
        return
    end
    
    if hasDrillEquipped then
        Config.Notify("You already have the drill in your hand!", "info")
        return
    end
    
    local playerPed = PlayerPedId()
    attachDrillToPlayer(playerPed)
    hasDrillEquipped = true
    Config.Notify(Config.NotificationMessages.equip_drill, "success")
    setupOxTarget()
end)

-- Thread for TextUI system and key detection
local helpTextShown = false
CreateThread(function()
    while true do
        Wait(0)

        if hasDrillEquipped then
            -- Show help text only once
            if not helpTextShown then
                helpTextShown = true
            end

            -- Display help text every frame when drill is equipped
            showHelpText()

            -- Key detection for G and H
            if IsControlJustPressed(0, 47) then -- G key
                dropDrill()
                helpTextShown = false
            elseif IsControlJustPressed(0, 74) then -- H key
                storeDrill()
                helpTextShown = false
            end

            -- TextUI system for wheel removal
            if Config.System == "textui" then
                local playerPed = PlayerPedId()
                local playerCoords = GetEntityCoords(playerPed)
                local closestVehicle = getClosestVehicle()
                local nearWheel = false
                local closestWheelIndex = -1

                if closestVehicle then
                    local wheelIndices = {0, 1, 2, 3}
                    local wheelBones = {"wheel_lf", "wheel_rf", "wheel_lr", "wheel_rr"}
                    local closestDistance = Config.WheelDistance

                    for i, wheelIndex in ipairs(wheelIndices) do
                        local boneIndex = GetEntityBoneIndexByName(closestVehicle, wheelBones[i])

                        if boneIndex ~= -1 then
                            local wheelCoords = GetWorldPositionOfEntityBone(closestVehicle, boneIndex)
                            local distance = #(wheelCoords - playerCoords)

                            if distance < closestDistance then
                                closestDistance = distance
                                closestWheelIndex = wheelIndex
                                nearWheel = true
                            end
                        end
                    end

                    if closestWheelIndex ~= -1 then
                        Draw2DText("Press [E] to Remove Wheel", 0.5, 0.9)

                        if IsControlJustPressed(0, 38) then -- E key
                            removeClosestWheel()
                        end
                    end
                end
            end
        else
            helpTextShown = false
            Wait(500) -- Only check every 500ms when drill is not equipped
        end
    end
end)

-- Thread to auto-unequip drill when entering vehicle
CreateThread(function()
    while true do
        Wait(500)

        if hasDrillEquipped then
            local playerPed = PlayerPedId()

            if IsPedInAnyVehicle(playerPed, false) then
                storeDrill()
            end
        end
    end
end)

-- Show help text
function showHelpText()
    SetTextComponentFormat("STRING")
    AddTextComponentString("[G] - Drop Impact Drill\n[H] - Store Impact Drill")
    DisplayHelpTextFromStringLabel(0, 0, 1, -1)
end

-- Draw 2D text on screen
function Draw2DText(text, x, y)
    SetTextFont(4)
    SetTextProportional(0)
    SetTextScale(0.35, 0.35)
    SetTextColour(255, 255, 255, 255)
    SetTextOutline()
    SetTextEntry("STRING")
    AddTextComponentString(text)
    DrawText(x, y)
end

-- Store drill
function storeDrill()
    local playerPed = PlayerPedId()
    
    if attachedDrill then
        DeleteObject(attachedDrill)
        attachedDrill = nil
    end
    
    hasDrillEquipped = false
    Config.Notify(Config.NotificationMessages.drill_stored or "Drill stored.", "inform")
    removeOxTarget()
end

-- Drop drill
function dropDrill()
    local playerPed = PlayerPedId()
    
    if attachedDrill then
        DeleteObject(attachedDrill)
        attachedDrill = nil
    end
    
    TriggerServerEvent("devkit_chopshop:server:removeitem", Config.RequiredItem)
    hasDrillEquipped = false
    Config.Notify(Config.NotificationMessages.drill_dropped or "Drill dropped!", "inform")
    removeOxTarget()
end