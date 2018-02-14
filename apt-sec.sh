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


###############################################################################
# VARIAVEIS DE CONTROLE
#############################################################################
#export LANG=en_US.UTF-8
export VERBOSE=no

export FILE_CONTROL="/tmp/apt-sec.ctrl"
export EXPIRED_CVE="600"
export EXPIRED_UPDATE="3600"

export CVE_DB_FILE="/tmp/apt-sec.cvedb"
export TMP_DIR="/tmp"

export ROLLBACK_PKG_DIR="/var/cache/apt/rollback"
export ROLLBACK_PKG_DIR_OWNER="root"
export APT_SEC_LOG="/var/log/apt-sec.log"

export ROLLBACK_LIMITE=5
export CVE_DB_LIMITE=10000


###############################################################################
# FUNCOES ASSESSÓRIAS
###############################################################################

function fn_requiriments()
{

	COUNT=0
	PKG=""
	which psql &> /dev/null
	if [ "$?" -ne 0 ];then
		fn_msg "[FAIL] Command 'psql' not found."
		PKG="${PKG}postgresql-client "
		COUNT=$(($COUNT+1))
	fi
	which lsb_release &> /dev/null
	if [ "$?" -ne 0 ];then
		fn_msg "[FAIL] Command 'lsb_release' not found."
		PKG="${PKG}lsb-release "
		COUNT=$(($COUNT+1))
	else
		export CODENOME=$(lsb_release -c | awk '{print $2}')

	fi

	which column &> /dev/null
	if [ "$?" -ne 0 ];then
		fn_msg "[FAIL] Command 'column' not found."
		PKG="${PKG}bsdmainutils "
		COUNT=$(($COUNT+1))
	fi

	which aptitude &> /dev/null
	if [ "$?" -ne 0 ];then
		fn_msg "[FAIL] Command 'aptitude' not found."
		PKG="${PKG}aptitude "
		COUNT=$(($COUNT+1))
	fi

	if [ "$COUNT" -ne 0 ];then
		fn_msg "[INFO] Verify requiriments..."
		fn_msg "[FAIL] Packages pendents"
		fn_msg "apt-get update && apt-get -y install $PKG"
		exit 1
	fi

}


function fn_verifyRepeat()
{
	# Função que verifica se um item ja existe na coleção
	# Sintaxe: fn_verifyRepeat COLECAO ITEM

	COLLECTION="$1"
	ITEM="$2"
	for I in $COLLECTION; do
		if [ "$ITEM" == "$I" ];then
			#echo "$ITEM == $I"
			return 0
		else
			continue	
		fi
	done
	return 1

}
		

function fn_isRoot()
{
	# Função que verifica se o usuário tem privilegios de superusuário

	ID=$(id -u)
	if [ "$ID" -ne 0 ]; then
		fn_msg "[ERROR] Permission denied!"
		echo " Usage: sudo $0 $@"
		exit 99
	fi
}

function fn_msg()
{
	# Função para apresentação de notificações no terminal de forma colorida

	TIPO=$(echo "$1"| grep -oiE "FAIL|ERROR|INFO")
	#echo "${TIPO}"
	case $TIPO in
		FAIL|ERROR)
		echo -e "\033[01;31m${1}\033[00;37m"
		;;
		"INFO")
		echo -e "\033[01;34m${1}\033[00;37m"
		;;
		*)
		echo -e "\033[01;33m${1}\033[00;37m"
		;;
	esac
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

function fn_titulo()
{
	fn_msg="$1"
	fn_line
	#echo
	echo " :: $fn_msg :: "
	#echo
	fn_line
}

function fn_get_terminal_size()
{
	echo $(($(tput cols)-2))
}

function fn_usage()
{
	echo "Usage: $0 <option>"
	echo "Options:"
	echo " -h|--help         - Help commands"
	echo " -l|--list         - List all packages upgradable"
	echo " -s|--summary      - List summary for packages upgradable urgency based"
	echo " -u|--urgency      - List all packages upgradable with urgency"
	echo " -c|--cve-list     - List only packages with CVE associated"
	echo " -a|--all          - Secure update for all packages upgradable"
	echo " -C|--cve-update   - Secure update only packages with CVE associated detailed"
	echo " -R|--rollback     - Execute rollback old packages"
	echo " --renew-cache     - Renew cache for temp files"
	
	echo

}


function fn_generate_apt_log()
{
	# Função acessório que gera o log das operações realizadas

	DATE="$1"
	#DATE_EVENT=$(date "+%x %T")
	DATE_EVENT="$2"
	PKG_COLLECTION="$3"
	ROLLBACK_ENABLE="$4"

	for I in $PKG_COLLECTION; do
		echo "$DATE|$DATE_EVENT|$ROLLBACK_ENABLE|$I" >> "$APT_SEC_LOG"
	done
}

function fn_get_timestamp_begin()
{
	export TIMESTAMP_BEGIN=$(date +%s)
}

function fn_get_timestamp_end()
{
	TIMESTAMP_END=$(date +%s)
	if [ -n "$TIMESTAMP_BEGIN" ];then
		echo " Elapsed time: $(( $TIMESTAMP_END -$TIMESTAMP_BEGIN  )) seconds"
	fi
}


