param(
    [Parameter(Position = 0)]
    $key
    #[switch]$display
)

$KEYVAULT_CONFIG = "$env:LOCALAPPDATA\keyvault\config.ini"

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
    Write-Host "Usage: $($MyInvocation.MyCommand.Name) <key> [-Display]"
    Write-Host "Use -Display if password is not displayed properly"
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


function Decrypt-Value {
    param (
        [string]$encryptedValue,
        [string]$privateKeyPath
    )

    $tempInputFile = [System.IO.Path]::GetTempFileName()
    $tempOutputFile = [System.IO.Path]::GetTempFileName()

    try {
        $bytes = [System.Convert]::FromBase64String($encryptedValue)
        [System.IO.File]::WriteAllBytes($tempInputFile, $bytes)

        # Use OpenSSL for decryption
        $opensslOutput = & openssl pkeyutl -decrypt -inkey $privateKeyPath -in $tempInputFile -out $tempOutputFile 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "OpenSSL decryption failed: $opensslOutput"
        }

        return [System.IO.File]::ReadAllText($tempOutputFile)
    }
    finally {
        # Clean up temporary files
        Remove-Item -Path $tempInputFile -ErrorAction SilentlyContinue
        Remove-Item -Path $tempOutputFile -ErrorAction SilentlyContinue
    }
}

function Decrypt-ProtectedValue {
    param (
        [string]$encryptedValue,
        [string]$privateKeyPath,
        [string]$privateKeyPass
    )

    $tempInputFile = [System.IO.Path]::GetTempFileName()
    $tempOutputFile = [System.IO.Path]::GetTempFileName()

    try {
        $bytes = [System.Convert]::FromBase64String($encryptedValue)
        [System.IO.File]::WriteAllBytes($tempInputFile, $bytes)

        # Use OpenSSL for decryption with password
        $opensslOutput = & openssl pkeyutl -decrypt -inkey $privateKeyPath -passin "pass:$privateKeyPass" -in $tempInputFile -out $tempOutputFile 2>&1

        if ($LASTEXITCODE -ne 0) {
            throw "OpenSSL decryption failed: $opensslOutput"
        }

        return [System.IO.File]::ReadAllText($tempOutputFile)
    }
    finally {
        # Clean up temporary files
        Remove-Item -Path $tempInputFile -ErrorAction SilentlyContinue
        Remove-Item -Path $tempOutputFile -ErrorAction SilentlyContinue
    }
}


function Get-CredentialManager {
    $credential = Get-StoredCredential -Target "$Script:ini_keychain_service" | Where-Object { $_.username -eq "$Script:ini_keychain_account" }
    if ($credential) {
        $password = ConvertFrom-SecureString -SecureString $credential.password -AsPlainText
    }
    else {
        $password = $null
    }
    return $password
}


function Get-Password {
    # Try to get the password from Windows Credential Manager
    $password = Get-CredentialManager

    if ($password) {
        Write-Host "Password protecting the key has been retrieved from Credential Manager."
    }
    else {
        # If password is not in Credential Manager, prompt the user
        Write-Host "Password protecting the Private key not found in Credential Manager."
        $password = Read-SecurePassword
    }
    return $password
}

function Test-KeyExistsInFile {
    param (
        [string]$key,
        [string]$fileLocation
    )

    return (Select-String -Path $fileLocation -Pattern "^$key=" -Quiet)
}

# Main script
Read-Ini $KEYVAULT_CONFIG

#if ($args.Count -eq 0) {
#    Show-Usage
#}

# $key = $args[0]
#$displayFormat = if ($args -contains "-Display") { "{0}`n" } else { "{0}" }
#if ($display) {
#    $displayFormat = "{0}`n"
#}
#else {
#    $displayFormat = "{0}"
#}

if (Test-KeyExistsInFile $key $Script:ini_keyvault_db) {
    $value = Get-KeyValueInFile $key $Script:ini_keyvault_db
    $valueLength = $value.Length
    $messageLength = $valueLength - 1
    $var1 = $value.Substring(0, $messageLength)
    $var2 = $value.Substring($messageLength, 1)

    $isEncrypted = [int]$var2 % 2

    switch ($messageLength) {
        { $_ -in 1..9 } { Write-Host "Input string is too short." }
        344 {
            if ($isEncrypted -eq 0) {
                # RSA 2048, max message length 256 byte
                $decrypted = Decrypt-Value $var1 $Script:ini_key2048_private
            }
            else {
                # RSA 2048 protected, max message length 256 byte
                $privateKeyPassword = Get-Password
                $decrypted = Decrypt-ProtectedValue $var1 $Script:ini_key2048_protected_private $privateKeyPassword
            }
            # $displayFormat -f $decrypted
            $decrypted
        }
        512 {
            if ($isEncrypted -eq 0) {
                # RSA 3072, max message length 384 bytes
                $decrypted = Decrypt-Value $var1 $Script:ini_key3072_private
            }
            else {
                # RSA 3072 protected
                $privateKeyPassword = Get-Password
                $decrypted = Decrypt-ProtectedValue $var1 $Script:ini_key3072_protected_private $privateKeyPassword
            }
            # $displayFormat -f $decrypted
            $decrypted
        }
        684 {
            if ($isEncrypted -eq 0) {
                # RSA 4096, max message length 512 bytes
                $decrypted = Decrypt-Value $var1 $Script:ini_key4096_private
            }
            else {
                # RSA 4096 protected
                $privateKeyPassword = Get-Password
                $decrypted = Decrypt-ProtectedValue $var1 $Script:ini_key4096_protected_private $privateKeyPassword
            }
            # $displayFormat -f $decrypted
            $decrypted
        }
        default { Write-Host "Invalid length: $messageLength" }
    }
}
else {
    Write-Host -NoNewline ""
}
