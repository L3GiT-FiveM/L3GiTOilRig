---@diagnostic disable: undefined-global

L3GiTOilRigDB = L3GiTOilRigDB or {}
local DB = L3GiTOilRigDB

DB._ready = DB._ready or false
DB._initStarted = DB._initStarted or false
DB._waitingForMySQL = DB._waitingForMySQL or false
DB._namesCache = DB._namesCache or {}

local function trim(s)
    s = tostring(s or "")
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s
end

local function getPlayerKey(src)
    if type(src) ~= 'number' then
        return tostring(src)
    end

    if GetPlayerIdentifierByType then
        local license = GetPlayerIdentifierByType(src, 'license')
        if license and license ~= '' then return license end
    end

    local ids = GetPlayerIdentifiers(src)
    if ids and ids[1] then return ids[1] end

    return tostring(src)
end

function DB.IsReady()
    return DB._ready == true
end

function DB.Init()
    if DB._initStarted then return end
    DB._initStarted = true

    -- oxmysql may not be available yet during resource start/refresh.
    -- Don't permanently disable persistence; retry until MySQL is ready.
    if not MySQL or not MySQL.query then
        if not DB._waitingForMySQL then
            DB._waitingForMySQL = true
            CreateThread(function()
                while not MySQL or not MySQL.query do
                    Wait(250)
                end
                DB._waitingForMySQL = false

                -- Re-run init steps now that MySQL exists.
                if not DB._ready then
                    local function ensureTables()
                        MySQL.query([[
                            CREATE TABLE IF NOT EXISTS l3git_oilrig_state (
                                rig_id VARCHAR(128) NOT NULL,
                                fuel_cans INT NOT NULL DEFAULT 0,
                                is_running TINYINT(1) NOT NULL DEFAULT 0,
                                start_time BIGINT NOT NULL DEFAULT 0,
                                end_time BIGINT NOT NULL DEFAULT 0,
                                barrels_ready INT NOT NULL DEFAULT 0,
                                last_fuel_used INT NOT NULL DEFAULT 0,
                                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                                PRIMARY KEY (rig_id)
                            )
                        ]])

                        -- Best-effort widen for existing installs (no-op if already wide).
                        MySQL.query('ALTER TABLE l3git_oilrig_state MODIFY rig_id VARCHAR(128) NOT NULL')

                        -- Per-player state table (each player has their own instance of each rig).
                        MySQL.query([[
                            CREATE TABLE IF NOT EXISTS l3git_oilrig_state_personal (
                                identifier VARCHAR(96) NOT NULL,
                                rig_id VARCHAR(64) NOT NULL,
                                fuel_cans INT NOT NULL DEFAULT 0,
                                is_running TINYINT(1) NOT NULL DEFAULT 0,
                                start_time BIGINT NOT NULL DEFAULT 0,
                                end_time BIGINT NOT NULL DEFAULT 0,
                                barrels_ready INT NOT NULL DEFAULT 0,
                                last_fuel_used INT NOT NULL DEFAULT 0,
                                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                                PRIMARY KEY (identifier, rig_id)
                            )
                        ]])

                        MySQL.query([[
                            CREATE TABLE IF NOT EXISTS l3git_oilrig_names (
                                identifier VARCHAR(96) NOT NULL,
                                rig_id VARCHAR(64) NOT NULL,
                                rig_name VARCHAR(64) NOT NULL,
                                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                                PRIMARY KEY (identifier, rig_id)
                            )
                        ]])

                        DB._ready = true
                    end

                    if MySQL.ready then
                        MySQL.ready(ensureTables)
                    else
                        ensureTables()
                    end
                end
            end)
        end
        return
    end

    local function ensureTables()
        MySQL.query([[
            CREATE TABLE IF NOT EXISTS l3git_oilrig_state (
                rig_id VARCHAR(128) NOT NULL,
                fuel_cans INT NOT NULL DEFAULT 0,
                is_running TINYINT(1) NOT NULL DEFAULT 0,
                start_time BIGINT NOT NULL DEFAULT 0,
                end_time BIGINT NOT NULL DEFAULT 0,
                barrels_ready INT NOT NULL DEFAULT 0,
                last_fuel_used INT NOT NULL DEFAULT 0,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (rig_id)
            )
        ]])

        -- Best-effort widen for existing installs (no-op if already wide).
        MySQL.query('ALTER TABLE l3git_oilrig_state MODIFY rig_id VARCHAR(128) NOT NULL')

        -- Per-player state table (each player has their own instance of each rig).
        MySQL.query([[
            CREATE TABLE IF NOT EXISTS l3git_oilrig_state_personal (
                identifier VARCHAR(96) NOT NULL,
                rig_id VARCHAR(64) NOT NULL,
                fuel_cans INT NOT NULL DEFAULT 0,
                is_running TINYINT(1) NOT NULL DEFAULT 0,
                start_time BIGINT NOT NULL DEFAULT 0,
                end_time BIGINT NOT NULL DEFAULT 0,
                barrels_ready INT NOT NULL DEFAULT 0,
                last_fuel_used INT NOT NULL DEFAULT 0,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (identifier, rig_id)
            )
        ]])

        MySQL.query([[
            CREATE TABLE IF NOT EXISTS l3git_oilrig_names (
                identifier VARCHAR(96) NOT NULL,
                rig_id VARCHAR(64) NOT NULL,
                rig_name VARCHAR(64) NOT NULL,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (identifier, rig_id)
            )
        ]])

        DB._ready = true
    end

    if MySQL.ready then
        MySQL.ready(ensureTables)
    else
        CreateThread(function()
            Wait(250)
            ensureTables()
        end)
    end
