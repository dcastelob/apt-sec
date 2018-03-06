#!/bin/bash
#################################################################################################################
# Description: O apt-rollback permite reverter instalações utilizando apt, apt-get e apitiude. Utiliza os logs de 
# histório do apt para realizar esta operação.
#
# Author: Diego Castelo Branco
# E-mail: dcastelob@gmail.com
# Create: 25/08/2017
# Update: 31/08/2017
# Version: 1.00.0001
#
#################################################################################################################

APT_HISTORY=apt-history.sh
LIMITE=20
function isRoot()
{
	ID=$(id -u) 
	if [ "$ID" -ne 0 ]; then
		echo "Permission Denied to execute:"
		echo "Use: sudo $0 $@"
	fi
}

function usage()
{
	echo "usage $0 <limite>"
	echo "limite is a number: 0~20"
}

function executeRollback()
{
	RESUME="$1"
	RESUME=$(echo $RESUME | grep -v "^Start")
	echo "$RESUME"
	QTD_INSTALL=$(echo "$RESUME"| grep "^install"| wc -l)
	QTD_UPGRADE=$(echo "$RESUME"| grep "^upgrade"| wc -l)
	QTD_REMOVE=$(echo "$RESUME"| grep "^remove"| wc -l)
	QTD_PURGE=$(echo "$RESUME"| grep "^purge"| wc -l)
	CMD_FULL=""
	echo "====================================================================================="	
	echo " Install: $QTD_INSTALL Upgrade: $QTD_UPGRADE Remove: $QTD_REMOVE Purge: $QTD_PURGE"
	echo "====================================================================================="	
	IFS=$'\n'

	#Controll Variables
	CMD_INSTALL_01=""
	CMD_INSTALL_02=""
	CMD_INSTALL_03=""
	CMD_PURGE_01=""
	CMD_PURGE_02=""

	# Preparate to install packages was removed
	if [ "$QTD_REMOVE" -gt 0 ]; then

        PKG_SELECTED=$(echo "$RESUME"| grep "^remove")
		PKG_OPERATION=""
                VERSION_PKG_INSTALL=""
                for PKG in $PKG_SELECTED; do
                        P=$(echo $PKG| cut -d';' -f2 | cut -d':' -f1)
                        OLD_VERSION=$(echo $PKG| cut -d';' -f3 )
			#REAL_OLD_VERSION=$(apt-cache policy "$P" | grep -o "([a-Z0-9:])*$OLD_VERSION" | uniq | egrep -v "Candidate:|Installed:")
			REAL_OLD_VERSION=$(apt-cache policy "$P" | egrep -o "([a-Z0-9:])*$OLD_VERSION" | uniq |  awk '{print $1}')
                        PKG_OPERATION="$PKG_OPERATION $P"
			echo "REAL: $REAL_OLD_VERSION Old: $OLD_VERSION" 
                        #VERSION_PKG_INSTALL="$VERSION_PKG_INSTALL ${P}=${OLD_VERSION}"
			if [ -n "$REAL_OLD_VERSION" ];then
                        	VERSION_PKG_INSTALL="$VERSION_PKG_INSTALL ${P}=${REAL_OLD_VERSION}"
                        fi
                done
		QTD_VERSION_PKG_INSTALL=$(echo "$VERSION_PKG_INSTALL" | wc -w)
                PKG_OPERATION=$(echo "$PKG_OPERATION" | tr "\n" " ")
                VERSION_PKG_INSTALL=$(echo "$VERSION_PKG_INSTALL" | tr "\n" " ")
                echo
                echo "[Packages Removed to INSTALL: $QTD_REMOVE packages, packages localizaded: $QTD_VERSION_PKG_INSTALL]:"
                echo "apt-get -y install $VERSION_PKG_INSTALL"
		CMD_INSTALL_01="apt-get -y install $VERSION_PKG_INSTALL"
		
		 # Crítica 
                if [ "$QTD_REMOVE" -ne "$QTD_VERSION_PKG_INSTALL" ];then
			echo
                        echo "[Remove option] Many packages versions not found in repositories. "
			read -p "Would you like to rollback only the packages whose previous versions were found? (y/n) [y]: " RESP
                        RESP=$(echo "${RESP:-"Y"}")
                        RESP=$(echo $RESP| tr [a-z] [A-Z])
                        case "$RESP" in
                                Y)
                                REMOVE_ONLY_LOCATED=1
                                ;;
                                N)

                                echo "Operation aborted!"
                                exit 1
                                ;;
                                *)
                                echo "Invalid option (y or n)"
                                exit 1
                                ;;
                        esac

                       
                fi
	fi

	# Preparate to install packages was purged
        if [ "$QTD_PURGE" -gt 0 ]; then

                PKG_SELECTED=$(echo "$RESUME"| grep "^purge")
                PKG_OPERATION=""
                VERSION_PKG_INSTALL=""
                for PKG in $PKG_SELECTED; do
                        P=$(echo $PKG| cut -d';' -f2 | cut -d':' -f1)
                        OLD_VERSION=$(echo $PKG| cut -d';' -f3 )
			#REAL_OLD_VERSION=$(apt-cache policy "$P" | grep -o "([a-Z0-9:])*$OLD_VERSION" | uniq | egrep -v "Candidate:|Installed:")
			REAL_OLD_VERSION=$(apt-cache policy "$P" | egrep -o "([a-Z0-9:])*$OLD_VERSION" | uniq |  awk '{print $1}')
                        PKG_OPERATION="$PKG_OPERATION $P"
                        #VERSION_PKG_INSTALL="$VERSION_PKG_INSTALL ${P}=${OLD_VERSION}"
			if [ -n "$REAL_OLD_VERSION" ];then
                                VERSION_PKG_INSTALL="$VERSION_PKG_INSTALL ${P}=${REAL_OLD_VERSION}"
                        fi
                done
		QTD_VERSION_PKG_INSTALL=$(echo "$VERSION_PKG_INSTALL" | wc -w)
                PKG_OPERATION=$(echo "$PKG_OPERATION" | tr "\n" " ")
                VERSION_PKG_INSTALL=$(echo "$VERSION_PKG_INSTALL" | tr "\n" " ")
                echo
                echo "[Packages Purged to INSTALL: $QTD_PURGE packages]:"
                #echo "apt-get install $VERSION_PKG_INSTALL"
                echo "apt-get -y install $PKG_OPERATION"
		CMD_INSTALL_02="apt-get -y install $PKG_OPERATION"

		 # Crítica 
                if [ "$QTD_PURGE" -ne "$QTD_VERSION_PKG_INSTALL" ];then
                        echo
                        echo "[Purge option] Many packages versions not found in repositories. "
                        read -p "Would you like to rollback only the packages whose previous versions were found? (y/n) [y]: " RESP
                        RESP=$(echo "${RESP:-"Y"}")
                        RESP=$(echo $RESP| tr [a-z] [A-Z])
                        case "$RESP" in
                                Y)
                                REMOVE_ONLY_LOCATED=1
                                ;;
                                N)

                                echo "Operation aborted!"
                                exit 1
                                ;;
                                *)
                                echo "Invalid option (y or n)"
                                exit 1
                                ;;
                        esac
                fi
        fi


	# Packages to purge off systems
	if [ "$QTD_INSTALL" -gt 0 ]; then
		PKG_SELECTED=$(echo "$RESUME"| grep "^install")
		PKG_OPERATION=""
		for PKG in $PKG_SELECTED; do
			#PKG_OPERATION="$PKG_OPERATION $(echo $PKG| cut -d";" -f2 | cut -d":" -f1)"
			OLD_VERSION=$(echo $PKG| cut -d';' -f3 )
			P=$(echo $PKG| cut -d';' -f2 | cut -d':' -f1)
			REAL_OLD_VERSION=$(apt-cache policy "$P" | egrep -o "([a-Z0-9:])*$OLD_VERSION" | uniq |  awk '{print $1}')
			PKG_OPERATION="$PKG_OPERATION ${P}"
		done
		PKG_OPERATION=$(echo $PKG_OPERATION | tr "\n" " ")
		
		echo "[Packages Installed to REMOVE: $QTD_INSTALL peckages]:"
		echo "apt-get -y purge $PKG_OPERATION"
		CMD_PURGE_01="apt-get -y purge $PKG_OPERATION"
		
	fi

	# prepare to remove new packages and install old packages
	if [ "$QTD_UPGRADE" -gt 0 ]; then

		PKG_SELECTED=$(echo "$RESUME"| grep "^upgrade")
		PKG_OPERATION=""
		PKG_OPERATION_ONLY_LOCATED=""
		VERSION_PKG_INSTALL=""
		for PKG in $PKG_SELECTED; do
			P=$(echo $PKG| cut -d';' -f2 | cut -d':' -f1)
			OLD_VERSION=$(echo $PKG| cut -d';' -f3 )
			REAL_OLD_VERSION=$(apt-cache policy "$P" | egrep -o "([a-Z0-9:])*$OLD_VERSION" | uniq |  awk '{print $1}')
			# echo "Parcial: ${P}=${REAL_OLD_VERSION}:$OLD_VERSION"  # debug
			PKG_OPERATION="$PKG_OPERATION $P"
			# Remove only packages located in process to install old packages
                      
			#VERSION_PKG_INSTALL="$VERSION_PKG_INSTALL ${P}=${OLD_VERSION}"
			if [ -n "$REAL_OLD_VERSION" ];then
				VERSION_PKG_INSTALL="$VERSION_PKG_INSTALL ${P}=${REAL_OLD_VERSION}"
                        	PKG_OPERATION_ONLY_LOCATED="$PKG_OPERATION_ONLY_LOCATED ${P}"
			fi
		done
		QTD_VERSION_PKG_INSTALL=$(echo "$VERSION_PKG_INSTALL" | wc -w)
		#echo "$VERSION_PKG_INSTALL"   # debug
		PKG_OPERATION=$(echo "$PKG_OPERATION" | tr "\n" " ")
		VERSION_PKG_INSTALL=$(echo "$VERSION_PKG_INSTALL" | tr "\n" " ")
		echo
		
		# Crítica 
                if [ "$QTD_UPGRADE" -ne "$QTD_VERSION_PKG_INSTALL" ];then
                        echo
                        echo "[Upgrade options] Many packages versions not found in repositories. "
                        read -p "Would you like to rollback only the packages whose previous versions were found? (y/n) [y]: " RESP
                        RESP=$(echo "${RESP:-"Y"}")
                        RESP=$(echo $RESP| tr [a-z] [A-Z])
                        case "$RESP" in
                                Y)
				echo "[Packages Upgraded to REMOVE: $QTD_UPGRADE packages, Total packages to purge $QTD_VERSION_PKG_INSTALL ]:"
				CMD_PURGE_02="apt-get -y purge $PKG_OPERATION_ONLY_LOCATED"
				echo "$CMD_PURGE_02"
                                ;;
                                N)
				
				echo "[Packages Upgraded to REMOVE: $QTD_UPGRADE packages]:"
				CMD_PURGE_02="apt-get -y purge $PKG_OPERATION"
				echo "$CMD_PURGE_02"
                                ;;
                                *)
                                echo "Invalid option (y or n)"
                                exit 1
                                ;;
                        esac
                fi
		echo
		echo "[Packages Upgraded to INSTALL old version: $QTD_UPGRADE packages, packages localizaded: $QTD_VERSION_PKG_INSTALL]:"
                echo "apt-get -y install $VERSION_PKG_INSTALL"
		echo
		CMD_INSTALL_03="apt-get -y install $VERSION_PKG_INSTALL"
		
