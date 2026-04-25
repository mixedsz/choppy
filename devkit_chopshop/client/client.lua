-- Framework Detection
local ESX = nil
local QBCore = nil
local playerIdentifier = nil
local allShops = {}
local shopBlips = {}
local activeZones = {}
local bossMenuTargets = {}
local lastChopTimes = {}

-- Initialize frameworks
CreateThread(function()
    while true do
        if ESX or QBCore then
            break
        end
        
        -- Try to get ESX
        if GetResourceState(Config.ESXgetSharedObject) == "started" then
            if exports[Config.ESXgetSharedObject] then
                ESX = exports[Config.ESXgetSharedObject]:getSharedObject()
            end
        end
        
        -- Try to get QBCore
        if GetResourceState(Config.QBCoreGetCoreObject) == "started" then
            if exports[Config.QBCoreGetCoreObject] then
                QBCore = exports[Config.QBCoreGetCoreObject]:GetCoreObject()
            end
        end
        
        Wait(250)
    end
    
    -- Get player identifier
    if ESX then
        while true do
            local playerData = ESX.GetPlayerData()
            if playerData and playerData.identifier then
                break
            end
            Wait(250)
        end
        playerIdentifier = ESX.GetPlayerData().identifier
    elseif QBCore then
        while true do
            local playerData = QBCore.Functions.GetPlayerData()
            if playerData and playerData.citizenid then
                break
            end
            Wait(250)
        end
        playerIdentifier = QBCore.Functions.GetPlayerData().citizenid
    end
    
    -- Request all shops from server
    TriggerServerEvent("devkit_chopshop:requestAllShops")
end)

-- Helper: Convert rotation to direction vector
function RotationToDirection(rotation)
    local adjustedRotation = {
        x = math.rad(rotation.x),
        y = 0,
        z = math.rad(rotation.z)
    }
    
    local direction = {
        x = -math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        y = math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        z = math.sin(adjustedRotation.x)
    }
    
    return direction
end

-- Get raycast hit position from camera
function GetCameraRayCastPosition(distance)
    local camRot = GetGameplayCamRot()
    local camPos = GetGameplayCamCoord()
    local direction = RotationToDirection(camRot)
    local destination = vector3(
        camPos.x + direction.x * distance,
        camPos.y + direction.y * distance,
        camPos.z + direction.z * distance
    )
    
    local _, hit, hitCoords = GetShapeTestResult(StartShapeTestRay(
        camPos.x, camPos.y, camPos.z,
        destination.x, destination.y, destination.z,
        -1, -1, 1
    ))
    
    return hitCoords
end

-- Pick coordinates using raycast
local isPickingCoords = false

function PickCoordRaycast(locationType)
    isPickingCoords = true
    Config.Notify(string.format("Point at the %s location and LEFT-CLICK or press [E] to set it.", locationType), "inform")
    
    local pickedCoords = nil
    
    while isPickingCoords do
        Wait(0)
        
        local camPos = GetGameplayCamCoord()
        local hitCoords = GetCameraRayCastPosition(300.0)
        
        if hitCoords then
            -- Draw line from camera to hit point
            DrawLine(camPos.x, camPos.y, camPos.z, hitCoords.x, hitCoords.y, hitCoords.z, 255, 0, 0, 255)
            
            -- Draw marker at hit point
            DrawMarker(28, hitCoords.x, hitCoords.y, hitCoords.z, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.3, 0.3, 255, 0, 0, 150, false, false, 2, nil, nil, false)
        end
        
        if IsControlJustPressed(0, 24) then -- Left mouse button
            pickedCoords = hitCoords
            isPickingCoords = false
        elseif IsControlJustPressed(0, 38) then -- E key
            pickedCoords = hitCoords
            isPickingCoords = false
        end
    end
    
    if pickedCoords then
        local x = string.format("%.2f", pickedCoords.x)
        local y = string.format("%.2f", pickedCoords.y)
        local z = string.format("%.2f", pickedCoords.z)
        Config.Notify(string.format("Picked %s coords: %s, %s, %s", locationType, x, y, z), "success")
    else
        Config.Notify("No coords picked!", "error")
    end
    
    return pickedCoords
end

-- Helper function to check chop access
local function canChopAtShop(shopId, shopData)
    -- Check ownership/access
    if shopData.owner then
        if shopData.owner ~= "" then
            local isOwner = shopData.owner == playerIdentifier
            local isEmployee = false

            for _, empId in ipairs(shopData.employees or {}) do
                if empId == playerIdentifier then
                    isEmployee = true
                    break
                end
            end

            if not isOwner and not isEmployee then
                return false, "You do not have access to chop here."
            end
        end
    end

    -- Check cooldown
    local cooldown = shopData.cooldown or Config.FallbackCooldown
    local lastChop = lastChopTimes[shopId]
    local currentTime = GetGameTimer()
    local cooldownMs = cooldown * 60 * 1000

    if lastChop and cooldownMs > (currentTime - lastChop) then
        local remaining = cooldownMs - (currentTime - lastChop)
        local remainingSec = math.floor(remaining / 1000)
        return false, string.format("Chop Shop on cooldown.\nWait %d more seconds.", remainingSec)
    end

    return true, nil
