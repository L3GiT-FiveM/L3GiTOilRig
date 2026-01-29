---@diagnostic disable: undefined-global
local rigs = {}
local fuelEventCooldown = {}
local DB = L3GiTOilRigDB

local PERSONAL_RIG_DELIM = '::'

local function getPlayerKey(src)
    if GetPlayerIdentifierByType then
        local license = GetPlayerIdentifierByType(src, 'license')
        if license and license ~= '' then return license end
    end

    local ids = GetPlayerIdentifiers(src)
    if ids and ids[1] then return ids[1] end

    return tostring(src)
end

local function findOnlineSrcByKey(key)
    key = tostring(key or '')
    if key == '' then return nil end

    for _, pid in ipairs(GetPlayers()) do
        if getPlayerKey(pid) == key then
            return tonumber(pid)
        end
    end

    return nil
end

local function newRigState()
    return {
        fuelCans = 0,
        isRunning = false,
        startTime = 0,
        endTime = 0,
        barrelsReady = 0,
        lastFuelUsed = 0,
        fuelEmptyNotified = false,
        _dbLoaded = false,
        _dbLoadAttemptAt = 0,
        _scheduledEnd = 0,
        _baseRigId = '',
        _ownerKey = ''
    }
end

local function resolveRigIds(src, rigId)
    local baseId = tostring(rigId or '')
    if baseId == '' then return nil, nil, nil end

    -- If a client ever sends a personal id, normalize to its base component.
    local cut = baseId:find(PERSONAL_RIG_DELIM, 1, true)
    if cut then
        baseId = baseId:sub(1, cut - 1)
    end

    local ownerKey = getPlayerKey(src)
    local personalId = ('%s%s%s'):format(baseId, PERSONAL_RIG_DELIM, ownerKey)
    return baseId, personalId, ownerKey
end

local function getRigForPlayer(src, rigId)
    local baseId, personalId, ownerKey = resolveRigIds(src, rigId)
    if not baseId or not personalId or not ownerKey then return nil, nil, nil, nil end

    rigs[personalId] = rigs[personalId] or newRigState()
    local rig = rigs[personalId]
    rig._baseRigId = baseId
    rig._ownerKey = ownerKey
    return rig, baseId, personalId, ownerKey
end

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

-- Forward declarations (used by the completion scheduler).
local nowMs
local advanceRigToNow
local scheduleCycleCompletion
local completeProductionIfFinished
local startCycle
local maybeAutoContinue
local getFuelBatchSize
local canStartCycle

local function dbReady()
    return DB and DB.IsReady and DB.IsReady()
end

local function dbSave(rigId, rig)
    if not dbReady() then return end
    if DB.SaveRigStateAwait then
        DB.SaveRigStateAwait(rigId, rig)
    else
        DB.SaveRigState(rigId, rig)
    end
end

local function titleMain()
    return (Config and Config.NotifyTitle) or (Config and Config.JobName) or 'Playground Oil Rig'
end

local function titleSupplier()
    return (Config and Config.Ui and Config.Ui.supplierSubtitle) or 'Fuel Supplier'
end

local function titleBuyer()
    return (Config and Config.Ui and Config.Ui.buyerSubtitle) or 'Oil Buyer'
end

local function waitForDbReady(timeoutMs)
    if dbReady() then return true end
    if not (MySQL and MySQL.query) then return false end

    local timeout = tonumber(timeoutMs or 0) or 0
    if timeout <= 0 then timeout = 4000 end

    local waited = 0
    while not dbReady() and waited < timeout do
        Wait(100)
        waited = waited + 100
    end

    if not dbReady() then
        dbg('DB not ready after %dms wait', waited)
    end
    return dbReady()
end

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= GetCurrentResourceName() then return end
    if not (DB and DB.SaveRigState) then return end
    if not dbReady() then return end

    for personalRigId, rig in pairs(rigs or {}) do
        if personalRigId and rig then
            -- Best-effort flush so active cycles resume with correct endTime.
            pcall(function()
                -- Don't use await here; shutdown hooks are not a safe place to yield.
                DB.SaveRigState(personalRigId, rig)
            end)
        end
    end
