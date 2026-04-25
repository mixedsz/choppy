-- Framework Detection
local ESX = nil
local QBCore = nil

-- Initialize ESX
if GetResourceState(Config.ESXgetSharedObject) == "started" then
    ESX = exports[Config.ESXgetSharedObject]:getSharedObject()
end

-- Initialize QBCore
if GetResourceState(Config.QBCoreGetCoreObject) == "started" then
    QBCore = exports[Config.QBCoreGetCoreObject]:GetCoreObject()
end

-- Database table name
local SHOPS_TABLE = "chopshops"

-- In-memory shop data
local allShops = {}

-- Create database table on resource start
CreateThread(function()
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `chopshops` (
            `id` int(11) NOT NULL AUTO_INCREMENT,
            `name` varchar(255) DEFAULT 'Unnamed Chop Shop',
            `owner` varchar(255) DEFAULT NULL,
            `price` int(11) DEFAULT 50000,
            `money` int(11) DEFAULT 0,
            `cooldown` int(11) DEFAULT 30,
            `coords` longtext DEFAULT NULL,
            `bosscoords` longtext DEFAULT NULL,
            `blip` longtext DEFAULT NULL,
            `employees` longtext DEFAULT NULL,
            PRIMARY KEY (`id`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
    ]])
    
    -- Load all shops from database
    loadAllShops()
end)

