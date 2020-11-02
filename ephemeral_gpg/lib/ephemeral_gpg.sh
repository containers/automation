
# Library of constants and functions for the ephemeral_gpg scripts and tests
# Not intended to be executed directly.

LIBRARY_DIRPATH=$(dirname $(realpath "${BASH_SOURCE[0]}"))
source "$LIBRARY_DIRPATH/common.sh"

# Executing inside a container (TODO: not used)
EPHEMERAL_CONTAINER="${EPHEMERAL_CONTAINER:-0}"

# Path to script template rendered by configure_git_gpg()
GIT_UNATTENDED_GPG_TEMPLATE="$LIBRARY_DIRPATH/git_unattended_gpg.sh.in"

# In case a bash prompt is presented, identify the environment
EPHEMERAL_ENV_PROMPT_DIRTRIM=2
EPHEMERAL_ENV_PS1='\e[0m[\e[0;37;41mEPHEMERAL\e[0m \e[1;34m\w\e[0m]\e[1;36m\$\e[0m '

# If for some future/unknown reason, input keys and passphrase files
# should NOT be truncated after read, set these to 0.
TRUNCATE_KEY_ON_READ=1
TRUNCATE_PASSPHRASE_ON_READ=1

# Machine parse-able status will be written here
# Empty-files have special-meanings to gpg, detect them to help debugging
MIN_INPUT_FILE_SIZE=8  # bytes

# Ref: https://help.github.com/en/github/authenticating-to-github/about-commit-signature-verification
GH_PUB_KEY_ID="4AEE18F83AFDEB23"
# Don't rely on internet access to download the key
GH_PUB_KEY="-----BEGIN PGP PUBLIC KEY BLOCK-----

mQENBFmUaEEBCACzXTDt6ZnyaVtueZASBzgnAmK13q9Urgch+sKYeIhdymjuMQta
x15OklctmrZtqre5kwPUosG3/B2/ikuPYElcHgGPL4uL5Em6S5C/oozfkYzhwRrT
SQzvYjsE4I34To4UdE9KA97wrQjGoz2Bx72WDLyWwctD3DKQtYeHXswXXtXwKfjQ
7Fy4+Bf5IPh76dA8NJ6UtjjLIDlKqdxLW4atHe6xWFaJ+XdLUtsAroZcXBeWDCPa
buXCDscJcLJRKZVc62gOZXXtPfoHqvUPp3nuLA4YjH9bphbrMWMf810Wxz9JTd3v
yWgGqNY0zbBqeZoGv+TuExlRHT8ASGFS9SVDABEBAAG0NUdpdEh1YiAod2ViLWZs
b3cgY29tbWl0IHNpZ25pbmcpIDxub3JlcGx5QGdpdGh1Yi5jb20+iQEiBBMBCAAW
BQJZlGhBCRBK7hj4Ov3rIwIbAwIZAQAAmQEH/iATWFmi2oxlBh3wAsySNCNV4IPf
DDMeh6j80WT7cgoX7V7xqJOxrfrqPEthQ3hgHIm7b5MPQlUr2q+UPL22t/I+ESF6
9b0QWLFSMJbMSk+BXkvSjH9q8jAO0986/pShPV5DU2sMxnx4LfLfHNhTzjXKokws
+8ptJ8uhMNIDXfXuzkZHIxoXk3rNcjDN5c5X+sK8UBRH092BIJWCOfaQt7v7wig5
4Ra28pM9GbHKXVNxmdLpCFyzvyMuCmINYYADsC848QQFFwnd4EQnupo6QvhEVx1O
j7wDwvuH5dCrLuLwtwXaQh0onG4583p0LGms2Mf5F+Ick6o/4peOlBoZz48=
=Bvzs
-----END PGP PUBLIC KEY BLOCK-----
"

# E-mail addresses are complex to match perfectly, assume this is good enough
FULL_NAME_RX='^([[:graph:] ]+)+'  # e.x. First Middle-Initial. Last (Comment) <user@example.com>
EMAIL_RX='[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]+'
FULL_NAME_EMAIL_RX="${FULL_NAME_RX}\B<${EMAIL_RX}>"