end)

local function applySavedRowToRig(rig, row)
    if not rig or not row then return end

    local function asBool01(v)
        if type(v) == 'boolean' then
            return v
        end
        return (tonumber(v or 0) or 0) == 1
    end

    rig.fuelCans = tonumber(row.fuel_cans or 0) or 0
    rig.isRunning = asBool01(row.is_running)
    rig.startTime = tonumber(row.start_time or 0) or 0
    rig.endTime = tonumber(row.end_time or 0) or 0
    rig.barrelsReady = tonumber(row.barrels_ready or 0) or 0
    rig.lastFuelUsed = tonumber(row.last_fuel_used or 0) or 0
end

local function normalizeRigRuntime(rigId, rig)
    if not rigId or not rig then return false end

    -- If a rig is marked running but has no valid endTime, treat it as stopped.
    -- This can happen with legacy rows, bad saves, or partial state during restarts.
    if rig.isRunning and (tonumber(rig.endTime or 0) or 0) <= 0 then
        rig.isRunning = false
        rig.startTime = 0
        rig.endTime = 0
        rig.lastFuelUsed = 0
        return true
    end

    return false
end

local function ensureRigLoaded(src, baseRigId, personalRigId, rig)
    if not baseRigId or not personalRigId or not rig then return false end

    if rig._dbLoaded then
        return true
    end

    if not dbReady() then
        local now = nowMs()
        if not rig._dbgNoDbAt or (now - rig._dbgNoDbAt) > 10000 then
            dbg('ensureRigLoaded(%s) skipped: DB not ready', tostring(personalRigId))
            rig._dbgNoDbAt = now
        end
        return false
    end

    -- Prevent spamming SQL if something calls this in a tight loop.
    local now = nowMs()
    if rig._dbLoadAttemptAt and (now - rig._dbLoadAttemptAt) < 2500 then
        return false
    end
    rig._dbLoadAttemptAt = now

    if not (DB and DB.LoadRigState) then
        return false
    end

    dbg('Loading rig state from DB for %s (base=%s)', tostring(personalRigId), tostring(baseRigId))

    -- Primary: legacy table keyed by personalRigId.
    local row = DB.LoadRigState(personalRigId)

    -- Fallback: if we previously used the per-player table (identifier + baseRigId), import it once.
    if not row then
        row = DB.LoadRigState(src, baseRigId)
        if row then
            dbg('Imported rig state from personal table for base rig %s into %s', tostring(baseRigId), tostring(personalRigId))
            applySavedRowToRig(rig, row)
            rig._dbLoaded = true
            normalizeRigRuntime(personalRigId, rig)
            dbSave(personalRigId, rig)
            return true
        end
    end

    if not row then
        dbg('No DB row found for rig %s', tostring(personalRigId))
        return false
    end

    applySavedRowToRig(rig, row)
    rig._dbLoaded = true

    dbg('Loaded rig %s: fuel=%s running=%s barrels=%s start=%s end=%s', tostring(personalRigId), tostring(rig.fuelCans), tostring(rig.isRunning), tostring(rig.barrelsReady), tostring(rig.startTime), tostring(rig.endTime))

    normalizeRigRuntime(personalRigId, rig)

    -- Catch up and re-schedule, if needed.
    if rig.isRunning then
        advanceRigToNow(personalRigId, rig, now)
        if rig.isRunning and (rig.endTime or 0) > 0 and rig._scheduledEnd ~= rig.endTime then
            rig._scheduledEnd = rig.endTime
            scheduleCycleCompletion(personalRigId, rig._ownerKey, rig.endTime)
        end
    end

    return true
end

local function calculateYield(fuelCans)
    local data = Config.FuelToYield[fuelCans]
    if not data then return 0 end
    return data.barrels or 0
end

local function getMaxStored()
    return tonumber(Config.MaxBarrelsStored) or 10
end

