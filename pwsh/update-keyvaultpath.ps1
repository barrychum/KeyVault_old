
param (
    [string]$path
)

function Read-Ini {
    <#
    .SYNOPSIS
        Reads key-value pairs from an INI configuration file.
    .DESCRIPTION
        Parses an INI file and sets variables in the script scope accordingly.
    .PARAMETER iniFile
        Specifies the path to the INI configuration file.
    #>

    param (
        [string]$iniFile
    )

    $section = ""
    Get-Content $iniFile | ForEach-Object {
        $line = $_.Trim()

        if ($line -eq "" -or $line.StartsWith("#")) {
            return
        }

        if ($line -match '^\[.*\]$') {
            $section = $line -replace '[\[\]]', ''
            return
        }

        if ($line -match '^[^=]+=') {
            $key, $value = $line -split '=', 2
            $key = $key.Trim()
            $value = $value.Trim()
            if ($section) {
                $key = "${section}_${key}"
            }
            Set-Variable -Name "ini_$key" -Value $value -Scope Script
        }
    }
}

function Show-Usage {

    Write-Host "Usage: $($MyInvocation.MyCommand.Name)"

    exit 1
}

function Get-KeyValueInFile {
    <#
    .SYNOPSIS
        Retrieves the value associated with a specific key from a file.
    .DESCRIPTION
        Searches for a key-value pair in a file and returns the corresponding value.
    .PARAMETER key
        Specifies the key whose value is to be retrieved.
    .PARAMETER fileLocation
        Specifies the path to the file where the key-value pairs are stored.
    #>

    param (
        [string]$key,
        [string]$fileLocation
    )

    $value = Get-Content $fileLocation | 
    Where-Object { $_ -match "^$key=" } | 
    ForEach-Object { $_.Split('=', 2)[1] }
    return $value
}

function Test-KeyExistsInFile {
    <#
    .SYNOPSIS
        Checks if a key exists in a specific file.
    .DESCRIPTION
        Searches for the presence of a key in a file and returns true if found, false otherwise.
    .PARAMETER key
        Specifies the key to search for.
    .PARAMETER fileLocation
        Specifies the path to the file where the key is expected to be found.
    #>

    param (
        [string]$key,
        [string]$fileLocation
    )

    return (Select-String -Path $fileLocation -Pattern "^$key=" -Quiet)
}

# Main Script Execution
$KEYVAULT_DIR = if ($path) { $path } else { Join-Path $env:LOCALAPPDATA "keyvault" }
$KEYVAULT_CONFIG = Join-Path $KEYVAULT_DIR "config.ini"

Read-Ini $KEYVAULT_CONFIG

$iniFile = Split-Path -Path $ini_keyvault_db -Leaf
$escapedLast = [regex]::Escape($iniFile)
$oldPath = [regex]::Replace($ini_keyvault_db, "$escapedLast$", '')
"Old path: $oldPath"

$currentIniPath = (Split-Path -Path $KEYVAULT_CONFIG -Parent) + '\'
"Ini path: $currentIniPath"

$newPath = Read-Host "Enter new path or 'enter' to use the current location of ini"


if ( $newPath ) {
    "new path provided"

    # Get a proper formatted newPath format
    $newPath = (Split-Path -Path (Join-Path $newPath "fakefile") -Parent) + '\'

    "Replacing: $oldPath --> $newPath"
    
    $fileContent = Get-Content -Path $KEYVAULT_CONFIG
    $escapedOldPath = [regex]::Escape($oldPath)
    $newContent = $fileContent -replace $escapedOldPath, $newPath
    Set-Content -Path $KEYVAULT_CONFIG -Value $newContent
}
else {
    # Ensure a trailing backslash
    $newPath = (Split-Path -Path $KEYVAULT_CONFIG -Parent) + '\'

    "Replacing: $oldPath --> $newPath"

    $fileContent = Get-Content -Path $KEYVAULT_CONFIG
    $escapedOldPath = [regex]::Escape($oldPath)
    $newContent = $fileContent -replace $escapedOldPath, $newPath
    Set-Content -Path $KEYVAULT_CONFIG -Value $newContent
}