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
1-1/2 hours, but instances come up in ~10-20m, ready for setup.

Both hosts and instances may be taken out of all management loops
by setting or removing its `PWPoolReady=true` tag.  Otherwise,
with a fully populated set of dedicated hosts and running instances,
state should be maintained using two loops:

1. `while ./LaunchInstances.sh; do echo "Sleeping..."; sleep 10m; done`
2. `while ./SetupInstances.sh; do echo "Sleeping..."; sleep 2m; done`

Cirrus-CI will assign tasks (specially) targeted at the pool, to an
instance with a running listener.  If there are none, the task will
queue forever (there might be a 24-hour timeout, I can't remember).
From a PR perspective, there is zero control over which instance you
get.  It could easily be one somebody's previous task barfed all over
and ruined.

## Initialization

When no dedicated hosts have instances running, complete creation and
setup will take many hours.  This may be bypassed by *manually* running
`LaunchInstances.sh --force`.  The operator should then wait 20minutes
before *manually* running `SetupInstances.sh --force`.  This delay
is necessary to account for the time a Mac instance takes to boot and
become ssh-able.

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
