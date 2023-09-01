#!/usr/bin/env python3

"""
Given one or more image/manifest-list dirs, attempt validation by various means.

Dependencies: Skopeo and everything listed in requirements.txt

Both image/manifest-list directories are expected to have been produced with
a successful `skopeo sync -a --scoped --preserve-digests -s docker -d dir ...`
or similar.  The `--scoped` part is really important, basic sanity checks
will fail w/o this.  Script assumes all examined content is whole and complete.

Output will include each FQIN dir, followed by a set of validation
checks and results.  All results will be of the form of (literal)
PASS/INDETERMINATE/FAIL w/ optional details as a comment when appropriate/possible.
If any result is not PASS, the script will exit with a non-zero code.

Note: Most result comments will not contain many specific details.  You may
need to run the script again in `--verbose` mode to discover where/why.
"""

# Note about 'manifest' naming:
#
# This term can be ambiguous and is thrown around a lot w/in and around
# container tools, docs, internally in this script, and in JSON data.
# It's esp. confusing WRT 'manifest-lists' which contain a 'manifests'
# list pointing at nested 'manifests'.  This can mean both the list item
# AND names data-type the thing it's pointing.  I've done my best to keep
# use of these terms consistent, but it's really hard and both my patients
# and immagination are limited.  Sorry in advance.

import json
import os
import os.path
import sys
from argparse import ArgumentParser
from contextlib import contextmanager
from datetime import datetime
from datetime import timedelta
from hashlib import sha256
from pathlib import Path
from pprint import pformat

# Ref: https://dateutil.readthedocs.io/en/stable/index.html
import dateutil.parser
import dateutil.tz

# Ref: https://gql.readthedocs.io/en/latest/index.html
from gql import Client as GQLClient
from gql import gql
from gql.transport.requests import RequestsHTTPTransport


DEFAULT_OS = None
DEFAULT_ARCH = None

# GraphQL API URL for Cirrus-CI
CCI_GQL_URL = "https://api.cirrus-ci.com/graphql"

# Magic value required in special cases
NA_RESULT_SENTINEL = f"@@@{id(json.loads)}@@@"

# Magic value to indicate the cirrus check is disabled
CIRRUS_DISABLED_SENTINEL = datetime.fromtimestamp(0, dateutil.tz.UTC)

# Magic string indicating check was skipped and not to display in results.
CHECK_SKIPPED_RESULT = "PASS  # Check skipped"

# Label representing the commit-sha of the image source
OCI_REV_LABEL = "org.opencontainers.image.revision"

# Minimum required labels for the -c,--cirrus check to work
CIRRUS_REQ_LABELS = set(["org.opencontainers.image.created", "org.opencontainers.image.source"])

# Default minimum required OCI labels.  Also required for cirrus_check().
DEF_REQ_LABELS = CIRRUS_REQ_LABELS | set([OCI_REV_LABEL])

# Yes there's a better way than using a global for this, I don't care.
# Default values listed within.
options = {
    # Set True when --verbose is first argument
    "verbose": False,
    # All manifest-lists/images must come from this registry
    "expected_registry": "quay.io",
    # containers/automation/build_push/bin/main.sh always build these
    # ignored for simple images
    "expected_platforms": set(["linux/amd64", "linux/s390x", "linux/ppc64le", "linux/arm64"]),
    # Labels that must be present in all images and manifest-list items
    # For manifest-lists, each must have matching sets of labels.
    "expected_labels": DEF_REQ_LABELS,
    # Disabled by default, see matching_check() docs.
    "matching_digests": False,
    # Disabled by default, see cirrus_check() docs
    "cirrus_timestamp": CIRRUS_DISABLED_SENTINEL,
    # Only relevant if cirrus_timestamp != CIRRUS_DISABLED_SENTINEL
    "max_cirrus_push_diff_min": 3,
    # Not all images may have a 'org.opencontainers.image.revision' label
    "commit_override": None,
}

############################
#                          #
# Helper/utility functions #
#                          #
############################


def msg(txt, pfx="", fd=sys.stdout):
    """Write msg with indent and prefix to fd followed by a newline."""
    indent = " " * 2 * _indent
    fd.write(f"{indent}{pfx}{txt}\n")


def dbg(txt):
    """Print msg with indent to stderr, when verbose is true."""
    if options["verbose"]:
        msg(txt, pfx="DEBUG: ", fd=sys.stderr)


def err(txt):
    """Print error message with indent to stderr then raise RuntimeError."""
    msg(txt, pfx="ERROR: ", fd=sys.stderr)
    sys.exit(1)


# There are lots of checks and loops and it's easy to get lost examining
# even debugging messages.  Use a context-managed message-indent scheme
# to help out humans.
_indent = 0


@contextmanager
def indented_output(dbgmsg=None):
    """Increment indentation level within an execution context."""
    global _indent
    _indent += 1
    if dbgmsg is not None:
        dbg(dbgmsg)
    try:
        yield _indent
    finally:
        _indent -= 1


def getkey_nocase_default(dictionary, key, default=None):
    """
    Return item's value or default from dictionary regardless of key case.

    There's lots of mixed value fetching from JSON parsed directly
    or from skopeo inspect output.  In all instances, the case of
    the key is irrelevant.  Behave like dict().get() w/o any case
    sensitivity.
    """
    for _key, _value in dictionary.items():
        if key.lower() == _key.lower():
            return _value
    return default


def getkey_nocase(dictionary, key):
    """
    Return item from dictionary regardless of key case.

    Identical to getkey_nocase_default but raises KeyError
    """
    for _key, _value in dictionary.items():
        if key.lower() == _key.lower():
            return _value
    # Assume this will throw an exception with a helpful message
    # and traceback.  Doing that ourself would be more complex.
    return dictionary[key.lower()]


def default_platform():
    """
    Return local golang platform (os/arch).

    For simple images, there might not be OS and/or Arch items in
    the manifest. Especially for images produced by older tooling.
    When accessing these images, tooling is suppose to default to
    the local os/arch.  However, since golang uses "special"
    architecture names, it's simpler to rely on other golang tooling
    to look them up.  Buildah stands out as well suited to this
    since it probably won't complain if this script happens to be
    executing in a container environment.  Podman might.
    """
    # Oof, I'd like to do this using buildah but apparently running it under
    # (cough) Docker environment breaks due to disallowed CLONE_NEWUSER call >:|
    # This is no problem for podman, but unf. the current CI system uses Docker.
    # Hard-code the default platform values for now.  Though the following
    # commented-out code is otherwise more reliable :(
    #
    # buildah_pipe = os.popen("command buildah info")
    # try:
    #     buildah_output = buildah_pipe.read()
    #     buildah_info = json.loads(buildah_output)
    # except json.decoder.JSONDecodeError:
    #     raise RuntimeError(f"Buildah info output does not parse as JSON: '{buildah_output}'")
    # finally:
    #     buildah_exit = buildah_pipe.close()
    #     if buildah_exit is not None:
    #         raise RuntimeError(f"Non-zero exit({buildah_exit}) from buildah with output: '{buildah_output}'")
    # host_info = getkey_nocase(buildah_info, "host")
    # default_os = getkey_nocase(host_info, "os")
    # default_arch = getkey_nocase(host_info, "arch")
    # return (default_os, default_arch)
    return ("linux", "amd64")


