#Requires AutoHotkey v2.0
#SingleInstance Force

; Caps Lock dual-role for the Windows host of the WSL machine:
;   tap  -> Escape
;   hold -> the window-manager layer (GlazeWM), reached via F14+<key>
;
; This is the Windows counterpart to keyd's `capslock = overload(meta, esc)`
; on Omarchy (root_etc/keyd/default.conf). WSL2 has no /dev/input -- the
; keyboard never reaches the Linux side as raw input, it arrives pre-cooked
; through ConPTY -- so the remap has to happen on the Windows host.
;
; Why not Super, the way keyd does it:
; Windows itself owns a large slice of Super (Win+E, Win+R, Win+number, the
; Start menu on bare press...), so a Caps-as-Super chord collides constantly.
; Ctrl+Alt+Shift "hyper" was the other candidate and is worse than it looks:
; Ctrl+Alt is AltGr on International layouts, and real applications do bind
; those chords.
;
; Why F13/F14 specifically:
; No physical key on a normal keyboard emits them, Windows binds nothing to
; them, and they carry no modifier semantics that could leak into an app as a
; stray Ctrl or Alt. GlazeWM can match on them because its keybinding matcher
; tests whether ANY listed key is held, not just real modifiers --
; wm-platform/src/keybinding_listener.rs:
;
;     keybinding.keys().iter().all(|&key| ... event.is_key_down(key))
;
; and its separate "reject if extra modifiers are held" pass only covers the
; Shift/Ctrl/Alt/Win groups, which F13/F14 are not in.
;
; Why F13 is never actually SENT:
; Holding Caps re-enters the hotkey via OS auto-repeat, so emitting a real
; held F13 would fire a stream of F13 keydowns at whatever has focus. In a
; terminal that is a stream of `\e[25~` escape sequences dumped into the
; shell. So the hold is tracked as AHK state instead, and only the resolved
; chord is synthesized -- nothing leaks to the focused window either way.
;
; Why AutoHotkey and not kanata (windows/kanata/kanata.kbd, kept for reference):
; kanata is the closer equivalent, but its only winget source is the GitHub
; release, and Zscaler 403s that download on the AMD network. That block looks
; deliberate rather than incidental -- unrelated GitHub release downloads
; (AutoHotkey, PowerToys) come through fine, and kanata is a low-level keyboard
; interception tool of exactly the shape endpoint security flags. AutoHotkey is
; the long-standing standard for this on Windows and installs without a fight.

; The physical toggle is never wanted -- without this, chords like Caps+q would
; flip the Caps Lock state on the way past.
SetCapsLockState "AlwaysOff"

; Matches kanata's tap-repress-timeout/hold-timeout. Past this, a press with no
; other key involved is a hold that produced nothing, not a tap: releasing it
; should not emit a late Escape.
TAP_MS := 200

; WezTerm's GUI process. The terminal is the one window with its own inner
; layers (herdr panes, nvim splits), so it is the only place hjkl needs to ask
; before moving.
TERM_EXE := "ahk_exe wezterm-gui.exe"

; herdr-navd, the arbitration daemon inside WSL (herdr/.local/bin/herdr-navd).
; `nav/<dir>` walks nvim splits -> herdr panes -> GlazeWM and reports which
; layer took the move; `launch` claims the next new window for the workspace
; that is focused right now. Windows reaches a WSL loopback listener in both
; NAT and mirrored networking modes, so these calls work regardless of
; .wslconfig; only the daemon's own hop out to GlazeWM needs mirrored.
; 6224, not 6124: under mirrored networking a WSL listener shares Windows'
; 127.0.0.1, and 6124 belongs to Zebar. See herdr-navd's header.
NAVD_URL := "http://127.0.0.1:6224/"

; Keys the window-manager layer owns while Caps is held. Each is consumed here
; and re-emitted as F14+<key>. Whether a chord actually does anything is
; decided solely by windows/glazewm/config.yaml -- an unbound one is simply
; swallowed, exactly as SUPER+<unbound> is inert on Hyprland. The list is
; deliberately broad so adding a GlazeWM binding never means editing this file.
WM_KEYS := [
    "a", "b", "c", "d", "e", "f", "g", "i", "m", "n", "o", "p",
    "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "Left", "Right", "Up", "Down", "Enter", "Tab", "Backspace",
    ",", ".", "/", "\", "-", "=", ";", "'", "[", "]"
]

; h/j/k/l are absent from WM_KEYS on purpose -- they arbitrate against the
; terminal first. Values are the direction word herdr-navd expects.
NAV_KEYS := Map("h", "left", "j", "down", "k", "up", "l", "right")

; Space is absent from WM_KEYS for a different reason: it is the app launcher,
; Omarchy's SUPER+SPACE. GlazeWM cannot host this one -- it has no "send a
; keystroke" command, and PowerToys Run is activated by a hotkey rather than by
; running an exe, so there is nothing for shell-exec to call. Hence the
; translation happens here: Caps+Space becomes PowerToys Run's own default
; chord. Change this if you rebind PT Run away from Alt+Space.
LAUNCHER_CHORD := "!{Space}"

capsDownAt := 0
capsHeld   := false

; Reading a global needs no declaration in v2 -- only assigning does, which is
; why the CapsLock hotkeys below declare and this doesn't.
IsCapsHeld(*) {
    return capsHeld
}

; Hotkeys created below inherit this context and are inert unless Caps is held,
; so every one of these keys behaves completely normally on its own.
HotIf IsCapsHeld
for key in WM_KEYS
    Hotkey "*" key, ProxyToWm