function fn_verify_expired()
{
	# Função acessório que verifica se o tempo de espera para coleta de dados foi excedido
	OPTION="$1"
	ATUAL=$(date +%s)

	if [ -e "$FILE_CONTROL" ]; then
		ULTIMO=$(cat "$FILE_CONTROL" | grep "$OPTION" | awk -F"=" '{print $2}')

		OPTION=$(echo "$OPTION" | tr "a-z" "A-Z")
		case "$OPTION" in
		CVE)
			EXPIRED="${EXPIRED_CVE}"
			;;
		UPDATE)
			EXPIRED="${EXPIRED_UPDATE}"
			;;
		esac

		if [ $(($ATUAL-$ULTIMO)) -gt "$EXPIRED" ];then
			# tempo maior que expirado
			#echo "Valor: OPTION: $OPTION e ULTIMO: $ULTIMO, DIF:$(($ATUAL-$ULTIMO)),  EXPIRED: $EXPIRED"
			return 0
		else
			return 1
		fi
	else
		# inicializando o arquivo de controle caso ele não exista
		echo "cve=$ATUAL" > "$FILE_CONTROL"
		echo "update=$ATUAL" >> "$FILE_CONTROL"
		return 0
	fi
}


function fn_update_time()
{
	# Função de autualiza o timestemp no arquivo de controle de expiração para a opção deseja
	OPTION="$1"
	NEW_TIME=$(date +%s)

	OPTION=$(echo "$OPTION" | tr "a-z" "A-Z")
	case "$OPTION" in
		CVE)
			 sed -i "s/cve=.*/cve=$NEW_TIME/" "$FILE_CONTROL"
			;;
		UPDATE)
			sed -i "s/update=.*/update=$NEW_TIME/" "$FILE_CONTROL"
			;;
	esac
}

function fn_aptget_update()
{
	fn_verify_expired "update"
	RESP="$?"

	if [ "$RESP" -eq 0  ]; then
		# tempo maior que expirado
		fn_msg "[INFO] apt-get update time expired..."
		VERBOSE=$(echo "$VERBOSE" | tr "a-z" "A-Z")
		fn_msg "[INFO] Update apt base (apt-get update) - Verbose Mode: $VERBOSE"
		case "$VERBOSE" in
			YES|1|TRUE)
				apt-get update
				fn_update_time "update"
				;;
			*)
				apt-get update &> /dev/null
				fn_update_time "update"
				;;
		esac
	fi
}


###############################################################################
# FUNCOES DE LOCALIZACAO
###############################################################################


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

		#fn_line "_"
		#printf "%10s | %-10s | %-25s | %-10s %s\n" "$CVE" "$SEVERITY" "$PKG" "$VERSION"
		echo "$CVE|$SEVERITY|$PKG|$VERSION|$DESCRIPTION"
		#fn_line
		#printf "DESCRIPTION:%s \n" "$DESCRIPTION"
		#fn_line
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



###############################################################################
# FUNCOES DE CONSULTA
###############################################################################


function fn_get_package_upgradeble()
{
	# Função que gera uma lista simples de pacotes atualizáveis

	LIST=$( apt-get upgrade --assume-no -V | grep "^ " | awk '{print $1"|"$2"|"$4}'| sed 's/[)(]//g')

	PKG=$(echo "$LIST" | awk -F "|" '{print $1}')
	VER_OLD=$(echo "$LIST" | awk -F "|" '{print $2}')
	VER_NEW=$(echo "$LIST" | awk -F "|" '{print $3}')

	echo "$LIST"
	#printf "%-25s | %-15s | %-15s\n" "$PKG" "$VER_OLD" "$VER_NEW"
}


function fn_get_all_package_upgradeble()
{
	# Função que gera uma lista simples de TODOS os pacotes atualizáveis

	# Lista de todos os pacotes e metadados
	LIST=$( apt-get upgrade --assume-no -V | grep "^ " | awk '{print $1"|"$2"|"$4"|UPGRADABLE"}'| sed 's/[)(]//g')

	# Lista apenas de todos os nomes de pacotes (utilizados para evitar repetições)
	ALL_PKGS=$(echo "$LIST"|awk -F"|" '{print $1}')

	PKG_COLLECTION=""
	#echo "$LIST"
	for I in $LIST; do
		PKG=$(echo "$I" | awk -F "|" '{print $1}')
		LIST_DEP=$(apt-get install "$PKG" -V --assume-no | egrep -A1000 "The following packages|Os pacotes a seguir"| grep "^ "| grep -v " ${PKG} " | awk '{print $1"|"$2"|"$4"|IS-DEPENDENCY"}' | sed 's/[)(]//g')
		#echo "Lista DEP: $LIST_DEP"
		
		fn_verifyRepeat "$ALL_PKGS" "$PKG"
		if [ "$?" -eq 1 ]; then
			LIST_DEP=$(echo "${LIST_DEP}" | egrep -v "^${PKG}\|")
			PKG_COLLECTION=$(echo -e "${PKG_COLLECTION}\n${LIST_DEP}")	
		fi 
	done

	PKG_COLLECTION=$(echo -e "${PKG_COLLECTION}\n${LIST}")

	echo "$PKG_COLLECTION" | sort -t"|" -k1 | uniq
}