def skopeo_cmd(skopeo_args):
    """Execute skopeo, return error string or JSON object on success."""
    try:
        skopeo_pipe = os.popen(f"command skopeo {skopeo_args}")
        skopeo_output = skopeo_pipe.read()
        skopeo_json = json.loads(skopeo_output)
    except json.decoder.JSONDecodeError:
        # Some callers may be expecting this
        return f"Skopeo output does not parse as JSON: '{skopeo_output}'"
    finally:
        skopeo_exit = skopeo_pipe.close()
        # Some callers may be expecting a non-zero exit
        if skopeo_exit is not None:
            dbg(f"Skopeo exit({skopeo_exit}) output: {skopeo_output}")
            return f"Skopeo command exited non-zero: {skopeo_exit}"
    return skopeo_json


def exit_with_results(fqin_details, override_status=None):
    """
    Display each fqin or fqin_path along with validation results.

    When override_status is not none, script will ALWAYS exit with that code
    regardless of any check result.
    """
    dbg("Processing validation results for output")

    exit_code = 0
    for fqin_detail in fqin_details:
        # The fqin isn't always reliably known (e.g. sanity_check failure)
        try:
            identifier = fqin_detail["fqin"]
        except KeyError:
            identifier = fqin_detail["fqin_path"]
        msg(f"Validation results for '{identifier}':")
        for check_name, check_result in fqin_detail["results"].items():
            with indented_output(f"Processing check '{check_name}'"):
                if check_result is None:
                    dbg("No result, possible script/resource-access fault/bug")
                    msg("INDETERMINATE", pfx=f"{check_name}: ")
                    if exit_code < 20:  # Exit with worst-fault level encountered
                        exit_code = 20
                elif str(check_result).startswith("PASS"):
                    if check_result != CHECK_SKIPPED_RESULT:
                        msg(str(check_result), pfx=f"{check_name}: ")
                else:  # format-strings convert check_result
                    msg(f"FAIL  # {check_result}", pfx=f"{check_name}: ")
                    if exit_code < 10:  # Exit with worst-fault level encountered
                        exit_code = 10

    if override_status is not None:
        sys.exit(override_status)

    sys.exit(exit_code)


def set_check_result(fqin_detail, check_name, check_result):
    """
    Set check result in fqin_detail dict, only if it's missing or None.

    Note: Assumes fqin_detail["results"] exists and is also a dictionary.
    """
    na_result = "PASS  # N/A"
    fqin_path = fqin_detail.get("fqin_path")
    msg_sfx = f"check '{check_name}' with result '{check_result}' for item '{fqin_path}'"
    with indented_output(f"Setting {msg_sfx}"):
        update_okay = [
            fqin_path is not None,
            check_name is not None,
            # This is critical, fail if any result would be overwritten
            fqin_detail["results"].get(check_name) is None,
        ]

        # Some check results are non-applicable for various reasons.
        if check_result == NA_RESULT_SENTINEL:
            check_result = na_result

        if all(update_okay) and fqin_detail["results"].get(check_name) is None:
            fqin_detail["results"][check_name] = check_result
            return None
        # Attempted N/A result updates are never an error, simply ignore them.
        elif check_result == na_result:
            dbg("Ignoring attempted update of N/A result.")
            return None

        err(f"Refusing to update {msg_sfx}")


def get_platform(dct, err_pfx="Encountered null"):
    """Return the platform string from dict-like object or error string (w/o a '/')."""
    _os = getkey_nocase_default(dct, "os", DEFAULT_OS)
    if _os is None:
        return f"{err_pfx} OS value."

    _arch = getkey_nocase_default(dct, "architecture")
    if _arch is None:
        return f"{err_pfx} architecture value."

    return "/".join([_os, _arch])


def get_ml_platform(ml_item):
    """Return the platform string for a manifest-list item or error string (w/o a '/')."""
    def_plat = {"os": DEFAULT_OS, "architecture": DEFAULT_ARCH}
    platform = getkey_nocase_default(ml_item, "platform", def_plat)

    err_pfx = "Encountered null manifest-list item"
    if platform is None:
        return f"{err_pfx} platform value."
    return get_platform(platform, err_pfx)


def config_same(as_platform, config):
    """Return config platform on match, or error message w/o '/' if mismatched."""
    with indented_output(f"Checking {as_platform} matches config"):
        config_platform = get_platform(config, "Encountered null config")
        if "/" not in config_platform:
            return config_platform  # there was an error
        if as_platform != config_platform:
            return "The {as_platform} != config {config_platform}"
        return config_platform


def examine_fqin(dbg_msg, fqin_detail, process_fn, results=None):
    """
    Call a processing functin for each provided image or manifest-list item.

    This is just a helper, it de-duplicates the process of looping through
    manifest-lists.  The results dictionary passed to each call to process_fn,
    is intended for storing accumulated results.  The process_fn is free to
    do with it as it pleases.  The examine_fqin() function will return the
    final call_result value as described below.  The process_fn function
    must have the following signature:

    def process_fn(fqin_detail, digest, manifest, config, results)

    It is expected to return an empty string if processing should continue.
    Alternately, it may return "PASS", "FAIL" string, or None (indeterminate/bug)
    to immediately stop looping and return that value to the caller.

    Note: Most of the inspection happens via skopeo since it does some
    minimal internal validation, and provides the most generally applicable
    data.  However it does hide some low-level details only accessible by
    reading the files directly.
    """
    dbg(dbg_msg)
    call_result = None  # An indeterminate/bug result
    fqin = fqin_detail["fqin"]
    fqin_path = fqin_detail["fqin_path"]

    if fqin_detail["is_manifest_list"]:
        manifest_list = getkey_nocase(fqin_detail["manifest"], "manifests")
        for item in manifest_list:
            ml_digest = getkey_nocase(item, "digest")
            if ml_digest is None:
                call_result = f"Missing digest in manifest-list '{fqin}'."
                break  # stop examining anything else

            ml_platform = get_ml_platform(item)
            if "/" not in ml_platform:  # it's a failure message
                call_result = ml_platform
                break

            ml_os, ml_arch = ml_platform.split("/", 2)

            with indented_output(f"Getting manifest and config from {fqin} manifest-list item '{ml_digest}'"):
                _cmd_sfx = f"--override-arch {ml_arch} --override-os {ml_os} dir:{fqin_path}"
                config = skopeo_cmd(f"inspect --config {_cmd_sfx}")
                if isinstance(config, str):
                    return config  # failure message

                manifest = skopeo_cmd(f"inspect {_cmd_sfx}")
                if isinstance(manifest, str):
                    return manifest  # failure message

                call_result = process_fn(fqin_detail, ml_digest, manifest, config, results)
                if call_result != "":
                    break  # Stop looping, return immediately with results
    else:  # Regular image
        manifest_digest = fqin_detail["manifest_digest"]
        with indented_output(f"Getting image config and manifest for '{fqin}'"):
            config = skopeo_cmd(f"inspect --config dir:{fqin_path}")
            if isinstance(config, str):
                return config  # failure message

            manifest = skopeo_cmd(f"inspect dir:{fqin_path}")
            if isinstance(manifest, str):
                return manifest  # failure message

            call_result = process_fn(fqin_detail, manifest_digest, manifest, config, results)

    return call_result


