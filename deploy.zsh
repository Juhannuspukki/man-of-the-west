#!/bin/zsh

# Enable better error handling
set -o errexit
set -o pipefail
set -o nounset

# Enable extended globbing for zsh
setopt extended_glob

# Colors for output
local RED='\033[0;31m'
local GREEN='\033[0;32m'
local YELLOW='\033[1;33m'
local BLUE='\033[0;34m'
local NC='\033[0m' # No Color

# Load environment variables from .env file if it exists
local ENV_FILE="${0:A:h}/.env"
if [[ -f "$ENV_FILE" ]]; then
    print -P "%F{blue}\n🔍 Loading environment variables from ${ENV_FILE}...\n%f"
    # Use zsh's built-in source command to load the .env file
    source "$ENV_FILE"
    # Export all variables from .env
    export $(grep -v '^#' "$ENV_FILE" | xargs)
else
    print -P "%F{yellow}⚠️  .env file not found. Using system environment variables.\n%f"
fi

# Check for required commands
local required_commands=(hugo wrangler rclone)
for cmd in "${required_commands[@]}"; do
    if ! command -v "$cmd" &> /dev/null; then
        print -P "%F{red}❌ Error: $cmd is not installed.\n%f"
        exit 1
    fi
done

# Check if R2 environment variables are set
if [[ -z "${R2_BUCKET_NAME:-}" ]]; then
    print -P "%F{red}❌ R2_BUCKET_NAME is not set. Please check your .env file.\n%f"
    exit 1
fi

print -P "%F{blue}🚀 Starting deployment process...\n%f"

# Remove public directory if it exists
if [[ -d "public" ]]; then
    print -P "%F{yellow}🗑️  Removing existing public directory...\n%f"
    rm -rf public
fi

# Build Hugo site with minification
print -P "%F{blue}🔨 Building site with Hugo...\n%f"
hugo --minify || {
    print -P "%F{red}❌ Hugo build failed!%f"
    exit 1
}

# Upload optimized images to R2 if the directory exists
if [[ -d "assets/optimized_images" ]]; then
    print -P "%F{blue}\n☁️  Uploading optimized images to R2 bucket '${R2_BUCKET_NAME}'...\n%f"
    rclone copy ./assets/optimized_images "r2:${R2_BUCKET_NAME}" --ignore-existing --progress --exclude ".DS_Store" || {
        print -P "%F{red}❌ Failed to upload images to R2!%f"
        exit 1
    }
    print -P "%F{green}\n✅ Successfully uploaded optimized images to R2%f"
else
    print -P "%F{yellow}⚠️  No optimized_images directory found. Skipping R2 upload.%f"
fi

# Deploy to Cloudflare Pages
print -P "%F{blue}\n☁️  Deploying to Cloudflare Pages...\n%f"
wrangler pages deploy || {
    print -P "%F{red}❌ Deployment failed!\n%f"
    exit 1
}

print -P "%F{green}\n✅ Deployment complete!%f"
