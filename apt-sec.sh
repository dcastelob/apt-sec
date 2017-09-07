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
export EXPIRED="60"
export CVE_DB_FILE="/tmp/apt-sec.cvedb"
export TMP_DIR="/tmp"

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
	# Função que verifica se o usuário tem privilegios de superusuário 
		
	ID=$(id -u) 
	if [ "$ID" -ne 0 ]; then
		echo "Permission Denied to execute:"
		echo "Use: sudo $0 $@"
		exit 99
	fi
}


function fn_line()
{
	# Função acessória que gera um linha
	
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
	echo " -s|--summary      - List summary for packages upgradable urgency based"
	echo " -u|--urgency      - List all packages upgradable with urgency"
	echo " -a|--all          - Secure update for all packages upgradable"
	echo " -c|--cve          - Secure update only packages with CVE associated"
	echo " -C|--cve-details  - Secure update only packages with CVE associated detailed"
	echo " -R|--rollback     - Execute rollback old packages"
	echo
	
}


function fn_verify_expired()
{
	# Função acessório que verifica se o tempo de espera para coleta de dados foi excedido 
	
	if [ -e "$FILE_CONTROL" ]; then
		ULTIMO=$(cat "$FILE_CONTROL")
		ATUAL=$(date +%s)
		if [ $(($ATUAL-$ULTIMO)) -gt "$EXPIRED" ];then
			# tempo maior que expirado
			return 0
		else
			return 1	
		fi		
	else
		return 0
	fi
}


function fn_update_time()
{
	date +%s > "$FILE_CONTROL"
}


function fn_get_urgency_upgradable_data()
{
	# Função que coleta dos dados de urgencia a partir dos changelogs dos pacotes e salva a relação em um arquivo temporário
	
	
	apt-get update
	RELACAO=""
	for PKG in $(apt-get upgrade -V --assume-no | grep "^ " | awk '{print $1}'); do
		#echo "Pacote $PKG"
		VAL="$PKG : "
		#fn_line
		export PAGER=cat
		RESULTADO=$(aptitude changelog "$PKG" 2>/dev/null)
		#echo "$RESULTADO"| head -n10
		
		RESP="$?"
		if [ -z "$RESULTADO" ];then
			VAL="${VAL}Not found change log for package $PKG; urgency=unknown"
		fi
		#echo "RESP: $RESP"
		if [ "$RESP" -eq 0 ];then
			VAL=${VAL}$(echo "$RESULTADO"| head -n2 | tail -n1)			
		else
			VAL=${VAL}$(echo "$PKG; urgency=unknown")
		fi
		RELACAO="${RELACAO}${VAL}\n"
	done
	echo -e "$RELACAO" | sort -t ";" -k 2 | uniq | grep -v ^$ > "$TMP_DIR"/resume_chagelog
	
	if [ -e "$TMP_DIR"/resume_chagelog ]; then
		return 0
	else
		return 1
	fi
}

function fn_get_urgency_upgradable()
{
	# Função que apresenta os pacotes a serem atualizados com as informações de urgência
	
	fn_verify_expired
	RESP="$?"
	
	if [ "$RESP" -eq 0  ]; then
		# tempo maior que expirado
		echo "[info] Tempo expirado"
		rm -f "$TMP_DIR"/resume_chagelog
		fn_get_urgency_upgradable_data && fn_update_time
	fi
	
	if [ -e "$TMP_DIR"/resume_chagelog ]; then
		echo
		echo " :: LIST ALL PACKAGES UPGRADEBLE - URGENCY ::"
		echo 
		fn_line
		printf "%-10s  | %-50s\n" " URGENCY" "PACKAGE (Version) - Channel"
		fn_line
		IFS_OLD="$IFS"
		IFS=$'\n'
		for PKG in $(cat "$TMP_DIR"/resume_chagelog);do
			P=$(echo $PKG | awk -F";" '{print $1}')
			URGENCY=$(echo $PKG | awk -F";" '{print $2}'| cut -d "=" -f2)
			printf " %-10s | %-50s\n" "$URGENCY" "$P"
		done
		fn_line
		IFS="$IFS_OLD"
	else
		fn_get_urgency_upgradable_data
		RESP="$?"
		if [ "$RESP" -eq 0 ];then
			fn_get_urgency_upgradable
		fi
	fi
}


function fn_get_urgency_upgradable_summary()
{
	# Função que apresenta um sumário dos pacotes por urgência
	
	fn_verify_expired
	RESP="$?"
	if [ "$RESP" -eq 0  ]; then
		# tempo maior que expirado
		echo "[info] Tempo expirado"
		rm -f "$TMP_DIR"/resume_chagelog
		fn_get_urgency_upgradable_data && fn_update_time
	fi
	
	if [ -e "$TMP_DIR"/resume_chagelog ]; then
		echo
		echo " :: SUMMARY OF PACKAGES UPGRADEBLE - URGENCY ::"
		echo 
		fn_line
		printf " %-10s | %-50s\n" "TOTAL" "URGENCY"
		fn_line
		IFS_OLD="$IFS"
		IFS=$'\n'
		for U in $(cat /tmp/resume_chagelog | cut -d";" -f2 | uniq );do
			TOTAL_PKG=$(cat "$TMP_DIR"/resume_chagelog | grep "$U" | wc -l)
			URGENCY=$(echo "$U" | cut -d"=" -f2)
			printf " %-10s | %-50s\n" "$TOTAL_PKG" "Packages in $URGENCY" 
		done
		fn_line
		IFS="$IFS_OLD"
	else
		fn_get_urgency_upgradable_data
		RESP="$?"
		if [ "$RESP" -eq 0 ];then
			fn_get_urgency_upgradable_sumary
		fi
	fi
}


