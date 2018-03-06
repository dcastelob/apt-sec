#!/bin/bash

#cd "/home/dcastelob/Documentos/scripts/apt-sec/git/apt-sec/deb/apt-sec-1.0"
#VERSION="1.0"
PKG_NAME="apt-sec"
BIN_PATH="../src/"
MAN_PATH="../man/"

VERSION=$(cat "${BIN_PATH}/apt-sec" | grep "APT_SEC_VERSION="| cut -d"=" -f2| sed "s/\"//g")
PATH_BASE="tmp/${PKG_NAME}-${VERSION}/DEBIAN"

# Removendo tudo antes de começar (limpeza)
echo "[INFO] Limpando dados anteriores"
if [ -d "$PATH_BASE" ]; then
	rm -Rf "$PATH_BASE"
	mkdir -p ${PATH_BASE}	
fi

# Criando os arquivos de controle do pacote Debian
echo "[INFO] Criando definições de pacote"

cat <<EOF >"${PATH_BASE}/control"
Package: ${PKG_NAME}
Version: ${VERSION}
Priority:
Architecture: all
Essential:
Depends: bsdmainutils (>= 8.0), aptitude (>=0.8.0), postgresql-client (>=8.0)
Pre-depends:
Suggests:
Installed-Size:
Maintainer: Diego Castelo Branco <dcastelob@gmail.com>
Conflicts:
Replaces:
Provides:
Description: apt-sec - advanced tool for managing system package updates
EOF

cat <<EOF >"${PATH_BASE}/copyright"
Format: http://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: ${PKG_NAME}
Upstream-Contact: dcastelob@gmail.com 

Files: *
Copyright: 2018 Diego Castelo Branco
License: GPL-3.
EOF


# Colocando o conteúdo no pacote .deb
echo "[INFO] Montando pacote .deb"

mkdir -p ${PATH_BASE}/usr/sbin
cp "${BIN_PATH}/apt-sec" ${PATH_BASE}/usr/sbin/apt-sec
chmod +x ${PATH_BASE}/usr/sbin/apt-sec

mkdir -p ${PATH_BASE}/etc/apt-sec
cp ${BIN_PATH}/apt-sec.conf  ${PATH_BASE}/etc/apt-sec/

mkdir -p ${PATH_BASE}/usr/local/man/man8/
cp ${MAN_PATH}/apt-sec ${PATH_BASE}/usr/local/man/man8/apt-sec.8
sed -i "s@VERSION@${VERSION}@" ${PATH_BASE}/usr/local/man/man8/apt-sec.8
gzip ${PATH_BASE}/usr/local/man/man8/apt-sec.8

# Alterando o caminho do arquivo de configuração
echo "[INFO] Ajustando arquivos de configuração"

sed -i "s@='apt-sec.conf'@='/etc/apt-get/apt-sec.conf'@" ${PATH_BASE}/usr/sbin/apt-sec

# Gerando o pacote .deb
echo "[INFO] Construindo o pacote ${PKG_NAME}.${VERSION}.deb"

rm -f ${PKG_NAME}.${VERSION}.deb
dpkg-deb -b tmp/${PKG_NAME}-${VERSION} ${PKG_NAME}.${VERSION}.deb
ls -l

