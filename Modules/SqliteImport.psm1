# SqliteImport.psm1 — Import sign-in JSON files for one client into SQLite

function Invoke-ClientImport {
    param(
        [string]$Abbr,
        [string]$SigninFolder,
        [string]$DbPath,
        [scriptblock]$OnProgress   # called with [string]$message
    )

    if (-not (Get-Module -ListAvailable -Name PSSQLite)) {
        Install-Module -Name PSSQLite -Scope CurrentUser -Force
    }
    Import-Module PSSQLite -ErrorAction Stop

    $totals = @{ Interactive = 0; NonInteractive = 0; Errors = 0 }

    # Ensure DB and tables exist
    _Initialize-Database -DbPath $DbPath
    foreach ($tableName in @('Interactive', 'NonInteractive')) {
        _Initialize-Table -DbPath $DbPath -TableName $tableName
    }

    $connection = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$DbPath;Version=3;")
    $connection.Open()
    Invoke-SqliteQuery -Query 'PRAGMA synchronous = OFF;'  -Connection $connection
    Invoke-SqliteQuery -Query 'PRAGMA journal_mode = MEMORY;' -Connection $connection
    Invoke-SqliteQuery -Query 'PRAGMA busy_timeout = 100;'    -Connection $connection

    try {
        foreach ($tableName in @('Interactive', 'NonInteractive')) {
            $folder = Join-Path $SigninFolder "$tableName\$Abbr"
            if (-not (Test-Path $folder)) {
                & $OnProgress "  [$tableName] Folder not found, skipping: $folder"
                continue
            }

            $finishedDir = Join-Path $SigninFolder "Finished\$tableName\$Abbr"
            if (-not (Test-Path $finishedDir)) { New-Item -Path $finishedDir -ItemType Directory | Out-Null }

            $logPath = Join-Path $SigninFolder "debug_$tableName.log"
            $files   = Get-ChildItem -Path $folder -Filter '*.json' -Recurse

            $insertQuery = @"
INSERT INTO $tableName (
    id,createdDateTime,userDisplayName,userPrincipalName,userId,appId,appDisplayName,
    ipAddress,clientAppUsed,userAgent,correlationId,conditionalAccessStatus,originalRequestId,
    isInteractive,tokenIssuerName,tokenIssuerType,clientCredentialType,processingTimeInMilliseconds,
    riskDetail,riskLevelAggregated,riskLevelDuringSignIn,riskState,resourceDisplayName,resourceId,
    resourceTenantId,homeTenantId,homeTenantName,authenticationRequirement,signInIdentifier,
    signInIdentifierType,servicePrincipalName,userType,flaggedForReview,isTenantRestricted,
    autonomousSystemNumber,crossTenantAccessType,uniqueTokenIdentifier,incomingTokenType,
    authenticationProtocol,signInTokenProtectionStatus,originalTransferMethod,
    isThroughGlobalSecureAccess,globalSecureAccessIpAddress,sessionId,appOwnerTenantId,
    resourceOwnerTenantId,status_errorCode,status_failureReason,status_additionalDetails,
    deviceDetail_deviceId,deviceDetail_displayName,deviceDetail_operatingSystem,deviceDetail_browser,
    deviceDetail_isCompliant,deviceDetail_isManaged,deviceDetail_trustType,
    location_city,location_state,location_countryOrRegion,
    location_geoCoordinates_latitude,location_geoCoordinates_longitude
) VALUES (
    @id,@createdDateTime,@userDisplayName,@userPrincipalName,@userId,@appId,@appDisplayName,
    @ipAddress,@clientAppUsed,@userAgent,@correlationId,@conditionalAccessStatus,@originalRequestId,
    @isInteractive,@tokenIssuerName,@tokenIssuerType,@clientCredentialType,@processingTimeInMilliseconds,
    @riskDetail,@riskLevelAggregated,@riskLevelDuringSignIn,@riskState,@resourceDisplayName,@resourceId,
    @resourceTenantId,@homeTenantId,@homeTenantName,@authenticationRequirement,@signInIdentifier,
    @signInIdentifierType,@servicePrincipalName,@userType,@flaggedForReview,@isTenantRestricted,
    @autonomousSystemNumber,@crossTenantAccessType,@uniqueTokenIdentifier,@incomingTokenType,
    @authenticationProtocol,@signInTokenProtectionStatus,@originalTransferMethod,
    @isThroughGlobalSecureAccess,@globalSecureAccessIpAddress,@sessionId,@appOwnerTenantId,
    @resourceOwnerTenantId,@status_errorCode,@status_failureReason,@status_additionalDetails,
    @deviceDetail_deviceId,@deviceDetail_displayName,@deviceDetail_operatingSystem,@deviceDetail_browser,
    @deviceDetail_isCompliant,@deviceDetail_isManaged,@deviceDetail_trustType,
    @location_city,@location_state,@location_countryOrRegion,
    @location_geoCoordinates_latitude,@location_geoCoordinates_longitude
);
"@

            foreach ($file in $files) {
                & $OnProgress "  [$tableName] Processing: $($file.Name)"
                try {
                    $records = Get-Content $file.FullName -Raw | ConvertFrom-Json
                    $inserted = 0
                    foreach ($record in $records) {
                        $exists = Invoke-SqliteQuery -DataSource $DbPath -Query "SELECT COUNT(*) FROM $tableName WHERE id=@id;" -SqlParameters @{id = $record.id} -As SingleValue
                        if ($exists -eq 0) {
                            $insertParams = @{
                                id                                = [string]$record.id
                                createdDateTime                   = [string]$record.createdDateTime
                                userDisplayName                   = [string]$record.userDisplayName
                                userPrincipalName                 = [string]$record.userPrincipalName
                                userId                            = [string]$record.userId
                                appId                             = [string]$record.appId
                                appDisplayName                    = [string]$record.appDisplayName
                                ipAddress                         = [string]$record.ipAddress
                                clientAppUsed                     = [string]$record.clientAppUsed
                                userAgent                         = [string]$record.userAgent
                                correlationId                     = [string]$record.correlationId
                                conditionalAccessStatus           = [string]$record.conditionalAccessStatus
                                originalRequestId                 = [string]$record.originalRequestId
                                isInteractive                     = [int]$record.isInteractive
                                tokenIssuerName                   = [string]$record.tokenIssuerName
                                tokenIssuerType                   = [string]$record.tokenIssuerType
                                clientCredentialType              = [string]$record.clientCredentialType
                                processingTimeInMilliseconds      = [int]$record.processingTimeInMilliseconds
                                riskDetail                        = [string]$record.riskDetail
                                riskLevelAggregated               = [string]$record.riskLevelAggregated
                                riskLevelDuringSignIn             = [string]$record.riskLevelDuringSignIn
                                riskState                         = [string]$record.riskState
                                resourceDisplayName               = [string]$record.resourceDisplayName
                                resourceId                        = [string]$record.resourceId
                                resourceTenantId                  = [string]$record.resourceTenantId
                                homeTenantId                      = [string]$record.homeTenantId
                                homeTenantName                    = [string]$record.homeTenantName
                                authenticationRequirement         = [string]$record.authenticationRequirement
                                signInIdentifier                  = [string]$record.signInIdentifier
                                signInIdentifierType              = [string]$record.signInIdentifierType
                                servicePrincipalName              = [string]$record.servicePrincipalName
                                userType                          = [string]$record.userType
                                flaggedForReview                  = [int]$record.flaggedForReview
                                isTenantRestricted                = [int]$record.isTenantRestricted
                                autonomousSystemNumber            = [int]$record.autonomousSystemNumber
                                crossTenantAccessType             = [string]$record.crossTenantAccessType
                                uniqueTokenIdentifier             = [string]$record.uniqueTokenIdentifier
                                incomingTokenType                 = [string]$record.incomingTokenType
                                authenticationProtocol            = [string]$record.authenticationProtocol
                                signInTokenProtectionStatus       = [string]$record.signInTokenProtectionStatus
                                originalTransferMethod            = [string]$record.originalTransferMethod
                                isThroughGlobalSecureAccess       = [int]$record.isThroughGlobalSecureAccess
                                globalSecureAccessIpAddress       = [string]$record.globalSecureAccessIpAddress
                                sessionId                         = [string]$record.sessionId
                                appOwnerTenantId                  = [string]$record.appOwnerTenantId
                                resourceOwnerTenantId             = [string]$record.resourceOwnerTenantId
                                status_errorCode                  = [int]$record.status.errorCode
                                status_failureReason              = [string]$record.status.failureReason
                                status_additionalDetails          = [string]$record.status.additionalDetails
                                deviceDetail_deviceId             = [string]$record.deviceDetail.deviceId
                                deviceDetail_displayName          = [string]$record.deviceDetail.displayName
                                deviceDetail_operatingSystem      = [string]$record.deviceDetail.operatingSystem
                                deviceDetail_browser              = [string]$record.deviceDetail.browser
                                deviceDetail_isCompliant          = [int]$record.deviceDetail.isCompliant
                                deviceDetail_isManaged            = [int]$record.deviceDetail.isManaged
                                deviceDetail_trustType            = [string]$record.deviceDetail.trustType
                                location_city                     = [string]$record.location.city
                                location_state                    = [string]$record.location.state
                                location_countryOrRegion          = [string]$record.location.countryOrRegion
                                location_geoCoordinates_latitude  = [double]$record.location.geoCoordinates.latitude
                                location_geoCoordinates_longitude = [double]$record.location.geoCoordinates.longitude
                            }
                            try {
                                Invoke-SqliteQuery -DataSource $DbPath -Query $insertQuery -SqlParameters $insertParams
                                $inserted++
                            } catch {
                                "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - Insert error: $_" | Add-Content $logPath
                                $totals.Errors++
                            }
                        }
                    }
                    $totals.$tableName += $inserted
                    & $OnProgress "  [$tableName] $inserted new records from $($file.Name)"
                    Move-Item -Path $file.FullName -Destination (Join-Path $finishedDir $file.Name) -Force
                } catch {
                    & $OnProgress "  [$tableName] ERROR: $($_.Exception.Message)"
                    "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss')) - $($_.Exception.Message)" | Add-Content $logPath
                    $totals.Errors++
                }
            }
        }
    } finally {
        $connection.Close()
    }

    return [PSCustomObject]@{
        InteractiveInserted    = $totals.Interactive
        NonInteractiveInserted = $totals.NonInteractive
        Errors                 = $totals.Errors
    }
}