function fn_list_package_upgradeble_formated(){

	# Função que gera uma lista formatada de pacotes atualizáveis

	fn_get_timestamp_begin
	fn_msg "[INFO] List all packages and depenedencies. It may take a few minutes."

	# Obtendo informações do terminal para dimensionamento das colunas da tabela de resulatados
	COL_FROM=$(( $(fn_get_terminal_size) / 4 ))
	COL_TO=${COL_FROM}
	#echo "COL_FROM: $COL_FROM e COL_TO: $COL_TO"   #DEBUG

	fn_aptget_update

	fn_titulo "LIST ALL PACKAGES UPGRADEBLE"

	LIST=$(fn_get_all_package_upgradeble)
	fn_line
	#printf " %-45s | %-25s | %-25s\n" "PACKAGE" "FROM VERSION" "TO VERSION"
	printf " %-45s | %-${COL_FROM=}s | %-${COL_TO=}s\n" "PACKAGE" "FROM VERSION" "TO VERSION"
	COUNT=0
	fn_line
	for I in $LIST; do
		COUNT=$(($COUNT+1))
		PKG=$(echo "$I" | awk -F "|" '{print $1}')
		VER_OLD=$(echo "$I" | awk -F "|" '{print $2}')
		VER_NEW=$(echo "$I" | awk -F "|" '{print $3}')
		OPERACAO=$(echo "$I" | awk -F "|" '{print $4}')
		PKG="$PKG ($OPERACAO)"

		#echo "$I"
		printf " %-45s | %-${COL_FROM=}s | %-${COL_TO=}s\n" "$PKG" "$VER_OLD" "$VER_NEW"
	done
	fn_line

	echo " $COUNT - Packages to update"
	fn_get_timestamp_end

	fn_line

	if [ -n "$LIST" ]; then
		return 0
	else
		return 1
	fi
}


