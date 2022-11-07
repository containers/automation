#!/usr/bin/perl

use v5.14;
use Test::More;
use Test::Differences;
use FindBin;

# Read tests
my @tests;
my $context = '';
while (my $line = <DATA>) {
    if ($line =~ /^<{10,}\s+(.*)$/) {
        $context = 'yml';
        push @tests, { name => $1, yml => "---\n", expect => '' };
    }
    elsif ($line =~ /^>{10,}$/) {
        $context = 'expect';
    }
    elsif ($line =~ /\S/) {
        $tests[-1]{$context} .= $line;
    }
}

plan tests => 1 + @tests;

require_ok "$FindBin::Bin/../cirrus-task-map";

for my $t (@tests) {
    my $tasklist = TaskList->new($t->{yml});
    my $gv = $tasklist->graphviz( 'a' .. 'z' );

    # Strip off the common stuff from start/end
    my @gv = grep { /^\s+\"/ } split "\n", $gv;

    my @expect = split "\n", $t->{expect};
    eq_or_diff \@gv, \@expect, $t->{name};
}






__END__



<<<<<<<<<<<<<<<<<<  simple setup: one task, no deps
just_one_task:
  name: "One Task"
>>>>>>>>>>>>>>>>>>

  "just_one" [shape=ellipse style=bold color=z fontcolor=z]




<<<<<<<<<<<<<<<<<<  two tasks, b depends on a
a_task:
    alias: "a_alias"

b_task:
    alias: "b_alias"
    depends_on:
      - "a"
>>>>>>>>>>>>>>>>>>
  "a" [shape=ellipse style=bold color=a fontcolor=a]
  "a" -> "b" [color=a]
  "b" [shape=ellipse style=bold color=z fontcolor=z]




<<<<<<<<<<<<<<<<<<  four tasks, two in the middle, with aliases
real_name_of_initial_task:
    alias: "initial"

middle_1_task:
    depends_on:
        - "initial"

middle_2_task:
    depends_on:
        - "initial"

end_task:
    depends_on:
        - "initial"
        - "middle_1"
        - "middle_2"
>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  "real_name_of_initial" [shape=ellipse style=bold color=a fontcolor=a]
  "real_name_of_initial" -> "middle_1" [color=a]
  "middle_1" [shape=ellipse style=bold color=b fontcolor=b]
  "middle_1" -> "end" [color=b]
  "end" [shape=ellipse style=bold color=z fontcolor=z]
  "real_name_of_initial" -> "middle_2" [color=a]
  "middle_2" [shape=ellipse style=bold color=c fontcolor=c]
  "middle_2" -> "end" [color=c]
  "real_name_of_initial" -> "end" [color=a]

<<<<<<<<<<<<<<<<<<  env interpolation 1
env:
    NAME: "top-level name"

a_task:
    name: "$NAME"
    matrix:
        - env:
            NAME: "name1"
        - env:
            NAME: "name2"
    env:
        NAME: "this should never be interpolated"
>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  "a" [shape=record style=bold color=z fontcolor=z label="a\l|- name1\l- name2\l"]


<<<<<<<<<<<<<<<<<<  real-world test: cevich "performant" branch
# Main collection of env. vars to set for all tasks and scripts.
env:
    ####
    #### Global variables used for all tasks
    ####
    # Name of the ultimate destination branch for this CI run, PR or post-merge.
    DEST_BRANCH: "master"
    # Overrides default location (/tmp/cirrus) for repo clone
    GOPATH: &gopath "/var/tmp/go"
    GOBIN: "${GOPATH}/bin"
    GOCACHE: "${GOPATH}/cache"
    GOSRC: &gosrc "/var/tmp/go/src/github.com/containers/podman"
    CIRRUS_WORKING_DIR: *gosrc
    # The default is 'sh' if unspecified
    CIRRUS_SHELL: "/bin/bash"
    # Save a little typing (path relative to $CIRRUS_WORKING_DIR)
    SCRIPT_BASE: "./contrib/cirrus"

    ####
    #### Cache-image names to test with (double-quotes around names are critical)
    ####
    FEDORA_NAME: "fedora-32"
    PRIOR_FEDORA_NAME: "fedora-31"
    UBUNTU_NAME: "ubuntu-20"
    PRIOR_UBUNTU_NAME: "ubuntu-19"

    # Google-cloud VM Images
    IMAGE_SUFFIX: "c5363056714711040"
    FEDORA_CACHE_IMAGE_NAME: "fedora-${IMAGE_SUFFIX}"
    PRIOR_FEDORA_CACHE_IMAGE_NAME: "prior-fedora-${IMAGE_SUFFIX}"
    UBUNTU_CACHE_IMAGE_NAME: "ubuntu-${IMAGE_SUFFIX}"
    PRIOR_UBUNTU_CACHE_IMAGE_NAME: "prior-ubuntu-${IMAGE_SUFFIX}"

    # Container FQIN's
    FEDORA_CONTAINER_FQIN: "quay.io/libpod/fedora_podman:${IMAGE_SUFFIX}"
    PRIOR-FEDORA_CONTAINER_FQIN: "quay.io/libpod/prior-fedora_podman:${IMAGE_SUFFIX}"
    UBUNTU_CONTAINER_FQIN: "quay.io/libpod/ubuntu_podman:${IMAGE_SUFFIX}"
    PRIOR-UBUNTU_CONTAINER_FQIN: "quay.io/libpod/prior-ubuntu_podman:${IMAGE_SUFFIX}"

    ####
    #### Control variables that determine what to run and how to run it.
    #### (Default's to running inside Fedora community-cluster container)
    TEST_FLAVOR:             # int, sys, ext_svc, smoke, automation, etc.
    TEST_ENVIRON: host       # host or container
    PODBIN_NAME: podman      # podman or remote
    PRIV_NAME: root          # root or rootless
    DISTRO_NV: $FEDORA_NAME  # any {PRIOR_,}{FEDORA,UBUNTU}_NAME value


# Default timeout for each task
timeout_in: 60m


gcp_credentials: ENCRYPTED[a28959877b2c9c36f151781b0a05407218cda646c7d047fc556e42f55e097e897ab63ee78369dae141dcf0b46a9d0cdd]


# Attempt to prevent flakes by confirming all required external/3rd-party
# services are available and functional.
ext_svc_check_task:
    alias: 'ext_svc_check'  # int. ref. name - required for depends_on reference
    name: "Ext. services"  # Displayed Title - has no other significance
    env:
        TEST_FLAVOR: ext_svc
    script: &setup_and_run
        - 'cd $GOSRC/$SCRIPT_BASE || exit 1'
        - './setup_environment.sh'
        - './runner.sh'
    # Default/small container image to execute tasks with
    container: &smallcontainer
        image: ${CTR_FQIN}
        # Resources are limited across ALL currently executing tasks
        # ref: https://cirrus-ci.org/guide/linux/#linux-containers
        cpu: 2
        memory: 2
    env:
        CTR_FQIN: ${FEDORA_CONTAINER_FQIN}


automation_task:
    alias: 'automation'
    name: "Check Automation"
    container: *smallcontainer
    env:
        TEST_FLAVOR: automation
        CTR_FQIN: ${FEDORA_CONTAINER_FQIN}
    script: *setup_and_run


smoke_task:
    # This task use to be called 'gating', however that name is being
    # used downstream for release testing.  Renamed this to avoid confusion.
    alias: 'smoke'
    name: "Smoke Test"
    container: &bigcontainer
        image: ${CTR_FQIN}
        # Leave some resources for smallcontainer
        cpu: 6
        memory: 22
    env:
        TEST_FLAVOR: 'smoke'
        CTR_FQIN: ${FEDORA_CONTAINER_FQIN}
    clone_script: &full_clone |
        cd /
        rm -rf $CIRRUS_WORKING_DIR
        mkdir -p $CIRRUS_WORKING_DIR
        git clone --recursive --branch=$DEST_BRANCH https://x-access-token:${CIRRUS_REPO_CLONE_TOKEN}@github.com/${CIRRUS_REPO_FULL_NAME}.git $CIRRUS_WORKING_DIR
        cd $CIRRUS_WORKING_DIR
        git remote update origin
        if [[ -n "$CIRRUS_PR" ]]; then # running for a PR
            git fetch origin pull/$CIRRUS_PR/head:pull/$CIRRUS_PR
            git checkout pull/$CIRRUS_PR
        else
            git reset --hard $CIRRUS_CHANGE_IN_REPO
        fi
        cd $CIRRUS_WORKING_DIR
        make install.tools
    script: *setup_and_run


build_task:
    alias: 'build'
    name: 'Build for $DISTRO_NV'
    depends_on:
        - ext_svc_check
        - smoke
        - automation
    container: *smallcontainer
    matrix: &platform_axis
        # Ref: https://cirrus-ci.org/guide/writing-tasks/#matrix-modification
        - env:  &stdenvars
              DISTRO_NV: ${FEDORA_NAME}
              # Not used here, is used in other tasks
              VM_IMAGE_NAME: ${FEDORA_CACHE_IMAGE_NAME}
              CTR_FQIN: ${FEDORA_CONTAINER_FQIN}
              # ID for re-use of build output
              _BUILD_CACHE_HANDLE: ${FEDORA_NAME}-build-${CIRRUS_BUILD_ID}
        - env:
              DISTRO_NV: ${PRIOR_FEDORA_NAME}
              VM_IMAGE_NAME: ${PRIOR_FEDORA_CACHE_IMAGE_NAME}
              CTR_FQIN: ${PRIOR-FEDORA_CONTAINER_FQIN}
              _BUILD_CACHE_HANDLE: ${PRIOR_FEDORA_NAME}-build-${CIRRUS_BUILD_ID}
        - env:
              DISTRO_NV: ${UBUNTU_NAME}
              VM_IMAGE_NAME: ${UBUNTU_CACHE_IMAGE_NAME}
              CTR_FQIN: ${UBUNTU_CONTAINER_FQIN}
              _BUILD_CACHE_HANDLE: ${UBUNTU_NAME}-build-${CIRRUS_BUILD_ID}
        - env:
              DISTRO_NV: ${PRIOR_UBUNTU_NAME}
              VM_IMAGE_NAME: ${PRIOR_UBUNTU_CACHE_IMAGE_NAME}
              CTR_FQIN: ${PRIOR-UBUNTU_CONTAINER_FQIN}
              _BUILD_CACHE_HANDLE: ${PRIOR_UBUNTU_NAME}-build-${CIRRUS_BUILD_ID}
    env:
        TEST_FLAVOR: build
    # Seed $GOCACHE from any previous instances of this task
    gopath_cache:  &gopath_cache  # 'gopath_cache' is the displayed name
        # Ref: https://cirrus-ci.org/guide/writing-tasks/#cache-instruction
        folder: *gopath  # Required hard-coded path, no variables.
        fingerprint_script: echo "$_BUILD_CACHE_HANDLE"
        # Cheat: Clone here when cache is empty, guaranteeing consistency.
        populate_script: *full_clone
    # A normal clone would invalidate useful cache
    clone_script: &noop mkdir -p $CIRRUS_WORKING_DIR
    script: *setup_and_run
    always:
        artifacts:  &all_gosrc
            path: ./*  # Grab everything in top-level $GOSRC
            type: application/octet-stream


validate_task:
    name: "Validate $DISTRO_NV Build"
    alias: validate
    depends_on:
        - build
    container: *bigcontainer
    env:
        <<: *stdenvars
        CTR_FQIN: ${FEDORA_CONTAINER_FQIN}
        TEST_FLAVOR: validate
    gopath_cache: &ro_gopath_cache
        <<: *gopath_cache
        reupload_on_changes: false
    clone_script: *noop
    script: *setup_and_run
    always:
        artifacts: *all_gosrc


bindings_task:
    name: "Test Bindings"
    alias: bindings
    depends_on:
        - build
    gce_instance: &standardvm
        image_project: libpod-218412
        zone: "us-central1-a"
        cpu: 2
        memory: "4Gb"
        # Required to be 200gig, do not modify - has i/o performance impact
        # according to gcloud CLI tool warning messages.
        disk: 200
        image_name: "${VM_IMAGE_NAME}"  # from stdenvars
    env:
        <<: *stdenvars
        TEST_FLAVOR: bindings
    gopath_cache: *ro_gopath_cache
    clone_script: *noop  # Comes from cache
    script: *setup_and_run
    always:
        artifacts: *all_gosrc


swagger_task:
    name: "Test Swagger"
    alias: swagger
    depends_on:
        - build
    container: *smallcontainer
    env:
        <<: *stdenvars
        TEST_FLAVOR: swagger
        CTR_FQIN: ${FEDORA_CONTAINER_FQIN}
    gopath_cache: *ro_gopath_cache
    clone_script: *noop  # Comes from cache
    script: *setup_and_run
    always:
        artifacts: *all_gosrc


endpoint_task:
    name: "Test Endpoint"
    alias: endpoint
    depends_on:
        - build
    container: *smallcontainer
    env:
        <<: *stdenvars
        TEST_FLAVOR: endpoint
        CTR_FQIN: ${FEDORA_CONTAINER_FQIN}
    gopath_cache: *ro_gopath_cache
    clone_script: *noop  # Comes from cache
    script: *setup_and_run
    always:
        artifacts: *all_gosrc


vendor_task:
    name: "Test Vendoring"
    alias: vendor
    depends_on:
        - build
    container: *smallcontainer
    env:
        <<: *stdenvars
        TEST_FLAVOR: vendor
        CTR_FQIN: ${FEDORA_CONTAINER_FQIN}
    gopath_cache: *ro_gopath_cache
    clone_script: *full_clone
    script: *setup_and_run
    always:
        artifacts: *all_gosrc


# Confirm alternate/cross builds succeed
alt_build_task:
    name: "$ALT_NAME"
    alias: alt_build
    depends_on:
        - build
    env:
        <<: *stdenvars
        TEST_FLAVOR: "altbuild"
    matrix:
      - env:
            ALT_NAME: 'Build Each Commit'
        gce_instance: *standardvm
      - env:
            ALT_NAME: 'Windows Cross'
        gce_instance: *standardvm
      - env:
            ALT_NAME: 'Build Without CGO'
        gce_instance: *standardvm
      - env:
            ALT_NAME: 'Build varlink API'
        gce_instance: *standardvm
      - env:
            ALT_NAME: 'Static build'
        timeout_in: 120m
        gce_instance:
            <<: *standardvm
            cpu: 4
            memory: "8Gb"
        nix_cache:
            folder: '/var/cache/nix'
            populate_script: <-
                mkdir -p /var/cache/nix &&
                podman run -i -v /var/cache/nix:/mnt/nix:Z \
                    nixos/nix cp -rfT /nix /mnt/nix
            fingerprint_script: cat nix/nixpkgs.json
      - env:
            ALT_NAME: 'Test build RPM'
        gce_instance: *standardvm
    script: *setup_and_run
    always:
        artifacts: *all_gosrc


# N/B: This is running on a Mac OS-X VM
osx_cross_task:
    name: "OSX Cross"
    alias: osx_cross
    depends_on:
        - build
    env:
        <<: *stdenvars
        # Some future release-processing will benefit from standardized details
        TEST_FLAVOR: "altbuild"  # Platform variation prevents alt_build_task inclusion
        ALT_NAME: 'OSX Cross'
    osx_instance:
        image: 'catalina-base'
    script:
        - brew install go
        - brew install go-md2mn
        - make podman-remote-darwin
        - make install-podman-remote-darwin-docs
    always:
        artifacts: *all_gosrc


task:
    name: Docker-py Compat.
    alias: docker-py_test
    depends_on:
        - build
    container: *smallcontainer
    env:
        <<: *stdenvars
        TEST_FLAVOR: docker-py
    gopath_cache: *ro_gopath_cache
    clone_script: *full_clone
    script: *setup_and_run
    always:
        artifacts: *all_gosrc


unit_test_task:
    name: "Unit tests on $DISTRO_NV"
    alias: unit_test
    depends_on:
        - build
    matrix: *platform_axis
    gce_instance: *standardvm
    env:
        TEST_FLAVOR: unit
    clone_script: *noop  # Comes from cache
    gopath_cache: *ro_gopath_cache
    script: *setup_and_run
    always:
        artifacts: *all_gosrc

# # Status aggregator for pass/fail from dependents
success_task:
    name: "Total Success"
    alias: success
    # N/B: ALL tasks must be listed here, minus their '_task' suffix.
    depends_on:
        - ext_svc_check
        - automation
        - smoke
        - build
        - validate
        - bindings
        - endpoint
        - swagger
        - vendor
        - alt_build
        - osx_cross
        - docker-py_test
        - unit_test
        # - integration_test
        # - userns_integration_test
        # - container_integration_test
        # - system_test
        # - userns_system_test
        # - meta
    container: *smallcontainer
    env:
        CTR_FQIN: ${FEDORA_CONTAINER_FQIN}
    clone_script: *noop
    script: /bin/true

>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>
  "automation" [shape=ellipse style=bold color=a fontcolor=a]
  "automation" -> "success" [color=a]
  "success" [shape=ellipse style=bold color="#000000" fillcolor="#00f000" style=filled fontcolor="#000000"]
  "automation" -> "build" [color=a]
  "build" [shape=record style=bold color="#0000f0" fillcolor="#f0f0f0" style=filled fontcolor="#0000f0" label="build\l|- Build for fedora-32\l- Build for fedora-31\l- Build for ubuntu-20\l- Build for ubuntu-19\l"]
  "build" -> "bindings" [color="#0000f0"]
  "bindings" [shape=ellipse style=bold color=b fontcolor=b]
  "bindings" -> "success" [color=b]
  "build" -> "docker-py_test" [color="#0000f0"]
  "docker-py_test" [shape=ellipse style=bold color=c fontcolor=c]
  "docker-py_test" -> "success" [color=c]
  "build" -> "endpoint" [color="#0000f0"]
  "endpoint" [shape=ellipse style=bold color=d fontcolor=d]
  "endpoint" -> "success" [color=d]
  "build" -> "osx_cross" [color="#0000f0"]
  "osx_cross" [shape=ellipse style=bold color=e fontcolor=e]
  "osx_cross" -> "success" [color=e]
  "build" -> "swagger" [color="#0000f0"]
  "swagger" [shape=ellipse style=bold color=f fontcolor=f]
  "swagger" -> "success" [color=f]
  "build" -> "validate" [color="#0000f0"]
  "validate" [shape=record style=bold color="#00c000" fillcolor="#f0f0f0" style=filled fontcolor="#00c000" label="validate\l|= Validate fedora-32 Build\l"]
  "validate" -> "success" [color="#00c000"]
  "build" -> "vendor" [color="#0000f0"]
  "vendor" [shape=ellipse style=bold color=g fontcolor=g]
  "vendor" -> "success" [color=g]
  "build" -> "unit_test" [color="#0000f0"]
  "unit_test" [shape=record style=bold color="#000000" fillcolor="#f09090" style=filled fontcolor="#000000" label="unit test\l|- Unit tests on fedora-32\l- Unit tests on fedora-31\l- Unit tests on ubuntu-20\l- Unit tests on ubuntu-19\l"]
  "unit_test" -> "success" [color="#f09090"]
  "build" -> "alt_build" [color="#0000f0"]
  "alt_build" [shape=record style=bold color="#0000f0" fillcolor="#f0f0f0" style=filled fontcolor="#0000f0" label="alt build\l|- Build Each Commit\l- Windows Cross\l- Build Without CGO\l- Build varlink API\l- Static build\l- Test build RPM\l"]
  "alt_build" -> "success" [color="#0000f0"]
  "build" -> "success" [color="#0000f0"]
  "ext_svc_check" [shape=ellipse style=bold color=h fontcolor=h]
  "ext_svc_check" -> "success" [color=h]
  "ext_svc_check" -> "build" [color=h]
  "smoke" [shape=ellipse style=bold color=i fontcolor=i]
  "smoke" -> "success" [color=i]
  "smoke" -> "build" [color=i]