def _ml_platform_digests(manifests):
    """Internal helper for use by digests_match() the helpers, do not use directly."""
    platform_digests = {}
    with indented_output("Verifying & gathering platforms and digests."):
        for item in manifests:
            digest = getkey_nocase(item, "digest")
            if digest is None:
                # This could be an outright error, for now assume some other
                # check will catch and flag this.
                return f"Manifest-list item has Null digest {digest}"

            platform = get_ml_platform(item)
            if "/" not in platform:  # it's a failure message
                return platform
            # Assume another check will find any platform duplicates
            platform_digests[platform] = digest

    if not bool(platform_digests):
        return "Did not find any platforms."

    return platform_digests


def _ml_to_ml(lhs_fqin_detail, rhs_fqin_detail):
    """Helper for digests_match()."""
    # Order of manifests entries is not guaranteed, must check each.
    lhs_manifests = getkey_nocase(lhs_fqin_detail["manifest"], "manifests")
    rhs_manifests = getkey_nocase(rhs_fqin_detail["manifest"], "manifests")
    lhs_platform_digests = _ml_platform_digests(lhs_manifests)
    if isinstance(lhs_platform_digests, str):  # it's a failure message
        dbg(lhs_platform_digests)
        return False

    with indented_output("Comparing platforms and digests."):
        for rhs_item in rhs_manifests:
            rhs_digest = getkey_nocase(rhs_item, "digest")
            if rhs_digest is None:
                dbg(f"Manifest-list item has Null digest {rhs_digest}")
                return False

            rhs_platform = get_ml_platform(rhs_item)
            if "/" not in rhs_platform:  # it's a failure message
                dbg(rhs_platform)
                return False

            pretty = pformat(lhs_platform_digests)
            # Assume another check will find any rhs_platform duplicates
            if getkey_nocase(lhs_platform_digests, rhs_platform) == rhs_digest:
                dbg("Manifest-list manifests exactly match for each platform")
                return True

            dbg(f"Manifest-list item {rhs_digest} for platform {rhs_platform} missing from: {pretty}")
            return False


def _ml_to_img(ml_fqin_detail, image_fqin_detail):
    """Helper for digests_match()."""
    manifests = getkey_nocase(ml_fqin_detail["manifest"], "manifests")
    ml_platform_digests = _ml_platform_digests(manifests)
    if isinstance(ml_platform_digests, str):  # it's a failure message
        dbg(ml_platform_digests)
        return False

    img_platform = get_platform(image_fqin_detail["manifest"])
    if "/" not in img_platform:  # it's a failure message
        dbg(img_platform)
        return False

    ml_fqin = ml_fqin_detail["fqin"]
    image_fqin = image_fqin_detail["fqin"]
    img_digest = image_fqin_detail["manifest_digest"]
    if img_digest == getkey_nocase(ml_platform_digests, img_platform):
        dbg(f"Found manifest-list {ml_fqin} matches image {image_fqin} digest for platform.")
        return True

    dbg(
        f"Simple image {image_fqin} digest {img_digest} not"
        f" present/no-match with {img_platform} in manifest-list {ml_fqin}"
    )
    return False


def _img_to_img(lhs_manifest, rhs_manifest):
    """Helper for digests_match()."""
    # Digests compared at start of digests_match(), only need to check layers
    lhs_layers = getkey_nocase(lhs_manifest, "layers")
    rhs_layers = getkey_nocase(rhs_manifest, "layers")
    # This should never happen, but catch it anyway.  Since it's rare,
    # assume the user can figure out which manifest is broken.
    if lhs_layers is None or rhs_layers is None:
        dbg("Encountered Null Layers list in manifest.")
    elif lhs_layers == rhs_layers:
        dbg("Simple images found to have matching layers.")
        return True
    return False


def digests_match(lhs_fqin_detail, rhs_fqin_detail):
    """Given two initialized fqin_details, compare digests for corresponding platforms."""
    lhs_fqin = lhs_fqin_detail["fqin"]
    rhs_fqin = rhs_fqin_detail["fqin"]
    with indented_output(f"Checking exact {lhs_fqin} == {rhs_fqin} digest match"):
        if lhs_fqin_detail["manifest_digest"] == rhs_fqin_detail["manifest_digest"]:
            dbg(f"Exact digest match found, {lhs_fqin} == {rhs_fqin}")
            return True

    if lhs_fqin_detail["is_manifest_list"] and rhs_fqin_detail["is_manifest_list"]:
        with indented_output(f"Comparing ML {lhs_fqin} to ML {rhs_fqin}"):
            return _ml_to_ml(lhs_fqin_detail, rhs_fqin_detail)

    elif lhs_fqin_detail["is_manifest_list"] and not rhs_fqin_detail["is_manifest_list"]:
        with indented_output(f"Comparing ML {lhs_fqin} to IMG {rhs_fqin}"):
            # Order is significant, left-side is always a manifest-list
            return _ml_to_img(lhs_fqin_detail, rhs_fqin_detail)

    elif not lhs_fqin_detail["is_manifest_list"] and rhs_fqin_detail["is_manifest_list"]:
        with indented_output(f"Comparing ML {rhs_fqin} to IMG {lhs_fqin}"):
            # Order is significant, left-side is always a manifest-list
            return _ml_to_img(rhs_fqin_detail, lhs_fqin_detail)

    elif not lhs_fqin_detail["is_manifest_list"] and not rhs_fqin_detail["is_manifest_list"]:
        with indented_output(f"Comparing IMG {lhs_fqin} to IMG {rhs_fqin}"):
            return _img_to_img(lhs_fqin_detail["manifest"], rhs_fqin_detail["manifest"])

    dbg(f"Failure comparing {lhs_fqin} to {rhs_fqin}")
    return None  # No match found


def gather_labels(fqin_detail):
    """
    Gataher and check consistency of labels for manifest-list or image.

    Returns a dictionary of labels or an error value (could be None).
    """
    fqin = fqin_detail["fqin"]
    results = {}
    call_result = examine_fqin(
        f"Gathering manifest-list/image labels from '{fqin}'", fqin_detail, labels_check_process, results=results
    )

    # call_result is "" only after successfully looping all manifest-list items
    if call_result != "":  # "FAIL"/None
        if call_result.startswith("PASS"):
            dbg("Something in labels_check_process() is broken/bugged")
            return None
        return call_result
    return results


def _query(gqlclient, query, verbose=False, **dargs):
    """Issue GraphQL query using client and optional dargs."""
    result = gqlclient.execute(query, variable_values=dargs)
    errors = result.get("errors")
    if errors is not None and result.get("data") is None:
        error_s = pformat(errors)
        err(f"Bad Cirrus-API GraphQL Query '{query}' or service failure: '{error_s}'")
    pretty = pformat(result)
    # This can be rather noisy, keep it off unless specifically requested
    if verbose:
        dbg(f"Cirrus-CI API Reply: {pretty}")
    return result


def is_valid_cirrus_api_gh_repo(gqlclient, gh_owner, gh_name):
    """Return True if Cirrus-CI replies with a repo ID."""
    with indented_output(f"Verifying Cirrus-CI knows about GH repo {gh_owner}/{gh_name}"):
        query = gql(
            """
            query gh_repo_id($owner: String!, $name: String!) {
              ownerRepository(platform: "github", owner: $owner, name: $name) {
                id
              }
            }
        """
        )
        result = _query(gqlclient, query, owner=gh_owner, name=gh_name)
        repo_id = int(result.get("ownerRepository", {}).get("id", 0))
        return bool(repo_id)