function fn_get_urgency_upgradable_data()
{
	# Função que coleta dos dados de urgencia a partir dos changelogs dos pacotes e salva a relação em um arquivo temporário

	fn_aptget_update
	

	#export LANG="pt_BR.UTF-8"
	RELACAO=""
	#for PKG in $(apt-get upgrade -V --assume-no | grep "^ " | awk '{print $1}'); do
	for PKG in $(fn_get_all_package_upgradeble | awk -F "|" '{print $1}'); do
		#echo "PKG: $PKG"
		VAL="$PKG : "
		#fn_line
		export PAGER=cat
		RESULTADO=$(aptitude changelog "$PKG" 2>/dev/null)
		#echo "$RESULTADO"| head -n10

		RESP="$?"
		if [ -z "$RESULTADO" ];then
			VAL="${VAL}Not found changelog for package $PKG; urgency=unknown"
		fi
		#echo "RESP: $RESP"
		echo "$RESULTADO"| grep -i "^Err" &>/dev/null
		ERROR=$?
		if [  "$ERROR" -eq 0 ];then
			VAL=${VAL}$(echo "$PKG; urgency=unknown")
		elif [ "$RESP" -eq 0 ];then
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

	fn_get_timestamp_begin

	fn_verify_expired "cve"
	RESP="$?"

	if [ "$RESP" -eq 0  ]; then
		# tempo maior que expirado
		fn_msg "[INFO] Time out. CVE expired. Get data now"
		rm -f "$TMP_DIR"/resume_chagelog

		# obtendo dados de changelog para extração da urgencia
		fn_get_urgency_upgradable_data && fn_update_time "cve"
	fi

	if [ -e "$TMP_DIR"/resume_chagelog ]; then

		fn_titulo "LIST ALL PACKAGES UPGRADEBLE - URGENCY"

		fn_line
		printf "%-10s  | %-50s\n" " URGENCY" "PACKAGE (Version) - Channel"
		fn_line
		IFS_OLD="$IFS"
		IFS=$'\n'
		COUNT=0
		for PKG in $(cat "$TMP_DIR"/resume_chagelog);do
			COUNT=$(($COUNT+1))
			P=$(echo $PKG | awk -F";" '{print $1}')
			URGENCY=$(echo $PKG | awk -F";" '{print $2}'| cut -d "=" -f2)
			printf " %-10s | %-50s\n" "$URGENCY" "$P"
		done
		fn_line

		echo " $COUNT - Packages to update"
		fn_get_timestamp_end

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


function fn_list_urgency_upgradable_summary()
{
	# Função que apresenta um sumário dos pacotes por urgência

	fn_get_timestamp_begin
	fn_msg "[INFO] List all packages and depenedencies. It may take a few minutes."

	# Verificando se o tempo de consulta do CVE expirou
	fn_verify_expired "cve"
	RESP="$?"
	if [ "$RESP" -eq 0  ]; then
		# tempo maior que expirado
		fn_msg "[INFO] Time out for CVE. Get data, it may take a few minutes."
		rm -f "$TMP_DIR"/resume_chagelog

		# Realizando o download dos changelogs dos pacotes para extração da urgencia.
		fn_get_urgency_upgradable_data && fn_update_time "cve"
	fi

	if [ -e "$TMP_DIR"/resume_chagelog ]; then

		fn_titulo "SUMMARY OF PACKAGES UPGRADEBLE - URGENCY"

		printf " %-10s | %-50s\n" "TOTAL" "URGENCY"
		fn_line
		IFS_OLD="$IFS"
		IFS=$'\n'
		COUNT=0
		for U in $(cat /tmp/resume_chagelog | cut -d";" -f2 | uniq );do
			TOTAL_PKG=$(cat "$TMP_DIR"/resume_chagelog | grep "$U" | wc -l)
			COUNT=$(($COUNT+$TOTAL_PKG))
			URGENCY=$(echo "$U" | cut -d"=" -f2)
			printf " %03d        | %-50s\n" "$TOTAL_PKG" "Packages in $URGENCY"
		done
		fn_line

		echo " $COUNT - Packages to update"
		fn_get_timestamp_end

		fn_line
		IFS="$IFS_OLD"
	else
		fn_get_urgency_upgradable_data
		RESP="$?"
		if [ "$RESP" -eq 0 ];then
			fn_list_urgency_upgradable_summary
		fi
	fi
}


function fn_download_cve_db()
{
	# Função que coleta a base de CVEs atualizada e guarda localmente, obedecendo o tempo de expiração.
	RELEASE="$1"
	fn_msg "[INFO] Collect CVE database, wait..."

	if [ -n "$RELEASE" ];then
		export PGPASSWORD=udd-mirror && psql --host=udd-mirror.debian.net --user=udd-mirror udd -c "select s1.issue, s1.source, s1.fixed_version, s1.urgency, s1.release, s1.status, s2.description from public.security_issues_releases as s1 inner join public.security_issues as s2 on (s1.issue = s2.issue) where s1.release='$RELEASE' and s1.status='resolved' and s1.issue like 'CVE%' order by s1.issue desc limit $CVE_DB_LIMITE;" > "$CVE_DB_FILE"
	else
		export PGPASSWORD=udd-mirror && psql --host=udd-mirror.debian.net --user=udd-mirror udd -c "select s1.issue, s1.source, s1.fixed_version, s1.urgency, s1.release, s1.status, s2.description from public.security_issues_releases as s1 inner join public.security_issues as s2 on (s1.issue = s2.issue) where s1.release='stretch' and s1.status='resolved' and s1.issue like 'CVE%' order by s1.issue desc limit $CVE_DB_LIMITE;" > "$CVE_DB_FILE"
	fi
	#cat "$CVE_DB_FILE"
}


function fn_list_package_upgradeble_cve_formated()
{

	# Função que gera uma lista formatada de pacotes atualizáveis que possuem CVE associado

	fn_get_timestamp_begin

	FORMAT="$1"

	fn_verify_expired "cve"
	RESP="$?"

	if [ "$RESP" -eq 0  ]; then
		# tempo maior que expirado
		fn_msg "[INFO] CVE base expired"

		# obtendo dados do UDD
		fn_download_cve_db "$CODENOME" && fn_update_time "cve"
	fi

	if [ ! -e "$CVE_DB_FILE" ]; then
		fn_msg "[INFO] CVE file not found"

		# obtendo dados do UDD
		fn_download_cve_db "$CODENOME" && fn_update_time "cve"
	fi
	
	fn_aptget_update

	fn_titulo "LIST ALL PACKAGES UPGRADEBLE - CVE"
	
	LIST=$(fn_get_all_package_upgradeble)

	if [ -z "$LIST" ];then
		fn_msg "[INFO] Packges from CVE file not found"
		exit 0
	fi
	COUNT=0

	printf " %-16s | %-16s | %-25s | %-10s %s\n" "CVE              " "SEVERITY" "PACKAGE" "VERSION"
	fn_line

	for I in $LIST; do

		PKG=$(echo "$I" | awk -F "|" '{print $1}')

		RESULTADO=$(fn_locate_package_in_cve "$PKG")
		RESP="$?"
		if [ "$RESP" -eq 0 ]; then
			COUNT=$(($COUNT+1))
			CVE=$(echo "$RESULTADO" | awk -F "|" '{print $1}'| sed 's/ //g')
			SEVERITY=$(echo "$RESULTADO" | awk -F "|" '{print $2}'| sed 's/ //g')
			PKG=$(echo "$RESULTADO" | awk -F "|" '{print $3}'| sed 's/ //g')
			VERSION=$(echo "$RESULTADO" | awk -F "|" '{print $4}'| sed 's/ //g')
			DESCRIPTION=$(echo "$RESULTADO" | awk -F "|" '{print $5}')

			case "$FORMAT" in
				detail)
					printf " %-16s | %-16s | %-25s | %-10s \n" "$CVE" "$SEVERITY" "$PKG" "$VERSION"
					fn_line
					printf " DESCRIPTION: %-s \n" "$DESCRIPTION"
					fn_line "="
					;;
				*)
					printf " %-16s | %-16s | %-25s | %-10s %s\n" "$CVE" "$SEVERITY" "$PKG" "$VERSION"
					;;
			esac
		fi
	done
	fn_line

	echo " $COUNT - Packages to update"
	fn_get_timestamp_end

	fn_line

	if [ "$COUNT" -ne 0  ]; then
		return 0
	else
		return 1
	fi
}