for key, direction in NAV_KEYS
    Hotkey "*" key, Navigate
Hotkey "*Space", LaunchApps
HotIf

; Synthesize the private AHK -> GlazeWM channel. {Blind} keeps any real
; modifier the user is also holding, so Caps+Shift+3 arrives as f14+shift+3.
; Named keys need braces; single characters must not have them ({,} is not
; valid Send syntax).
SendToWm(key) {
    wrapped := StrLen(key) = 1 ? key : "{" key "}"
    Send "{F14 Down}{Blind}" wrapped "{F14 Up}"
}

ProxyToWm(hotkeyName) {
    SendToWm(SubStr(hotkeyName, 2))   ; strip the leading "*"
}

; No {Blind} here, unlike SendToWm. Caps held is only a flag in this script --
; nothing is physically down but CapsLock itself, which is not a modifier and is
; pinned off by SetCapsLockState. Passing real modifiers through would only turn
; an accidental Caps+Shift+Space into a chord PT Run doesn't answer to.
;
; Consuming Space here also suppresses the tap-Escape on release: the CapsLock
; up handler only emits Escape when A_PriorKey is still CapsLock, and Space
; having been pressed in between is exactly what makes it not.
;
; The daemon call first, and it matters. PT Run is a tool window GlazeWM cannot
; manage, so closing it hands foreground back to the top app window in the
; Z-order -- on the other monitor, if the workspace you launched from is empty
; -- and the app then opens over there. /launch claims the next window GlazeWM
; manages for the workspace focused right now, which has to be read BEFORE the
; launcher opens and takes the focus with it. See herdr-navd's "Launcher
; claims" section. If the daemon is down this returns "" and Caps+Space is
; exactly what it always was.
LaunchApps(*) {
    AskNavd("launch")
    Send LAUNCHER_CHORD
}

; One GET per keypress, on a connection WinHTTP keeps alive between them. The
; object is cached because creating it is the expensive part; a failed request
; drops it so the next keypress starts clean rather than inheriting a wedged
; session.
;
; Timeouts are deliberately brutal (resolve/connect/send 200ms, receive 400ms).
; This is on the path of a keystroke: a daemon that hasn't answered in that
; long is down or hung, and falling back to a plain window move beats freezing
; the keyboard while WinHTTP waits out a default 30-second timeout.
navdHttp := ""

; `path` is a route on the daemon: "nav/left", "launch". Returns the body --
; the layer that consumed a move, the workspace a launch was claimed for -- or
; "" if the daemon is unreachable or had nothing to report.
AskNavd(path) {
    global navdHttp
    try {
        if (!IsObject(navdHttp))
            navdHttp := ComObject("WinHttp.WinHttpRequest.5.1")
        navdHttp.SetTimeouts(200, 200, 200, 400)
        navdHttp.Open("GET", NAVD_URL path, false)
        navdHttp.Send()
        if (navdHttp.Status != 200)
            return ""
        body := Trim(navdHttp.ResponseText, " `t`r`n")
        ; "none" also covers the case where only the daemon's GlazeWM hop is
        ; broken -- .wslconfig still on NAT, say -- while GlazeWM itself is
        ; perfectly reachable from this side. Falling through to the f14
        ; channel makes the outermost hop work either way.
        return body = "none" ? "" : body
    } catch {
        navdHttp := ""
        return ""
    }
}

; Directional focus. Only the terminal has an inner layer worth asking, so
; everywhere else this is an ordinary window move and goes straight to the WM.
;
; Inside the terminal the move goes to herdr-navd in WSL, which walks nvim
; splits -> herdr panes -> GlazeWM and stops at the first layer that can take
; it. That arbitration has to happen on the Linux side because neither AHK nor
; GlazeWM can see inside WSL; this is the same job hypr/.../scripts/herdr-nav
; does on Omarchy, split across the boundary.
;
; If the daemon is down the move degrades to a plain window focus rather than
; doing nothing -- Caps+hjkl always moves *something*.
;
; Only a BARE Caps+hjkl is a focus move the terminal might want to consume.
; Adding Shift or Ctrl makes it a move/resize, which is always the window
; manager's job -- and must keep its modifier, so it goes through SendToWm's
; {Blind} rather than being swallowed here.
Navigate(hotkeyName) {
    key := SubStr(hotkeyName, 2)
    bare := !GetKeyState("Shift", "P")
         && !GetKeyState("Ctrl", "P")
         && !GetKeyState("Alt", "P")
    if (bare && WinActive(TERM_EXE) && AskNavd("nav/" NAV_KEYS[key]) != "")
        return
    SendToWm(key)
}

; The * prefix fires regardless of which other modifiers are already held, so
; Ctrl+Caps and friends still route through here.
*CapsLock:: {
    global capsDownAt, capsHeld
    ; Held keys auto-repeat and re-enter this hotkey; keep the first timestamp
    ; so a long hold doesn't keep looking freshly pressed.
    if (capsDownAt = 0)
        capsDownAt := A_TickCount
    capsHeld := true
}

*CapsLock up:: {
    global capsDownAt, capsHeld
    held := A_TickCount - capsDownAt
    capsDownAt := 0
    capsHeld := false

    ; A_PriorKey is still CapsLock only if nothing else was pressed in between,
    ; which is what separates a bare tap from Caps-as-a-modifier.
    if (A_PriorKey = "CapsLock") && (held < TAP_MS)
        Send "{Escape}"
}