-- Load all shops from database
function loadAllShops()
    MySQL.query('SELECT * FROM ' .. SHOPS_TABLE, {}, function(result)
        if result then
            for _, row in ipairs(result) do
                allShops[row.id] = {
                    id = row.id,
                    name = row.name,
                    owner = row.owner,
                    price = row.price,
                    money = row.money,
                    cooldown = row.cooldown,
                    coords = json.decode(row.coords) or {},
                    bosscoords = json.decode(row.bosscoords) or {},
                    blip = json.decode(row.blip) or {},
                    employees = json.decode(row.employees) or {}
                }
            end
        end
        print("[ChopShop] Loaded " .. #result .. " chop shops")
    end)
end

-- Save shop to database
function saveShop(shopId)
    local shop = allShops[shopId]
    if not shop then return end
    
    MySQL.update('UPDATE ' .. SHOPS_TABLE .. ' SET name=?, owner=?, price=?, money=?, cooldown=?, coords=?, bosscoords=?, blip=?, employees=? WHERE id=?', {
        shop.name,
        shop.owner,
        shop.price,
        shop.money,
        shop.cooldown,
        json.encode(shop.coords),
        json.encode(shop.bosscoords),
        json.encode(shop.blip),
        json.encode(shop.employees),
        shopId
    })
end

-- Get player identifier
function getPlayerIdentifier(source)
    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            return xPlayer.identifier
        end
    elseif QBCore then
        local player = QBCore.Functions.GetPlayer(source)
        if player then
            return player.PlayerData.citizenid
        end
    end
    return nil
end

-- Check if player is admin
function isPlayerAdmin(source)
    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            for _, group in ipairs(Config.AdminGroups) do
                if xPlayer.getGroup() == group then
                    return true
                end
            end
        end
    elseif QBCore then
        local player = QBCore.Functions.GetPlayer(source)
        if player then
            for _, group in ipairs(Config.AdminGroups) do
                if QBCore.Functions.HasPermission(source, group) then
                    return true
                end
            end
        end
    end
    return false
end

-- Add money to player
function addMoneyToPlayer(source, amount)
    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if Config.Rewards.Currency.type == 'account' then
                xPlayer.addAccountMoney(Config.Rewards.Currency.payment, amount)
            else
                xPlayer.addInventoryItem(Config.Rewards.Currency.payment, amount)
            end
        end
    elseif QBCore then
        local player = QBCore.Functions.GetPlayer(source)
        if player then
            if Config.Rewards.Currency.type == 'account' then
                player.Functions.AddMoney(Config.Rewards.Currency.payment, amount)
            else
                player.Functions.AddItem(Config.Rewards.Currency.payment, amount)
            end
        end
    end
end

-- Add item to player
function addItemToPlayer(source, item, amount)
    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.addInventoryItem(item, amount)
        end
    elseif QBCore then
        local player = QBCore.Functions.GetPlayer(source)
        if player then
            player.Functions.AddItem(item, amount)
        end
    end
end

-- Remove item from player
function removeItemFromPlayer(source, item, amount)
    amount = amount or 1
    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            xPlayer.removeInventoryItem(item, amount)
        end
    elseif QBCore then
        local player = QBCore.Functions.GetPlayer(source)
        if player then
            player.Functions.RemoveItem(item, amount)
        end
    end
end

-- Get player money
function getPlayerMoney(source, moneyType)
    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if moneyType == 'bank' then
                return xPlayer.getAccount('bank').money
            else
                return xPlayer.getMoney()
            end
        end
    elseif QBCore then
        local player = QBCore.Functions.GetPlayer(source)
        if player then
            return player.PlayerData.money[moneyType] or 0
        end
    end
    return 0
end

-- Remove money from player
function removeMoneyFromPlayer(source, amount, moneyType)
    moneyType = moneyType or 'cash'
    if ESX then
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            if moneyType == 'bank' then
                xPlayer.removeAccountMoney('bank', amount)
            else
                xPlayer.removeMoney(amount)
            end
            return true
        end
    elseif QBCore then
        local player = QBCore.Functions.GetPlayer(source)
        if player then
            return player.Functions.RemoveMoney(moneyType, amount)
        end
    end
    return false
end

-- Event: Request all shops
RegisterNetEvent("devkit_chopshop:requestAllShops", function()
    local src = source
    print(string.format("^3[ChopShop DEBUG] Player %d requested all shops^0", src))
    print(string.format("^3[ChopShop DEBUG] Sending %d shops to client^0", table.count(allShops)))

    -- Debug: Print each shop's blip data
    for shopId, shopData in pairs(allShops) do
        local blipData = shopData.blip or {}
        print(string.format("^3[ChopShop DEBUG] Shop #%d (%s): blip sprite=%s^0",
            shopId, shopData.name or "Unknown", tostring(blipData.sprite)))
    end

    TriggerClientEvent("devkit_chopshop:receiveAllShops", src, allShops)
end)

-- Helper function to count table entries
function table.count(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- Event: Get shop data
RegisterNetEvent("devkit_chopshop:getShopData", function(shopId)
    local src = source
    local shop = allShops[shopId]
    if shop then
        TriggerClientEvent("devkit_chopshop:receiveShopData", src, shop)
    end
end)

-- Event: Buy shop
RegisterNetEvent("devkit_chopshop:buyShop", function(shopId, price)
    local src = source
    local identifier = getPlayerIdentifier(src)
    local shop = allShops[shopId]
    
    if not shop then
        TriggerClientEvent('devkit_chopshopCL:notify', src, "Invalid shop!", "error")
        return
    end
    
    if shop.owner and shop.owner ~= "" then
        TriggerClientEvent('devkit_chopshopCL:notify', src, "This shop is already owned!", "error")
        return
    end
    
    local playerMoney = getPlayerMoney(src, 'bank')
    if playerMoney < price then
        TriggerClientEvent('devkit_chopshopCL:notify', src, "You don't have enough money!", "error")
        return
    end
    
    if removeMoneyFromPlayer(src, price, 'bank') then
        shop.owner = identifier
        saveShop(shopId)
        
        TriggerClientEvent('devkit_chopshopCL:notify', src, "You purchased the chop shop!", "success")
        TriggerClientEvent("devkit_chopshop:receiveAllShops", -1, allShops)
    end
end)

-- Event: Sell business
RegisterNetEvent("devkit_chopshop:sellBusiness", function(shopId)
    local src = source
    local identifier = getPlayerIdentifier(src)
    local shop = allShops[shopId]
    
    if not shop then return end
    
    if shop.owner ~= identifier then
        TriggerClientEvent('devkit_chopshopCL:notify', src, "You don't own this shop!", "error")
        return
    end
    
    addMoneyToPlayer(src, shop.price)
    
    shop.owner = nil
    shop.money = 0
    shop.employees = {}
    saveShop(shopId)
    
    TriggerClientEvent('devkit_chopshopCL:notify', src, "You sold the business!", "success")
    TriggerClientEvent("devkit_chopshop:receiveAllShops", -1, allShops)
end)

-- Event: Transfer business
RegisterNetEvent("devkit_chopshop:transferBusiness", function(shopId, targetId)
    local src = source
    local identifier = getPlayerIdentifier(src)
    local targetIdentifier = getPlayerIdentifier(targetId)
    local shop = allShops[shopId]
    
    if not shop then return end
    
    if shop.owner ~= identifier then
        TriggerClientEvent('devkit_chopshopCL:notify', src, "You don't own this shop!", "error")
        return
    end
    
    if not targetIdentifier then
        TriggerClientEvent('devkit_chopshopCL:notify', src, "Target player not found!", "error")
        return
    end
    
    shop.owner = targetIdentifier
    saveShop(shopId)
    
    TriggerClientEvent('devkit_chopshopCL:notify', src, "Business transferred!", "success")
    TriggerClientEvent('devkit_chopshopCL:notify', targetId, "You received a chop shop!", "success")
    TriggerClientEvent("devkit_chopshop:receiveAllShops", -1, allShops)
end)

-- Event: Withdraw funds
RegisterNetEvent("devkit_chopshop:withdrawFunds", function(shopId, amount)
    local src = source
    local identifier = getPlayerIdentifier(src)
    local shop = allShops[shopId]
    
    if not shop then return end
    
    if shop.owner ~= identifier then
        TriggerClientEvent('devkit_chopshopCL:notify', src, "You don't own this shop!", "error")
        return
    end
    
    if shop.money < amount then
        TriggerClientEvent('devkit_chopshopCL:notify', src, "Not enough money in business!", "error")
        return
    end
    
    shop.money = shop.money - amount
    addMoneyToPlayer(src, amount)
    saveShop(shopId)
    
    TriggerClientEvent('devkit_chopshopCL:notify', src, string.format("Withdrew $%d", amount), "success")
    TriggerClientEvent("devkit_chopshop:receiveAllShops", -1, allShops)
end)

-- Event: Owner hire employee by ID
RegisterNetEvent("devkit_chopshop:ownerHireEmployeeById", function(shopId, targetId)
    local src = source
    local identifier = getPlayerIdentifier(src)
    local targetIdentifier = getPlayerIdentifier(targetId)
    local shop = allShops[shopId]
    
    if not shop then return end
    
    if shop.owner ~= identifier then
        TriggerClientEvent('devkit_chopshopCL:notify', src, "You don't own this shop!", "error")
        return
    end
    
    if not targetIdentifier then
        TriggerClientEvent('devkit_chopshopCL:notify', src, "Target player not found!", "error")
        return
    end
    
    for _, empId in ipairs(shop.employees) do
        if empId == targetIdentifier then
            TriggerClientEvent('devkit_chopshopCL:notify', src, "Player is already an employee!", "error")
            return
        end
    end
    
    table.insert(shop.employees, targetIdentifier)
    saveShop(shopId)
    
    TriggerClientEvent('devkit_chopshopCL:notify', src, "Employee hired!", "success")
    TriggerClientEvent('devkit_chopshopCL:notify', targetId, "You were hired at a chop shop!", "success")
    TriggerClientEvent("devkit_chopshop:receiveAllShops", -1, allShops)
end)

-- Event: Owner fire employee by identifier
RegisterNetEvent("devkit_chopshop:ownerFireEmployeeByIdentifier", function(shopId, empIdentifier)
    local src = source
    local identifier = getPlayerIdentifier(src)
    local shop = allShops[shopId]
    
    if not shop then return end
    
    if shop.owner ~= identifier then
        TriggerClientEvent('devkit_chopshopCL:notify', src, "You don't own this shop!", "error")
        return
    end
    
    for i, empId in ipairs(shop.employees) do
        if empId == empIdentifier then
            table.remove(shop.employees, i)
            saveShop(shopId)
            TriggerClientEvent('devkit_chopshopCL:notify', src, "Employee fired!", "success")
            TriggerClientEvent("devkit_chopshop:receiveAllShops", -1, allShops)
            return
        end
    end
    
    TriggerClientEvent('devkit_chopshopCL:notify', src, "Employee not found!", "error")
end)

-- Event: Payout
RegisterNetEvent("devkit_chopshop:payout", function(shopId)
    local src = source
    local shop = allShops[shopId]
    
    if not shop then return end
    
    if Config.Rewards.Enabled then
        -- Give items
        for itemName, itemData in pairs(Config.Rewards.Items) do
            if math.random(100) <= itemData.probability then
                local amount = math.random(itemData.min, itemData.max)
                addItemToPlayer(src, itemName, amount)
            end
        end
        
        -- Give currency
        local currencyAmount = math.random(Config.Rewards.Currency.amount.min, Config.Rewards.Currency.amount.max)
        local businessCut = math.floor(currencyAmount * (Config.Rewards.Currency.split / 100))
        local playerCut = currencyAmount - businessCut
        
        shop.money = shop.money + businessCut
        addMoneyToPlayer(src, playerCut)
        saveShop(shopId)
        
        TriggerClientEvent('devkit_chopshopCL:notify', src, string.format("You earned $%d!", playerCut), "success")
        TriggerClientEvent("devkit_chopshop:receiveAllShops", -1, allShops)
    end
end)

-- Event: Remove owned vehicle
RegisterNetEvent("devkit_chopshop:removeownedvehicle", function(plate)
    if not Config.DeleteVehicle then return end
    
    if ESX then
        MySQL.update('DELETE FROM owned_vehicles WHERE plate = ?', {plate})
    elseif QBCore then
        MySQL.update('DELETE FROM player_vehicles WHERE plate = ?', {plate})
    end
end)

-- Admin Commands

-- Command: Open admin menu
RegisterCommand(Config.AdminChopShopCommand, function(source, args, rawCommand)
    local src = source
    
    if not isPlayerAdmin(src) then
        TriggerClientEvent('devkit_chopshopCL:notify', src, "No permission!", "error")
        return
    end
    
    TriggerClientEvent("devkit_chopshop:openAdminMainMenu", src, allShops)
end, false)

-- Event: Create shop
RegisterNetEvent("devkit_chopshop:createShop", function(shopData)
    local src = source
    
    if not isPlayerAdmin(src) then return end
    
    MySQL.insert('INSERT INTO ' .. SHOPS_TABLE .. ' (name, price, cooldown, coords, bosscoords, blip, employees) VALUES (?, ?, ?, ?, ?, ?, ?)', {
        shopData.name,
        shopData.price,
        shopData.cooldown,
        json.encode(shopData.coords),
        json.encode(shopData.bosscoords),
        json.encode(shopData.blip),
        json.encode({})
    }, function(insertId)
        shopData.id = insertId
        shopData.owner = nil
        shopData.money = 0
        shopData.employees = {}
        allShops[insertId] = shopData
        
        TriggerClientEvent('devkit_chopshopCL:notify', src, "Chop shop created!", "success")
        TriggerClientEvent("devkit_chopshop:receiveAllShops", -1, allShops)
    end)
end)

-- Event: Admin update shop name
RegisterNetEvent("devkit_chopshop:adminUpdateShopName", function(shopId, newName)
    local src = source
    
    if not isPlayerAdmin(src) then return end
    
    local shop = allShops[shopId]
    if shop then
        shop.name = newName
        saveShop(shopId)
        TriggerClientEvent('devkit_chopshopCL:notify', src, "Shop name updated!", "success")
        TriggerClientEvent("devkit_chopshop:receiveAllShops", -1, allShops)
    end
end)

-- Event: Admin update shop price
RegisterNetEvent("devkit_chopshop:adminUpdateShopPrice", function(shopId, newPrice)
    local src = source
    
    if not isPlayerAdmin(src) then return end
    
    local shop = allShops[shopId]
    if shop then
        shop.price = newPrice
        saveShop(shopId)
        TriggerClientEvent('devkit_chopshopCL:notify', src, "Shop price updated!", "success")
        TriggerClientEvent("devkit_chopshop:receiveAllShops", -1, allShops)
    end
end)

-- Event: Admin update cooldown
RegisterNetEvent("devkit_chopshop:adminUpdateCooldown", function(shopId, newCooldown)
    local src = source
    
    if not isPlayerAdmin(src) then return end
    
    local shop = allShops[shopId]
    if shop then
        shop.cooldown = newCooldown
        saveShop(shopId)
        TriggerClientEvent('devkit_chopshopCL:notify', src, "Cooldown updated!", "success")
        TriggerClientEvent("devkit_chopshop:receiveAllShops", -1, allShops)
    end
end)

-- Event: Admin update shop blip
RegisterNetEvent("devkit_chopshop:adminUpdateShopBlip", function(shopId, sprite, color, scale)
    local src = source

    print(string.format("^3[ChopShop DEBUG] adminUpdateShopBlip called for shop #%d^0", shopId))
    print(string.format("^3[ChopShop DEBUG] Blip values: sprite=%s, color=%s, scale=%s^0",
        tostring(sprite), tostring(color), tostring(scale)))

    if not isPlayerAdmin(src) then
        print("^1[ChopShop DEBUG] Player is not admin!^0")
        return
    end

    local shop = allShops[shopId]
    if shop then
        shop.blip = {
            sprite = sprite,
            color = color,
            scale = scale
        }
        print(string.format("^2[ChopShop DEBUG] Updated shop #%d blip in memory^0", shopId))

        saveShop(shopId)
        print(string.format("^2[ChopShop DEBUG] Saved shop #%d to database^0", shopId))

        TriggerClientEvent('devkit_chopshopCL:notify', src, "Blip updated!", "success")
        TriggerClientEvent("devkit_chopshop:receiveAllShops", -1, allShops)
        print("^2[ChopShop DEBUG] Sent updated shops to all clients^0")
    else
        print(string.format("^1[ChopShop DEBUG] Shop #%d not found!^0", shopId))
    end
end)

-- Event: Admin delete shop
RegisterNetEvent("devkit_chopshop:adminDeleteShop", function(shopId)
    local src = source
    
    if not isPlayerAdmin(src) then return end
    
    MySQL.update('DELETE FROM ' .. SHOPS_TABLE .. ' WHERE id = ?', {shopId}, function()
        allShops[shopId] = nil
        TriggerClientEvent('devkit_chopshopCL:notify', src, "Shop deleted!", "success")
        TriggerClientEvent("devkit_chopshop:receiveAllShops", -1, allShops)
    end)
end)

-- Event: Admin hire employee
RegisterNetEvent("devkit_chopshop:adminHireEmployeeById", function(shopId, targetId)
    local src = source
    
    if not isPlayerAdmin(src) then return end
    
    local targetIdentifier = getPlayerIdentifier(targetId)
    local shop = allShops[shopId]
    
    if not shop then return end
    
    if not targetIdentifier then
        TriggerClientEvent('devkit_chopshopCL:notify', src, "Target player not found!", "error")
        return
    end
    
    for _, empId in ipairs(shop.employees) do
        if empId == targetIdentifier then
            TriggerClientEvent('devkit_chopshopCL:notify', src, "Player is already an employee!", "error")
            return
        end
    end
    
    table.insert(shop.employees, targetIdentifier)
    saveShop(shopId)
    
    TriggerClientEvent('devkit_chopshopCL:notify', src, "Employee hired!", "success")
    TriggerClientEvent("devkit_chopshop:receiveAllShops", -1, allShops)
end)

-- Event: Admin remove employee
RegisterNetEvent("devkit_chopshop:adminRemoveEmployee", function(shopId, empIdentifier)
    local src = source
    
    if not isPlayerAdmin(src) then return end
    
    local shop = allShops[shopId]
    if not shop then return end
    
    for i, empId in ipairs(shop.employees) do
        if empId == empIdentifier then
            table.remove(shop.employees, i)
            saveShop(shopId)
            TriggerClientEvent('devkit_chopshopCL:notify', src, "Employee removed!", "success")
            TriggerClientEvent("devkit_chopshop:receiveAllShops", -1, allShops)
            return
        end
    end
    
    TriggerClientEvent('devkit_chopshopCL:notify', src, "Employee not found!", "error")
end)

-- ESX Callback for item check
if ESX then
    ESX.RegisterServerCallback("devkit_chopshop:server:hasitemesx", function(source, cb, itemName)
        local xPlayer = ESX.GetPlayerFromId(source)
        if xPlayer then
            local item = xPlayer.getInventoryItem(itemName)
            cb(item and item.count > 0)
        else
            cb(false)
        end
    end)

    -- Register impact_drill as usable item
    ESX.RegisterUsableItem('impact_drill', function(playerId)
        TriggerClientEvent('devkit_chopshop:client:useImpactDrill', playerId)
    end)
end

-- QB-Core: Register impact_drill as usable item
if QBCore then
    QBCore.Functions.CreateUseableItem('impact_drill', function(source, item)
        TriggerClientEvent('devkit_chopshop:client:useImpactDrill', source)
    end)
end

-- Event: Remove item
RegisterNetEvent("devkit_chopshop:server:removeitem", function(itemName)
    local src = source
    removeItemFromPlayer(src, itemName, 1)
end)

print("[ChopShop] Server script loaded successfully!")