# SPDX-License-Identifier: GPL-3.0-only
[CmdletBinding()]
param([ValidateSet('Check','Install','Uninstall')][string]$Action = 'Check')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$product = 'SOFTWARE\Reallusion\Character Creator\5.0'
$avatarClass = 'Charactor Creator.ccAvatar' # Spelling used by the vendor.
$commandKey = "SOFTWARE\Classes\$avatarClass\shell\open\command"
$receiptKey = 'SOFTWARE\CC5 Native Open\5.20.2310.1'
$fields = @('Main Program','Check Update Edition','EM2','Version Code','Product Build')
$expectedHash = '0E5A23BDB0ABF04EFCC14218A272E3659E16E09C64702B531AF8546A23DEC3DF'
$bin = Join-Path ([Environment]::GetEnvironmentVariable('ProgramW6432')) 'Reallusion\Character Creator 5\Bin64'
$plugin = Join-Path $bin 'OpenPlugin\CC5AvatarOpen'
$pluginFiles = @('main.py','Open-Avatar.ps1')

function Read-String($root, $path, $name) {
    $key = $root.OpenSubKey($path)
    if (!$key) { return }
    try {
        if ($key.GetValueNames() -notcontains $name) { return }
        if ($key.GetValueKind($name) -ne 'String') { throw "Unexpected registry type at $path ($name)." }
        return $key.GetValue($name)
    } finally { $key.Dispose() }
}

function Get-Fingerprint([string]$value) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($value))) }
    finally { $sha.Dispose() }
}

