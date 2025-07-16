<#
.SYNOPSIS
  Bulk-remove specific client secrets from Azure AD (Entra) App Registrations based on a CSV input.

.PARAMETER CsvPath
  Path to a CSV file containing columns: AppId, SecretKeyId

.EXAMPLE
  .\Remove-AppSecretsFromCsv.ps1 -CsvPath "C:\temp\secrets-to-remove.csv"
#>

param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$CsvPath
)

# 1. Ensure CSV exists
if (-not (Test-Path $CsvPath)) {
    Throw "CSV file not found at path: $CsvPath"
}

# 2. Ensure the Graph Applications module is available
if (-not (Get-Module -ListAvailable -Name Microsoft.Graph.Applications)) {
    Write-Host "Installing Microsoft.Graph.Applications module…" -ForegroundColor Yellow
    Install-Module Microsoft.Graph.Applications -Scope CurrentUser -Force
}
Import-Module Microsoft.Graph.Applications -ErrorAction Stop

# 3. Connect to Microsoft Graph
Connect-MgGraph -Scopes "Application.ReadWrite.All"

# 4. Import CSV
$entries = Import-Csv -Path $CsvPath
if ($entries.Count -eq 0) {
    Write-Warning "CSV file contains no entries."
    Disconnect-MgGraph
    exit 0
}

# 5. Process each row
foreach ($row in $entries) {
    $appId       = $row.AppId.Trim()
    $secretKeyId = $row.SecretKeyId.Trim()

    if (-not [Guid]::TryParse($secretKeyId, [ref]$null)) {
        Write-Warning "Skipping invalid SecretKeyId '$secretKeyId' for AppId '$appId'."
        continue
    }

    Write-Host "→ AppId: $appId | SecretKeyId: $secretKeyId" -ForegroundColor Cyan

    # Fetch the application
    $app = Get-MgApplication -Filter "appId eq '$appId'" -ErrorAction SilentlyContinue
    if (-not $app) {
        Write-Warning "  • Application with AppId '$appId' not found."
        continue
    }

    # Verify the secret exists
    $secret = $app.PasswordCredentials | Where-Object KeyId -EQ $secretKeyId
    if (-not $secret) {
        Write-Warning "  • No secret with KeyId '$secretKeyId' found on '$($app.DisplayName)'."
        continue
    }

    # Remove the secret
    try {
        Remove-MgApplicationPassword -ApplicationId $app.Id -KeyId $secretKeyId -ErrorAction Stop
        Write-Host "  ✅ Removed secret from '$($app.DisplayName)'." -ForegroundColor Green
    }
    catch {
        Write-Error "  ✖ Failed to remove SecretKeyId '$secretKeyId' from '$($app.DisplayName)': $_"
    }
}

# 6. Disconnect
Disconnect-MgGraph
Write-Host "Done." -ForegroundColor Yellow