function fn_get_packages_dsa()
{
	# DESATIVADA
	DSA="$1"
	VALOR=$(curl --silent https://security-tracker.debian.org/tracker/"$DSA" 2>&1 |sed -e 's/<[tr]*>/\n/g'|sed -e 's/<[^>]*>/ /g'|  grep "$CODENOME" | grep -v "(unfixed)"| tail -n1)
	if [ -z "$VALOR" ];then
		echo "Sem resultado"
	else
		echo "$VALOR"
	fi
}



###############################################################################
# FUNCOES DE UPDATE
###############################################################################

function fn_upgrade_all ()
{
	#apt-get update
	fn_aptget_update

	fn_titulo "UPGRADE ALL PACKAGES"

	# Atualizando todos os pacotes que obtiveram sucesso no download
	PKG_COLLECTION=""
	PKG_COLLECTION_FAIL=""
	PKG_TO_UPDATE=""
	PKG_TO_UPDATE_FAIL=""
	PKG_TO_UPDATE_FAIL_fn_msg=""


	fn_list_package_upgradeble_formated
	RESP="$?"
	if [ "$RESP" -eq 0 ];then
		echo
		read -p "[QUESTION] Secure upgrade all packages from list? (y/n) [n]: " RESP
	    RESP=$(echo "${RESP:-"N"}")
    	RESP=$(echo $RESP| tr [a-z] [A-Z])

    	echo
    	case $RESP in
			Y|S)
				# sim
				fn_msg "[INFO] Inittiate download for actually version for rollback operations..."
				;;

			N)
				# não
				fn_msg "[FAIL] Operation aborted!"
				exit 1
				;;

			*)
				fn_msg "[ERROR] Invalid option"
				fn_msg "[ERROR] Operation aborted!"
				exit 1
				;;
		esac
	else
		fn_msg "[ERROR] No packages to update"
		exit 0

	fi

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
			PKG_COLLECTION=$(echo -e "${PKG_COLLECTION}\n${ITEM}")
		else
			# pacotes que não foi possivel realizar o download de pacotes atualmente instalados para possível rollback
			PKG_TO_UPDATE_FAIL="${PKG_TO_UPDATE_FAIL} ${PKG}"
			PKG_TO_UPDATE_FAIL_fn_msg="${PKG_TO_UPDATE_FAIL_fn_msg} ${PKG}=${VER_OLD}"
			PKG_COLLECTION_FAIL=$(echo -e "${PKG_COLLECTION_FAIL}\n${ITEM}")
		fi
	done

	OPERACAO_TIMESTAMP=$(date +%s)
	OPERACAO_DATA=$(date "+%x %T")

	if [ -n "$PKG_TO_UPDATE_FAIL" ];then
		echo
		fn_msg "[ERROR] Packages not found actually version to garant rollback!"
		fn_msg "[ERROR] Packages: $PKG_TO_UPDATE_FAIL_fn_msg"
		echo

		read -p "[QUESTION] Existem pacotes que não podemos garantir o rollback. Deseja prosseguir mesmo assim? (y/n/a) [a]: " RESP
	    RESP=$(echo "${RESP:-"A"}")
    	RESP=$(echo $RESP| tr [a-z] [A-Z])

    	echo
    	case $RESP in
			Y|S)
				# sim
				fn_msg "[INFO] Segue com pacotes sem suporte a Rollback"
				#echo "Pacotes válidos: $PKG_TO_UPDATE"
				#echo "Pacotes inválidos: $PKG_TO_UPDATE_FAIL"
				## Juntando todos os
				#ALL_COLLECTION=$(echo -e "${PKG_COLLECTION}\n${PKG_COLLECTION_FAIL}")

				for ITEM in $PKG_COLLECTION; do
					PKG=$(echo "$ITEM" | awk -F "|" '{print $1}')
					VER_OLD=$(echo "$ITEM" | awk -F "|" '{print $2}')
					VER_NEW=$(echo "$ITEM" | awk -F "|" '{print $3}')
					echo "apt-get install -y "$PKG""
					apt-get install -y "$PKG"

					RESP="$?"
					if [ "$RESP" -eq 0 ]; then
						fn_generate_apt_log "$OPERACAO_TIMESTAMP" "$OPERACAO_DATA" "$ITEM" "ROLLBACK-ON"
					fi
				done

				for ITEM in $PKG_COLLECTION_FAIL; do
					PKG=$(echo "$ITEM" | awk -F "|" '{print $1}')
					VER_OLD=$(echo "$ITEM" | awk -F "|" '{print $2}')
					VER_NEW=$(echo "$ITEM" | awk -F "|" '{print $3}')
					echo "apt-get install -y "$PKG""
					apt-get install -y "$PKG"
					RESP="$?"
					if [ "$RESP" -eq 0 ]; then
						fn_generate_apt_log "$OPERACAO_TIMESTAMP" "$OPERACAO_DATA" "$ITEM" "ROLLBACK-OFF"
					fi
				done

				;;

			N)
				# não
				echo "Segue apenas com os pacotes com suporte a Rollback"
				#echo "Pacotes válidos: $PKG_TO_UPDATE"

				for ITEM in $PKG_COLLECTION; do
					PKG=$(echo "$ITEM" | awk -F "|" '{print $1}')
					VER_OLD=$(echo "$ITEM" | awk -F "|" '{print $2}')
					VER_NEW=$(echo "$ITEM" | awk -F "|" '{print $3}')
					echo "apt-get install "$PKG""
					RESP="$?"
					if [ "$RESP" -eq 0 ]; then
						fn_generate_apt_log "$OPERACAO_TIMESTAMP" "$OPERACAO_DATA" "$ITEM" "ROLLBACK-ON"
					fi
				done
				;;
			A)
				fn_msg "[FAIL] Operation aborted!"
				;;
			*)
				fn_msg "[ERROR] Invalid option"
				fn_msg "[ERROR] Operation aborted!"
		esac

	else
		for ITEM in $PKG_COLLECTION; do
			PKG=$(echo "$ITEM" | awk -F "|" '{print $1}')
			VER_OLD=$(echo "$ITEM" | awk -F "|" '{print $2}')
			VER_NEW=$(echo "$ITEM" | awk -F "|" '{print $3}')
			echo "apt-get install "$PKG""
			RESP="$?"
			if [ "$RESP" -eq 0 ]; then
				fn_generate_apt_log "$OPERACAO_TIMESTAMP" "$OPERACAO_DATA" "$ITEM" "ROLLBACK-ON"
			fi
		done
	fi