#		# Crítica 
#		if [ "$QTD_UPGRADE" -ne "$QTD_VERSION_PKG_INSTALL" ];then
#			echo
#			echo "[Upgrade options] Many packages versions not found in repositories. "
#			read -p "Are you sure you want to roll back the system? (y/n) [n]: " RESP
 #       		RESP=$(echo "${RESP:-"N"}")
  #     			RESP=$(echo $RESP| tr [a-z] [A-Z])
#        		case "$RESP" in
#                		Y)
#                       		 #echo "Comando: $CMD_FULL"
#                        	#eval "$CMD_FULL"
#                        	;;
#                		N)
#
#                        	echo "Operation aborted!"
#                        	exit 1
#                        	;;
#                		*)
#                        	echo "Invalid option (y or n)"
#                        	exit 1
#                        	;;
#        		esac
#
#		fi
	fi

        

	# Begin process to execute rollback

	echo	
	echo "We recommend that you back up the system before performing this operation. Do you want to continue anyway?"
	read -p "Are you sure you want to roll back the system? (y/n) [n]: " RESP
	RESP=$(echo "${RESP:-"N"}")
	RESP=$(echo $RESP| tr [a-z] [A-Z])
	case "$RESP" in
		Y)
			CMD_FULL=""
			for C in $CMD_PURGE_01 $CMD_PURGE_02 $CMD_INSTALL_01 $CMD_INSTALL_02 $CMD_INSTALL_03; do
                 		CMD_FULL="$CMD_FULL $C &&"
			done
			CMD_FULL="$CMD_FULL true"
			echo "Comando Full: $CMD_FULL"
			eval "$CMD_FULL"
			echo
			echo "Type ENTER to return to menu..."
			;;
		N)
			
			echo "Operation aborted!"
			exit 1
			;;
		*)
			echo "Invalid option (y or n)"
			exit 1
			;;
	esac
}




