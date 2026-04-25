--[[
    orbit_target — Server Side
    ===========================
    Thin server layer. Handles cross-client target broadcasts and exposes
    server-side exports so other resources can query or force targeting state.

    Events:
      orbit_target:server:notifyLock   — broadcast when a player acquires a lock
      orbit_target:server:notifyBreak  — broadcast when a lock breaks
      orbit_target:server:forceTarget  — server → client: force a specific target

    Exports (server-side):
      ForceTargetEntity(playerId, targetServerId)  — make a player lock onto another
      ClearPlayerLocks(playerId)                   — clear all locks for a player
      GetPlayerMode(playerId)                      — returns mode string via callback
--]]

-- ─── Lock Broadcast ───────────────────────────────────────────────────────────

RegisterNetEvent('orbit_target:server:notifyLock', function(targetNetId, targetType, slot)
    local src = source
    TriggerClientEvent('orbit_target:client:onLockAcquired', -1, src, targetNetId, targetType, slot)
end)

RegisterNetEvent('orbit_target:server:notifyBreak', function(targetNetId, slot, reason)
    local src = source
    TriggerClientEvent('orbit_target:client:onLockBroke', -1, src, targetNetId, slot, reason)
end)

-- ─── Server Exports ───────────────────────────────────────────────────────────

--[[
    ForceTargetEntity(playerId, targetServerId)
    Force the client at `playerId` to lock onto the entity controlled by `targetServerId`.
    targetServerId can be a player server id or a network entity id.
--]]
exports('ForceTargetEntity', function(playerId, targetNetId)
    TriggerClientEvent('orbit_target:client:forceTarget', playerId, targetNetId)
end)

--[[
    ClearPlayerLocks(playerId)
    Tell the client at `playerId` to release all lock-on slots.
--]]
exports('ClearPlayerLocks', function(playerId)
    TriggerClientEvent('orbit_target:client:clearLocks', playerId)
end)

-- ─── Client-Side Handlers for Server-Triggered Events ────────────────────────
-- These are handled in targeting.lua on the client; registered here for clarity.

-- orbit_target:client:forceTarget  (netId)  → client calls ForceLock on the entity
-- orbit_target:client:clearLocks           → client calls ClearAllLocks
