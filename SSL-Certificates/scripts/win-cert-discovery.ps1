<#
.SYNOPSIS
    Zabbix low-level discovery and expiry reporter for Windows machine
    certificates.

.DESCRIPTION
    Read-only helper for the "NOMMA SSL Certificates by Zabbix Agent 2"
    template. It never writes files, never touches the registry and never
    starts or stops a service.

    Scope is deliberately narrow: Cert:\LocalMachine\My only. CurrentUser and
    every CA / Root / intermediate store are skipped, because those are trust
    anchors rather than certificates this server serves.

    Modes:
        discover  Emits Zabbix LLD JSON, one row per certificate.
        expiry    Emits the whole number of days until the certificate with
                  the given thumbprint expires (negative once expired).

    PowerShell 5.1 compatible and safe to run through Action1: no
    [CmdletBinding()], no typed parameters, no advanced-function features.

.PARAMETER Mode
    discover (default) or expiry.

.PARAMETER Thumbprint
    Certificate thumbprint, required for -Mode expiry. Spaces, colons and
    case are normalised away.

.PARAMETER StorePath
    Certificate store to read. Defaults to Cert:\LocalMachine\My and should
    not normally be changed.

.EXAMPLE
    .\win-cert-discovery.ps1
    .\win-cert-discovery.ps1 -Mode expiry -Thumbprint A1B2C3...
#>

param(
    $Mode = "discover",
    $Thumbprint = "",
    $StorePath = "Cert:\LocalMachine\My"
)

# ---- Helpers ----------------------------------------------------------------

function ConvertTo-JsonSafeString {
    param($Text)

    if ($null -eq $Text) { return "" }

    $s = [string]$Text
    $s = $s.Replace('\', '\\')
    $s = $s.Replace('"', '\"')
    $s = $s.Replace("`r", ' ')
    $s = $s.Replace("`n", ' ')
    $s = $s.Replace("`t", ' ')

    return $s
}

function Get-CertCommonName {
    param($Cert)

    $cn = ""

    try {
        $cn = $Cert.GetNameInfo(
            [System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName,
            $false)
    }
    catch {
        $cn = ""
    }

    if ([string]::IsNullOrEmpty($cn)) {
        $subject = [string]$Cert.Subject
        $match = [regex]::Match($subject, 'CN\s*=\s*([^,]+)')
        if ($match.Success) {
            $cn = $match.Groups[1].Value.Trim()
        }
    }

    if ([string]::IsNullOrEmpty($cn)) {
        $cn = [string]$Cert.Thumbprint
    }

    return $cn
}

function Get-CertNotAfterString {
    param($Cert)

    $invariant = [System.Globalization.CultureInfo]::InvariantCulture
    return $Cert.NotAfter.ToString("yyyy-MM-dd HH:mm:ss", $invariant)
}

function Get-CertDaysRemaining {
    param($Cert)

    $span = $Cert.NotAfter - (Get-Date)
    return [int][math]::Floor($span.TotalDays)
}

function Get-MachineCertificates {
    param($Path)

    $result = @()

    try {
        $result = @(Get-ChildItem -Path $Path -ErrorAction Stop |
            Where-Object { $null -ne $_.Thumbprint })
    }
    catch {
        [Console]::Error.WriteLine("win-cert-discovery.ps1 ${Path}: store not readable - $($_.Exception.Message)")
        $result = @()
    }

    return $result
}

function Get-NormalisedThumbprint {
    param($Value)

    if ($null -eq $Value) { return "" }
    return ([string]$Value -replace '[^0-9A-Fa-f]', '').ToUpper()
}

# ---- Mode: discover ---------------------------------------------------------

function Invoke-Discover {
    param($Path)

    $storeLabel = ConvertTo-JsonSafeString $Path
    $rows = New-Object System.Collections.ArrayList

    foreach ($cert in (Get-MachineCertificates -Path $Path)) {
        $thumbprint = ConvertTo-JsonSafeString $cert.Thumbprint
        $commonName = ConvertTo-JsonSafeString (Get-CertCommonName -Cert $cert)
        $subject    = ConvertTo-JsonSafeString $cert.Subject
        $issuer     = ConvertTo-JsonSafeString $cert.Issuer
        $notAfter   = ConvertTo-JsonSafeString (Get-CertNotAfterString -Cert $cert)
        $days       = [string](Get-CertDaysRemaining -Cert $cert)

        $row = '{'
        $row = $row + '"{#TLS.CERT.THUMBPRINT}":"' + $thumbprint + '",'
        $row = $row + '"{#TLS.CERT.CN}":"' + $commonName + '",'
        $row = $row + '"{#TLS.CERT.SUBJECT}":"' + $subject + '",'
        $row = $row + '"{#TLS.CERT.ISSUER}":"' + $issuer + '",'
        $row = $row + '"{#TLS.CERT.NOTAFTER}":"' + $notAfter + '",'
        $row = $row + '"{#TLS.CERT.STORE}":"' + $storeLabel + '",'
        $row = $row + '"{#TLS.CERT.DAYS}":"' + $days + '"'
        $row = $row + '}'

        $null = $rows.Add($row)
    }

    Write-Output ('[' + ($rows -join ',') + ']')
}

# ---- Mode: expiry -----------------------------------------------------------

function Invoke-Expiry {
    param($Path, $WantedThumbprint)

    $wanted = Get-NormalisedThumbprint -Value $WantedThumbprint

    if ($wanted.Length -eq 0) {
        [Console]::Error.WriteLine("win-cert-discovery.ps1 expiry: -Thumbprint is required")
        exit 1
    }

    foreach ($cert in (Get-MachineCertificates -Path $Path)) {
        if ((Get-NormalisedThumbprint -Value $cert.Thumbprint) -eq $wanted) {
            Write-Output ([string](Get-CertDaysRemaining -Cert $cert))
            exit 0
        }
    }

    [Console]::Error.WriteLine("win-cert-discovery.ps1 ${wanted}: certificate not found in $Path")
    exit 1
}

# ---- Dispatch ---------------------------------------------------------------

$requestedMode = ([string]$Mode).Trim().ToLower()

switch ($requestedMode) {
    "discover" {
        Invoke-Discover -Path $StorePath
        exit 0
    }
    "expiry" {
        Invoke-Expiry -Path $StorePath -WantedThumbprint $Thumbprint
        exit 0
    }
    default {
        [Console]::Error.WriteLine("win-cert-discovery.ps1 ${requestedMode}: unknown mode, expected discover or expiry")
        exit 1
    }
}
