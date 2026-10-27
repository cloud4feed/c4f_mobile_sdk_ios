<#
.SYNOPSIS
    Opens the EC2 Mac desktop in TigerVNC through an SSH tunnel (one click).

.DESCRIPTION
    Port 5900 (Screen Sharing) is never opened to the internet: the viewer connects to
    localhost:5900 and SSH carries the traffic to the Mac. The tunnel stays up while the viewer
    is open and closes with it.

    Sign in with user "ec2-user" and the Mac password (Scripts/mac-enable-screen-sharing.sh).
    RealVNC does not work with macOS Tahoe 26.6+ ("key length too large"); TigerVNC does.

.EXAMPLE
    .\Scripts\connect-mac.ps1
    .\Scripts\connect-mac.ps1 -MacHost 1.2.3.4 -KeyPath C:\keys\mac.pem
#>
param(
    [string] $MacHost = "3.68.218.129",
    [string] $KeyPath = "$env:USERPROFILE\.ssh\mobilesdk_ios.pem",
    [string] $HostKeyAlias = "ec2-3-68-218-129.eu-central-1.compute.amazonaws.com",
    [int] $LocalPort = 5900,
    [string] $User = "ec2-user"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $KeyPath)) { throw "Key file not found: $KeyPath" }
$viewer = Join-Path $env:ProgramFiles "TigerVNC\vncviewer.exe"
if (-not (Test-Path -LiteralPath $viewer)) {
    throw "TigerVNC not found. Install it with: winget install --id TigerVNC.TigerVNC --exact"
}

$tunnel = $null
$listening = Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue
if ($listening) {
    Write-Host "A tunnel is already listening on localhost:$LocalPort, reusing it."
} else {
    Write-Host "Opening SSH tunnel localhost:$LocalPort -> ${MacHost}:5900 ..."
    $sshArgs = @("-i", $KeyPath, "-N",
                 "-o", "ExitOnForwardFailure=yes", "-o", "ServerAliveInterval=30",
                 "-o", "HostKeyAlias=$HostKeyAlias",
                 "-L", "${LocalPort}:localhost:5900", "$User@$MacHost")
    $tunnel = Start-Process -FilePath "ssh" -ArgumentList $sshArgs -PassThru -WindowStyle Hidden
    $ready = $false
    for ($i = 0; $i -lt 30 -and -not $tunnel.HasExited; $i++) {
        if (Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue) { $ready = $true; break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) {
        throw "SSH tunnel did not start. Is the instance running, and is your current IP allowed in the security group?"
    }
}

Write-Host "Starting TigerVNC: localhost:$LocalPort (user $User, Mac password)"
$view = Start-Process -FilePath $viewer -ArgumentList "localhost:$LocalPort" -PassThru
try {
    Wait-Process -Id $view.Id
} finally {
    if ($tunnel -and -not $tunnel.HasExited) { Stop-Process -Id $tunnel.Id -Force }
    Write-Host "Viewer closed; tunnel closed."
}