end

-- Helper function to process vehicle chop
local function processVehicleChop(vehicle, shopId)
    local plate = GetVehicleNumberPlateText(vehicle)
    local model = GetEntityModel(vehicle)
    local displayName = GetDisplayNameFromVehicleModel(model)

    -- Check blacklist
    for _, blacklisted in ipairs(Config.CarBlacklist) do
        if string.upper(displayName) == string.upper(blacklisted) then
            Config.Notify("We are not interested in this car model.", "error")
            return false
        end
    end

    lastChopTimes[shopId] = GetGameTimer()
    TriggerServerEvent("devkit_chopshop:removeownedvehicle", plate)

    -- Hide TextUI before starting chop
    if Config.System ~= "ox_target" then
        Config.HideTextUI()
    end

    ChopVehicle(vehicle, shopId)
    return true
end

-- Setup chop zones
function setupChopZones()
    -- Remove existing zones
    for _, zone in ipairs(activeZones) do
        if Config.System == "ox_target" then
            exports.ox_target:removeZone(zone)
        else
            zone:remove()
        end
    end
    activeZones = {}

    -- Create new zones
    for shopId, shopData in pairs(allShops) do
        local coords = shopData.coords or {}

        for _, coord in ipairs(coords) do
            if Config.System == "ox_target" then
                -- ox_target implementation
                local zoneId = exports.ox_target:addSphereZone({
                    coords = vec3(coord.x, coord.y, coord.z),
                    radius = 5.0,
                    debug = false,
                    options = {
                        {
                            name = "chop_vehicle_" .. shopId,
                            label = "Chop Vehicle",
                            icon = "fas fa-car-crash",
                            canInteract = function(entity, distance, coords, name)
                                local playerPed = PlayerPedId()
                                if not IsPedInAnyVehicle(playerPed, false) then
                                    return false
                                end

                                local canChop, errorMsg = canChopAtShop(shopId, shopData)
                                return canChop
                            end,
                            onSelect = function(data)
                                local playerPed = PlayerPedId()
                                local vehicle = GetVehiclePedIsIn(playerPed, false)
                                if vehicle and vehicle ~= 0 then
                                    processVehicleChop(vehicle, shopId)
                                end
                            end
                        }
                    }
                })

                table.insert(activeZones, zoneId)
            else
                -- textui implementation
                local zone = lib.zones.sphere({
                    coords = vec3(coord.x, coord.y, coord.z),
                    radius = 5.0,
                    debug = false,
                    textUIShown = false,
                    lastTextUIMessage = "",
                    isChopping = false,
                    onEnter = function(self)
                        -- Reset state when entering zone
                        self.textUIShown = false
                        self.lastTextUIMessage = ""
                        self.isChopping = false
                    end,
                    inside = function(self)
                        -- Skip if currently chopping
                        if self.isChopping then
                            return
                        end

                        local playerPed = PlayerPedId()

                        local canChop, errorMsg = canChopAtShop(shopId, shopData)

                        if not canChop then
                            local msg = errorMsg or "Cannot chop here"

                            if not self.textUIShown or self.lastTextUIMessage ~= msg then
                                if self.textUIShown then
                                    Config.HideTextUI()
                                end
                                Config.ShowTextUI(msg)
                                self.textUIShown = true
                                self.lastTextUIMessage = msg
                            end
                            return
                        end

                        -- Check if in vehicle
                        if IsPedInAnyVehicle(playerPed, false) then
                            local msg = "[E] - Chop this vehicle"

                            if not self.textUIShown or self.lastTextUIMessage ~= msg then
                                if self.textUIShown then
                                    Config.HideTextUI()
                                end
                                Config.ShowTextUI(msg)
                                self.textUIShown = true
                                self.lastTextUIMessage = msg
                            end

                            if IsControlJustPressed(0, 38) then -- E key
                                local vehicle = GetVehiclePedIsIn(playerPed, false)
                                self.isChopping = true

                                -- Process chop in a separate thread
                                CreateThread(function()
                                    local success = processVehicleChop(vehicle, shopId)

                                    -- Wait a bit for the chop to complete
                                    Wait(1000)

                                    -- Reset state after chopping
                                    self.isChopping = false
                                    self.textUIShown = false
                                    self.lastTextUIMessage = ""
                                end)
                            end
                        else
                            if self.textUIShown then
                                Config.HideTextUI()
                                self.textUIShown = false
                                self.lastTextUIMessage = ""
                            end
                        end
                    end,
                    onExit = function(self)
                        if self.textUIShown then
                            Config.HideTextUI()
                            self.textUIShown = false
                            self.lastTextUIMessage = ""
                        end
                        self.isChopping = false
                    end
                })

                table.insert(activeZones, zone)
            end
        end
    end
end

