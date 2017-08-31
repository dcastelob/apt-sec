#!/bin/bash
#################################################################################################################
# Description: O apt-sec é um script que promete auxiliar o procedimento de atualização de pacotes em 
# ambientes Debian/Ubuntu, possibilitando a restauração (rollback) em caso de inconsistências
#
# Author: Diego Castelo Branco
# E-mail: dcastelob@gmail.com
# Create: 25/08/2017
# Update: 31/08/2017
# Version: 1.00.0001
#
#################################################################################################################



export CODENOME=$(lsb_release -c | awk '{print $2}')


export FILE_CONTROL="/tmp/apt-sec.ctrl"
export EXPIRED="3600"
export CVE_DB_FILE="/tmp/apt-sec.cvedb"

export ROLLBACK_PKG_DIR="/var/cache/apt/rollback"
export ROLLBACK_PKG_DIR_OWNER="root"
export APT_SEC_LOG="/var/log/apt-sec.log"

function fn_isRoot()
{
	ID=$(id -u) 
	if [ "$ID" -ne 0 ]; then
		echo "Permission Denied to execute:"
		echo "Use: sudo $0 $@"
		exit 99
	fi
}

function fn_usage()
{
	echo "Usage: $0 <option>"
	echo "Options:"
	echo "-h|--help - Help commands"
	echo "-l|--list	- List all packages upgradable"
	echo "-a|--all	- Secure update for all packages upgradable"
	echo "--cve		- Secure update only packages with CVE associated"
	echo "-R|--rollback - Execute rollback old packages"
	
}

function fn_generate_apt_log()
{
	DATE="$1"
	PKG_COLLECTION="$2"
	DATE_EVENT=$(date "+%x %T")
	for I in $PKG_COLLECTION; do
		echo "$DATE|$DATE_EVENT|$I" >> "$APT_SEC_LOG" 
	done
}

function fn_get_cve_db()
{
	# Função que coleta a base de CVEs atualizada e guarda localmente, obedecendo o tempo de expiração.
	
	echo "[info] Coletando dados de base de CVE, Aguarde..."	
	export PGPASSWORD=udd-mirror && psql --host=udd-mirror.debian.net --user=udd-mirror udd -c "select s1.issue, s1.source, s1.fixed_version, s1.urgency, s1.release, s1.status, s2.description from public.security_issues_releases as s1 inner join public.security_issues as s2 on (s1.issue = s2.issue) where s1.release='stretch' and s1.status='resolved' and s1.issue like 'CVE%' order by s1.issue desc;" > "$CVE_DB_FILE"
	#cat "$CVE_DB_FILE"
}


