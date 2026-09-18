
local home = os.getenv("HOME")

local function unbind(keys)
  pcall(hl.unbind, keys)
end

unbind("SUPER + H")
unbind("SUPER + J") -- was toggle window split
unbind("SUPER + K") -- was keybinding menu
unbind("SUPER + L") -- was workspace layout toggle
local nav = home .. "/.config/hypr/scripts/herdr-nav "
o.bind("SUPER + H", "Focus left", nav .. "l")
o.bind("SUPER + J", "Focus down", nav .. "d")
o.bind("SUPER + K", "Focus up", nav .. "u")
o.bind("SUPER + L", "Focus right", nav .. "r")

unbind("SUPER + W") -- was close window
unbind("SUPER + Q")
o.bind("SUPER + Q", "Close window", hl.dsp.window.close())

unbind("SUPER + BACKSLASH")
o.bind("SUPER + BACKSLASH", "Toggle split orientation", hl.dsp.layout("togglesplit"))

unbind("SUPER + SLASH") -- was monitor scaling up
o.bind("SUPER + SLASH", "Keybindings", "omarchy-menu-keybindings")

o.bind("SUPER + W", "Browser", "omarchy-launch-browser")

unbind("SUPER + SHIFT + A")
unbind("SUPER + SHIFT + ALT + A")
o.bind("SUPER + SHIFT + A", "Claude", { webapp = "https://claude.ai" })
o.bind("SUPER + SHIFT + ALT + A", "Gemini", { webapp = "https://gemini.google.com" })

unbind("SUPER + SHIFT + E") -- was Hey Email
o.bind("SUPER + SHIFT + E", "Email", { launch = "xdg-terminal-exec -e nvim +Himalaya" })

unbind("SUPER + SHIFT + C") -- Hey Calendar
unbind("SUPER + SHIFT + W") -- Omawrite/Typora
unbind("SUPER + SHIFT + X") -- X/Twitter
unbind("SUPER + SHIFT + ALT + X") -- X Post


o.bind("SUPER + R", "Toggle screen recording", "omarchy-capture-screenrecording")
o.bind("SUPER + SHIFT + R", "Toggle screen recording (with mic)", "omarchy-capture-screenrecording --with-microphone-audio")
