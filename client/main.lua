---@diagnostic disable: undefined-global
local rigStates = {}
local currentRigId = nil
local nuiReady = false
local lastUiShownAt = 0
local fuelingInProgress = false
local fuelingEndsAt = 0

local function dbg(fmt, ...)
    if not (Config and Config.Debug) then return end

    local ok, msg
    if select('#', ...) > 0 then
        ok, msg = pcall(string.format, fmt, ...)
    else
        ok, msg = true, tostring(fmt)
    end

    if not ok then msg = tostring(fmt) end
    print(('[L3GiTOilRig][DEBUG] %s'):format(tostring(msg)))
end

local JOB_NAME = (Config and Config.JobName) or 'Playground Oil Rig'
local JOB_BLIP_COLOR = 5

local rigBlips = {}
local rigObjects = {}
local rigTargetsAdded = {}

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
        dbg('getPlayerFuelCount: ox_inventory Search failed')
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
        dbg('getPlayerBarrelCount: ox_inventory Search failed')
        return 0
    end

    return tonumber(count or 0) or 0
end

local function openFuelSupplierUI()
    dbg('openFuelSupplierUI')
    -- Close rig UI if open.
    if currentRigId ~= nil then
        SendNUIMessage({ action = 'hideRigUI' })
        currentRigId = nil
        fuelingInProgress = false
        fuelingEndsAt = 0
    end

    local currentFuel = getPlayerFuelCount()
    dbg('FuelSupplier currentFuel=%s', tostring(currentFuel))
    SendNUIMessage({
        action = 'showSupplierUI',
        config = {
            fuelCost = Config.FuelCost or 0,
            currentFuel = currentFuel or 0,
            maxHold = 9,
            uiKicker = (Config.Ui and Config.Ui.opsKicker) or 'Operations',
            uiTitle = (Config.Ui and Config.Ui.mainTitle) or JOB_NAME,
            uiSubtitle = (Config.Ui and Config.Ui.supplierSubtitle) or 'Fuel Supplier'
        }
    })
    SetNuiFocus(true, true)
end

local function openOilBuyerUI()
    dbg('openOilBuyerUI')
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
    dbg('OilBuyer currentBarrels=%s', tostring(currentBarrels))
    SendNUIMessage({
        action = 'showBuyerUI',
        config = {
            barrelPrice = Config.BarrelSellPrice or 0,
            currentBarrels = currentBarrels or 0,
            uiKicker = (Config.Ui and Config.Ui.opsKicker) or 'Operations',
            uiTitle = (Config.Ui and Config.Ui.mainTitle) or JOB_NAME,
            uiSubtitle = (Config.Ui and Config.Ui.buyerSubtitle) or 'Oil Buyer'
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

    dbg('updateUI rigId=%s fuel=%s running=%s barrels=%s remaining=%s', tostring(rigId), tostring(state.fuelCans), tostring(state.isRunning), tostring(state.barrelsReady), tostring(state.remaining))

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
    dbg('openRigPanel rigId=%s', tostring(rigId))
    -- Wait briefly for NUI to report ready; avoids locking player if NUI failed to load.
    if not nuiReady then
        local start = GetGameTimer()
        while not nuiReady and (GetGameTimer() - start) < 2000 do
            Wait(50)
        end
        if not nuiReady then
            dbg('NUI not ready after 2000ms (opening anyway)')
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
        dbg('getRigState returned nil; using defaults')
        state = { fuelCans = 0, isRunning = false, barrelsReady = 0, remaining = 0 }
    end

    local rigName = ''
    local okName, nameOrErr = pcall(function()
        return lib.callback.await('L3GiTOilRig:server:getRigName', false, rigId)
    end)
    if okName and type(nameOrErr) == 'string' then
        rigName = nameOrErr
    else
        dbg('getRigName failed or returned non-string')
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
            subtitle = 'Fuel → Produce → Collect → Sell',
            uiKicker = (Config.Ui and Config.Ui.mainKicker) or 'Field Terminal',
            uiTitle = (Config.Ui and Config.Ui.mainTitle) or JOB_NAME,
            uiSubtitle = (Config.Ui and Config.Ui.mainSubtitle) or 'Restricted Field Terminal',
            infoNote = (Config.Ui and Config.Ui.infoNote) or ''
        }
    })

    SetNuiFocus(true, true)

    dbg('Rig UI shown; focus set. rigId=%s', tostring(rigId))

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
            dbg('uiShown not received within 1500ms; releasing focus')
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
    dbg('notify type=%s title=%s msg=%s', tostring(data and data.type), tostring(data and data.title), tostring(data and data.message))
    SendNUIMessage({
        action = 'notify',
        title = data.title or (Config and Config.NotifyTitle) or JOB_NAME,
        message = data.message or '',
        nType = data.type or 'info',
        duration = 4000
    })
