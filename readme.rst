Idled
==============================================================================

This daemon detects keypresses or mice movements.  The user can be
anywhere: virtual terminals outside of X, terminals in X or in Wayland.
All mice movements are known, including gpm.  **idled** uses a heuristic
match of udev symlink names in `/sys/` to determine the keyboard and
mouse devices to monitor.  It handles added/removed devices by
rescanning from start.

Right now, this is used only to tell if you're at the keyboard or not,
and generate afk/back output messages and/or logfile.  There is a state
machine with crude heuristics to determine when you are idle, back, etc.

Idle state could inform other things.  The plan is to implement
configurable scripts / shell commands that will trigger on state
changes.

Lots of integration possibilities with the window manager and time
tracking tools.

| scott@smemsh.net
| https://github.com/smemsh/idled/
| https://spdx.org/licenses/GPL-2.0

____

.. contents::

____


Configure
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The config file ``~/.idlerc`` configures ``idled``::

  unidle_keyboard_count: 3
  unidle_keyboard_secs: 10
  unidle_mouse_count: 60
  unidle_mouse_secs: 7
  idle_secs: 30
  restart_secs: 3
  rescan_secs: 2

In the future we will add variables to configure ``execve()`` on idle
events.

*TODO* detail those variables!


Rescan
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

When devices are added and removed, **idled** currently rescans devices,
resetting the global idle state machine.  We could keep a per-device
state in the future and use them to infer the global idle state.


Overhead
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

The overhead is very low.  It uses an edge triggered kernel event.
**TODO confirm.**  Specifically, it uses epoll(7) and inotify(7)
mechanisms via ctypes-linked C code (via pypi inotify library at the
moment).


Inotify
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

Requires: inotify-0.2.10+ | https://pypi.org/project/inotify/

We use inotify lib from pypi, but what we use from it is small and we
should just port this into idled.  We have to go through unnecessary
abstractions and have limitation on sleep time per loop when using the
library library.  Better to do ourselves.


Run
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

example debug run::

  $ DEBUG=1 sudo idled
 debug: enabled
 > /home/scott/bin/idled(519)main()
 -> process_rcfile()
 (Pdb) r
 debug: making async task process_events-8154414866282
 debug: making async task watch_devices-8154414866292
 20241030200522 2s device enumeration sleep...
 debug: paths
 ['/dev/input/by-path/pci-0000:00:14.0-usb-0:4.2:1.1-event-kbd',
  '/dev/input/by-path/platform-i8042-serio-0-event-kbd',
  '/dev/input/by-path/pci-0000:00:14.0-usb-0:4.4:1.0-event-mouse',
  '/dev/input/by-path/pci-0000:00:15.1-platform-i2c_designware.1-event-mouse']
 debug: making async task queue_events-8154414866272
 debug: making async task queue_events-8154414866272
 debug: making async task queue_events-8154414866272
 debug: making async task queue_events-8154414866272
 20241030200524 monitoring 4 inputs
 debug: fd6: type:1, code:30, value:1
 debug: fd6: type:0, code:0, value:0
 debug: fd6: saw 3, processed 1, key 1, mouse 0
 debug: fd6: type:1, code:30, value:0
 debug: fd6: type:0, code:0, value:0
 debug: fd6: saw 3, processed 1, key 0, mouse 0
 debug: fd6: type:1, code:48, value:1
 debug: fd6: type:0, code:0, value:0
 debug: fd6: saw 3, processed 1, key 1, mouse 0
 debug: fd6: type:1, code:48, value:0
 debug: fd6: type:0, code:0, value:0
 debug: fd6: saw 3, processed 1, key 0, mouse 0
 debug: fd8: type:2, code:0, value:1
 debug: fd8: type:2, code:1, value:-2
 debug: fd8: type:0, code:0, value:0
 debug: fd8: saw 3, processed 2, key 0, mouse 2
 debug: fd8: type:2, code:1, value:-1
 debug: fd8: type:0, code:0, value:0
 debug: fd8: saw 2, processed 1, key 0, mouse 1
 debug: fd8: type:2, code:1, value:-1
 debug: fd8: type:0, code:0, value:0
 debug: fd8: saw 2, processed 1, key 0, mouse 1

..