#	cat "$APT_SEC_LOG"

}


function fn_update_packages_cve_old()
{


	fn_verify_expired "cve"
	RESP="$?"

	if [ "$RESP" -eq 0  ]; then
		# tempo maior que expirado
		fn_msg "[INFO] CVE database expired"
		fn_download_cve_db && fn_update_time "cve"
	fi
	#apt-get update
	fn_aptget_update

	# Verificando se todos os pacotes atualizaveis possuem um CVE associado

	fn_titulo "LIST PACKAGES WITH CVE"

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
		fn_generate_apt_log "$OPERACAO_TIMESTAMP" "$OPERACAO_DATA" "$PKG_COLLECTION" "ROLLBACK-ON"
	else
		echo "Not found packages with CVE"
	fi

}

function fn_update_packages_cve ()
{
	fn_titulo "UPGRADE PACKAGES WITH CVE"

	fn_verify_expired "cve"
	RESP="$?"

	if [ "$RESP" -eq 0  ]; then
		# tempo maior que expirado
		fn_msg "[INFO] CVE database expired"
		fn_download_cve_db && fn_update_time "cve"
	fi
	#apt-get update
	#fn_aptget_update

	# Atualizando todos os pacotes que obtiveram sucesso no download
	PKG_COLLECTION=""
	PKG_COLLECTION_FAIL=""
	PKG_TO_UPDATE=""
	PKG_TO_UPDATE_FAIL=""
	PKG_TO_UPDATE_FAIL_fn_msg=""


	#fn_list_package_upgradeble_formated
	fn_list_package_upgradeble_cve_formated
	RESP="$?"
	if [ "$RESP" -eq 0 ];then
		echo
		read -p "[QUESTION] Secure upgrade all packages from list? (y/n) [n]: " RESP
	    RESP=$(echo "${RESP:-"N"}")
    	RESP=$(echo $RESP| tr [a-z] [A-Z])

    	echo
    	case $RESP in
			Y|S)
				# sim
				fn_msg "[INFO] Inittiate download for actually version for rollback operations..."
				;;

			N)
				# não
				fn_msg "[INFO] Operation aborted!"
				exit 1
				;;

			*)
				fn_msg "[FAIL] Invalid option"
				fn_msg "[INFO] Operation aborted!"
				exit 1
				;;
		esac
	else
		fn_msg "[FAIL] No packages to update"
		exit 0

	fi

	LISTA=$(fn_get_all_package_upgradeble)
	for ITEM in $LISTA; do
		#echo "ITEM: $ITEM"
		PKG=$(echo "$ITEM" | awk -F "|" '{print $1}')
		VER_OLD=$(echo "$ITEM" | awk -F "|" '{print $2}')
		VER_NEW=$(echo "$ITEM" | awk -F "|" '{print $3}')

		fn_locate_package_in_cve "$PKG" &> /dev/null
		RESP="$?"
		if [ "$RESP" -eq 0 ]; then
			fn_download_package_version "$PKG" "$VER_OLD"
			RESP="$?"

			if [ "$RESP" -eq 0 ]; then
				#echo "PACOTE: $PKG"
				PKG_TO_UPDATE="${PKG_TO_UPDATE} ${PKG}"
				PKG_COLLECTION=$(echo -e "${PKG_COLLECTION}\n${ITEM}")
			else
				# pacotes que não foi possivel realizar o download de pacotes atualmente instalados para possível rollback
				PKG_TO_UPDATE_FAIL="${PKG_TO_UPDATE_FAIL} ${PKG}"
				PKG_TO_UPDATE_FAIL_fn_msg="${PKG_TO_UPDATE_FAIL_fn_msg} ${PKG}=${VER_OLD}"
				PKG_COLLECTION_FAIL=$(echo -e "${PKG_COLLECTION_FAIL}\n${ITEM}")
			fi
		fi

	done

	OPERACAO_TIMESTAMP=$(date +%s)
	OPERACAO_DATA=$(date "+%x %T")

	if [ -n "$PKG_TO_UPDATE_FAIL" ];then
		echo
		fn_msg "[ERROR] Packages not found actually version to garant rollback!"
		fn_msg "[ERROR] Packages: $PKG_TO_UPDATE_FAIL_fn_msg"
		echo

		read -p "[QUESTION] Existem pacotes que não podemos garantir o rollback. Deseja prosseguir mesmo assim? (y/n/a) [a]: " RESP
	    RESP=$(echo "${RESP:-"A"}")
    	RESP=$(echo $RESP| tr [a-z] [A-Z])

    	echo
    	case $RESP in
			Y|S)
				# sim
				echo "Segue com pacotes sem suporte a Rollback"
				#echo "Pacotes válidos: $PKG_TO_UPDATE"
				#echo "Pacotes inválidos: $PKG_TO_UPDATE_FAIL"
				## Juntando todos os
				#ALL_COLLECTION=$(echo -e "${PKG_COLLECTION}\n${PKG_COLLECTION_FAIL}")


				for ITEM in $PKG_COLLECTION; do
					PKG=$(echo "$ITEM" | awk -F "|" '{print $1}')
					VER_OLD=$(echo "$ITEM" | awk -F "|" '{print $2}')
					VER_NEW=$(echo "$ITEM" | awk -F "|" '{print $3}')
					#echo "apt-get install "$PKG""
					apt-get install -y "$PKG"
					RESP="$?"
					if [ "$RESP" -eq 0 ]; then
						fn_generate_apt_log "$OPERACAO_TIMESTAMP" "$OPERACAO_DATA" "$ITEM" "ROLLBACK-ON"
					fi
				done

				for ITEM in $PKG_COLLECTION_FAIL; do
					PKG=$(echo "$ITEM" | awk -F "|" '{print $1}')
					VER_OLD=$(echo "$ITEM" | awk -F "|" '{print $2}')
					VER_NEW=$(echo "$ITEM" | awk -F "|" '{print $3}')
					#echo "apt-get install $PKG"
					apt-get install -y "$PKG"
					RESP="$?"
					if [ "$RESP" -eq 0 ]; then
						fn_generate_apt_log "$OPERACAO_TIMESTAMP" "$OPERACAO_DATA" "$ITEM" "ROLLBACK-OFF"
					fi
				done

				;;

			N)
				# não
				echo "Segue apenas com os pacotes com suporte a Rollback"
				#echo "Pacotes válidos: $PKG_TO_UPDATE"

				for ITEM in $PKG_COLLECTION; do
					PKG=$(echo "$ITEM" | awk -F "|" '{print $1}')
					VER_OLD=$(echo "$ITEM" | awk -F "|" '{print $2}')
					VER_NEW=$(echo "$ITEM" | awk -F "|" '{print $3}')
					#echo "apt-get install $PKG"
					apt-get install "$PKG"
					RESP="$?"
					if [ "$RESP" -eq 0 ]; then
						fn_generate_apt_log "$OPERACAO_TIMESTAMP" "$OPERACAO_DATA" "$ITEM" "ROLLBACK-ON"
					fi
				done
				;;
			A)
				echo "Operation aborted!"
				;;
			*)
				echo "Invalid option"
				echo "Operation aborted!"
		esac
	else
		for ITEM in $PKG_COLLECTION; do
			PKG=$(echo "$ITEM" | awk -F "|" '{print $1}')
			VER_OLD=$(echo "$ITEM" | awk -F "|" '{print $2}')
			VER_NEW=$(echo "$ITEM" | awk -F "|" '{print $3}')
			#echo "apt-get install $PKG"
			apt-get install "$PKG"
			RESP="$?"
			if [ "$RESP" -eq 0 ]; then
				fn_generate_apt_log "$OPERACAO_TIMESTAMP" "$OPERACAO_DATA" "$ITEM" "ROLLBACK-ON"
			fi
		done
	fi