# Intentionally blank, this is set by calling set_default_keyid()
_KEY_CACHE_FN=""
_DEF_KEY_ID=""
_DEF_KEY_ARG=""
_KEY_PASSPHRASE=""
_EPHEMERAL_ENV_EXIT=0

# Used by get_???_key_id functions
_KEY_COMMON_RX='u:[[:digit:]]+:[[:digit:]]+:[[:alnum:]]+:[[:digit:]]+:+u?:+'

# These variables either absolutely must not, or simply should not
# pass through to commands executed beneith the ephemeral environment
_UNSET_VARS=( \
    EMAIL_RX
    EPHEMERAL_ENV_PROMPT_DIRTRIM
    FULL_NAME_EMAIL_RX
    FULL_NAME_RX
    GH_PUB_KEY
    GH_PUB_KEY_ID
    MKTEMP_FORMAT
    PRIVATE_KEY_FILEPATH
    PRIVATE_PASSPHRASE_FILEPATH
    TRUNCATE_KEY_ON_READ
    TRUNCATE_PASSPHRASE_ON_READ
    _BOOKENDS_ESCAPED_SED_EXP
    _BOOKENDS_SED_EXP
    _DEF_KEY_ID
    _EPHEMERAL_ENV_EXIT
    _KEY_COMMON_RX
    _KEY_PASSPHRASE
    _UNSET_VARS
)

verify_env_vars() {
    local env_var_name
    for kind in KEY PASSPHRASE; do
        case "$kind" in
            KEY)
                env_var_name=PRIVATE_KEY_FILEPATH
                trunc_var_name=TRUNCATE_KEY_ON_READ
                ;;
            PASSPHRASE)
                env_var_name=PRIVATE_PASSPHRASE_FILEPATH
                trunc_var_name=TRUNCATE_PASSPHRASE_ON_READ
                ;;
            *)
                die "Unsupported/Unknown \$kind '$kind'."
        esac

        dbg "Checking \$${env_var_name} '${!env_var_name}':"
        dbg $(ls -la "${!env_var_name}" || true)

        [[ -n "${!env_var_name}" ]] || \
            die "Expecting \$$env_var_name to not be empty/blank" 2

        [[ -f "${!env_var_name}" ]] || \
            die "Expecting readable \$$env_var_name file, got '${!env_var_name}'" 2

        # The '-w' test always passes for root, must look at actual permissions
        dbg "Found \$$trunc_var_name '${!trunc_var_name}'"
        if [[ ${!trunc_var_name} -ne 0 ]] && stat --format=%A "${!env_var_name}" | egrep -qv '^-rw'; then
            die "The file referenced in \$$env_var_name must be writable if \$$trunc_var_name is '${!trunc_var_name}'"
        else
            dbg "The file "${!env_var_name}" is writeable)"
        fi

        if (($(stat "--format=%s" "${!env_var_name}")<$MIN_INPUT_FILE_SIZE)); then
            die "The file '${!env_var_name}' must be larger than $MIN_INPUT_FILE_SIZE bytes."
        fi

        dbg "\$${env_var_name} appears fine for use."
    done
}

