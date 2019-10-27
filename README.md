# git-logic-init
[![Build Status](https://travis-ci.org/NaanProphet/git-logic-init.svg?branch=master)](https://travis-ci.org/NaanProphet/git-logic-init)

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

## Dependencies

* Homebrew
* Git (>= 2.9)
* Git LFS
* Git Store Meta

## Usage

### Initial

* Create a new folder
  * Open Terminal
  * Create a new folder `mkdir myrepo`
  * `cd` into the new folder `myrepo`
* Pull the latest script from GitHub Releases
  ```
  curl -s -L -O https://github.com/NaanProphet/git-logic-init/releases/latest/download/init.sh \
  && shasum -a 256 -c <<< "417d713906b9add06b74113c01f7e7bab14ccabc0f4f9b7ff27f90319169b3ac *init.sh"
  ```
* Checksum verification should pass saying `init.sh: OK`
* Run script `sh init.sh`
  * This will bootstrap the commit hooks and create the `.githooks` folder (which can be committed into source control)
  * This will also run the command `git config core.hooksPath .githooks` at the end to setup the custom hooks folder
* Commit!

### Cloning

To re-initialize a repo that already has a `.githooks` folder, simply run `sh init.sh` again.

## Default Rules

## Ignore

The following files/folders are automatically added to the repo's `.gitignore` to prevent too much chatter. Loosely based on https://sound.stackexchange.com/a/38454.

| Name | Description |
| --- | --- |
| `.DS_Store` | Excluded because even opening a folder in Finder updates it. It's a tiny file, but updating it all the time unnecessarily increases the size of the Git repo! The tradeoff however is Finder colors will not stored—use a README instead. |
| `Freeze Files` | Files in this folder can change a lot, so assume owner of repo has access to all plugins so that Freeze Files are not needed. Otherwise, manually zip up the Freeze Files folder to upload them.
| `Undo Data.nosync` | Internal project file that keeps track of Undo History. Sometimes these files are 14 MB each, and by default Logic X will keep the last 10. Git *is* for version control so in-flight Undos are not needed.
| `Project File Backups` | Every time a project is saved, a backup is created. No need for intermediate versions, again, use Git to commit/restore actual checkpoints.
| `Autosave` | The folder where Logic records every edit until you use the Save command again. Not needed because it is assumed the person has saved before making a new commit. |
| `*.rxdoc` | iZotope RX documents. Sometimes I use RX to make changes in the Audio Files folder, and for convenience these are excluded from being picked up. |

### LFS

The following filetypes will be tracked by Git LFS after initialization:

* Audio Extensions
  * `*.wav`
  * `*.aif`
  * `*.aiff`
  * `*.mp3`
  * `*.m4a`
  * `*.alac` (Apple Lossless)
  * `*.aifc` (AIFF Compressed)
* Archives
  * `*.zip`
  * `*.gz`
  * `*.tgz`
* Logic Files
  * `ProjectData` (the actual project database file)

## Caveats

On most Git platforms LFS files seem to continue being stored even after commits are rewritten to dereference them.

For example, here's output force pushing a blank repo to an Azure Devops remote in attempt to "start over" again.

```
$ git push origin
Uploading LFS objects: 100% (175/175), 3.9 GB | 0 B/s, done                     
Counting objects: 476, done.
Delta compression using up to 4 threads.
Compressing objects: 100% (475/475), done.
Writing objects: 100% (476/476), 48.65 MiB | 7.14 MiB/s, done.
Total 476 (delta 24), reused 0 (delta 0)
remote: Analyzing objects... (476/476) (6396 ms)
remote: Storing packfile... done (614 ms)
remote: Storing index... done (52 ms)
$
```

0 B/s to upload 3.9 GB!? Oh reeeealy.... This can work both for/against your workflow depending on what you're doing.

It seems currently, the only way to actually remove LFS files is by deleting the project and creating a new one. This is [documented in GitHub](https://help.github.com/en/github/managing-large-files/removing-files-from-git-large-file-storage#git-lfs-objects-in-your-repository) and GitLabs seems to work the same way. There's actually an [open issue from 2017 on GitLabs](https://gitlab.com/gitlab-org/gitlab/issues/17711) to prune unreferenced LFS files more proactively.
