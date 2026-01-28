---@diagnostic disable: undefined-global
local rigStates = {}
local currentRigId = nil
local nuiReady = false
local lastUiShownAt = 0
local fuelingInProgress = false
local fuelingEndsAt = 0

local JOB_NAME = 'Playground Oil Rig'
local JOB_BLIP_COLOR = 5

local rigBlips = {}

local function formatTime(ms)
    local seconds = math.floor(ms / 1000)
    local minutes = math.floor(seconds / 60)
    local rem = seconds % 60
    return string.format('%02d:%02d', minutes, rem)
end

local function getPlayerFuelCount()
    if GetResourceState('ox_inventory') ~= 'started' then
        return 0
    end

    local ok, count = pcall(function()
        -- ox_inventory client API
        return exports.ox_inventory:Search('count', Config.FuelItem)
    end)

    if not ok then
        return 0
    end

    return tonumber(count or 0) or 0
end

local function getPlayerBarrelCount()
    if GetResourceState('ox_inventory') ~= 'started' then
        return 0
    end

    local ok, count = pcall(function()
        return exports.ox_inventory:Search('count', Config.BarrelItem)
    end)

    if not ok then
        return 0
    end

    return tonumber(count or 0) or 0
end

local function openFuelSupplierUI()
    -- Close rig UI if open.
    if currentRigId ~= nil then
        SendNUIMessage({ action = 'hideRigUI' })
        currentRigId = nil
        fuelingInProgress = false
        fuelingEndsAt = 0
    end

    local currentFuel = getPlayerFuelCount()
    SendNUIMessage({
        action = 'showSupplierUI',
        config = {
            fuelCost = Config.FuelCost or 0,
            currentFuel = currentFuel or 0,
            maxHold = 9
        }
    })
    SetNuiFocus(true, true)
end

local function openOilBuyerUI()
    -- Close rig UI if open.
    if currentRigId ~= nil then
        SendNUIMessage({ action = 'hideRigUI' })
        currentRigId = nil
        fuelingInProgress = false
        fuelingEndsAt = 0
    end

    -- Close supplier UI if open.
    SendNUIMessage({ action = 'hideSupplierUI' })

    local currentBarrels = getPlayerBarrelCount()
    SendNUIMessage({
        action = 'showBuyerUI',
        config = {
            barrelPrice = Config.BarrelSellPrice or 0,
            currentBarrels = currentBarrels or 0
        }
    })
    SetNuiFocus(true, true)
end

-- Send updated rig state to UI
local function updateUI(rigId, state)
    state = state or {}
    if currentRigId ~= rigId then
        return
    end

    local maxBarrels = tonumber(Config.MaxBarrelsStored) or 10
    local remaining = tonumber(state.remaining or 0) or 0
    local progressPct = 0
    if state.isRunning and Config.ProductionTime > 0 then
        progressPct = math.max(0, math.min(1, 1 - (remaining / Config.ProductionTime)))
    end

    local playerFuel = getPlayerFuelCount()

    SendNUIMessage({
        action = 'updateRigPanel',
        rigId = rigId,
        data = {
            fuelCans = state.fuelCans or 0,
            maxFuel = Config.MaxFuelCansStored or 9,
            fuelBatch = Config.MaxFuelCansPerCycle or 3,
            playerFuel = playerFuel,
            maxBarrels = maxBarrels,
            status = (state.isRunning and 'RUNNING') or (((state.fuelCans or 0) >= (Config.MaxFuelCansPerCycle or 3)) and 'READY') or 'OUT_OF_FUEL',
            timeRemaining = remaining > 0 and formatTime(remaining) or 'N/A',
            barrelsReady = state.barrelsReady or 0,
            storagePct = maxBarrels > 0 and ((state.barrelsReady or 0) / maxBarrels) or 0,
            progressPct = progressPct,
            productionTime = formatTime(Config.ProductionTime)
        }
    })
end

