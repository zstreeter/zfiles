# ble.sh init (read from ${XDG_CONFIG_HOME:-~/.config}/blesh/init.sh).
#
# The cursor shape says which vi mode you are in, so the "-- INSERT --" mode line is noise.
# Both settings belong to the vi keymap module, which ble.sh loads lazily -- hence the hook.
function blerc/vi-mode {
    bleopt keymap_vi_mode_show=          # no mode name under the prompt
    ble-bind -m vi_imap --cursor 5       # insert: blinking bar
    ble-bind -m vi_nmap --cursor 2       # normal: steady block
}
blehook/eval-after-load keymap_vi blerc/vi-mode