function Get-Parents([string]$path) {
    while ($path) {
        $path
        if (!$path.Contains('\')) { break }
        $path = $path.Substring(0,$path.LastIndexOf('\'))
    }
}

function Update-Registration($root, $entries, $mode) {
    $receipt = $root.OpenSubKey($receiptKey, ($mode -ne 'Check'))
    try {
        # Check every destination before making a change.
        foreach ($entry in $entries) {
            $current = Read-String $root $entry.Path $entry.Name
            $tracked = @()
            if ($receipt) { $tracked = @($receipt.GetValue($entry.Id),$receipt.GetValue("Previous:$($entry.Id)")) }
            if ($mode -eq 'Uninstall') {
                if (!$receipt -or $receipt.GetValueNames() -notcontains $entry.Id) { continue }
                if ($null -ne $current -and (Get-Fingerprint $current) -cnotin $tracked) {
                    throw "Another installer or user changed $($entry.Id). It has been preserved."
                }
            } elseif ($null -ne $current -and $current -cne $entry.Value -and
                ((Get-Fingerprint $current) -cnotin $tracked)) {
                throw "Existing $($entry.Id) differs. It has been preserved."
            }
            if ($mode -eq 'Check') {
                $state = if ($null -eq $current) { 'missing' } else { 'present' }
                Write-Output "$($entry.Id): $state"
            }
        }
        if ($mode -eq 'Check') { return }
        if ($mode -eq 'Uninstall' -and !$receipt) { return }
        foreach ($entry in $entries) {
            $current = Read-String $root $entry.Path $entry.Name
            if ($mode -eq 'Install' -and $current -cne $entry.Value) {
                if (!$receipt) { $receipt = $root.CreateSubKey($receiptKey) }
                # Journal first. A second install can finish an interrupted operation.
                foreach ($path in (Get-Parents $entry.Path)) {
                    $existing = $root.OpenSubKey($path)
                    if ($existing) { $existing.Dispose(); break }
                    $receipt.SetValue("Key:$path",'created')
                }
                # A previous patch release may own an older Open command.
                if ($null -ne $current) {
                    $receipt.SetValue("Previous:$($entry.Id)", (Get-Fingerprint $current))
                }
                $receipt.SetValue($entry.Id, (Get-Fingerprint $entry.Value))
                $receipt.Flush()
                $key = $root.CreateSubKey($entry.Path)
                try { $key.SetValue($entry.Name,$entry.Value,'String') } finally { $key.Dispose() }
                if ((Read-String $root $entry.Path $entry.Name) -cne $entry.Value) { throw "Readback failed for $($entry.Id)." }
                $receipt.DeleteValue("Previous:$($entry.Id)",$false)
                Write-Output "Installed $($entry.Id)."
            } elseif ($mode -eq 'Uninstall' -and $receipt.GetValueNames() -contains $entry.Id) {
                if ($null -ne $current) {
                    $key = $root.OpenSubKey($entry.Path,$true)
                    try { $key.DeleteValue($entry.Name) } finally { $key.Dispose() }
                }
                $receipt.DeleteValue($entry.Id)
                $receipt.DeleteValue("Previous:$($entry.Id)",$false)
                Write-Output "Removed $($entry.Id)."
            }
        }
        if ($mode -eq 'Uninstall') {
            $paths = foreach ($entry in $entries) { Get-Parents $entry.Path }
            foreach ($path in ($paths | Sort-Object -Unique | Sort-Object Length -Descending)) {
                if ($receipt.GetValue("Key:$path") -cne 'created') { continue }
                $key = $root.OpenSubKey($path)
                if ($key) {
                    try { $empty = !$key.ValueCount -and !$key.SubKeyCount } finally { $key.Dispose() }
                    if ($empty) { $root.DeleteSubKey($path) }
                }
                $receipt.DeleteValue("Key:$path")
            }
        }
        if ($mode -eq 'Uninstall' -and !$receipt.GetValueNames().Length) {
            $receipt.Dispose()
            $receipt = $null
            $root.DeleteSubKey($receiptKey)
        }
    } finally { if ($receipt) { $receipt.Dispose() } }
}

function Update-Plugin($root, $mode) {
    $receipt = $root.OpenSubKey($receiptKey, ($mode -ne 'Check'))
    try {
        foreach ($name in $pluginFiles) {
            $target = Join-Path $plugin $name
            $local = Join-Path $PSScriptRoot $name
            $installed = if ([IO.File]::Exists($target)) { (Get-FileHash -LiteralPath $target).Hash }
            $owned = if ($receipt) { $receipt.GetValue("File:$name") }
            if ($mode -eq 'Uninstall') {
                if ($owned -and $installed -and $installed -cne $owned) { throw "Locally modified $name was preserved." }
            } else {
                $wanted = (Get-FileHash -LiteralPath $local).Hash
                if ($installed -and $installed -cne $wanted -and $installed -cne $owned) {
                    throw "An unrelated $name already exists in the patch folder."
                }
                if ($mode -eq 'Check') { Write-Output "$name matches package: $($installed -ceq $wanted)" }
            }
        }
        if ($mode -eq 'Check') { return }
        foreach ($name in $pluginFiles) {
            $target = Join-Path $plugin $name
            if ($mode -eq 'Install') {
                $local = Join-Path $PSScriptRoot $name
                $wanted = (Get-FileHash -LiteralPath $local).Hash
                if ([IO.File]::Exists($target) -and (Get-FileHash -LiteralPath $target).Hash -ceq $wanted) { continue }
                if (!$receipt) { $receipt = $root.CreateSubKey($receiptKey) }
                $receipt.SetValue("File:$name",$wanted)
                $receipt.Flush()
                [IO.Directory]::CreateDirectory($plugin) | Out-Null
                [IO.File]::Copy($local,$target,$true)
                if ((Get-FileHash -LiteralPath $target).Hash -cne $wanted) { throw "Copy failed for $name." }
            } elseif ($receipt -and $receipt.GetValue("File:$name")) {
                [IO.File]::Delete($target)
                $receipt.DeleteValue("File:$name")
            }
        }
        if ($mode -eq 'Uninstall' -and [IO.Directory]::Exists($plugin) -and
            ![IO.Directory]::GetFileSystemEntries($plugin).Length) { [IO.Directory]::Delete($plugin) }
    } finally { if ($receipt) { $receipt.Dispose() } }
}

# Dot-sourcing exposes the update routines for isolated registry tests.
if ($MyInvocation.InvocationName -eq '.') { return }
$native = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine','Registry64')
$installer = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine','Registry32')
$lock = $null
$held = $false
try {
    $entries = foreach ($name in $fields) {
        [pscustomobject]@{Id=$name; Path=$product; Name=$name; Value=$null}
    }
    $entries += [pscustomobject]@{Id='Avatar Open'; Path=$commandKey; Name=''; Value=$null}
    if ($Action -ne 'Uninstall') {
        foreach ($entry in $entries[0..4]) {
            $entry.Value = Read-String $installer $product $entry.Name
            if ([string]::IsNullOrWhiteSpace($entry.Value)) { throw "Missing installer field $($entry.Id)." }
        }
        $exe = $entries[0].Value
        if ($exe -ine (Join-Path $bin 'CharacterCreator.exe') -or $entries[1].Value -cne 'CC5PIPE' -or $entries[3].Value -cne '520' -or
            $entries[4].Value -cne '5.2.2310.1' -or (Split-Path -Leaf $exe) -ine 'CharacterCreator.exe' -or
            (Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash -cne $expectedHash) {
            throw 'Unsupported CC5 installation or executable.'
        }
        if ((Read-String $native 'SOFTWARE\Classes\.ccAvatar' '') -cne $avatarClass) {
            throw 'The installed .ccAvatar file class differs from the supported installation.'
        }
        $powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $entries[-1].Value = '"{0}" -NoProfile -WindowStyle Hidden -ExecutionPolicy RemoteSigned -File "{1}" "%1"' -f $powershell,(Join-Path $plugin 'Open-Avatar.ps1')
    }
    if ($Action -ne 'Check') {
        if (Get-Process -Name CharacterCreator -ErrorAction SilentlyContinue) {
            # Updating only the Explorer script is safe while a character is open.
            if ($Action -ne 'Install') { throw 'Save your work and close CC5 first.' }
            foreach ($entry in $entries) {
                if ((Read-String $native $entry.Path $entry.Name) -cne $entry.Value) { throw 'Close CC5 before changing its registration.' }
            }
            $hostPlugin = Join-Path $plugin 'main.py'
            if (![IO.File]::Exists($hostPlugin) -or
                (Get-FileHash -LiteralPath $hostPlugin).Hash -cne (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot 'main.py')).Hash) {
                throw 'Close CC5 before changing its loaded plug-in.'
            }
        }
        $principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
        if (!$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Run this operation as administrator.' }
        $lock = [Threading.Mutex]::new($false,'Global\CC5NativeOpenRepair_5202310')
        try { $held = $lock.WaitOne(0) } catch [Threading.AbandonedMutexException] { $held = $true }
        if (!$held) { throw 'Another repair is running.' }
    }
    if ($Action -eq 'Install') {
        Update-Plugin $native Check
        Update-Registration $native $entries Check
    }
    Update-Plugin $native $Action
    Update-Registration $native $entries $Action
} finally {
    if ($held) { $lock.ReleaseMutex() }
    if ($lock) { $lock.Dispose() }
    $installer.Dispose()
    $native.Dispose()
}