nowMs = function()
    return os.time() * 1000
end

local function sendRigStateToPlayer(src, rigId, rig)
    if not src then return end
    local remaining = 0
    if rig.isRunning then
        remaining = math.max((rig.endTime or 0) - (os.time() * 1000), 0)
    end

    TriggerClientEvent('L3GiTOilRig:client:updateRigState', src, rigId, {
        fuelCans = rig.fuelCans or 0,
        isRunning = rig.isRunning or false,
        remaining = remaining,
        barrelsReady = rig.barrelsReady or 0
    })
end

local function maybeNotifyFuelEmpty(src, rigId, rig)
    if not rigId or not rig then return end

    local fuel = tonumber(rig.fuelCans or 0) or 0
    if fuel > 0 then
        rig.fuelEmptyNotified = false
        return
    end

    if rig.isRunning then
        return
    end

    if rig.fuelEmptyNotified then
        return
    end

    rig.fuelEmptyNotified = true

    if not src then return end
    TriggerClientEvent('L3GiTOilRig:client:notify', src, {
        title = titleMain(),
        message = 'Your oil rig is out of fuel. Refill it to keep producing.',
        type = 'info',
        duration = 6500
    })
end

scheduleCycleCompletion = function(personalRigId, ownerKey, expectedEnd)
    if not personalRigId or not ownerKey then return end
    local rig = rigs[personalRigId]
    if not rig or not rig.isRunning then return end

    local remaining = math.max((expectedEnd or 0) - (os.time() * 1000), 0)
    SetTimeout(remaining + 150, function()
        local r = rigs[personalRigId]
        if not r or not r.isRunning then return end
        if r.endTime ~= expectedEnd then return end

        if completeProductionIfFinished(r) then
            -- Use up remaining fuel automatically before stopping.
            if not (maybeAutoContinue and maybeAutoContinue(personalRigId, ownerKey, r, expectedEnd)) then
                local onlineSrc = findOnlineSrcByKey(ownerKey)
                maybeNotifyFuelEmpty(onlineSrc, r._baseRigId, r)
                dbSave(personalRigId, r)
                if onlineSrc then
                    sendRigStateToPlayer(onlineSrc, r._baseRigId, r)
                end
            end
        end
    end)
end

local function beginCycleAt(rig, startAt)
    if not rig then return false end

    local batch = getFuelBatchSize()
    rig.fuelCans = (rig.fuelCans or 0) - batch
    rig.lastFuelUsed = batch
    rig.isRunning = true
    rig.startTime = tonumber(startAt or 0) or 0
    rig.endTime = rig.startTime + Config.ProductionTime

    return true
end

advanceRigToNow = function(rigId, rig, at)
    if not rigId or not rig or not rig.isRunning then return false end

    local t = tonumber(at or 0) or nowMs()
    local changed = false
    local safety = 0

    while rig.isRunning and (rig.endTime or 0) > 0 and t >= (rig.endTime or 0) do
        safety = safety + 1
        if safety > 10 then
            break
        end

        local endedAt = rig.endTime
        if completeProductionIfFinished(rig) then
            changed = true
        else
            break
        end

        if canStartCycle(rig) then
            beginCycleAt(rig, endedAt)
            changed = true
        else
            break
        end
    end

    if changed then
        -- Persisting is handled by caller (per-player) to avoid cross-player leakage.
    end

    return changed
end

CreateThread(function()
    if DB and DB.Init then
        DB.Init()
    end

    dbg('Server init: waiting for DB ready...')

    -- Wait for SQL to become ready (covers refresh/start order where oxmysql comes up after this resource).
    -- Don't permanently give up: oxmysql can become ready after refresh.
    local waited = 0
    local warned = false
    while not dbReady() do
        Wait(250)
        waited = waited + 250

        if not warned and waited >= 15000 then
            warned = true
            dbg('Still waiting for DB ready (%dms)...', waited)
        end
    end

    dbg('DB ready after %dms.', waited)

    -- Migrate any legacy rig IDs to current IDs (keeps saved progress).
    for _, rigCfg in ipairs(Config.RigLocations or {}) do
        if rigCfg.legacyId and rigCfg.id and DB and DB.MigrateRigId then
            dbg('Migrating rig id %s -> %s (if needed)', tostring(rigCfg.legacyId), tostring(rigCfg.id))
            DB.MigrateRigId(rigCfg.legacyId, rigCfg.id)
        end
    end

    -- Per-player rigs are loaded on-demand when a player interacts.
end)

