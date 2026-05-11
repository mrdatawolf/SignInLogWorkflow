#Requires -Version 5.1
# Re-launch in STA thread if needed (WPF requirement)
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    & powershell -STA -NoProfile -File $MyInvocation.MyCommand.Path
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$ScriptRoot = $PSScriptRoot

# Load modules
Import-Module (Join-Path $ScriptRoot 'Modules\Config.psm1')       -Force
Import-Module (Join-Path $ScriptRoot 'Modules\ClientList.psm1')   -Force
Import-Module (Join-Path $ScriptRoot 'Modules\Clipboard.psm1')    -Force
Import-Module (Join-Path $ScriptRoot 'Modules\FileHandler.psm1')  -Force
Import-Module (Join-Path $ScriptRoot 'Modules\SqliteImport.psm1') -Force

# Load config
$Config = Get-AppConfig -ScriptRoot $ScriptRoot

# Load XAML
[xml]$xaml = Get-Content (Join-Path $ScriptRoot 'UI\MainWindow.xaml')
$reader    = [System.Xml.XmlNodeReader]::new($xaml)
$window    = [System.Windows.Markup.XamlReader]::Load($reader)

# ── Helper: get named element ──────────────────────────────────────
function e { param($n) $window.FindName($n) }

# ── State ──────────────────────────────────────────────────────────
$script:Clients     = @()
$script:ClientIndex = -1
$script:Step        = 0   # 0=ready 1=browser-open 2=password-ready 3=files-moved(import running)

# ── Navigation ────────────────────────────────────────────────────
function Show-View {
    param([string]$Name)
    foreach ($v in @('viewSetup','viewWorkflow','viewSettings')) {
        (e $v).Visibility = if ($v -eq $Name) { 'Visible' } else { 'Collapsed' }
    }
    (e 'btnNavWorkflow').Style = $window.FindResource(
        $(if ($Name -eq 'viewWorkflow') { 'NavButtonActive' } else { 'NavButton' }))
    (e 'btnNavSettings').Style  = $window.FindResource(
        $(if ($Name -eq 'viewSettings') { 'NavButtonActive' } else { 'NavButton' }))
}

(e 'btnNavWorkflow').Add_Click({ Show-View 'viewWorkflow' })
(e 'btnNavSettings').Add_Click({
    (e 'txtBaseFolder').Text      = $Config.BaseFolder
    (e 'txtAdminEmailsFile').Text = $Config.AdminEmailsFile
    (e 'txtDownloadsFolder').Text = $Config.DownloadsFolder
    (e 'lblResolvedPaths').Text   = "SigninFolder : $($Config.SigninFolder)`nDbPath       : $($Config.DbPath)`nCompaniesFile: $($Config.CompaniesFile)"
    Show-View 'viewSettings'
})

# ── Settings: save ────────────────────────────────────────────────
(e 'btnSaveSettings').Add_Click({
    $override = [PSCustomObject]@{
        baseFolder      = (e 'txtBaseFolder').Text.Trim()
        adminEmailsFile = (e 'txtAdminEmailsFile').Text.Trim()
        downloadsFolder = (e 'txtDownloadsFolder').Text.Trim()
    }
    Save-AppConfig -ScriptRoot $ScriptRoot -Config $override
    $script:Config = Get-AppConfig -ScriptRoot $ScriptRoot
    [System.Windows.MessageBox]::Show('Settings saved. Reload clients to apply.', 'Saved', 'OK', 'Information')
})

# ── Progress bar update ───────────────────────────────────────────
function Update-Progress {
    $total     = $script:Clients.Count
    if ($total -eq 0) { return }
    $done      = ($script:Clients | Where-Object { $_.Status -in @('Done','Error','Skipped') }).Count
    $importing = ($script:Clients | Where-Object { $_.Status -eq 'Importing' }).Count
    (e 'sessionProgress').Value = $done / $total
    $txt = "$done / $total done"
    if ($importing -gt 0) { $txt += "  ($importing importing in background)" }
    (e 'lblProgress').Text = $txt
}

# ── Status color helper (for DataGrid) ────────────────────────────
# DataGrid rows are plain text; color the Status cell via DataGridTemplateColumn if desired.
# For now status text carries emoji for quick scanning.
function Status-Label {
    param([string]$s)
    switch ($s) {
        'Pending'   { '○ Pending'   }
        'Active'    { '▶ Active'    }
        'Importing' { '⟳ Importing' }
        'Done'      { '✓ Done'      }
        'Error'     { '✗ Error'     }
        'Skipped'   { '— Skipped'   }
        default     { $s }
    }
}

