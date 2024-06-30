#!/bin/bash

# Define the KeyVault environment variables
KEYVAULT_DIR="$HOME/.config/keyvault"
KEYVAULT_CONFIG="$KEYVAULT_DIR/config.ini"
KEYVAULT_DB="$KEYVAULT_DIR/keyvault.db"
KEYVAULT_KEYS="$KEYVAULT_DIR/keys"

# Function to read password with asterisks and handle backspace/delete
read_password() {
    local password=""
    local char=""

    # Turn off echoing
    stty -echo

    while IFS= read -r -s -n 1 char; do
        # Enter key is pressed (ASCII 10, 13 or Null)
        if [[ $char == $'\n' || $char == $'\r' || $char == $'\x0' ]]; then
            break
        fi

        # Backspace is pressed (ASCII 127 or 8)
        if [[ $char == $'\x7f' || $char == $'\b' ]]; then
            if [ -n "$password" ]; then
                # Remove the last character from password
                password=${password%?}
                # Move cursor back, overwrite with space, move cursor back again
                printf "\b \b" >&2
            fi
        else
            # Add the character to password
            password+="$char"
            # Print an asterisk
            printf "*" >&2
        fi
    done

    # Turn echoing back on
    stty echo
    printf "\n" >&2
    printf "%s" "$password"
}

# Function to prompt for password protection
prompt_password_protection() {
    echo "Do you want the private key to be password protected? (strongly recommended): "
    echo "(yes/no): "
    read -r password_protected
    while [[ "$password_protected" != "yes" && "$password_protected" != "no" ]]; do
        echo "Invalid input. Please enter yes or no: "
        read -r password_protected
    done

    if [ "$password_protected" == "yes" ]; then
        echo "Enter a password for the private key: "
        #read -s password1
        password1=$(read_password)
        echo "Confirm the password for the private key: "
        #read -s password2
        password2=$(read_password)
        while [ "$password1" != "$password2" ]; do
            echo "Passwords do not match. Please enter the password again: "
            #read -s password1
            password1=$(read_password)
            echo "Confirm the password for the private key: "
            #read -s password2
            password2=$(read_password)
        done
    fi

    unset password2
}

# Function to create the KeyVault directories
setup_directories() {
    mkdir -p "$KEYVAULT_DIR"
    mkdir -p "$KEYVAULT_KEYS"
}

# Function to create the configuration file
setup_config_file() {
    if [ -f "$KEYVAULT_CONFIG" ]; then
        echo "The configuration file $KEYVAULT_CONFIG already exists. Do you want to overwrite it? (yes/no): "
        read -r overwrite
        if [ "$overwrite" != "yes" ]; then
            echo "Setup aborted."
            exit 1
        fi
    fi

    if [ -d "$KEYVAULT_KEYS" ]; then
        # Check if there are any .pem files in the folder
        pem_files=("$KEYVAULT_KEYS"/*.pem)
        if [ -e "${pem_files[0]}" ]; then
            echo "Found .pem files in the key folder."
            echo "Make sure you have your private keys backed up"
            echo "Setup aborted."
            exit 1
        fi
    fi

    cat <<EOF >"$KEYVAULT_CONFIG"
[keyvault]
db=$KEYVAULT_DB
keys=$KEYVAULT_KEYS
pass=$password_protected
[keychain]
service=KeyVault
account=private.key.password
[key2048]
private=$KEYVAULT_KEYS/KeyVault_2048_private.pem
public=$KEYVAULT_KEYS/KeyVault_2048_public.pem
[key3072]
private=$KEYVAULT_KEYS/KeyVault_3072_private.pem
public=$KEYVAULT_KEYS/KeyVault_3072_public.pem
[key4096]
private=$KEYVAULT_KEYS/KeyVault_4096_private.pem
public=$KEYVAULT_KEYS/KeyVault_4096_public.pem
[key2048_protected]
private=$KEYVAULT_KEYS/KeyVault_2048_protected_private.pem
public=$KEYVAULT_KEYS/KeyVault_2048_protected_public.pem
[key3072_protected]
private=$KEYVAULT_KEYS/KeyVault_3072_protected_private.pem
public=$KEYVAULT_KEYS/KeyVault_3072_protected_public.pem
[key4096_protected]
public=$KEYVAULT_KEYS/KeyVault_4096_protected_public.pem
private=$KEYVAULT_KEYS/KeyVault_4096_protected_private.pem
EOF
}


# Function to generate the key pair
generate_keys_batch() {
    local key_length=$1
    local password_protected=$2
    local key_location=$3

    if [ "$2" == "yes" ]; then
        local private_key_filename="KeyVault_${key_length}_protected_private.pem"
        local public_key_filename="KeyVault_${key_length}_protected_public.pem"
    else
        local private_key_filename="KeyVault_${key_length}_private.pem"
        local public_key_filename="KeyVault_${key_length}_public.pem"
    fi

    if [ -f "$key_location/$private_key_filename" ] || [ -f "$key_location/$public_key_filename" ]; then
        echo "Error: One or both target files already exist. Please choose a different name or location."
        exit 1
    fi

    echo "Key length : $key_length"
    echo "Private key: $key_location/$private_key_filename"
    echo "Public key : $key_location/$public_key_filename"
    echo "Password   : $password_protected"

    if [ "$password_protected" == "yes" ]; then
        openssl genpkey -algorithm RSA -out "$key_location/$private_key_filename" -aes256 -pass pass:"$password1" -pkeyopt rsa_keygen_bits:"$key_length"
        openssl rsa -pubout -in "$key_location/$private_key_filename" -out "$key_location/$public_key_filename" -passin pass:"$password1"
    else
        openssl genpkey -algorithm RSA -out "$key_location/$private_key_filename" -pkeyopt rsa_keygen_bits:"$key_length"
        openssl rsa -pubout -in "$key_location/$private_key_filename" -out "$key_location/$public_key_filename"
    fi
    echo "Keys generated and saved to $key_location"
}

# Main script execution
if [ "$1" == "--demo" ]; then
    password_protected="yes"
    password1=$(echo $(uuidgen) | cut -d'-' -f1)
else
    prompt_password_protection
fi
setup_directories
setup_config_file

key_location="$KEYVAULT_KEYS"

key_length="2048"
generate_keys_batch "$key_length" "no" "$key_location"
key_length="3072"
generate_keys_batch "$key_length" "no" "$key_location"
key_length="4096"
generate_keys_batch "$key_length" "no" "$key_location"

# Read the .ini file
#password_required_ini=$(awk -F "=" '/^keyvault_pass/ {print $2}' $KEYVAULT_CONFIG)
password_required_ini=$password_protected

if [ $password_required_ini == "yes" ]; then
    key_length="2048"
    generate_keys_batch "$key_length" "yes" "$key_location"
    key_length="3072"
    generate_keys_batch "$key_length" "yes" "$key_location"
    key_length="4096"
    generate_keys_batch "$key_length" "yes" "$key_location"
fi

# Confirm setup
echo "KeyVault environment setup complete."
echo "Configuration directory: $KEYVAULT_DIR"
echo "Configuration file: $KEYVAULT_CONFIG"
echo "Database file: $KEYVAULT_DB"
echo "Keys directory: $KEYVAULT_KEYS"
echo "Password protection for private key: $password_protected"

if [ "$1" == "--demo" ]; then
    echo "Demo private key password: $password1"
fi

unset password1