function fn_get_packages_cve()
{
	
	CVE="$1"
	#VALOR=$(curl --silent https://security-tracker.debian.org/tracker/"$CVE" 2>&1 |sed -e 's/<[tr]*>/\n/g'|sed -e 's/<[^>]*>/ /g'|  grep "$CODENOME" | grep -v "(unfixed)"| tail -n1)
	VALOR=$(curl --silent https://security-tracker.debian.org/tracker/"$CVE" 2>&1 |sed -e 's/<[tr]*>/\n/g'|sed -e 's/<[^>]*>/ /g')
	
	if [ -z "$VALOR" ];then
		echo "Sem resultado"
	else
		#echo resultado #"$VALOR"
		export PACKAGE_NAME=$(echo "$VALOR"| grep -A1 "^ Package" | tail -1 | awk '{print $1}')
		export SEVERITY=$(echo "$VALOR"| grep -i "severity" | awk '{print $3}')
		export VERSION=$(echo "$VALOR"|  grep "$CODENOME" | grep "fixed" | awk '{print $3}' | tail -n1)
		export DESCRIPTION=$(echo "$VALOR"| grep -i "Description" | sed 's/ Description//')	
	fi
		
}

function fn_get_packages_dsa()
{
	DSA="$1"
	VALOR=$(curl --silent https://security-tracker.debian.org/tracker/"$DSA" 2>&1 |sed -e 's/<[tr]*>/\n/g'|sed -e 's/<[^>]*>/ /g'|  grep "$CODENOME" | grep -v "(unfixed)"| tail -n1)
	if [ -z "$VALOR" ];then
		echo "Sem resultado"
	else
		echo "$VALOR"	
	fi
}

function fn_get_package_upgradeble(){
	

	#LIST=$(sudo apt-get upgrade --assume-no -V | grep "^ ")
	LIST=$(sudo apt-get upgrade --assume-no -V | grep "^ " | awk '{print $1"|"$2"|"$4}'| sed 's/[)(]//g')
	#PACKAGES=$(echo "$LIST" | awk '{print $1}')
	
	echo "$LIST"
}

function fn_locate_package_in_cve()
{
	# função para localizar se existe CVE para atualização de pacote
	PKG="$1"
	#cat "$CVE_DB_FILE" | grep "| $PKG " | head -n1 |sed 's/ //g'| awk -F "|" '{print $1" "$2" "$3" "$4" "$7}'
	RESULTADO=$(cat "$CVE_DB_FILE" | grep "| $PKG " | head -n1 | awk -F "|" '{print $1"|"$2"|"$3"|"$4"|"$7}')
	if [ -n "$RESULTADO" ];then
		echo "$RESULTADO"
		return 0
	else
		return 1	
	fi
}


function fn_download_package_version()
{
	# função para realização de download de pacotes para realização de rollback
	PKG="$1"
	VERSION="$2"
	#echo "%$PKG%$VERSION%"
	if [ ! -d $ROLLBACK_PKG_DIR ];then
		mkdir "$ROLLBACK_PKG_DIR"
		chown root:root "$ROLLBACK_PKG_DIR"
	fi
	cd "$ROLLBACK_PKG_DIR"
	
	LOCALIZA=$(ls /var/cache/apt/archive/"${PKG}_$VERSION_*.deb" 2>/dev/null)
	if [ -n "$LOCALIZA" ];then
		cp "${PKG}_${VERSION}_*.deb" "$ROLLBACK_PKG_DIR/"
		echo "[info] Pacote: ${PKG}_$VERSION (existente no archives) foi arquivado para rollback em: $ROLLBACK_PKG_DIR" 
	else
		sudo apt-get download "$PKG"="$VERSION" 2> /dev/null
		RESULT="$?"
		#echo "DOWNLOAD RESULT: $RESULT"   #DEBUG
		if [ "$RESULT" -eq 0 ];then
			echo "[info] Pacote: ${PKG}_$VERSION baixado e arquivado para rollback em: $ROLLBACK_PKG_DIR"
			return 0
		else
			echo "[Erro] Problemas ao baixar pacote: ${PKG}_$VERSION para rollback em: $ROLLBACK_PKG_DIR"
			return 1	
		fi
	fi
}

function fn_verify_package()
{
	PACKAGE="$1"
	VERSION="$2"
	if [ -z "$PACKAGE"  -o  -z "$VERSION" ];then
		echo "CVE sem informações suficientes!"
		exit 1
	else
		#echo "ELES NAO SAO NULOS"
		LISTA=$(dpkg -l | grep -i "$PACKAGE" | grep "$VERSION")
		if [ -z "$LISTA" ];then
			echo "Pacotes não encontrados"
		else
			echo "Resultados encontrados:"
			echo "$LISTA" 
		fi		
	fi 
	
}

#===========================================================================
# ROLLBACK

function fn_execute_rollback()
{
	PKG_COLLECTION="$1"
	
	PKG_TO_PURGE=""
	PKG_TO_REINSTALL=""
	for P in $PKG_COLLECTION; do
		
		PKG=$(echo "$P" | awk -F"|" '{print $1}' )
		VER_OLD=$(echo "$P" | awk -F"|" '{print $2}' )
		VER_NEW=$(echo "$P" | awk -F"|" '{print $2}' )
		
		PKG_TO_PURGE="${PKG_TO_PURGE} ${PKG}"
		PKG_TO_REINSTALL="${PKG_TO_REINSTALL}  ${PKG}=${VER_NEW}"
	done
	
	# PErguntar antes de restaurar, solicitar confirmação antes de fazer...
	
	echo "apt-get -y purge $PKG_TO_PURGE"
	echo "apt-get -y install $PKG_TO_REINSTALL"
}


function fn_menu_rollback()
{
	#LIMITE="$1"
	LIMITE=10
	LISTA=$(cat "$APT_SEC_LOG" | awk -F "|" '{print $1" "$2}' | uniq -c | awk '{print $2"|"$3" " $4"|"$1 " Package(s)"}' | head -n "$LIMITE" )
	OLD_IFS=$' \t\n'
	IFS=$'\n'

	echo "--------------------------------------------------"
	echo "| Rollback packages                              |"
	echo "--------------------------------------------------"
	echo "Select rollback iterate:"
	select OPT in $LISTA "Quit";  do
		case $OPT in
			Sair|Quit)
				echo "$OPT option selected!" 
				exit 0
				;;
			*)
				FILTER=$(echo $OPT| awk '{print $1}')
				PKG_COLLECTION=$(cat "$APT_SEC_LOG" | grep "$FILTER" | awk -F "|" '{print $3"|"$4"|"$5}' )
				
				#for PKG in $PKG_COLLECTION; do
				#	echo "$PKG"
				#done
				fn_execute_rollback	"$PKG_COLLECTION"
		esac
	done
	IFS=$OLD_IFS
}


