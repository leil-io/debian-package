#!/bin/bash

. ./version.sh
BUILD_DIRECTORY="/tmp/package-saunafs"

SOURCE_DIR="${BUILD_DIRECTORY}/saunafs-${VERSION}"
SOURCE_TAR="saunafs_${VERSION}.orig.tar.gz"

apt install equivs

rm -rf "${BUILD_DIRECTORY:?}"
mkdir "${BUILD_DIRECTORY}"
cp -r debian "${BUILD_DIRECTORY}"
cd "${BUILD_DIRECTORY}"
wget https://github.com/leil-io/saunafs/archive/refs/tags/v${VERSION}.tar.gz

mv "v${VERSION}.tar.gz" "${SOURCE_TAR}"
tar xf "${SOURCE_TAR}"

rm "${SOURCE_DIR}/debian" -rf
cp -r "${BUILD_DIRECTORY}/debian" "${SOURCE_DIR}"

cd "$SOURCE_DIR"
mk-build-deps
apt install --yes "./saunafs-build-deps_${VERSION}-${REVISION}_all.deb"
rm "./saunafs-build-deps_${VERSION}-${REVISION}"*

rm -rf "${BUILD_DIRECTORY:?}"
