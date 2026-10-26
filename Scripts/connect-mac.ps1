<#
.SYNOPSIS
    Opens the EC2 Mac desktop in RealVNC Viewer through an SSH tunnel.

.DESCRIPTION
    Port 5900 (Screen Sharing) is never opened to the internet: the viewer connects to
    localhost, and SSH carries the traffic to the Mac. Close this window (or press Ctrl+C)
    to close the tunnel.

    One-time setup on the Mac first: bash Scripts/mac-enable-screen-sharing.sh

.EXAMPLE
    .\Scripts\connect-mac.ps1 -MacHost ec2-1-2-3-4.eu-central-1.compute.amazonaws.com -KeyPath C:\keys\mac.pem
#>
param(
    [Parameter(Mandatory = $true)] [string] $MacHost,
    [Parameter(Mandatory = $true)] [string] $KeyPath,
    [int] $LocalPort = 5900,
    [string] $User = "ec2-user"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $KeyPath)) {
    throw "Key file not found: $KeyPath"
}

$viewer = Join-Path $env:ProgramFiles "RealVNC\RealVNC Connect\rvncconnect.exe"
if (-not (Test-Path -LiteralPath $viewer)) {
    throw "RealVNC Viewer not found. Install it with: winget install --id RealVNC.VNCViewer --exact"
}

$busy = Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue
if ($busy) {
    throw "Local port $LocalPort is already in use. Run again with -LocalPort 5901."
}

Write-Host "Opening SSH tunnel localhost:$LocalPort -> ${MacHost}:5900 ..."
$sshArgs = @(
    "-i", $KeyPath,
    "-N",
    "-o", "ExitOnForwardFailure=yes",
    "-o", "ServerAliveInterval=30",
    "-L", "${LocalPort}:localhost:5900",
    "$User@$MacHost"
)
$tunnel = Start-Process -FilePath "ssh" -ArgumentList $sshArgs -PassThru -NoNewWindow

try {
    # Wait until the tunnel listens locally (max ~15 s).
    $ready = $false
    for ($i = 0; $i -lt 30 -and -not $tunnel.HasExited; $i++) {
        if (Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue) {
            $ready = $true
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) {
        throw "SSH tunnel did not start. Check the host name, key file and that the instance is running."
    }

    Write-Host "Tunnel ready. Starting RealVNC Viewer: localhost:$LocalPort"
    Write-Host "If the viewer opens without connecting, type localhost:$LocalPort in its address bar."
    Write-Host "A RealVNC account is not needed for this direct connection; skip the sign-in offer."
    Write-Host "Sign in to the Mac with user '$User' and the password set by mac-enable-screen-sharing.sh."
    Start-Process -FilePath $viewer -ArgumentList "localhost:$LocalPort"

    Write-Host "Keep this window open while you work. Press Ctrl+C to close the tunnel."
    Wait-Process -Id $tunnel.Id
}
finally {
    if (-not $tunnel.HasExited) {
        Stop-Process -Id $tunnel.Id -Force
    }
    Write-Host "Tunnel closed."
}
