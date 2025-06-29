#!/bin/zsh
setopt ERR_EXIT PIPE_FAIL NO_UNSET
IFS=$'\n\t'

CONTENT_DIR="./content"
IMAGE_DIR="./assets/images"
THUMB_SIZE="32x32"

OVERWRITE=false
[[ "${1:-}" == "--overwrite" ]] && OVERWRITE=true

find "$CONTENT_DIR" -type f -name "*.md" | while read -r md_file; do
  print "🏞️   Processing $md_file"
  start_time=$(date +%s.%N)


  # Skip if thumbnail is already set and not overwriting
  existing_thumb=$(yq eval --front-matter=extract '.thumbnail' "$md_file" 2>/dev/null || echo "")
  if [[ -n "$existing_thumb" && "$existing_thumb" != "null" && "$OVERWRITE" != true ]]; then
    print "  Skipping (thumbnail already exists)"
    continue
  fi

  banner_path=$(yq eval --front-matter=extract '.banner' "$md_file" 2>/dev/null || print "")
  print "  banner: $banner_path"

  if [[ -z "$banner_path" || "$banner_path" == "null" ]]; then
    print "  Skipping (no banner)"
    continue
  fi

  full_image_path="$IMAGE_DIR/$banner_path"
  if [[ ! -f "$full_image_path" ]]; then
    print "  Image not found: $full_image_path"
    continue
  fi

  ####################
  # Generate AVIF Base64
  ####################
  tmp_rgb=$(mktemp -t thumb_rgb_XXXXXX).png # convert to png first, it seems to result in overall better quality and colors
  tmp_avif=$(mktemp -t thumb_avif_XXXXXX).avif
  magick "$full_image_path" -resize "$THUMB_SIZE" -strip +set date:create +set date:modify "$tmp_rgb"
  avifenc --min 20 --max 30 "$tmp_rgb" "$tmp_avif" >/dev/null 2>&1 || {
    print "  Failed to encode AVIF"
    rm -f "$tmp_rgb" "$tmp_avif"
    continue
  }
  base64_avif=$(base64 -i "$tmp_avif")
  avif_size=$(printf "%s" "$base64_avif" | LC_ALL=C wc -c | awk '{print $1}')
  rm "$tmp_rgb" "$tmp_avif"

  ####################
  # Update Front Matter
  ####################
  front="$(awk '/^---/{f=!f; next} f' "$md_file")"
  body="$(awk 'BEGIN{p=0} /^---/ {c++; next} c==2{p=1} p' "$md_file" | sed '/./,$!d')"

  new_front=$(print "$front" | yq eval ".thumbnail = \"$base64_avif\"" -)

  {
    printf -- "---\n"
    printf "%s\n" "$new_front"
    printf -- "---\n"
    printf "%s\n" "$body"
  } > "$md_file"

  end_time=$(date +%s.%N)
  duration=$(print "$end_time - $start_time" | bc)

  ####################
  # Print Comparison
  ####################
  print "  🗜️  AVIF Base64:   ${avif_size} bytes"
  print "  Done in ${duration}s"
  print ""
done