end)

-- Server pushes updated rig state
RegisterNetEvent('L3GiTOilRig:client:updateRigState', function(rigId, data)
    dbg('updateRigState rigId=%s fuel=%s running=%s barrels=%s remaining=%s', tostring(rigId), tostring(data and data.fuelCans), tostring(data and data.isRunning), tostring(data and data.barrelsReady), tostring(data and data.remaining))
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
    local function alignRigObject(obj, rig)
        if not obj or obj == 0 or not rig then return end

        -- If the object was already frozen (or created by us), unfreeze briefly so coords can apply.
        FreezeEntityPosition(obj, false)

        -- Always apply heading.
        if rig.heading ~= nil then
            SetEntityHeading(obj, rig.heading)
        end

        -- Try to snap to the actual ground Z at the rig location.
        local x, y, z = rig.coords.x, rig.coords.y, rig.coords.z
        RequestCollisionAtCoord(x, y, z)

        local foundGround, groundZ = GetGroundZFor_3dCoord(x, y, z + 50.0, false)
        if foundGround then
            local zOff = tonumber(Config.RigZOffset or 0.0) or 0.0
            SetEntityCoordsNoOffset(obj, x, y, groundZ + zOff, false, false, false)
        else
            -- Fallback: use the entity's current position and the built-in helper.
            PlaceObjectOnGroundProperly(obj)
            local zOff = tonumber(Config.RigZOffset or 0.0) or 0.0
            if zOff ~= 0.0 then
                local p = GetEntityCoords(obj)
                SetEntityCoordsNoOffset(obj, p.x, p.y, p.z + zOff, false, false, false)
            end
        end

        FreezeEntityPosition(obj, true)
    end

    local function prepareRigObject(obj)
        if not obj or obj == 0 then return end

        -- Prevent world cleanup/destruction.
        SetEntityAsMissionEntity(obj, true, true)
        SetEntityInvincible(obj, true)
        SetEntityCanBeDamaged(obj, false)
        SetEntityDynamic(obj, false)

        -- Help avoid aggressive culling/streaming weirdness.
        SetEntityVisible(obj, true, false)
        ResetEntityAlpha(obj)
        SetEntityAlpha(obj, 255, false)
        SetEntityLodDist(obj, 1200)
    end

    local function ensureRigObject(rig)
        if not rig or not rig.coords then return 0 end

        local rigId = tostring(rig.id)
        local existing = rigObjects[rigId]
        if existing and existing ~= 0 and DoesEntityExist(existing) then
            return existing
        end

        local radius = 25.0
        local obj = GetClosestObjectOfType(rig.coords.x, rig.coords.y, rig.coords.z, radius, Config.RigModel, false, false, false)
        if obj == 0 then
            lib.requestModel(Config.RigModel)
            obj = CreateObject(Config.RigModel, rig.coords.x, rig.coords.y, rig.coords.z, false, false, false)
            dbg('spawned rig object rigId=%s entity=%s', tostring(rigId), tostring(obj))
        else
            dbg('found existing rig object rigId=%s entity=%s', tostring(rigId), tostring(obj))
        end

        if obj ~= 0 then
            prepareRigObject(obj)
            alignRigObject(obj, rig)
            rigObjects[rigId] = obj
            rigTargetsAdded[rigId] = false
        end

        return obj
    end

    local function ensureRigTarget(rig)
        if GetResourceState('ox_target') ~= 'started' then
            return
        end

        local rigId = tostring(rig.id)
        local obj = ensureRigObject(rig)
        if obj == 0 then return end

        if rigTargetsAdded[rigId] then
            return
        end

        exports.ox_target:addLocalEntity(obj, {
            {
                name = 'L3GiTOilRig_panel_' .. rigId,
                label = 'Rig Control Panel',
                icon = 'fa-solid fa-oil-can',
                distance = Config.TargetDistanceRig,
                onSelect = function()
                    openRigPanel(rig.id)
                end
            }
        })
        rigTargetsAdded[rigId] = true
        dbg('added ox_target to rigId=%s entity=%s', tostring(rigId), tostring(obj))
    end

    -- Always spawn rigs (even if ox_target isn't started yet).
    for _, rig in ipairs(Config.RigLocations or {}) do
        ensureRigObject(rig)
        ensureRigTarget(rig)
    end

    -- Watchdog: rigs can be cleaned up/destroyed; ensure they exist and are targetable.
    CreateThread(function()
        while true do
            Wait(1000)

            local ped = PlayerPedId()
            local p = GetEntityCoords(ped)
            for _, rig in ipairs(Config.RigLocations or {}) do
                local dx = (p.x - rig.coords.x)
                local dy = (p.y - rig.coords.y)
                local dz = (p.z - rig.coords.z)
                local dist = math.sqrt((dx * dx) + (dy * dy) + (dz * dz))

                -- Only babysit rigs when the player is reasonably close.
                if dist <= 175.0 then
                local rigId = tostring(rig.id)
                local before = rigObjects[rigId]
                local obj = ensureRigObject(rig)
                if obj ~= 0 and before ~= obj then
                    rigTargetsAdded[rigId] = false
                end

                -- If something made it invisible, force it back.
                if obj ~= 0 and DoesEntityExist(obj) then
                    prepareRigObject(obj)
                end

                ensureRigTarget(rig)
                end
            end
        end
    end)
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
    dbg('NUI closeUI')
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'hideRigUI' })
    currentRigId = nil
    fuelingInProgress = false
    fuelingEndsAt = 0
    cb('ok')
