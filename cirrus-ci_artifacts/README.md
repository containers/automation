# Description

This is a small script which examines a Cirrus-CI build and downloads
available artifacts in parallel, into a subdirectory tree corresponding
with the Cirrus-CI build ID, followed by the task-name, artifact-name
and file-path.  Optionally, a regex may be provided to download only
specific artifacts matching the subdirectory path.

The script may be executed from a currently running Cirrus-CI build
(utilizing `$CIRRUS_BUILD_ID`), but only previously uploaded artifacts
will be downloaded, and the task must have a `depends_on` statement
to synchronize with tasks providing expected artifacts.

# Installation

Install the python3 module requirements using pip3:
(Note: These go into `$HOME/.local/lib/python<version>`)

```
$ pip3 install --user --requirement ./requirements.txt
```

# Usage

Create and change to the directory where artifact tree should be
created.  Call the script, passing in the following arguments:

1. Optional, `--verbose` prints out artifacts as they are
   downloaded or skipped.
2. The Cirrus-CI build id (required) to retrieve (doesn't need to be
   finished running).
3. Optional, a filter regex e.g. `'runner_stats/.*fedora.*'` to
   only download artifacts matching `<task>/<artifact>/<file-path>`
