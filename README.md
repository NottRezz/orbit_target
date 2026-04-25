# orbit_target

> Advanced dual-mode targeting system for FiveM superhero scripts.

A lightweight, highly optimized targeting resource with two distinct modes — a passive soft-highlight for normal play and an active lock-on system with an orbiting-ring HUD. Built to integrate cleanly into any superhero script via exports and callbacks.

---

## Features

- **Normal mode** — scans a configurable forward cone, highlights the nearest entity with a bracket reticle and info panel
- **Lock-on mode** — hard-locks up to 5 simultaneous targets, renders an orbiting ring at each target's screen position, tracks through the world
- **Auto-break** — locks break on death, distance exceeded, or line-of-sight loss
- **Full callback system** — react to target acquire, untarget, lock, break, and mode changes
- **Server exports** — force targets or clear locks from the server side
- **Cross-client broadcasts** — other clients are notified when a player acquires or breaks a lock
- **Optimized NUI** — dirty-flag gated pushes, DOM element pooling, GPU-accelerated CSS animations only

---

## Modes

| Mode | Description |
|------|-------------|
| `none` | System disabled, no NUI rendered |
| `normal` | Passive soft-highlight — scans a forward cone and highlights the nearest entity |
| `lockon` | Active hard-lock — orbiting ring UI tracks one or more entities across the world |

---

## Installation

1. Drop the `orbit_target` folder into your `resources` directory.
2. Add `ensure orbit_target` to your `server.cfg`.
3. Call `exports['orbit_target']:Enable()` from your superhero script when powers are active.

---

## Configuration (`shared/config.lua`)

| Key | Default | Description |
|-----|---------|-------------|
| `ScanInterval` | `100` | ms between normal-mode scans |
| `LockOnUpdateInterval` | `50` | ms between lock-on tracking updates |
| `NUIThrottle` | `50` | minimum ms between NUI pushes |
| `ScanRadius` | `50.0` | normal-mode detection radius (m) |
| `ScanConeAngle` | `45.0` | half-angle of detection cone (degrees) |
| `LockOnRadius` | `80.0` | max lock-on acquisition distance (m) |
| `LockOnConeAngle` | `30.0` | lock-on acquisition cone half-angle |
| `TargetPeds` | `true` | include peds in scans |
| `TargetVehicles` | `true` | include vehicles in scans |
| `TargetObjects` | `false` | include objects (expensive) |
| `IgnoreDead` | `true` | skip dead entities |
| `LockOnRequiresKey` | `true` | press key to enter lock-on vs auto |
| `LockOnKey` | `19` | key to acquire lock (Tab) |
| `LockOnCycleKey` | `172` | key to cycle primary target |
| `CancelLockOnKey` | `194` | key to cancel all locks |
| `MaxLockOnTargets` | `5` | max simultaneous lock-on slots |
| `LockOnBreakDistance` | `120.0` | auto-break distance (m) |
| `LockOnBreakLOS` | `true` | break on line-of-sight loss |
| `LockOnBreakLOSTime` | `3000` | ms without LOS before breaking |
| `ShowTargetName` | `true` | display entity label |
| `ShowTargetHealth` | `true` | display health bar |
| `ShowTargetDistance` | `true` | display distance |
| `ShowTargetThreat` | `true` | display threat level icon |
| `ColorNormal` | `#00e5ff` | soft-highlight / non-primary colour |
| `ColorLocked` | `#ff1744` | primary lock colour |
| `ColorFriendly` | `#69ff47` | friendly entity colour (reserved) |
| `PlayAcquireSound` | `true` | play sound on lock acquire |
| `PlayBreakSound` | `true` | play sound on lock break |

---

## Client Exports

All called via `exports['orbit_target']:FunctionName(...)`.

### System Control

```lua
-- Start the targeting system (enters normal mode)
exports['orbit_target']:Enable()

-- Stop the targeting system and clear all locks
exports['orbit_target']:Disable()

-- Returns true/false
local active = exports['orbit_target']:IsEnabled()

-- Returns 'none' | 'normal' | 'lockon'
local mode = exports['orbit_target']:GetMode()
```

### Normal Mode

```lua
-- Returns { entity = handle, type = 'ped'|'vehicle'|'object' }
-- entity is nil when nothing is in the cone
local t = exports['orbit_target']:GetSoftTarget()
if t.entity then
    print('Soft target:', t.entity, t.type)
end

-- Returns a rich info table for any entity handle
local info = exports['orbit_target']:GetEntityInfo(entity)
-- info = {
--   entity   = 12345,
--   type     = 'ped',
--   label    = 'Unknown Ped',
--   health   = 84,          -- 0-100
--   distance = 23,          -- metres
--   threat   = 2,           -- 0=none 1=low 2=armed 3=combat
--   coords   = vector3(...),
--   heading  = 180.0,
-- }
```

### Lock-On Mode

