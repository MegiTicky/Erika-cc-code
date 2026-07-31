# Erika ComputerCraft Code

ComputerCraft programs for the Valkyrien Skies 2 and Create builds in this
repository. Everything is kept in one repository so the code can be versioned
and updated without maintaining one GitHub repository per in-game program.

## Layout

- `1 Air exclusive/`, `1 Ground exclusive/`, and `1 Naval exclsuive/`: vehicle
  programs.
- `Missile&NGDW/`: missile, radar, and NGDW programs.
- `Grandop/`: battle and server systems.
- `Utility/`: reusable utilities and measurements.
- `test/`: experiments and test programs.
- `Old/`: older versions retained for reference.
- `install.lua`: an in-game downloader for individual files.

The original filenames and folders are intentionally preserved. This means a
program can be installed by its repository-relative path without maintaining a
separate repository for it.

## Git workflow

From this folder:

```text
git pull
# edit or add ComputerCraft files
git add .
git commit -m "Describe the change"
git push
```

Use a short, specific commit message. For risky vehicle changes, test in a
copy of the world before pushing.

## Install a program in ComputerCraft

The repository is intended to be public so computers can download raw files
without storing GitHub credentials. On a computer with HTTP enabled, download
the installer once:

```text
wget https://raw.githubusercontent.com/MegiTicky/Erika-cc-code/main/install.lua install
```

Then install a program by its path in this repository:

```text
install "Utility/matrix.lua" matrix.lua
install "1 Air exclusive/Z-10Control.lua" startup
```

The destination defaults to the source filename. Existing files are protected
from accidental replacement; pass `--force` as the final argument when an
explicit replacement is intended:

```text
install "Utility/matrix.lua" matrix.lua --force
```

The installer URL-encodes each path component, so spaces, `&`, apostrophes, and
other special characters in existing folder names are supported.
