#!/bin/bash
set -euo pipefail
IFS=$'\n\t'

CONTENT_DIR="./content/"
IMAGE_DIR="./assets/images"
COLOR_COUNT=6 # Grab more, we'll filter down
PALETTE_SIZE=3
BRIGHTNESS_FACTOR=3
MAX_ALLOWED_BRIGHTNESS=230   # Above this: skip brightening
MIN_ALLOWED_BRIGHTNESS=160
SCORE_WEIGHT=1.9  # Tune this: how much to prioritize saturation
HUE_PENALTY_WEIGHT=250   # How much to penalize very similar hues (try 10–40)
HUE_PENALTY_THRESHOLD=30
PERCENTAGE_WEIGHT=250       # Penalty strength for low-percentage colors
PERCENTAGE_THRESHOLD=0.02 # Threshold below which colors are penalized

OVERWRITE=false
for arg in "$@"; do
  if [[ "$arg" == "--overwrite" ]]; then
    OVERWRITE=true
  fi
done

rgb_to_hex() {
  IFS=',' read -r r g b <<<"${1// /}"
  printf "#%02x%02x%02x" "$r" "$g" "$b"
}

# Convert hex to RGB
hex_to_rgb() {
  local hex="$1"
  # Remove # if present
  hex="${hex#\#}"
  
  # Convert hex to RGB
  local r=$((16#${hex:0:2}))
  local g=$((16#${hex:2:2}))
  local b=$((16#${hex:4:2}))
  
  printf "%d,%d,%d" "$r" "$g" "$b"
}

# Convert RGB to Lab using ImageMagick
rgb_to_lab() {
  local r=$1 g=$2 b=$3
  magick xc:"rgb($r,$g,$b)" -colorspace Lab -format "%[fx:u.r*100],%[fx:u.g*255-128],%[fx:u.b*255-128]" info:
}

color_distance() {
  IFS=',' read -r l1 a1 b1 <<< "$1"
  IFS=',' read -r l2 a2 b2 <<< "$2"
  awk -v l1="$l1" -v a1="$a1" -v b1="$b1" -v l2="$l2" -v a2="$a2" -v b2="$b2" '
    BEGIN {
      d = sqrt((l1-l2)^2 + (a1-a2)^2 + (b1-b2)^2);
      printf "%.2f", d
    }'
}

# Brightens a color with dynamic scaling up to MAX_ALLOWED_BRIGHTNESS
brighten_rgb() {
  IFS=',' read -r r g b <<<"${1// /}"
  
  calculate_scale() {
    local val=$1
    if (( val == 0 )); then
      echo "$BRIGHTNESS_FACTOR"
      return
    fi
    local max_scale=$(awk -v max="$MAX_ALLOWED_BRIGHTNESS" -v v="$val" 'BEGIN {printf "%.2f", max / v}')
    awk -v bf="$BRIGHTNESS_FACTOR" -v ms="$max_scale" 'BEGIN {printf "%.2f", (bf < ms) ? bf : ms}'
  }

  local r_scale=$(calculate_scale "$r")
  local g_scale=$(calculate_scale "$g")
  local b_scale=$(calculate_scale "$b")
  local scale=$(printf "%s\n%s\n%s" "$r_scale" "$g_scale" "$b_scale" | sort -n | head -n1)

  local r_new=$(awk -v r="$r" -v s="$scale" 'BEGIN {v=int(r * s); print (v > 255 ? 255 : v)}')
  local g_new=$(awk -v g="$g" -v s="$scale" 'BEGIN {v=int(g * s); print (v > 255 ? 255 : v)}')
  local b_new=$(awk -v b="$b" -v s="$scale" 'BEGIN {v=int(b * s); print (v > 255 ? 255 : v)}')

  # Calculate perceived brightness
  perceived_brightness=$(awk -v r="$r_new" -v g="$g_new" -v b="$b_new" \
    'BEGIN { printf "%.2f", 0.2126 * r + 0.7152 * g + 0.0722 * b }')

  if (( $(awk -v p="$perceived_brightness" -v min="$MIN_ALLOWED_BRIGHTNESS" 'BEGIN {print (p < min)}') )); then
    brightness_scale=$(awk -v min="$MIN_ALLOWED_BRIGHTNESS" -v p="$perceived_brightness" 'BEGIN {printf "%.2f", min / p}')
    
    r_new=$(awk -v c="$r_new" -v s="$brightness_scale" 'BEGIN {v=int(c * s); print (v > 255 ? 255 : v)}')
    g_new=$(awk -v c="$g_new" -v s="$brightness_scale" 'BEGIN {v=int(c * s); print (v > 255 ? 255 : v)}')
    b_new=$(awk -v c="$b_new" -v s="$brightness_scale" 'BEGIN {v=int(c * s); print (v > 255 ? 255 : v)}')
  fi

  printf "%d,%d,%d" "$r_new" "$g_new" "$b_new"
}

find "$CONTENT_DIR" -type f -name "*.md" | while read -r md_file; do
  echo "Processing $md_file"

  # Check for existing .palette
  existing_palette=$(yq eval --front-matter=extract '.palette' "$md_file" 2>/dev/null || echo "")
  if [[ "$existing_palette" != "null" && -n "$existing_palette" && "$OVERWRITE" != "true" ]]; then
    echo "  Skipping (palette already exists; use --overwrite to force)"
    continue
  fi
  start_time=$(date +%s.%N)

  banner_path=$(yq eval --front-matter=extract '.banner' "$md_file" 2>/dev/null || echo "")
  echo "  banner: $banner_path"

  if [[ -z "$banner_path" || "$banner_path" == "null" ]]; then
    echo "  Skipping (no banner)"
    continue
  fi

  full_image_path="$IMAGE_DIR/$banner_path"
  if [[ ! -f "$full_image_path" ]]; then
    echo "  Image not found: $full_image_path"
    continue
  fi

  # Create a temporary file for the downsampled image (macOS compatible)
  temp_image="$(mktemp -t tmp.XXXXXXXXXX).jpg" || { echo "  Failed to create temp file"; continue; }
  
  # Downsample the image, longest side 512px, maintaining aspect ratio
  echo "  Downsampling image..."
  if ! magick "$full_image_path" -resize '512x512>' "$temp_image"; then
    echo "  Failed to downsample image, using original"
    # Only remove if the file was created
    [[ -f "$temp_image" ]] && rm -f "$temp_image"
    temp_image="$full_image_path"
  else
    # If downsampling succeeded, use the temp file for color extraction
    color_output=$(kmeans_colors -i "$temp_image" -k $COLOR_COUNT -p --pct --no-file 2>/dev/null || echo "")
    # Clean up the temporary file
    rm -f "$temp_image"
  fi

  # If we're using the original image or downsampling failed
  if [[ -z "${color_output:-}" && -f "$full_image_path" ]]; then
    color_output=$(kmeans_colors -i "$full_image_path" -k $COLOR_COUNT -p --pct --no-file 2>/dev/null || echo "")
  fi
  
  if [[ -z "$color_output" ]]; then
    echo "  Failed to extract colors from $full_image_path"
    continue
  fi

  echo "  kmeans_colors output:"
  echo "$color_output"

  # Parse the output - kmeans_colors outputs hex colors on one line, percentages on the next
  color_lines=$(echo "$color_output" | tail -n 2)
  hex_colors=$(echo "$color_lines" | head -n 1)
  percentages=$(echo "$color_lines" | tail -n 1)

  # Convert comma-separated hex colors to array
  IFS=',' read -ra hex_array <<< "$hex_colors"
  IFS=',' read -ra pct_array <<< "$percentages"

  scored_colors=()
  used_labs=()
  
  for i in "${!hex_array[@]}"; do
    hex_color="${hex_array[i]}"
    percentage="${pct_array[i]:-0}"
    
    # Convert hex to RGB
    rgb=$(hex_to_rgb "$hex_color")
    IFS=',' read -r r g b <<<"$rgb"

    brightness=$(( (r + g + b) / 3 ))

    min_rgb=$(printf "%s\n" "$r" "$g" "$b" | sort -n | head -1)
    max_rgb=$(printf "%s\n" "$r" "$g" "$b" | sort -n | tail -1)
    saturation=$(( max_rgb - min_rgb ))

    # Use percentage as additional weight factor
    # Calculate each component
    sat_contrib=$(awk -v s="$saturation" -v w="$SCORE_WEIGHT" 'BEGIN { printf "%.2f", s * w }')
    # Calculate percentage contribution with threshold logic
    # Apply penalty only if below threshold
    pct_contrib=$(awk -v p="$percentage" -v w="$PERCENTAGE_WEIGHT" -v t="$PERCENTAGE_THRESHOLD" '
      BEGIN {
        if (p < t) {
          diff = t - p
          printf "%.2f", -1 * diff * 100 * w
        } else {
          printf "0.00"
        }
      }')
    base_score=$(awk -v b="$brightness" -v sc="$sat_contrib" -v pc="$pct_contrib" 'BEGIN { printf "%.2f", b + sc + pc }')

    rgb_lab=$(rgb_to_lab "$r" "$g" "$b" 2>/dev/null || echo "")
    if [[ -z "$rgb_lab" ]]; then
      echo "  Skipping (failed to convert $rgb to Lab)"
      continue
    fi

    penalty=0
    for existing_lab in "${used_labs[@]:-}"; do
      dist=$(color_distance "$rgb_lab" "$existing_lab")
      if (( $(awk "BEGIN {print ($dist < $HUE_PENALTY_THRESHOLD)}") )); then
        falloff=$(awk -v d="$dist" -v w="$HUE_PENALTY_WEIGHT" -v maxd="$HUE_PENALTY_THRESHOLD" \
          'BEGIN { norm = 1 - (d / maxd); printf "%.2f", w * norm }')
        penalty=$(awk -v p="$penalty" -v f="$falloff" 'BEGIN { printf "%.2f", p + f }')
      fi
    done

    used_labs+=("$rgb_lab")

    if (( $(awk "BEGIN {print ($percentage >= $PERCENTAGE_THRESHOLD)}") )); then
      pct_note="bonus"
    else
      pct_note="penalty"
    fi

    score=$(awk -v s="$base_score" -v p="$penalty" 'BEGIN { printf "%.2f", s - p }')

    printf "\e[38;2;%s;%s;%sm" "$r" "$g" "$b"
    echo -e "Color → Score: $score | Bright: $brightness | Sat×$SCORE_WEIGHT: $sat_contrib | %×$PERCENTAGE_WEIGHT ($pct_note): $pct_contrib | Lab penalty: $penalty | RGB: $rgb | %: $percentage"
    printf "\e[0m"

    scored_colors+=("$score:$rgb")
  done

  # Sort scored colors descending
  sorted=()
  while IFS= read -r line; do
    sorted+=("$line")
  done < <(printf '%s\n' "${scored_colors[@]}" | sort -t: -k1,1nr)

  # Select top N
  top_colors=()
  for entry in "${sorted[@]}"; do
    score="${entry%%:*}"
    rgb="${entry#*:}"

    IFS=',' read -r r g b <<< "$rgb"

    # Brighten and convert
    bright_rgb=$(brighten_rgb "$rgb")
    hex=$(rgb_to_hex "$bright_rgb")

    # Avoid duplicates
    already_present=0
    for c in "${top_colors[@]:-}"; do
      [[ "$c" == "$hex" ]] && already_present=1 && break
    done

    if [[ "$already_present" -eq 0 ]]; then
      top_colors+=("$hex")
    fi

    (( ${#top_colors[@]} >= PALETTE_SIZE )) && break
  done

  palette=$(IFS=, ; echo "${top_colors[*]}")
  echo "  Final palette: $palette"

  # Split file: extract front matter and body separately
  front="$(awk '/^---/{f=!f; next} f' "$md_file")"
  body="$(awk 'BEGIN{p=0} /^---/ {c++; next} c==2{p=1} p' "$md_file" | sed '/./,$!d')"

  # Modify front matter safely
  new_front=$(echo "$front" | yq eval ".palette = \"$palette\"" -)

  # Reassemble
  {
    echo "---"
    echo "$new_front"
    echo "---"
    printf "%s\n" "$body"
  } > "$md_file"
  
  end_time=$(date +%s.%N)
  duration=$(echo "$end_time - $start_time" | bc)
  echo "  Generated gradient in ${duration}s"
  echo ""  # Add empty line for better readability between files
done