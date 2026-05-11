# FileHandler.psm1 — Detect today's downloaded JSON files and move them to the UNC share

function Find-TodaysSignInFiles {
    param(
        [string]$DownloadsFolder,
        [string]$Abbr
    )
    $today = (Get-Date).ToString('yyyy-MM-dd')

    $interactive = Get-ChildItem -Path $DownloadsFolder -Filter "InteractiveSignIns_*_$today.json" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    $nonInteractive = Get-ChildItem -Path $DownloadsFolder -Filter "NonInteractiveSignIns_*_$today.json" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1

    return [PSCustomObject]@{
        Interactive    = $interactive
        NonInteractive = $nonInteractive
        Abbr           = $Abbr
    }
}

function Move-FilesToShare {
    param(
        [PSCustomObject]$FoundFiles,
        [string]$SigninFolder
    )
    $errors = [System.Collections.Generic.List[string]]::new()

    foreach ($type in @('Interactive', 'NonInteractive')) {
        $file = $FoundFiles.$type
        if (-not $file) {
            $errors.Add("No $type file found for today in Downloads.")
            continue
        }

        $destDir = Join-Path $SigninFolder "$type\$($FoundFiles.Abbr)"
        try {
            if (-not (Test-Path $destDir)) {
                New-Item -Path $destDir -ItemType Directory | Out-Null
            }
            $destPath = Join-Path $destDir $file.Name
            Move-Item -Path $file.FullName -Destination $destPath -Force
        } catch {
            $errors.Add("Failed to move $type file: $($_.Exception.Message)")
        }
    }

    return [PSCustomObject]@{
        Success = $errors.Count -eq 0
        Errors  = $errors
    }
}

Export-ModuleMember -Function Find-TodaysSignInFiles, Move-FilesToShare
