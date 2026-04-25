--[[
    orbit_target — Client Core
    ===========================
    Manages two targeting modes:

      NORMAL   — passive soft-highlight of nearest entity in a forward cone.
                 Updates at Config.ScanInterval. Fires callbacks & exports.

      LOCK-ON  — active hard-lock on one or more entities. Orbiting-ring NUI,
                 distance/health/threat HUD. Updates at Config.LockOnUpdateInterval.
                 Breaks on distance / LOS loss.

    Internal state is private; external scripts interact via exports (exports.lua).
--]]

-- ─── Localised globals (avoid table lookups in hot paths) ────────────────────
local math_sqrt  = math.sqrt
local math_floor = math.floor
local math_max   = math.max
local ipairs     = ipairs
local table_remove = table.remove

local PlayerPedId = PlayerPedId
local PlayerId = PlayerId
local GetGameTimer = GetGameTimer
local GetGamePool = GetGamePool
local GetEntityCoords = GetEntityCoords
local GetEntityModel = GetEntityModel
local GetEntityHeading = GetEntityHeading
local GetEntityHealth = GetEntityHealth
local DoesEntityExist = DoesEntityExist
local IsEntityAPed = IsEntityAPed
local IsEntityAVehicle = IsEntityAVehicle
local IsEntityDead = IsEntityDead
local IsPedInCombat = IsPedInCombat
local IsPedArmed = IsPedArmed
local GetPedRelationshipGroupHash = GetPedRelationshipGroupHash
local GetPedMaxHealth = GetPedMaxHealth
local GetPlayerWantedLevel = GetPlayerWantedLevel
local GetVehicleBodyHealth = GetVehicleBodyHealth
local GetDisplayNameFromVehicleModel = GetDisplayNameFromVehicleModel
local GetLabelText = GetLabelText
local GetScreenCoordFromWorldCoord = GetScreenCoordFromWorldCoord
local HasEntityClearLosToEntity = HasEntityClearLosToEntity
local SendNUIMessage = SendNUIMessage
local SetNuiFocus = SetNuiFocus
local CreateThread = CreateThread
local Wait = Wait
local IsControlJustPressed = IsControlJustPressed
local PlaySoundFrontend = PlaySoundFrontend
local NetworkGetEntityIsNetworked = NetworkGetEntityIsNetworked
local NetworkGetNetworkIdFromEntity = NetworkGetNetworkIdFromEntity
local TriggerServerEvent = TriggerServerEvent
local NetToEnt = NetToEnt
local RegisterNetEvent = RegisterNetEvent
local AddEventHandler = AddEventHandler
local GetCurrentResourceName = GetCurrentResourceName

-- ─── State ────────────────────────────────────────────────────────────────────

local state = {
    -- mode: 'none' | 'normal' | 'lockon'
    mode           = 'none',
    enabled        = false,

    -- normal mode
    softTarget     = nil,   -- entity handle or nil
    softTargetType = nil,   -- 'ped' | 'vehicle' | 'object'

    -- lock-on mode
    lockSlots      = {},    -- array of { entity, type, acquireTime, losTimer }
    primarySlot    = 1,

    -- NUI dirty-flag throttle
    lastNUIPush    = 0,
    nuiDirty       = false,
    lastNUIPayload = nil,
}

-- Callbacks registered by external scripts
local callbacks = {
    onSoftTarget   = {},   -- fn(entity, entityType)
    onSoftUntarget = {},   -- fn(entity)
    onLockAcquire  = {},   -- fn(entity, entityType, slot)
    onLockBreak    = {},   -- fn(entity, slot, reason)
    onModeChange   = {},   -- fn(newMode, oldMode)
}

-- ─── Pool cache — refreshed every POOL_REFRESH_MS, avoids table-per-scan ────
local poolCache = { peds = {}, vehicles = {}, objects = {} }
local poolLastRefresh = 0
local POOL_REFRESH_MS = 250
local targetPeds = Config.TargetPeds
local targetVehicles = Config.TargetVehicles
local targetObjects = Config.TargetObjects
local ignoreDead = Config.IgnoreDead
local scanInterval = Config.ScanInterval
local lockOnUpdateInterval = Config.LockOnUpdateInterval
local nuiThrottle = Config.NUIThrottle
local lockOnRequiresKey = Config.LockOnRequiresKey
local lockOnKey = Config.LockOnKey
local lockOnCycleKey = Config.LockOnCycleKey
local cancelLockOnKey = Config.CancelLockOnKey
local lockOnBreakLOS = Config.LockOnBreakLOS
local lockOnBreakLOSTime = Config.LockOnBreakLOSTime

