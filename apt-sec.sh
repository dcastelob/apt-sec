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

export ROLLBACK_LIMITE=5

function fn_requiriments()
{
	which psql &> /dev/null
	if [ "$?" -ne 0 ];then
		echo "Install postgres client (apt-get install postgresql-client)"
		exit
	fi
	which lsb_release &> /dev/null
	if [ "$?" -ne 0 ];then
		echo "Install lsb_release (apt-get install lsb-release)"
		exit
	fi
	
	which column &> /dev/null
	if [ "$?" -ne 0 ];then
		echo "apt-get install bsdmainutils"
		exit
	fi
	
}
function fn_isRoot()
{
	ID=$(id -u) 
	if [ "$ID" -ne 0 ]; then
		echo "Permission Denied to execute:"
		echo "Use: sudo $0 $@"
		exit 99
	fi
}

function fn_line()
{
	CHAR="$1"
	if [ -n "$CHAR" ];then
		printf "%$(tput cols)s\n" | tr ' ' $CHAR
	else
		printf "%$(tput cols)s\n" | tr ' ' -
	fi
}
function fn_usage()
{
	echo "Usage: $0 <option>"
	echo "Options:"
	echo " -h|--help         - Help commands"
	echo " -l|--list         - List all packages upgradable"
	echo " -a|--all          - Secure update for all packages upgradable"
	echo " -c|--cve          - Secure update only packages with CVE associated"
	echo " -C|--cve-details  - Secure update only packages with CVE associated detailed"
	echo " -R|--rollback     - Execute rollback old packages"
	echo
	
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
	

	#LIST=$( apt-get upgrade --assume-no -V | grep "^ ")
	LIST=$( apt-get upgrade --assume-no -V | grep "^ " | awk '{print $1"|"$2"|"$4}'| sed 's/[)(]//g')
	
	PKG=$(echo "$LIST" | awk -F "|" '{print $1}')
	VER_OLD=$(echo "$LIST" | awk -F "|" '{print $2}')
	VER_NEW=$(echo "$LIST" | awk -F "|" '{print $3}')
	
	echo "$LIST"
	#printf "%-25s | %-15s | %-15s\n" "$PKG" "$VER_OLD" "$VER_NEW"
}

function fn_get_package_upgradeble_formated(){
	

	#LIST=$( apt-get upgrade --assume-no -V | grep "^ ")
	LIST=$( apt-get upgrade --assume-no -V | grep "^ " | awk '{print $1"|"$2"|"$4}'| sed 's/[)(]//g')
	fn_line
	printf "%-45s | %-15s | %-15s\n" "Package" "From version" "To version"
	fn_line
	for I in $LIST; do
		PKG=$(echo "$I" | awk -F "|" '{print $1}')
		VER_OLD=$(echo "$I" | awk -F "|" '{print $2}')
		VER_NEW=$(echo "$I" | awk -F "|" '{print $3}')
	
	#echo "$LIST"
	printf "%-45s | %-15s | %-15s\n" "$PKG" "$VER_OLD" "$VER_NEW"
	done
	fn_line
}


function fn_locate_package_in_cve()
{
	# função para localizar se existe CVE para atualização de pacote
	PKG="$1"
	#cat "$CVE_DB_FILE" | grep "| $PKG " | head -n1 |sed 's/ //g'| awk -F "|" '{print $1" "$2" "$3" "$4" "$7}'
	RESULTADO=$(cat "$CVE_DB_FILE" | grep "| $PKG " | head -n1 | awk -F "|" '{print $1"|"$2"|"$3"|"$4"|"$7}')
	CVE=$(echo "$RESULTADO" | awk -F "|" '{print $1}'| sed 's/ //g')
	SEVERITY=$(echo "$RESULTADO" | awk -F "|" '{print $4}'| sed 's/ //g')
	PKG=$(echo "$RESULTADO" | awk -F "|" '{print $2}'| sed 's/ //g')
	VERSION=$(echo "$RESULTADO" | awk -F "|" '{print $3}'| sed 's/ //g')
	DESCRIPTION=$(echo "$RESULTADO" | awk -F "|" '{print $5}')
	
	if [ -n "$RESULTADO" ];then
		#echo "$RESULTADO"
		
		fn_line "_"
		printf "%10s | %-10s | %-25s | %-10s %s\n" "$CVE" "$SEVERITY" "$PKG" "$VERSION"
		#fn_line
		#printf "DESCRIPTION:%s \n" "$DESCRIPTION"
		fn_line
		return 0
	else
		return 1	
	fi
}

