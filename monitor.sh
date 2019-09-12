#!/bin/sh

# bug(dallas): name resolution fails and causes errors when internet goes down

#-------------------------------------------------------------------------------------------------------------------- path ---+
PATH=/sbin:$PATH # asterisk scripts called by fwconsole fail unless /sbin is explicity added to the path, either in the script or as a part of the cron job
#------------------------------------------------------------------------------------------------------------------- usage ---+
usage()
{
	echo "usage:"
	echo "	monitor.sh [[[-c count -m min_acceptable_pings] [-a address] [-n] [-nl] [-ne] [-d] [-i]] | [-h]]"
	echo ""
	echo "	-c (ping count): specifies the number of pings to send to the server, defaults to 10. undefined behavior when used without -m"
	echo "	-m (minimum acceptable ping count): specifies the minimum amount of pings that must succeed for the trunks to remain online. defaults to 8. should be less than the ping count (-c)"
	echo "	-a (server address): the ip address of the external host that will be pinged. defaults to 8.8.8.8"
	echo "	-n (all logging disabled): prevents logs from being emailed or created / updated in /var/log/asterisk/monitor"
	echo "	-nl (no log reports): prevents logs from being created / updated in /var/log/asterisk/monitor. does not stop generating email reports"
	echo "	-ne (no email reports): prevents email reports from generating. does not stop logs from being created / updated in /var/log/asterisk/monitor"
	echo "	-i (interactive): prints script activity to the command line"
	echo "	-d (debug): prints extra debug info to the command line. implies -i"
	echo "	-h (help): display usage information"
}
#-------------------------------------------------------------------------------------------------------------------- vars ---+
#--------------
# Touch these:
#--------------
address="8.8.8.8"
pings=0
ping_count=10
min_acceptable_pings=8
logfilepath="/var/log/asterisk/monitor"
emaildest="techs@ksp.ca"
#--------------------
# Don't touch these:
#--------------------
interactive=false
debug=false
# todo(dallas): replace xargs w/ sed
#interfaces=($(/usr/local/sbin/fwconsole trunk --list | grep 'sip' | awk -F'|' '{print $2}' | xargs)) # note(dallas): StackOverflow to the rescue! https://stackoverflow.com/questions/9293887/reading-a-delimited-string-into-an-array-in-bash
interfaces=($(/usr/local/sbin/fwconsole trunk --list | grep 'sip' | awk -F'|' '{print $2}' | xargs))
num_interfaces=${#interfaces[@]}
disabled=($(/usr/local/sbin/fwconsole trunk --list | grep 'sip' | awk -F'|' '{print $5}' | xargs))
reload_needed=false
filestamp="$(date +'%h %d %Y')"
logfile="$logfilepath/$filestamp"
datestamp="$(date +'%H:%M:%S, %h %d, %Y')"
PBXname=$(hostname)
#-------------------------------------------------------------------------------------------------------- cmd line parsing ---+
while [ "$1" != "" ]; do
	case "$1" in
		# bug(dallas): if -c is specified without -m, script may not work as intended
		-c )	shift
			ping_count=$1
		;;
		-a )	shift
			address="$1"
		;;
		-d )	debug=true
			interactive=true
		;;
		-m )	shift
			min_acceptable_pings="$1"
		;;
		-i )
			interactive=true
		;;
		-n )
			logfile="/dev/null"
			emaildest=""
		;;
		-nl )
			logfile="/dev/null"
		;;
		-ne )
			emaildest=""
		;;
		-h )	usage
			exit 1
		;;
	esac
	shift
done
#---------------------------------------------------------------------------------------------------------- vars debugging ---+
mkdir --parents $logfilepath
if [ $debug = true ]; then
	echo +--------------------------------------------------------+
	echo interactive=$interactive
	echo debug=$debug
	echo current time=$datestamp
	echo PBXname=$PBXname
	echo ping_count=$ping_count
	echo min_acceptable_pings=$min_acceptable_pings
	echo address=$address
	echo $num_interfaces SIP trunks found:
	for i in $(seq 0 $(($num_interfaces-1))); do
		if [ "${disabled[$i]}" = "on" ]; then
			yes_no="yes"
		elif [ "${disabled[$i]}" = "off" ]; then
			yes_no="no"
		else
			echo Error in debug loop!
		fi
		echo -e '\t' interface ${interfaces[$i]} disabled? $yes_no
	done
	echo filestamp=$filestamp
	echo datestamp=$datestamp
	echo logfile=$logfile
	echo emaildest=$emaildest
	echo ==============================================
