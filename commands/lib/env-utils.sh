#!/usr/bin/env bash
set -euo pipefail

# Validates that required environment variables are set and non-empty
#
# This function checks if the specified environment variables are defined
# either in the .env file or as exported environment variables. If any 
# required variable is missing or empty, the script exits with error code 1.
#
# Search priority:
#   1. First checks .env file for variable=value pairs
#   2. If not found in .env, checks exported environment variables
#   3. If not found anywhere, prints error and exits
#
# Arguments:
#   $1, $2, ... $N    Variable names to validate (e.g., "MAINNET_RPC_URL" "ETHERSCAN_API_KEY")
#
# Examples:
#   validate_env "MAINNET_RPC_URL"
#   validate_env "ETHERSCAN_API_KEY" "MAINNET_RPC_URL" "MAINNET_FORK_BLOCK_NUMBER"
#
# Exit codes:
#   0 - All variables are set and non-empty
#   1 - One or more variables are missing or empty
#
# Notes:
#   - Always uses .env file in current directory
#   - Prints warning if .env file doesn't exist
#   - Variable names must match pattern: [A-Za-z_][A-Za-z0-9_]*
#   - Ignores empty lines and comments (starting with #) in .env
#   - Trims whitespace from values
validate_env() {
    local env_file=".env"
    local required_vars=("$@")
    local var
    local found
    local line
    local value
    
    # # Parse arguments - only variable names
    # for arg in "$@"; do
    #     required_vars+=("$arg")
    # done
    
    # Check if no variables provided
    if [[ ${#required_vars[@]} -eq 0 ]]; then
        echo "Warning: No variables specified for validation" >&2
        return 0
    fi
    
    # Check each required variable
    for var in "${required_vars[@]}"; do
        found=false
        
        # Validate variable name format
        if ! [[ "$var" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
            echo "Error: Invalid variable name '$var'. Must start with letter or underscore, contain only letters, numbers, and underscores" >&2
            exit 1
        fi
        
        # First check in .env file
        if [[ -f "$env_file" ]]; then
            while IFS= read -r line || [[ -n "$line" ]]; do
                # Skip empty lines and comments
                [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
                
                # Remove inline comments and trim whitespace
                line=$(echo "$line" | sed -E 's/[[:space:]]+#.*$//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                
                # Skip empty processed lines
                [[ -z "$line" ]] && continue
                
                # Check if this line contains our variable
                if [[ "$line" =~ ^$var[[:space:]]*= ]]; then
                    # Extract value (everything after first =)
                    value="${line#*=}"
                    
                    # Trim whitespace from value
                    value=$(echo "$value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                    
                    # Check if value is not empty
                    if [[ -n "$value" ]]; then
                        found=true
                        break
                    fi
                fi
            done < "$env_file"
        else
            # Warning if .env file doesn't exist
            echo "Warning: .env file not found" >&2
        fi
        
        # If not found in .env, check exported environment variables
        if [[ "$found" == "false" ]]; then
            if [[ -n "${!var:-}" ]]; then
                found=true
            fi
        fi
        
        # If variable not found anywhere - error and exit
        if [[ "$found" == "false" ]]; then
            echo "Error: Required environment variable '$var' is not set or empty" >&2
            echo "Please set it in .env file or export it" >&2
            exit 1
        fi
    done
    
    return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "This file should be sourced, not executed directly"
    exit 1
fi