def is_main_build(gqlclient, bid):
    """Legitimate container images are/were only pushed from 'main'."""
    with indented_output(f"Determining if Build ID {bid} ran on 'main' branch."):
        query = gql(
            """
          query build_branch($bid: ID!) {
            build(id: $bid) {
              branch
            }
          }
        """
        )
        result = _query(gqlclient, query, bid=bid)

        branch_name = result.get("build", {}).get("branch", "").strip()
        if branch_name in ["master", "main"]:
            return True
        dbg(f"Warning: {bid} came from a non-main branch!")
        return False


def get_cirrus_builds(gqlclient, gh_owner, gh_name, commit):
    """Return a list of Cirrus-CI build IDs (if any) found for commit."""
    with indented_output(f"Looking up Cirrus-CI Build IDs for https://github.com/{gh_owner}/{gh_name}/commit/{commit}"):
        query = gql(
            """
          query builds_by_commit($owner: String!, $name: String!, $sha: String!) {
            searchBuilds(
              repositoryOwner: $owner
              repositoryName: $name
              SHA: $sha
            ) {id}
          }
        """
        )
        result = _query(gqlclient, query, owner=gh_owner, name=gh_name, sha=commit)

        build_ids = []
        for item in result.get("searchBuilds", []):
            bid = int(item.get("id"))  # Validate it's a number
            # I've never ever seen a "small" Cirrus-CI build ID
            if bid > 123456789 and is_main_build(gqlclient, bid):
                build_ids.append(str(bid))

        return build_ids


def cirrus_success_before(gqlclient, build_ids, image_created):
    """
    Return list of build_ids started before image_created.

    N/B: This search includes potentially unsuccessful builds since they
    still may have had successful image-build tasks.
    """
    good_bids = []
    for build_id in build_ids:
        with indented_output(f"Looking up start time and status for {build_id}"):
            query = gql(
                """
              query started_status($bid: ID!) {
                build(id: $bid) {
                  buildCreatedTimestamp
                }
              }
          """
            )
            result = _query(gqlclient, query, bid=build_id)
            created = result.get("build", {}).get("buildCreatedTimestamp")

            build_start = datetime.fromtimestamp(int(created) / 1000.0, tz=dateutil.tz.UTC)
            # The org.opencontainers.image.created label value must always
            # be some time after the build start-time.
            if image_created < build_start:
                continue
            dbg(f"Yay! Identified relevant build warranting further inspection https://cirrus-ci.com/build/{build_id}")
            good_bids.append(build_id)
    return good_bids


def get_cirrus_task_finish_times(gqlclient, build_ids, image_created):
    """
    Find successful image_build tasks for build_ids started before image_created.

    Return value is list of (task_id, final_timestamp) tuples
    """
    found_tasks = []
    for build_id in build_ids:
        with indented_output(f"Searching for image_build tasks from build {build_id}."):
            query = gql(
                """
            query task_details($bid: ID!) {
              build(id: $bid) {
                tasks {
                  id
                  name
                  nameAlias
                  status
                  baseEnvironment
                  finalStatusTimestamp
                }
              }
            }
          """
            )
            result = _query(gqlclient, query, bid=build_id)
            # result = _query(gqlclient, query, bid=build_id)
            for task_detail in result.get("build", {}).get("tasks", []):
                # This is a bit ham-fisted.  Some kind of fancy task-filter
                # argument could be passed into this function to filter
                # the tasks.  But I'm lazy and currently only have a
                # single use-case relating to
                # https://github.com/containers/podman/discussions/19796
                # The quay.io stable podman/buildah/skopeo images were
                # always produced by task name ending in "stable".
                # Select those.
                name = task_detail.get("name").strip()
                if task_detail.get("nameAlias") != "image_build" or not name.endswith("stable"):
                    continue

                # Tasks can be re-run, have to check each/every one
                if task_detail.get("status").lower() != "completed":
                    dbg("Ignoring unsuccessful task")
                    continue

                # Builds always ran from cron job with this name
                required_env = "CIRRUS_CRON=multiarch"
                if required_env not in task_detail.get("baseEnvironment", []):
                    dbg(f"Ignoring task missing env. var. '{required_env}'")
                    continue

                finished = task_detail.get("finalStatusTimestamp")
                task_end = datetime.fromtimestamp(int(finished) / 1000.0, tz=dateutil.tz.UTC)
                # The org.opencontainers.image.created label value must always
                # be some time before the successful task finished
                if image_created > task_end:
                    dbg(f"Image 'created' label time {image_created} is after {task_end}")
                    continue

                tid = int(task_detail.get("id"))  # Validate it's a number
                dbg(
                    f"Yay! Identified successful and relevant '{name}' task"
                    " warranting further inspection https://cirrus-ci.com/task/{tid}"
                )
                found_tasks.append((tid, task_end))
    return found_tasks


@contextmanager
def cirrus_ci_api_client():
    """Simplify obtaining & closing client instance w/ synchronous transport."""
    xport = RequestsHTTPTransport(url=CCI_GQL_URL, verify=True, retries=3)
    try:
        with GQLClient(transport=xport, fetch_schema_from_transport=True) as client:
            yield client
    finally:
        xport.close()


############################################
#                                          #
# Image/manifest-list validation functions #
#                                          #
############################################