function getMenu()
{
	LIMITE="$1"
	LISTA=$(./$APT_HISTORY date-only| head -n "$LIMITE" )
#	LISTA=$(./$APT_HISTORY date-only )
	OLD_IFS=$' \t\n'
	IFS=$'\n'

	echo "Assistente de Reversão de pacotes"
	echo "--------------------------------------------------"
	echo "Selecione o periodo que será realizado o rollback:"
	select OPT in $LISTA "Sair";  do
		case $OPT in
			Sair)
				echo "Opção $OPT selecionada!" 
				exit 0
				;;
			*)
				OPERATION=$(echo "$OPT" | awk '{print $4 $5 $6 $7 $8 $9}' | sed "s/:/ /g")
				DATE=$(echo "$OPT" | awk '{print $2}' | sed "s/:/ /g")
				HOUR=$(echo "$OPT" | awk '{print $3}')
				RESULT=""
				export IFS=" "
				for OP in $OPERATION; do
					#echo "$OP $DATE $HOUR"
					RESULT="$RESULT $(./$APT_HISTORY "$OP" "$DATE" "$HOUR")"
				done
				executeRollback "$RESULT"	
		esac
	done
	IFS=$OLD_IFS
}


# Início do script
isRoot

VAR="1"
for I in $(seq 2 $LIMITE);do
	VAR="$VAR|$I"
done


case "$1" in
	1|2|3|4|5|6|7|8|9|10|11|12|13|14|15|16|17|18|19|20) 
	#$VAR) 
		getMenu "$1"
		;;
	--help|-h|*)
		usage
		;;
esac