-- Setup blips
function setupBlips()
    print("^3[ChopShop DEBUG] setupBlips called^0")

    -- Remove existing blips
    for _, blip in ipairs(shopBlips) do
        if DoesBlipExist(blip) then
            RemoveBlip(blip)
        end
    end
    shopBlips = {}

    -- Create new blips
    local blipCount = 0
    for shopId, shopData in pairs(allShops) do
        print(string.format("^3[ChopShop DEBUG] Shop #%d: %s^0", shopId, shopData.name or "Unknown"))

        -- Use chopping coords for blip location
        local coords = shopData.coords or {}
        local blipData = shopData.blip or {}

        print(string.format("^3[ChopShop DEBUG] Blip data: sprite=%s, color=%s, scale=%s^0",
            tostring(blipData.sprite), tostring(blipData.color), tostring(blipData.scale)))

        -- If no chop coords, don't create blip (don't fall back to boss coords)
        if #coords > 0 then
            if blipData.sprite and blipData.sprite > 0 then
                blipData.color = blipData.color or 42
                blipData.scale = blipData.scale or 0.7

                -- Use first chopping location for blip
                local coord = coords[1]
                if coord and coord.x and coord.y and coord.z then
                    local blip = AddBlipForCoord(coord.x, coord.y, coord.z)

                    if not DoesBlipExist(blip) then
                        print("^1[ChopShop DEBUG] FAILED to create blip!^0")
                    else
                        SetBlipSprite(blip, blipData.sprite)
                        SetBlipDisplay(blip, 4)
                        SetBlipScale(blip, blipData.scale)
                        SetBlipColour(blip, blipData.color)
                        SetBlipAsShortRange(blip, true)  -- TRUE = Show on map when in range, FALSE = always on radar
                        SetBlipAlpha(blip, 255)  -- Full opacity
                        SetBlipCategory(blip, 1)  -- Category: default
                        BeginTextCommandSetBlipName("STRING")
                        AddTextComponentString(shopData.name or ("ChopShop #" .. tostring(shopId)))
                        EndTextCommandSetBlipName(blip)

                        -- Force blip to show
                        SetBlipPriority(blip, 10)  -- High priority
                        SetBlipHiddenOnLegend(blip, false)  -- Show in legend

                        table.insert(shopBlips, blip)
                        blipCount = blipCount + 1

                        local verifySprite = GetBlipSprite(blip)
                        local verifyColor = GetBlipColour(blip)
                        local verifyAlpha = GetBlipAlpha(blip)

                        print(string.format("^2[ChopShop DEBUG]   Verify: sprite=%d, color=%d, alpha=%d^0",
                            verifySprite, verifyColor, verifyAlpha))

                        print(string.format("^2[ChopShop DEBUG] Created blip at CHOPPING location for shop #%d at %.2f, %.2f, %.2f^0",
                            shopId, coord.x, coord.y, coord.z))

                        print(string.format("^2[ChopShop DEBUG]   Set: sprite=%d, color=%d, scale=%.2f^0",
                            blipData.sprite, blipData.color, blipData.scale))
                    end
                else
                    print("^1[ChopShop DEBUG] Invalid coords for shop #" .. shopId .. "^0")
                end
            else
                print(string.format("^1[ChopShop DEBUG] Blip disabled or invalid sprite for shop #%d (sprite=%s)^0",
                    shopId, tostring(blipData.sprite)))
            end
        else
            print("^1[ChopShop DEBUG] No chopping coords for shop #" .. shopId .. "^0")
        end
    end

    print(string.format("^2[ChopShop DEBUG] Created %d blips total^0", blipCount))
end

-- Setup boss menu markers
function setupBossMenuMarkers()
    CreateThread(function()
        while true do
            Wait(0)
            local playerPed = PlayerPedId()
            local playerCoords = GetEntityCoords(playerPed)
            local nearAnyBoss = false

            for shopId, shopData in pairs(allShops) do
                local bosscoords = shopData.bosscoords
                if bosscoords and bosscoords.x then
                    local bossPos = vector3(bosscoords.x, bosscoords.y, bosscoords.z)
                    local distance = #(playerCoords - bossPos)

                    if distance < 50.0 then
                        nearAnyBoss = true
                        -- Draw marker at boss menu location (raised 1.0 unit above ground)
                        DrawMarker(
                            20, -- Marker type (cylinder)
                            bosscoords.x, bosscoords.y, bosscoords.z + 1.0,
                            0.0, 0.0, 0.0, -- Direction
                            0.0, 0.0, 0.0, -- Rotation
                            0.5, 0.5, 0.5, -- Scale
                            255, 0, 0, 150, -- RGBA (red with transparency)
                            false, -- Bob up and down
                            true, -- Face camera
                            2, -- Rotation order
                            false, nil, nil, false
                        )
                    end
                end
            end

            if not nearAnyBoss then
                Wait(500) -- If not near any boss menu, check less frequently
            end
        end
    end)
end

