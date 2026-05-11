# Config.psm1 — Load .env + config.json, expose resolved settings

function Import-EnvFile {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }
    Get-Content $Path | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($Matches[1].Trim(), $Matches[2].Trim(), 'Process')
        }
    }
}

function Get-AppConfig {
    param([string]$ScriptRoot)

    Import-EnvFile -Path (Join-Path $ScriptRoot '.env')

    $configPath = Join-Path $ScriptRoot 'config.json'
    $saved = if (Test-Path $configPath) {
        Get-Content $configPath -Raw | ConvertFrom-Json
    } else { [PSCustomObject]@{} }

    $baseFolder   = if ($saved.baseFolder)    { $saved.baseFolder }    else { $env:baseFolder }
    $signinFolder = Join-Path $baseFolder 'O365 Signins'
    $dbPath       = Join-Path $signinFolder 'O365logins.sqlite3'

    [PSCustomObject]@{
        BaseFolder        = $baseFolder
        SigninFolder      = $signinFolder
        DbPath            = $dbPath
        CompaniesFile     = Join-Path $baseFolder ($env:companiesFilename ?? 'companies.xlsx')
        AdminEmailsFile   = if ($saved.adminEmailsFile) { $saved.adminEmailsFile } else { $env:adminEmailsFile }
        DownloadsFolder   = if ($saved.downloadsFolder) { $saved.downloadsFolder } else { Join-Path $env:USERPROFILE 'Downloads' }
    }
}

function Save-AppConfig {
    param([string]$ScriptRoot, [PSCustomObject]$Config)
    $configPath = Join-Path $ScriptRoot 'config.json'
    $Config | ConvertTo-Json | Set-Content $configPath
}

function Test-Prechecks {
    param([PSCustomObject]$Config)
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()

    $checks = @(
        @{ Name = 'UNC Share accessible';       Test = { Test-Path $Config.BaseFolder } }
        @{ Name = 'O365 Signins folder exists'; Test = { Test-Path $Config.SigninFolder } }
        @{ Name = 'Companies file exists';      Test = { Test-Path $Config.CompaniesFile } }
        @{ Name = 'Admin Emails file exists';   Test = { Test-Path $Config.AdminEmailsFile } }
        @{ Name = 'SQLite DB accessible';       Test = { Test-Path (Split-Path $Config.DbPath -Parent) } }
        @{ Name = 'Downloads folder exists';    Test = { Test-Path $Config.DownloadsFolder } }
    )

    foreach ($check in $checks) {
        $passed = $false
        $err    = $null
        try { $passed = & $check.Test } catch { $err = $_.Exception.Message }
        $results.Add([PSCustomObject]@{ Name = $check.Name; Passed = $passed; Error = $err })
    }
    return $results
}

Export-ModuleMember -Function Import-EnvFile, Get-AppConfig, Save-AppConfig, Test-Prechecks