# ── Load clients ──────────────────────────────────────────────────
function Invoke-LoadClients {
    (e 'btnLoadClients').IsEnabled = $false
    (e 'lblSessionDate').Text = "Session: $((Get-Date).ToString('dddd, MMMM d yyyy'))"
    try {
        $script:Clients = Get-ClientList -Config $Config
        $script:DoneCount   = 0
        $script:ClientIndex = -1

        # Build display list for DataGrid
        $displayList = $script:Clients | ForEach-Object {
            [PSCustomObject]@{ Abbr = $_.Abbr; Status = Status-Label $_.Status; _ref = $_ }
        }
        (e 'dgClients').ItemsSource = $displayList
        Update-Progress
        Start-NextClient
    } catch {
        [System.Windows.MessageBox]::Show("Failed to load clients:`n$($_.Exception.Message)", 'Error', 'OK', 'Error')
        (e 'btnLoadClients').IsEnabled = $true
    }
}

(e 'btnLoadClients').Add_Click({ Invoke-LoadClients })

# ── Advance to next pending client ────────────────────────────────
function Start-NextClient {
    $next = -1
    for ($i = 0; $i -lt $script:Clients.Count; $i++) {
        if ($script:Clients[$i].Status -eq 'Pending') { $next = $i; break }
    }
    # 'Importing' clients are in-flight — they are not Pending, not blocked

    if ($next -eq -1) {
        # No more pending clients — may still have background imports running
        (e 'panelSteps').Visibility    = 'Collapsed'
        (e 'panelNoClient').Visibility = 'Collapsed'
        (e 'panelAllDone').Visibility  = 'Visible'
        $done      = ($script:Clients | Where-Object { $_.Status -in @('Done','Importing') }).Count
        $errors    = ($script:Clients | Where-Object Status -eq 'Error').Count
        $skipped   = ($script:Clients | Where-Object Status -eq 'Skipped').Count
        $importing = ($script:Clients | Where-Object Status -eq 'Importing').Count
        $summary   = "$done completed, $errors errors, $skipped skipped"
        if ($importing -gt 0) { $summary += " ($importing still importing in background)" }
        (e 'lblFinalSummary').Text = $summary
        return
    }

    $script:ClientIndex = $next
    $client = $script:Clients[$next]
    $client.Status = 'Active'
    $script:Step   = 0
    Refresh-ClientList

    (e 'lblActiveAbbr').Text  = $client.Abbr
    (e 'lblActiveEmail').Text = $client.Email
    (e 'panelNoClient').Visibility  = 'Collapsed'
    (e 'panelAllDone').Visibility   = 'Collapsed'
    (e 'panelSteps').Visibility     = 'Visible'

    # Reset step UI
    Set-StepState
}

# ── Keep DataGrid in sync ─────────────────────────────────────────
function Refresh-ClientList {
    $items = (e 'dgClients').ItemsSource
    if (-not $items) { return }
    for ($i = 0; $i -lt $script:Clients.Count; $i++) {
        $items[$i].Status = Status-Label $script:Clients[$i].Status
    }
    (e 'dgClients').Items.Refresh()
    Update-Progress
}

# ── Step state: enable/disable controls and highlight active step ─
function Set-StepState {
    $s = $script:Step

    # Step borders: active = blue tint, inactive = gray tint
    $active   = [System.Windows.Media.Color]::FromRgb(0xEF,0xF6,0xFF)
    $inactive = [System.Windows.Media.Color]::FromRgb(0xF8,0xFA,0xFC)
    $activeBorder   = [System.Windows.Media.Color]::FromRgb(0xBF,0xDB,0xFE)
    $inactiveBorder = [System.Windows.Media.Color]::FromRgb(0xE2,0xE8,0xF0)

    foreach ($pair in @(
        @{ Border='step1Border'; Active = ($s -eq 0) }
        @{ Border='step2Border'; Active = ($s -eq 1) }
        @{ Border='step3Border'; Active = ($s -eq 2) }
        @{ Border='step4Border'; Active = ($s -ge 3) }
    )) {
        $el = e $pair.Border
        $el.Background   = [System.Windows.Media.SolidColorBrush]::new($(if ($pair.Active) { $active   } else { $inactive }))
        $el.BorderBrush  = [System.Windows.Media.SolidColorBrush]::new($(if ($pair.Active) { $activeBorder } else { $inactiveBorder }))
    }

    (e 'btnOpenBrowser').IsEnabled  = ($s -eq 0)
    (e 'btnUsernameDone').IsEnabled = ($s -eq 1)
    (e 'btnFilesDone').IsEnabled    = ($s -eq 2)
    (e 'btnNextClient').IsEnabled   = ($s -ge 3)   # available as soon as files are moved

    if ($s -lt 3) {
        (e 'lblMoveStatus').Text         = 'Waiting for files…'
        (e 'importLogBorder').Visibility = 'Collapsed'
        (e 'lblImportResult').Text       = ''
    }
}

