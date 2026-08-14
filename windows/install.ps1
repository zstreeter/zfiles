<#
.SYNOPSIS
    Windows-side setup for the zfiles WSL target.

.DESCRIPTION
    Invoked by bootstrap.sh step 15 on every run, so everything here is
    idempotent: re-running changes nothing unless a config actually differs.

    Scope is the Caps Lock remap (AutoHotkey), GlazeWM, WezTerm, and the
    .wslconfig switch to mirrored networking that lets WSL reach GlazeWM's IPC
    server on 127.0.0.1.

    Configs are COPIED onto the Windows side rather than pointed at across
    \\wsl.localhost. The logon task runs when the WSL distro is not necessarily
    up; a UNC path there would either fail outright or force the distro to boot
    just to read a script. The tradeoff is that editing the repo copy takes a
    re-run of this script (or of bootstrap.sh) to take effect.
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WindowsDir = $PSScriptRoot
$TaskName   = 'zfiles-caps'
$WmTaskName = 'zfiles-glazewm'

function Info { param([string]$Message) Write-Host "[zfiles] $Message" }

# Both the Caps Lock remap and the window manager need to run at logon with
# RunLevel Highest -- elevated so they also apply over elevated windows, and
# registered this way so neither raises a UAC prompt at logon.
function Register-ZfilesLogonTask {
    param([Parameter(Mandatory)][string]$Name,
          [Parameter(Mandatory)][string]$Execute,
          [string]$Argument = '',
          [switch]$ViaShellExecute)

    # -ViaShellExecute exists for one reason: a binary whose manifest sets
    # uiAccess="true" cannot be started by Task Scheduler. The scheduler uses
    # CreateProcessAsUser, and Windows only grants uiAccess through
    # ShellExecute (which routes via the AppInfo service); CreateProcess on
    # such a binary fails with 0x800702E4 ERROR_ELEVATION_REQUIRED no matter
    # what RunLevel the principal asks for. Start-Process defaults to
    # ShellExecute, so a one-line PowerShell shim is the whole workaround --
    # the same thing GlazeWM's own docs achieve with a Startup-folder shortcut.
    $action = if ($ViaShellExecute) {
        $inner = if ($Argument) {
            "Start-Process -FilePath '$Execute' -ArgumentList '$Argument'"
        } else {
            "Start-Process -FilePath '$Execute'"
        }
        New-ScheduledTaskAction `
            -Execute (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
            -Argument "-NoProfile -WindowStyle Hidden -Command `"$inner`""
    } elseif ($Argument) {
        New-ScheduledTaskAction -Execute $Execute -Argument $Argument
    } else {
        New-ScheduledTaskAction -Execute $Execute
    }
    $trigger   = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
    $principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
                                            -LogonType Interactive -RunLevel Highest
    # Neither a keyboard remap nor a window manager should ever be stopped for
    # running long or for battery.
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                                             -DontStopIfGoingOnBatteries `
                                             -StartWhenAvailable `
                                             -ExecutionTimeLimit ([TimeSpan]::Zero)

    Register-ScheduledTask -TaskName $Name -Action $action -Trigger $trigger `
                           -Principal $principal -Settings $settings -Force | Out-Null
    Info "task       $Name registered (at logon)"
}

# Copies only when the content differs, so a re-run is quiet and doesn't churn
# file mtimes. An unmanaged file already at the destination is backed up once,
# the same courtesy bootstrap.sh's backup_stow_conflicts() extends on the Linux
# side -- once, so repeated runs can't bury the original under .bak files.
function Copy-IfChanged {
    param([Parameter(Mandatory)][string]$Source,
          [Parameter(Mandatory)][string]$Destination)

    $dir = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    if (Test-Path -LiteralPath $Destination) {
        if ((Get-FileHash -LiteralPath $Source).Hash -eq
            (Get-FileHash -LiteralPath $Destination).Hash) {
            Info "unchanged  $Destination"
            return $false
        }
        $backup = "$Destination.zfiles-bak"
        if (-not (Test-Path -LiteralPath $backup)) {
            Copy-Item -LiteralPath $Destination -Destination $backup -Force
            Info "backed up  $backup"
        }
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force
    Info "installed  $Destination"
    return $true
}

# --- Taskbar -----------------------------------------------------------------
# Zebar (GlazeWM's status bar, started from its startup_commands) is the top
# bar; auto-hiding the Windows taskbar leaves it as the only one, which is the
# Omarchy look. Auto-hide rather than removal -- the tray still matters, and
# pushing the cursor to the bottom edge brings it back.
#
# THIS SECTION MUST STAY AHEAD OF EVERY SECTION THAT STARTS A PROCESS. It
# restarts explorer, and explorer going down takes collateral with it:
# AutoHotkey's low-level keyboard hook stops being called (the script keeps
# running and logs nothing, so it looks fine while Caps does nothing), and
# Zebar's window is destroyed while the process survives -- the bar flashes up
# and vanishes. Both were observed on a real run with this block at the end,
# and both cost an afternoon to attribute because neither process dies or logs.
# Ordered first, the restart lands before anything is running to break.
#
# Bit 0 of byte 8 of StuckRects3\Settings is the auto-hide flag. Explorer reads
# this blob once at startup and rewrites it at shutdown, so the change needs an
# explorer restart to show up -- and has to be written while explorer is down,
# or its own copy overwrites ours on the way out.
$stuckRects = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
$settings = (Get-ItemProperty -LiteralPath $stuckRects -ErrorAction SilentlyContinue).Settings

if (-not $settings) {
    Write-Warning '[zfiles] StuckRects3\Settings not found - taskbar left as is.'
} elseif ($settings[8] -band 0x01) {
    Info 'taskbar    already auto-hiding'
} else {
    $settings[8] = $settings[8] -bor 0x01
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    Set-ItemProperty -LiteralPath $stuckRects -Name Settings -Value $settings
    # Explorer normally respawns on its own; start it if this shell's session
    # is one where it doesn't.
    Start-Sleep -Seconds 2
    if (-not (Get-Process -Name 'explorer' -ErrorAction SilentlyContinue)) {
        Start-Process 'explorer.exe'
    }
    Info 'taskbar    set to auto-hide'
}

# --- Desktop icons -----------------------------------------------------------
# The other half of the clean-background look: no shortcuts on the desktop.
# Hidden as a VIEW setting, not by deleting anything. Every icon on this machine
# comes from C:\Users\Public\Desktop -- installer- and IT-placed shortcuts
# (Okta Verify, Self-Host Agent). Deleting those needs admin, hits every user of
# the box, and quietly removing IT's items on a managed work laptop is not this
# script's call. The user's own Desktop is already empty.
#
# Reverts with a right-click on the desktop -> View -> Show desktop icons.
#
# HideIcons alone only takes effect when explorer next starts, and restarting
# explorer is exactly what this file must not do casually (see the Taskbar
# section). So the registry write is paired with the shell's own toggle
# command, 0x7402, which applies it to the running explorer for free.
if (-not ('ZfilesDesktop' -as [type])) {
    Add-Type -Namespace '' -Name 'ZfilesDesktop' -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr FindWindow(string c, string w);
[DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr c, string cls, string w);
[DllImport("user32.dll")] public static extern IntPtr SendMessageTimeout(
    IntPtr h, uint msg, IntPtr wp, IntPtr lp, uint flags, uint timeout, out IntPtr res);
'@
}

$advanced = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
Set-ItemProperty -LiteralPath $advanced -Name HideIcons -Value 1 -Type DWord

# 0x7402 is a toggle, so it must only be sent when the icons are actually
# showing -- otherwise a second run of this script turns them back on. The live
# truth is whether the icon list exists: hiding destroys the SysListView32,
# leaving its SHELLDLL_DefView host behind.
$progman = [ZfilesDesktop]::FindWindow('Progman', 'Program Manager')
$defView = if ($progman -ne [IntPtr]::Zero) {
    [ZfilesDesktop]::FindWindowEx($progman, [IntPtr]::Zero, 'SHELLDLL_DefView', $null)
} else { [IntPtr]::Zero }
$iconList = if ($defView -ne [IntPtr]::Zero) {
    [ZfilesDesktop]::FindWindowEx($defView, [IntPtr]::Zero, 'SysListView32', $null)
} else { [IntPtr]::Zero }

if ($progman -eq [IntPtr]::Zero) {
    Write-Warning '[zfiles] Progman not found - desktop icons left as is.'
} elseif ($iconList -eq [IntPtr]::Zero) {
    Info 'desktop    icons already hidden'
} else {
    # SendMessageTimeout rather than SendMessage: a wedged explorer must not
    # take the whole bootstrap down with it.
    $unused = [IntPtr]::Zero
    [void][ZfilesDesktop]::SendMessageTimeout(
        $progman, 0x111, [IntPtr]0x7402, [IntPtr]::Zero, 2, 3000, [ref]$unused)
    Info 'desktop    icons hidden'
}

# --- Caps Lock scancode remap ------------------------------------------------
# Turn the Caps Lock key into F13 in the keyboard driver, so Windows has no
# Caps Lock key at all and the lock state can never latch.
#
# caps.ahk used to be the only thing holding it off, via SetCapsLockState
# "AlwaysOff" plus its hook. That leaves a hole exactly the width of the
# process not running -- during logon before the task fires, and during every
# restart after an edit to the script -- and one press in that window latches
# the lock for real. The hole cannot be closed from userspace; it is closed
# here instead, one layer down, where it holds whether or not AutoHotkey is up.
#
# F13 and not F14: GlazeWM installs its own low-level keyboard hook, and hook
# order between two logon-started processes is not pinnable, so a physical F14
# could reach GlazeWM before caps.ahk suppressed it and fire every binding
# twice. Nothing is bound to f13, so the physical key is inert to the WM.
#
# Scancode Map layout (REG_BINARY, all little-endian DWORDs): version 0, flags
# 0, count 2 (one mapping plus the null terminator), then each mapping as
# (source << 16) | target, then a zero DWORD closing the list.
#
# THE SOURCE IS THE HIGH WORD -- it reads backwards from the arrow you say out
# loud, and getting it round the wrong way is silent. kbdclass accepts the
# value either way and simply maps a key nothing on the keyboard emits, leaving
# the real one alone. This shipped reversed once (0x0064003A, F13 -> Caps Lock)
# and the only symptom was Caps Lock going on latching, which looks exactly
# like the map not having been applied at all. What settled it was an
# AutoHotkey InputHook still logging sc=0x3A after a reboot with the value in
# place. Microsoft's own worked example is the thing to check a new mapping
# against: 0x003A001D is documented as "CAPS LOCK -> Left CTRL (0x3A -> 0x1D)".
#
# Little-endian, so the DWORD 0x003A0064 lands on disk as the bytes
# 64 00 3A 00 -- target first. `reg query` prints them in that order too.
$kbLayoutKey = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout'
$capsToF13 = [byte[]]@(
    0x00,0x00,0x00,0x00,   # version
    0x00,0x00,0x00,0x00,   # flags
    0x02,0x00,0x00,0x00,   # entry count, terminator included
    0x64,0x00,0x3A,0x00,   # 0x003A0064: 0x3A Caps Lock -> 0x64 F13
    0x00,0x00,0x00,0x00    # terminator
)

# The reversed value this script wrote before the fix above. Recognised by name
# so the "someone else's map" warning below does not fire on our own old
# mistake and stash it in a .zfiles-bak value as though it were a deliberate
# remap worth restoring by hand.
$capsToF13Reversed = [byte[]]@(
    0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,
    0x02,0x00,0x00,0x00,
    0x3A,0x00,0x64,0x00,   # 0x0064003A: F13 -> Caps Lock, which is not the job
    0x00,0x00,0x00,0x00
)

# GetValue, not Get-ItemProperty: under Set-StrictMode -Version Latest, reading
# a property off an object that lacks it is a terminating error, and an
# unmapped keyboard is exactly the case where the value is absent. The registry
# key object answers with $null instead.
$currentMap = (Get-Item -LiteralPath $kbLayoutKey).GetValue('Scancode Map')

if ($currentMap -and -not (Compare-Object $currentMap $capsToF13 -SyncWindow 0)) {
    Info 'scancode   Caps Lock -> F13 already mapped'
} else {
    if ($currentMap -and -not (Compare-Object $currentMap $capsToF13Reversed -SyncWindow 0)) {
        Info 'scancode   replacing the old reversed map (was F13 -> Caps Lock)'
    } elseif ($currentMap) {
        # Preserve a map we did not write rather than dropping remaps someone
        # set up deliberately. Merging two of them is not something to guess
        # at, so the old bytes are kept beside ours to be restored by hand.
        Write-Warning @'
[zfiles] A 'Scancode Map' already exists and is not ours. Replacing it, with
  the old bytes saved to the 'Scancode Map.zfiles-bak' value beside it. Any
  other remaps it set up are off until you merge them back by hand.
'@
    }

    # HKLM needs elevation and bootstrap.sh does not run this script elevated,
    # so shell out through RunAs. One UAC prompt, on the run that changes
    # something -- the no-op branch above is what every later run takes.
    $writeMap = @"
`$key = '$kbLayoutKey'
`$old = (Get-Item -LiteralPath `$key).GetValue('Scancode Map')
`$reversed = [byte[]]@($($capsToF13Reversed -join ','))
if (`$old -and (Compare-Object `$old `$reversed -SyncWindow 0)) {
    Set-ItemProperty -LiteralPath `$key -Name 'Scancode Map.zfiles-bak' -Value `$old -Type Binary
}
Set-ItemProperty -LiteralPath `$key -Name 'Scancode Map' ``
                 -Value ([byte[]]@($($capsToF13 -join ','))) -Type Binary
"@

    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($writeMap))
    $elevated = Start-Process `
        -FilePath (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
        -ArgumentList '-NoProfile', '-EncodedCommand', $encoded `
        -Verb RunAs -Wait -PassThru -WindowStyle Hidden

    if ($elevated.ExitCode -ne 0) {
        Write-Warning @'
[zfiles] Could not write the Caps Lock scancode map -- UAC declined, most
  likely. Caps Lock stays a real toggle key and caps.ahk's SetCapsLockState
  fallback is all that holds it off. Re-run bootstrap.sh and accept the
  prompt.
'@
    } else {
        Info 'scancode   Caps Lock -> F13 written'
        Write-Warning '[zfiles] Reboot for the Caps Lock scancode map to take effect.'
    }
}

# --- Caps Lock: tap = Escape, hold = Super -----------------------------------
# AutoHotkey rather than kanata: kanata's only winget source is its GitHub
# release, and Zscaler 403s that download on the AMD network. See the header of
# windows/autohotkey/caps.ahk for why that block looks deliberate.
function Get-AutoHotkeyExe {
    $cmd = Get-Command 'AutoHotkey64.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    $wellKnown = Join-Path $env:ProgramFiles 'AutoHotkey\v2\AutoHotkey64.exe'
    if (Test-Path -LiteralPath $wellKnown) { return $wellKnown }

    return $null
}

$ahkExe = Get-AutoHotkeyExe
if (-not $ahkExe) {
    Info 'AutoHotkey not installed - fetching AutoHotkey.AutoHotkey via winget'
    # Non-terminating on purpose: a failed install should cost the Caps Lock
    # remap, not the rest of the Windows-side setup.
    try {
        winget install --id AutoHotkey.AutoHotkey --exact --silent `
                       --accept-package-agreements --accept-source-agreements
    } catch {
        Write-Warning "[zfiles] winget install failed: $_"
    }
    $ahkExe = Get-AutoHotkeyExe
}

