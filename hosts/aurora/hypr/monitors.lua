-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and supported resolutions with: hyprctl monitors all

local omarchy_gdk_scale = 2
local omarchy_monitor_scale = 2

hl.env("GDK_SCALE", tostring(omarchy_gdk_scale))
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = omarchy_monitor_scale })

-- Configure a specific monitor.
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- Portrait/rotated secondary monitor (transform: 1 = 90°, 3 = 270°).
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })

-- Main ASUS XG27UCDMG: use its supported 4K 240 Hz mode.
hl.monitor({ output = "DP-1", mode = "3840x2160@240", position = "0x0", scale = 1.5 })

-- Second ASUS XG27UQ: use its maximum supported 4K refresh rate.
hl.monitor({ output = "DP-2", mode = "3840x2160@144", position = "2560x0", scale = 1.5 })
