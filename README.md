# Man of the West

A blog site utilizing Hugo where content is by default stored in a git submodule. Generator: Hugo 0.147.6+extended

To add a submodule:

```git submodule add https://github.com/yourusername/your-content-repo content/```

Related tutorial: https://www.taniarascia.com/git-submodules-private-content/

Image processing workflow:

As Hugo does not support large-scale image processing (and nor does Git support storing them), take the following steps to do it manually:

1. Add images to `static/images`
2. Run `./scripts/convert_images.sh` to resize and convert images to avif/webp
3. Upload images to R2 bucket using `rclone`:
```rclone copy ./static/optimized_images r2:bucket-name --ignore-existing --progress --exclude ".DS_Store"```