if (-not $ahkExe) {
    Write-Warning @'
[zfiles] AutoHotkey unavailable - Caps Lock will not be remapped. Install
  AutoHotkey v2 by hand and re-run bootstrap.sh; this script is idempotent.
'@
} else {
    Info "autohotkey $ahkExe"

    $capsScript = Join-Path $env:USERPROFILE '.config\zfiles\caps.ahk'
    $scriptChanged = Copy-IfChanged (Join-Path $WindowsDir 'autohotkey\caps.ahk') $capsScript

    # Validate before restarting: a broken script that takes down the running
    # instance leaves the keyboard unremapped with no obvious reason why.
    #
    # /ErrorStdOut is load-bearing, not tidiness. Without it a syntax error
    # opens a modal dialog and -Wait blocks on it forever, hanging bootstrap on
    # a window the user may not even be looking at.
    $errFile = Join-Path $env:TEMP 'zfiles-ahk-validate.txt'
    $check = Start-Process -FilePath $ahkExe `
                           -ArgumentList '/ErrorStdOut', '/validate', "`"$capsScript`"" `
                           -Wait -PassThru -WindowStyle Hidden `
                           -RedirectStandardError $errFile
    if ($check.ExitCode -ne 0) {
        $detail = (Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue)
        Remove-Item -LiteralPath $errFile -ErrorAction SilentlyContinue
        throw "AutoHotkey rejected ${capsScript}:`n$detail"
    }
    Remove-Item -LiteralPath $errFile -ErrorAction SilentlyContinue
    Info 'script     valid'

    Register-ZfilesLogonTask -Name $TaskName -Execute $ahkExe -Argument "`"$capsScript`""

    # Match on the command line, not the process name: other AutoHotkey scripts
    # may legitimately be running and are none of our business.
    $running = @(Get-CimInstance Win32_Process -Filter "Name='AutoHotkey64.exe'" `
                    -ErrorAction SilentlyContinue |
                 Where-Object { $_.CommandLine -like '*caps.ahk*' })

    # AutoHotkey reads the script once at startup, so a change needs a restart.
    # Start it when nothing is running either -- first install, or after a crash.
    if ($scriptChanged -or $running.Count -eq 0) {
        if ($running.Count -gt 0) {
            $running | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
            Info 'caps.ahk   stopped (script changed)'
        }
        Start-ScheduledTask -TaskName $TaskName
        Info 'caps.ahk   started'
    } else {
        Info 'caps.ahk   already running with current script'
    }
}

