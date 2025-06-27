#!/bin/zsh

# Usage: ./convert_images.zsh [--overwrite] [--path relative/path]

set -e

SOURCE_BASE=$(realpath "./assets/images/")
DEST_BASE=$(realpath "./assets/optimized_images/")
OVERWRITE=false
RELATIVE_PATH=""

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --overwrite)
      OVERWRITE=true
      shift
      ;;
    --path)
      RELATIVE_PATH="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: ./convert_images.zsh [--overwrite] [--path relative/path]"
      exit 1
      ;;
  esac
done

# Set final source and destination directories
if [[ -n "$RELATIVE_PATH" ]]; then
  SOURCE_DIR="$SOURCE_BASE/$RELATIVE_PATH"
  DEST_DIR="$DEST_BASE/$RELATIVE_PATH"
else
  SOURCE_DIR="$SOURCE_BASE"
  DEST_DIR="$DEST_BASE"
fi

# Ensure directories exist and normalize paths
mkdir -p "$SOURCE_DIR" "$DEST_DIR"
SOURCE_DIR=$(cd "$SOURCE_DIR"; pwd)
DEST_DIR=$(cd "$DEST_DIR"; pwd)

# Extensions and target widths
IMAGE_EXTENSIONS=(jpg jpeg png webp tif tiff bmp gif)
TARGET_WIDTHS=(384 512 640 768 1024 1280 1920 2560)  # AVIF sizes
WEBP_WIDTH=512               # Only one WebP fallback at this width
ASPECT_RATIO=1.6             # 16:10 aspect ratio

if [[ -n "$RELATIVE_PATH" ]]; then
  echo "🔍 Scanning '$SOURCE_DIR' (relative path: $RELATIVE_PATH) for images..."
else
  echo "🔍 Scanning '$SOURCE_DIR' for images..."
fi

# Build find command with proper zsh array handling and exclude hidden files
find_args=("$SOURCE_DIR" \( -iname "*.mp4")
for ext in $IMAGE_EXTENSIONS; do
  find_args+=(-o -iname "*.$ext")
done
find_args+=(\) -not -path "*/.*")

find "${find_args[@]}" | while read FILE; do
  REL_PATH="${FILE#$SOURCE_DIR/}"
  DEST_PATH="$DEST_DIR/$REL_PATH"
  DEST_DIR_PATH=${DEST_PATH:h}

  mkdir -p "$DEST_DIR_PATH"

  EXT="${FILE:e}"
  EXT_LOWER=${(L)EXT}
  BASENAME=${${REL_PATH:t}:r}

  if [[ "$EXT_LOWER" == "mp4" ]]; then
    if [[ "$OVERWRITE" = true || ! -f "$DEST_PATH" ]]; then
      echo "📼 Copying MP4: $REL_PATH"
      cp "$FILE" "$DEST_PATH"
    else
      echo "📼 Skipping existing MP4: $REL_PATH"
    fi
  else
    # Check if we need to process any outputs for this image
    NEED_PROCESSING=false
    
    # First check if any AVIF files are missing
    for WIDTH in $TARGET_WIDTHS; do
      AVIF_OUT="$DEST_DIR_PATH/${BASENAME}-${WIDTH}w.avif"
      if [[ "$OVERWRITE" = true || ! -f "$AVIF_OUT" ]]; then
        NEED_PROCESSING=true
        break
      fi
    done
    
    # Check WebP if no AVIF processing needed
    if [[ "$NEED_PROCESSING" = false ]]; then
      WEBP_OUT="$DEST_DIR_PATH/${BASENAME}-${WEBP_WIDTH}w.webp"
      if [[ "$OVERWRITE" = true || ! -f "$WEBP_OUT" ]]; then
        NEED_PROCESSING=true
      fi
    fi
    
    # Skip entirely if nothing needs processing
    if [[ "$NEED_PROCESSING" = false ]]; then
      echo "🖼️  Skipping $REL_PATH (all outputs exist)"
      continue
    fi

    echo "🖼️  Processing image: $REL_PATH"

    # Get original dimensions using -ping for faster header-only read
    IMG_DIMS=($(identify -ping -format "%w %h" "$FILE"))
    IMG_WIDTH=$IMG_DIMS[1]
    IMG_HEIGHT=$IMG_DIMS[2]

    for WIDTH in $TARGET_WIDTHS; do
      # Calculate minimum height for this width
      MIN_HEIGHT=$(( (WIDTH * 10) / (ASPECT_RATIO * 10) ))
      
      # Scale factor if image height would be too low
      SCALE_WIDTH=$WIDTH
      if (( IMG_HEIGHT * WIDTH / IMG_WIDTH < MIN_HEIGHT )); then
        SCALE_WIDTH=$(( IMG_WIDTH * MIN_HEIGHT / IMG_HEIGHT ))
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