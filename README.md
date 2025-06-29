# Man of the West

A blog site utilizing Hugo where content is by default stored in a git submodule. Generator: Hugo 0.147.6+extended

To add a submodule:

```git submodule add https://github.com/yourusername/your-content-repo content/```

Related tutorial: https://www.taniarascia.com/git-submodules-private-content/

Image processing workflow:

As Hugo does not support extreme-scale image processing (and nor does Git support storing an extreme number of them), take the following steps to do it manually:

1. Add images to `assets/images`
2. Run `./scripts/convert_images.sh` to resize and convert images to avif/webp
3. Run `./scripts/generate_gradients.sh` to generate gradients
4. Upload images to R2 bucket using `rclone`:
```rclone copy ./assets/optimized_images r2:bucket-name --ignore-existing --progress --exclude ".DS_Store"```

Deploy to Cloudflare Pages:
```rm -rf public && hugo --minify && wrangler pages deploy```