end

function DB.LoadAllRigStates()
    if not DB.IsReady() or not MySQL or not MySQL.query then return {} end

    local rows = MySQL.query.await(
        'SELECT rig_id, fuel_cans, is_running, start_time, end_time, barrels_ready, last_fuel_used FROM l3git_oilrig_state',
        {}
    )

    local map = {}
    for _, row in ipairs(rows or {}) do
        if row.rig_id then
            map[row.rig_id] = row
        end
    end

    return map
end

local function loadRigStateLegacy(rigId)
    if not rigId then return nil end
    if not DB.IsReady() or not MySQL or not MySQL.query then return nil end

    local rows = MySQL.query.await(
        'SELECT rig_id, fuel_cans, is_running, start_time, end_time, barrels_ready, last_fuel_used FROM l3git_oilrig_state WHERE rig_id = ? LIMIT 1',
        { tostring(rigId) }
    )

    if rows and rows[1] then
        return rows[1]
    end

    return nil
end

-- Per-player load. Backwards compatible with older calls: DB.LoadRigState(rigId)
function DB.LoadRigState(src, rigId)
    -- Legacy signature: (rigId)
    if rigId == nil then
        return loadRigStateLegacy(src)
    end

    if not rigId then return nil end
    if not DB.IsReady() or not MySQL or not MySQL.query then return nil end

    local key = getPlayerKey(src)

    local rows = MySQL.query.await(
        'SELECT rig_id, fuel_cans, is_running, start_time, end_time, barrels_ready, last_fuel_used FROM l3git_oilrig_state_personal WHERE identifier = ? AND rig_id = ? LIMIT 1',
        { tostring(key), tostring(rigId) }
    )

    if rows and rows[1] then
        return rows[1]
    end

    return nil
end

local function buildStateParamsPersonal(identifier, rigId, rig)
    return {
        tostring(identifier),
        tostring(rigId),
        tonumber(rig.fuelCans or 0) or 0,
        (rig.isRunning and 1) or 0,
        tonumber(rig.startTime or 0) or 0,
        tonumber(rig.endTime or 0) or 0,
        tonumber(rig.barrelsReady or 0) or 0,
        tonumber(rig.lastFuelUsed or 0) or 0,
    }
end

local function buildStateParamsLegacy(rigId, rig)
    return {
        tostring(rigId),
        tonumber(rig.fuelCans or 0) or 0,
        (rig.isRunning and 1) or 0,
        tonumber(rig.startTime or 0) or 0,
        tonumber(rig.endTime or 0) or 0,
        tonumber(rig.barrelsReady or 0) or 0,
        tonumber(rig.lastFuelUsed or 0) or 0,
    }
end

