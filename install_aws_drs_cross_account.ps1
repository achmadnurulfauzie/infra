#requires -Version 3.0
<#
.SYNOPSIS
Installs the AWS Elastic Disaster Recovery Replication Agent on Windows.

.DESCRIPTION
Supports AccessKey authentication mode. Credentials must belong to the target/Central DRS account.
Does not use --account-id.

The script:
- Requires elevation.
- Enables TLS 1.2.
- Downloads the installer and SHA-512 hash from AWS with fallback URLs.
- Validates the installer checksum before execution.
- Optionally validates AccessKey credentials with AWS STS when AWS CLI exists.
- Removes temporary files and restores credential environment variables.

.EXAMPLE
$env:AWS_ACCESS_KEY_ID     = '<temporary-access-key>'
$env:AWS_SECRET_ACCESS_KEY = '<temporary-secret-key>'
$env:AWS_SESSION_TOKEN     = '<temporary-session-token>'
.\install-aws-drs-agent-cross-account.ps1
#>

[CmdletBinding()]
param(


    [ValidatePattern('^[a-z]{2}(?:-gov)?-[a-z]+-\d$')]
    [string]$Region = $(
        if (-not [string]::IsNullOrWhiteSpace($env:AWS_REGION)) {
            $env:AWS_REGION
        }
        elseif (-not [string]::IsNullOrWhiteSpace($env:AWS_DEFAULT_REGION)) {
            $env:AWS_DEFAULT_REGION
        }
        else {
            'ap-southeast-3'
        }
    ),

    [string]$AwsAccessKeyId = $env:AWS_ACCESS_KEY_ID,
    [string]$AwsSecretAccessKey = $env:AWS_SECRET_ACCESS_KEY,
    [string]$AwsSessionToken = $env:AWS_SESSION_TOKEN,

    # Example: C:,D:
    [string]$DrsDevices = $env:DRS_DEVICES,

    # Supported examples:
    # Environment=Production,SourceAccount=422032869525
    # {"Environment"="Production"},{"SourceAccount"="422032869525"}
    [string]$DrsTags = $env:DRS_TAGS,

    [bool]$ExcludeInstanceStoreVolumes = $true,

    # Prevent credential prompts when invoked by SSM or another automation.
    [switch]$NonInteractive
)

Set-StrictMode -Version 2.0
Set-PSDebug -Off
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$script:ExitCode = 0
$workDir = $null
$credentialEnvironmentBackup = @{}

function Write-Log {
    param([Parameter(Mandatory = $true)][string]$Message)
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ssK'
    Write-Host "[$timestamp] $Message"
}

function ConvertFrom-SecureStringPlainText {
    param([Parameter(Mandatory = $true)][Security.SecureString]$SecureString)

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-TemporaryProcessEnvironmentVariable {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowEmptyString()][string]$Value
    )

    if (-not $credentialEnvironmentBackup.ContainsKey($Name)) {
        $credentialEnvironmentBackup[$Name] = [Environment]::GetEnvironmentVariable($Name, 'Process')
    }

    if ([string]::IsNullOrEmpty($Value)) {
        [Environment]::SetEnvironmentVariable($Name, $null, 'Process')
    }
    else {
        [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
    }
}

