#!/bin/bash

# Hugo Front Matter Key Renamer
# Renames keys in YAML front matter of Hugo markdown files

set -e

# Configuration
CONTENT_DIR="./content"
DRY_RUN=false
BACKUP=true

# Key mappings - modify as needed
# Format: "old_key:new_key"
declare -a KEY_MAPPINGS=(
    "people:henkilöhahmot"
    "tag:tags"
    "category:categories"
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage function
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --dir DIR        Content directory (default: ./content)"
    echo "  -n, --dry-run        Show what would be changed without modifying files"
    echo "  -b, --no-backup      Don't create backup files"
    echo "  -h, --help           Show this help message"
    echo ""
    echo "Key mappings are configured in the script itself."
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dir)
            CONTENT_DIR="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -b|--no-backup)
            BACKUP=false
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Check dependencies
check_dependencies() {
    if ! command -v yq &> /dev/null; then
        echo -e "${RED}Error: yq is not installed${NC}"
        echo "Install with: brew install yq"
        exit 1
    fi
}

# Extract front matter from markdown file
extract_front_matter() {
    local file="$1"
    awk '/^---$/{if(NR==1){p=1; next} else {p=0}} p' "$file"
}

# Extract content (everything after front matter)
extract_content() {
    local file="$1"
    awk '/^---$/{if(NR==1){p=1; c=0; next} else if(p==1){p=0; c=1; next}} c' "$file"
}

# Check if file has valid front matter
has_front_matter() {
    local file="$1"
    head -1 "$file" | grep -q "^---$"
}

# Process a single file
process_file() {
    local file="$1"
    local changed=false
    local temp_yaml=$(mktemp)
    
    echo -e "${BLUE}Processing: $file${NC}"
    
    # Check if file has front matter
    if ! has_front_matter "$file"; then
        echo -e "${YELLOW}  Skipping: No front matter found${NC}"
        rm "$temp_yaml"
        return
    fi
    
    # Extract front matter to temp file
    extract_front_matter "$file" > "$temp_yaml"
    
    # Check if YAML is valid
    if ! yq eval '.' "$temp_yaml" > /dev/null 2>&1; then
        echo -e "${YELLOW}  Skipping: Invalid YAML front matter${NC}"
        rm "$temp_yaml"
        return
    fi
    
    # Process key mappings
    local modified_yaml="$temp_yaml"
    for mapping in "${KEY_MAPPINGS[@]}"; do
        local old_key="${mapping%:*}"
        local new_key="${mapping#*:}"
        
        # Check if old key exists
        if yq eval "has(\"$old_key\")" "$modified_yaml" | grep -q "true"; then
            echo -e "${GREEN}  Renaming: '$old_key' → '$new_key'${NC}"
            
            # Create new temp file with renamed key
            local next_temp=$(mktemp)
            yq eval ".$new_key = .$old_key | del(.$old_key)" "$modified_yaml" > "$next_temp"
            rm "$modified_yaml"
            modified_yaml="$next_temp"
            changed=true
        fi
    done
    
    # If no changes, clean up and return
    if [ "$changed" = false ]; then
        rm "$modified_yaml"
        return
    fi
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}  DRY RUN: Would update file${NC}"
        rm "$modified_yaml"
        return
    fi
    
    # Create backup if requested
    if [ "$BACKUP" = true ]; then
        cp "$file" "${file}.bak"
        echo -e "${BLUE}  Created backup: ${file}.bak${NC}"
    fi
    
    # Reconstruct file with modified front matter
    local temp_file=$(mktemp)
    {
        echo "---"
        cat "$modified_yaml"
        echo "---"
        extract_content "$file"
    } > "$temp_file"
    
    # Replace original file
    mv "$temp_file" "$file"
    echo -e "${GREEN}  Updated: $file${NC}"
    
    rm "$modified_yaml"
}

# Process directory recursively
process_directory() {
    local dir="$1"
    
    find "$dir" -type f \( -name "*.md" -o -name "*.markdown" \) | while read -r file; do
        process_file "$file"
    done
}

# Main function
main() {
    echo "Hugo Front Matter Key Renamer"
    echo "============================"
    echo ""
    
    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}🔍 DRY RUN MODE - No files will be modified${NC}"
    fi
    
    echo "Content directory: $CONTENT_DIR"
    echo "Backup files: $BACKUP"
    echo ""
    echo "Key mappings:"
    for mapping in "${KEY_MAPPINGS[@]}"; do
        local old_key="${mapping%:*}"
        local new_key="${mapping#*:}"
        echo "  $old_key → $new_key"
    done
    echo ""
    
    # Check if content directory exists
    if [ ! -d "$CONTENT_DIR" ]; then
        echo -e "${RED}Error: Content directory '$CONTENT_DIR' not found${NC}"
        exit 1
    fi
    
    # Check dependencies
    check_dependencies
    
    # Process files
    process_directory "$CONTENT_DIR"
    
    echo ""
    echo -e "${GREEN}Processing complete!${NC}"
    
    if [ "$BACKUP" = true ] && [ "$DRY_RUN" = false ]; then
        echo -e "${BLUE}Backup files created with .bak extension${NC}"
    fi
}

# Run main function
main "$@"