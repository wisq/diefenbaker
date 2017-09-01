# Example runit setup

As an example, here's the contents of my `/etc/sv/dief-ups/run` file:

```
#!/bin/sh

exec 2>&1
exec chpst -u dief -- sh ./launch.sh
```

This first redirects standard error to standard output (important for `runit` scripts), then switches to the `dief` user and runs the `launch.sh` script.

Here's the contents of that `launch.sh` file:

```
#!/bin/sh

set -e -x
sleep 20
cd /home/dief/diefenbaker
bundle check || bundle install
exec bundle exec ruby bin/ups.rb ups1 ups2 ups3
```

This turns on shell error handling and verbosity, sleeps for twenty seconds between runs, changes directory, installs gems if needed, and then runs the `ups.rb` script.

## Logging

I also have a `/etc/sv/dief-ups/log/main` directory.  This is where the logs will go.  (You can also put them somewhere under `/var/log` or `/var/local/log` if you prefer.  Or anywhere, really.)

Then, I have a `/etc/sv/dief-ups/log/run` file:

```
#!/bin/sh

exec svlogd -tt ./main
```

This script accepts log input on standard input, and writes it out to files in the `main` directory.  When one file fills up, it rotates it and starts a new one.  When there's too many rotated files, it deletes the oldest.

As such, no matter how much output we have, there's never any risk of the disk filling up, and I don't have to set up any `logrotate` configuration for it.

## Moar monitoring!

If I want to run other checks as well, I create more `/etc/sv/dief-*` services that each run one service only.

Alternatively, you can set up your `launch.sh` script to run more than one check script per invocation.  However, this runs the risk of one check failing or stalling and blocking all the others, instead of just itself.  Up to you.

## Important notes

* If you're doing `bundle install` in your `runit` service like I am, make sure that **only one service** is doing it.
  * Otherwise, they may run at the same time and stomp on each other.
* Put your `sleep` statement **before** the actual service script, not after.
  * This ensures that, even if the script fails for some reason, you always put a pause between runs — and thus avoid slamming the server with repeated failed runs.
  * Also, it lets you do `exec` at your last action, which helps with memory efficiency and process control.
