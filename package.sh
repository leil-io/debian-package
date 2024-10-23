#!/bin/bash
set -ex

VERSION="4.5.1"
OUTPUT_DIR="$(pwd)/build"
BUILD_DIRECTORY="/tmp/package-saunafs"
PATCHES_DIRECTORY="${BUILD_DIRECTORY}/patches"

print_help() {
	echo "
This helper script allows quickly building saunafs debian
packages. By default, it will download from the releases section of
SaunaFS github, but you can also specify a option to build from a
specific git reference, note that if you use a specific version ref, the
packages will be confusingly named to the version of the debian folder. Use
the tags on this repository to change to the version you want!"
	echo "Options are:"
	echo "-r <string>: Clone and build from a git reference"
	echo "-p <path/to/file>: Apply a single patch file"
	echo "-f <path/to/directory>: Apply patches from directory"
}

PATCHES=()

while getopts ":hr:p:f:" arg; do
	case $arg in
		r)
			REF="${OPTARG}"
			;;
		p)
			if [ ! -f "${OPTARG}" ]; then
				echo "${OPTARG} not found!"
				exit 1
			fi
			PATCHES+=("${OPTARG}")
			;;
		f)
			if [ ! -d "${OPTARG}" ]; then
				echo "${OPTARG} not found!"
				exit 1
			fi
			for patch in "${OPTARG}"/*.patch; do
				PATCHES+=("${patch}")
			done
			;;
		h | *) # Display help.
			print_help
			exit 0
			;;
	esac
done

SOURCE_DIR="${BUILD_DIRECTORY}/saunafs-${VERSION}"
SOURCE_TAR="saunafs_${VERSION}.orig.tar.gz"

mkdir -p "${OUTPUT_DIR}"
mkdir "${BUILD_DIRECTORY}"
mkdir "${PATCHES_DIRECTORY}"
if [ ${#PATCHES[@]} != 0 ]; then
	for patch in $PATCHES; do
		cp "${patch}" "${PATCHES_DIRECTORY}"
	done
fi
cp -r debian "${BUILD_DIRECTORY}"
cd "${BUILD_DIRECTORY}"

if [ -n "$REF" ]; then
	git clone https://github.com/leil-io/saunafs/
	cd saunafs
	git checkout "${REF}"
	cd ..
	mv saunafs saunafs-${VERSION}
	tar --exclude-vcs -czf "${SOURCE_TAR}" saunafs-${VERSION}
	rm -rf saunafs
else
	wget https://github.com/leil-io/saunafs/archive/refs/tags/v${VERSION}.tar.gz
	mv "v${VERSION}.tar.gz" "${SOURCE_TAR}"
fi

cp "${SOURCE_TAR}" "${OUTPUT_DIR}"
tar xf "${SOURCE_TAR}"

rm "${SOURCE_DIR}/debian" -rf
cp -r "${BUILD_DIRECTORY}/debian" "${SOURCE_DIR}"

cd "$SOURCE_DIR"
mk-build-deps
sudo apt install "./saunafs-build-deps_${VERSION}_all.deb"
rm "./saunafs-build-deps_${VERSION}"*

if [ -n "$(ls -A "${PATCHES_DIRECTORY}")" ]; then
	for patch in "${PATCHES_DIRECTORY}"/*; do
		QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index" QUILT_PATCHES=debian/patches \
			quilt import "${patch}"
	done
fi

debuild -us -uc
# Package metadata
cp "${BUILD_DIRECTORY}/saunafs_"* "${OUTPUT_DIR}"
# Actual packages
cp "${BUILD_DIRECTORY}/saunafs-"*".deb" "${OUTPUT_DIR}"
rm -rf "${BUILD_DIRECTORY}"