-- Event: Receive all shops
RegisterNetEvent("devkit_chopshop:receiveAllShops")
AddEventHandler("devkit_chopshop:receiveAllShops", function(shops)
    print("^3[ChopShop DEBUG] Received shops from server^0")

    -- Count shops properly (works with non-sequential keys)
    local shopCount = 0
    for _ in pairs(shops) do shopCount = shopCount + 1 end
    print("^3[ChopShop DEBUG] Number of shops: " .. tostring(shopCount) .. "^0")

    allShops = shops

    print("^3[ChopShop DEBUG] Setting up boss menu targets...^0")
    setupBossMenuTargets()

    print("^3[ChopShop DEBUG] Setting up chop zones...^0")
    setupChopZones()

    print("^3[ChopShop DEBUG] Setting up blips...^0")
    setupBlips()

    print("^3[ChopShop DEBUG] Setting up boss menu markers...^0")
    setupBossMenuMarkers()

    print("^2[ChopShop DEBUG] All shops setup complete!^0")
end)

-- Event: Receive shop data (for purchase/management)
RegisterNetEvent("devkit_chopshop:receiveShopData")
AddEventHandler("devkit_chopshop:receiveShopData", function(shopData)
    if not shopData then
        return
    end
    
    -- If no owner, show purchase menu
    if not shopData.owner or shopData.owner == "" then
        local shopId = shopData.id
        local price = shopData.price or 50000
        local contextId = "purchase_menu_" .. shopId
        
        lib.registerContext({
            id = contextId,
            title = string.format("Buy %s", shopData.name or ("ChopShop #" .. shopId)),
            options = {
                {
                    title = "Purchase Business",
                    description = string.format("Price: $%d", price),
                    icon = "fa-solid fa-cart-shopping",
                    onSelect = function()
                        TriggerServerEvent("devkit_chopshop:buyShop", shopId, price)
                    end
                }
            }
        })
        lib.showContext(contextId)
    else
        -- If owner matches, show boss menu
        if shopData.owner == playerIdentifier then
            openBossMenu(shopData)
        else
            Config.Notify("This chop shop is owned by someone else.", "error")
        end
    end
end)

-- Open boss menu
function openBossMenu(shopData)
    if not shopData then
        return
    end
    
    local shopName = shopData.name or ("ChopShop #" .. tostring(shopData.id))
    local menuId = "boss_menu_" .. tostring(shopData.id)
    local title = string.format("%s [MANAGEMENT]", shopName)
    local balance = shopData.money or 0
    local sellPrice = shopData.price or 50000
    
    lib.registerContext({
        id = menuId,
        title = title,
        options = {
            {
                title = "Withdraw Funds",
                icon = "fa-solid fa-money-bill",
                description = string.format("Business Balance: $%d", balance),
                onSelect = function()
                    local input = lib.inputDialog("Withdraw Funds", {
                        {type = "number", label = "Amount"}
                    })
                    if not input then return end
                    
                    local amount = tonumber(input[1]) or 0
                    if amount > 0 then
                        TriggerServerEvent("devkit_chopshop:withdrawFunds", shopData.id, amount)
                    end
                end
            },
            {
                title = "Sell Business",
                icon = "fa-solid fa-store-slash",
                description = string.format("Value: $%d", sellPrice),
                onSelect = function()
                    local alert = lib.alertDialog({
                        header = "Sell Business",
                        content = "Are you sure you want to sell?",
                        centered = true,
                        cancel = true
                    })
                    if alert == "confirm" then
                        TriggerServerEvent("devkit_chopshop:sellBusiness", shopData.id)
                    end
                end
            },
            {
                title = "Transfer Business",
                icon = "fa-solid fa-exchange-alt",
                description = "Transfer ownership to another player",
                onSelect = function()
                    local input = lib.inputDialog("Transfer Business", {
                        {type = "number", label = "Player ID"}
                    })
                    if not input then return end
                    
                    local targetId = tonumber(input[1])
                    if targetId and targetId > 0 then
                        TriggerServerEvent("devkit_chopshop:transferBusiness", shopData.id, targetId)
                    end
                end
            },
            {
                title = "Manage Employees",
                icon = "fa-solid fa-users",
                description = "Hire & Fire employees for this shop",
                onSelect = function()
                    openOwnerManageEmployeesMenu(shopData.id)
                end
            }
        }
    })
    lib.showContext(menuId)
end

-- Owner: Manage employees menu
function openOwnerManageEmployeesMenu(shopId)
    local menuId = "chopshop_owner_manage_employees_" .. tostring(shopId)
    local title = "Manage Employees"
    
    local options = {
        {
            title = "Hire Employee",
            icon = "fa-solid fa-user-plus",
            description = "Hire a new employee by Player ID",
            onSelect = function()
                local input = lib.inputDialog("Hire Employee", {
                    {type = "number", label = "Player ID"}
                })
                if not input then return end
                
                local targetId = tonumber(input[1]) or 0
                if targetId < 1 then return end
                
                TriggerServerEvent("devkit_chopshop:ownerHireEmployeeById", shopId, targetId)
            end
        },
        {
            title = "Fire Employee",
            icon = "fa-solid fa-user-minus",
            description = "Fire an existing employee from a list",
            onSelect = function()
                openOwnerFireEmployeesList(shopId)
            end
        }
    }
    
    lib.registerContext({
        id = menuId,
        title = title,
        options = options
    })
    lib.showContext(menuId)
