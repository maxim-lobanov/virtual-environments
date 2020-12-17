function Choco-Install {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $PackageName,
        [string[]] $ArgumentList,
        [int] $RetryCount = 5
    )

    process {
        Write-Host "Running [#$count]: choco install $packageName -y $argumentList"
        choco install $packageName -y @argumentList
    }
}