local function refreshPoolCache()
    local now = GetGameTimer()
    if (now - poolLastRefresh) < POOL_REFRESH_MS then return end
    poolLastRefresh = now
    if targetPeds     then poolCache.peds     = GetGamePool('CPed')     end
    if targetVehicles then poolCache.vehicles = GetGamePool('CVehicle') end
    if targetObjects  then poolCache.objects  = GetGamePool('CObject')  end
end

-- Pre-squared thresholds — avoids sqrt in hot-path radius checks
local scanRadSq  = Config.ScanRadius   * Config.ScanRadius
local lockRadSq  = Config.LockOnRadius * Config.LockOnRadius
local lockBreakSq = Config.LockOnBreakDistance * Config.LockOnBreakDistance
-- Screen-snap thresholds stay as raw values; we compare squared below
local snapSq     = Config.ScreenSnapRadius  * Config.ScreenSnapRadius
local lockSnapSq = Config.LockOnScreenSnap  * Config.LockOnScreenSnap
local staticNUIActions = { hide = true, idle = true }

-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function entityType(ent)
    if IsEntityAPed(ent) then
        return 'ped'
    elseif IsEntityAVehicle(ent) then
        return 'vehicle'
    else
        return 'object'
    end
end

local function isEntityValid(ent)
    return ent and ent ~= 0 and DoesEntityExist(ent) and not IsEntityDead(ent)
end

local function getEntityLabel(ent, eType)
    if eType == 'ped' then
        local model = GetEntityModel(ent)
        local name = GetLabelText(GetDisplayNameFromVehicleModel(model))
        if name == 'NULL' or name == '' then name = 'Unknown Ped' end
        return name
    elseif eType == 'vehicle' then
        local model = GetEntityModel(ent)
        local name  = GetLabelText(GetDisplayNameFromVehicleModel(model))
        if name == 'NULL' or name == '' then name = 'Unknown Vehicle' end
        return name
    end
    return 'Object'
end

-- Returns pct (0-100) and overflow flag together to avoid calling GetEntityHealth twice
local function getEntityHealthFull(ent, eType)
    if eType == 'ped' then
        local raw   = GetEntityHealth(ent)
        local hp    = raw - 100
        local maxHp = GetPedMaxHealth(ent) - 100
        if maxHp <= 0 then return 0, false end
        return math_floor((hp / maxHp) * 100), raw > 200
    elseif eType == 'vehicle' then
        return math_floor((GetVehicleBodyHealth(ent) / 1000.0) * 100), false
    end
    return 100, false
end

-- Returns 0-3 threat level (0=none, 1=low, 2=medium, 3=high)
local function getEntityThreat(ent, eType, playerPed, playerId)
    if eType ~= 'ped' then return 0 end
    playerPed = playerPed or PlayerPedId()
    if IsPedInCombat(ent, playerPed) then return 3 end
    if IsPedArmed(ent, 7) then return 2 end
    if GetPedRelationshipGroupHash(ent) == GetPedRelationshipGroupHash(playerPed) then
        return 0
    end
    if GetPlayerWantedLevel(playerId or PlayerId()) > 0 then return 1 end
    return 0
end

local function fireCallbacks(list, ...)
    for _, fn in ipairs(list) do
        pcall(fn, ...)
    end
end

-- ─── NUI Communication ────────────────────────────────────────────────────────

