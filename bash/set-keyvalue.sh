#!/bin/bash

usage() {
    echo "Usage: $0 <key> <value> [--protected | -p] [--key=2048 | -k=2048] [--key=3072 | -k=3072] [--key=4096 | -k=4096]"
    echo "   or"
    echo "       $0 <-i | --interactive>"
    exit 1
}

parse_args() {
    for arg in "$@"; do
        case $arg in
        --protected | -p)
            flag_protected=true
            ;;
        --interactive | -i)
            flag_interactive=true
            ;;
        --path=* | -p=*)
            KEYVAULT_DIR="${arg#*=}"
            ;;
        --key=* | -k=*)
            key_size="${arg#*=}"
            ;;
        --totp)
            flag_totp=true
            ;;
        --help | -h)
            usage
            exit 1
            ;;
        esac
    done
}

parse_ini() {
    local ini_file="$1"
    local section=""
    local line
    while IFS= read -r line; do
        # Remove leading and trailing whitespaces
        local line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^# ]]; then
            continue
        fi

        # Handle section headers
        if [[ "$line" =~ ^\[.*\]$ ]]; then
            local section=$(echo "$line" | sed 's/\[\(.*\)\]/\1/')
            continue
        fi

        # Handle key-value pairs
        if [[ "$line" =~ ^[^=]+=[^=]+$ ]]; then
            local key=$(echo "$line" | cut -d '=' -f 1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            local value=$(echo "$line" | cut -d '=' -f 2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [[ -n "$section" ]]; then
                local key="${section}_${key}"
            fi
            export "ini_$key"="$value"
        fi
    done <"$ini_file"
}

get_key_value_in_file() {
    local key=$1
    local file_location=$2

    local value=$(awk -F= -v key="$key" \
        '$1 == key {print substr($0, index($0, "=") + 1)}' \
        "$file_location")
    printf "%s" "$value"
}

# Encrypt a value using RSA public key
encrypt_value() {
    local value=$1
    local public_key_path=$2
    printf "%s" "$value" |
        openssl pkeyutl -encrypt -pubin -inkey "$public_key_path" | base64
}

# Add or replace a key-value pair in sec_env
add_key_value() {
    local key=$1
    local value=$2

    # Create sec_env file if it doesn't exist
    touch "$ini_keyvault_db"

    # Check if key exists and replace its value
    if grep -q "^$key=" "$ini_keyvault_db"; then
        echo "Key already exists.  Overwrite ? (yes,no)"
        read -r overwrite
        while [[ "$overwrite" != "yes" && "$overwrite" != "no" ]]; do
            echo "Invalid input. Please enter yes or no: "
            read -r overwrite
        done

        if [ "$overwrite" == "yes" ]; then
            sed -i "" "s|^$key=.*|$key=$value|" "$ini_keyvault_db"
        else
            echo "Abort"
            exit 1
        fi
    else
        echo "$key=$value" >>"$ini_keyvault_db"
    fi
}

interactive_mode() {
    # Prompt user for key
    echo -n "Enter key: "
    read key

    # Prompt user for value
    echo -n "Enter value for '$key': "
    read value

    # Prompt user for key size
    echo -n "Enter key size (2048, 3072, 4096): "
    read key_size

    # Validate key size input (optional)
    while [[ ! "$key_size" =~ ^(2048|3072|4096)$ ]]; do
        echo -n "Invalid key size. Please enter 2048, 3072, or 4096: "
        read key_size
    done

    # Prompt user for password protection
    echo -n "Do you want to use password protected keys? (yes/no): "
    read flag

    # Validate flag input (optional)
    while [[ "$flag" != "yes" && "$flag" != "no" ]]; do
        echo -n "Invalid input. Please enter 'yes' or 'no': "
        read flag
    done

    # Convert flag to boolean
    if [[ "$flag" == "yes" ]]; then
        flag_protected=true
    else
        flag_protected=false
    fi

    # Prompt user for totp
    echo -n "Is this used by One Time Password ? (yes/no): "
    read flag

    # Validate flag input (optional)
    while [[ "$flag" != "yes" && "$flag" != "no" ]]; do
        echo -n "Invalid input. Please enter 'yes' or 'no': "
        read flag
    done

    # Convert flag to boolean
    if [[ "$flag" == "yes" ]]; then
        flag_totp=true
    else
        flag_totp=false
    fi
}

##### main

KEYVAULT_DIR="$HOME/.config/keyvault"
key_size="2048"        # default to use 4096 bit key
flag_protected=false   # default to use password protected private key
flag_interactive=false # default to use command line
flag_totp=false        # default the key is not used for totp generation

parse_args "$@"

KEYVAULT_CONFIG="$KEYVAULT_DIR/config.ini"
parse_ini "$KEYVAULT_CONFIG"

if [ $flag_interactive = true ]; then
    interactive_mode
else
    # Check if we have at least two arguments
    if [ "$#" -lt 2 ]; then
    echo "broken"
        usage
    else
        key=$1
        value=$2
    fi
fi

######## secret type
# plain    0
# totp     1

if [ $flag_totp = true ]; then
    secret_type=1
else
    secret_type=0
fi
padding=$((secret_type * 2))
if $flag_protected; then
    ((padding = padding + 1))
fi
padding_char=$(printf "%s" "$padding")

# Handle the optional parameter with a case statement
case "$key_size" in
2048)
    if $flag_protected; then
        encrypted_value="$(encrypt_value "$value" \
            "$ini_key2048_protected_public")$padding_char"
    else
        encrypted_value="$(encrypt_value "$value" \
            "$ini_key2048_public")$padding_char"
    fi
    add_key_value "$key" "$encrypted_value"
    ;;
3072)
    if $flag_protected; then
        encrypted_value="$(encrypt_value "$value" \
            "$ini_key3072_protected_public")$padding_char"
    else
        encrypted_value="$(encrypt_value "$value" \
            "$ini_key3072_public")$padding_char"
    fi
    add_key_value "$key" "$encrypted_value"
    ;;
4096)
    if $flag_protected; then
        encrypted_value="$(encrypt_value "$value" \
            "$ini_key4096_protected_public")$padding_char"
    else
        encrypted_value="$(encrypt_value "$value" \
            "$ini_key4096_public")$padding_char"
    fi
    add_key_value "$key" "$encrypted_value"
    ;;
*)
    usage
    ;;
esac
