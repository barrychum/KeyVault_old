#!/bin/bash

KEYVAULT_CONFIG="$HOME/.config/keyvault/config.ini"

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

# Function to display usage information
usage() {
    echo "Usage: $0 <key> [--display]"
    echo "use -display if password is not displayed properly"
    exit 1
}

get_key_value_in_file() {
    local key=$1
    local file_location=$2

    local value=$(awk -F= -v key="$key" \
        '$1 == key {print substr($0, index($0, "=") + 1)}' \
        "$file_location")
    printf "%s" "$value"
}

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

#############

# Paths
parse_ini "$KEYVAULT_CONFIG"

# Decrypt a value using RSA private key
decrypt_value() {
    local encrypted_value="$1"
    local private_key="$2"
    printf "%s" "$encrypted_value" | base64 --decode |
        openssl pkeyutl -decrypt -inkey "$private_key"
}

decrypt_protected_value() {
    local encrypted_value="$1"
    local private_key="$2"
    local private_key_pass="$3"

    printf "%s" "$encrypted_value" | base64 --decode |
        openssl pkeyutl -decrypt -inkey "$private_key" -passin pass:"$private_key_pass"

}

get_password() {
    # Retrieve the password
    keychain_password=$(security find-generic-password -s "$ini_keychain_service" -a "$ini_keychain_account" -w)
    if [ $? -eq 0 ]; then
        echo "Private key password obtained from keychain" >&2
        printf "%s" "$keychain_password"
    else
        # read -s -p "Password not in keychain.  Please enter private key password: " userinput
        echo "Private key password not in keychain.  Please enter private key password: " >&2
        userinput=$(read_password)
        echo >&2
        printf "%s" "$userinput"
    fi
}

key_exist_in_file() {
    local key=$1
    local file_location=$2

    grep -q "^${key}=" "$file_location" || return 1
    return 0
}

# Check if the mandatory argument is provided
if [ -z "$1" ]; then
    usage
fi

key=$1
if [ "$2" == "--display" ]; then
    display_format="%s\n"
else
    display_format="%s"
fi

if key_exist_in_file "$key" "$ini_keyvault_db"; then
    value=$(get_key_value_in_file "$key" "$ini_keyvault_db")
    value_length=${#value}
    message_length=$((value_length - 1))
    var1="${value:0:message_length}"
    var2="${value:message_length:1}"

    is_encrypted=$((var2 % 2))

    case $message_length in
    [1-9])
        echo "Input string is too short."
        ;;
    344)
        if [ "$is_encrypted" -eq 0 ]; then
            # RSA 2048, max message length 256 byte
            printf "$display_format" "$(decrypt_value "$var1" \
                "$ini_key2048_private")"
        else
            # RSA 2048 protected, max message length 256 byte
            private_key_password=$(get_password)
            printf "$display_format" "$(decrypt_protected_value "$var1" \
                "$ini_key2048_protected_private" "$private_key_password")"
        fi
        ;;
    512)
        if [ "$is_encrypted" -eq 0 ]; then
            # RSA 3072, max message length 384 bytes
            printf "$display_format" "$(decrypt_value "$var1" \
                "$ini_key3072_private")"
        else
            # RSA 3072
            private_key_password=$(get_password)
            printf "$display_format" "$(decrypt_protected_value "$var1" \
                "$ini_key3072_protected_private" "$private_key_password")"
        fi
        ;;
    684)
        if [ "$is_encrypted" -eq 0 ]; then
            # RSA 4096, max message length 512 bytes
            printf "$display_format" "$(decrypt_value "$var1" \
                "$ini_key4096_private")"
        else
            # RSA 4096
            private_key_password=$(get_password)
            printf "$display_format" "$(decrypt_protected_value "$var1" \
                "$ini_key4096_protected_private" "$private_key_password")"
        fi
        ;;
    *)
        echo "Invalid length: $length"
        ;;
    esac
else
    printf "%s" ""
fi