completeProductionIfFinished = function(rig)
    if not rig or not rig.isRunning then return false end

    local now = os.time() * 1000
    if now < (rig.endTime or 0) then
        return false
    end

    local produced = calculateYield(rig.lastFuelUsed or 0)
    local cap = getMaxStored()
    local before = rig.barrelsReady or 0

    rig.barrelsReady = math.min(before + produced, cap)
    rig.isRunning = false
    rig.startTime = 0
    rig.endTime = 0
    rig.lastFuelUsed = 0

    return true
end

getFuelBatchSize = function()
    return tonumber(Config.MaxFuelCansPerCycle) or 3
end

local function getFuelCapacity()
    return tonumber(Config.MaxFuelCansStored) or 9
end

canStartCycle = function(rig, ignoreStorage)
    if not rig or rig.isRunning then return false end
    if (rig.fuelCans or 0) < getFuelBatchSize() then return false end
    if not ignoreStorage and (rig.barrelsReady or 0) >= getMaxStored() then return false end
    return true
end

startCycle = function(rigId, rig, ignoreStorage)
    if not canStartCycle(rig, ignoreStorage) then return false end

    beginCycleAt(rig, nowMs())

    -- Persist/notify handled by caller (per-player)

    return true
end

maybeAutoContinue = function(rigId, ownerKey, rig, startAt)
    if not rigId or not ownerKey or not rig then return false end
    -- Auto-continue should respect storage limits.
    if not canStartCycle(rig, false) then return false end

    -- When auto-continuing after a finished cycle, align the next cycle start to the previous end time.
    local startTime = tonumber(startAt or 0) or 0
    if startTime <= 0 then
        startTime = nowMs()
    end

    beginCycleAt(rig, startTime)
    dbSave(rigId, rig)
    local onlineSrc = findOnlineSrcByKey(ownerKey)
    if onlineSrc then
        sendRigStateToPlayer(onlineSrc, rig._baseRigId, rig)
    end
    scheduleCycleCompletion(rigId, ownerKey, rig.endTime)
    return true
end

RegisterNetEvent('L3GiTOilRig:server:buyDiesel', function(amount)
    local src = source

    dbg('buyDiesel src=%s amount=%s', tostring(src), tostring(amount))

    local qty = tonumber(amount or 1) or 1
    qty = math.floor(qty)
    if qty < 1 then qty = 1 end
    if qty > 9 then qty = 9 end

    local current = exports.ox_inventory:GetItem(src, Config.FuelItem, nil, true) or 0
    current = tonumber(current or 0) or 0
    local maxHold = tonumber(Config.MaxFuelCansStored) or 9
    if current >= maxHold then
        dbg('buyDiesel blocked: current=%d maxHold=%d', current, maxHold)
        Notify(src, {
            title = titleSupplier(),
            message = ('You can only hold %d diesel cans.'):format(maxHold),
            type = 'error'
        })
        return
    end

    local allowed = maxHold - current
    if qty > allowed then
        qty = allowed
    end
    if qty <= 0 then
        return
    end

    if not exports.ox_inventory:CanCarryItem(src, Config.FuelItem, qty) then
        Notify(src, {
            title = titleSupplier(),
            message = 'You cannot carry more diesel cans.',
            type = 'error'
        })
        return
    end

    local totalCost = (tonumber(Config.FuelCost) or 0) * qty
    local removed = exports.ox_inventory:RemoveItem(src, 'money', totalCost)
    if not removed then
        dbg('buyDiesel failed: insufficient cash (cost=%s qty=%s)', tostring(totalCost), tostring(qty))
        Notify(src, {
            title = titleSupplier(),
            message = 'You do not have enough cash.',
            type = 'error'
        })
        return
    end

    exports.ox_inventory:AddItem(src, Config.FuelItem, qty)

    dbg('buyDiesel success: qty=%s totalCost=%s', tostring(qty), tostring(totalCost))

    Notify(src, {
        title = titleSupplier(),
        message = ('Purchased %dx diesel can(s) for $%s (%d/%d).'):format(qty, totalCost, math.min(current + qty, maxHold), maxHold),
        type = 'success'
    })
end)

