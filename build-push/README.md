# Build-push script

This is a wrapper around buildah build, coupled with pre and post
build commands and automatic registry server push.  Its goal is to
provide an abstraction layer for additional build automation. Though
it may be useful on its own, this is not its primary purpose.


## Requirements

* Executables for `jq`, and `buildah` (1.23 or later) are available.
* Automation common-library is installed & env. var set.
  * Installed system-wide as per
    [the top-level documentation](https://github.com/containers/automation#installation)
  * -or-
  * Run directly from repository clone by first doing
    `export AUTOMATION_LIB_PATH=/path/to/clone/common/lib`
* Optionally, the kernel may be configured to use emulation (such as QEMU)
  for non-native binary execution (where available and supported).  See
  [the section below for more
  infomration](README.md#qemu-user-static-emulation).


## QEMU-user-static Emulation

On platforms/distro's that support it (Like F34+) this is a handy
way to enable non-native binary execution.  It can therefore be
used to build container images for other non-native architectures.
Though setup may vary by distro/version, in F34 all that's needed
is to install the `qemu-user-static` package.  It will take care
of automatically registering the emulation executables with the
kernel.

Otherwise, you may find these [handy/dandy scripts and
container images useful](https://github.com/multiarch/qemu-user-static#multiarchqemu-user-static-images) for environments without native support (like
CentOS and RHEL).  However, be aware I cannot atest to the safety
or quality of those binaries/images, so use them at your own risk.
Something like this (as **root**):

```bash
~# install qemu user static binaries somehow
~# qemu_setup_fqin="docker.io/multiarch/qemu-user-static:latest"
~# vol_awk='{print "-v "$1":"$1""}'
~# bin_vols=$(find /usr/bin -name 'qemu-*-static' | awk -e "$vol_awk" | tr '\n' ' ')
~# podman run --rm --privileged $bin_vols $qemu_setup_fqin --reset -p yes
```

Note: You may need to alter `$vol_awk` or the `podman` command line
depending on what your platform supports.


## Use in build automation

This script may be useful as a uniform interface for building and pushing
for multiple architectures, all in one go.  A simple example would be:

```bash
$ export SOME_USERNAME=foo  # normally hidden/secured in the CI system
$ export SOME_PASSWORD=bar  # along with this password value.

$ build-push.sh --arches=arm64,ppc64le,s390x quay.io/some/thing ./path/to/contextdir
```

In this case, the image `quay.io/some/thing:latest` would be built for the
listed architectures, then pushed to the remote registry server.

### Use in automation with additional preparation

When building for multiple architectures using emulation, it's vastly
more efficient to execute as few non-native RUN instructions as possible.
This is supported by the `--prepcmd` option, which specifies a shell
command-string to execute prior to building the image. The command-string
will have access to a set of exported env. vars. for use and/or
substitution (see the `--help` output for details).

For example, this command string could be used to seed the build cache
by pulling down previously built image of the same name:

```bash
$ build-push.sh ... quay.io/test/ing --prepcmd='$RUNTIME pull $FQIN:latest'
```

In this example, the command `buildah pull quay.io/test/ing:latest` will
be executed prior to the build.

### Use in automation with modified images

Sometimes additional steps need to be performed after the build, to modify,
inspect or additionally tag the built image before it's pushed.  This could
include (for example) running tests on the image, or modifying its metadata
in some way.  All these and more are supported by the `--modcmd` option.

Simply feed it a command string to be run after a successful build.  The
command-string script will have access to a set of exported env. vars.
for use and/or substitution (see the `--help` output for details).

After executing a `--modcmd`, `build-push.sh` will take care to identify
all images related to the original FQIN (minus the tag).  Should
additional tags be present, they will also be pushed (absent the
`--nopush` flag).  If any/all images are missing, they will be silently
ignored.

For example you could use this to only push version-tagged images, and
never `latest`:

```
$ build-push.sh ... --modcmd='$RUNTIME tag $FQIN:latest $FQIN:9.8.7 && \
                              $RUNTIME manifest rm $FQIN:latest'
```

Note: If your `--modcmd` command or script removes **ALL** tags, and
`--nopush` was **not** specified, an error message will be printed
followed by a non-zero exit.  This is intended to help automation
catch an assumed missed-expectation.