# Setup environment required for non-interactive secure use of gpg_cmd()
go_ephemeral() {
    # Security-note: This is not perfectly safe, and it can't be in any practical way
    # with a shell-script.  It simply ensures the key is only exposed in memory of the
    # this shell process and not stored on disk in an otherwise known/discoverable location.
    _KEY_PASSPHRASE="$(<$PRIVATE_PASSPHRASE_FILEPATH)"
    if ((TRUNCATE_PASSPHRASE_ON_READ)); then
        truncate --size=0 "$PRIVATE_PASSPHRASE_FILEPATH"
    fi

    export GNUPGHOME=$(mktemp -p '' -d $MKTEMP_FORMAT)
    chmod 0700 "$GNUPGHOME"
    dbg "Created '$GNUPGHOME' as \$GNUPGHOME, will be removed upon exit."
    trap "rm -rf $GNUPGHOME" EXIT
    dbg "Using \$GNUPGHOME $GNUPGHOME"

    # Needed for error-checking and KEY ID caching
    export GPG_STATUS_FILEPATH=$GNUPGHOME/gpg.status
    # Must use a file not a variable for this, unit-tests execute in a subshell and a var would not persist.
    _KEY_CACHE_FN=$GNUPGHOME/.keycache
    touch "$_KEY_CACHE_FN"
    touch "$GPG_STATUS_FILEPATH"

    # Don't allow any default pass-through env. vars to leak from outside environment
    local default_env_vars=$(gpg-connect-agent --quiet 'getinfo std_env_names' /bye | \
                             tr -d '\000' | awk --sandbox '$1=="D" {print $2}' | \
                             egrep -iv 'term')
    dbg "Force-clearing "$default_env_vars
    unset $default_env_vars

    # gpg_cmd() checks for this to indicate function was called at least once
    touch "$GNUPGHOME/.ephemeral"
}

# Execute arguments in a sanitized environment
ephemeral_env() {
    local args="$@"
    # quoted @ is special-case substitution
    dbg "Entering ephemeral environment for command execution: '$args'"
    local gpg_key_uid="$(get_key_uid $_DEF_KEY_ID)"
    local unsets=$(for us in "${_UNSET_VARS[@]}"; do echo "--unset=$us"; done)
    cd $GNUPGHOME
    env ${unsets[@]} \
        DEBUG="$DEBUG" \
        TEST_DEBUG="$TEST_DEBUG" \
        PROMPT_DIRTRIM="$EPHEMERAL_ENV_PROMPT_DIRTRIM" \
        GNUPGHOME="$GNUPGHOME" \
        HOME="$GNUPGHOME" \
        GPG_KEY_ID="$_DEF_KEY_ID" \
        GPG_KEY_UID="$gpg_key_uid" \
        GPG_TTY="$(tty)" \
        HISTFILE="$HISTFILE" \
        HOME="$GNUPGHOME" \
        PS1="$EPHEMERAL_ENV_PS1" \
        "$@" || _EPHEMERAL_ENV_EXIT=$?
    cd - &> /dev/null
    dbg "Leaving ephemeral environment after command exit '$_EPHEMERAL_ENV_EXIT'"
    return $_EPHEMERAL_ENV_EXIT
}

# Snag key IDs and hashes from common operations, assuming reverse order relevancy
# N/B: NO error checking or validation is performed
cache_status_key() {
    [[ -r "$_KEY_CACHE_FN" ]] || \
        die "Expecting prior call to go_ephemeral() function"
    local awk_script='
        / ERROR /{exit}
        / KEY_CREATED /{print $4; exit}
        / KEY_CONSIDERED /{print $3; exit}
        / EXPORTED /{print $3; exit}
        / IMPORT_OK /{print $4; exit}
    '
    local cache="$(tac $GPG_STATUS_FILEPATH | awk -e "$awk_script")"
    if [[ -n "$cache" ]]; then
        dbg "Caching '$cache' in '$_KEY_CACHE_FN'"
        echo -n "$cache" > "$_KEY_CACHE_FN"
    else
        dbg "Clearing cache in '$_KEY_CACHE_FN'"
        truncate --size 0 "$_KEY_CACHE_FN"
    fi
}

print_cached_key() {
    [[ -r "$_KEY_CACHE_FN" ]] || \
        die "Expecting prior call to go_ephemeral() function"
    local cache=$(<"$_KEY_CACHE_FN")
    if [[ -n "$cache" ]]; then
        dbg "Found cached key '$cache'"
        echo "$cache" > /dev/stdout
    else
        # Be helpful to callers with a warning, assume they were not expecting the cache to be empty/cleared.
        warn "Empty key cache '$_KEY_CACHE_FN' encountered in call from ${BASH_SOURCE[2]}:${BASH_LINENO[1]}"
    fi
}