# ── Step 1: Open Firefox ──────────────────────────────────────────
(e 'btnOpenBrowser').Add_Click({
    $client = $script:Clients[$script:ClientIndex]
    $url    = "https://entra.microsoft.com/#view/Microsoft_AAD_IAM/SignInEventsV3Blade/timeRangeType/last7days/showApplicationSignIns~/true&login_hint=$($client.Email)"

    $firefoxPaths = @(
        "$env:ProgramFiles\Mozilla Firefox\firefox.exe",
        "${env:ProgramFiles(x86)}\Mozilla Firefox\firefox.exe",
        "$env:LocalAppData\Mozilla Firefox\firefox.exe"
    )
    $firefox = $firefoxPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($firefox) {
        Start-Process $firefox -ArgumentList '-private-window', $url
    } else {
        [System.Windows.MessageBox]::Show('Firefox not found. Opening in default browser.','Warning','OK','Warning')
        Start-Process $url
    }

    # Copy username to clipboard immediately
    Copy-StringToClipboard -Value $client.Email

    $script:Step = 1
    Set-StepState
})

# ── Step 2: Username done → copy password ─────────────────────────
(e 'btnUsernameDone').Add_Click({
    $client = $script:Clients[$script:ClientIndex]
    Copy-SecureStringToClipboard -SecureValue $client.SecurePassword
    $script:Step = 2
    Set-StepState
})

