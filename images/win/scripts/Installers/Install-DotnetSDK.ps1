################################################################################
##  File:  Install-DotnetSDK.ps1
##  Desc:  Install all released versions of the dotnet sdk and populate package
##         cache.  Should run after VS and Node
################################################################################

# Set environment variables
Set-SystemVariable -SystemVariable DOTNET_MULTILEVEL_LOOKUP -Value "0"

[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor "Tls12"

function Get-AvailableSDKVersions {
    $dotnetVersions = (Get-ToolsetContent).dotnet.versions
    $sdkList = [System.Collections.Generic.List[string]]::New()
    $dotnetVersions | ForEach-Object {
        $releasesUrl = "https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/$_/releases.json"
        $releases = Invoke-RestMethod $releasesUrl
        $sdkList.AddRange([Collections.Generic.List[String]]$releases.releases.sdk.version)
        $sdkList.AddRange([Collections.Generic.List[String]]$releases.releases.sdks.version)
    }

    # exclude all preview and rc versions
    $stableSdkList = $sdkList | Select-String -Pattern 'preview|rc|display' -NotMatch | Select-Object -ExpandProperty Line
    return $stableSdkList | Sort-Object { [Version]$_ }
}

function Install-InstallerScript {
    $installerUrl = "https://dot.net/v1/dotnet-install.ps1"
    return Start-DownloadWithRetry -Url $installerUrl
}

function Invoke-ApplyWorkaround1276 {
    param(
        [string[]] $SdkVersions
    )

    $sdkTargetsName = "Microsoft.NET.Sdk.ImportPublishProfile.targets"
    $sdkTargetsUrl = "https://raw.githubusercontent.com/dotnet/sdk/82bc30c99f1325dfaa7ad450be96857a4fca2845/src/Tasks/Microsoft.NET.Build.Tasks/targets/${sdkTargetsName}"
    $sdkTargetsLocalPath = Start-DownloadWithRetry -Url $sdkTargetsUrl
    $SdkVersions | ForEach-Object {
        $sdkTargetsPath = "C:\Program Files\dotnet\sdk\$_\Sdks\Microsoft.NET.Sdk\targets\$sdkTargetsName"
        Copy-Item -Path $sdkTargetsLocalPath -Destination $sdkTargetsPath
    }
}

function Invoke-WarmupDotNet {
    param(
        [String] $Version
    )

    $templates = @('console', 'mstest', 'web', 'mvc', 'webapi')
    $tempRootDirectory = Join-Path $env:TEMP "dotnet-$Version"
    New-Item -Path $tempRootDirectory -ItemType Directory -Force | Out-Null

    $templates | ForEach-Object {
        $template = $_
        $templateDirectory = Join-Path $tempRootDirectory $template
        New-Item -Path $templateDirectory -ItemType Directory -Force | Out-Null
        Push-Location -Path $templateDirectory
        & dotnet new globaljson --sdk-version $Version
        & dotnet new $template
        Pop-Location
    }

    Remove-Item -Path $tempRootDirectory -Recurse -Force
}

function RunPostInstallationSteps()
{
    Add-MachinePathItem "C:\Program Files\dotnet"
    # Run script at startup for all users
    $cmdDotNet = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -Command "[System.Environment]::SetEnvironmentVariable(''PATH'',"""$env:USERPROFILE\.dotnet\tools;$env:PATH""", ''USER'')"'

    # Update Run key to run a script at logon
    Set-ItemProperty -Path "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run" -Name "DOTNETUSERPATH" -Value $cmdDotNet
}

$installerScriptPath = Install-InstallerScript
$sdkVersions = Get-AvailableSDKVersions

Write-Host "Installing the following dotnet versions:"
Write-Host ($sdkVersions -join ", ")
$installationDirectory = Join-Path -Path $env:ProgramFiles -ChildPath 'dotnet'
$sdkVersions | ForEach-Object {
    Write-Host "Installing dotnet $_"
    & $installerScriptPath -Architecture x64 -Version $_ -InstallDir $installationDirectory
}

# Fix for issue 1276.  This will be fixed in 3.1.
Write-Host "Apply workaround for Microsoft.NET.Sdk.ImportPublishProfile.targets"
Invoke-ApplyWorkaround1276 -SdkVersions $sdkVersions

# Warm up is necessary to speed up customers' builds on Hosted agents
# It initializes every project type for every dotnet
# Under hood, it downloads and cached NuGet packages that are used by default in .NET projects
# C:\Users\testAdm2\.nuget\packages
# C:\Program Files (x86)\Microsoft SDKs\NuGetPackages
Write-Host "Invoking warm up for every SDK version..."
$sdkVersions | ForEach-Object {
    Write-Host "Invoke warm up for dotnet $_"
    #Invoke-WarmupDotNet -Version $_
}

# Add "$env:USERPROFILE\.dotnet\tools" to PATH
RunPostInstallationSteps

Invoke-PesterTests -TestFile "DotnetSDK"