fi
echo +--------------------------------------------------------+ >> $logfile
echo interactive=$interactive >> $logfile
echo debug=$debug >> $logfile
echo current time=$datestamp >> $logfile
echo PBXname=$PBXname >> $logfile
echo ping_count=$ping_count >> $logfile
echo min_acceptable_pings=$min_acceptable_pings >> $logfile
echo address=$address >> $logfile
echo $num_interfaces SIP trunks found: >> $logfile
for i in $(seq 0 $(($num_interfaces-1))); do
	if [ "${disabled[$i]}" = "on" ]; then
		yes_no="yes"
	elif [ "${disabled[$i]}" = "off" ]; then
		yes_no="no"
	else
		echo Error in debug loop! >> $logfile
	fi
	echo -e '\t' interface ${interfaces[$i]} disabled? $yes_no >> $logfile
done
echo filestamp=$filestamp >> $logfile
echo datestamp=$datestamp >> $logfile
echo logfile=$logfile >> $logfile
echo emaildest=$emaildest >> $logfile
echo ============================================== >> $logfile
#--------------------------------------------------------------------------------------------------------- meat & potatoes ---+
if [ $interactive = true ]; then
	echo monitoring trunks at $datestamp...
fi
echo monitoring trunks at $datestamp... >> $logfile
if [ $interactive = true ]; then
	echo pinging $address $ping_count times...
fi
echo pinging $address $ping_count times... >> $logfile
pings=$(ping -c $ping_count $address | grep 'received' | awk -F',' '{print $2}' | awk '{print $1}')
if [ -z "$pings" ]; then
	pings=0
fi
if [ $interactive = true ]; then
	echo "$pings successful pings to $address"
fi
echo "$pings successful pings to $address" >> $logfile
if [ $pings -lt $min_acceptable_pings ]; then
	if [ $interactive = true ]; then
		echo Unacceptable min ping threshold $min_acceptable_pings reached
	fi
	echo Unacceptable min ping threshold $min_acceptable_pings reached  >> $logfile
	for i in $(seq 0 $(($num_interfaces-1))); do
		if [ "${disabled[$i]}" = "off" ]; then
			/usr/local/sbin/fwconsole trunk --disable "${interfaces[$i]}" > /dev/null
			if [ $interactive = true ]; then
				echo "Trunk ${interfaces[$i]} disabled on ${PBXname} at ${datestamp}"
			fi
			echo "Trunk ${interfaces[$i]} disabled on ${PBXname} at ${datestamp}" | mail -s "${PBXname}: trunk disabled" $emaildest
			echo "Trunk ${interfaces[$i]} disabled on ${PBXname} at ${datestamp}" >> $logfile
			reload_needed=true
		fi
	done
else
	for i in $(seq 0 $(($num_interfaces-1))); do
		if [ "${disabled[$i]}" = "on" ]; then
			/usr/local/sbin/fwconsole trunk --enable "${interfaces[$i]}" > /dev/null
			if [ $interactive = true ]; then
				echo "Trunk ${interfaces[$i]} enabled on ${PBXname} at ${datestamp}" 
			fi
			echo "Trunk ${interfaces[$i]} enabled on ${PBXname} at ${datestamp}" | mail -s "${PBXname}: trunk enabled" $emaildest
			echo "Trunk ${interfaces[$i]} enabled on ${PBXname} at ${datestamp}" >> $logfile
			reload_needed=true
		fi
	done
fi
if [ $reload_needed = true ]; then
	if [ $interactive = true ]; then
		echo Reloading FreePBX...
	fi
	echo Reloading FreePBX... >> $logfile
	/usr/local/sbin/fwconsole reload >> /dev/null
	if [ $interactive = true ]; then
		echo Successfully reloaded
	fi
	echo Successfully reloaded >> $logfile
fi
if [ $debug = true ]; then
	echo +--------------------------------------------------------+
fi
echo +--------------------------------------------------------+ >> $logfile