end

-- Owner: Fire employees list
function openOwnerFireEmployeesList(shopId)
    local shop = allShops[shopId]
    if not shop then return end
    
    local employees = shop.employees or {}
    if #employees < 1 then
        Config.Notify("No employees to fire!", "error")
        return
    end
    
    local options = {}
    for _, empId in ipairs(employees) do
        table.insert(options, {
            title = empId,
            description = "Fire this employee",
            onSelect = function()
                local alert = lib.alertDialog({
                    header = "Fire Employee",
                    content = string.format("Are you sure you want to fire %s?", empId),
                    centered = true,
                    cancel = true
                })
                if alert == "confirm" then
                    TriggerServerEvent("devkit_chopshop:ownerFireEmployeeByIdentifier", shopId, empId)
                end
            end
        })
    end
    
    local menuId = "chopshop_owner_fire_list_" .. shopId
    lib.registerContext({
        id = menuId,
        title = "Fire Employee(s)",
        options = options
    })
    lib.showContext(menuId)
end

-- Event: Open admin main menu
RegisterNetEvent("devkit_chopshop:openAdminMainMenu")
AddEventHandler("devkit_chopshop:openAdminMainMenu", function(shops)
    allShops = shops
    
    local options = {}
    
    for shopId, shopData in pairs(shops) do
        table.insert(options, {
            title = string.format("[%d] %s", shopId, shopData.name or ("ChopShop #" .. shopId)),
            description = string.format("Owner: %s | Price: $%d | Cooldown: %d min", 
                shopData.owner or "None",
                shopData.price or 50000,
                shopData.cooldown or Config.FallbackCooldown
            ),
            onSelect = function()
                openAdminShopDetails(shopId)
            end
        })
    end
    
    table.insert(options, {
        title = "Setup a Chopshop",
        icon = "fa-solid fa-plus",
        description = "Create a new Chopshop",
        onSelect = function()
            setupChopShopDialogRaycast()
        end
    })
    
    lib.registerContext({
        id = "devkit_chopshop_admin_menu",
        title = "Chop Shops",
        options = options
    })
    lib.showContext("devkit_chopshop_admin_menu")
end)

-- Admin: Shop details menu
function openAdminShopDetails(shopId)
    -- Always get fresh shop data
    local shop = allShops[shopId]
    if not shop then
        Config.Notify("Invalid shop ID: " .. tostring(shopId), "error")
        return
    end

    print(string.format("^3[ChopShop DEBUG] Opening admin details for shop #%d, blip sprite: %s^0",
        shopId, tostring((shop.blip or {}).sprite)))

    local menuId = "chopshop_admin_details_" .. tostring(shopId)
    local title = string.format("Edit Shop #%d (%s)", shopId, shop.name or "??")
    
    local options = {
        {
            title = "Edit Name",
            description = "Change the shop's name",
            icon = "fa-solid fa-pen-to-square",
            onSelect = function()
                local input = lib.inputDialog("Change Shop Name", {
                    {type = "input", label = "New Name", default = shop.name or ""}
                })
                if not input then return end
                
                local newName = input[1] or ""
                TriggerServerEvent("devkit_chopshop:adminUpdateShopName", shopId, newName)
            end
        },
        {
            title = "Manage Employees",
            description = "Hire & Fire employees for this shop",
            icon = "fa-solid fa-users",
            onSelect = function()
                openAdminManageEmployeesMenu(shopId)
            end
        },
        {
            title = "Edit Price",
            description = string.format("Current Price: $%d", shop.price or 50000),
            icon = "fa-solid fa-tag",
            onSelect = function()
                local input = lib.inputDialog("Edit Shop Price", {
                    {type = "number", label = "New Price", default = shop.price or 50000}
                })
                if not input then return end
                
                local newPrice = tonumber(input[1]) or 50000
                TriggerServerEvent("devkit_chopshop:adminUpdateShopPrice", shopId, newPrice)
            end
        },
        {
            title = "Edit Cooldown (minutes)",
            description = string.format("Current: %d", shop.cooldown or Config.FallbackCooldown),
            icon = "fa-solid fa-hourglass-half",
            onSelect = function()
                local input = lib.inputDialog("Change Shop Cooldown (minutes)", {
                    {type = "number", label = "New Cooldown", default = shop.cooldown or Config.FallbackCooldown}
                })
                if not input then return end
                
                local newCooldown = tonumber(input[1]) or 30
                TriggerServerEvent("devkit_chopshop:adminUpdateCooldown", shopId, newCooldown)
            end
        },
        {
            title = "Edit Blip",
            description = "Change the blip (sprite/color/scale, enable/disable)",
            icon = "fa-solid fa-map-pin",
            onSelect = function()
                -- Always get fresh data from allShops
                local currentShop = allShops[shopId]
                if not currentShop then
                    Config.Notify("Shop not found!", "error")
                    return
                end

                local blipData = currentShop.blip or {}
                local sprite = blipData.sprite or 0
                local color = blipData.color or 42
                local scale = blipData.scale or 0.7
                local enabled = sprite > 0

                print(string.format("^3[ChopShop DEBUG] Opening blip editor - current sprite: %d, enabled: %s^0", sprite, tostring(enabled)))

                local input = lib.inputDialog("Edit Blip", {
                    {type = "checkbox", label = "Enable Blip?", default = enabled},
                    {type = "number", label = "Sprite", default = (sprite > 0 and sprite or 225)},
                    {type = "number", label = "Color", default = color},
                    {type = "number", label = "Scale", default = scale}
                })
                if not input then return end

                local newEnabled = input[1]
                local newSprite = tonumber(input[2]) or 225
                local newColor = tonumber(input[3]) or 42
                local newScale = tonumber(input[4]) or 0.7

                -- If disabled, set sprite to 0, otherwise use the provided sprite
                if not newEnabled then
                    newSprite = 0
                elseif newSprite == 0 then
                    -- If enabled but sprite is 0, use default sprite
                    newSprite = 225
                end

                print(string.format("^3[ChopShop DEBUG] Saving blip - sprite: %d, color: %d, scale: %.2f^0", newSprite, newColor, newScale))
                TriggerServerEvent("devkit_chopshop:adminUpdateShopBlip", shopId, newSprite, newColor, newScale)

                -- Wait for server to update and client to receive new data
                Wait(500)

                -- Notify user
                Config.Notify("Blip settings saved!", "success")
            end
        },
        {
            title = "Delete Shop",
            description = "Delete this chop shop.",
            icon = "fa-solid fa-trash",
            onSelect = function()
                local alert = lib.alertDialog({
                    header = "Delete ChopShop",
                    content = string.format("Are you sure you want to delete shop #%d (%s)?", shopId, shop.name or "??"),
                    centered = true,
                    cancel = true
                })
                if alert == "confirm" then
                    TriggerServerEvent("devkit_chopshop:adminDeleteShop", shopId)
                end
            end
        }
    }
    
    lib.registerContext({
        id = menuId,
        title = title,
        options = options
    })
    lib.showContext(menuId)