local function buildNUIPayload()
    if state.mode == 'none' or not state.enabled then
        return { action = 'hide' }
    end

    if state.mode == 'normal' then
        if not isEntityValid(state.softTarget) then
            return { action = 'idle' }
        end
        local playerPed = PlayerPedId()
        local playerPos = GetEntityCoords(playerPed)
        local ent   = state.softTarget --[[@as integer]]
        local eType = state.softTargetType
        local pos   = GetEntityCoords(ent)
        local dx, dy, dz = pos.x - playerPos.x, pos.y - playerPos.y, pos.z - playerPos.z
        local dist  = math_sqrt(dx*dx + dy*dy + dz*dz)

        local onScreen, sx, sy = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z + 0.5)

        local health, overflow = getEntityHealthFull(ent, eType)

        return {
            action   = 'normal',
            onScreen = onScreen,
            sx       = sx,
            sy       = sy,
            health   = Config.ShowTargetHealth   and health           or nil,
            overflow = overflow,
            distance = Config.ShowTargetDistance and math_floor(dist) or nil,
            threat   = Config.ShowTargetThreat   and getEntityThreat(ent, eType, playerPed) or nil,
        }
    end

    if state.mode == 'lockon' then
        local playerPed = PlayerPedId()
        local playerPos = GetEntityCoords(playerPed)
        local showHealth = Config.ShowTargetHealth
        local showDistance = Config.ShowTargetDistance
        local showThreat = Config.ShowTargetThreat
        local slots = {}
        local lockSlots = state.lockSlots
        for i = 1, #lockSlots do
            local slot = lockSlots[i]
            if isEntityValid(slot.entity) then
                local pos  = GetEntityCoords(slot.entity)
                local dx, dy, dz = pos.x - playerPos.x, pos.y - playerPos.y, pos.z - playerPos.z
                local dist = math_sqrt(dx*dx + dy*dy + dz*dz)

                local onScreen, sx, sy = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z + 0.5)

                local health, overflow = getEntityHealthFull(slot.entity, slot.type)

                slots[#slots + 1] = {
                    slot     = i,
                    primary  = (i == state.primarySlot),
                    health   = showHealth and health or nil,
                    overflow = overflow,
                    distance = showDistance and math_floor(dist) or nil,
                    threat   = showThreat and getEntityThreat(slot.entity, slot.type, playerPed) or nil,
                    onScreen = onScreen,
                    sx       = sx,
                    sy       = sy,
                }
            end
        end

        if #slots == 0 then
            return { action = 'hide' }
        end

        return {
            action = 'lockon',
            slots  = slots,
        }
    end

    return { action = 'hide' }
end

local function pushNUI(force)
    local now = GetGameTimer()
    if not force and (now - state.lastNUIPush) < nuiThrottle then
        state.nuiDirty = true
        return
    end

    local payload = buildNUIPayload()

    -- Skip if static action hasn't changed (hide/idle don't carry per-frame data)
    if not force and state.lastNUIPayload
        and staticNUIActions[payload.action]
        and payload.action == state.lastNUIPayload.action then
        return
    end

    state.lastNUIPayload = payload
    state.lastNUIPush    = now
    state.nuiDirty       = false

    SendNUIMessage(payload)
end

-- ─── Normal Mode ──────────────────────────────────────────────────────────────

local function checkNormalEntity(ent, eType, playerPed, playerX, playerY, playerZ, bestSq)
    if ent == playerPed                        then return nil, bestSq end
    if not DoesEntityExist(ent)                then return nil, bestSq end
    if ignoreDead and IsEntityDead(ent) then return nil, bestSq end

    local pos = GetEntityCoords(ent)
    local dx, dy, dz = pos.x - playerX, pos.y - playerY, pos.z - playerZ
    if (dx*dx + dy*dy + dz*dz) > scanRadSq then return nil, bestSq end

    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z + 0.5)
    if not onScreen then return nil, bestSq end

    local sdx, sdy = sx - 0.5, sy - 0.5
    local sq = sdx*sdx + sdy*sdy
    if sq >= bestSq then return nil, bestSq end

    if not HasEntityClearLosToEntity(playerPed, ent, 17) then return nil, bestSq end

    return ent, sq, eType
end