function fn_generate_apt_log()
{
	# Função que gera o log das operações realizadas
	
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
	
#	CVE="$1"
#	#VALOR=$(curl --silent https://security-tracker.debian.org/tracker/"$CVE" 2>&1 |sed -e 's/<[tr]*>/\n/g'|sed -e 's/<[^>]*>/ /g'|  grep "$CODENOME" | grep -v "(unfixed)"| tail -n1)
#	VALOR=$(curl --silent https://security-tracker.debian.org/tracker/"$CVE" 2>&1 |sed -e 's/<[tr]*>/\n/g'|sed -e 's/<[^>]*>/ /g')
	
#	if [ -z "$VALOR" ];then
#		echo "Sem resultado"
#	else
#		#echo resultado #"$VALOR"
#		export PACKAGE_NAME=$(echo "$VALOR"| grep -A1 "^ Package" | tail -1 | awk '{print $1}')
#		export SEVERITY=$(echo "$VALOR"| grep -i "severity" | awk '{print $3}')
#		export VERSION=$(echo "$VALOR"|  grep "$CODENOME" | grep "fixed" | awk '{print $3}' | tail -n1)
#		export DESCRIPTION=$(echo "$VALOR"| grep -i "Description" | sed 's/ Description//')	
#	fi
	
	fn_verify_expired
	RESP="$?"
	
	if [ "$RESP" -eq 0  ]; then
		# tempo maior que expirado
		echo "[info] Base de CVE expirada"
		fn_get_cve_db && fn_update_time
	fi
	apt-get update
	# Verificando se todos os pacotes atualizaveis possuem um CVE associado
	echo
	echo " :: LIST PACKAGES WITH CVE :: "
	echo 
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
		
}


function fn_get_packages_cve_details()
{
	fn_verify_expired
	RESP="$?"
	
	if [ "$RESP" -eq 0  ]; then
		# tempo maior que expirado
		echo "[info] Base de CVE expirada"
		fn_get_cve_db && fn_update_time
	fi
	apt-get update
	# Verificando se todos os pacotes atualizaveis possuem um CVE associado
	echo
	echo " :: LIST PACKAGES WITH CVE - DETAILS :: "
	echo 
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
}


function fn_get_packages_dsa()
{
	#DESATIVADA
	DSA="$1"
	VALOR=$(curl --silent https://security-tracker.debian.org/tracker/"$DSA" 2>&1 |sed -e 's/<[tr]*>/\n/g'|sed -e 's/<[^>]*>/ /g'|  grep "$CODENOME" | grep -v "(unfixed)"| tail -n1)
	if [ -z "$VALOR" ];then
		echo "Sem resultado"
	else
		echo "$VALOR"	
	fi
}


function fn_get_package_upgradeble()
{
	# Função que gera uma lista simples de pacotes atualizáveis	

	#LIST=$( apt-get upgrade --assume-no -V | grep "^ ")
	LIST=$( apt-get upgrade --assume-no -V | grep "^ " | awk '{print $1"|"$2"|"$4}'| sed 's/[)(]//g')
	
	PKG=$(echo "$LIST" | awk -F "|" '{print $1}')
	VER_OLD=$(echo "$LIST" | awk -F "|" '{print $2}')
	VER_NEW=$(echo "$LIST" | awk -F "|" '{print $3}')
	
	echo "$LIST"
	#printf "%-25s | %-15s | %-15s\n" "$PKG" "$VER_OLD" "$VER_NEW"
}


function fn_upgrade_all ()
{
	apt-get update
	echo 
	echo " :: UPGRADE ALL PACKAGES :: "
	echo
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
}


function fn_get_package_upgradeble_formated(){
	
	# Função que gera uma lista formatada de pacotes atualizáveis	
	
	apt-get update
	echo 
	echo " :: LIST ALL PACKAGES UPGRADEBLE :: "
	echo
	
	#LIST=$( apt-get upgrade --assume-no -V | grep "^ ")
	LIST=$( apt-get upgrade --assume-no -V | grep "^ " | awk '{print $1"|"$2"|"$4}'| sed 's/[)(]//g')
	fn_line
	printf " %-45s | %-25s | %-25s\n" "PACKAGE" "FROM VERSION" "TO VERSION"
	fn_line
	for I in $LIST; do
		PKG=$(echo "$I" | awk -F "|" '{print $1}')
		VER_OLD=$(echo "$I" | awk -F "|" '{print $2}')
		VER_NEW=$(echo "$I" | awk -F "|" '{print $3}')
	
	#echo "$LIST"
	printf " %-45s | %-25s | %-25s\n" "$PKG" "$VER_OLD" "$VER_NEW"
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



#===========================================================================
# ROLLBACK FUCNTIONS
#===========================================================================


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




#===========================================================================
# FUNCÃO PRINCIPAL
#===========================================================================


function fn_main()
{
	
	OPT="$1"
	
	# Verifca se é root
	fn_isRoot
			
		
	case $OPT in
		-c|--cve)
			# Verificando a necessidade de invocar a coleta de dados de CVEs do Debian
			fn_get_packages_cve		
			;;
		-C|--cve-details)
		
			# Verificando a necessidade de invocar a coleta de dados de CVEs do Debian
			fn_get_packages_cve_details
			;;	
		
		-a|--all)
			fn_upgrade_all
			;;	
		
		-l|--list)
			fn_get_package_upgradeble_formated	
			;;
		
		-s|--summary)	
			fn_get_urgency_upgradable_summary
			;;
		
		-u|--urgency)	
			fn_get_urgency_upgradable
			;;
		
		-R|--rollback)
			fn_menu_rollback
			;;
	
		-h|--help)
			fn_usage
			;;
	
		*)
			fn_usage
			;;	
	esac  
	
}

# inicio do script
fn_requiriments
fn_main "$1"