def sanity_check(fqin_path, fqin_details):
    """
    Verify image or manifest_list basic sanity, return failure or "" for success.

    Despite the script assuming already validated input, a minimum baseline
    is required for each fqin_path otherwise further checks are pointless.
    Also verify any required registry server is present for each item and
    verify there are no duplicate inputs.
    """
    manifest_path = fqin_path / "manifest.json"
    # Required/expected minimum contents by caller
    fqin_detail = {"fqin_path": fqin_path, "manifest_path": manifest_path, "results": {"Sanity": None}}

    # Basic directory checks & name component contains a ':' w/ tag name
    # and contains at least 3 path "parts".
    sanity_checks = {
        "Path does not exist": os.path.exists(fqin_path),
        "Path is not a dir": os.path.isdir(fqin_path),
        "Path has < 3 name components": len(fqin_path.parts) >= 3,
        "Final path name missing ':'": fqin_path.parts[-1].rfind(":", 1, -1) >= 0,
        "No manifest.json inside path": os.path.exists(manifest_path),
        "manifest.json not a file": os.path.isfile(manifest_path),
    }

    def set_sanity_result(result):
        return set_check_result(fqin_detail, "Sanity", result)

    result_comment = ""

    if all(sanity_checks.values()):
        with indented_output(f"Extracting FQIN from dir '{fqin_path}' path name"):
            # The --scoped option to skopeo sync is critical for this.
            # There's no other reliable/verifiable way to assert the actual FQIN
            # sync'd down from the remote repository.  Internal annotations can
            # be manipulated (checked later).
            fqin = "/".join(fqin_path.parts[-3:])  # path length asserted >= 3
            fqin_detail.update({"fqin": fqin})

            # This check is done here because a mismatch should block all
            # other checks.
            exp_reg = options["expected_registry"]
            if exp_reg is not None:
                dbg(f"Checking for required registry server '{exp_reg}'")
                if not fqin.startswith(exp_reg):
                    set_sanity_result(f"Missing '{exp_reg}' registry server")
                    return fqin_detail
            else:
                # N/B: Value must be different from CHECK_SKIPPED_RESULT
                # otherwise sanity-check result won't be displayed.
                result_comment = "  # Registry check skipped."

            dbg(f"Checking for duplicate FQIN dir '{fqin_path}' or symlink")
            for existing in fqin_details:
                existing_path = existing.get("fqin_path")
                with indented_output(f"Checking if dir '{fqin_path}' matches existing '{existing_path}'"):
                    # Another entry may have failed sanity checking, can't count
                    # on "fqin" being present.
                    if fqin == existing.get("fqin") or fqin_path == existing_path:
                        set_sanity_result("FQIN dir specified twice or symlinked")
                        return fqin_detail

            # Script assumes skopeo sync was successful and complete
            dbg(f"Loading FQIN '{fqin}' manifest JSON from {manifest_path}")
            with open(manifest_path, "r", encoding="utf-8") as manifest_file:
                # Contents will be verified later, only care if it loads.
                try:
                    manifest = json.load(manifest_file)
                    fqin_detail.update({"manifest": manifest})
                except json.decoder.JSONDecodeError:
                    set_sanity_result("Failed to parse manifest as JSON")
                    return fqin_detail

            # Verifiable digest for the manifest-list/image on registry
            dbg(f"Calculating manifest-list/image '{fqin}' digest from manifest.json")
            with open(manifest_path, "rb") as manifest_file:
                hasher = sha256()
                hasher.update(manifest_file.read())
                # All values in image/layer JSON contain 'sha256' prefix
                fqin_detail.update({"manifest_digest": f"sha256:{hasher.hexdigest()}"})
            dbg(f"Determining if '{fqin}' is an image or manifest-list.")
            # JSON will translate a 'null' into None, catch this.
            sentinel = f"@@@@@{id(manifest)}@@@@@"
            manifest_list = getkey_nocase_default(manifest, "manifests", sentinel)
            if manifest_list != sentinel:
                if isinstance(manifest_list, list):
                    with indented_output(f"FQIN dir '{fqin_path}' appears to represent a manifest-list"):
                        fqin_detail["is_manifest_list"] = True
                else:
                    set_sanity_result(f"Present manifest 'manifests' item is a non-list: '{manifest_list.__class__}'")
                    return fqin_detail

            else:  # no 'manifests' item present
                with indented_output(f"FQIN dir '{fqin_path}' appears to represent a refular/simple image"):
                    fqin_detail["is_manifest_list"] = False

            set_sanity_result(f"PASS{result_comment}")
            return fqin_detail

    dbg(f"Setting basic sanity check failure for '{fqin_path}'")
    basic_fail_index = list(sanity_checks.values()).index(False)
    basic_result = list(sanity_checks.keys())[basic_fail_index]
    set_sanity_result(basic_result)
    return fqin_detail


def skopeo_check_process(fqin_detail, digest, manifest, config, results):
    """Processing helper for skopeo_check()."""
    expected_mani_keys = set(["digest", "created", "labels", "architecture", "os", "layers", "layersdata"])
    expected_cfg_keys = set(["created", "architecture", "os", "config", "rootfs", "history"])
    with indented_output(f"Examining config and manifest keys in '{digest}'"):
        actual_mani_keys = set([k.lower() for k in manifest.keys()])
        actual_cfg_keys = set([k.lower() for k in config.keys()])

        for expected, actual, name in [
            (expected_mani_keys, actual_mani_keys, "manifest"),
            (expected_cfg_keys, actual_cfg_keys, "config"),
        ]:
            missing = expected - actual
            if bool(missing):
                return f"Missing (case-insensitive) {name} key(s): {missing}"
    return ""  # Everything is okay, continue.


def skopeo_check(fqin_detail, fqin_details):
    """
    Validate skopeo is able to successfully inspect image/manifest list.

    Experimentation shows, skopeo inspect doesn't actually perform many
    actual checks on the image/manifest-list.  However, it's very useful
    for easily accessing various parts of an image/manifest list.  This
    is utilized heavily by more involved checks, and so it's basic
    functionality should be confirmed.
    """
    dbg("Executing raw skopeo raw inspect on manifest-list/image")
    fqin = fqin_detail["fqin"]
    fqin_path = fqin_detail["fqin_path"]
    raw_manifest = skopeo_cmd(f"inspect --no-tags --raw dir:{fqin_path}")
    if isinstance(raw_manifest, str):
        return raw_manifest  # failure message

    call_result = examine_fqin(f"Confirming basic skopeo processing of '{fqin}'", fqin_detail, skopeo_check_process)

    # call_result is "" only after successfully looping all manifest-list items
    if call_result == "":  # Clean-run, no failures.
        return "PASS"
    return call_result


def manifest_check_process(fqin_detail, digest, manifest, config, results):
    """Processing helper for manifest_check()."""
    fqin = fqin_detail["fqin"]
    with indented_output(f"Checking/Validating item '{digest}' from '{fqin}'"):
        # Near as I can tell, you can't access the config digest through skopeo
        # on a manifest list (i.e. using both --raw and --override-X).  However,
        # all that's desired by manifest_check(), is to ensure there are no
        # duplicates configs.  Calculating our own hash is good enough for that.
        hasher = sha256()
        # utf-8 is the standard for json string conversions.
        hasher.update(bytes(json.dumps(config, sort_keys=True), encoding="utf-8"))
        config_digest = f"sha256:{hasher.hexdigest()}"
        results["config_digests"].append(config_digest)

        manifest_platform = config_same(get_platform(manifest), config)
        if "/" not in manifest_platform:
            return manifest_platform

        # Note: This is not the same as what's done in platforms_check()
        dbg(f"Verifying {fqin} manifest platform {manifest_platform}")
        if manifest_platform not in results["expected_platforms"]:
            pretty = pformat(results["expected_platforms"])
            return f"Manifest platform not in {pretty}"

        dbg("Storing layer digests for uniqueness comparison later")
        # No need to further validate these values, the image literally won't
        # work if they're wrong.
        # TODO: Probably should check compressed manifest["LayersData"]
        # "MIMEType" item for gzip (it may not be once zstd support is widespread)
        # Would also be good to validate the LayerData digests match the Layers list.
        comp_layer_digests = getkey_nocase(manifest, "layers")
        if comp_layer_digests is None or comp_layer_digests == []:
            return "Found unset or empty layers (case-insensitive) it manifest."
        results["comp_layer_digests"].extend(comp_layer_digests)

        config_path = fqin_detail["fqin_path"] / config_digest
        rootfs = getkey_nocase(config, "rootfs")
        if getkey_nocase(rootfs, "type").lower() != "layers":
            return f"Config JSON from '{config_path}' rootfs not type=layers"
        uncomp_config_layer_digests = getkey_nocase(rootfs, "diff_ids")
        if uncomp_config_layer_digests is None or uncomp_config_layer_digests == []:
            return "Config rootfs layers (diff_ids) is empty or unset"

        # Not sure why this can be a list of empty-items for regular images,
        # but sometimes it is.  e.g. quay.io/podman/stable:v2.1.1
        if "" in uncomp_config_layer_digests:
            if not fqin_detail["is_manifest_list"]:
                dbg(f"Warning, encountered list of empty diff_ids in {fqin} config")
                return ""  # Everything is okay, continue.
            return '"" in diff_ids for manifest-list config'
        results["uncomp_layer_digests"].extend(uncomp_config_layer_digests)
    return ""  # Everything is okay, continue.


