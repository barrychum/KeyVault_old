param ([switch]$demo)

# Define the KeyVault environment variables
$KEYVAULT_DIR = "$env:LOCALAPPDATA\keyvault"
$KEYVAULT_CONFIG = Join-Path $KEYVAULT_DIR "config.ini"
$KEYVAULT_DB = Join-Path $KEYVAULT_DIR "keyvault.db"
$KEYVAULT_KEYS = Join-Path $KEYVAULT_DIR "keys"

# Function to prompt user for password protection preference
function Prompt-PasswordProtection {
    Write-Host "Do you want the private key to be password protected? (yes/no):"
    $password_protected = Read-Host
    while ($password_protected -ne "yes" -and $password_protected -ne "no") {
        Write-Host "Invalid input. Please enter 'yes' or 'no':" -ForegroundColor Yellow
        $password_protected = Read-Host
    }

    if ($password_protected -eq "yes") {
        $password1 = Read-Host "Enter a password :" -AsSecureString
        $password2 = Read-Host "Re-enter password:" -AsSecureString
    
        # Validate that both passwords match
        while ((ConvertFrom-SecureString $password1 -AsPlainText) -ne (ConvertFrom-SecureString $password2 -AsPlainText)) {
            Write-Host "Passwords do not match. Please enter the password again" -ForegroundColor Yellow
            $password1 = Read-Host "Enter a password :" -AsSecureString
            $password2 = Read-Host "Re-enter password:" -AsSecureString
        }
    }

    return $password_protected, (ConvertFrom-SecureString $password1 -AsPlainText)
}

# Function to create the KeyVault directories
function Setup-Directories {
    New-Item -ItemType Directory -Path $KEYVAULT_DIR -Force | Out-Null
    New-Item -ItemType Directory -Path $KEYVAULT_KEYS -Force | Out-Null
}

# Function to create the configuration file
function Setup-ConfigFile {
    if (Test-Path $KEYVAULT_CONFIG) {
        Write-Host "The configuration file $KEYVAULT_CONFIG already exists. Do you want to overwrite it? (yes/no):"
        $overwrite = Read-Host
        if ($overwrite -ne "yes") {
            Write-Host "Setup aborted." -ForegroundColor Yellow
            exit 1
        }
    }

    $key_location = $KEYVAULT_KEYS
    $configContent = @"
[keyvault]
db=$KEYVAULT_DB
keys=$KEYVAULT_KEYS
pass=$password_protected

[keychain]
service=KeyVault
account=private.key.password

[key2048]
private=$($key_location)\KeyVault_2048_private.pem
public=$($key_location)\KeyVault_2048_public.pem

[key3072]
private=$($key_location)\KeyVault_3072_private.pem
public=$($key_location)\KeyVault_3072_public.pem

[key4096]
private=$($key_location)\KeyVault_4096_private.pem
public=$($key_location)\KeyVault_4096_public.pem

[key2048_protected]
private=$($key_location)\KeyVault_2048_protected_private.pem
public=$($key_location)\KeyVault_2048_protected_public.pem

[key3072_protected]
private=$($key_location)\KeyVault_3072_protected_private.pem
public=$($key_location)\KeyVault_3072_protected_public.pem

[key4096_protected]
private=$($key_location)\KeyVault_4096_protected_private.pem
public=$($key_location)\KeyVault_4096_protected_public.pem
"@

    Set-Content -Path $KEYVAULT_CONFIG -Value $configContent
}

# Function to generate the key pair
function Generate-Keys {
    param(
        [int]$key_length,
        [string]$password_protected,
        [string]$key_location
    )

    if ($password_protected -eq "yes") {
        $private_key_filename = "KeyVault_${key_length}_protected_private.pem"
        $public_key_filename = "KeyVault_${key_length}_protected_public.pem"
    }
    else {
        $private_key_filename = "KeyVault_${key_length}_private.pem"
        $public_key_filename = "KeyVault_${key_length}_public.pem"
    }

    if ((Test-Path (Join-Path $key_location $private_key_filename)) -or (Test-Path (Join-Path $key_location $public_key_filename))) {
        Write-Host "Error: One or both target files already exist. Please choose a different name or location." -ForegroundColor Red
        exit 1
    }

    Write-Host "Generating $key_length-bit Private key: $($key_location)\$private_key_filename"
    Write-Host "Generating $key_length-bit Public key : $($key_location)\$public_key_filename"
    Write-Host "Password   : $password_protected"
    Write-Host

    if ($password_protected -eq "yes") {
        openssl genpkey -algorithm RSA -out (Join-Path $key_location $private_key_filename) -aes256 -pass pass:"$password1" -pkeyopt rsa_keygen_bits:"$key_length" 2>$null
        openssl rsa -pubout -in (Join-Path $key_location $private_key_filename) -out (Join-Path $key_location $public_key_filename) -passin pass:"$password1" 2>$null
    }
    else {
        openssl genpkey -algorithm RSA -out (Join-Path $key_location $private_key_filename) -pkeyopt rsa_keygen_bits:"$key_length" 2>$null
        openssl rsa -pubout -in (Join-Path $key_location $private_key_filename) -out (Join-Path $key_location $public_key_filename) 2>$null
    }
}

# Main script execution

# Check if running in demo mode
if ($demo) {
    # If demo mode, set password protection to "yes" and generate a demo password
    $password_protected =  "yes"
    $password1 = (New-Guid).Guid.Substring(0, 8)
}
else {
    # If not demo mode, prompt user for password protection preference and secure password
    $password_protected, $password1 = Prompt-PasswordProtection
}

# Set up directories and configuration file
Setup-Directories
Setup-ConfigFile

$key_location = $KEYVAULT_KEYS

# Generate key pairs of different lengths without password protection
Generate-Keys -key_length 2048 -password_protected "no" -key_location $key_location
Generate-Keys -key_length 3072 -password_protected "no" -key_location $key_location
Generate-Keys -key_length 4096 -password_protected "no" -key_location $key_location

# Read the .ini file to determine if password protection is required
$password_required_ini = (Get-Content -Path $KEYVAULT_CONFIG | Where-Object { $_ -match "^pass=" }).Split('=')[1].Trim()

# If password protection is required, generate additional key pairs with protection
if ($password_required_ini -eq "yes") {
    Generate-Keys -key_length 2048 -password_protected "yes" -key_location $key_location
    Generate-Keys -key_length 3072 -password_protected "yes" -key_location $key_location
    Generate-Keys -key_length 4096 -password_protected "yes" -key_location $key_location
}

# Display setup confirmation and environment details
Write-Host "KeyVault environment setup completed"
Write-Host "Keyvault directory : $KEYVAULT_DIR"
Write-Host "Configuration file : $KEYVAULT_CONFIG"
Write-Host "Database file      : $KEYVAULT_DB"
Write-Host "Keys directory     : $KEYVAULT_KEYS"
Write-Host "Password protection for private key: $password_protected"

# If in demo mode, display the demo password
if ($demo) {
    Write-Host "Demo private key password: $password1"  -ForegroundColor Yellow
}

# Clean up variables
Remove-Variable -Name password1 -Force
Write-Host