end

-- Admin: Manage employees
function openAdminManageEmployeesMenu(shopId)
    local menuId = "chopshop_admin_manage_employees_" .. tostring(shopId)
    local title = "Manage Employees"
    
    local options = {
        {
            title = "Hire Employee",
            icon = "fa-solid fa-user-plus",
            description = "Hire a new employee by Player ID",
            onSelect = function()
                local input = lib.inputDialog("Hire Employee", {
                    {type = "number", label = "Player ID"}
                })
                if not input then return end
                
                local targetId = tonumber(input[1]) or 0
                if targetId < 1 then return end
                
                TriggerServerEvent("devkit_chopshop:adminHireEmployeeById", shopId, targetId)
            end
        },
        {
            title = "Fire Employee",
            icon = "fa-solid fa-user-minus",
            description = "Fire an existing employee from a list",
            onSelect = function()
                openAdminFireEmployeesList(shopId)
            end
        }
    }
    
    lib.registerContext({
        id = menuId,
        title = title,
        options = options
    })
    lib.showContext(menuId)
end

-- Admin: Fire employees list
function openAdminFireEmployeesList(shopId)
    local shop = allShops[shopId]
    if not shop then return end
    
    local employees = shop.employees or {}
    if #employees < 1 then
        Config.Notify("No employees to fire!", "error")
        return
    end
    
    local options = {}
    for _, empId in ipairs(employees) do
        table.insert(options, {
            title = empId,
            description = "Fire this employee",
            onSelect = function()
                local alert = lib.alertDialog({
                    header = "Fire Employee",
                    content = string.format("Are you sure you want to fire %s?", empId),
                    centered = true,
                    cancel = true
                })
                if alert == "confirm" then
                    TriggerServerEvent("devkit_chopshop:adminRemoveEmployee", shopId, empId)
                end
            end
        })
    end
    
    local menuId = "chopshop_admin_fire_list_" .. shopId
    lib.registerContext({
        id = menuId,
        title = "Fire Employee(s)",
        options = options
    })
    lib.showContext(menuId)
end

-- Setup chopshop with raycast
function setupChopShopDialogRaycast()
    -- Pick boss menu location
    local bossCoords = PickCoordRaycast("Boss Menu")
    if not bossCoords then return end

    Wait(500)

    -- Pick chop location
    local chopCoords = PickCoordRaycast("Chop Location")
    if not chopCoords then return end

    -- Get shop details
    local input = lib.inputDialog("Setup New Chopshop", {
        {type = "input", label = "Chop Shop Name", placeholder = "Franklin's Chopshop"},
        {type = "number", label = "Price", default = 50000},
        {type = "number", label = "Cooldown (minutes)", default = 30},
        {type = "number", label = "Blip Sprite", default = 225},
        {type = "number", label = "Blip Color", default = 42},
        {type = "number", label = "Blip Scale", default = 0.7}
    })
    if not input then return end

    local shopName = input[1] or "Unnamed Chop"
    local price = tonumber(input[2]) or 50000
    local cooldown = tonumber(input[3]) or 30
    local blipSprite = tonumber(input[4]) or 225
    local blipColor = tonumber(input[5]) or 42
    local blipScale = tonumber(input[6]) or 0.7

    -- Always create blip at chopping location (automatically enabled)
    local blipData = {
        sprite = blipSprite,
        color = blipColor,
        scale = blipScale
    }

    local bossLocation = {x = bossCoords.x, y = bossCoords.y, z = bossCoords.z}
    local chopLocations = {{x = chopCoords.x, y = chopCoords.y, z = chopCoords.z}}

    local newShop = {
        name = shopName,
        price = price,
        cooldown = cooldown,
        coords = chopLocations,
        bosscoords = bossLocation,
        blip = blipData
    }

    TriggerServerEvent("devkit_chopshop:createShop", newShop)