def manifest_check(fqin_detail, fqin_details):
    """
    Validate image/manifest-list contents are consistent w/o any duplication.

    This is a somewhat simplistic validation that layers don't point at eachother,
    share configs, and the platforms are consistent across manifest-lists and
    their manifests and configs, similar for regular images.
    """
    fqin = fqin_detail["fqin"]
    results = {
        "expected_platforms": [],
        "manifest_digests": [],
        "config_digests": [],
        "comp_layer_digests": [],
        "uncomp_layer_digests": [],
    }

    with indented_output(f"Obtaining expected platforms for '{fqin}'"):
        if fqin_detail["is_manifest_list"]:
            manifest_list = getkey_nocase(fqin_detail["manifest"], "manifests")
            for item in manifest_list:
                manifest_digest = getkey_nocase(item, "digest")
                if manifest_digest is None:
                    return "Found Null digest in manifests list"
                # Manifest-list item digest must all be unique.
                results["manifest_digests"].append(manifest_digest)
                with indented_output(f"Working on {manifest_digest}"):
                    ml_platform = get_ml_platform(item)
                    if "/" not in ml_platform:  # it's a failure message
                        return ml_platform
                    results["expected_platforms"].append(ml_platform)
        else:  # regular image
            image_platform = get_platform(fqin_detail["manifest"])
            if "/" not in image_platform:  # it's a failure message
                return image_platform

            results["expected_platforms"].append(image_platform)

    call_result = examine_fqin(
        f"Confirming manifest-list/image consistency for '{fqin}'", fqin_detail, manifest_check_process, results=results
    )

    # call_result is "" only after successfully looping all manifest-list items
    if call_result != "":  # "FAIL"/None
        if call_result.startswith("PASS"):
            dbg("Something in manifest_check_process() is broken/bugged")
            return None
        return call_result

    # Checking expected_platforms may seem pointless, however we want to
    # verify there isn't more than one manifest-list item per platform.
    # i.e. this is a different check that what's done in platforms_check()
    for check_name, check_values in results.items():
        set_value = set(check_values)
        # Simply a duplicates check
        len_check_values = len(check_values)
        len_set_check_values = len(set_value)
        if len_check_values != len_set_check_values:
            dbg(f"Duplicate {check_name} item found in {check_values}")
            return f"Found duplicated {check_name} item."

    return "PASS"


def labels_check_process(fqin_detail, digest, manifest, config, results):
    """Processing helper for labels_check() and cirrus_check()."""
    fqin = fqin_detail["fqin"]
    with indented_output(f"Gathering labels for {fqin} digest {digest}"):
        manifest_labels = getkey_nocase(manifest, "labels")
        if manifest_labels is None:
            return "Encountered Null manifest label list"

        config_labels = getkey_nocase(getkey_nocase(config, "config"), "labels")
        if config_labels is None:
            return "Encountered Null config label list"

        # Need to check both sets of labels and values.  Could use a set
        # comparison, but that would complicate providing nice failure messages.
        for manifest_label, manifest_value in manifest_labels.items():
            if manifest_label not in config_labels:
                return f"Missing manifest label {manifest_label} in config"
            config_value = config_labels[manifest_label]
            if manifest_value != config_value:
                return f"Different manifest label {manifest_label} value in config"

        for config_label, config_value in config_labels.items():
            if config_label not in manifest_labels:
                return f"Missing manifest label {manifest_label} in config"
            manifest_value = manifest_labels[config_label]
            if config_value != manifest_value:
                return f"Different config label {config_label} value in manifest"

            results[config_label] = config_value

    return ""  # Everything is okay, continue.


def check_expected_labels(expected_labels, actual_labels):
    """
    Validate all actual_labels are present in expected_labels.

    Returns "PASS" or None/error message string.
    """
    # All image/manifest-list labels must be in expected_labels
    actual_set = set(actual_labels.keys())
    a_pretty = pformat(actual_set)
    with indented_output(f"Checking missing labels among {a_pretty}"):
        # items in expected not present in actual
        act_exp_diff = expected_labels - actual_set
        if act_exp_diff != set([]):
            # Integration tests check for specific items in specific order
            sorted_diff = list(act_exp_diff)
            sorted_diff.sort()
            m_pretty = pformat(sorted_diff)
            # Integration tests check this debug value, do not modify!
            return f"Missing labels: {m_pretty}"

    return "PASS"


def labels_check(fqin_detail, fqin_details):
    """
    Validate image/manifest-list labels are consistent and present in expected_labels.

    Besides confirming any expected labels are present, this also validates the
    label consistency between manifest and config, for every manifest-list item and
    simple image.
    """
    expected_labels = options["expected_labels"]
    if not bool(expected_labels):
        return CHECK_SKIPPED_RESULT

    actual_labels = gather_labels(fqin_detail)
    if not isinstance(actual_labels, dict):
        return actual_labels  # An error value

    pretty = pformat(actual_labels)
    dbg(f"Verified consistent labels: {pretty}")
    return check_expected_labels(expected_labels, actual_labels)


def platforms_check_process(fqin_detail, digest, manifest, config, results):
    """Processing helper for platforms_check()."""
    fqin = fqin_detail["fqin"]
    with indented_output(f"Gathering platforms for {fqin} digest {digest}"):
        manifest_platform = get_platform(manifest)
        if "/" not in manifest_platform:
            return manifest_platform  # contains failure message

        config_platform = config_same(manifest_platform, config)
        if "/" not in config_platform:
            return config_platform  # contains failure message
        # Results will be processed as a set, so probably not necessary
        # to append both.  But that's assuming other checks validated
        # there are no duplicates.  Maybe that's not always a safe assumption?
        results.append(manifest_platform)
        results.append(config_platform)
    return ""  # Everything is okay, continue.


def platforms_check(fqin_detail, fqin_details):
    """
    Validate image/manifest-list platforms are all present in expected_platforms.

    This verifies there are no extra/unexpected platforms present and for
    manifest-lists, there is only one entry per platform.  It also confirms
    platforms are consistent between manifest and config.
    """
    fqin = fqin_detail["fqin"]
    results = []  # List of all platforms encountered
    call_result = examine_fqin(
        f"Gathering manifest-list/image platforms from '{fqin}'", fqin_detail, platforms_check_process, results=results
    )

    # call_result is "" only after successfully looping all manifest-list items
    if call_result != "":  # "FAIL"/None
        if call_result.startswith("PASS"):
            dbg("Something in platforms_check_process() is broken/bugged")
            return None
        return call_result

    expected_platforms = options["expected_platforms"]
    if expected_platforms is None:
        return CHECK_SKIPPED_RESULT

    # Platforms from manifest-lists must exactly match expected_platforms
    actual_set = set(results)
    a_pretty = pformat(actual_set)
    dbg(f"Validating found platforms: {a_pretty}")
    if fqin_detail["is_manifest_list"]:
        with indented_output("Checking missing platforms for manifest-list"):
            act_exp_diff = expected_platforms - actual_set
            if act_exp_diff != set([]):
                # Integration tests check for specific items in specific order
                sorted_diff = list(act_exp_diff)
                sorted_diff.sort()
                m_pretty = pformat(sorted_diff)
                # Integration tests check this debug value, do not modify!
                dbg(f"Missing platforms: {m_pretty}")
                return "Manifest-list missing expected platforms"

        with indented_output("Checking unexpected platforms for manifest-list"):
            act_exp_diff = actual_set - expected_platforms
            if act_exp_diff != set([]):
                u_pretty = pformat(act_exp_diff)
                dbg(f"Extra unexpected: {u_pretty}")
                return "Manifest-list has extra/unexpected platforms"

    else:
        with indented_output(f"Checking simple image {fqin} platform"):
            count = len(actual_set)
            if count != 1:
                return f"Expecting exactly one platform not {count}"
            actual_platform = results[0]
            if actual_platform not in options["expected_platforms"]:
                return "Unexpected platform."

    return "PASS"


