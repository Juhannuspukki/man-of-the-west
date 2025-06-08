#!/bin/bash

# Usage: ./convert_images.sh

set -e

SOURCE_DIR=$(realpath "./assets/images")
DEST_DIR=$(realpath "./assets/optimized_images")

if [[ -z "$SOURCE_DIR" || -z "$DEST_DIR" ]]; then
  echo "Usage: $0 <source_dir> <dest_dir>"
  exit 1
fi

# Normalize paths
SOURCE_DIR=$(cd "$SOURCE_DIR"; pwd)
DEST_DIR=$(cd "$DEST_DIR"; pwd)

# Extensions and target widths
IMAGE_EXTENSIONS="jpg jpeg png tif tiff bmp gif"
TARGET_WIDTHS=(384 512 640 768 1024 1280 1920 2560)  # AVIF sizes
WEBP_WIDTH=512               # Only one WebP fallback at this width

echo "🔍 Scanning '$SOURCE_DIR' for images..."

find "$SOURCE_DIR" \( -iname "*.mp4" $(for ext in $IMAGE_EXTENSIONS; do echo -o -iname "*.$ext"; done) \) | while read FILE; do
  REL_PATH="${FILE#$SOURCE_DIR/}"
  DEST_PATH="$DEST_DIR/$REL_PATH"
  DEST_DIR_PATH=$(dirname "$DEST_PATH")

  mkdir -p "$DEST_DIR_PATH"

  EXT="${FILE##*.}"
  EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')
  BASENAME=$(basename "$REL_PATH" ".$EXT_LOWER")

  if [[ "$EXT_LOWER" == "mp4" ]]; then
    if [[ ! -f "$DEST_PATH" ]]; then
      echo "📼 Copying MP4: $REL_PATH"
      cp "$FILE" "$DEST_PATH"
    else
      echo "📼 Skipping existing MP4: $REL_PATH"
    fi
  else
    echo "🖼️  Processing image: $REL_PATH"

    for WIDTH in "${TARGET_WIDTHS[@]}"; do
      AVIF_OUT="$DEST_DIR_PATH/${BASENAME}-${WIDTH}w.avif"
      if [[ ! -f "$AVIF_OUT" ]]; then
        echo "  - AVIF ${WIDTH}w"
        magick "$FILE" -strip -resize "${WIDTH}" -quality 60 "$AVIF_OUT"
      else
        echo "  - Skipping existing AVIF ${WIDTH}w"
      fi
    done

    WEBP_OUT="$DEST_DIR_PATH/${BASENAME}-${WEBP_WIDTH}w.webp"
    if [[ ! -f "$WEBP_OUT" ]]; then
      echo "  - WebP fallback ${WEBP_WIDTH}w"
      magick "$FILE" -strip -resize "${WEBP_WIDTH}" -quality 80 "$WEBP_OUT"
    else
      echo "  - Skipping existing WebP fallback"
    fi
  fi
done

echo "✅ All images processed (AVIF at multiple widths + WebP fallback)."