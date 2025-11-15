#!/bin/bash

# Vercel Environment Sync Script
# This script helps manage environment variables between local .env file and Vercel
# Uses npx vercel (no global installation required)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Function to check if npx is available
check_vercel_cli() {
    if ! command -v npx &> /dev/null; then
        echo -e "${RED}Error: npx is not available.${NC}"
        echo "Make sure Node.js and npm are installed."
        exit 1
    fi
}

# Function to check if user is logged in to Vercel
check_vercel_auth() {
    if ! echo 'y' | npx vercel whoami &> /dev/null; then
        echo -e "${RED}Error: Not logged in to Vercel.${NC}"
        echo "Run: npx vercel login"
        exit 1
    fi
}

# Function to pull environment variables from Vercel
pull_env() {
    local env="$1"
    local env_display=$(echo "$env" | tr '[:lower:]' '[:upper:]')
    
    echo -e "${BLUE}Pulling $env_display environment variables from Vercel...${NC}"
    
    check_vercel_cli
    check_vercel_auth
    
    # Pull environment variables for specified environment
    echo 'y' | npx vercel env pull "$ENV_FILE" --environment="$env"
    
    if [ $? -eq 0 ]; then
        # Remove VERCEL_OIDC_TOKEN and NODE_ENV from the pulled .env file
        if [ -f "$ENV_FILE" ]; then
            sed -i.bak '/^VERCEL_OIDC_TOKEN=/d; /^NODE_ENV=/d' "$ENV_FILE"
            rm -f "$ENV_FILE.bak"
            echo -e "${YELLOW}Note: VERCEL_OIDC_TOKEN and NODE_ENV have been filtered out and not included in .env${NC}"
        fi
        
        # Clean up literal escape sequences (\n, \r, \t) from environment variable values
        if [ -f "$ENV_FILE" ]; then
            # Remove literal \n, \r, \t from the end of quoted values and unquoted values
            sed -i.bak 's/\\n"$/"/g; s/\\r"$/"/g; s/\\t"$/"/g; s/\\n$//g; s/\\r$//g; s/\\t$//g' "$ENV_FILE"
            # Also remove any literal escape sequences in the middle of values
            sed -i.bak 's/\\n//g; s/\\r//g; s/\\t//g' "$ENV_FILE"
            rm -f "$ENV_FILE.bak"
            echo -e "${YELLOW}Note: Literal escape sequences (n, r, t) have been cleaned from environment values${NC}"
        fi
        
        echo -e "${GREEN}✓ Successfully pulled $env_display environment variables to .env${NC}"
        echo -e "${YELLOW}Note: Review the .env file and update .env.example accordingly (with masked values)${NC}"
    else
        echo -e "${RED}✗ Failed to pull environment variables${NC}"
        exit 1
    fi
}

