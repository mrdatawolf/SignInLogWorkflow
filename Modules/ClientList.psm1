# ClientList.psm1 — Read clients from Excel, return objects with SecureString passwords

function Get-ClientList {
    param([PSCustomObject]$Config)

    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        Install-Module -Name ImportExcel -Scope CurrentUser -Force
    }
    Import-Module ImportExcel -ErrorAction Stop

    # Load abbreviations from companies.xlsx (same filter as PS script)
    $companies = Import-Excel -Path $Config.CompaniesFile -WorksheetName 'Companies'
    $abbrs = @('BT') + ($companies | Where-Object { $_.Group -eq 'SLG' } | Select-Object -ExpandProperty Abbrv)

    # Load credentials from Admin Emails.xlsx
    $adminData = Import-Excel -Path $Config.AdminEmailsFile

    $clients = foreach ($abbr in $abbrs) {
        $row = $adminData | Where-Object { $_.Client -eq $abbr } | Select-Object -First 1
        if ($row) {
            [PSCustomObject]@{
                Abbr           = $abbr
                Email          = $row.Email
                SecurePassword = ConvertTo-SecureString $row.Password -AsPlainText -Force
                Status         = 'Pending'   # Pending | Active | Done | Error | Skipped
                ImportResult   = $null
            }
        }
    }
    return @($clients)
}

Export-ModuleMember -Function Get-ClientList