function Restore-ProcessEnvironmentVariables {
    foreach ($entry in $credentialEnvironmentBackup.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
}

function Invoke-DownloadFirstAvailable {
    param(
        [Parameter(Mandatory = $true)][string[]]$Urls,
        [Parameter(Mandatory = $true)][string]$Destination,
        [ValidateRange(1, 10)][int]$AttemptsPerUrl = 3
    )

    foreach ($url in $Urls) {
        for ($attempt = 1; $attempt -le $AttemptsPerUrl; $attempt++) {
            $webClient = $null
            try {
                Write-Log "Downloading $(Split-Path -Leaf $Destination) from an AWS endpoint; attempt $attempt/$AttemptsPerUrl."
                $webClient = New-Object System.Net.WebClient
                $webClient.Headers['User-Agent'] = 'aws-drs-agent-bootstrap-windows/1.0'
                $webClient.DownloadFile($url, $Destination)

                if ((Test-Path -LiteralPath $Destination) -and
                    ((Get-Item -LiteralPath $Destination).Length -gt 0)) {
                    return
                }

                throw "The downloaded file is empty: $Destination"
            }
            catch {
                Write-Warning "Download failed from $($url): $($_.Exception.Message)"
                Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue
                if ($attempt -lt $AttemptsPerUrl) {
                    Start-Sleep -Seconds 2
                }
            }
            finally {
                if ($null -ne $webClient) {
                    $webClient.Dispose()
                }
            }
        }
    }

    throw "Download failed from every configured AWS endpoint. Check DNS, proxy, firewall, and outbound HTTPS/443 access."
}

function Get-Sha512Lowercase {
    param([Parameter(Mandatory = $true)][string]$Path)

    $sha512 = [Security.Cryptography.SHA512]::Create()
    $stream = $null
    try {
        $stream = [IO.File]::OpenRead($Path)
        $hashBytes = $sha512.ComputeHash($stream)
        return ([BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
        $sha512.Dispose()
    }
}

function Get-InstallerTagArguments {
    param([AllowEmptyString()][string]$RawTags)

    if ([string]::IsNullOrWhiteSpace($RawTags)) {
        return @()
    }

    $result = New-Object System.Collections.Generic.List[string]

    foreach ($rawTag in ($RawTags -split '\s*,\s*')) {
        $tag = $rawTag.Trim()
        if ([string]::IsNullOrWhiteSpace($tag)) {
            continue
        }

        # Preserve already formatted AWS DRS tag expressions.
        if ($tag -match '^\{.+\}$') {
            [void]$result.Add($tag)
            continue
        }

        $parts = $tag -split '=', 2
        if ($parts.Count -ne 2 -or
            [string]::IsNullOrWhiteSpace($parts[0]) -or
            [string]::IsNullOrWhiteSpace($parts[1])) {
            throw "Invalid DRS tag '$tag'. Use Key=Value pairs separated by commas."
        }

        $key = $parts[0].Trim()
        $value = $parts[1].Trim().Trim('"')

        if ($key -match '["{}]') {
            throw "Invalid characters in DRS tag key '$key'."
        }
        if ($value -match '["{}]') {
            throw "Invalid characters in DRS tag value for key '$key'."
        }

        [void]$result.Add(('{"' + $key + '"="' + $value + '"}'))
    }

    return $result.ToArray()
}

try {
    if (-not (Test-IsAdministrator)) {
        throw 'Run this script from an elevated PowerShell session as Administrator.'
    }

    # AWS requires TLS 1.2 or later. Keep any currently enabled protocol flags.
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    $osVersion = [Environment]::OSVersion.Version
    $installerSubPath = 'windows/AwsReplicationWindowsInstaller.exe'

    if ($osVersion.Major -eq 6) {
        if ($osVersion.Minor -eq 1) {
            $installerSubPath = 'windows_legacy/windows_2008_legacy/AwsReplicationWindows2008LegacyInstaller.exe'
            Write-Log 'Legacy Windows Server 2008 R2 / Windows 7 detected. Using legacy installer.'
        }
        elseif ($osVersion.Minor -eq 2 -or $osVersion.Minor -eq 3) {
            $installerSubPath = 'windows_legacy/windows_2012_legacy/AwsReplicationWindows2012LegacyInstaller.exe'
            Write-Log 'Legacy Windows Server 2012 / 2012 R2 detected. Using legacy installer.'
        }
        else {
            throw "Unsupported legacy Windows version: $osVersion"
        }
    }

    $workDir = Join-Path ([IO.Path]::GetTempPath()) ("aws-drs-agent-" + [Guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $workDir -Force)

    $installerFilename = Split-Path -Leaf $installerSubPath
    $installerPath = Join-Path $workDir $installerFilename
    $hashPath = Join-Path $workDir "$installerFilename.sha512"

    Write-Log "AWS Region     : $Region"
    Write-Log "Windows        : $([Environment]::OSVersion.VersionString)"

    if ([string]::IsNullOrWhiteSpace($AwsAccessKeyId)) {
        if ($NonInteractive) {
            throw 'AWS_ACCESS_KEY_ID is empty in non-interactive mode.'
        }
        $AwsAccessKeyId = Read-Host "AWS Access Key ID"
    }

    if ([string]::IsNullOrWhiteSpace($AwsSecretAccessKey)) {
        if ($NonInteractive) {
            throw 'AWS_SECRET_ACCESS_KEY is empty in non-interactive mode.'
        }
        $AwsSecretAccessKey = ConvertFrom-SecureStringPlainText (
            Read-Host "AWS Secret Access Key" -AsSecureString
        )
    }

    if ([string]::IsNullOrWhiteSpace($AwsSessionToken) -and -not $NonInteractive) {
        $sessionTokenSecure = Read-Host 'AWS Session Token; press Enter only when using a long-term access key' -AsSecureString
        $AwsSessionToken = ConvertFrom-SecureStringPlainText $sessionTokenSecure
    }

    if ([string]::IsNullOrWhiteSpace($AwsAccessKeyId)) {
        throw 'AWS_ACCESS_KEY_ID is empty.'
    }
    if ([string]::IsNullOrWhiteSpace($AwsSecretAccessKey)) {
        throw 'AWS_SECRET_ACCESS_KEY is empty.'
    }

    Set-TemporaryProcessEnvironmentVariable -Name 'AWS_ACCESS_KEY_ID' -Value $AwsAccessKeyId
    Set-TemporaryProcessEnvironmentVariable -Name 'AWS_SECRET_ACCESS_KEY' -Value $AwsSecretAccessKey
    Set-TemporaryProcessEnvironmentVariable -Name 'AWS_SESSION_TOKEN' -Value $AwsSessionToken
    Set-TemporaryProcessEnvironmentVariable -Name 'AWS_REGION' -Value $Region
    Set-TemporaryProcessEnvironmentVariable -Name 'AWS_DEFAULT_REGION' -Value $Region

    $awsCommand = Get-Command aws.exe -ErrorAction SilentlyContinue
    if ($null -eq $awsCommand) {
        $awsCommand = Get-Command aws -ErrorAction SilentlyContinue
    }

    if ($null -ne $awsCommand) {
        Write-Log 'Validating credential ownership with AWS STS.'
        $callerAccountOutput = & $awsCommand.Source sts get-caller-identity `
            --region $Region `
            --query Account `
            --output text 2>$null
        $stsExitCode = $LASTEXITCODE
        $callerAccount = (($callerAccountOutput | Out-String).Trim())

        if ($stsExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($callerAccount)) {
            throw 'Credentials are invalid, expired, or STS is unreachable.'
        }
    }
    else {
        Write-Warning 'AWS CLI is not installed; credential validation with STS is skipped.'
    }

    $installerUrls = @(
        "https://aws-elastic-disaster-recovery-${Region}.s3.${Region}.amazonaws.com/latest/$installerSubPath",
        "https://aws-elastic-disaster-recovery-${Region}.s3.dualstack.${Region}.amazonaws.com/latest/$installerSubPath"
    )

    $hashUrls = @(
        "https://aws-elastic-disaster-recovery-hashes-${Region}.s3.${Region}.amazonaws.com/latest/${installerSubPath}.sha512",
        "https://aws-elastic-disaster-recovery-hashes-${Region}.s3.dualstack.${Region}.amazonaws.com/latest/${installerSubPath}.sha512"
    )

    Invoke-DownloadFirstAvailable -Urls $hashUrls -Destination $hashPath
    Invoke-DownloadFirstAvailable -Urls $installerUrls -Destination $installerPath

    $hashContent = (Get-Content -LiteralPath $hashPath -Raw).Trim()
    $expectedHash = (($hashContent -split '\s+')[0]).Trim().ToLowerInvariant()
    $computedHash = Get-Sha512Lowercase -Path $installerPath

    if ($expectedHash -notmatch '^[0-9a-f]{128}$') {
        throw 'The SHA-512 value downloaded from AWS has an invalid format.'
    }
    if ($computedHash -ne $expectedHash) {
        throw 'Checksum validation failed. The installer will not be executed.'
    }

    Write-Log 'SHA-512 checksum is valid.'

    $installArguments = New-Object System.Collections.Generic.List[string]
    [void]$installArguments.Add('--no-prompt')
    [void]$installArguments.Add('--region')
    [void]$installArguments.Add($Region)

    # Use AccessKey credentials.
    [void]$installArguments.Add('--aws-access-key-id')
    [void]$installArguments.Add($AwsAccessKeyId)
    [void]$installArguments.Add('--aws-secret-access-key')
    [void]$installArguments.Add($AwsSecretAccessKey)

    if (-not [string]::IsNullOrWhiteSpace($AwsSessionToken)) {
        [void]$installArguments.Add('--aws-session-token')
        [void]$installArguments.Add($AwsSessionToken)
    }

    if ($ExcludeInstanceStoreVolumes) {
        [void]$installArguments.Add('--exclude-instance-store-volumes')
    }

    if (-not [string]::IsNullOrWhiteSpace($DrsDevices)) {
        [void]$installArguments.Add('--devices')
        [void]$installArguments.Add($DrsDevices)
    }

    $tagArguments = @(Get-InstallerTagArguments -RawTags $DrsTags)
    if ($tagArguments.Count -gt 0) {
        [void]$installArguments.Add('--tags')
        foreach ($tagArgument in $tagArguments) {
            [void]$installArguments.Add($tagArgument)
        }
    }

    Write-Log 'Starting the AWS DRS Replication Agent installer.'
    $nativeArguments = $installArguments.ToArray()
    & $installerPath @nativeArguments
    $installerExitCode = $LASTEXITCODE

    if ($installerExitCode -ne 0) {
        throw "AWS DRS installer failed with exit code $installerExitCode."
    }

    Write-Log "Installer completed. Verify that the source server appears in AWS DRS, region $Region."
    Write-Log 'Wait for Initial Sync, validate replication lag and selected disks, then perform a drill before production failover.'
}
catch {
    $script:ExitCode = 1
    Write-Error $_.Exception.Message -ErrorAction Continue
    if (-not [string]::IsNullOrWhiteSpace($_.ScriptStackTrace)) {
        Write-Error $_.ScriptStackTrace -ErrorAction Continue
    }
}
finally {
    if (-not [string]::IsNullOrWhiteSpace($workDir) -and (Test-Path -LiteralPath $workDir)) {
        Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    Restore-ProcessEnvironmentVariables

    # Reduce the lifetime of plaintext references within this PowerShell process.
    $AwsAccessKeyId = $null
    $AwsSecretAccessKey = $null
    $AwsSessionToken = $null
}

exit $script:ExitCode