local function scanNormal()
    local playerPed = PlayerPedId()
    local playerPos = GetEntityCoords(playerPed)
    local playerX, playerY, playerZ = playerPos.x, playerPos.y, playerPos.z

    local bestEnt  = nil
    local bestSq   = snapSq   -- screen-distance² threshold; updated as we find closer candidates
    local bestType = nil

    --[[ local function checkEntity(ent, eType)
        local foundEnt, sq, foundType = checkNormalEntity(ent, eType, playerPed, playerX, playerY, playerZ, bestSq)
        if foundEnt then
            bestEnt, bestSq, bestType = foundEnt, sq, foundType
        end
        return

        if ent == playerPed                        then return end
        if not DoesEntityExist(ent)                then return end
        if ignoreDead and IsEntityDead(ent) then return end

        -- 1. World-space distance cull (squared, no sqrt)
        local pos = GetEntityCoords(ent)
        local dx, dy, dz = pos.x - playerPos.x, pos.y - playerPos.y, pos.z - playerPos.z
        if (dx*dx + dy*dy + dz*dz) > scanRadSq then return end

        -- 2. Screen-project and reject off-screen or outside snap radius
        --    Cheaper than a LOS raycast — do this before HasEntityClearLosToEntity
        local onScreen, sx, sy = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z + 0.5)
        if not onScreen then return end

        local sdx, sdy = sx - 0.5, sy - 0.5
        local sq = sdx*sdx + sdy*sdy
        if sq >= bestSq then return end

        -- 3. LOS check — only reached by entities near screen centre (expensive raycast last)
        if not HasEntityClearLosToEntity(playerPed, ent, 17) then return end

        bestEnt  = ent
        bestSq   = sq
        bestType = eType
    end

    --]]

    refreshPoolCache()

    if targetPeds then
        local peds = poolCache.peds
        for i = 1, #peds do
            local ent, sq, eType = checkNormalEntity(peds[i], 'ped', playerPed, playerX, playerY, playerZ, bestSq)
            if ent then
                bestEnt, bestSq, bestType = ent, sq, eType
            end
        end
    end

    if targetVehicles then
        local vehicles = poolCache.vehicles
        for i = 1, #vehicles do
            local ent, sq, eType = checkNormalEntity(vehicles[i], 'vehicle', playerPed, playerX, playerY, playerZ, bestSq)
            if ent then
                bestEnt, bestSq, bestType = ent, sq, eType
            end
        end
    end

    if targetObjects then
        local objects = poolCache.objects
        for i = 1, #objects do
            local ent, sq, eType = checkNormalEntity(objects[i], 'object', playerPed, playerX, playerY, playerZ, bestSq)
            if ent then
                bestEnt, bestSq, bestType = ent, sq, eType
            end
        end
    end

    if bestEnt ~= state.softTarget then
        if state.softTarget then
            fireCallbacks(callbacks.onSoftUntarget, state.softTarget)
        end
        state.softTarget     = bestEnt
        state.softTargetType = bestType
        if bestEnt then
            fireCallbacks(callbacks.onSoftTarget, bestEnt, bestType)
        end
        pushNUI(true)
    else
        pushNUI(false)
    end
end

-- ─── Lock-On Mode ─────────────────────────────────────────────────────────────

local function playSound(sound, bank)
    PlaySoundFrontend(-1, sound, bank, true)
end

local function addLockSlot(ent, eType)
    if #state.lockSlots >= Config.MaxLockOnTargets then return false end
    local lockSlots = state.lockSlots
    for i = 1, #lockSlots do
        local s = lockSlots[i]
        if s.entity == ent then return false end
    end

    state.lockSlots[#state.lockSlots + 1] = {
        entity      = ent,
        type        = eType,
        acquireTime = GetGameTimer(),
        losTimer    = 0,
    }

    local slot = #state.lockSlots
    fireCallbacks(callbacks.onLockAcquire, ent, eType, slot)

    if Config.PlayAcquireSound then
        playSound(Config.AcquireSound, Config.AcquireSoundBank)
    end

    pushNUI(true)
    return true
end