function _Initialize-Database {
    param([string]$DbPath)
    if (-not (Test-Path $DbPath)) {
        $conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$DbPath;Version=3;")
        $conn.Open(); $conn.Close()
    }
}

function _Initialize-Table {
    param([string]$DbPath, [string]$TableName)
    $sql = @"
CREATE TABLE IF NOT EXISTS $TableName (
    id TEXT PRIMARY KEY, createdDateTime TEXT, userDisplayName TEXT, userPrincipalName TEXT,
    userId TEXT, appId TEXT, appDisplayName TEXT, ipAddress TEXT, clientAppUsed TEXT,
    userAgent TEXT, correlationId TEXT, conditionalAccessStatus TEXT, originalRequestId TEXT,
    isInteractive INTEGER, tokenIssuerName TEXT, tokenIssuerType TEXT, clientCredentialType TEXT,
    processingTimeInMilliseconds INTEGER, riskDetail TEXT, riskLevelAggregated TEXT,
    riskLevelDuringSignIn TEXT, riskState TEXT, resourceDisplayName TEXT, resourceId TEXT,
    resourceTenantId TEXT, homeTenantId TEXT, homeTenantName TEXT, authenticationRequirement TEXT,
    signInIdentifier TEXT, signInIdentifierType TEXT, servicePrincipalName TEXT, userType TEXT,
    flaggedForReview INTEGER, isTenantRestricted INTEGER, autonomousSystemNumber INTEGER,
    crossTenantAccessType TEXT, uniqueTokenIdentifier TEXT, incomingTokenType TEXT,
    authenticationProtocol TEXT, signInTokenProtectionStatus TEXT, originalTransferMethod TEXT,
    isThroughGlobalSecureAccess INTEGER, globalSecureAccessIpAddress TEXT, sessionId TEXT,
    appOwnerTenantId TEXT, resourceOwnerTenantId TEXT, status_errorCode INTEGER,
    status_failureReason TEXT, status_additionalDetails TEXT, deviceDetail_deviceId TEXT,
    deviceDetail_displayName TEXT, deviceDetail_operatingSystem TEXT, deviceDetail_browser TEXT,
    deviceDetail_isCompliant INTEGER, deviceDetail_isManaged INTEGER, deviceDetail_trustType TEXT,
    location_city TEXT, location_state TEXT, location_countryOrRegion TEXT,
    location_geoCoordinates_latitude REAL, location_geoCoordinates_longitude REAL
);
CREATE INDEX IF NOT EXISTS idx_id_$TableName ON $TableName (id);
"@
    Invoke-SqliteQuery -DataSource $DbPath -Query $sql
}

Export-ModuleMember -Function Invoke-ClientImport