function fn_main()
{
	
	OPT="$1"
	
	# Verifca se é root
	fn_isRoot
	
			
		
	case $OPT in
	"--cve")
		# Verificando a necessidade de invocar a coleta de dados de CVEs do Debian
		if [ -e $FILE_CONTROL ]; then
				ULTIMO=$(cat "$FILE_CONTROL")
				ATUAL=$(date +%s)
				if [ $(($ATUAL-$ULTIMO)) -gt "$EXPIRED" ];then
					# tempo maior que expirado
					echo "[info] Base de CVE expirada"
					fn_get_cve_db && date +%s > "$FILE_CONTROL"
				fi		
		else
			date +%s > "$FILE_CONTROL"
			fn_get_cve_db	
		fi
		
		sudo apt-get update
		# Verificando se todos os pacotes atualizaveis possuem um CVE associado
		LISTA=$(fn_get_package_upgradeble)
		for ITEM in $LISTA; do
			#echo "ITEM: $ITEM"
			PKG=$(echo "$ITEM" | awk -F "|" '{print $1}')
			VER_OLD=$(echo "$ITEM" | awk -F "|" '{print $2}')
			VER_NEW=$(echo "$ITEM" | awk -F "|" '{print $3}')
			
			#echo "PKG: $PKG, VER_OLD: $VER_OLD, VER_NEW: $VER_NEW "   #DEBUG
			fn_locate_package_in_cve "$PKG"
			RESP="$?"
			if [ "$RESP" -eq 0 ]; then
				#echo "PACOTE: $PKG"
				fn_download_package_version "$PKG" "$VER_OLD"
				RESP2="$?"
				if [ "$RESP2" -eq 0 ]; then
					PKG_COLLECTION=$(echo -e "${PKG_COLLECTION}\n${ITEM}")
					PKG_TO_UPDATE="${PKG_TO_UPDATE} ${PKG}"
				fi
			fi
		done
		echo "apt-get install $PKG_TO_UPDATE"
		fn_generate_apt_log "$(date +%s)" "$PKG_COLLECTION"
		;;
	-a|--all)
		sudo apt-get update
		# Atualizando todos os pacotes que obtiveram sucesso no download		
		PKG_TO_UPDATE=""
		LISTA=$(fn_get_package_upgradeble)
		
		for ITEM in $LISTA; do
			#echo "ITEM: $ITEM"
			PKG=$(echo "$ITEM" | awk -F "|" '{print $1}')
			VER_OLD=$(echo "$ITEM" | awk -F "|" '{print $2}')
			VER_NEW=$(echo "$ITEM" | awk -F "|" '{print $3}')
			
			fn_download_package_version "$PKG" "$VER_OLD"
			RESP="$?"
			
			if [ "$RESP" -eq 0 ]; then
				#echo "PACOTE: $PKG"
				PKG_TO_UPDATE="${PKG_TO_UPDATE} ${PKG}"
			fi
		done
		echo "apt-get install $PKG_TO_UPDATE"
		;;	
	-l|--list)
		sudo apt-get update
		echo "[List all packages upgradeble]"
		fn_get_package_upgradeble	
		;;
	-h|--help)
		fn_usage
		;;
	-R|--rollback)
		fn_menu_rollback
		;;		
	*)
		fn_usage
		;;	
	esac  
	
	
	
}

# inicio do script

fn_main "$1"

#fn_get_packages_cve "$1"
#fn_get_cve

#echo Nome: "$PACKAGE_NAME"
#echo Versão: "$VERSION"
#echo Severidade: "$SEVERITY"
#echo Descrição: "$DESCRIPTION"

# fn_verify_package "$PACKAGE_NAME" "$VERSION"

