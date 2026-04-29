--[[
    orbit_target — Shared Configuration
    ====================================
    All tunable values live here. Changes take effect on resource restart.
--]]

Config = {}

-- ─── Tick Rates ───────────────────────────────────────────────────────────────
-- How often (ms) the scan loop runs. Lower = more responsive, higher = cheaper.
Config.ScanInterval         = 50    -- normal-mode entity scan
Config.LockOnUpdateInterval = 33    -- lock-on tracking update
Config.NUIThrottle          = 33    -- minimum ms between NUI pushes (~30fps cap)

-- ─── Detection ────────────────────────────────────────────────────────────────
Config.ScanRadius           = 100.0  -- metres — normal mode entity detection radius
Config.ScreenSnapRadius     = 0.08  -- normalised screen units from centre (0.0–0.5) to trigger soft lock
Config.LockOnRadius         = 80.0  -- metres — how far away lock-on can acquire
Config.LockOnScreenSnap     = 0.06  -- screen-centre snap radius for lock-on acquisition

-- ─── Entity Filters ───────────────────────────────────────────────────────────
Config.TargetPeds           = true  -- scan for peds
Config.TargetVehicles       = true  -- scan for vehicles
Config.TargetObjects        = false -- scan for objects (expensive — off by default)
Config.IgnoreDead           = true  -- skip dead entities in normal mode
Config.IgnoreFriendly       = false -- set true to skip same-team peds

-- ─── Lock-On Behaviour ────────────────────────────────────────────────────────
Config.LockOnRequiresKey    = true  -- true = press key to enter lock-on; false = auto
Config.LockOnKey            = 27    -- INPUT_CHARACTER_WHEEL (Tab) — change freely
Config.LockOnCycleKey       = 15   -- INPUT_SELECT_NEXT_WEAPON — cycle targets
Config.CancelLockOnKey      = 27   -- INPUT_FRONTEND_CANCEL (Escape)
Config.MaxLockOnTargets     = 5     -- max simultaneous lock-on slots
Config.LockOnBreakDistance  = 120.0 -- metres — lock breaks if target moves beyond this
Config.LockOnBreakLOS       = true  -- break lock when target leaves line-of-sight
Config.LockOnBreakLOSTime   = 3000  -- ms of hidden target before lock breaks

-- ─── Visual ───────────────────────────────────────────────────────────────────
Config.ShowTargetName       = true
Config.ShowTargetHealth     = true
Config.ShowTargetDistance   = true
Config.ShowTargetThreat     = true  -- shows a threat level icon based on armed/wanted

-- Colours (hex strings used by NUI)
Config.ColorNormal          = '#00e5ff'   -- cyan — soft highlight
Config.ColorLocked          = '#ff1744'   -- red  — confirmed lock
Config.ColorFriendly        = '#69ff47'   -- green

-- ─── Audio ────────────────────────────────────────────────────────────────────
Config.PlayAcquireSound     = true
Config.AcquireSound         = 'WEAPON_ARMOUR_UPGRADE'
Config.AcquireSoundBank     = 'HUD_MINI_GAME_SOUNDSET'
Config.PlayBreakSound       = true
Config.BreakSound           = 'BACK'
Config.BreakSoundBank       = 'HUD_FRONTEND_DEFAULT_SOUNDSET'