```lua
-- Force-lock any entity (adds it to lock slots). Returns true on success.
local ok = exports['orbit_target']:ForceLock(entity)

-- Release a specific entity from lock-on. Returns true if it was locked.
local ok = exports['orbit_target']:ReleaseLock(entity)

-- Release all locks and return to normal mode
exports['orbit_target']:ClearAllLocks()

-- Returns array of slot tables:
-- { { entity, type, slot, primary }, ... }
local slots = exports['orbit_target']:GetLockSlots()

-- Returns { entity, type } of the current primary (focused) lock
local t = exports['orbit_target']:GetPrimaryLock()

-- Set which entity is the primary/focused lock. Returns true on success.
local ok = exports['orbit_target']:SetPrimaryLock(entity)

-- Cycle the primary slot forward (wraps around)
exports['orbit_target']:CycleLock()
```

### Callbacks

Register callbacks before calling `Enable()`. They fire on the same resource tick as the event.

```lua
-- Fires when a new entity enters the soft-highlight cone
exports['orbit_target']:OnSoftTarget(function(entity, entityType)
    print('Now targeting', entity, entityType)
end)

-- Fires when the soft-highlight cone no longer contains an entity
exports['orbit_target']:OnSoftUntarget(function(entity)
    print('Lost soft target', entity)
end)

-- Fires when a lock-on slot is acquired
exports['orbit_target']:OnLockAcquire(function(entity, entityType, slot)
    print('Locked slot', slot, entity, entityType)
end)

-- Fires when a lock-on slot breaks
-- reason: 'dead' | 'distance' | 'los' | 'manual' | 'cancelled' | 'disabled' | 'released' | 'cleared'
exports['orbit_target']:OnLockBreak(function(entity, slot, reason)
    print('Lock broke', slot, reason)
end)

-- Fires when the mode changes
exports['orbit_target']:OnModeChange(function(newMode, oldMode)
    print('Mode', oldMode, '->', newMode)
end)
```

---

## Server Exports

```lua
-- Force a player client to lock onto a network entity
exports['orbit_target']:ForceTargetEntity(playerId, networkEntityId)

-- Clear all locks on a player client
exports['orbit_target']:ClearPlayerLocks(playerId)
```

---

## Net Events

### Client → Server

| Event | Args | Description |
|-------|------|-------------|
| `orbit_target:server:notifyLock` | `netId, type, slot` | Fired when a client acquires a lock |
| `orbit_target:server:notifyBreak` | `netId, slot, reason` | Fired when a lock breaks |

### Server → Client (broadcast)

| Event | Args |
|-------|------|
| `orbit_target:client:onLockAcquired` | `sourcePlayer, targetNetId, type, slot` |
| `orbit_target:client:onLockBroke` | `sourcePlayer, targetNetId, slot, reason` |

---

## Example — Superhero Integration

```lua
-- Enable targeting when powers are active
AddEventHandler('superhero:powersEnabled', function()
    exports['orbit_target']:Enable()
end)

AddEventHandler('superhero:powersDisabled', function()
    exports['orbit_target']:Disable()
end)

-- Beam attack fires at the primary locked target, falls back to soft target
RegisterCommand('beamattack', function()
    local t = exports['orbit_target']:GetPrimaryLock()
    if not t.entity then
        t = exports['orbit_target']:GetSoftTarget()
    end
    if t.entity then
        TriggerEvent('superhero:fireBeam', t.entity)
    end
end)

-- Multi-target AoE — iterate all lock slots
RegisterCommand('aoe', function()
    local slots = exports['orbit_target']:GetLockSlots()
    for _, s in ipairs(slots) do
        TriggerEvent('superhero:applyAoE', s.entity, s.type)
    end
end)

-- Play SFX and set anim on lock events
exports['orbit_target']:OnLockAcquire(function(entity, entityType, slot)
    TriggerEvent('superhero:playHeroPowerSFX', 'target_lock')
end)

exports['orbit_target']:OnModeChange(function(newMode, oldMode)
    if newMode == 'lockon' then
        TriggerEvent('superhero:setHeroAnim', 'combat_stance')
    elseif newMode == 'normal' then
        TriggerEvent('superhero:setHeroAnim', 'idle')
    end
end)
```

---

## Performance

- **NUI updates** are dirty-flag gated — `SendNUIMessage` is only called when state changes, and never faster than `Config.NUIThrottle` (default 50 ms).
- **JS DOM writes** are skipped when the value hasn't changed (dirty-check before every assignment).
- **Lock-on ring nodes** are pooled at startup — no DOM creation or destruction during gameplay.
- **CSS animations** use `transform` and `opacity` only, running on the compositor thread with zero layout cost. `will-change: transform` applied to all animated elements.
- **Scan loops** use `SetInterval` rather than `CreateThread` + `Wait(0)` — they fire at the configured interval and yield automatically between ticks.
- **Input polling** runs in its own thread only while the system is enabled, and self-exits cleanly on disable.

---

## File Structure

```
orbit_target/
├── fxmanifest.lua
├── README.md
├── shared/
│   └── config.lua          ← all tunable values
├── client/
│   ├── targeting.lua       ← core logic, OrbitTarget API, loops
│   └── exports.lua         ← thin export wrappers
├── server/
│   └── main.lua            ← broadcast events, server exports
└── html/
    ├── index.html
    ├── style.css           ← GPU-accelerated CSS, no JS animations
    └── app.js              ← dirty-flag DOM patcher, ring pool
```
