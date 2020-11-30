# Description

This is a small script which examines a Cirrus-CI build and downloads
available artifacts in parallel, to the current working directory.
Optionally, a regex may be provided to download only specific artifacts
(by name/path).

The script may be executed from a currently running Cirrus-CI build
(utilizing `$CIRRUS_BUILD_ID`), but only previously uploaded artifacts
will be downloaded.

It is assumed that GCP is used as the back-end for the Cirrus-CI build,
and the name of the (repository-specific) google-storage bucket is
known.

# Installation

Install the python3 module requirements using pip3:
(Note: These go into `$HOME/.local/lib/python<version>`)

```
$ pip3 install --user --requirement ./requirements.txt
```

# Usage

Create and change to the directory where artifacts should be downloaded.
Call the script, passing in the following arguments:

1. The Repository owner/name *e.g. `"containers/podman"`*
2. The GCS bucket name *e.g. `"cirrus-ci-6707778565701632-fcae48"`*
3. Optionally, a filter regex *e.g. `"runner_stats/.*fedora"`*