# Name referenced from multiple locations
_matching_check_name = "Matching Digests"


def matching_check(fqin_detail, fqin_details):
    """
    Verify manifest-list item digests exactly match (by platform) across other fqins.

    The intention of this is to verify correspondence across FQINs which were
    build from using shared cache.  If there is a mix of simple images and
    manifest-lists, this check can only confirm the layers digests match.
    """
    if not options["matching_digests"]:
        return CHECK_SKIPPED_RESULT

    # It's simpler/easer/faster to check all items in one go
    if fqin_detail != fqin_details[0]:
        # Special case to avoid set_check_result() blowing up
        # due to result-overwrite protection.
        return NA_RESULT_SENTINEL

    dbg("Verifying equivalency across all fqin_details")
    this = fqin_detail
    this_fqin = this["fqin"]
    for other in fqin_details:
        other_fqin = other["fqin"]
        if this_fqin == other_fqin:
            continue  # No need to self-compare
        with indented_output(f"Comparing {this_fqin} to {other_fqin}"):
            if not digests_match(this, other):
                # With really long digests and other details being compared,
                # it would be very hard to summarize and keep output readable.
                # It's not very nice, but probably safe to just expect user
                # to re-run the check in verbose mode to discover the details.
                set_check_result(other, _matching_check_name, f"{other_fqin} != {this_fqin}")
                return f"{this_fqin} != {other_fqin}"
    return "PASS  # All digests match"


def cirrus_check(fqin_detail, fqin_details):
    """Check timestamp from CLI matches +/- 2m to Cirrus-CI API using FQIN commit SHA."""
    if options["cirrus_timestamp"] == CIRRUS_DISABLED_SENTINEL:
        return CHECK_SKIPPED_RESULT

    # The label_check() may be disabled/altered on command-line,
    # validate minimum required labels for this check.
    with indented_output("Gathering/verifying labels for Cirrus-CI Check"):
        labels = gather_labels(fqin_detail)
        if not isinstance(labels, dict):
            return labels  # An error value

        check_result = check_expected_labels(CIRRUS_REQ_LABELS, labels)
        if not check_result.startswith("PASS"):
            return check_result  # Missing labels or Validation failed

    pretty = pformat(labels)
    with indented_output(f"Validating label values {pretty}"):
        try:
            image_created_value = labels["org.opencontainers.image.created"]
            # N/B: This timestamp is _NOT_ authorative, it could easily
            # have been tampered with.  Other checks will be done (below)
            # validate it's accuracy compared to trusted/imutable values.
            image_created = dateutil.parser.isoparse(image_created_value)
        except ValueError:
            dbg(f"Invalid label iso-8601 value: '{image_created_value}'")
            return "Unparsable org.opencontainers.image.created"

        gh_prefix = "https://github.com/"  # trailing slash is important
        git = ".git"
        repo = labels["org.opencontainers.image.source"]
        if not repo.startswith(gh_prefix) or not repo.endswith(git):
            dbg(f"Expecting repo. prefix '{gh_prefix}' and suffix '{git}'")
            return f"Unsupported repo '{repo}'"

    # When used with -m,--matching, since all labels also match (above),
    # there's no reason to check anything other than a single image vs Cirrus-CI API.
    if options["matching_digests"] and fqin_detail != fqin_details[0]:
        # Special case to avoid set_check_result() blowing up
        # due to result-overwrite protection.
        return NA_RESULT_SENTINEL

    if options["commit_override"] is not None:
        commit = options["commit_override"]
        dbg(f"Warning: Checking Cirrus-CI API using CLI overriden commit {commit}")
    else:
        try:
            commit = labels[OCI_REV_LABEL]
        except KeyError:
            return f"Missing '{OCI_REV_LABEL}'"

    if len(commit) < 40:
        # Warning: integration tests check this value
        return f"Bad CommitID '{commit}'"

    _tmp = Path(repo.removeprefix(gh_prefix).removesuffix(git))
    gh_owner = _tmp.parts[0]  # breaks if gh_prefix doesn't end with '/'
    gh_name = _tmp.parts[1]
    with cirrus_ci_api_client() as gqlclient:
        if not is_valid_cirrus_api_gh_repo(gqlclient, gh_owner, gh_name):
            return f"Cirrus-CI unsupported {repo}"

        build_ids = get_cirrus_builds(gqlclient, gh_owner, gh_name, commit)
        if not bool(build_ids):
            return "No Cirrus-CI Builds found"

        good_build_ids = cirrus_success_before(gqlclient, build_ids, image_created)
        if not bool(good_build_ids):
            return "No relevant Cirrus-CI builds found"

        tids_finished = get_cirrus_task_finish_times(gqlclient, good_build_ids, image_created)
        if not bool(tids_finished):
            return "No relevant tasks found"

        # Second tuple-item is the task ending timestamp
        tids_finished.sort(reverse=True, key=lambda t: t[1])
        (latest_tid, latest_ts) = tids_finished[0]  # Most recent entry

    cli_arg_time = options["cirrus_timestamp"]
    max_diff_min = options["max_cirrus_push_diff_min"]
    delta = abs(latest_ts - cli_arg_time)
    dbg(f"Comparing image-build task completion time {latest_ts.isoformat()} to --cirrus {cli_arg_time.isoformat()}")

    max_diff = timedelta(seconds=(max_diff_min / 2.0) * 60)
    if delta > max_diff:
        return f"Over +/-{max_diff.total_seconds()}s: {delta.total_seconds()}"

    return f"PASS  # Delta {delta.total_seconds()}s"


def run_checks(fqin_detail, fqin_details):
    """Execute each function from checks list against item in fqin_detail."""
    fqin = fqin_detail["fqin"]  # N/B: NOT authoritative FQIN, just for ref.
    for check_name, check_fn in checks:
        # Side-effect: Checks may update fqin_detail but treat fqin_details as read-only
        with indented_output(f"Executing '{check_name}' check on '{fqin}'"):
            result = check_fn(fqin_detail, fqin_details)
            set_check_result(fqin_detail, check_name, result)