RegisterNetEvent('L3GiTOilRig:server:fuelRig', function(rigId, cansToUse)
    local src = source
    dbg('fuelRig src=%s rigId=%s cansToUse=%s', tostring(src), tostring(rigId), tostring(cansToUse))
    local rig, baseId, personalId, ownerKey = getRigForPlayer(src, rigId)
    if not rig then return end

    -- Ensure SQL is online so we can persist and avoid state desync.
    if (MySQL and MySQL.query) and not dbReady() then
        if not waitForDbReady(15000) then
            Notify(src, {
                title = titleMain(),
                message = 'Rig database is still loading. Try again in a moment.',
                type = 'error'
            })
            return
        end
    end

    ensureRigLoaded(src, baseId, personalId, rig)

    do
        local now = GetGameTimer()
        local last = fuelEventCooldown[src]
        if last and (now - last) < 1500 then
            return
        end
        fuelEventCooldown[src] = now
    end

    local batch = 1
    local capacity = getFuelCapacity()

    if (rig.fuelCans or 0) >= capacity then
        dbg('fuelRig blocked: tank full (%s/%s)', tostring(rig.fuelCans), tostring(capacity))
        Notify(src, {
            title = titleMain(),
            message = ('Fuel tank is full (%d/%d gal).'):format(rig.fuelCans or 0, capacity),
            type = 'error'
        })
        return
    end

    local has = exports.ox_inventory:GetItem(src, Config.FuelItem, nil, true)
    if (has or 0) < batch then
        dbg('fuelRig blocked: player lacks fuel item (%s have=%s need=%s)', tostring(Config.FuelItem), tostring(has), tostring(batch))
        Notify(src, {
            title = titleMain(),
            message = ('You need %d diesel cans.'):format(batch),
            type = 'error'
        })
        return
    end

    local removed = exports.ox_inventory:RemoveItem(src, Config.FuelItem, 1)
    if not removed then
        dbg('fuelRig failed: RemoveItem failed (item=%s src=%s)', tostring(Config.FuelItem), tostring(src))
        Notify(src, {
            title = titleMain(),
            message = 'Fueling failed (inventory remove failed). Try again.',
            type = 'error'
        })
        return
    end
    rig.fuelCans = math.min((rig.fuelCans or 0) + 1, capacity)

    dbg('fuelRig applied: rigId=%s fuelNow=%s/%s', tostring(rigId), tostring(rig.fuelCans), tostring(capacity))

    -- Reset fuel-empty notification once fuel is added.
    if (rig.fuelCans or 0) > 0 then
        rig.fuelEmptyNotified = false
    end

    Notify(src, {
        title = titleMain(),
        message = ('Added 1 gal fuel (%d/%d gal).'):format(rig.fuelCans or 0, capacity),
        type = 'success'
    })

    dbg('fuelRig saving state: baseId=%s personalId=%s fuel=%s', tostring(baseId), tostring(personalId), tostring(rig.fuelCans))
    dbSave(personalId, rig)
    sendRigStateToPlayer(src, baseId, rig)
end)

