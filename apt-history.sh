#!/bin/bash
#################################################################################################################
# Description: O apt-history é um script que promete auxiliar a identificação operaçãoes com pacotes 
# em ambientes Debian/Ubuntu, permitindo identificar, intalações, remoções, atualizações...
#
# Author: Diego Castelo Branco
# E-mail: dcastelob@gmail.com
# Create: 25/08/2017
# Update: 31/08/2017
# Version: 1.00.0001
#
#################################################################################################################

APT_LOG="/var/log/apt/history.log"

function usage()
{
	echo "apt-history is a tool to only consult data off apt operations log in ($APT_LOG)."
	echo "Use apt-history to filter data and select isolated operations"
	echo 
	echo "Usage: $0 <filter> [date] [hour]"
	echo " Filters: date-only|install|remove|purge|upgrade"
	echo " Data Format: \"YYYY-MM-DD\"  Hour Format: \"hh:mm:ss\""
}

function getAptHistory()
{
	OPTION="$1"
	DATE="$2"
	HOUR="$3"
	INFO="$4"

	LOG_INLINE="cat /var/log/apt/history.log | tr "\n" ";" | sed 's/Start/\nStart/g'"	
	if [ -n "$DATE" ]; then
		COMMAND="cat $APT_LOG | grep $DATE -A5"
		if [ -n "$HOUR"  ];then
			COMMAND="cat $APT_LOG | grep $DATE  $HOUR -A5"
		fi
	else
		COMMAND="cat $APT_LOG | egrep -v \"End-Date\"| egrep -i \"^${OPTION}|Start-Date\" | sed 's/),/)\n/g' | sed 's/[),(]/;/g' | sed \"s/ //g\""
	fi
#	if [ "$INFO" == "--info" ];then
#		COMMAND_INFO="${COMMAND} | egrep  \"Start-Date\"| cut -d\":\" -f2-20"
#		eval $COMMAND_INFO
#	else
#		COMMAND="${COMMAND} | egrep -v \"Start-Date|End-Date\"| grep -i \"^${OPTION}\" | sed 's/),/)\n/g' | sed 's/[),(]/;/g' | sed \"s/ //g\""
#	echo "seria o comando completo "
#	fi
	eval $COMMAND
	#echo $COMMAND	
}

#cat /var/log/apt/history.log | tr "\n" ";" | sed 's/Start/\nStart/g' | grep -i "upgrade:"
function getAptHistory2()
{
        OPTION="$1"
        DATE="$2"
        HOUR="$3"
        INFO="$4"
	
	# Dentro dessa variável estão todos os eventos
#        LOG_INLINE=$(cat /var/log/apt/history.log | tr "\n" ";"| sed 's/Start/\nStart/g') 
	
	CMD_LOG_INLINE="cat $APT_LOG | tr \"\n\" \";\"| sed 's/Start/\nStart/g'| grep -i \"${OPTION}:\""
	# echo "CMD: $CMD_LOG_INLINE"  # debug
	# Tudo em uma linha comecando por Start-Date
	RESULT=$(eval $CMD_LOG_INLINE)
	# echo "REsult: $RESULT"   # debug
	#DATE=$(echo $RESULT | egrep -o "Start-Date: ([[:digit:]]){4}-([[:digit:]]){2}-([[:digit:]]){2}  ([[:digit:]]){2}:([[:digit:]]){2}:([[:digit:]]){2}") 
	#DATE=$(echo "$RESULT" | egrep -o "Start-Date: ([[:digit:]]){4}-([[:digit:]]){2}-([[:digit:]]){2}  ([[:digit:]]){2}:([[:digit:]]){2}:([[:digit:]]){2}") 
	FILTER=""
	if [ -n "$DATE" ];then
		if [ -n "$HOUR" ];then
			FILTER="$DATE  $HOUR"
		else
			FILTER="$DATE"
		fi
	else
		FILTER=""

	fi
	OLD_IFS=$' \t\n'
	IFS=$'\n'	
	for EVENT in $(echo "$RESULT" | grep -i "$FILTER"); do
		START_DATE=$(echo "$EVENT" | egrep -o "Start-Date: ([[:digit:]]){4}-([[:digit:]]){2}-([[:digit:]]){2}  ([[:digit:]]){2}:([[:digit:]]){2}:([[:digit:]]){2}")
		END_DATE=$(echo "$EVENT" | egrep -o "End-Date: ([[:digit:]]){4}-([[:digit:]]){2}-([[:digit:]]){2}  ([[:digit:]]){2}:([[:digit:]]){2}:([[:digit:]]){2}")
		FILTER=""
		#for F in Install Remove Purge Upgrade End-Date; do
		for F in Install Remove Purge Upgrade End-Date Error; do
			FILTER="$FILTER | sed 's/$F:/\n$F:/g' "
		done
		CMD_MULTILINE="echo \"$EVENT\" $FILTER"
		EVENT_MULTILINE=$(eval "$CMD_MULTILINE")
		echo 
		#echo "CMD_MULTILINE : $CMD_MULTILINE " # debug
		echo "$START_DATE - [$OPTION]"
		#echo "DataFim   : $END_DATE"		# debug
		#echo "Multiline : $EVENT_MULTILINE"	# debug
		FILTER=""
		# Retirando o tipo de operação de dentro dos registros
		for F in Install Remove Purge Upgrade End-Date Error; do
                        FILTER="$FILTER | sed 's/$F://g' "
                done
		CMD_MULTILINE="echo \"$EVENT_MULTILINE\" | grep -i \"${OPTION}:\" ${FILTER} | sed 's/),/)\n/g' | sed 's/[),(]/;/g' | sed 's/ //g'"
		#echo "CM: $CMD_MULTILINE"
		RESULT=$(eval "$CMD_MULTILINE")
		#RESULT=$(echo "$EVENT_MULTILINE" | grep -i "${OPTION}:"|  sed 's/),/)\n/g' | sed 's/[),(]/;/g' | sed 's/ //g')
		#echo "$EVENT_MULTILINE" | grep -i "$OPTION" # debug
		## echo "$RESULT"
		for LINHA in $RESULT;do
			echo "$OPTION;$LINHA"
		done
	done
}
function getResumeHistory()
{
	#cat $APT_LOG | egrep --color=auto "^([[:alpha:]])*:|Start-Date: ([[:digit:]]){4}-([[:digit:]]){2}-([[:digit:]]){2}  ([[:digit:]]){2}:([[:digit:]]){2}:([[:digit:]]){2}" -o | grep -v "Commandline:"| tr "\n" " " | sed 's/Start/\nStart/g' | grep -v "^$"
	cat $APT_LOG | egrep --color=auto "^([[:alpha:]])*:|Start-Date: ([[:digit:]]){4}-([[:digit:]]){2}-([[:digit:]]){2}  ([[:digit:]]){2}:([[:digit:]]){2}:([[:digit:]]){2}" -o | grep -v "Commandline:"| tr "\n" " " | sed 's/Start/\nStart/g' | grep -v "^$" | tac

}


# begin script
OPT=$(echo "$1" | tr 'A-Z' 'a-z')

if [ "$#" -lt 1 ]; then
	usage
	exit 1
else
	case "$OPT" in
		install|purge|remove|upgrade|error)
		#	getAptHistory "$1" "$2" "$3" "$4"
			getAptHistory2 "$OPT" "$2" "$3" "$4"
			;;
		date-only)
			getResumeHistory
			;;
		*)
		usage
	esac
fi