end

-- Progress bar wrapper
function doProgressBar(duration, label)
    if not Config.ProgressBar.enabled then
        Wait(duration)
        return true
    end
    
    if Config.ProgressBar.type == "ox" then
        return lib.progressBar({
            duration = duration,
            label = label,
            canCancel = false,
            disable = {
                move = true,
                car = true,
                combat = true
            }
        })
    elseif Config.ProgressBar.type == "mythic" then
        local result = false
        exports.mythic_progbar:Progress({
            name = "devkit_chop_action",
            duration = duration,
            label = label,
            canCancel = false,
            controlDisables = {
                disableMovement = true,
                disableCarMovement = true,
                disableCombat = true
            },
            animation = {
                animDict = "anim@amb@clubhouse@tutorial@bkr_tut_ig3@",
                anim = "machinic_loop_mechandplayer"
            }
        }, function(cancelled)
            result = cancelled
        end)
        
        while not result do
            Wait(50)
        end
        return result
    else
        Wait(duration)
        return true
    end
end

-- Chop vehicle function
function ChopVehicle(vehicle, shopId)
    if not DoesEntityExist(vehicle) then
        return
    end
    
    local doorCount = GetNumberOfVehicleDoors(vehicle)
    local doorIndices = {0, 1, 4, 5}
    
    -- Chop doors
    if doorCount > 4 then
        for i = 0, doorCount - 1 do
            SetVehicleDoorOpen(vehicle, i, false, false)
            doProgressBar(Config.ChoppingTime * 1000, "Chopping Vehicle...")
            Wait(100)
            SetVehicleDoorBroken(vehicle, i, false)
        end
    else
        for _, doorIndex in ipairs(doorIndices) do
            if doorCount > doorIndex then
                SetVehicleDoorOpen(vehicle, doorIndex, false, false)
                doProgressBar(Config.ChoppingTime * 1000, "Chopping Vehicle...")
                Wait(100)
                SetVehicleDoorBroken(vehicle, doorIndex, false, false)
            end
        end
    end
    
    TriggerEvent("DeleteEntity")
    TriggerServerEvent("devkit_chopshop:payout", shopId)
end

-- Event: Delete entity
RegisterNetEvent("DeleteEntity")
AddEventHandler("DeleteEntity", function()
    local playerPed = PlayerPedId()
    local vehicle = GetVehiclePedIsIn(playerPed, false)
    
    if IsPedSittingInAnyVehicle(playerPed) then
        SetEntityAsMissionEntity(vehicle, true, true)
        TaskLeaveVehicle(playerPed, vehicle, 0)
        Wait(2000)
        
        NetworkFadeOutEntity(vehicle, true, false)
        Wait(2000)
        
        -- Delete vehicle using framework or native
        if ESX then
            if ESX.Game then
                ESX.Game.DeleteVehicle(vehicle)
            end
        elseif QBCore then
            if QBCore.Functions then
                QBCore.Functions.DeleteVehicle(vehicle)
            end
        else
            DeleteVehicle(vehicle)
        end
        
        -- Chance to alert police
        if math.random(100) <= Config.AlertPercentage then
            Config.Alerts(GetEntityCoords(playerPed))
        end
    end
end)