function fn_locate_package_in_cve_details()
{
	# função para localizar se existe CVE para atualização de pacote
	PKG="$1"
	#cat "$CVE_DB_FILE" | grep "| $PKG " | head -n1 |sed 's/ //g'| awk -F "|" '{print $1" "$2" "$3" "$4" "$7}'
	RESULTADO=$(cat "$CVE_DB_FILE" | grep "| $PKG " | head -n1 | awk -F "|" '{print $1"|"$2"|"$3"|"$4"|"$7}')
	CVE=$(echo "$RESULTADO" | awk -F "|" '{print $1}'| sed 's/ //g')
	SEVERITY=$(echo "$RESULTADO" | awk -F "|" '{print $4}'| sed 's/ //g')
	PKG=$(echo "$RESULTADO" | awk -F "|" '{print $2}'| sed 's/ //g')
	VERSION=$(echo "$RESULTADO" | awk -F "|" '{print $3}'| sed 's/ //g')
	DESCRIPTION=$(echo "$RESULTADO" | awk -F "|" '{print $5}')
	
	if [ -n "$RESULTADO" ];then
		#echo "$RESULTADO"
		
		fn_line "_"
		printf "%10s | %-10s | %-25s | %-10s %s\n" "$CVE" "$SEVERITY" "$PKG" "$VERSION"
		fn_line
		printf "DESCRIPTION:%s \n" "$DESCRIPTION"
		fn_line
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
		 apt-get download "$PKG"="$VERSION" 2> /dev/null
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



#===========================================================================
# ROLLBACK

function fn_execute_rollback()
{
	PKG_COLLECTION="$1"
	
	PKG_TO_PURGE=""
	PKG_TO_REINSTALL=""
	fn_line
	printf "%-45s | %-20s | %-15s\n" "Package" "From New version" "To Old version"
	fn_line
	for P in $PKG_COLLECTION; do
		
		PKG=$(echo "$P" | awk -F"|" '{print $1}' )
		VER_OLD=$(echo "$P" | awk -F"|" '{print $2}' )
		VER_NEW=$(echo "$P" | awk -F"|" '{print $3}' )
		
		PKG_TO_PURGE="${PKG_TO_PURGE} ${PKG}"
		PKG_TO_REINSTALL="${PKG_TO_REINSTALL}  ${PKG}=${VER_NEW}"
		printf "%-45s | %-20s | %-15s\n" "$PKG" "$VER_NEW" "$VER_OLD" 
	done
	fn_line
	
	read -p " WARNING - Rollback packages selected? (y/n) [n]: " RESP
	RESP=$(echo "${RESP:-"N"}")
	RESP=$(echo $RESP| tr [a-z] [A-Z])
		
	if [ $RESP = "Y" ]; then
		echo "apt-get -y purge $PKG_TO_PURGE"
		echo "apt-get -y install $PKG_TO_REINSTALL"
	else
		echo " Operation Canceled!"
		echo 
		echo " [ Press enter to view rollback list...] "
		echo
		#exit 1
		return 1 
	fi
	
	
}


function fn_menu_rollback()
{

	LISTA=$(tac "$APT_SEC_LOG" | awk -F "|" '{print $1" "$2}' | uniq -c | awk '{print $2" | "$3" " $4" | "$1 " Package(s)"}' | head -n "$ROLLBACK_LIMITE" )
	OLD_IFS=$' \t\n'
	IFS=$'\n'

	fn_line
	echo " ROLLBACK PACKAGES "
	fn_line
	echo -e " Select number from rollback list (new on top) - Limited to $ROLLBACK_LIMITE itens:\n"
	select OPT in $LISTA "Quit";  do
		case $OPT in
			Sair|Quit)
				#echo "$OPT option selected!" 
				echo "Finished!"
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
	-c|--cve)
		# Verificando a necessidade de invocar a coleta de dados de CVEs do Debian
		if [ -e "$FILE_CONTROL" ]; then
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
		
		apt-get update
		# Verificando se todos os pacotes atualizaveis possuem um CVE associado
		echo
		echo "::LIST PACKAGES WITH CVE::"
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
		
		if [ -n "$PKG_TO_UPDATE" ];then
			echo "apt-get install $PKG_TO_UPDATE"
			fn_generate_apt_log "$(date +%s)" "$PKG_COLLECTION"
		else
			echo "Not found packages with CVE"	
		fi
		;;
	-C|--cve-details)
		# Verificando a necessidade de invocar a coleta de dados de CVEs do Debian
		if [ -e "$FILE_CONTROL" ]; then
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
		
		apt-get update
		# Verificando se todos os pacotes atualizaveis possuem um CVE associado
		echo
		echo "::LIST PACKAGES WITH CVE - DETAILS::"
		LISTA=$(fn_get_package_upgradeble)
		for ITEM in $LISTA; do
			#echo "ITEM: $ITEM"
			PKG=$(echo "$ITEM" | awk -F "|" '{print $1}')
			VER_OLD=$(echo "$ITEM" | awk -F "|" '{print $2}')
			VER_NEW=$(echo "$ITEM" | awk -F "|" '{print $3}')
			
			#echo "PKG: $PKG, VER_OLD: $VER_OLD, VER_NEW: $VER_NEW "   #DEBUG
			fn_locate_package_in_cve_details "$PKG"
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
		
		if [ -n "$PKG_TO_UPDATE" ];then
			echo "apt-get install $PKG_TO_UPDATE"
			fn_generate_apt_log "$(date +%s)" "$PKG_COLLECTION"
		else
			echo "Not found packages with CVE"	
		fi
		;;	
		
	-a|--all)
		 apt-get update
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
		apt-get update
		echo 
		echo ":: LIST ALL PACKAGES UPGRADEBLE ::"
		fn_get_package_upgradeble_formated	
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
fn_requiriments
fn_main "$1"

#fn_get_packages_cve "$1"
#fn_get_cve

#echo Nome: "$PACKAGE_NAME"
#echo Versão: "$VERSION"
#echo Severidade: "$SEVERITY"
#echo Descrição: "$DESCRIPTION"

# fn_verify_package "$PACKAGE_NAME" "$VERSION"

