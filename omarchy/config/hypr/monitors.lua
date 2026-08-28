-- See https://wiki.hypr.land/Configuring/Basics/Monitors/
-- List current monitors and resolutions: hyprctl monitors all

-- 1x scale for the ultrawides
hl.env("GDK_SCALE", "1")

-- Stacked ultrawides: old Dell U3818DW on top, new Dell U3824DW (primary) below.
-- Laptop panel (eDP-1) is left to omarchy's lid switch: on when lid open, off when closed.
-- Do NOT hardcode eDP-1 disable here — it hides the panel from hyprctl, so the lid
-- handler writes a malformed "monitor=,disable" rule on close and breaks the externals.
-- Match by description, not port: dock port names (DP-3/DP-9...) shift between replugs.
-- Both panels are 3840x1600, so the bottom sits at y=1600.
hl.monitor({ output = "desc:Dell Inc. DELL U3818DW", mode = "3840x1600@60", position = "0x0", scale = 1 })
hl.monitor({ output = "desc:Dell Inc. DELL U3824DW", mode = "3840x1600@60", position = "0x1600", scale = 1 })

-- Fallback for any other monitor
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })
