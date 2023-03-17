#!/usr/bin/env python3

"""
Digest `benchmarks.env` and `benchmarks.csv`, uploads to google firestore.

Expects to be called with $GOOGLE_APPLICATION_CREDENTIALS env. var. value
pointing at a JSON service account key file, with access to write firestore
data.
"""

import csv
import datetime
import os
import sys
from argparse import ArgumentParser
from math import ceil
from pathlib import Path
from pprint import pformat

# Ref: https://pypi.org/project/binary/
from binary import BinaryUnits, DecimalUnits, convert_units

# Ref: https://github.com/rconradharris/envparse
from envparse import env

# Ref: https://cloud.google.com/firestore/docs/create-database-server-client-library
from google.cloud import firestore

# Set True when --verbose flag is set
VERBOSE = False

# Set True when --dry-run flag is set
DRYRUN = False


def v(msg):
    """Print a helpful msg when the global VERBOSE is set true."""
    if VERBOSE:
        print(msg)


def die(msg, code=1):
    """Print an error message to stderr, then exit with code."""
    sys.stderr.write(f"ERROR: {msg}\n")
    sys.exit(code)


# Ref: https://docs.python.org/3.10/library/argparse.html
def get_args(argv):
    """Return parsed argument namespace object."""
    parser = ArgumentParser(prog="bench_stuff", description=__doc__)
    parser.add_argument('-v', '--verbose',
                        dest='verbose', action='store_true', default=False,
                        help='Show internal state/status while processing input/output.')
    parser.add_argument('-d', '--dry-run',
                        dest='dryrun', action='store_true', default=False,
                        help="Process benchmark data but don't try to store anything.")
    parser.add_argument('bench_dir', metavar='<benchmarks dirpath>', type=Path,
                        help=("Path to subdirectory containing benchmarks.env"
                              " and benchmarks.csv files."))
    parsed = parser.parse_args(args=argv[1:])

    # Ref: https://docs.python.org/3.10/library/pathlib.html#operators
    env_path = parsed.bench_dir / "benchmarks.env"
    csv_path = parsed.bench_dir / "benchmarks.csv"
    f_err_fmt = "Expecting a path to a directory containing an {0} file, got '{1}' instead."
    for file_path in (env_path, csv_path):
        if not file_path.exists() or not file_path.is_file():
            parser.error(f_err_fmt.format(file_path.name, str(file_path.parent)))

    gac = os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if gac is None or gac.strip() == "":
        parser.error("Expecting $GOOGLE_APPLICATION_CREDENTIALS to be defined/non-empty")
    # Google's firestore module will ultimately consume this, do some
    # basic checks up-front to provide a quick error message if possible.
    gac_path = Path(gac)
    if not gac_path.exists() or not gac_path.is_file():
        parser.error(f"Expecting $GOOGLE_APPLICATION_CREDENTIALS value '{gac_path}'"
                     f" to be an existing file.")

    return (parsed.verbose, parsed.dryrun, env_path, csv_path)


def handle_units(row):
    """
    Convert each element of row dict into floating-point or decimal units.

    The end-goal is to do calculations from on this data and present it
    to humans.  Converting all units into fundimental / numeric values before
    storage scales much better than burdening a script during final
    human-presentation step where it may need to traverse hundreds of records.
    """
    result = {}
    for key, value in row.items():
        value = value.upper()
        if value.endswith('S'):
            result[key] = float(value.rstrip(' S'))
        elif value.endswith('%'):
            result[key] = float(value.rstrip(' %'))
        elif value.endswith('KB'):
            raw = float(value.strip(' KB'))
            # First element is value, second is unit-string. Only numeric value is needed
            float_bytes = convert_units(raw, BinaryUnits.KB, DecimalUnits.B)[0]
            # Don't try to store partial-bytes, always round-up.
            result[key] = int(ceil(float_bytes))
        elif value.endswith('MB'):
            raw = float(value.strip(' MB'))
            float_bytes = convert_units(raw, BinaryUnits.MB, DecimalUnits.B)[0]
            result[key] = int(ceil(float_bytes))
        else:
            # Don't store "bad" data in database, bail out so somebody can fix this script.
            die(f"Can't parse units from '{key}' value '{value}'", code=3)
    return result


def insert_data(bench_basis, meta_data, bench_data):
    """Store bench_data and meta_data in an orderly-fashion wthin GCP firestore."""
    db = firestore.Client()
    batch = db.batch()  # Ensure data addition happens atomicly
    # Categorize all benchmarks based on the instance-type they ran on.
    doc_ref = db.collection('benchmarks').document(bench_basis['arch'])
    # Sub-collections must be anchored by a document, include all benchmark basis-details.
    batch.set(doc_ref, bench_basis, merge=True)  # Document likely to already exist
    v(f"Reticulating {bench_basis['arch']} document for task {meta_data['task']}")
    # Data points and metadata stored in a sub-collection of basis-document
    data_ref = doc_ref.collection('tasks').document(str(meta_data['task']))
    # Having meta-data at the top-level of the document makes indexing/querying simpler
    item = meta_data.copy()
    item["point"] = bench_data
    batch.set(data_ref, item)
    batch.commit()
    v("Data point and environment details commited to database")


def main(env_path, csv_path):
    """Load environment basis, load and convert csv data into a nosql database."""
    v(f"Loading environment '{env_path}' and benchmarks '{csv_path}'")
    env.read_envfile(env_path)

    if env.int('BENCH_ENV_VER') != 1:
        die("Only version 1 of $BENCH_ENV_VER is supported")

    bench_basis = {
        'cpu': env.int('CPUTOTAL'),
        # First element is value, second is unit-string. Only numeric value is needed
        'mem': int(ceil(convert_units(env.int('MEMTOTALKB'), BinaryUnits.KB, DecimalUnits.B)[0])),
        'arch': env.str('UNAME_M'),
        'type': env.str('INST_TYPE'),
    }
    v(f"Processing Basis: {pformat(bench_basis)}")

    meta_data = {
        'ver': 3,  # identifies this schema version, increment for major layout changes.
        'occasion': datetime.datetime.utcnow(),
        # Firestore can delete old data automatically based on a field value.
        'expires': datetime.datetime.utcnow() + datetime.timedelta(days=180),
        'build': env.int('CIRRUS_BUILD_ID'),
        'task': env.int('CIRRUS_TASK_ID'),  # collection-key
        # Will be pull/# for PRs; branch-name for branches
        'branch': env.str('CIRRUS_BRANCH'),
        'dist': env.str('DISTRO_NV'),
        'kern': env.str('UNAME_R'),
        'commit': env.str('CIRRUS_CHANGE_IN_REPO')
    }
    bench_data = {}

    test_names = []
    with open(csv_path) as csv_file:
        reader = csv.DictReader(csv_file, dialect='unix', skipinitialspace=True)
        for row in reader:
            test_name = row.pop("Test Name")
            bench_data[test_name] = handle_units(row)
            test_names.append(test_name)
    v(f"Loaded Data for tests: {pformat(test_names)}")

    msg = f"benchmark data for {bench_basis['arch'] } task {meta_data['task']}"
    if not DRYRUN:
        insert_data(bench_basis, meta_data, bench_data)
        print(f"Inserted {msg}")
    else:
        print(f"Did NOT insert {msg}")


if __name__ == "__main__":
    args = get_args(sys.argv)
    if args[0]:
        VERBOSE = True
        v("Verbose-mode enabled")
    if args[1]:
        DRYRUN = True
        v("Dry-run: Will not send data to firestore")
    main(*args[2:])
