#!/bin/bash
set -ex

. ./version.sh
OUTPUT_DIR="$(pwd)/build"
BUILD_DIRECTORY="/tmp/package-saunafs"
PATCHES_DIRECTORY="${BUILD_DIRECTORY}/patches"

rm -rf ${BUILD_DIRECTORY:?}

print_help() {
	echo "
This helper script allows quickly building saunafs debian
packages. By default, it will download from the releases section of
SaunaFS github, but you can also specify a option to build from a
specific git reference, note that if you use a specific version ref, the
packages will be confusingly named to the version of the debian folder. Use
the tags on this repository to change to the version you want!"
	echo "environment variables are:"
	echo "REF=<string>: Clone and build from a git reference"
	echo "PATCH=<path/to/patch>: Apply a single patch file"
	echo "PATCHES_DIR=<path/to/directory>: Apply patches from directory"
}

PATCHES=()

SOURCE_DIR="${BUILD_DIRECTORY}/saunafs-${VERSION}"
SOURCE_TAR="saunafs_${VERSION}.orig.tar.gz"

mkdir -p "${OUTPUT_DIR}"
mkdir "${BUILD_DIRECTORY}"
mkdir "${PATCHES_DIRECTORY}"

if [[ -n $PATCH ]]; then
	cp "${PATCH}" "${PATCHES_DIRECTORY}"
fi

if [ -n $PATCHES_DIR ]; then
	for patch in $PATCHES_DIR; do
		cp "${patch}" "${PATCHES_DIRECTORY}"
	done
fi
cp -r debian "${BUILD_DIRECTORY}"
cd "${BUILD_DIRECTORY}"

if [ -z "$REF" ]; then
	REF="v${VERSION}"
fi

git clone https://github.com/leil-io/saunafs/
cd saunafs
git checkout "${REF}"
export GIT_COMMIT=$(git rev-parse HEAD)
export GIT_BRANCH=$REF
cd ..
mv saunafs saunafs-"${VERSION}"
tar --exclude-vcs -czf "${SOURCE_TAR}" saunafs-"${VERSION}"
rm -rf saunafs

cp "${SOURCE_TAR}" "${OUTPUT_DIR}"
tar xf "${SOURCE_TAR}"

rm "${SOURCE_DIR}/debian" -rf
cp -r "${BUILD_DIRECTORY}/debian" "${SOURCE_DIR}"

cd "$SOURCE_DIR"

if [ -n "$(ls -A "${PATCHES_DIRECTORY}")" ]; then
	for patch in "${PATCHES_DIRECTORY}"/*; do
		QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index" QUILT_PATCHES=debian/patches \
			quilt import "${patch}"
	done
fi

cd "${BUILD_DIRECTORY}"
git clone https://github.com/microsoft/vcpkg.git
cd vcpkg
./bootstrap-vcpkg.sh
export VCPKG_ROOT="${BUILD_DIRECTORY}/vcpkg"
cd "${SOURCE_DIR}"
"${VCPKG_ROOT}/vcpkg" install

# Default from dpkg-source, with vcpkg_installed as extra at the end
dpkg-buildpackage -b
# Package metadata
cp "${BUILD_DIRECTORY}/saunafs_"* "${OUTPUT_DIR}"
# Actual packages
cp "${BUILD_DIRECTORY}/saunafs-"*".deb" "${OUTPUT_DIR}"
rm -rf "${BUILD_DIRECTORY:?}"
