# SPDX-License-Identifier: GPL-3.0-only
param([Parameter(Mandatory, Position=0)][string]$File)
$ErrorActionPreference = 'Stop'
$request = $null
try {
    $item = Get-Item -LiteralPath $File
    if ($item.PSIsContainer -or $item.Extension -ine '.ccAvatar' -or $item.FullName -notmatch '^[A-Za-z]:\\') {
        throw 'Choose a .ccAvatar file on a local drive.'
    }
    $exe = Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'CharacterCreator.exe'
    $folder = Join-Path $env:LOCALAPPDATA 'CC5 Startup Patch'
    [IO.Directory]::CreateDirectory($folder) | Out-Null
    $session = [Diagnostics.Process]::GetCurrentProcess().SessionId
    $running = Get-Process -Name CharacterCreator -ErrorAction SilentlyContinue | Where-Object SessionId -eq $session
    $cold = !$running
    if (!$running) {
        $running = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -PassThru
    }
    if (@($running).Count -ne 1) { throw 'Multiple CC5 instances are open. Select a single instance first.' }
    # The splash screen accepts messages before the host can load a character.
    $deadline = [DateTime]::UtcNow.AddMinutes(3)
    $ready = 0
    while ($ready -lt 5) {
        $running.Refresh()
        if ($running.HasExited) { throw 'CC5 exited before opening its project window.' }
        if ([DateTime]::UtcNow -gt $deadline) { throw 'CC5 did not reach a responsive project window within three minutes.' }
        if ($running.MainWindowTitle -match '\.(ccProject|ccAvatar)\b' -and $running.Responding) { $ready++ } else { $ready = 0 }
        Start-Sleep -Seconds 1
    }
    $stem = Join-Path $folder ([guid]::NewGuid().ToString('N'))
    [IO.File]::WriteAllText("$stem.tmp",$item.FullName)
    $request = if ($cold -and $running.MainWindowTitle -eq 'Character Creator 5 - Default.ccProject') {
        "$stem.fresh.avatar"
    } else { "$stem.avatar" }
    [IO.File]::Move("$stem.tmp",$request)
} catch {
    if ($request -and [IO.File]::Exists($request)) { [IO.File]::Delete($request) }
    Add-Type -AssemblyName PresentationFramework
    [Windows.MessageBox]::Show($_.Exception.Message,'CC5 could not open the avatar') | Out-Null
    exit 1
}
