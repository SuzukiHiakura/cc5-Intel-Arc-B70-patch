# SPDX-License-Identifier: GPL-3.0-only
# Exercise install and rollback inside a disposable key owned by this user.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Repair-CC5.ps1')
$receiptKey = 'Journal'
$fixture = 'Software\CC5NativeOpenTest-' + [Guid]::NewGuid().ToString('N')
$user = [Microsoft.Win32.Registry]::CurrentUser
$root = $user.CreateSubKey($fixture)
$plugin = Join-Path ([IO.Path]::GetTempPath()) ('CC5PluginTest-' + [Guid]::NewGuid().ToString('N'))
$entries = @(
    [pscustomobject]@{Id='Existing'; Path='Product'; Name='Version'; Value='example'},
    [pscustomobject]@{Id='Missing'; Path='Product'; Name='Build'; Value='test'},
    [pscustomobject]@{Id='Open'; Path='Type\shell\open\command'; Name=''; Value='"example.exe" "%1"'}
)
function Assert-True($condition, $message) { if (!$condition) { throw $message } }
try {
    $key = $root.CreateSubKey('Product')
    $key.SetValue('Version','example')
    $key.Dispose()
    Update-Registration $root $entries Check
    Update-Registration $root $entries Install
    Update-Registration $root $entries Install
    Assert-True ((Read-String $root 'Product' 'Build') -ceq 'test') 'Installation failed.'
    Assert-True ((Read-String $root $entries[2].Path '') -ceq $entries[2].Value) 'Open command failed.'
    $key = $root.OpenSubKey('Product',$true)
    $key.SetValue('Build','changed')
    $key.Dispose()
    foreach ($mode in 'Install','Uninstall') {
        $refused = $false
        try { Update-Registration $root $entries $mode } catch { $refused = $true }
        Assert-True $refused "Conflict accepted in $mode."
    }
    $key = $root.OpenSubKey('Product',$true)
    $key.SetValue('Build','test')
    $key.Dispose()
    Update-Registration $root $entries Uninstall
    Update-Registration $root $entries Uninstall
    Assert-True ($null -eq (Read-String $root 'Product' 'Build')) 'Rollback failed.'
    Assert-True ((Read-String $root 'Product' 'Version') -ceq 'example') 'Pre-existing entry changed.'
    Assert-True ($root.GetSubKeyNames() -notcontains 'Type') 'Empty file association remained.'
    Assert-True ($root.GetSubKeyNames() -notcontains 'Journal') 'Journal remained.'
    Update-Plugin $root Install
    Update-Plugin $root Install
    $copy = Join-Path $plugin 'main.py'
    Assert-True ((Get-FileHash $copy).Hash -eq (Get-FileHash (Join-Path $PSScriptRoot 'main.py')).Hash) 'Plugin copy differs.'
    [IO.File]::AppendAllText($copy,"# local edit")
    $refused = $false
    try { Update-Plugin $root Uninstall } catch { $refused = $true }
    Assert-True $refused 'Modified plugin was removed.'
    [IO.File]::Copy((Join-Path $PSScriptRoot 'main.py'),$copy,$true)
    Update-Plugin $root Uninstall
    Assert-True (![IO.Directory]::Exists($plugin)) 'Temporary plugin directory remained.'
    'Passed install, repeat install, conflict protection, rollback and plug-in file checks.'
} finally {
    if ([IO.Directory]::Exists($plugin)) {
        foreach ($name in $pluginFiles) { [IO.File]::Delete((Join-Path $plugin $name)) }
        [IO.Directory]::Delete($plugin)
    }
    $root.Dispose()
    $user.DeleteSubKeyTree($fixture)
}