-- Open UI
local function openRigPanel(rigId)
    -- Wait briefly for NUI to report ready; avoids locking player if NUI failed to load.
    if not nuiReady then
        local start = GetGameTimer()
        while not nuiReady and (GetGameTimer() - start) < 2000 do
            Wait(50)
        end
        if not nuiReady then
            -- Don't block entirely; allow attempting to open UI anyway.
            -- The existing uiShown fail-safe will release focus if NUI is truly broken.
            TriggerEvent('L3GiTOilRig:client:notify', {
                title = 'Oil Rig',
                message = 'UI is still loading. Trying to open anyway.',
                type = 'error'
            })
        end
    end

    local state = lib.callback.await('L3GiTOilRig:server:getRigState', false, rigId)
    if not state then
        state = { fuelCans = 0, isRunning = false, barrelsReady = 0, remaining = 0 }
    end

    local rigName = ''
    local okName, nameOrErr = pcall(function()
        return lib.callback.await('L3GiTOilRig:server:getRigName', false, rigId)
    end)
    if okName and type(nameOrErr) == 'string' then
        rigName = nameOrErr
    end

    rigStates[rigId] = state
    currentRigId = rigId

    lastUiShownAt = 0
    SendNUIMessage({
        action = 'showRigUI',
        rigId = rigId,
        rigName = rigName,
        config = {
            maxFuel = Config.MaxFuelCansStored or 9,
            fuelBatch = Config.MaxFuelCansPerCycle or 3,
            maxBarrels = tonumber(Config.MaxBarrelsStored) or 10,
            productionTimeLabel = formatTime(Config.ProductionTime),
            fuelCost = Config.FuelCost,
            barrelSellPrice = Config.BarrelSellPrice,
            fuelToYield = Config.FuelToYield,
            subtitle = 'Fuel → Produce → Collect → Sell'
        }
    })

    SetNuiFocus(true, true)

    -- Fail-safe: if NUI doesn't acknowledge showing within 1.5s, release focus.
    CreateThread(function()
        local myRigId = rigId
        local startedAt = GetGameTimer()
        while currentRigId == myRigId and (GetGameTimer() - startedAt) < 1500 do
            Wait(50)
            if lastUiShownAt > 0 then
                return
            end
        end

        if currentRigId == myRigId and lastUiShownAt == 0 then
            SetNuiFocus(false, false)
            currentRigId = nil
        end
    end)

    updateUI(rigId, state)

    -- Countdown thread to update remaining time every second
    CreateThread(function()
        local uiRigId = rigId
        local lastRemainingTime = -1
        while currentRigId == uiRigId do
            Wait(1000)
            if currentRigId == uiRigId then
                local currentState = rigStates[uiRigId]
                if currentState then
                    -- Only decrement if rig is actually running
                    if currentState.isRunning and currentState.remaining > 0 then
                        currentState.remaining = math.max(currentState.remaining - 1000, 0)
                        
                        -- When countdown reaches 0, fetch updated state from server
                        if currentState.remaining <= 0 and lastRemainingTime ~= 0 then
                            lastRemainingTime = 0
                            local success, latestState = pcall(function()
                                return lib.callback.await('L3GiTOilRig:server:getRigState', false, uiRigId)
                            end)
                            if success and latestState then
                                rigStates[uiRigId] = latestState
                                updateUI(uiRigId, latestState)
                            end
                        else
                            updateUI(uiRigId, currentState)
                        end
                    end
                end
            end
        end
    end)
end

-- Notifications
RegisterNetEvent('L3GiTOilRig:client:notify', function(data)
    SendNUIMessage({
        action = 'notify',
        title = data.title or 'Playground Oil Rig',
        message = data.message or '',
        nType = data.type or 'info',
        duration = 4000
    })
end)

-- Server pushes updated rig state
RegisterNetEvent('L3GiTOilRig:client:updateRigState', function(rigId, data)
    local state = {
        fuelCans = data.fuelCans or 0,
        isRunning = data.isRunning or false,
        barrelsReady = data.barrelsReady or 0,
        remaining = data.remaining or 0
    }

    rigStates[rigId] = state
    updateUI(rigId, state)
end)

-- Spawn NPCs
local function spawnNPC(cfg)
    lib.requestModel(cfg.pedModel)
    local ped = CreatePed(4, cfg.pedModel, cfg.coords.x, cfg.coords.y, cfg.coords.z - 1.0, cfg.coords.w, false, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    if cfg.invincible then SetEntityInvincible(ped, true) end
    if cfg.frozen then FreezeEntityPosition(ped, true) end
    if cfg.scenario then TaskStartScenarioInPlace(ped, cfg.scenario, 0, true) end
    return ped
end

local function createJobBlip(coords, label, sprite, color)
    local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
    SetBlipSprite(blip, sprite or 361)
    SetBlipDisplay(blip, 4)
    SetBlipScale(blip, 0.85)
    SetBlipColour(blip, color or JOB_BLIP_COLOR)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label or 'Job')
    EndTextCommandSetBlipName(blip)
    return blip
