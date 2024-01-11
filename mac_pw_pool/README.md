# Cirrus-CI persistent worker maintenance

These docs and scripts were implemented in a hurry.  They both likely
contain cringe-worthy content and incomplete information.
This might be improved in the future.  Sorry.

## Prerequisites

* The `aws` binary present somewhere on `$PATH`.
* Standard AWS `credentials` and `config` files exist under `~/.aws`
  and set the region to `us-east-1`.
* A copy of the ssh-key referenced by `CirrusMacM1PWinstance` launch template
  under "Assumptions" below.
* The ssh-key has been added to a running ssh-agent.
* The env. var. `POOLTOKEN` is set to the Cirrus-CI persistent worker pool
  token value.

## Assumptions

* You've read all scripts in this directory and meet any requirements
  stated within.
* You have permissions to access all referenced AWS resources.
* There are one or more dedicated hosts allocated and have set:
  * A name tag like `MacM1-<some number>`
  * The `mac2` instance family
  * The `mac2.metal` instance type
  * Disabled "Instance auto-placement", "Host recovery", and "Host maintenance"
  * Quantity: 1
  * Tags: `automation=false` and `PWPoolReady=true`
* The EC2 `CirrusMacM1PWinstance` instance-template exists and sets:
  * Shutdown-behavior: terminate
  * Same "key pair" referenced under `Prerequisites`
  * All other required instance parameters complete
  * A user-data script that shuts down the instance after 2 days.

## Operation (Theory)

The goal is to maintain sufficient alive/running/working instances
to service most Cirrus-CI tasks pointing at the pool.  This is
best achieved with slower maintenance of hosts compared to setup
of ready instances.  This is because hosts can be inaccessible for
1-1/2 hours, but instances come up in ~10-20m, ready to run tasks.

Either hosts and/or instances may be removed from management by
setting "false" or removing their `PWPoolReady=true` tag.  Otherwise,
the pool should be maintained by installing the crontab lines
indicated in the `Cron.sh` script.

Cirrus-CI will assign tasks (specially) targeted at the pool, to an
instance with a running listener.  If there are none, the task will
queue forever (there might be a 24-hour timeout, I can't remember).
From a PR perspective, there is zero control over which instance you
get.  It could easily be one somebody's previous task barfed all over
and ruined.

## Initialization

When no dedicated hosts have instances running, complete creation and
setup will take many hours.  This may be bypassed by *manually* running
`LaunchInstances.sh --force`.  This should be done prior to installing
the `Cron.sh` cron-job.

In order to prevent all the instances from being recycled at the same
(future) time, the shutdown time installed by `SetupInstances.sh` also
needs to be adjusted.  The operator should first wait about 20 minutes
for all new instances to fully boot.  Followed by a call to
`SetupInstances.sh --force`.

Now the `Cron.sh` cron-job may be installed, enabled and started.

## Manual Testing

Verifying changes to these scripts / cron-job must be done manually.
To support this, every dedicated host has a `purpose` tag set, which
must correspond to the value indicated in `pw_lib.sh`.  To test script
changes, first create one or more dedicated hosts with a unique `purpose`
tag (like "cevich-testing").  Then temporarily update `pw_lib.sh` to use
that value.

***Importantly***, if running test tasks against the test workers,
ensure you also customize the `purpose` label in the `cirrus.yml` task(s).
Without this, production tasks will get scheduled on your testing instances.
Just be sure to revert all the `purpose` values back to `prod`
(and destroy related dedicated hosts) before any PRs get merged.

## Security

To thwart attempts to hijack or use instances for nefarious purposes,
each employs three separate self-termination mechanisms.  Two of them
depend on the instance's shutdown behavior being set to `terminate`
(see above).  These mechanisms also ensure the workers remain relatively
"clean" an "fresh" from a "CI-Working" perspective.

Note: Should there be an in-flight CI task on a worker at
shutdown, Cirrus-CI will perform a single automatic re-run on an
available worker.

1. Daily, a Cirrus-cron job runs and kills any instance running longer
   than 3 days.
2. Each instance's startup script runs a background 2-day sleep and
   shutdown command (via MacOS-init consuming instance user-data).
3. A setup script run on each instance starts a pool-listener
   process.
   1. If the worker process dies the instance shuts down.
   2. After 24 +/-4 hours the instance shuts down if there are no
      cirrus-agent processes (presumably servicing a CI task).
   3. After 2 more hours, the instance shuts down regardless of any
      running agents - probably hung/stuck agent process or somebody's
      started a fake agent doing "bad things".
