--[[
    orbit_target — Client Exports
    ==============================
    All exports are thin wrappers around OrbitTarget.* (defined in targeting.lua).
    External scripts call these via:  exports['orbit_target']:FunctionName(...)

    ─── System Control ───────────────────────────────────────────────────────────
    Enable()                 — Start the targeting system (normal mode)
    Disable()                — Stop the targeting system, clear all locks
    IsEnabled()              — Returns bool
    GetMode()                — Returns 'none' | 'normal' | 'lockon'

    ─── Normal Mode ──────────────────────────────────────────────────────────────
    GetSoftTarget()          — Returns entity, entityType  (nil, nil if none)
    GetEntityInfo(entity)    — Returns table with label, health, distance, threat…

    ─── Lock-On Mode ─────────────────────────────────────────────────────────────
    ForceLock(entity)        — Force-add an entity to the lock-on list. Returns bool.
    ReleaseLock(entity)      — Remove a specific entity from lock-on. Returns bool.
    ClearAllLocks()          — Release all lock-on slots and return to normal mode.
    GetLockSlots()           — Returns array of slot tables.
    GetPrimaryLock()         — Returns entity, entityType of the current primary target.
    SetPrimaryLock(entity)   — Set the primary/focused lock slot. Returns bool.
    CycleLock()              — Cycle primary slot forward.

    ─── Callbacks ────────────────────────────────────────────────────────────────
    OnSoftTarget(fn)         — fn(entity, entityType)
    OnSoftUntarget(fn)       — fn(entity)
    OnLockAcquire(fn)        — fn(entity, entityType, slot)
    OnLockBreak(fn)          — fn(entity, slot, reason)
    OnModeChange(fn)         — fn(newMode, oldMode)
--]]

-- System control
exports('Enable',       function() OrbitTarget.enable()          end)
exports('Disable',      function() OrbitTarget.disable()         end)
exports('IsEnabled',    function() return OrbitTarget.isEnabled() end)
exports('GetMode',      function() return OrbitTarget.getMode()   end)

-- Normal mode
-- Returns { entity, type } table (exports only support one return value)
exports('GetSoftTarget', function()
    local ent, eType = OrbitTarget.getSoftTarget()
    return { entity = ent, type = eType }
end)

exports('GetEntityInfo', function(entity)
    return OrbitTarget.getEntityInfo(entity)
end)

exports('GetLookCoords', function(maxDistance, flags, ignoreEntity)
    return OrbitTarget.getLookCoords(maxDistance, flags, ignoreEntity)
end)

-- Lock-on
exports('ForceLock', function(entity)
    return OrbitTarget.forceLock(entity)
end)

exports('ReleaseLock', function(entity)
    return OrbitTarget.releaseLock(entity)
end)

exports('ClearAllLocks', function()
    OrbitTarget.clearAllLocks()
end)

exports('GetLockSlots', function()
    return OrbitTarget.getLockSlots()
end)

-- Returns { entity, type } table (exports only support one return value)
exports('GetPrimaryLock', function()
    local ent, eType = OrbitTarget.getPrimaryLock()
    return { entity = ent, type = eType }
end)

exports('SetPrimaryLock', function(entity)
    return OrbitTarget.setPrimaryLock(entity)
end)

exports('CycleLock', function()
    OrbitTarget.cycleLock()
end)

-- Callbacks
exports('OnSoftTarget',   function(fn) OrbitTarget.onSoftTarget(fn)   end)
exports('OnSoftUntarget', function(fn) OrbitTarget.onSoftUntarget(fn) end)
exports('OnLockAcquire',  function(fn) OrbitTarget.onLockAcquire(fn)  end)
exports('OnLockBreak',    function(fn) OrbitTarget.onLockBreak(fn)    end)
exports('OnModeChange',   function(fn) OrbitTarget.onModeChange(fn)   end)