RegisterNetEvent('L3GiTOilRig:server:startCycle', function(rigId)
    local src = source

    dbg('startCycle request src=%s rigId=%s', tostring(src), tostring(rigId))

    if (MySQL and MySQL.query) and not dbReady() then
        dbg('startCycle blocked: DB not ready')
        Notify(src, {
            title = titleMain(),
            message = 'Rig database is still loading. Try again in a moment.',
            type = 'error'
        })
        return
    end

    local baseId = tostring(rigId or '')
    if baseId == '' then
        dbg('startCycle blocked: invalid rig id')
        Notify(src, {
            title = titleMain(),
            message = 'Start failed: invalid rig id.',
            type = 'error'
        })
        return
    end

    local rig, baseId2, personalId, ownerKey = getRigForPlayer(src, baseId)
    ensureRigLoaded(src, baseId2, personalId, rig)
    if not rig then
        Notify(src, {
            title = titleMain(),
            message = ('Start failed: rig not found (%s).'):format(baseId),
            type = 'error'
        })
        return
    end

    if rig.isRunning then
        dbg('startCycle blocked: already running (%s)', tostring(baseId))
        Notify(src, { title = titleMain(), message = 'This rig is already running.', type = 'error' })
        return
    end

    local need = getFuelBatchSize()
    local fuel = tonumber(rig.fuelCans or 0) or 0
    if fuel < need then
        dbg('startCycle blocked: insufficient fuel (%s fuel=%d need=%d)', tostring(baseId), fuel, need)
        Notify(src, {
            title = titleMain(),
            message = ('You need at least %d gal fuel to start a cycle (rig has %d).'):format(need, fuel),
            type = 'error'
        })
        return
    end

    -- Manual start: allow starting as long as fuel is available (>= 3),
    -- even if storage is currently full. Output will cap at the storage limit.
    if startCycle(personalId, rig, true) then
        dbg('startCycle started: rig=%s start=%s end=%s fuelNow=%s', tostring(baseId), tostring(rig.startTime), tostring(rig.endTime), tostring(rig.fuelCans))
        Notify(src, { title = titleMain(), message = ('Cycle started (used %d gal).'):format(need), type = 'success' })

        dbSave(personalId, rig)
        sendRigStateToPlayer(src, baseId2, rig)
        scheduleCycleCompletion(personalId, ownerKey, rig.endTime)
    else
        local storage = tonumber(rig.barrelsReady or 0) or 0
        local maxStorage = getMaxStored()
        dbg('startCycle failed: rig=%s fuel=%d need=%d storage=%d/%d', tostring(baseId), fuel, need, storage, maxStorage)
        Notify(src, {
            title = titleMain(),
            message = ('Start failed (rig=%s, fuel=%d, need=%d, storage=%d/%d).'):format(baseId, fuel, need, storage, maxStorage),
            type = 'error'
        })
        sendRigStateToPlayer(src, baseId2, rig)
    end
end)

RegisterNetEvent('L3GiTOilRig:server:collectBarrel', function(rigId)
    local src = source
    dbg('collectBarrel src=%s rigId=%s', tostring(src), tostring(rigId))
    local rig, baseId, personalId, ownerKey = getRigForPlayer(src, rigId)
    if not rig then return end
    ensureRigLoaded(src, baseId, personalId, rig)

    if rig.isRunning and (rig.endTime or 0) > 0 then
        if advanceRigToNow(personalId, rig, nowMs()) then
            dbSave(personalId, rig)
        end
        if not rig.isRunning then
            maybeNotifyFuelEmpty(src, baseId, rig)
        end
    end

    local amount = tonumber(rig.barrelsReady or 0) or 0
    if amount <= 0 then
        dbg('collectBarrel blocked: no barrels (rig=%s)', tostring(rigId))
        Notify(src, {
            title = titleMain(),
            message = 'Rig is not ready to collect. No barrels produced.',
            type = 'error'
        })
        return
    end

    if not exports.ox_inventory:CanCarryItem(src, Config.BarrelItem, amount) then
        dbg('collectBarrel blocked: cannot carry item=%s amount=%s', tostring(Config.BarrelItem), tostring(amount))
        Notify(src, {
            title = titleMain(),
            message = ('You cannot carry %dx oil barrels. Your inventory is full.'):format(amount),
            type = 'error'
        })
        return
    end

    rig.barrelsReady = 0
    exports.ox_inventory:AddItem(src, Config.BarrelItem, amount)

    dbg('collectBarrel success: gave %dx %s', amount, tostring(Config.BarrelItem))

    Notify(src, {
        title = titleMain(),
        message = ('Collected %dx oil barrels.'):format(amount),
        type = 'success'
    })

    dbSave(personalId, rig)
    sendRigStateToPlayer(src, baseId, rig)
end)