local function removeLockSlot(index, reason)
    local slot = state.lockSlots[index]
    if not slot then return end

    fireCallbacks(callbacks.onLockBreak, slot.entity, index, reason or 'manual')

    if Config.PlayBreakSound then
        playSound(Config.BreakSound, Config.BreakSoundBank)
    end

    table_remove(state.lockSlots, index)

    if state.primarySlot > #state.lockSlots then
        state.primarySlot = math_max(1, #state.lockSlots)
    end

    pushNUI(true)
end

local function clearAllLocks(reason)
    for i = #state.lockSlots, 1, -1 do
        removeLockSlot(i, reason)
    end
end

local function updateLockOn()
    local playerPed = PlayerPedId()
    local playerPos = GetEntityCoords(playerPed)
    local now       = GetGameTimer()

    for i = #state.lockSlots, 1, -1 do
        local slot = state.lockSlots[i]

        if not DoesEntityExist(slot.entity) or IsEntityDead(slot.entity) then
            removeLockSlot(i, 'dead')
            goto continue
        end

        local ePos = GetEntityCoords(slot.entity)
        local dx, dy, dz = ePos.x - playerPos.x, ePos.y - playerPos.y, ePos.z - playerPos.z
        if (dx*dx + dy*dy + dz*dz) > lockBreakSq then
            removeLockSlot(i, 'distance')
            goto continue
        end

        if lockOnBreakLOS then
            local hasLOS = HasEntityClearLosToEntity(playerPed, slot.entity, 17)
            if not hasLOS then
                if slot.losTimer == 0 then
                    state.lockSlots[i].losTimer = now
                elseif (now - slot.losTimer) >= lockOnBreakLOSTime then
                    removeLockSlot(i, 'los')
                    goto continue
                end
            else
                state.lockSlots[i].losTimer = 0
            end
        end

        ::continue::
    end

    if state.mode == 'lockon' and #state.lockSlots == 0 then
        local oldMode = state.mode
        state.mode    = 'normal'
        fireCallbacks(callbacks.onModeChange, 'normal', oldMode)
        pushNUI(true)
        return
    end

    pushNUI(false)
end

-- Attempt to acquire lock-on on the entity closest to screen centre
local function checkLockEntity(ent, eType, playerPed, playerX, playerY, playerZ, bestSq)
    if ent == playerPed         then return nil, bestSq end
    if not DoesEntityExist(ent) then return nil, bestSq end
    if IsEntityDead(ent)        then return nil, bestSq end

    local pos = GetEntityCoords(ent)
    local dx, dy, dz = pos.x - playerX, pos.y - playerY, pos.z - playerZ
    if (dx*dx + dy*dy + dz*dz) > lockRadSq then return nil, bestSq end

    local onScreen, sx, sy = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z + 0.5)
    if not onScreen then return nil, bestSq end

    local sdx, sdy = sx - 0.5, sy - 0.5
    local sq = sdx*sdx + sdy*sdy
    if sq >= bestSq then return nil, bestSq end

    if not HasEntityClearLosToEntity(playerPed, ent, 17) then return nil, bestSq end

    return ent, sq, eType
end

local function tryAcquireLock()
    local playerPed = PlayerPedId()
    local playerPos = GetEntityCoords(playerPed)
    local playerX, playerY, playerZ = playerPos.x, playerPos.y, playerPos.z

    local bestEnt  = nil
    local bestSq   = lockSnapSq
    local bestType = nil

    --[[ local function check(ent, eType)
        local foundEnt, sq, foundType = checkLockEntity(ent, eType, playerPed, playerX, playerY, playerZ, bestSq)
        if foundEnt then
            bestEnt, bestSq, bestType = foundEnt, sq, foundType
        end
        return

        if ent == playerPed         then return end
        if not DoesEntityExist(ent) then return end
        if IsEntityDead(ent)        then return end

        local pos = GetEntityCoords(ent)
        local dx, dy, dz = pos.x - playerPos.x, pos.y - playerPos.y, pos.z - playerPos.z
        if (dx*dx + dy*dy + dz*dz) > lockRadSq then return end

        -- Screen-project before LOS (same ordering as scanNormal)
        local onScreen, sx, sy = GetScreenCoordFromWorldCoord(pos.x, pos.y, pos.z + 0.5)
        if not onScreen then return end

        local sdx, sdy = sx - 0.5, sy - 0.5
        local sq = sdx*sdx + sdy*sdy
        if sq >= bestSq then return end

        if not HasEntityClearLosToEntity(playerPed, ent, 17) then return end

        bestEnt  = ent
        bestSq   = sq
        bestType = eType
    end

    -- tryAcquireLock is called on keypress, not per-frame — use fresh pools
    --]]

    if targetPeds then
        local peds = GetGamePool('CPed')
        for i = 1, #peds do
            local ent, sq, eType = checkLockEntity(peds[i], 'ped', playerPed, playerX, playerY, playerZ, bestSq)
            if ent then
                bestEnt, bestSq, bestType = ent, sq, eType
            end
        end
    end

    if targetVehicles then
        local vehicles = GetGamePool('CVehicle')
        for i = 1, #vehicles do
            local ent, sq, eType = checkLockEntity(vehicles[i], 'vehicle', playerPed, playerX, playerY, playerZ, bestSq)
            if ent then
                bestEnt, bestSq, bestType = ent, sq, eType
            end
        end
    end

    if bestEnt then
        addLockSlot(bestEnt, bestType)
        state.mode = 'lockon'
        fireCallbacks(callbacks.onModeChange, 'lockon', 'normal')
    end