end

local function updateRigBlipName(rigId, rigName)
    local blip = rigBlips[rigId]
    if not blip then return end

    local name = tostring(rigName or '')
    name = name:gsub('^%s+', ''):gsub('%s+$', '')

    -- User-request: rig blip name should match their rig name.
    local label = (name ~= '' and name) or (JOB_NAME .. ' - Rig')
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentString(label)
    EndTextCommandSetBlipName(blip)
end

local function refreshRigBlipNameFromServer(rigId)
    CreateThread(function()
        local ok, res = pcall(function()
            return lib.callback.await('L3GiTOilRig:server:getRigName', false, rigId)
        end)
        if ok and type(res) == 'string' then
            updateRigBlipName(rigId, res)
        end
    end)
end

-- Fuel Supplier NPC
CreateThread(function()
    local fuelPed = spawnNPC(Config.FuelSupplier)

    -- Map blip for the fuel supplier.
    createJobBlip(Config.FuelSupplier.coords, JOB_NAME .. ' - Fuel Supplier', 361, JOB_BLIP_COLOR)

    if GetResourceState('ox_target') ~= 'started' then
        return
    end

    exports.ox_target:addLocalEntity(fuelPed, {
        {
            name = 'L3GiTOilRig_buy_fuel',
            label = 'Purchase Rig Fuel',
            icon = 'fa-solid fa-gas-pump',
            distance = Config.FuelSupplier.targetDistance,
            onSelect = function()
                openFuelSupplierUI()
            end
        }
    })

    -- Oil Buyer NPC
    local buyerPed = spawnNPC(Config.OilBuyer)

    -- Map blip for the oil buyer.
    createJobBlip(Config.OilBuyer.coords, JOB_NAME .. ' - Oil Buyer', 277, JOB_BLIP_COLOR)

    exports.ox_target:addLocalEntity(buyerPed, {
        {
            name = 'L3GiTOilRig_sell_barrel',
            label = 'Sell Oil Barrels',
            icon = 'fa-solid fa-dollar-sign',
            distance = Config.OilBuyer.targetDistance,
            onSelect = function()
                openOilBuyerUI()
            end
        }
    })
end)

-- Rig Target
CreateThread(function()
    if GetResourceState('ox_target') ~= 'started' then
        return
    end

    for _, rig in ipairs(Config.RigLocations) do
        local obj = GetClosestObjectOfType(rig.coords.x, rig.coords.y, rig.coords.z, 2.0, Config.RigModel, false, false, false)
        if obj == 0 then
            lib.requestModel(Config.RigModel)
            obj = CreateObject(Config.RigModel, rig.coords.x, rig.coords.y, rig.coords.z, false, false, false)
            SetEntityHeading(obj, rig.heading)
            FreezeEntityPosition(obj, true)
        end

        exports.ox_target:addLocalEntity(obj, {
            {
                name = 'L3GiTOilRig_panel_' .. rig.id,
                label = 'Rig Control Panel',
                icon = 'fa-solid fa-oil-can',
                distance = Config.TargetDistanceRig,
                onSelect = function()
                    openRigPanel(rig.id)
                end
            }
        })
    end
end)

-- Map blips for rigs
CreateThread(function()
    for _, rig in ipairs(Config.RigLocations or {}) do
        if rig and rig.coords then
            rigBlips[rig.id] = createJobBlip(rig.coords, JOB_NAME .. ' - Rig', 436, JOB_BLIP_COLOR)
            refreshRigBlipNameFromServer(rig.id)
        end
    end
end)

-- NUI Callbacks
RegisterNUICallback('closeUI', function(_, cb)
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideRigUI' })
    currentRigId = nil
    fuelingInProgress = false
    fuelingEndsAt = 0
    cb('ok')
end)

RegisterNUICallback('closeSupplierUI', function(_, cb)
    cb('ok')
    SendNUIMessage({ action = 'hideSupplierUI' })
    SetNuiFocus(false, false)
end)

RegisterNUICallback('closeBuyerUI', function(_, cb)
    cb('ok')
    SendNUIMessage({ action = 'hideBuyerUI' })
    SetNuiFocus(false, false)
end)