def main(fqin_paths):
    """Sanity-check fqins, print their full names, then execute checks in order."""
    dbg(f"Received FQIN directories {fqin_paths}")
    fqin_details = []
    sanity_fault = False
    for fqin_path in fqin_paths:
        with indented_output(f"Sanity-checking FQIN path '{fqin_path}'"):
            details = sanity_check(fqin_path, fqin_details)
            fqin_details.append(details)
            if not details["results"].get("Sanity", "").startswith("PASS"):
                dbg(f"Sanity check failed for '{fqin_path}'")
                sanity_fault = True

    # No need to perform more detailed validation if any sanity_check() fails
    if sanity_fault:
        # Integration tests verify sanity-failures exit(9)
        exit_with_results(fqin_details, override_status=9)

    for fqin_detail in fqin_details:
        fqin = fqin_detail["fqin"]  # N/B: NOT authoritative FQIN, just for ref.
        with indented_output(f"Running checks on FQIN '{fqin}'"):
            run_checks(fqin_detail, fqin_details)

    exit_with_results(fqin_details)


def get_args(argv):
    """Return parsed argument namespace object."""
    # This makes for a really ugly description, but it's simple and prevents duplication.
    parser = ArgumentParser(description=sys.modules[__name__].__doc__)

    _mty = "(empty string disables)"

    max_cirrus_push_diff_min = options["max_cirrus_push_diff_min"]
    parser.add_argument(
        "-c",
        "--cirrus",
        dest="cirrus_timestamp",
        # Note: This is a sentinel value to indicate no option was specified
        # (check disabled)
        default=CIRRUS_DISABLED_SENTINEL,
        type=dateutil.parser.isoparse,
        metavar="<iso-8601>",
        help=(
            "Timestamps retrieved from Cirrus-CI API using <fqin_dir>'s"
            f" '{OCI_REV_LABEL}'"
            f" label, must match <iso-8601> within +/-{max_cirrus_push_diff_min} minutes. This check is"
            " skipped by default.  See also -d,--delta-minutes.  Use of -m,--matching highly recommended."
        ),
    )

    parser.add_argument(
        "--commit",
        dest="commit_override",
        default=None,
        type=str,
        metavar="<CommitID>",
        help=(
            f"When using -c,--cirrus ignore any {OCI_REV_LABEL} label in the manifest-list/image,"
            " and check the Cirrus-CI API with <CommitID> instead."
        ),
    )

    parser.add_argument(
        "-d",
        "--delta-minutes",
        dest="delta_minutes",
        default=max_cirrus_push_diff_min,
        metavar="<+/-min>",
        type=int,
        help=(
            "Intended to be used along with -c,--cirrus option. Allows changing the"
            " default delta WRT <fqin_dir>'s push-timestamp to something other than"
            f" +/-{max_cirrus_push_diff_min} minutes."
        ),
    )

    _tmp = ",".join(options["expected_labels"])
    parser.add_argument(
        "-l",
        "--labels",
        dest="expected_labels",
        default=_tmp,
        metavar="<label CSV>",
        type=str,
        help=(f"Required CSV list of labels for all <fqin_dir>'s {_mty}." f" Default: '{_tmp}'"),
    )

    parser.add_argument(
        "-m",
        "--matching",
        dest="matching_digests",
        default=False,
        action="store_true",
        help=(
            "Require all <fqin_dir>'s to have exactly matching manifest-list"
            " item digests (across os/platforms) and/or identical image layer"
            " digests. This check is disabled by default."
        ),
    )

    _tmp = ",".join(options["expected_platforms"])
    parser.add_argument(
        "-p",
        "--platforms",
        dest="expected_platforms",
        default=_tmp,
        metavar="<platform CSV>",
        type=str,
        help=(f"Required CSV list of <os>/<arch> platforms for all <fqin_dir>s" f" {_mty}.  Default: '{_tmp}'"),
    )

    _tmp = options["expected_registry"]
    parser.add_argument(
        "-r",
        "--registry",
        dest="expected_registry",
        default=_tmp,
        metavar="<registry>",
        type=str,
        help=(f"Expected registry for all <fqin_dir>s {_mty}. Default: '{_tmp}'"),
    )

    parser.add_argument(
        "-v",
        "--verbose",
        dest="verbose",
        action="store_true",
        default=False,
        help="Show internal debugging/processing details",
    )

    parser.add_argument(
        "fqin_paths",  # Path() type converts from "dir" (string) -> "Path" (object)
        nargs="+",
        default=None,
        type=Path,
        # Call this "dir" as reminder to user this is interpreted as a "dir:"
        # container-transport value.  Whereas "path" could be ambiguous.
        metavar="<fqin dir>",
        help=(
            "Relative or absolute path to directory containing manifest-list"
            " or image contents written using the 'dir:' containers-transports"
            " (man 5)."
        ),
    )
    return parser.parse_args(args=argv[1:])


if __name__ == "__main__":
    DEFAULT_OS, DEFAULT_ARCH = default_platform()

    # N/B: Every variable defined here is a global, be careful with naming.
    _args = get_args(sys.argv)
    options["verbose"] = _args.verbose
    _n_fqins = len(_args.fqin_paths)

    _expected_registry = _args.expected_registry.strip()
    if not bool(_expected_registry):
        _expected_registry = None
    options["expected_registry"] = _expected_registry

    _expected_platforms = set(_args.expected_platforms.strip().split(","))
    # argparse enforces a minimum of one argument
    if len(_expected_platforms) == 1 and list(_expected_platforms)[0].strip() == "":
        _expected_platforms = None
    options["expected_platforms"] = _expected_platforms

    if _args.matching_digests and _n_fqins == 1:
        # Careful, this message is checked by tests
        err("Matching (-m,--matching) option specified with only one <fqin_dir>")
    options["matching_digests"] = _args.matching_digests

    options["cirrus_timestamp"] = _args.cirrus_timestamp
    options["max_cirrus_push_diff_min"] = _args.delta_minutes

    _expected_labels = set(_args.expected_labels.strip().split(","))
    if len(_expected_labels) == 1 and list(_expected_labels)[0].strip() == "":
        _expected_labels = []
    # Related...
    if _args.commit_override is not None:
        if _args.cirrus_timestamp == CIRRUS_DISABLED_SENTINEL:
            err("Can only use --commit option along with -c,--cirrus option")
        dbg(f"Overriding Cirrus-API check to use commit {_args.commit_override}")
        options["commit_override"] = _args.commit_override

        # Don't bother label_check() with org.opencontainers.image.revision since it's
        # probably absent (the reason for having a --commit option).
        if OCI_REV_LABEL in _expected_labels:
            dbg(f"Warning: Removing {OCI_REV_LABEL} from list of required labels b/c --commit option is in use.")
            _expected_labels = _expected_labels - set([OCI_REV_LABEL])
    options["expected_labels"] = _expected_labels

    if _n_fqins > 9:
        msg(f"Processing {_n_fqins} items, this might take a while.", pfx="Warning: ", fd=sys.stderr)

    # TODO: Rather than a bunch of functions, it would be neat to load
    # from a set of files using a special naming format.
    checks = [
        ("Skopeo Inspect", skopeo_check),
        ("Manifest Consistency", manifest_check),
        ("Expected labels", labels_check),
        ("Expected platforms", platforms_check),
        (_matching_check_name, matching_check),
        ("Cirrus timestamp", cirrus_check),
    ]

    main(_args.fqin_paths)
