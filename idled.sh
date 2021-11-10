#!/bin/bash
#
# Monitor keystrokes and mouse usage of primary console
#
# - robotically samples activity at the console, logging
#   idle data, user-provided window/shell names other info
#   (see ${expansions[@]}
# - charge time spent in hierarchical 'goto' ticket labels
#   representing work (godo, goassoc, go*)
# - maintains notion of
# - issues warning sound to user before marking away
#

trap "exit" INT

xvtnum=63	# X run on which virtual terminal?

keybdint=1	# hardware interrupt line for keyboard
mouseint=12	# hardware interrupt line for mouse

micethresh=100	# trackpoint can move accidentally while cover closed
keysthresh=0	# no tolerance for keypresses (XXX TODO per unit time)

sleepval=3s	# loop duration: sleep between checks of interrupt counters
warn_toidle=16	# this many sleepvals before warning we will make idle
real_toidle=18	# this many sleepvals until we really do idle state change
warn_fromidle=7	# but easier to come back from idle
real_fromidle=9	# for real
resetiters=2	

# always want it called this
#
progname=idled
invopath=${BASH_SOURCE[0]}
invoname=$(basename $invopath)
invoexec=$(dirname $invopath)/$progname

logfile=~/var/log/idle.log
afkfile=~/var/go/afk
pausefile=~/var/go/paused

declare logical_idle=0
declare raw_idle=1
declare ndifferent=0

export debug=0
export PS4=${debug:+'+ $BASHPID: $FUNCNAME: '}

##############################################################################

#
# start daemon to monitor input lines and recording into
# logfile/syslog with shell goto/godo/goassoc or ratpoison
# builtin grename/gnew
#
# (we have access to titles, window list and group lists)
#
daemonize_self ()
{
	local exe=$1; shift

	if ! ((daemonized)); then
		export daemonized=1
		setsid $exe $@ </dev/null &>/dev/null &
		return $?
	fi

}

### INVOCATION NAMES #########################################################

case $invoname in

# start the idle monitor daemon
#
(idleon|idlestart|idled)

	if ! ((daemonized)); then
		if false && pgrep $progname &>/dev/null; then
			echo "already running? try idlestat/idleoff"
			exit 1;
		elif daemonize_self $invoexec $@; then
			echo "daemonized"; exit 0;
		else
			echo "daemonization failed"; exit 1;
		fi
	fi

	exec 2> >(logger -t $progname)

	((debug)) && set -x

	;;

(idlenew)

	idleoff && idleon
	exit $?

	;;

# stop idle monitor daemon
#
(idleoff|idlestop)

	if pgrep $progname &>/dev/null
	then
		if pkill $progname
		then echo "killed"; exit 0;
		else echo "bad kill"; exit 1;
		fi
	else
		echo "already off"; exit 1;
	fi ;;

# check if idled running
#
(idlestat)

	if pgrep $progname &>/dev/null
	then echo "$progname running"; exit 0;
	else echo "$progname not running, try idleon"; exit 1
	fi ;;

# all the others -- not sure if they work anymore
#
(goafk)		echo "away from keyboard"; touch $afkfile;	exit 0;;
(gokfa)		echo "back to keyboard"; rm -f $afkfile;	exit 0;;
(gopause)	echo "paused"; touch $pausefile;		exit 0;;
(goresume)	echo "unpaused"; rm -f $pausefile;		exit 0;;
(*)		echo "$progname: unsupported usage";		exit 1;;

esac

##############################################################################

# talk (literally) to the machine operator (used here to let
# him be aware of idle state transitions) while also making
# record in system log
#
say ()
{
	# warm up: when we come bach from auto-suspend
	# first part of speech is clipped
	#
	#echo | espeak

	# make both fs log and to syslog, prefixed with the date
	#
	echo "$(date +%Y%m%d%H%M%S): $*" |
	tee -a ~/var/log/idled-said.log |
	logger -t $progname

	# but for the speaker itself we don't use the date
	# XXX TODO see strace, commenting out for now
	#
	#espeak -v english-us "$*"
}

# just play a sound...
# XXX TODO this routine never runs, see maybe_do_alert()
#
do_alert ()
{
	# XXX TODO temporary until thinkpad console beep
	# works again...
	#
	play -q ~/var/sounds/centerim-email.wav

	# early exit, see below
	#
	return

	# ...at which time just use this
	#
	local beepdev=/dev/tty1
	for ((i = 0; i < 20; i++)); do
		echo -en \\a > $beepdev
		usleep 10000
	done
}

# XXX TODO this routine does nothing because 'alertiters'
# is uninitialized and nobody else references it.  Not sure
# what the value would be in playing wav file cyclically
# though, this may just be left over kruft
#
maybe_do_alert ()
{
	if ((alertloops++ > alertiters))
	then
		do_alert
		alertloops=0
	fi
}

in_xwindows ()
{
	((fgconsole == xvtnum))
}

get_field_from_matching ()
{
	local line="$1"
	local pattern=$2
	local match=$3
	local fieldnum=$4

	[[ $line =~ $pattern ]]
	match="${BASH_REMATCH[1]}"
	assoc="${BASH_REMATCH[2]}"
	[[ $match == '*' ]] && printf "$assoc"
}

