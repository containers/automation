

# This library is intended for use by the scripts in this directory.
# It should not be used directly or by any other scripts.

# Execute some command or function but make github WebUI organize the
# output inside a handy-dandy expandable section with a title. Ref:
# https://docs.github.com/en/actions/reference/workflow-commands-for-github-actions
group_run() {
    local ret
    local command="$1"
    shift
    local title="$@"
    echo "::group::$title"
    # grouping gets screwed up by stderr output.  Thanks github.
    if $command &> /dev/stdout; then
        echo "::endgroup::"
    else
        ret=$?
        echo "::endgroup::"
        echo "::error::(exit $ret)"
        return $ret
    fi
}

install_automation_tooling() {
    local install_version="2.1.4"
    local installer_url="https://raw.githubusercontent.com/containers/automation/master/bin/install_automation.sh"
    curl --silent --show-error --location \
         --url "$installer_url" | \
             env INSTALL_PREFIX=$HOME/.local /bin/bash -s - "$install_version"
}

setup_automation_tooling() {
    # defines AUTOMATION_LIB_PATH
    source $HOME/.local/automation/environment
    # load all common libraries
    source $AUTOMATION_LIB_PATH/common_lib.sh
    # Must be defined after common_lib.sh is loaded
    SECRET_ENV_RE='(.+PASSWORD.*)|(.+USERNAME.*)'
}

repo_name() {
    req_env_vars GITHUB_REPOSITORY
    cut -d "/" -f 2 <<<"$GITHUB_REPOSITORY"
}

get_context_dirpath() {
    req_env_vars GITHUB_WORKSPACE INPUT_SOURCE_NAME
    printf "%s/%s/%s/\n" \
        "$GITHUB_WORKSPACE/contrib" \
        $(repo_name)image \
        "$INPUT_SOURCE_NAME"
}

verify_runtime_environment() {
    req_env_vars CI GITHUB_ACTIONS GITHUB_REPOSITORY GITHUB_SHA GITHUB_ACTION_PATH
    req_env_vars INPUT_REGISTRY_NAMESPACE INPUT_IMAGE_NAME INPUT_SOURCE_NAME
    req_env_vars INPUT_REGISTRY_USERNAME INPUT_REGISTRY_PASSWORD INPUT_BUILD_ARCHES

    # Only "Composite" github actions define GITHUB_ACTION_PATH, this is required
    # because we will be using container tooling, which cannot run properly inside
    # a container (the normal environment for github actions).
    if  [[ "$CI" != "true" ]] || \
        [[ "$GITHUB_ACTIONS" != "true" ]] || \
        [[ ! -d "$GITHUB_ACTION_PATH" ]]
    then
        die "This script must be run as a github composite action"
    fi
    msg "Runtime environment appears as expected"

    # Dump required action input variables into a file so they don't need to be
    # duplicated over and over in action.yml (YAML anchors/aliases not supported).
    cat << EOF > $HOME/.local/automation/runtime
# Automatically generated file, do not edit, any/all changes will be overwritten.
INPUT_REGISTRY_NAMESPACE="$INPUT_REGISTRY_NAMESPACE"
INPUT_IMAGE_NAME="$INPUT_IMAGE_NAME"
INPUT_SOURCE_NAME="$INPUT_SOURCE_NAME"
INPUT_REGISTRY_USERNAME="$INPUT_REGISTRY_USERNAME"
INPUT_REGISTRY_PASSWORD="$INPUT_REGISTRY_PASSWORD"
INPUT_BUILD_ARCHES="$INPUT_BUILD_ARCHES"
BUILDCTX=$(get_context_dirpath)
BUILDTMP="$(mktemp -d -p '' tmp_$(basename $0)_XXXXXXXX)"
FQIN="$INPUT_REGISTRY_NAMESPACE/$INPUT_IMAGE_NAME:latest"
EOF
}

load_runtime_environment() {
    source $HOME/.local/automation/runtime
    req_env_vars FQIN
    # For filesystem names, need to replace problematic characters
    _FQIN=$(tr -d '[:space:]' <<<"$FQIN" | tr -c '[:alnum:]' '_')
}

# Register QEMU to handle non-native execution
# Ref: https://github.com/multiarch/qemu-user-static#multiarchqemu-user-static-images
setup_qemu_binfmt() {
    local bin_vols
    # TODO: Copy this image over to quay to avoid pull-throttling surprises
    local qemu_setup_fqin="docker.io/multiarch/qemu-user-static"
    sudo apt-get update -qq -y
    sudo apt-get install -qq -y qemu-user-static
    # Register binaries the host actually has available
    bin_vols=$(find /usr/bin -name 'qemu-*-static' | awk '{print "-v "$1":"$1}' | tr '\n' ' ')
    # This has to run as root and --privileged since it modifies the kernel
    # sysctl's and loads the interpreter binaries persistently into memory.
    sudo podman run --rm --privileged $bin_vols $qemu_setup_fqin --reset -p yes
}

