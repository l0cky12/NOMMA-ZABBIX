[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Shares', 'DnsSrv', 'ReplicationFailures', 'ReplicationAge')]
    [string]$Check
)

$ErrorActionPreference = 'Stop'

try {
    switch ($Check) {
        'Shares' {
            # 0 = SYSVOL and NETLOGON shares both exist; 1 = either share is absent.
            $sysvol = Get-SmbShare -Name 'SYSVOL' -ErrorAction SilentlyContinue
            $netlogon = Get-SmbShare -Name 'NETLOGON' -ErrorAction SilentlyContinue

            if ($sysvol -and $netlogon) { 0 } else { 1 }
        }

        'DnsSrv' {
            # Query local DNS for the AD LDAP service record.
            $domain = (Get-CimInstance Win32_ComputerSystem).Domain
            $record = "_ldap._tcp.dc._msdcs.$domain"
            $result = Resolve-DnsName -Name $record -Type SRV -Server 127.0.0.1 -DnsOnly -ErrorAction Stop

            if ($result) { 0 } else { 1 }
        }

        'ReplicationFailures' {
            Import-Module ActiveDirectory -ErrorAction Stop
            $partners = @(Get-ADReplicationPartnerMetadata -Target $env:COMPUTERNAME -Scope Server)

            # A single-DC domain has no partners. It is healthy, but this template should not be linked yet.
            if ($partners.Count -eq 0) { 0; break }

            @($partners | Where-Object { $_.LastReplicationResult -ne 0 }).Count
        }

        'ReplicationAge' {
            Import-Module ActiveDirectory -ErrorAction Stop
            $partners = @(Get-ADReplicationPartnerMetadata -Target $env:COMPUTERNAME -Scope Server)

            if ($partners.Count -eq 0) { 0; break }

            $oldestSuccess = @(
                $partners |
                    Where-Object { $_.LastReplicationSuccess } |
                    Select-Object -ExpandProperty LastReplicationSuccess |
                    Sort-Object |
                    Select-Object -First 1
            )

            if ($oldestSuccess.Count -eq 0) {
                -1
            }
            else {
                [int]((New-TimeSpan -Start $oldestSuccess[0] -End (Get-Date)).TotalSeconds)
            }
        }
    }
}
catch {
    # Any script or AD query failure is unhealthy. -1 distinguishes age-query failure.
    if ($Check -eq 'ReplicationAge') { -1 } else { 1 }
}
