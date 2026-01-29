Config = {}

--========================================================--
--====================== BRANDING ========================--
--========================================================--

-- These labels are used across UI headers, blips, and notifications.
-- Customize them to match your server/job.

Config.JobName = 'Playground Oil Rig'
Config.NotifyTitle = 'Playground Oil Rig'

-- When enabled, prints helpful debug logs to client/server console.
Config.Debug = false

Config.Ui = {
    mainKicker = 'Field Terminal',
    mainTitle = 'Playground Oil Rig',
    mainSubtitle = 'Restricted Field Terminal',
    opsKicker = 'Operations',
    supplierSubtitle = 'Fuel Supplier',
    buyerSubtitle = 'Oil Buyer',
    infoNote = 'All progress is saved after tsunami.'
}

--========================================================--
--======================= ECONOMY =========================--
--========================================================--

-- Inventory items
Config.FuelItem = 'rig_fuel'      -- updated fuel item name
Config.BarrelItem = 'oil_barrel'  -- unchanged

-- Prices
Config.FuelCost = 2000            -- cost per rig_fuel can
Config.BarrelSellPrice = 8976     -- tuned: ~$999,936 net over 7 days if kept running (336 barrels/week)

-- Fueling
Config.MaxFuelCansPerCycle = 3    -- fuel required per production cycle

-- Fuel tank capacity (total fuel stored at rig)
Config.MaxFuelCansStored = 9      -- 9 gal total capacity (add 1 gal at a time)


-- Storage
Config.MaxBarrelsStored = 10      -- max barrels that can be stored at the rig


--========================================================--
--===================== PRODUCTION ========================--
--========================================================--

-- Production time: 20 minutes per cycle (3 fuel)
Config.ProductionTime = 20 * 60 * 1000

-- Fuel → Yield mapping
Config.FuelToYield = {
    [3] = { barrels = 1, label = '3 gal → 1 barrel' },
}


--========================================================--
--==================== RIG LOCATIONS ======================--
--========================================================--

Config.RigModel = joaat('p_oil_pjack_03_s')

-- If your rig model is floating/sunk, adjust this (negative moves it down).
Config.RigZOffset = 0.0

Config.RigLocations = {
    {
        id = 'oilrig_01',
        legacyId = 'rig_1',
        coords = vector4(1721.658447, -1657.900146, 112.520378, 213.523438),
        heading = 0.0
    }
    -- Add more rigs here
}


--========================================================--
--========================= NPCS ==========================--
--========================================================--

Config.FuelSupplier = {
    pedModel = joaat('s_m_m_dockwork_01'),
    coords = vector4(1708.044434, -1661.021973, 112.469872, 282.119690),
    invincible = true,
    frozen = true,
    scenario = 'WORLD_HUMAN_CLIPBOARD',
    targetDistance = 2.0
}

Config.OilBuyer = {
    pedModel = joaat('s_m_m_ammucountry'),
    coords = vector4(1706.521729, -1654.657959, 112.447090, 275.730255),
    invincible = true,
    frozen = true,
    scenario = 'WORLD_HUMAN_STAND_IMPATIENT',
    targetDistance = 2.0
}

--========================================================--
--======================= TARGETING =======================--
--========================================================--

Config.TargetDistanceRig = 2.0


--========================================================--
--==================== NOTIFICATION WRAPPER ===============--
--========================================================--

function Notify(src, data)
    if IsDuplicityVersion() then
        TriggerClientEvent('L3GiTOilRig:client:notify', src, data)
    else
        TriggerEvent('L3GiTOilRig:client:notify', data)
    end
end