tooling_versions() {
    skopeo --version
    buildah version
    podman version
}

build_image_arch() {
    req_env_vars arch BUILDCTX BUILDTMP GITHUB_REPOSITORY GITHUB_SHA
    local arch_fqin
    local tmp_root
    local tmp_run
    # Docs indicate source image must be tagged for addition into a manifest
    arch_fqin="${FQIN%%:latest}:$arch"
    # Assuming builds are running in parallel for multiple architectures,
    # it's possible for storage clashes to occur when pulling the base image.
    # Guarantee this cannot happen by performing each build in a dedicated
    # storage root.
    tmp_root=$(mktemp -d -p "$BUILDTMP" "${arch}_root_XXXXXXXX")
    tmp_run=$(mktemp -d -p "$BUILDTMP" "${arch}_run_XXXXXXXX")

    echo "Building $arch_fqin using $BUILDCTX"
    podman \
        --root=$tmp_root \
        --runroot=$tmp_run \
        build \
        --no-cache \
        --arch=$arch \
        --tag=$arch_fqin \
        --label "org.opencontainers.image.source=https://github.com/$GITHUB_REPOSITORY.git" \
        --label "org.opencontainers.image.revision=$GITHUB_SHA" \
        --label "org.opencontainers.image.created=$(date -u --iso-8601=seconds)" \
        "$BUILDCTX"

    echo "Migrating built image from sequestered to main storage"
    podman \
        --root=$tmp_root \
        --runroot=$tmp_run \
        save \
        --quiet \
        --format=docker-archive \
        --output="$BUILDTMP/images/${arch}_img.tar" \
        $arch_fqin

    # Later, image will be executed to obtain version information
    podman load --quiet --input="$BUILDTMP/images/${arch}_img.tar"

    echo "Cleaning up sequestered build storage"
    sudo rm -rf "$tmp_root" "$tmp_run"
}

combine_images() {
    local arch
    local arch_fqin
    req_env_vars FQIN
    for arch in $INPUT_BUILD_ARCHES; do
        arch_fqin="${FQIN%%:latest}:$arch"
        msg "Adding $arch_fqin..."
        # Careful, the option order is: <list> <image>
        # N/B: Images _MUST_ be added to manifest from a docker-archive
        # file.  Using containers-storage image will strip out non-native
        # architecture layers.
        podman manifest add --all \
            "$FQIN" \
            "docker-archive:$BUILDTMP/images/${arch}_img.tar"
    done
    echo "Image manifest contents:"
    podman manifest inspect $FQIN | jq --color-output .
}

get_version() {
    req_env_vars FQIN
    local stdout
    local version_cmd
    local version
    case $(repo_name) in
        skopeo) version_cmd="--version" ;;  # image sets entrypoint
        buildah) version_cmd="podman --storage-driver=vfs version" ;;
        podman) version_cmd="buildah --storage-driver=vfs version" ;;
        *) die "Unknown/unhandled repository '$(repo_name)'"
    esac
    msg "Executing '$version_cmd'"
    stdout=$(podman run -i --rm $FQIN bash -c "$version_cmd")
    msg "Output:
$stdout"
    version=$(grep -Eim1 '^version:[[:space:]]+' <<<"$stdout" | awk '{print $2}')
    test -n "$version"
    msg "Found version '$version'"
    echo "$version"
}

get_existing_tags() {
    req_env_vars FQIN
    local existing_tags
    existing_tags=$(skopeo list-tags \
        docker://${FQIN%%:latest} | \
        jq -r '.Tags[]')
    msg "Existing tags:
$existing_tags"
    test -n "$existing_tags"
    echo "$existing_tags"
}

reg_login() {
    req_env_vars INPUT_REGISTRY_NAMESPACE INPUT_REGISTRY_USERNAME INPUT_REGISTRY_PASSWORD
    # At the time of implementation, for an unknown reason, skopeo isn't using
    # the correct auth file, but buildah/podman are fine.  Work around this by
    # forcing a specific file location.
    export REGISTRY_AUTH_FILE=$HOME/auth.json
    echo "$INPUT_REGISTRY_PASSWORD" | \
        skopeo login --username "$INPUT_REGISTRY_USERNAME" --password-stdin \
        "$INPUT_REGISTRY_NAMESPACE"
}

push_if_new() {
    local existing_tags
    req_env_vars VERSION FQIN FQIN2

    echo "::warning::Pushing to $FQIN"
    podman push $FQIN

    existing_tags=$(get_existing_tags)
    if [[ -z "$existing_tags" ]]; then
        die "Retrieved empty tag list, is this a new registry/image?"
    fi

    if ! fgrep -qx "$VERSION" <<<"$existing_tags";
    then  # A new version was built
        echo "::warning::Pushing to $FQIN2"
        podman tag $FQIN $FQIN2
        podman push $FQIN2
    else
        echo "Found existing tag $VERSION, not pushing."
    fi
}