log_activity ()
{
	local active=${1:?}
	local now=$(date +%Y%m%d%H%M%S)
	local rp='DISPLAY=:0 ratpoison -c'

	# these are the two important variables
	local group assoc

	if in_xwindows
	then
		# GROUP ###
		#
		# Get ratpoison 'group' and 'window' output instead ;
		# this is intended for humans so we have to make a regex
		# table
		#
		# In output, asterisk signifies the console user's
		# current group or window, which we use as the
		# "association" from a compound of group:window.
		#
		# They only look pretty if we name them in Ratpoison so
		# this often will catch very ugly filenames, typically
		# for a browser window.
		#
		while read line; do
			pat='^[[:digit:]]+(.)(.*)'
			group="$(
				get_field_from_matching "$line" "$pat" '*' 2
			)" && break
		done <<< "$(eval $rp groups)"

		### WINDOWS ###
		#
		# XXX TODO truncated, obeys my display settings which
		# aren't infinite, logged should be full string maybe
		# (arguable) screen gets truncated copy
		#
		while read line; do
			pat='^(.)[[:space:]]+'
			pat+='[[:digit:]]+[[:space:]]+'
			pat+='[[:digit:]]+[[:space:]]+'
			pat+='(.*)'
			assoc="$(
				get_field_from_matching "$line" "$pat" '*' 2
			)" && break
		done <<< "$(eval $rp windows)"
	else
		### CONSOLE ###
		#
		# at console it's much easier: extract the
		# data from the tty associations maintained
		# by our own goto system when we associate a
		# terminal with an issue being worked
		# (shell: "goassoc")
		#
		# XXX TODO stsart using pgsql or sqlite here
		# but then how about remote systems? make
		# .so for loading into bash? for remote too?
		#
		assoc=$(
			ls -d1Rt ~/var/go/tty/$fgconsole/*/assoc |
			head -1
		) || return 1
		assoc=$(basename $(readlink $assoc))
		group=${assoc%%:*}
	fi

	# whether we are clockon or clockoff
	#
	gstat=$(ls -t $(for dir in stops starts; do
		cd ~/$(<~/.goprefix)/log/$dir || exit 1
		readlink -f $(ls -t | head -1)
		cd $OLDPWD
	done) | head -1)
	gstat=$(basename $(dirname $gstat))
	gstat=${gstat%s}

	# Sometimes there just is no association to get
	#
	# - XXX TODO when? grepping logs, this appears to be
	#   error if happens, which I could not find a case of
	#
	# - XXX TODO the future we should do *something* here like
	#   maybe just the command line of the foreground process
	#   (console), or something...
	#
	group="${group:-NOGROUP}"
	assoc="${assoc:-NOASSOC}"
	gstat="${gstat:-NOGSTAT}"

	# so now we have the format for a line for our idle log
	#
	local expansions=(
		$active		# if we are most likely at keyboard
		${gstat:?}	# are we tracking time right now?
		$(godo)		# last thing we were working on
		$fgconsole	# virtual teletype of console operator
		"${group:?}"	# ratpoison group: gnew, gmove, gselect,
		"${assoc:?}"	# title of specific window
	)

	# if nothing has changed since the last run, skip log
	#
	new_logstring="${expansions[*]}"
	[[ $old_logstring == $new_logstring ]] ||
		echo "$now $new_logstring" >> $logfile
	old_logstring="$new_logstring"
}

is_idle_raw ()
{
	((oldkeys + keysthresh >= newkeys &&
	  oldmice + micethresh >= newmice))
}

is_afk	  () { test -f $afkfile; }
is_paused () { test -f $pausefile; }

update_interrupt_counters ()
{
	while read intnum cpu1 cpu2 rest
	do
		if [[ $intnum == $keybdint: ]]
		then newkeys=$((cpu1 + cpu2))
		elif [[ $intnum == $mouseint: ]]
		then newmice=$((cpu1 + cpu2)); break
		fi
	done < /proc/interrupts
}

# for is_idle_raw()
save_interrupt_counters ()
{
	oldkeys=$newkeys
	oldmice=$newmice
}

toggle_idle_state ()
{
	logical_idle=$((++logical_idle % 2));

	if ((logical_idle))
	then say="away"
	else say="returned"
	fi

	say "$say"
}

# two different "profiles" of idle depending on if we are
# coming from or to the keyboard, allowing separate timeout
# settings
#
update_threshold_vars ()
{
	if ((logical_idle)); then
		state_change_threshold=$real_fromidle
		warn_threshold=$warn_fromidle
	else
		state_change_threshold=$real_toidle
		warn_threshold=$warn_toidle
	fi

	reset_threshold=$resetiters
}

update_idle_status ()
{
	((debug)) && declare -p ndifferent raw_idle logical_idle >&2

	if ((raw_idle != logical_idle))
	then
		# counter gets incremented each iteration if
		# real status differs from last recorded
		# status
		#
		let ndifferent++

		# once the count of discrepancies exceeds the
		# configured threshold we toggle the idle status state
		# (after first going through a warning phase)
		#
		if ((ndifferent > state_change_threshold)); then
			toggle_idle_state
			update_threshold_vars
			ndifferent=0
		elif ((ndifferent > warn_threshold)); then
			issue_warning $ndifferent
		fi
	else
		((ndifferent)) && let ndifferent--
	fi
}

issue_warning ()
{
	local n=$1
	say $((n - warn_threshold))

	let warning_issued++
}

##############################################################################

main ()
{
	update_interrupt_counters

	if is_idle_raw
	then raw_idle=1
	else raw_idle=0
	fi

	if ! is_paused; then
		update_idle_status
	fi

	if ((logical_idle))
	then logstring=inactive
	else logstring=active
	fi

	fgconsole=$(fgconsole) ||
		{ echo "VT_GETSTATE failed, exiting" >&2; exit 1; }

	log_activity $logstring

	#if
	#	log_activity inactive
	#	if ! is_afk && ! is_paused; then maybe_do_alert; fi
	#else
	#	log_activity active
	#	if is_afk && ! is_paused; then maybe_do_alert; fi
	#fi

	save_interrupt_counters
	sleep $sleepval
}

##############################################################################

# set initial state before starting to loop
# we were probably started from keyboard
#
say "start"
update_threshold_vars

while true; do main $@; done