end

local function cycleLockTarget()
    if #state.lockSlots < 2 then return end
    state.primarySlot = (state.primarySlot % #state.lockSlots) + 1
    pushNUI(true)
end

-- ─── Main Loops ───────────────────────────────────────────────────────────────

local normalRunning  = false
local lockOnRunning  = false

local function startNormalLoop()
    if normalRunning then return end
    normalRunning = true
    CreateThread(function()
        while normalRunning do
            if state.enabled and state.mode == 'normal' then
                scanNormal()
            end
            Wait(scanInterval)
        end
    end)
end

local function stopNormalLoop()
    normalRunning = false
end

local function startLockOnLoop()
    if lockOnRunning then return end
    lockOnRunning = true
    CreateThread(function()
        while lockOnRunning do
            if state.enabled and state.mode == 'lockon' then
                updateLockOn()
            end
            Wait(lockOnUpdateInterval)
        end
    end)
end

local function stopLockOnLoop()
    lockOnRunning = false
end

local inputRunning = false

local function startInputLoop()
    if inputRunning then return end
    inputRunning = true
    CreateThread(function()
        while inputRunning do
            if lockOnRequiresKey and IsControlJustPressed(0, lockOnKey) then
                if state.mode == 'normal' then
                    tryAcquireLock()
                elseif state.mode == 'lockon' and lockOnKey == cancelLockOnKey then
                    clearAllLocks('cancelled')
                    local oldMode = state.mode
                    state.mode    = 'normal'
                    fireCallbacks(callbacks.onModeChange, 'normal', oldMode)
                    pushNUI(true)
                end
            end

            if state.mode == 'lockon' and IsControlJustPressed(0, lockOnCycleKey) then
                cycleLockTarget()
            end

            if lockOnKey ~= cancelLockOnKey
                and state.mode == 'lockon'
                and IsControlJustPressed(0, cancelLockOnKey) then
                clearAllLocks('cancelled')
                local oldMode = state.mode
                state.mode    = 'normal'
                fireCallbacks(callbacks.onModeChange, 'normal', oldMode)
                pushNUI(true)
            end

            Wait(0)
        end
    end)
end

local function stopInputLoop()
    inputRunning = false
end

-- ─── Public API (used by exports.lua) ─────────────────────────────────────────

OrbitTarget = {}

function OrbitTarget.enable()
    if state.enabled then return end
    state.enabled = true
    state.mode    = 'normal'
    SetNuiFocus(false, false)
    startNormalLoop()
    startLockOnLoop()
    startInputLoop()
    pushNUI(true)
    fireCallbacks(callbacks.onModeChange, 'normal', 'none')
end

function OrbitTarget.disable()
    if not state.enabled then return end
    state.enabled = false
    clearAllLocks('disabled')
    state.mode        = 'none'
    state.softTarget  = nil
    stopNormalLoop()
    stopLockOnLoop()
    stopInputLoop()
    pushNUI(true)
    fireCallbacks(callbacks.onModeChange, 'none', state.mode)
end

function OrbitTarget.isEnabled()
    return state.enabled
end

function OrbitTarget.getMode()
    return state.mode
end

function OrbitTarget.getSoftTarget()
    if not isEntityValid(state.softTarget) then return nil, nil end
    return state.softTarget, state.softTargetType
end

function OrbitTarget.getLockSlots()
    local out = {}
    for i, s in ipairs(state.lockSlots) do
        out[i] = { entity = s.entity, type = s.type, slot = i, primary = (i == state.primarySlot) }
    end
    return out
end

function OrbitTarget.getPrimaryLock()
    local slot = state.lockSlots[state.primarySlot]
    if not slot or not isEntityValid(slot.entity) then return nil, nil end
    return slot.entity, slot.type
end

function OrbitTarget.forceLock(entity)
    if not DoesEntityExist(entity) then return false end
    local eType = entityType(entity)
    if state.mode ~= 'lockon' then
        state.mode = 'lockon'
        fireCallbacks(callbacks.onModeChange, 'lockon', 'normal')
    end
    return addLockSlot(entity, eType)
end

function OrbitTarget.releaseLock(entity)
    for i, s in ipairs(state.lockSlots) do
        if s.entity == entity then
            removeLockSlot(i, 'released')
            return true
        end
    end
    return false
end

function OrbitTarget.clearAllLocks()
    clearAllLocks('cleared')
    if state.mode == 'lockon' then
        state.mode = 'normal'
        fireCallbacks(callbacks.onModeChange, 'normal', 'lockon')
        pushNUI(true)
    end
end

function OrbitTarget.setPrimaryLock(entity)
    for i, s in ipairs(state.lockSlots) do
        if s.entity == entity then
            state.primarySlot = i
            pushNUI(true)
            return true
        end
    end
    return false
end

function OrbitTarget.cycleLock()
    cycleLockTarget()
end

function OrbitTarget.getEntityInfo(entity)
    if not DoesEntityExist(entity) then return nil end
    local eType     = entityType(entity)
    local playerPos = GetEntityCoords(PlayerPedId())
    local entPos    = GetEntityCoords(entity)
    local dx, dy, dz = entPos.x - playerPos.x, entPos.y - playerPos.y, entPos.z - playerPos.z
    local health, _ = getEntityHealthFull(entity, eType)
    return {
        entity   = entity,
        type     = eType,
        label    = getEntityLabel(entity, eType),
        health   = health,
        distance = math_floor(math_sqrt(dx*dx + dy*dy + dz*dz)),
        threat   = getEntityThreat(entity, eType),
        coords   = entPos,
        heading  = GetEntityHeading(entity),
    }
end

-- ─── Callback Registration ────────────────────────────────────────────────────

function OrbitTarget.onSoftTarget(fn)
    callbacks.onSoftTarget[#callbacks.onSoftTarget + 1] = fn
end

function OrbitTarget.onSoftUntarget(fn)
    callbacks.onSoftUntarget[#callbacks.onSoftUntarget + 1] = fn
end

function OrbitTarget.onLockAcquire(fn)
    callbacks.onLockAcquire[#callbacks.onLockAcquire + 1] = fn
end

function OrbitTarget.onLockBreak(fn)
    callbacks.onLockBreak[#callbacks.onLockBreak + 1] = fn
end

function OrbitTarget.onModeChange(fn)
    callbacks.onModeChange[#callbacks.onModeChange + 1] = fn
end

-- ─── NUI Dirty-Flag Flusher ───────────────────────────────────────────────────
-- Runs at 33ms (matching NUIThrottle) — no need to check every frame.
CreateThread(function()
    while true do
        Wait(33)
        if state.nuiDirty then
            pushNUI(true)
        end
    end
end)

-- ─── Server-Triggered Net Events ─────────────────────────────────────────────

RegisterNetEvent('orbit_target:client:forceTarget', function(netId)
    local ent = NetToEnt(netId)
    if DoesEntityExist(ent) then
        OrbitTarget.forceLock(ent)
    end
end)

RegisterNetEvent('orbit_target:client:clearLocks', function()
    OrbitTarget.clearAllLocks()
end)

OrbitTarget.onLockAcquire(function(entity, eType, slot)
    if NetworkGetEntityIsNetworked(entity) then
        TriggerServerEvent('orbit_target:server:notifyLock', NetworkGetNetworkIdFromEntity(entity), eType, slot)
    end
end)

OrbitTarget.onLockBreak(function(entity, slot, reason)
    if DoesEntityExist(entity) and NetworkGetEntityIsNetworked(entity) then
        TriggerServerEvent('orbit_target:server:notifyBreak', NetworkGetNetworkIdFromEntity(entity), slot, reason)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        OrbitTarget.disable()
        SendNUIMessage({ action = 'hide' })
    end
end)