# Function to push environment variables to Vercel
push_env() {
    local env="$1"
    local env_display=$(echo "$env" | tr '[:lower:]' '[:upper:]')
    
    echo -e "${BLUE}Pushing $env_display environment variables to Vercel...${NC}"
    
    check_vercel_cli
    check_vercel_auth
    
    if [ ! -f "$ENV_FILE" ]; then
        echo -e "${RED}Error: .env file not found at $ENV_FILE${NC}"
        exit 1
    fi
    
    echo -e "${YELLOW}This will add/update environment variables in Vercel's $env environment.${NC}"
    echo -e "${YELLOW}Reading from: $ENV_FILE${NC}"
    echo ""
    
    # Read .env file and push each variable
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Extract variable name and value
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            var_name="${BASH_REMATCH[1]}"
            var_value="${BASH_REMATCH[2]}"
            
            # Skip VERCEL_OIDC_TOKEN and NODE_ENV
            if [[ "$var_name" == "VERCEL_OIDC_TOKEN" ]] || [[ "$var_name" == "NODE_ENV" ]]; then
                echo -e "Skipping: ${YELLOW}$var_name${NC} (ignored)"
                continue
            fi
            
            # Remove surrounding quotes if present
            var_value=$(echo "$var_value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
            
            # Remove trailing whitespace and newlines
            var_value=$(printf '%s' "$var_value" | sed -e 's/[[:space:]]*$//')
            
            # Remove literal \n sequences (backslash followed by n)
            # Using bash parameter expansion to remove literal backslash-n
            var_value="${var_value//\\n/}"
            
            echo -e "Pushing: ${GREEN}$var_name${NC}"
            printf '%s' "$var_value" | npx vercel env add "$var_name" "$env" --force
        fi
    done < "$ENV_FILE"
    
    if [ $? -eq 0 ]; then
        echo ""
        echo -e "${GREEN}✓ Successfully pushed $env_display environment variables to Vercel${NC}"
    else
        echo -e "${RED}✗ Failed to push some environment variables${NC}"
        exit 1
    fi
}

# Function to push a single environment variable or variables matching a prefix to Vercel
push_single_env() {
    local var_pattern="$1"
    local env="$2"
    local env_display=$(echo "$env" | tr '[:lower:]' '[:upper:]')
    
    check_vercel_cli
    check_vercel_auth
    
    if [ ! -f "$ENV_FILE" ]; then
        echo -e "${RED}Error: .env file not found at $ENV_FILE${NC}"
        exit 1
    fi
    
    if [ -z "$var_pattern" ]; then
        echo -e "${RED}Error: Variable name or prefix is required${NC}"
        echo "Usage: $0 push-single VARIABLE_NAME_OR_PREFIX [environment]"
        exit 1
    fi
    
    # Collect matching variables - try exact match first, then prefix match
    declare -a matching_vars
    declare -a matching_values
    local is_prefix=false
    
    # First pass: try exact match
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Extract variable name and value
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local current_var_name="${BASH_REMATCH[1]}"
            local current_var_value="${BASH_REMATCH[2]}"
            
            # Skip VERCEL_OIDC_TOKEN and NODE_ENV
            if [[ "$current_var_name" == "VERCEL_OIDC_TOKEN" ]] || [[ "$current_var_name" == "NODE_ENV" ]]; then
                continue
            fi
            
            # Exact matching
            if [[ "$current_var_name" == "$var_pattern" ]]; then
                matching_vars+=("$current_var_name")
                matching_values+=("$current_var_value")
            fi
        fi
    done < "$ENV_FILE"
    
    # If no exact match found, try prefix matching
    if [ ${#matching_vars[@]} -eq 0 ]; then
        is_prefix=true
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip empty lines and comments
            if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
                continue
            fi
            
            # Extract variable name and value
            if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
                local current_var_name="${BASH_REMATCH[1]}"
                local current_var_value="${BASH_REMATCH[2]}"
                
                # Skip VERCEL_OIDC_TOKEN and NODE_ENV
                if [[ "$current_var_name" == "VERCEL_OIDC_TOKEN" ]] || [[ "$current_var_name" == "NODE_ENV" ]]; then
                    continue
                fi
                
                # Prefix matching: check if variable starts with the pattern
                if [[ "$current_var_name" == "$var_pattern"* ]]; then
                    matching_vars+=("$current_var_name")
                    matching_values+=("$current_var_value")
                fi
            fi
        done < "$ENV_FILE"
    fi
    
    # Check if any variables were found
    if [ ${#matching_vars[@]} -eq 0 ]; then
        echo -e "${RED}Error: No variables matching '$var_pattern' found in $ENV_FILE${NC}"
        exit 1
    fi
    
    # Display what will be pushed
    if [ "$is_prefix" = true ]; then
        echo -e "${BLUE}Pushing variables matching prefix ${GREEN}$var_pattern${BLUE} to $env_display environment in Vercel...${NC}"
        echo -e "${YELLOW}Found ${#matching_vars[@]} variable(s) matching prefix:${NC}"
        for var in "${matching_vars[@]}"; do
            echo -e "  - ${GREEN}$var${NC}"
        done
        echo ""
    else
        echo -e "${BLUE}Pushing single variable ${GREEN}$var_pattern${BLUE} to $env_display environment in Vercel...${NC}"
    fi
    
    # Push each matching variable
    local success_count=0
    local fail_count=0
    
    for i in "${!matching_vars[@]}"; do
        local var_name="${matching_vars[$i]}"
        local var_value="${matching_values[$i]}"
        
        # Remove surrounding quotes if present
        var_value=$(echo "$var_value" | sed -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//")
        
        # Remove trailing whitespace and newlines
        var_value=$(printf '%s' "$var_value" | sed -e 's/[[:space:]]*$//')
        
        # Remove literal \n sequences (backslash followed by n)
        var_value="${var_value//\\n/}"
        
        echo -e "${YELLOW}Pushing variable to $env_display environment...${NC}"
        echo -e "Variable: ${GREEN}$var_name${NC}"
        echo -e "Value: ${GREEN}${var_value:0:20}...${NC}"
        echo ""
        
        if printf '%s' "$var_value" | npx vercel env add "$var_name" "$env" --force; then
            echo -e "${GREEN}✓ Successfully pushed $var_name${NC}"
            ((success_count++))
        else
            echo -e "${RED}✗ Failed to push $var_name${NC}"
            ((fail_count++))
        fi
        echo ""
    done
    
    # Summary
    echo -e "${GREEN}Push complete!${NC}"
    echo -e "Successfully pushed: ${GREEN}$success_count${NC}"
    if [ $fail_count -gt 0 ]; then
        echo -e "Failed to push: ${RED}$fail_count${NC}"
        exit 1
    fi
}

# Function to pull a single environment variable or variables matching a prefix from Vercel into .env
pull_single_env() {
    local var_pattern="$1"
    local env="$2"
    local env_display=$(echo "$env" | tr '[:lower:]' '[:upper:]')

    check_vercel_cli
    check_vercel_auth

    if [ -z "$var_pattern" ]; then
        echo -e "${RED}Error: Variable name or prefix is required${NC}"
        echo "Usage: $0 pull-single VARIABLE_NAME_OR_PREFIX [environment]"
        exit 1
    fi

    echo -e "${BLUE}Pulling environment variables from $env_display (Vercel) matching '${GREEN}$var_pattern${BLUE}'...${NC}"

    # Create temporary file to hold all variables pulled from Vercel
    local tmp_env_file
    tmp_env_file=$(mktemp 2>/dev/null || echo "/tmp/vercel-env-pull-single-$$.env")

    echo 'y' | npx vercel env pull "$tmp_env_file" --environment="$env"

    if [ $? -ne 0 ]; then
        echo -e "${RED}✗ Failed to pull environment variables from Vercel${NC}"
        [ -f "$tmp_env_file" ] && rm -f "$tmp_env_file"
        exit 1
    fi

    # Remove VERCEL_OIDC_TOKEN and NODE_ENV from the temporary env file
    if [ -f "$tmp_env_file" ]; then
        sed -i.bak '/^VERCEL_OIDC_TOKEN=/d; /^NODE_ENV=/d' "$tmp_env_file"
        # Clean up literal escape sequences (\n, \r, \t) from environment variable values
        sed -i.bak 's/\\n"$/"/g; s/\\r"$/"/g; s/\\t"$/"/g; s/\\n$//g; s/\\r$//g; s/\\t$//g' "$tmp_env_file"
        sed -i.bak 's/\\n//g; s/\\r//g; s/\\t//g' "$tmp_env_file"
        rm -f "$tmp_env_file.bak"
    fi

    # Collect matching variables - try exact match first, then prefix match
    declare -a matching_vars
    declare -a matching_lines
    local is_prefix=false

    # First pass: try exact match
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip empty lines and comments
        if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi

        # Extract variable name and value
        if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
            local current_var_name="${BASH_REMATCH[1]}"

            # Skip VERCEL_OIDC_TOKEN and NODE_ENV just in case
            if [[ "$current_var_name" == "VERCEL_OIDC_TOKEN" ]] || [[ "$current_var_name" == "NODE_ENV" ]]; then
                continue
            fi

            # Exact matching
            if [[ "$current_var_name" == "$var_pattern" ]]; then
                matching_vars+=("$current_var_name")
                matching_lines+=("$line")
            fi
        fi
    done < "$tmp_env_file"

    # If no exact match found, try prefix matching
    if [ ${#matching_vars[@]} -eq 0 ]; then
        is_prefix=true
        while IFS= read -r line || [ -n "$line" ]; do
            # Skip empty lines and comments
            if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
                continue
            fi

            # Extract variable name and value
            if [[ "$line" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
                local current_var_name="${BASH_REMATCH[1]}"

                # Skip VERCEL_OIDC_TOKEN and NODE_ENV just in case
                if [[ "$current_var_name" == "VERCEL_OIDC_TOKEN" ]] || [[ "$current_var_name" == "NODE_ENV" ]]; then
                    continue
                fi

                # Prefix matching: check if variable starts with the pattern
                if [[ "$current_var_name" == "$var_pattern"* ]]; then
                    matching_vars+=("$current_var_name")
                    matching_lines+=("$line")
                fi
            fi
        done < "$tmp_env_file"
    fi

    # We no longer need the temporary file
    rm -f "$tmp_env_file"

    # Check if any variables were found
    if [ ${#matching_vars[@]} -eq 0 ]; then
        echo -e "${RED}Error: No variables matching '$var_pattern' found in $env_display environment${NC}"
        exit 1
    fi

    # Display what will be pulled
    if [ "$is_prefix" = true ]; then
        echo -e "${BLUE}Pulling variables matching prefix ${GREEN}$var_pattern${BLUE} from $env_display into local .env...${NC}"
        echo -e "${YELLOW}Found ${#matching_vars[@]} variable(s) matching prefix:${NC}"
        for var in "${matching_vars[@]}"; do
            echo -e "  - ${GREEN}$var${NC}"
        done
        echo ""
    else
        echo -e "${BLUE}Pulling single variable ${GREEN}$var_pattern${BLUE} from $env_display into local .env...${NC}"
    fi

    # Ensure local .env exists
    if [ ! -f "$ENV_FILE" ]; then
        echo -e "${YELLOW}Local .env file not found. Creating a new one at $ENV_FILE${NC}"
        touch "$ENV_FILE"
    fi

    # Update each matching variable in .env
    local updated_count=0
    for i in "${!matching_vars[@]}"; do
        local var_name="${matching_vars[$i]}"
        local line="${matching_lines[$i]}"

        # Remove any existing line for this variable in .env
        if [ -f "$ENV_FILE" ]; then
            sed -i.bak "/^${var_name}=.*/d" "$ENV_FILE"
            rm -f "$ENV_FILE.bak"
        fi

        # Append the line from Vercel to .env
        echo "$line" >> "$ENV_FILE"

        echo -e "${GREEN}✓ Updated $var_name in .env${NC}"
        ((updated_count++))
    done

    echo ""
    echo -e "${GREEN}Pull complete!${NC}"
    echo -e "Updated variables in .env: ${GREEN}$updated_count${NC}"
    echo -e "${YELLOW}Note: Review the .env file and update .env.example accordingly (with masked values).${NC}"
}

# Function to delete a single environment variable or variables matching a prefix from Vercel
delete_single_env() {
    local var_pattern="$1"
    local env="$2"
    local env_display=$(echo "$env" | tr '[:lower:]' '[:upper:]')
    
    check_vercel_cli
    check_vercel_auth
    
    if [ -z "$var_pattern" ]; then
        echo -e "${RED}Error: Variable name or prefix is required${NC}"
        echo "Usage: $0 delete-single VARIABLE_NAME_OR_PREFIX [environment]"
        exit 1
    fi
    
    echo -e "${BLUE}Fetching environment variables from $env_display...${NC}"
    
    # Get list of environment variables from Vercel
    env_vars=$(npx vercel env ls "$env" 2>/dev/null | grep -v "^Environment Variables" | grep -v "^─" | awk '{print $1}' | grep -v "^$" | grep -v "^name$")
    
    if [ -z "$env_vars" ]; then
        echo -e "${YELLOW}No environment variables found in $env_display environment.${NC}"
        exit 0
    fi
    
    # Collect matching variables - try exact match first, then prefix match
    declare -a matching_vars
    local is_prefix=false
    
    # First pass: try exact match
    while IFS= read -r var_name; do
        if [ -n "$var_name" ]; then
            # Skip VERCEL_OIDC_TOKEN and NODE_ENV
            if [[ "$var_name" == "VERCEL_OIDC_TOKEN" ]] || [[ "$var_name" == "NODE_ENV" ]]; then
                continue
            fi
            
            # Exact matching
            if [[ "$var_name" == "$var_pattern" ]]; then
                matching_vars+=("$var_name")
            fi
        fi
    done <<< "$env_vars"
    
    # If no exact match found, try prefix matching
    if [ ${#matching_vars[@]} -eq 0 ]; then
        is_prefix=true
        while IFS= read -r var_name; do
            if [ -n "$var_name" ]; then
                # Skip VERCEL_OIDC_TOKEN and NODE_ENV
                if [[ "$var_name" == "VERCEL_OIDC_TOKEN" ]] || [[ "$var_name" == "NODE_ENV" ]]; then
                    continue
                fi
                
                # Prefix matching: check if variable starts with the pattern
                if [[ "$var_name" == "$var_pattern"* ]]; then
                    matching_vars+=("$var_name")
                fi
            fi
        done <<< "$env_vars"
    fi
    
    # Check if any variables were found
    if [ ${#matching_vars[@]} -eq 0 ]; then
        echo -e "${RED}Error: No variables matching '$var_pattern' found in $env_display environment${NC}"
        exit 1
    fi
    
    # Display what will be deleted
    if [ "$is_prefix" = true ]; then
        echo -e "${BLUE}Variables matching prefix ${GREEN}$var_pattern${BLUE} in $env_display environment:${NC}"
    else
        echo -e "${BLUE}Variable ${GREEN}$var_pattern${BLUE} in $env_display environment:${NC}"
    fi
    
    echo -e "${YELLOW}Found ${#matching_vars[@]} variable(s) to delete:${NC}"
    for var in "${matching_vars[@]}"; do
        echo -e "  - ${YELLOW}$var${NC}"
    done
    echo ""
    
    # Ask for confirmation
    echo -e "${RED}WARNING: This will delete the above variable(s) from the $env environment!${NC}"
    echo -e "${YELLOW}This action cannot be undone.${NC}"
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        echo -e "${YELLOW}Operation cancelled.${NC}"
        exit 0
    fi
    
    echo ""
    
    # Delete each matching variable
    local deleted_count=0
    local failed_count=0
    
    for var_name in "${matching_vars[@]}"; do
        echo -e "Deleting: ${YELLOW}$var_name${NC}"
        if echo 'y' | npx vercel env rm "$var_name" "$env" &> /dev/null; then
            echo -e "${GREEN}✓ Deleted: $var_name${NC}"
            ((deleted_count++))
        else
            echo -e "${RED}✗ Failed to delete: $var_name${NC}"
            ((failed_count++))
        fi
        echo ""
    done
    
    # Summary
    echo -e "${GREEN}Deletion complete!${NC}"
    echo -e "Successfully deleted: ${GREEN}$deleted_count${NC}"
    if [ $failed_count -gt 0 ]; then
        echo -e "Failed to delete: ${RED}$failed_count${NC}"
        exit 1
    fi
}

# Function to delete all environment variables from Vercel
delete_env() {
    local env="$1"
    local env_display=$(echo "$env" | tr '[:lower:]' '[:upper:]')
    
    echo -e "${BLUE}Deleting all $env_display environment variables from Vercel...${NC}"
    
    check_vercel_cli
    check_vercel_auth
    
    echo -e "${RED}WARNING: This will delete ALL environment variables from the $env environment!${NC}"
    echo -e "${YELLOW}This action cannot be undone.${NC}"
    read -p "Are you sure you want to continue? (yes/no): " confirmation
    
    if [[ "$confirmation" != "yes" ]]; then
        echo -e "${YELLOW}Operation cancelled.${NC}"
        exit 0
    fi
    
    echo -e "${BLUE}Fetching environment variables from $env_display...${NC}"
    
    # Get list of environment variables
    env_vars=$(npx vercel env ls "$env" 2>/dev/null | grep -v "^Environment Variables" | grep -v "^─" | awk '{print $1}' | grep -v "^$" | grep -v "^name$")
    
    if [ -z "$env_vars" ]; then
        echo -e "${YELLOW}No environment variables found in $env_display environment.${NC}"
        exit 0
    fi
    
    echo -e "${BLUE}Found the following variables:${NC}"
    echo "$env_vars"
    echo ""
    
    # Delete each variable
    deleted_count=0
    failed_count=0
    
    while IFS= read -r var_name; do
        if [ -n "$var_name" ]; then
            echo -e "Deleting: ${YELLOW}$var_name${NC}"
            if echo 'y' | npx vercel env rm "$var_name" "$env" &> /dev/null; then
                echo -e "${GREEN}✓ Deleted: $var_name${NC}"
                ((deleted_count++))
            else
                echo -e "${RED}✗ Failed to delete: $var_name${NC}"
                ((failed_count++))
            fi
        fi
    done <<< "$env_vars"
    
    echo ""
    echo -e "${GREEN}Deletion complete!${NC}"
    echo -e "Successfully deleted: ${GREEN}$deleted_count${NC}"
    if [ $failed_count -gt 0 ]; then
        echo -e "Failed to delete: ${RED}$failed_count${NC}"
    fi
}

# Function to display usage
usage() {
	echo "Usage: $0 {pull|pull-single|push|push-single|delete-single|delete} [arguments]"
    echo ""
    echo "Commands:"
   	echo "  pull [env]              Pull environment variables from Vercel to .env"
   	echo "                          Default: development"
   	echo "                          Options: development, preview, production"
   	echo ""
   	echo "  pull-single VAR [env]   Pull a single environment variable or variables matching a prefix"
   	echo "                          from Vercel into local .env"
   	echo "                          VAR: Variable name or prefix (required)"
   	echo "                          Default environment: development"
   	echo "                          Options: development, preview, production"
   	echo ""
   	echo "  push [env]              Push environment variables from .env to Vercel"
   	echo "                          Default: development"
   	echo "                          Options: development, preview, production"
    echo ""
    echo "  push-single VAR [env]   Push a single environment variable or variables matching a prefix"
    echo "                          from .env to Vercel"
    echo "                          VAR: Variable name or prefix (required)"
    echo "                          Default environment: development"
    echo "                          Options: development, preview, production"
    echo ""
    echo "  delete-single VAR [env] Delete a single environment variable or variables matching a prefix"
    echo "                          from Vercel"
    echo "                          VAR: Variable name or prefix (required)"
    echo "                          Default environment: development"
    echo "                          Options: development, preview, production"
    echo "                          WARNING: This action cannot be undone!"
    echo ""
    echo "  delete [env]            Delete ALL environment variables from Vercel environment"
    echo "                          Default: development"
    echo "                          Options: development, preview, production"
    echo "                          WARNING: This action cannot be undone!"
    echo ""
    echo "Examples:"
   	echo "  $0 pull                              # Pull from development (default)"
   	echo "  $0 pull preview                      # Pull from preview"
   	echo "  $0 pull-single SESSION_              # Pull all SESSION_* vars into local .env from development"
   	echo "  $0 pull-single SESSION_ preview      # Pull all SESSION_* vars into local .env from preview"
   	echo "  $0 pull-single SESSION_ production   # Pull all SESSION_* vars into local .env from production"
   	echo "  $0 push                              # Push to development (default)"
   	echo "  $0 push production                   # Push to production"
   	echo "  $0 push-single SESSION_              # Push all SESSION_* vars to development"
   	echo "  $0 push-single SESSION_ preview      # Push all SESSION_* vars to preview"
   	echo "  $0 push-single SESSION_ production   # Push all SESSION_* vars to production"
   	echo "  $0 delete-single SESSION_            # Delete all SESSION_* vars from development"
   	echo "  $0 delete-single SESSION_ preview    # Delete all SESSION_* vars from preview"
   	echo "  $0 delete-single SESSION_ production # Delete all SESSION_* vars from production"
   	echo "  $0 delete preview                    # Delete all variables from preview"
    echo ""
    echo "Note: VERCEL_OIDC_TOKEN and NODE_ENV are automatically ignored (for pull/push)"
    echo ""
    echo "Prerequisites:"
    echo "  - Node.js and npm installed (npx comes with npm)"
    echo "  - Logged in to Vercel (npx vercel login)"
    echo "  - Linked to a Vercel project (npx vercel link)"
}

# Main script logic
COMMAND="${1:-}"
ENVIRONMENT="${2:-development}"

case "$COMMAND" in
	pull)
		pull_env "$ENVIRONMENT"
		;;
	pull-single)
		VAR_NAME="${2:-}"
		ENV_ARG="${3:-development}"
		pull_single_env "$VAR_NAME" "$ENV_ARG"
		;;
	push)
		push_env "$ENVIRONMENT"
		;;
	push-single)
		VAR_NAME="${2:-}"
		ENV_ARG="${3:-development}"
		push_single_env "$VAR_NAME" "$ENV_ARG"
		;;
	delete-single)
		VAR_NAME="${2:-}"
		ENV_ARG="${3:-development}"
		delete_single_env "$VAR_NAME" "$ENV_ARG"
		;;
	delete)
		delete_env "$ENVIRONMENT"
		;;
	*)
		usage
		exit 1
		;;
esac