# ── Step 3: Files downloaded → move + import ─────────────────────
# The click handler returns immediately; all file I/O and import work
# runs on a background runspace so the UI thread is never blocked.
(e 'btnFilesDone').Add_Click({
    Clear-Clipboard
    (e 'btnFilesDone').IsEnabled     = $false
    (e 'lblMoveStatus').Text         = 'Searching for today''s files…'
    (e 'importLogBorder').Visibility = 'Visible'
    (e 'lblImportResult').Text       = ''

    $importIndex   = $script:ClientIndex
    $importClient  = $script:Clients[$importIndex]
    $importDisplay = (e 'dgClients').ItemsSource[$importIndex]

    $syncHash = [hashtable]::Synchronized(@{
        Window          = $window
        LogEl           = (e 'lblImportLog')
        ScrollEl        = (e 'importLogScroll')
        ResultEl        = (e 'lblImportResult')
        MoveStatusEl    = (e 'lblMoveStatus')
        FilesDoneBtn    = (e 'btnFilesDone')
        ClientObj       = $importClient
        DisplayRow      = $importDisplay
        Log             = "[$($importClient.Abbr)] Searching for today's files…`n"
        Result          = $null
        Abbr            = $importClient.Abbr
        DownloadsFolder = $Config.DownloadsFolder
        SigninFolder    = $Config.SigninFolder
        DbPath          = $Config.DbPath
    })
    (e 'lblImportLog').Text = $syncHash.Log

    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions  = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('syncHash', $syncHash)
    $rs.SessionStateProxy.SetVariable('ScriptRoot', $ScriptRoot)

    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.Runspace = $rs
    [void]$ps.AddScript({
        Import-Module (Join-Path $ScriptRoot 'Modules\FileHandler.psm1')  -Force
        Import-Module (Join-Path $ScriptRoot 'Modules\SqliteImport.psm1') -Force

        # ── Find files ──────────────────────────────────────────────
        $found = Find-TodaysSignInFiles -DownloadsFolder $syncHash.DownloadsFolder -Abbr $syncHash.Abbr

        if (-not $found.Interactive -and -not $found.NonInteractive) {
            $syncHash.Window.Dispatcher.Invoke([Action]{
                $syncHash.MoveStatusEl.Text = "No matching files found in: $($syncHash.DownloadsFolder)"
                $syncHash.FilesDoneBtn.IsEnabled = $true
                $syncHash.LogEl.Text = ''
                $syncHash.Window.FindName('importLogBorder').Visibility = 'Collapsed'
            })
            return
        }

        # ── Move files ──────────────────────────────────────────────
        $syncHash.Log += "Moving files to share…`n"
        [void]$syncHash.Window.Dispatcher.InvokeAsync([Action]{
            $syncHash.MoveStatusEl.Text = 'Moving files to share…'
            $syncHash.LogEl.Text        = $syncHash.Log
        })

        $moveResult = Move-FilesToShare -FoundFiles $found -SigninFolder $syncHash.SigninFolder
        if (-not $moveResult.Success) {
            $syncHash.MoveErrors = $moveResult.Errors -join "`n"
            $syncHash.Window.Dispatcher.Invoke([Action]{
                $syncHash.MoveStatusEl.Text      = "Move failed: $($syncHash.MoveErrors)"
                $syncHash.FilesDoneBtn.IsEnabled  = $true
            })
            return
        }

        # ── Advance UI to step-4 state; enable Next Client ──────────
        # $script:Step cannot be set cross-runspace; button/border states
        # are applied directly here. btnNextClient.Add_Click resets to 0 anyway.
        $syncHash.Log += "Files moved. Starting import…`n"
        $syncHash.Window.Dispatcher.Invoke([Action]{
            $syncHash.MoveStatusEl.Text = 'Files moved. Import running in background…'
            $syncHash.LogEl.Text        = $syncHash.Log
            $syncHash.ScrollEl.ScrollToEnd()
            $syncHash.Window.FindName('btnNextClient').IsEnabled = $true

            $active         = [System.Windows.Media.Color]::FromRgb(0xEF,0xF6,0xFF)
            $inactive       = [System.Windows.Media.Color]::FromRgb(0xF8,0xFA,0xFC)
            $activeBorder   = [System.Windows.Media.Color]::FromRgb(0xBF,0xDB,0xFE)
            $inactiveBorder = [System.Windows.Media.Color]::FromRgb(0xE2,0xE8,0xF0)
            foreach ($pair in @(
                @{ Name='step1Border'; IsActive=$false }
                @{ Name='step2Border'; IsActive=$false }
                @{ Name='step3Border'; IsActive=$false }
                @{ Name='step4Border'; IsActive=$true  }
            )) {
                $el = $syncHash.Window.FindName($pair.Name)
                $el.Background  = [System.Windows.Media.SolidColorBrush]::new(
                    $(if ($pair.IsActive) { $active } else { $inactive }))
                $el.BorderBrush = [System.Windows.Media.SolidColorBrush]::new(
                    $(if ($pair.IsActive) { $activeBorder } else { $inactiveBorder }))
            }
        })

        # ── Import ───────────────────────────────────────────────────
        # $msg is updated in background runspace (where it is in scope);
        # the [Action] only reads from syncHash to avoid cross-boundary capture issues.
        $onProgress = {
            param($msg)
            $syncHash.Log += "$msg`n"
            [void]$syncHash.Window.Dispatcher.InvokeAsync([Action]{
                $syncHash.LogEl.Text = $syncHash.Log
                $syncHash.ScrollEl.ScrollToEnd()
            })
        }

        try {
            $result = Invoke-ClientImport -Abbr $syncHash.Abbr `
                -SigninFolder $syncHash.SigninFolder `
                -DbPath $syncHash.DbPath `
                -OnProgress $onProgress
            $syncHash.Result = $result
        } catch {
            $syncHash.Result = [PSCustomObject]@{
                InteractiveInserted=0; NonInteractiveInserted=0
                Errors=1; ErrorMessage=$_.Exception.Message
            }
        }

        # ── Completion ───────────────────────────────────────────────
        $syncHash.Window.Dispatcher.Invoke([Action]{
            $r = $syncHash.Result
            $hasError = ($r.Errors -gt 0 -and $r.InteractiveInserted -eq 0 -and $r.NonInteractiveInserted -eq 0)

            $syncHash.ClientObj.Status       = if ($hasError) { 'Error' } else { 'Done' }
            $syncHash.ClientObj.ImportResult = $r

            $label = if ($hasError) { '✗ Error' } else { "✓ Done (+$($r.InteractiveInserted) / +$($r.NonInteractiveInserted))" }
            $syncHash.DisplayRow.Status = $label
            $syncHash.Window.FindName('dgClients').Items.Refresh()

            $allClients = $syncHash.Window.FindName('dgClients').ItemsSource
            $total  = $allClients.Count
            $doneN  = ($allClients | Where-Object { $_.Status -match '^(✓|✗|—)' }).Count
            $impN   = ($allClients | Where-Object { $_.Status -match '^⟳' }).Count
            $syncHash.Window.FindName('sessionProgress').Value = if ($total -gt 0) { $doneN / $total } else { 0 }
            $pTxt = "$doneN / $total done"
            if ($impN -gt 0) { $pTxt += "  ($impN importing in background)" }
            $syncHash.Window.FindName('lblProgress').Text = $pTxt

            if ($syncHash.Window.FindName('lblActiveAbbr').Text -eq $syncHash.Abbr) {
                if ($hasError) {
                    $syncHash.MoveStatusEl.Text   = 'Import finished with errors.'
                    $syncHash.ResultEl.Foreground = [System.Windows.Media.Brushes]::OrangeRed
                } else {
                    $syncHash.MoveStatusEl.Text   = 'Import complete.'
                    $syncHash.ResultEl.Foreground = [System.Windows.Media.Brushes]::Green
                }
                $syncHash.ResultEl.Text = "Interactive: +$($r.InteractiveInserted)   Non-Interactive: +$($r.NonInteractiveInserted)   Errors: $($r.Errors)"
            }
        })
    })

    [void]$ps.BeginInvoke()
})

# ── Next client ───────────────────────────────────────────────────
(e 'btnNextClient').Add_Click({
    $c = $script:Clients[$script:ClientIndex]
    # If import is still running in background, mark Importing; RunSpace will flip to Done/Error
    if ($c.Status -notin @('Done','Error')) { $c.Status = 'Importing' }
    $script:Step = 0
    Refresh-ClientList
    Start-NextClient
})

# ── Skip client ───────────────────────────────────────────────────
(e 'btnSkipClient').Add_Click({
    $script:Clients[$script:ClientIndex].Status = 'Skipped'
    $script:Step = 0
    Refresh-ClientList
    Start-NextClient
})

# ── Initialise: run prechecks, go straight to workflow if all pass ─
$checks = Test-Prechecks -Config $Config
$allPass = ($checks | Where-Object { -not $_.Passed }).Count -eq 0

if (-not $allPass) {
    # Build display items
    $checkItems = $checks | ForEach-Object {
        [PSCustomObject]@{
            Name        = $_.Name
            StatusText  = if ($_.Passed) { 'Pass' } else { "Fail$(if($_.Error){': '+$_.Error})" }
            StatusColor = if ($_.Passed) { '#16A34A' } else { '#DC2626' }
        }
    }
    (e 'lstPrechecks').ItemsSource = $checkItems
    (e 'btnProceedToWorkflow').IsEnabled = $false
    Show-View 'viewSetup'

    (e 'btnRetryChecks').Add_Click({
        $c2 = Test-Prechecks -Config $Config
        $items = (e 'lstPrechecks').ItemsSource
        for ($i=0; $i -lt $c2.Count; $i++) {
            $items[$i].StatusText  = if ($c2[$i].Passed) { 'Pass' } else { "Fail$(if($c2[$i].Error){': '+$c2[$i].Error})" }
            $items[$i].StatusColor = if ($c2[$i].Passed) { '#16A34A' } else { '#DC2626' }
        }
        (e 'lstPrechecks').Items.Refresh()
        $ok = ($c2 | Where-Object { -not $_.Passed }).Count -eq 0
        (e 'btnProceedToWorkflow').IsEnabled = $ok
    })
    (e 'btnProceedToWorkflow').Add_Click({
        Show-View 'viewWorkflow'
        Invoke-LoadClients
    })
} else {
    Show-View 'viewWorkflow'
    $window.Add_ContentRendered({ Invoke-LoadClients })
}

# ── Show window ────────────────────────────────────────────────────
[void]$window.ShowDialog()