-- Setup boss menu targets
function setupBossMenuTargets()
    print("^3[ChopShop DEBUG] setupBossMenuTargets called, System: " .. Config.System .. "^0")

    if Config.System == "ox_target" then
        -- Remove existing targets
        for shopId, zoneId in pairs(bossMenuTargets) do
            exports.ox_target:removeZone(zoneId)
        end
        bossMenuTargets = {}

        -- Create new targets
        local targetCount = 0
        for shopId, shopData in pairs(allShops) do
            local bossCoords = shopData.bosscoords
            if bossCoords and bossCoords.x then
                local zoneId = exports.ox_target:addSphereZone({
                    coords = vec3(bossCoords.x, bossCoords.y, bossCoords.z),
                    radius = 1.0,
                    debug = false,
                    options = {
                        {
                            name = "boss_menu_" .. shopId,
                            label = "Manage Chop Shop",
                            onSelect = function()
                                TriggerServerEvent("devkit_chopshop:getShopData", shopId)
                            end
                        }
                    }
                })
                bossMenuTargets[shopId] = zoneId
                targetCount = targetCount + 1
                print(string.format("^2[ChopShop DEBUG] Created ox_target boss zone for shop #%d at %.2f, %.2f, %.2f^0",
                    shopId, bossCoords.x, bossCoords.y, bossCoords.z))
            end
        end
        print(string.format("^2[ChopShop DEBUG] Created %d ox_target boss zones^0", targetCount))
    else
        -- Remove existing zones
        for shopId, zone in pairs(bossMenuTargets) do
            zone:remove()
        end
        bossMenuTargets = {}

        -- Create new zones
        local zoneCount = 0
        for shopId, shopData in pairs(allShops) do
            local bossCoords = shopData.bosscoords
            if bossCoords and bossCoords.x then
                print(string.format("^3[ChopShop DEBUG] Creating textui boss zone for shop #%d at %.2f, %.2f, %.2f^0",
                    shopId, bossCoords.x, bossCoords.y, bossCoords.z))

                local zone = lib.zones.sphere({
                    coords = vec3(bossCoords.x, bossCoords.y, bossCoords.z),
                    radius = 2.0,
                    debug = false,
                    textUIShown = false,
                    onEnter = function(self)
                        print("^2[ChopShop DEBUG] ========== PLAYER ENTERED BOSS ZONE FOR SHOP #" .. shopId .. " ==========^0")
                        -- Reset state when entering zone
                        self.textUIShown = false
                    end,
                    inside = function(self)
                        if not self.textUIShown then
                            print("^2[ChopShop DEBUG] ========== SHOWING BOSS MENU TEXTUI FOR SHOP #" .. shopId .. " ==========^0")
                            Config.ShowTextUI("[E] - Manage Chop Shop")
                            self.textUIShown = true
                        end

                        if IsControlJustPressed(0, 38) then -- E key
                            print("^2[ChopShop DEBUG] ========== E PRESSED IN BOSS ZONE FOR SHOP #" .. shopId .. " ==========^0")
                            TriggerServerEvent("devkit_chopshop:getShopData", shopId)
                            Wait(500)
                        end
                    end,
                    onExit = function(self)
                        print("^3[ChopShop DEBUG] ========== PLAYER EXITED BOSS ZONE FOR SHOP #" .. shopId .. " ==========^0")
                        if self.textUIShown then
                            Config.HideTextUI()
                            self.textUIShown = false
                        end
                    end
                })
                bossMenuTargets[shopId] = zone
                zoneCount = zoneCount + 1
                print(string.format("^2[ChopShop DEBUG] Created textui boss zone for shop #%d^0", shopId))
            else
                print(string.format("^1[ChopShop DEBUG] No boss coords for shop #%d^0", shopId))
            end
        end
        print(string.format("^2[ChopShop DEBUG] Created %d textui boss zones^0", zoneCount))
    end
end

-- Debug command to check blip locations
RegisterCommand("chopblips", function()
    print("^3========== CHOP SHOP BLIPS DEBUG ==========^0")
    for shopId, shopData in pairs(allShops) do
        local blipData = shopData.blip or {}
        local coords = shopData.coords or {}
        if #coords < 1 and shopData.bosscoords then
            coords[1] = shopData.bosscoords
        end

        if #coords > 0 then
            local coord = coords[1]
            print(string.format("^2Shop #%d (%s):^0", shopId, shopData.name or "Unknown"))
            print(string.format("  Coords: %.2f, %.2f, %.2f", coord.x, coord.y, coord.z))
            print(string.format("  Blip: sprite=%s, color=%s, scale=%s",
                tostring(blipData.sprite), tostring(blipData.color), tostring(blipData.scale)))
            print(string.format("  Blip enabled: %s", tostring(blipData.sprite and blipData.sprite > 0)))

            -- Set waypoint to this location
            SetNewWaypoint(coord.x, coord.y)
            print(string.format("^2  Waypoint set to shop location!^0"))

            -- Check if blip exists in our table
            local blipExists = false
            for _, blip in ipairs(shopBlips) do
                if DoesBlipExist(blip) then
                    local blipCoord = GetBlipCoords(blip)
                    if math.abs(blipCoord.x - coord.x) < 1 and math.abs(blipCoord.y - coord.y) < 1 then
                        blipExists = true
                        print(string.format("^2  Blip EXISTS in game at %.2f, %.2f, %.2f^0", blipCoord.x, blipCoord.y, blipCoord.z))
                        print(string.format("  Blip sprite: %d, color: %d, display: %d, alpha: %d",
                            GetBlipSprite(blip), GetBlipColour(blip), GetBlipDisplay(blip), GetBlipAlpha(blip)))
                    end
                end
            end
            if not blipExists then
                print("^1  Blip NOT FOUND in game!^0")
            end
        end
    end
    print("^3==========================================^0")
end, false)

-- Register command on resource start
AddEventHandler("onClientResourceStart", function(resourceName)
    if GetCurrentResourceName() ~= resourceName then
        return
    end
    
    TriggerEvent("chat:addSuggestion", "/" .. Config.AdminChopShopCommand, "Open Chopshop Menu (ADMIN ONLY)")
end)