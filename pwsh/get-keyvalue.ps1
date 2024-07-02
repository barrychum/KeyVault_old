param (
    [Parameter(Position = 0, Mandatory = $true)]
    [string]$key
)

$KEYVAULT_DIR = "$env:LOCALAPPDATA\keyvault"
$KEYVAULT_CONFIG = "$KEYVAULT_DIR\config.ini"

function Read-Ini {
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
    Write-Host "Usage: $($MyInvocation.MyCommand.Name) <key> [-display]"
    Write-Host "Use -display if password is not displayed properly"
    exit 1
}

function Get-KeyValueInFile {
    param (
        [string]$key,
        [string]$fileLocation
    )

    $value = Get-Content $fileLocation | 
    Where-Object { $_ -match "^$key=" } | 
    ForEach-Object { $_.Split('=', 2)[1] }
    return $value
}

function Read-SecurePassword {
    $securePassword = Read-Host "Enter a password:" -AsSecureString
    $password = ConvertFrom-SecureString $securePassword -AsPlainText
    return $password
}

function Get-Password {
    # Try to get the password from Windows Credential Manager
    $credential = Get-StoredCredential -Target "$Script:ini_keychain_service" | Where-Object { $_.username -eq "$Script:ini_keychain_account" }
    if ($credential) {
        Write-Host "Private key password obtained from Credential Manager" -ForegroundColor Yellow
        return ConvertFrom-SecureString -SecureString $credential.password -AsPlainText
    }
    else {
        Write-Host "Private key password not in Credential Manager. Please enter private key password: " -ForegroundColor Yellow
        return Read-SecurePassword
    }
}

function Test-KeyExistsInFile {
    param (
        [string]$key,
        [string]$fileLocation
    )

    return (Select-String -Path $fileLocation -Pattern "^$key=" -Quiet)
}

function Decrypt-Value {
    param (
        [string]$encryptedValue,
        [string]$privateKey
    )

    $bytes = [Convert]::FromBase64String($encryptedValue)

    # Use PowerShell's pipeline to send data directly to openssl and capture the output
    $result = $bytes | openssl pkeyutl -decrypt -inkey $privateKey | Out-String

    return $result.Trim()
}

function Decrypt-ProtectedValue {
    param (
        [string]$encryptedValue,
        [string]$privateKey,
        [string]$privateKeyPass
    )

    $bytes = [Convert]::FromBase64String($encryptedValue)

    # Use PowerShell's pipeline to send data directly to openssl and capture the output
    $result = $bytes | openssl pkeyutl -decrypt -inkey $privateKey -passin "pass:$privateKeyPass" | Out-String

    return $result.Trim()
}

# Main Script Execution
Read-Ini $KEYVAULT_CONFIG

if (-not $key) { Show-Usage }

if (Test-KeyExistsInFile $key $Script:ini_keyvault_db) {
    $value = Get-KeyValueInFile $key $Script:ini_keyvault_db
    $messageLength = $value.Length - 1
    $var1 = $value.Substring(0, $messageLength)
    $var2 = [int]$value[$messageLength]

    $isEncrypted = $var2 % 2

    switch ($messageLength) {
        { $_ -in 1..9 } { Write-Host "Input string is too short." }
        344 {
            if ($isEncrypted -eq 0) {
                $decrypted = Decrypt-Value $var1 $Script:ini_key2048_private
            }
            else {
                $privateKeyPassword = Get-Password
                $decrypted = Decrypt-ProtectedValue $var1 $Script:ini_key2048_protected_private $privateKeyPassword
            }
            $decrypted
        }
        512 {
            if ($isEncrypted -eq 0) {
                $decrypted = Decrypt-Value $var1 $Script:ini_key3072_private
            }
            else {
                $privateKeyPassword = Get-Password
                $decrypted = Decrypt-ProtectedValue $var1 $Script:ini_key3072_protected_private $privateKeyPassword
            }
            $decrypted
        }
        684 {
            if ($isEncrypted -eq 0) {
                $decrypted = Decrypt-Value $var1 $Script:ini_key4096_private
            }
            else {
                $privateKeyPassword = Get-Password
                $decrypted = Decrypt-ProtectedValue $var1 $Script:ini_key4096_protected_private $privateKeyPassword
            }
            $decrypted
        }
        default { Write-Host "Invalid length: $messageLength" }
    }
}
else {
    Write-Host -NoNewline ""
}
