#!/bin/bash

# Usage: ./convert_images.sh [--overwrite]

set -e

SOURCE_DIR=$(realpath "./assets/images/")
DEST_DIR=$(realpath "./assets/optimized_images/")
OVERWRITE=false

if [[ "$1" == "--overwrite" ]]; then
  OVERWRITE=true
fi

# Normalize paths
SOURCE_DIR=$(cd "$SOURCE_DIR"; pwd)
DEST_DIR=$(cd "$DEST_DIR"; pwd)

# Extensions and target widths
IMAGE_EXTENSIONS="jpg jpeg png tif tiff bmp gif"
TARGET_WIDTHS=(384 512 640 768 1024 1280 1920 2560)  # AVIF sizes
WEBP_WIDTH=512               # Only one WebP fallback at this width
ASPECT_RATIO=1.6             # 16:10 aspect ratio

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
    if [[ "$OVERWRITE" = true || ! -f "$DEST_PATH" ]]; then
      echo "📼 Copying MP4: $REL_PATH"
      cp "$FILE" "$DEST_PATH"
    else
      echo "📼 Skipping existing MP4: $REL_PATH"
    fi
  else
    echo "🖼️  Processing image: $REL_PATH"

    # Get original dimensions
    read IMG_WIDTH IMG_HEIGHT <<< $(identify -format "%w %h" "$FILE")

    for WIDTH in "${TARGET_WIDTHS[@]}"; do
      # Calculate minimum height for this width
      MIN_HEIGHT=$(awk "BEGIN { printf \"%d\", $WIDTH / $ASPECT_RATIO }")
      
      # Scale factor if image height would be too low
      SCALE_WIDTH=$WIDTH
      if (( IMG_HEIGHT * WIDTH / IMG_WIDTH < MIN_HEIGHT )); then
        SCALE_WIDTH=$(awk "BEGIN { printf \"%d\", $IMG_WIDTH * $MIN_HEIGHT / $IMG_HEIGHT }")
      fi

      AVIF_OUT="$DEST_DIR_PATH/${BASENAME}-${WIDTH}w.avif"
      if [[ "$OVERWRITE" = true || ! -f "$AVIF_OUT" ]]; then
        echo "  - AVIF ${WIDTH}w (resized to width ${SCALE_WIDTH})"
        magick "$FILE" -strip -resize "${SCALE_WIDTH}" -quality 60 "$AVIF_OUT"
      else
        echo "  - Skipping existing AVIF ${WIDTH}w"
      fi
    done

    WEBP_OUT="$DEST_DIR_PATH/${BASENAME}-${WEBP_WIDTH}w.webp"
    if [[ "$OVERWRITE" = true || ! -f "$WEBP_OUT" ]]; then
      echo "  - WebP fallback ${WEBP_WIDTH}w"
      magick "$FILE" -strip -resize "${WEBP_WIDTH}" -quality 80 "$WEBP_OUT"
    else
      echo "  - Skipping existing WebP fallback"
    fi
  fi
done

echo "✅ All images processed (AVIF at multiple widths + WebP fallback)."