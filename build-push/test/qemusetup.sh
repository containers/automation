

# This script is intend for use by tests, DO NOT EXECUTE.

set -eo pipefail

# shellcheck disable=SC2154
if  [[ "$CIRRUS_CI" == "true" ]]; then
    # Cirrus-CI is setup (see .cirrus.yml) to run tests on CentOS
    # for simplicity, but it has no native qemu-user-static.  For
    # the benefit of CI testing, cheat and use whatever random
    # emulators are included in the container image.

    # N/B: THIS IS NOT SAFE FOR PRODUCTION USE!!!!!
    podman run --rm --privileged \
        mirror.gcr.io/multiarch/qemu-user-static:latest \
        --reset -p yes
elif [[ -x "/usr/bin/qemu-aarch64-static" ]]; then
    # TODO: Better way to determine if kernel already setup?
    echo "Warning: Assuming qemu-user-static is already setup"
else
    echo "Error: System does not appear to have qemu-user-static setup"
    exit 1
fi