#	cat "$APT_SEC_LOG"

}



#===========================================================================
# ROLLBACK FUCNTIONS
#===========================================================================


function fn_download_package_version()
{
	# função para realização de download de pacotes e dependencias antigos (anteriores) para realização de rollback.
	PKG="$1"
	VERSION="$2"
	SAIDA=0

	#echo "%$PKG%$VERSION%"
	if [ ! -d $ROLLBACK_PKG_DIR ];then
		mkdir "$ROLLBACK_PKG_DIR"
		chown root:root "$ROLLBACK_PKG_DIR"
	fi
	cd "$ROLLBACK_PKG_DIR"

	LIST_DEP=$(apt-get install "$PKG" -V --assume-no | egrep -A1000 "The following packages will be upgraded:|Os pacotes a seguir serão atualizados:"| grep "^ " | awk '{print $1"|"$2"|"$4"|INSTALL"}' | sed 's/[)(]//g')

	#echo "DEPENDENCIAS $LIST_DEP"  #DEBUG

	for P in $LIST_DEP; do
		TMP_PKG=$(echo "$P" | awk -F "|" '{print $1}')
		TMP_OLD_VER=$(echo "$P" | awk -F "|" '{print $2}')

		#LOCALIZA=$(ls /var/cache/apt/archive/"${PKG}_$VERSION_*.deb" 2>/dev/null)
		LOCALIZA=$(ls /var/cache/apt/archive/"${TMP_PKG}_${TMP_OLD_VER}_*.deb" 2>/dev/null)
		if [ -n "$LOCALIZA" ];then
			#cp "${PKG}_${VERSION}_*.deb" "$ROLLBACK_PKG_DIR/"
			cp "/var/cache/apt/archive/${TMP_PKG}_${TMP_OLD_VER}_*.deb" "$ROLLBACK_PKG_DIR/"
			fn_msg "[INFO] Pacote: ${TMP_PKG}_${TMP_OLD_VER} (existente no archives) foi arquivado para rollback em: $ROLLBACK_PKG_DIR"
		else
			#apt-get download "$PKG"="$VERSION" 2> /dev/null
			apt-get download "${TMP_PKG}"="${TMP_OLD_VER}" 2> /dev/null
			RESULT="$?"
			#echo "DOWNLOAD RESULT: $RESULT"   #DEBUG
			if [ "$RESULT" -eq 0 ];then
				fn_msg "[INFO] Pacote: ${TMP_PKG}_${TMP_OLD_VER} baixado e arquivado para rollback em: $ROLLBACK_PKG_DIR"
				#return 0
				RETORNO=0
			else
				fn_msg "[ERROR] Problemas ao baixar pacote: ${TMP_PKG}_${TMP_OLD_VER} para rollback em: $ROLLBACK_PKG_DIR"
				RETORNO=1
			fi
		fi
		if [ "$RETORNO" -eq 1 ];then
			SAIDA=1
		fi

	done
	return "$SAIDA"
}



