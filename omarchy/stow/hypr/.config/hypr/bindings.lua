-- zfiles bindings - personal keybindings overlay (Omarchy 4 Lua config)
-- SUPER = Caps Lock (held) via keyd; Caps Lock (tap) = Escape
--
-- Loaded by ~/.config/hypr/hyprland.lua after Omarchy's defaults.
-- See current bindings: omarchy menu keybindings --print

local home = os.getenv("HOME")

-- hl.unbind on a key that isn't bound (e.g. preinstalled app bindings turned
-- off) must not take the whole file down with it.
local function unbind(keys)
  pcall(hl.unbind, keys)
end

-- === Window Focus (vim-style, seamless) ===
-- One keystroke walks nvim splits -> herdr panes -> Hyprland windows, in that
-- order, so SUPER+hjkl feels the same whether you're in nvim, a herdr split, or
-- across tiled windows. Logic lives in scripts/herdr-nav.
unbind("SUPER + H")
unbind("SUPER + J") -- was toggle window split
unbind("SUPER + K") -- was keybinding menu
unbind("SUPER + L") -- was workspace layout toggle
local nav = home .. "/.config/hypr/scripts/herdr-nav "
o.bind("SUPER + H", "Focus left", nav .. "l")
o.bind("SUPER + J", "Focus down", nav .. "d")
o.bind("SUPER + K", "Focus up", nav .. "u")
o.bind("SUPER + L", "Focus right", nav .. "r")

-- === Window Actions ===
unbind("SUPER + W") -- was close window
unbind("SUPER + Q")
o.bind("SUPER + Q", "Close window", hl.dsp.window.close())

-- === Toggle Split (rebound from J) ===
unbind("SUPER + BACKSLASH")
o.bind("SUPER + BACKSLASH", "Toggle split orientation", hl.dsp.layout("togglesplit"))

-- === Keybinding Menu (rebound to SUPER + /) ===
unbind("SUPER + SLASH") -- was monitor scaling up
o.bind("SUPER + SLASH", "Keybindings", "omarchy-menu-keybindings")

-- === Browser (SUPER+W) ===
o.bind("SUPER + W", "Browser", "omarchy-launch-browser")

-- === AI Assistants (replacing ChatGPT/Grok) ===
unbind("SUPER + SHIFT + A")
unbind("SUPER + SHIFT + ALT + A")
o.bind("SUPER + SHIFT + A", "Claude", { webapp = "https://claude.ai" })
o.bind("SUPER + SHIFT + ALT + A", "Gemini", { webapp = "https://gemini.google.com" })

-- === Email (Neovim + Himalaya) ===
unbind("SUPER + SHIFT + E") -- was Hey Email
o.bind("SUPER + SHIFT + E", "Email", { launch = "xdg-terminal-exec -e nvim +Himalaya" })

-- === Remove unused web apps ===
unbind("SUPER + SHIFT + C") -- Hey Calendar
unbind("SUPER + SHIFT + W") -- Omawrite/Typora
unbind("SUPER + SHIFT + X") -- X/Twitter
unbind("SUPER + SHIFT + ALT + X") -- X Post

-- Clamshell mode is handled by Omarchy's stock binding
-- (omarchy-hyprland-monitor-internal off/on).

-- === Screen Recording (demo capture) ===
-- One-press TOGGLE via gpu-screen-recorder: first press starts, second press
-- stops + saves an MP4 to ~/Videos/. Omarchy's ALT+PRINT still opens the menu.
o.bind("SUPER + R", "Toggle screen recording", "omarchy-capture-screenrecording")
o.bind("SUPER + SHIFT + R", "Toggle screen recording (with mic)", "omarchy-capture-screenrecording --with-microphone-audio")