local STATE_UPSERT_SQL_PERSONAL = [[
    INSERT INTO l3git_oilrig_state_personal
        (identifier, rig_id, fuel_cans, is_running, start_time, end_time, barrels_ready, last_fuel_used)
    VALUES
        (?, ?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
        fuel_cans = VALUES(fuel_cans),
        is_running = VALUES(is_running),
        start_time = VALUES(start_time),
        end_time = VALUES(end_time),
        barrels_ready = VALUES(barrels_ready),
        last_fuel_used = VALUES(last_fuel_used)
]]

local STATE_UPSERT_SQL = [[
    INSERT INTO l3git_oilrig_state
        (rig_id, fuel_cans, is_running, start_time, end_time, barrels_ready, last_fuel_used)
    VALUES
        (?, ?, ?, ?, ?, ?, ?)
    ON DUPLICATE KEY UPDATE
        fuel_cans = VALUES(fuel_cans),
        is_running = VALUES(is_running),
        start_time = VALUES(start_time),
        end_time = VALUES(end_time),
        barrels_ready = VALUES(barrels_ready),
        last_fuel_used = VALUES(last_fuel_used)
]]

-- Fire-and-forget save (safe to call during shutdown hooks).
-- Fire-and-forget save. Backwards compatible:
-- - DB.SaveRigState(rigId, rig) (legacy shared rig)
-- - DB.SaveRigState(src, rigId, rig) (personal rig)
function DB.SaveRigState(a, b, c)
    if not DB.IsReady() or not MySQL or not MySQL.query then return end

    -- Legacy signature.
    if c == nil then
        local rigId, rig = a, b
        if not rigId or not rig then return end
        MySQL.query(STATE_UPSERT_SQL, buildStateParamsLegacy(rigId, rig))
        return
    end

    local src, rigId, rig = a, b, c
    if not rigId or not rig then return end
    local key = getPlayerKey(src)
    MySQL.query(STATE_UPSERT_SQL_PERSONAL, buildStateParamsPersonal(key, rigId, rig))
end

-- Synchronous save (use during gameplay so a restart can't drop the write).
function DB.SaveRigStateAwait(a, b, c)
    if not DB.IsReady() or not MySQL or not MySQL.query then return end

    -- Legacy signature.
    if c == nil then
        local rigId, rig = a, b
        if not rigId or not rig then return end
        MySQL.query.await(STATE_UPSERT_SQL, buildStateParamsLegacy(rigId, rig))
        return
    end

    local src, rigId, rig = a, b, c
    if not rigId or not rig then return end
    local key = getPlayerKey(src)
    MySQL.query.await(STATE_UPSERT_SQL_PERSONAL, buildStateParamsPersonal(key, rigId, rig))
end

function DB.GetRigName(src, rigId)
    local key = getPlayerKey(src)
    DB._namesCache[key] = DB._namesCache[key] or {}

    if DB._namesCache[key][rigId] ~= nil then
        return DB._namesCache[key][rigId]
    end

    if not DB.IsReady() or not MySQL or not MySQL.query then
        DB._namesCache[key][rigId] = ''
        return ''
    end

    local rows = MySQL.query.await(
        'SELECT rig_name FROM l3git_oilrig_names WHERE identifier = ? AND rig_id = ? LIMIT 1',
        { key, tostring(rigId) }
    )

    local name = (rows and rows[1] and rows[1].rig_name) or ''
    name = tostring(name or '')

    DB._namesCache[key][rigId] = name
    return name
end

function DB.SetRigName(src, rigId, rigName)
    local key = getPlayerKey(src)
    DB._namesCache[key] = DB._namesCache[key] or {}

    local name = trim(tostring(rigName or ''))
    name = name:gsub('[\r\n\t]', ' ')
    name = trim(name)
    if #name > 64 then
        name = name:sub(1, 64)
        name = trim(name)
    end

    if not DB.IsReady() or not MySQL or not MySQL.query then
        DB._namesCache[key][rigId] = name
        return true, name
    end

    if name == '' then
        MySQL.query('DELETE FROM l3git_oilrig_names WHERE identifier = ? AND rig_id = ?', { key, tostring(rigId) })
        DB._namesCache[key][rigId] = ''
        return true, ''
    end

    MySQL.query(
        [[
            INSERT INTO l3git_oilrig_names (identifier, rig_id, rig_name)
            VALUES (?, ?, ?)
            ON DUPLICATE KEY UPDATE rig_name = VALUES(rig_name)
        ]],
        { key, tostring(rigId), name }
    )

    DB._namesCache[key][rigId] = name
    return true, name
end

function DB.MigrateRigId(oldRigId, newRigId)
    if not DB.IsReady() or not MySQL or not MySQL.query then return false end
    oldRigId = tostring(oldRigId or '')
    newRigId = tostring(newRigId or '')
    if oldRigId == '' or newRigId == '' or oldRigId == newRigId then return false end

    -- State table: only move if the new ID isn't already present.
    local existsNew = MySQL.query.await(
        'SELECT rig_id FROM l3git_oilrig_state WHERE rig_id = ? LIMIT 1',
        { newRigId }
    )
    if not (existsNew and existsNew[1] and existsNew[1].rig_id) then
        MySQL.query('UPDATE l3git_oilrig_state SET rig_id = ? WHERE rig_id = ?', { newRigId, oldRigId })
    end

    -- Personal state table: move rows to the new rig_id.
    MySQL.query('UPDATE l3git_oilrig_state_personal SET rig_id = ? WHERE rig_id = ?', { newRigId, oldRigId })

    -- Names table: upsert rows under the new rig_id, then remove old rows.
    local nameRows = MySQL.query.await(
        'SELECT identifier, rig_name FROM l3git_oilrig_names WHERE rig_id = ?',
        { oldRigId }
    )
    for _, row in ipairs(nameRows or {}) do
        if row.identifier and row.rig_name then
            MySQL.query(
                [[
                    INSERT INTO l3git_oilrig_names (identifier, rig_id, rig_name)
                    VALUES (?, ?, ?)
                    ON DUPLICATE KEY UPDATE rig_name = VALUES(rig_name)
                ]],
                { tostring(row.identifier), newRigId, tostring(row.rig_name) }
            )
        end
    end
    MySQL.query('DELETE FROM l3git_oilrig_names WHERE rig_id = ?', { oldRigId })

    -- Clear any cached name entries for the old id so it doesn't linger.
    for ident, rigsById in pairs(DB._namesCache or {}) do
        if rigsById and rigsById[oldRigId] ~= nil then
            rigsById[oldRigId] = nil
        end
    end

    return true
end