function fn_execute_rollback()
{
	PKG_COLLECTION="$1"

	PKG_TO_PURGE=""
	PKG_TO_REINSTALL=""
	fn_line
	printf " %-45s | %-25s | %-15s\n" "PACKAGE" "FROM NEW VERSION" "TO OLD VERSION"
	fn_line
	for P in $PKG_COLLECTION; do

		PKG=$(echo "$P" | awk -F"|" '{print $1}' )
		VER_OLD=$(echo "$P" | awk -F"|" '{print $2}' )
		VER_NEW=$(echo "$P" | awk -F"|" '{print $3}' )

		PKG_TO_PURGE="${PKG_TO_PURGE} ${PKG}"
		PKG_TO_REINSTALL="${PKG_TO_REINSTALL}  ${PKG}=${VER_NEW}"
		printf " %-45s | %-25s | %-15s\n" "$PKG" "$VER_NEW" "$VER_OLD"
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
	# função que prapara o menu para seleção de pacotes para a realização de Rollback (restauração)
	
	fn_titulo "ROLLBACK PACKAGES"
	
	LISTA=$(tac "$APT_SEC_LOG" 2> /dev/null| grep -v "^$"| grep "ROLLBACK-ON" | awk -F "|" '{print $1" "$2}' | uniq -c  | awk '{print $2" | "$3" " $4" | "$1 " Package(s)"}' | head -n "$ROLLBACK_LIMITE" )

	if [ ! -e "$APT_SEC_LOG" -o -z "$LISTA" ];then
		#fn_msg "[ERROR] Log file: $APT_SEC_LOG not valid register found!"
		#fn_msg "[INFO] NOT ROLLBACK NEEDED!"
		fn_msg "[INFO] NOT ROLLBACK (ON) REGISTER TO PROCESS!"
		exit 2
	fi

	

	OLD_IFS=$' \t\n'
	IFS=$'\n'

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
				PKG_COLLECTION=$(cat "$APT_SEC_LOG" | grep "ROLLBACK-ON" | grep "$FILTER" | awk -F "|" '{print $4"|"$5"|"$6}' )

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
	fn_isRoot "$@"


	case $OPT in
		-a|--all)
			fn_upgrade_all
			;;

		-c|--cve-list)
			# Verificando a necessidade de invocar a coleta de dados de CVEs do Debian
			fn_list_package_upgradeble_cve_formated detail
			;;

		-C|--cve-update)
			# Verificando a necessidade de invocar a coleta de dados de CVEs do Debian
			fn_update_packages_cve
			;;

		-l|--list)
			fn_list_package_upgradeble_formated
			;;

		-t)
			echo "XX fn_list_package_upgradeble_cve_formated"
			fn_list_package_upgradeble_cve_formated
			;;

		-s|--summary)
			fn_list_urgency_upgradable_summary
			;;

		-u|--urgency)
			fn_get_urgency_upgradable
			;;

		-R|--rollback)
			fn_menu_rollback
			;;
		--renew-cache)
			fn_download_cve_db
			;;	

		-h|--help)
			fn_usage
			;;

		*)
			fn_msg "[ERROR] option $OPT not found!"
			fn_usage
			;;
	esac

}

# inicio do script
fn_requiriments
fn_main "$1"