RegisterNetEvent('L3GiTOilRig:server:sellBarrel', function()
    local src = source
    TriggerEvent('L3GiTOilRig:server:sellBarrels', 1)
end)

RegisterNetEvent('L3GiTOilRig:server:sellBarrels', function(amount)
    local src = source

    dbg('sellBarrels src=%s amount=%s', tostring(src), tostring(amount))

    local qty = tonumber(amount or 1) or 1
    qty = math.floor(qty)
    if qty < 1 then qty = 1 end

    local count = exports.ox_inventory:GetItem(src, Config.BarrelItem, nil, true) or 0
    count = tonumber(count or 0) or 0

    if count <= 0 then
        dbg('sellBarrels blocked: no barrels')
        Notify(src, {
            title = titleBuyer(),
            message = 'You have no oil barrels to sell.',
            type = 'error'
        })
        return
    end

    if qty > count then
        qty = count
    end

    local priceEach = tonumber(Config.BarrelSellPrice or 0) or 0
    local total = priceEach * qty

    local removed = exports.ox_inventory:RemoveItem(src, Config.BarrelItem, qty)
    if not removed then
        dbg('sellBarrels failed: RemoveItem failed (item=%s qty=%s)', tostring(Config.BarrelItem), tostring(qty))
        Notify(src, {
            title = titleBuyer(),
            message = 'Sale failed. Try again.',
            type = 'error'
        })
        return
    end

    exports.ox_inventory:AddItem(src, 'money', total)

    dbg('sellBarrels success: qty=%s total=%s', tostring(qty), tostring(total))

    Notify(src, {
        title = titleBuyer(),
        message = ('Sold %dx oil barrel(s) for $%s'):format(qty, total),
        type = 'success'
    })
end)

lib.callback.register('L3GiTOilRig:server:getRigState', function(src, rigId)
    -- If the resource just started, give SQL a moment to come online so we don't return a default state.
    waitForDbReady(15000)
    local rig, baseId, personalId, ownerKey = getRigForPlayer(src, rigId)
    if not rig then return nil end

    ensureRigLoaded(src, baseId, personalId, rig)

    local now = nowMs()
    local remaining = 0

    normalizeRigRuntime(personalId, rig)

    if rig.isRunning and (rig.endTime or 0) > 0 then
        if advanceRigToNow(personalId, rig, now) then
            dbSave(personalId, rig)
            if rig.isRunning and (rig.endTime or 0) > 0 and rig._scheduledEnd ~= rig.endTime then
                rig._scheduledEnd = rig.endTime
                scheduleCycleCompletion(personalId, ownerKey, rig.endTime)
            end
        end
    end

    if rig.isRunning then
        remaining = math.max((rig.endTime or 0) - now, 0)
    end

    return {
        fuelCans = rig.fuelCans,
        isRunning = rig.isRunning,
        startTime = rig.startTime,
        endTime = rig.endTime,
        barrelsReady = rig.barrelsReady,
        remaining = remaining,
        maxBarrels = getMaxStored()
    }
end)

lib.callback.register('L3GiTOilRig:server:getRigName', function(src, rigId)
    if not DB or not DB.GetRigName then return '' end
    return DB.GetRigName(src, rigId)
end)

lib.callback.register('L3GiTOilRig:server:setRigName', function(src, rigId, rigName)
    if not DB or not DB.SetRigName then
        return { ok = false, name = '' }
    end

    local ok, name = DB.SetRigName(src, rigId, rigName)
    return { ok = ok == true, name = name or '' }
end)