# Superseded by zfiles-caps; drop it so an old install doesn't leave a task
# pointing at a kanata binary that was never obtainable here.
if (Get-ScheduledTask -TaskName 'zfiles-kanata' -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName 'zfiles-kanata' -Confirm:$false
    Info 'task       removed stale zfiles-kanata'
}

# --- Zebar -------------------------------------------------------------------
# The top bar, and the closest thing to Omarchy's waybar. Zebar ships with
# GlazeWM and is launched from its `startup_commands`, so this has to be on
# disk BEFORE the GlazeWM section below starts the WM.
#
# Zebar renders "packs" -- a zpack.json manifest plus the widget's own
# HTML/CSS. windows/zebar/ is a copy of the bundled `starter` pack with two
# changes that the bundled one cannot carry, because it lives under
# Program Files and is replaced on every Zebar upgrade:
#   zOrder: top_most   so the bar isn't painted over by a tiled window
#   dockToEdge         so Windows shrinks the workarea to match and GlazeWM
#                      tiles beneath the bar instead of behind it
#
# settings.json is what actually selects the pack at startup. It must be
# BOM-free: Zebar's parser rejects a leading BOM with the un-obvious
# "expected value at line 1 column 1". Authoring it in the repo and byte-copying
# it with Copy-IfChanged keeps it that way -- do NOT rewrite it with
# Set-Content -Encoding UTF8, which is BOM-emitting on PowerShell 5.1.
$zebarRoot = Join-Path $env:USERPROFILE '.glzr\zebar'
$zebarPack = Join-Path $zebarRoot 'zfiles'
$zebarSrc  = Join-Path $WindowsDir 'zebar'