end)

RegisterNUICallback('closeSupplierUI', function(_, cb)
    dbg('NUI closeSupplierUI')
    cb('ok')
    SendNUIMessage({ action = 'hideSupplierUI' })
    SetNuiFocus(false, false)
end)

RegisterNUICallback('closeBuyerUI', function(_, cb)
    dbg('NUI closeBuyerUI')
    cb('ok')
    SendNUIMessage({ action = 'hideBuyerUI' })
    SetNuiFocus(false, false)
end)

RegisterNUICallback('buyDiesel', function(data, cb)
    cb('ok')

    local amount = tonumber(data and data.amount or 1) or 1
    dbg('NUI buyDiesel amount=%s', tostring(amount))
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
    dbg('NUI requestSupplierRefresh')
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
    dbg('NUI sellBarrels amount=%s', tostring(amount))
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
    dbg('NUI uiReady')
    cb('ok')
end)

RegisterNUICallback('uiShown', function(_, cb)
    lastUiShownAt = GetGameTimer()
    dbg('NUI uiShown')
    cb('ok')
end)

RegisterNUICallback('fuelRig', function(data, cb)
    cb('ok')

    local rigId = data.rigId

    dbg('NUI fuelRig rigId=%s', tostring(rigId))

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
    dbg('NUI startCycle rigId=%s', tostring(rigId))
    TriggerServerEvent('L3GiTOilRig:server:startCycle', rigId)
end)

RegisterNUICallback('collectBarrel', function(data, cb)
    cb('ok')
    dbg('NUI collectBarrel rigId=%s', tostring(data and data.rigId))
    TriggerServerEvent('L3GiTOilRig:server:collectBarrel', data.rigId)
end)

RegisterNUICallback('setRigName', function(data, cb)
    cb('ok')
    if not currentRigId then return end

    local rigId = data.rigId or currentRigId
    local name = data.rigName or ''

    dbg('NUI setRigName rigId=%s name=%s', tostring(rigId), tostring(name))

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