# Execute gpg batch command with secure passphrase
# N/B: DOES NOT die() ON ERROR, CALLER MUST CHECK RETURN STATUS FILE
gpg_cmd() {
    args="$@"
    [[ -n "$args" ]] || \
        die "Expecting one or more gpg arguments as function parameters"
    [[ -r "$GNUPGHOME/.ephemeral" ]] || \
        die "The go_ephemeral() function must be used before calling ${FUNCNAME[0]}()"
    [[ ${#_KEY_PASSPHRASE} -gt $MIN_INPUT_FILE_SIZE ]] || \
        die "Bug: Passphrase not found in \$_KEY_PASSPHRASE"
    local harmless_warning_rx='^gpg: WARNING: standard input reopened.*'
    local future_algo="ed25519/cert,sign+cv25519/encr"
    local cmd="gpg --quiet --batch --with-colons \
        --status-file $GPG_STATUS_FILEPATH \
        --pinentry-mode loopback --passphrase-fd 42 \
        --trust-model tofu+pgp --tofu-default-policy good \
        --default-new-key-algo $future_algo \
        $_DEF_KEY_ARG --keyid-format LONG"
    dbg "Resetting status file $GNUPGHOME/gpg.status contents"
    dbg "+ $cmd $@"
    # Execute gpg command, but filter harmless/annoying warning message for testing consistency
    $ephemeral_env $cmd "$@" 42<<<"$_KEY_PASSPHRASE" |& \
        sed -r -e "s/$harmless_warning_rx//g" || true
    dbg "gpg command exited $?"
    dbg "gpg status after command:
$(<$GPG_STATUS_FILEPATH)
"
    cache_status_key
}

# Exit with an error if gpg_cmd() call indicates an error in the status file
gpg_status_error_die() {
    local last_status=$(tail -1 "$GPG_STATUS_FILEPATH")
    if egrep -i -q 'ERROR' "$GPG_STATUS_FILEPATH"; then
        die "gpg ERROR status found:
$last_status
"
    fi
}

_verify_key_exists() {
    local keyid="$1"
    [[ -n "$keyid" ]] || \
        die "Expecting a key-id as the first parameter"
    local output=$(gpg_cmd --list-keys "$keyid" 2>&1)
    if egrep -i -q 'error reading key' <<<"$output"; then
        die "Non-existing key '$keyid'; gpg output:
$output"
    else
        gpg_status_error_die
    fi
}

# Github signs merge commits using this key, trust it to keep git happy
trust_github() {
    dbg "Importing Github's merge-commit signing key"
    gpg_cmd --import <<<"$GH_PUB_KEY"
    gpg_status_error_die
    _verify_key_exists "$GH_PUB_KEY_ID"
}

set_default_keyid() {
    local keyid="$1"
    _verify_key_exists $keyid
    dbg "Setting default GPG key to ID $keyid"
    _DEF_KEY_ID="$keyid"
    _DEF_KEY_ARG="--default-key $keyid"
}

_get_sec_key_id() {
    local keyid="$1"
    local line_re="$2"
    _verify_key_exists $keyid
    # Double --with-fingerprint is intentional
    listing=$(gpg_cmd --fixed-list-mode --with-fingerprint --with-fingerprint --list-secret-keys $keyid)
    gpg_status_error_die
    dbg "Searching for key matching regex '$line_re'"
    awk --field-separator ':' --sandbox -e "/$line_re/"'{print $5}' <<<"$listing"
}

# Usage-note: The purpose-build sub-keys are preferred to using the main key,
#             since they are more easily replaced.  This one is not that, it is
#             simply the ID of the secret part of the primary key (i.e. probably
#             not what you want to be using on a regular basis).
get_sec_key_id() {
    # Format Ref: /usr/share/doc/gnupg2/DETAILS (field 5 is the key ID)
    # N/B: The 'scESCA' (in any order) near the end is REALLY important, esp. to verify does not have a 'd'
    _get_sec_key_id "$1" "^sec:${_KEY_COMMON_RX}:[scESCA]+:"
}

get_enc_key_id() {
    _get_sec_key_id "$1" "^ssb:${_KEY_COMMON_RX}:e:"
}

get_sig_key_id() {
    _get_sec_key_id "$1" "^ssb:${_KEY_COMMON_RX}:s:"
}

get_auth_key_id() {
    _get_sec_key_id "$1" "^ssb:${_KEY_COMMON_RX}:a:"
}

get_key_uid() {
    local keyid="$1"
    _verify_key_exists $keyid
    # Added keys appear in reverse-chronological order, search oldest-first.
    local keys=$(gpg_cmd --fixed-list-mode --with-fingerprint --with-fingerprint --list-keys $keyid | tac)
    gpg_status_error_die
    dbg "Searching for UID subkey in $keyid:"
    dbg "
$keys
"
    local uid_string
    # Format Ref: /usr/share/doc/gnupg2/DETAILS (field 10 is the UID string)
    awk --field-separator ':' --sandbox -e '/uid/{print $10}' <<<"$keys" | \
        while read uid_string; do
            dbg "Considering '$uid_string'"
            if egrep -Eioqm1 "${FULL_NAME_EMAIL_RX}" <<<"$uid_string"; then
                dbg "It matches regex!"
                echo "$uid_string"
                break
            fi
        done
}

git_config_ephemeral() {
    local args="$@"
    [[ -n "$args" ]] || \
        die "Expecting git config arguments as parameters"
    # Be nice to developers, don't trash their configuration and
    # also avoid interfering with other system/user configuration
    dbg "Configuring '$args' in \$GNUPGHOME/gitconfig"
    git config --file $GNUPGHOME/gitconfig "$@"
}

configure_git_gpg() {
    local optional_keyid="$1"  # needed for unit-testing
    [[ -z "$optional_keyid" ]] ||
        set_default_keyid "$optional_keyid"
    # Required for obtaining the UID info and the sig subkey
    [[ -n "$_DEF_KEY_ID" ]] || \
        die "No default key has been set, call set_default_keyid() <ID> first."
    [[ -r "$GIT_UNATTENDED_GPG_TEMPLATE" ]] || \
        die "Could not read template file '$GIT_UNATTENDED_GPG_TEMPLATE'"
    local uid_string=$(get_key_uid "$_DEF_KEY_ID")
    [[ -n "$uid_string" ]] || \
        die "Expected non-empty uid string using the format:: <full name> <'<'e-mail address'>'>"
    local email=$(egrep -Eiom1 "$EMAIL_RX" <<<$uid_string)
    local full_name=$(egrep -Eiom1 "$FULL_NAME_RX" <<<$uid_string | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')

    dbg "Parsed uid record string into '$full_name' first/last and '$email' email"
    git_config_ephemeral user.name "$full_name"
    git_config_ephemeral user.email "$email"
    git_config_ephemeral user.signingkey $(get_sig_key_id $_DEF_KEY_ID)
    git_config_ephemeral commit.gpgsign true
    git_config_ephemeral tag.gpgSign true
    git_config_ephemeral log.showSignature true
    # Make active for general use, assuming they have \$HOME set properly
    ln -sf $GNUPGHOME/gitconfig $GNUPGHOME/.gitconfig

    # Necessary so git doesn't prompt for passwords
    local unattended_script=$(mktemp -p "$GNUPGHOME" ....XXXX)
    dbg "Rendering unattended gpg passphrase supply script '$unattended_script'"
    # Security note: Any git commands will async. call into gpg, possibly
    # in the future.  Therefor we must provide the passphrase for git's use,
    # otherwise an interaction would be required.  Relying on the
    # random script filename and a kernel session keyring with an
    # obfuscated base64 encoded passphrase is about as good as can be had.
    local _shit=$'#\a#\a#\a#\a#\a#'
    local _obfsctd_b64_kp=$(printf '%q' "$_shit")$(base64 -w0 <<<"$_KEY_PASSPHRASE")$(printf '%q' "$_shit")
    sed -r -e "s/@@@@@ SUBSTITUTION TOKEN @@@@@/${_obfsctd_b64_kp}/" \
        "$GIT_UNATTENDED_GPG_TEMPLATE" > "$unattended_script"
    chmod 0700 "$unattended_script"
    git_config_ephemeral gpg.program "$unattended_script"
}