RegisterNUICallback('buyDiesel', function(data, cb)
    cb('ok')

    local amount = tonumber(data and data.amount or 1) or 1
    TriggerServerEvent('L3GiTOilRig:server:buyDiesel', amount)

    -- Refresh max quantity from inventory shortly after buying.
    CreateThread(function()
        Wait(350)
        local currentFuel = getPlayerFuelCount()
        SendNUIMessage({
            action = 'updateSupplierUI',
            config = {
                currentFuel = currentFuel or 0,
                fuelCost = Config.FuelCost or 0,
                maxHold = 9
            }
        })
    end)
end)

RegisterNUICallback('requestSupplierRefresh', function(_, cb)
    cb('ok')
    local currentFuel = getPlayerFuelCount()
    SendNUIMessage({
        action = 'updateSupplierUI',
        config = {
            currentFuel = currentFuel or 0,
            fuelCost = Config.FuelCost or 0,
            maxHold = 9
        }
    })
end)

RegisterNUICallback('sellBarrels', function(data, cb)
    cb('ok')

    local amount = tonumber(data and data.amount or 1) or 1
    TriggerServerEvent('L3GiTOilRig:server:sellBarrels', amount)

    -- Refresh max quantity from inventory shortly after selling.
    CreateThread(function()
        Wait(350)
        local currentBarrels = getPlayerBarrelCount()
        SendNUIMessage({
            action = 'updateBuyerUI',
            config = {
                currentBarrels = currentBarrels or 0,
                barrelPrice = Config.BarrelSellPrice or 0
            }
        })
    end)
end)

RegisterNUICallback('uiReady', function(_, cb)
    nuiReady = true
    cb('ok')
end)

RegisterNUICallback('uiShown', function(_, cb)
    lastUiShownAt = GetGameTimer()
    cb('ok')
end)

RegisterNUICallback('fuelRig', function(data, cb)
    cb('ok')

    local rigId = data.rigId

    local now = GetGameTimer()
    if fuelingInProgress and now < (fuelingEndsAt or 0) then
        return
    end

    fuelingInProgress = true
    fuelingEndsAt = now + 5050

    SendNUIMessage({
        action = 'fueling',
        state = 'start',
        duration = 5000
    })

    CreateThread(function()
        Wait(5000)

        if currentRigId ~= rigId then
            fuelingInProgress = false
            fuelingEndsAt = 0
            return
        end

        fuelingInProgress = false
        fuelingEndsAt = 0
        SendNUIMessage({ action = 'fueling', state = 'done' })
        TriggerServerEvent('L3GiTOilRig:server:fuelRig', rigId, 1)
    end)
end)

RegisterNUICallback('startCycle', function(data, cb)
    cb('ok')
    local rigId = (data and data.rigId) or currentRigId
    TriggerServerEvent('L3GiTOilRig:server:startCycle', rigId)
end)

RegisterNUICallback('collectBarrel', function(data, cb)
    cb('ok')
    TriggerServerEvent('L3GiTOilRig:server:collectBarrel', data.rigId)
end)

RegisterNUICallback('setRigName', function(data, cb)
    cb('ok')
    if not currentRigId then return end

    local rigId = data.rigId or currentRigId
    local name = data.rigName or ''

    CreateThread(function()
        local ok, res = pcall(function()
            return lib.callback.await('L3GiTOilRig:server:setRigName', false, rigId, name)
        end)

        if ok and type(res) == 'table' and res.ok then
            SendNUIMessage({ action = 'setRigName', rigId = rigId, rigName = res.name or '' })
            updateRigBlipName(rigId, res.name or '')
            TriggerEvent('L3GiTOilRig:client:notify', {
                title = JOB_NAME,
                message = 'Rig name saved.',
                type = 'success'
            })
        else
            TriggerEvent('L3GiTOilRig:client:notify', {
                title = JOB_NAME,
                message = 'Failed to save rig name.',
                type = 'error'
            })
        end
    end)
end)

RegisterNUICallback('modalResponse', function(data, cb)
    cb('ok')

    if data.modalId == 'buyFuel' and data.accepted then
        TriggerServerEvent('L3GiTOilRig:server:buyDiesel')
    end

    if currentRigId == nil then
        SetNuiFocus(false, false)
    else
        SetNuiFocus(true, true)
    end
end)