foreach ($file in 'zpack.json', 'with-glazewm.html', 'styles.css') {
    Copy-IfChanged -Source (Join-Path $zebarSrc $file) `
                   -Destination (Join-Path $zebarPack $file) | Out-Null
}
Copy-IfChanged -Source (Join-Path $zebarSrc 'settings.json') `
               -Destination (Join-Path $zebarRoot 'settings.json') | Out-Null

# --- GlazeWM -----------------------------------------------------------------
# The Hyprland stand-in. Bindings live in windows/glazewm/config.yaml, all on
# the synthetic `f14` channel that windows/autohotkey/caps.ahk emits when Caps
# Lock is held -- see that file's header for why the modifier is a function key
# rather than Super.
#
# GlazeWM rather than komorebi, which is the better window manager but is
# licensed for personal use only ("without any anticipated commercial
# application"); this is a work machine. Whim and workspacer are too small a
# bet. GlazeWM is GPL-3.0 and its keybinding matcher tests whether ANY held key
# is down rather than requiring a real modifier, which is exactly what makes
# the f14 channel possible.
function Get-GlazeWmExe {
    $cmd = Get-Command 'glazewm.exe' -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:LOCALAPPDATA)) {
        if (-not $root) { continue }
        $candidate = Join-Path $root 'glzr.io\GlazeWM\glazewm.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

$wmExe = Get-GlazeWmExe
if (-not $wmExe) {
    Info 'GlazeWM not installed - fetching glzr-io.glazewm via winget'
    # Non-terminating for the same reason as AutoHotkey above: a failed install
    # should cost the window manager, not the rest of the Windows-side setup.
    try {
        winget install --id glzr-io.glazewm --exact --silent `
                       --accept-package-agreements --accept-source-agreements
    } catch {
        Write-Warning "[zfiles] winget install failed: $_"
    }
    # winget updates the machine PATH but not this already-running process, so
    # re-probe the well-known locations rather than trusting Get-Command.
    $wmExe = Get-GlazeWmExe
}

if (-not $wmExe) {
    Write-Warning @'
[zfiles] GlazeWM unavailable - no tiling window manager will run. Install
  glzr-io.glazewm by hand and re-run bootstrap.sh; this script is idempotent.
'@
} else {
    Info "glazewm    $wmExe"

    # GlazeWM reads %USERPROFILE%\.glzr\glazewm\config.yaml by default.
    $wmConfig = Join-Path $env:USERPROFILE '.glzr\glazewm\config.yaml'
    $wmChanged = Copy-IfChanged (Join-Path $WindowsDir 'glazewm\config.yaml') $wmConfig

    # `start` is not optional: glazewm.exe is a subcommand CLI (start/query/
    # command/sub), and invoked bare it prints usage and exits 2.
    Register-ZfilesLogonTask -Name $WmTaskName -Execute $wmExe -Argument 'start' `
                             -ViaShellExecute

    $wmRunning = @(Get-Process -Name 'glazewm' -ErrorAction SilentlyContinue)

    if ($wmChanged -and $wmRunning.Count -gt 0) {
        # Cheaper and far less disruptive than a restart: GlazeWM re-reads the
        # config in place and keeps every window where it is.
        try {
            & $wmExe command wm-reload-config | Out-Null
            Info 'glazewm    config reloaded'
        } catch {
            Write-Warning "[zfiles] wm-reload-config failed: $_"
        }
    } elseif ($wmRunning.Count -eq 0) {
        Start-ScheduledTask -TaskName $WmTaskName
        Info 'glazewm    started'
    } else {
        Info 'glazewm    already running with current config'
    }
}

# --- PowerToys Run -----------------------------------------------------------
# The app launcher, standing in for Omarchy's walker on SUPER+SPACE. GlazeWM
# has no launcher and cannot host one: it has no "send a keystroke" command,
# and PT Run answers to a hotkey rather than to being exec'd, so shell-exec has
# nothing to call. windows/autohotkey/caps.ahk therefore translates Caps+Space
# into PT Run's own default Alt+Space; see LAUNCHER_CHORD there.
#
# PowerToys and not Flow Launcher or Keypirinha: this is a managed work laptop,
# and a Microsoft-signed, MIT-licensed package is the one least likely to argue
# with either endpoint security or the software policy.
#
# PT Run's activation chord is left at its default rather than configured here.
# It lives in a settings JSON that PowerToys rewrites wholesale on exit, so
# editing it from a script races the running process and loses.
# Probe all three scopes rather than assuming Program Files: winget picks the
# per-user installer for this package unless told otherwise, which lands it in
# %LOCALAPPDATA%\PowerToys. Checking only the machine-wide path reports a
# successful install as a failure.
function Get-PowerToysExe {
    foreach ($root in @($env:LOCALAPPDATA, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if (-not $root) { continue }
        $candidate = Join-Path $root 'PowerToys\PowerToys.exe'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $null
}

$ptExe = Get-PowerToysExe
if (-not $ptExe) {
    Info 'PowerToys not installed - fetching Microsoft.PowerToys via winget'
    try {
        winget install --id Microsoft.PowerToys --exact --silent `
                       --accept-package-agreements --accept-source-agreements
    } catch {
        Write-Warning "[zfiles] winget install failed: $_"
    }
    $ptExe = Get-PowerToysExe
}

if (-not $ptExe) {
    Write-Warning '[zfiles] PowerToys unavailable - Caps+Space will do nothing.'
} else {
    Info "powertoys  $ptExe"

    # PT Run indexes the Desktop as a program source by default. zfiles empties
    # the desktop on purpose (see the Desktop icons section), so that source can
    # only ever contribute stale entries: the plugin caches the .lnk path it saw
    # at index time, and launching one after the file is gone fails with
    #   Unable to start: C:\Users\Public\Desktop\WezTerm.lnk
    # Every app worth launching has a Start Menu entry pointing at the real
    # .exe, and the Start Menu / registry / PATH sources stay enabled, so this
    # loses nothing. The cost is that a shortcut deliberately placed on the
    # desktop later won't be indexed -- which is the intended trade here.
    #
    # PowerToys rewrites this JSON wholesale on exit, so patching it underneath
    # a running process loses the change. Stop it first and let the start block
    # below bring it back.
    $ptProgramSettings = Join-Path $env:LOCALAPPDATA (Join-Path 'Microsoft\PowerToys\PowerToys Run\Settings\Plugins' `
        'Microsoft.Plugin.Program\ProgramPluginSettings.json')

    if (-not (Test-Path -LiteralPath $ptProgramSettings)) {
        # Written on PT Run's first run; nothing to patch before that.
        Info 'powertoys  PT Run not configured yet - desktop source left alone'
    } elseif ((Get-Content -LiteralPath $ptProgramSettings -Raw) -match '"EnableDesktopSource"\s*:\s*true') {
        Get-Process -Name 'PowerToys*' -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 3

        $raw = (Get-Content -LiteralPath $ptProgramSettings -Raw) `
            -replace '"EnableDesktopSource"\s*:\s*true', '"EnableDesktopSource": false'
        # Age the index timestamp too, or the plugin trusts a cache that still
        # holds the deleted desktop shortcuts.
        $raw = $raw -replace '"LastIndexTime"\s*:\s*"[^"]*"',
                             '"LastIndexTime": "2000-01-01T00:00:00-05:00"'

        # WriteAllText with an explicit BOM-less encoding, not Set-Content
        # -Encoding UTF8, which emits a BOM on PowerShell 5.1. Same trap as
        # Zebar's settings.json above.
        [System.IO.File]::WriteAllText(
            $ptProgramSettings, $raw, (New-Object System.Text.UTF8Encoding $false))
        Info 'powertoys  PT Run desktop program source disabled'
    } else {
        Info 'powertoys  PT Run desktop source already off'
    }

    # Keyboard Manager must not remap Caps Lock. caps.ahk owns that key: it holds
    # it as the F14 modifier and emits Escape only on a short tap. A KBM
    # Caps->Escape entry does the tap half a second time, and the two fight over
    # the low-level hook chain -- which Windows calls most-recently-installed
    # first. Whoever started last wins, so the chord works or doesn't depending on
    # process start order, and PowerToys restarting (an update, a settings change,
    # this script's own patch above) silently flips it. Observed 2026-08-13:
    # restarting PowerToys put KBM ahead of AutoHotkey, KBM swallowed Caps Lock
    # and injected Escape, and Caps+2 stopped switching workspaces with every
    # process still running and nothing logged anywhere.
    $kbmSettings = Join-Path $env:LOCALAPPDATA 'Microsoft\PowerToys\Keyboard Manager\default.json'
    # 20 = VK_CAPITAL, 27 = VK_ESCAPE. Match any target, not just Escape: any
    # remap of Caps Lock breaks the modifier, whatever it maps to.
    $capsRemap = '\{"originalKeys":"20","newRemapKeys":"[^"]*"\}'

    if (-not (Test-Path -LiteralPath $kbmSettings)) {
        Info 'powertoys  Keyboard Manager not configured - nothing to clear'
    } elseif ((Get-Content -LiteralPath $kbmSettings -Raw) -match $capsRemap) {
        Get-Process -Name 'PowerToys*' -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 3

        # Drop just the Caps entry and tidy any comma it leaves behind, so other
        # remaps the user set up deliberately survive.
        $raw = (Get-Content -LiteralPath $kbmSettings -Raw) -replace $capsRemap, ''
        $raw = $raw -replace ',\s*,', ',' -replace '\[\s*,', '[' -replace ',\s*\]', ']'
        [System.IO.File]::WriteAllText(
            $kbmSettings, $raw, (New-Object System.Text.UTF8Encoding $false))
        Info 'powertoys  Keyboard Manager Caps Lock remap removed'
    } else {
        Info 'powertoys  Keyboard Manager leaves Caps Lock alone'
    }

    # PowerToys runs its modules from a single tray process; PowerToys.exe being
    # up is what makes PT Run answer its hotkey.
    if (-not (Get-Process -Name 'PowerToys' -ErrorAction SilentlyContinue)) {
        # ShellExecute for the same uiAccess reason as GlazeWM above.
        Start-Process $ptExe
        Info 'powertoys  started'
    } else {
        Info 'powertoys  already running'
    }
}

# --- WSL mirrored networking -------------------------------------------------
# herdr-navd (Linux side) hands off to GlazeWM by talking to its IPC server, a
# WebSocket on ws://127.0.0.1:6123 (wm-common/src/ipc.rs). In WSL2's default
# NAT mode `localhost` inside the distro is NOT the Windows host -- reaching it
# means chasing a gateway address that changes on every restart, through the
# firewall. Mirrored mode makes 127.0.0.1 mean the same thing on both sides.
#
# The alternative -- shelling out to glazewm.exe through WSL interop -- was
# measured at ~290ms per invocation, which is unusable for focus movement.
#
# Requires Windows 11 22H2+ and WSL 2.0+; both hold on this machine.
$wslConfig = Join-Path $env:USERPROFILE '.wslconfig'

if (-not (Test-Path -LiteralPath $wslConfig)) {
    @('[wsl2]', 'networkingMode=mirrored') |
        Set-Content -LiteralPath $wslConfig -Encoding ASCII
    Info "installed  $wslConfig (networkingMode=mirrored)"
    Write-Warning '[zfiles] Run `wsl --shutdown` for mirrored networking to take effect.'
} else {
    $lines = @(Get-Content -LiteralPath $wslConfig)

    if ($lines -match '^\s*networkingMode\s*=') {
        # Never silently rewrite an explicit choice -- if it is set to
        # something else, that was deliberate and herdr-navd is what breaks,
        # so say so rather than fixing it behind the user's back.
        if ($lines -match '^\s*networkingMode\s*=\s*mirrored\s*$') {
            Info 'unchanged  .wslconfig (networkingMode=mirrored)'
        } else {
            Write-Warning @"
[zfiles] $wslConfig sets networkingMode to something other than 'mirrored'.
  Leaving it alone. herdr-navd cannot reach GlazeWM's IPC server on
  127.0.0.1:6123 until this is 'mirrored'.
"@
        }
    } else {
        Copy-Item -LiteralPath $wslConfig -Destination "$wslConfig.zfiles-bak" -Force
        Info "backed up  $wslConfig.zfiles-bak"

        if ($lines -match '^\s*\[wsl2\]\s*$') {
            # Insert directly under the existing [wsl2] header; appending to
            # the end of the file could land the key under a later section.
            $out = foreach ($line in $lines) {
                $line
                if ($line -match '^\s*\[wsl2\]\s*$') { 'networkingMode=mirrored' }
            }
        } else {
            $out = $lines + @('[wsl2]', 'networkingMode=mirrored')
        }

        $out | Set-Content -LiteralPath $wslConfig -Encoding ASCII
        Info "updated    $wslConfig (networkingMode=mirrored)"
        Write-Warning '[zfiles] Run `wsl --shutdown` for mirrored networking to take effect.'
    }
}

# --- WezTerm -----------------------------------------------------------------
# No restart needed: WezTerm watches its config file and reloads in place.
Copy-IfChanged (Join-Path $WindowsDir 'wezterm\wezterm.lua') `
               (Join-Path $env:USERPROFILE '.wezterm.lua') | Out-Null

# --- sioyek ------------------------------------------------------------------
# The PDF reader, installed on the Windows side rather than inside WSL. That is
# the general rule for anything with a window on this target -- see
# wsl/.local/bin/winapp, which is what routes `sioyek foo.pdf` in a WSL shell
# to the exe installed here. Measured reason, on GlazeWM 3.10.1: a Linux GUI
# app reaches Windows through WSLg's RDP RemoteApp channel, so it arrives as a
# RAIL_WINDOW owned by msrdc.exe -- indistinguishable from every other WSLg
# app, opened fullscreen regardless of `initial_state: tiling`, and immune to
# both `glazewm command close` and a direct WM_CLOSE. The Windows build is an
# ordinary Win32 window that tiles and closes.
#
# ahrm.sioyek ships as a PORTABLE zip, which decides where the config lives:
# sioyek prints its own paths on startup and they are all inside the extracted
# directory, not %APPDATA%. Emptying or deleting the shipped prefs_user.config
# does not move them -- it was tried. So the configs go next to the exe, and
# the exe lives under a version-stamped winget Packages\ path, which means a
# sioyek upgrade lands in a fresh directory with empty configs. Re-running
# bootstrap.sh puts them back; nothing here can prevent the gap.
function Get-SioyekDir {
    $root = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
    if (-not (Test-Path -LiteralPath $root)) { return $null }

    $exe = Get-ChildItem -LiteralPath $root -Directory -Filter 'ahrm.sioyek*' `
                         -ErrorAction SilentlyContinue |
           ForEach-Object {
               Get-ChildItem -LiteralPath $_.FullName -Recurse -Filter 'sioyek.exe' `
                             -ErrorAction SilentlyContinue
           } | Select-Object -First 1

    if ($exe) { return $exe.DirectoryName }
    return $null
}

$sioyekDir = Get-SioyekDir
if (-not $sioyekDir) {
    Info 'sioyek not installed - fetching ahrm.sioyek via winget'
    # Non-terminating, as with AutoHotkey and GlazeWM above: a PDF reader that
    # failed to install should not take the rest of the Windows setup with it.
    try {
        winget install --id ahrm.sioyek --exact --silent `
                       --accept-package-agreements --accept-source-agreements
    } catch {
        Write-Warning "[zfiles] winget install failed: $_"
    }
    $sioyekDir = Get-SioyekDir
}

if (-not $sioyekDir) {
    Write-Warning @'
[zfiles] sioyek unavailable - PDFs opened from WSL will have nowhere to land.
  Install ahrm.sioyek by hand and re-run bootstrap.sh; this script is idempotent.
'@
} else {
    Info "sioyek     $sioyekDir"

    # The keymap is not duplicated into windows/: it is identical on both
    # targets, so the Linux package's copy is the single source. The prefs are
    # NOT shared -- on Omarchy that file is a symlink the theme engine rewrites
    # on every theme switch, which is meaningless here.
    $repoDir = Split-Path -Parent $WindowsDir
    Copy-IfChanged (Join-Path $repoDir 'sioyek\.config\sioyek\keys_user.config') `
                   (Join-Path $sioyekDir 'keys_user.config') | Out-Null
    Copy-IfChanged (Join-Path $WindowsDir 'sioyek\prefs_user.config') `
                   (Join-Path $sioyekDir 'prefs_user.config') | Out-Null
}

Info 'done'
