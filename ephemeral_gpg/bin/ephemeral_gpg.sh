#!/bin/bash

set -eo pipefail

# Execute gpg with an ephemeral home-directory and externally supplied
# key details.  This is intended to protect sensitive bits by avoiding
# persisting any runtime daemons/background processes or temporary files.
# Allowing gpg and/or git commands to be executed inside a volume-mounted
# workdir using a consistent and repeatable environment.
#
# Ref: https://www.gnupg.org/documentation//manuals/gnupg/Unattended-Usage-of-GPG.html#Unattended-Usage-of-GPG

source $(dirname $(realpath "${BASH_SOURCE[0]}"))/../lib/$(basename "${BASH_SOURCE[0]}")

# Documented/intended normal behavior to protect keys at rest
safe_keyfile() {
    # Validated by verify_env_vars()
    if ((TRUNCATE_KEY_ON_READ)); then
        dbg "Truncating \$PRIVATE_KEY_FILEPATH useless after import."
        truncate --size=0 "$PRIVATE_KEY_FILEPATH"
    fi
}

# Scan file, extract FIRST ascii-armor encoded private-key ONLY
first_private_key() {
    file="$1"
    [[ -n "$file" ]] || \
        die "Expecting path to file as first argument"
    dbg "Importing the first private-key encountered in '$file'"
    awk -r -e '
        BEGIN {
            got_start=0;
            got_end=0;
        }
        /-----BEGIN.+PRIVATE/ {
            if (got_end == 1) exit 1;
            got_start=1;
        }
        /-----END.+PRIVATE/ {
            if (got_start == 0) exit 2;
            got_end=1;
            print $0;
        }
        {
            if (got_start == 1 && got_end == 0) print $0; else next;
        }
    ' "$file"
}

##### MAIN() #####

dbg "Validating required environment variables and values"
verify_env_vars
dbg "Entering ephemeral environment"
# Create a $GNUPGHOME and arrange for it's destruction upon exit
go_ephemeral

# The incoming key file may have an arbitrary number of public
# and private keys, in an arbitrary order.  For configuration
# and trust purposes, we must obtain exactly one primary secret
# key's ID.  While we're at it, import and clean/fix the key
# into a new keyring.
first_private_key "$PRIVATE_KEY_FILEPATH" | \
    gpg_cmd --import --import-options import-local-sigs,no-import-clean,import-restore
gpg_status_error_die

# Grab reference to the ID of the primary secret key imported above
GPG_KEY_ID=$(print_cached_key)

# For all future gpg commands, reference this key as the default
set_default_keyid $GPG_KEY_ID

# Imported keys have an 'untrusted' attribute assigned by default
dbg "Marking imported private-key as ultimately trusted and valid"
# Under non-debugging situations ignore all the output
dbg $(gpg_cmd --command-fd 0 --edit-key "$GPG_KEY_ID" <<<"
trust
5
y
enable
save
")
# Exit if there was any error
gpg_status_error_die

dbg "Importing remaining keys in \$PRIVATE_KEY_FILEPATH '$PRIVATE_KEY_FILEPATH'"
# Don't clobber the alrady imported and trusted primary key "$GPG_KEY_ID
gpg_cmd --import --import-options keep-ownertrust,import-clean <"$PRIVATE_KEY_FILEPATH"
gpg_status_error_die
# Assume it is desireable to protect data-at-rest as much as possible
safe_keyfile

# This allows validating any appearance of this key in the commit log
dbg "Importing and trusting Github's merge-commit signing key"
trust_github
dbg "Configuring unattended gpg use by git"
configure_git_gpg

# Execute the desired command/arguments from the command-line, inside prepared environment
ephemeral_env "$@"
exit $?
