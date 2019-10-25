# git-logic-init

An init script intended for use versioning Apple Logic projects with Git.

## Why

Apple Logic will recalculate overviews (thumbnails) for audio files if their timestamps change—even if the checksums match. Since Git does not natively preserve timestamps, any clone will cause a rescan.

![Logic project re-creating overview for audio files after Git clone](https://github.com/NaanProphet/git-logic-init/raw/master/docs/creating-overview.png)

This may not seem like such a bad thing (it's rather fast) except that...**rescanning changes the checksums!!**

![Checksums changed after opening Logic project - closed without saving](https://github.com/NaanProphet/git-logic-init/raw/master/docs/checksums-changed.png)

This creates a nightmare for version control and increases the size of the Git repo unnecessarily!

## Solution

1. Use [Git LFS](https://github.com/git-lfs/git-lfs) to store large files and keep the repo size small (based on SHA 256 checksums)
2. Use [Git Store Meta](https://github.com/danny0838/git-store-meta) to preserve timestamps

Since Git commit hooks are scripts, they must—by design—be re-configured each time a repository is created/cloned.

## Usage

### Initial

* Create a new folder
  * Open Terminal
  * Create a new folder `mkdir myrepo`
  * `cd` into the new folder `myrepo`
* Pull the latest script from GitHub Releases
  ```
  curl -s -L -O https://github.com/NaanProphet/git-logic-init/releases/latest/download/init.sh \
  && shasum -a 256 -c <<< "cc3fdbc123f4f586f33ce5494ee43da7e741018ec9fc77d354d4ac717dcfb202 *init.sh"
  ```
* Checksum verification should pass saying `init.sh: OK`
* Run script `sh init.sh`
  * This will bootstrap the commit hooks and create the `.githooks` folder (which can be committed into source control)
  * This will also run the command `git config core.hooksPath .githooks` at the end to setup the custom hooks folder
* Commit!

### Cloning

To re-initialize a repo that already has a `.githooks` folder, simply run `sh init.sh` again.

## Dependencies

* Homebrew
* Git (>= 2.9)
* Git LFS
* Git Store Meta
