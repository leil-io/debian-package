#!/bin/bash
set -ex

. ./version.sh
OUTPUT_DIR="$(pwd)/build"
SOURCE_DIR="$(pwd)"
BUILD_DIRECTORY="/tmp/package-saunafs"
PATCHES_DIRECTORY="${BUILD_DIRECTORY}/patches"

rm -rf ${BUILD_DIRECTORY:?}

sanitize_deb_version_component() {
	# Debian version components may only contain: [0-9A-Za-z.+:~\-]
	# Replace everything else (including '/', '_', '^', whitespace) with '.'
	local value="${1:-}"
	value="$(echo "$value" | sed -E 's/[^0-9A-Za-z.+:~\-]+/./g; s/\.+/./g; s/^\.+//; s/\.+$//')"
	echo "$value"
}

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
	echo "SNAPSHOT=[false|true]: Whether to add date and git info to version (default false)"
}

: "${SNAPSHOT:=false}"

mkdir -p "${OUTPUT_DIR}"
mkdir "${BUILD_DIRECTORY}"
mkdir "${PATCHES_DIRECTORY}"

if [[ -n $PATCH ]]; then
	cp "${PATCH}" "${PATCHES_DIRECTORY}"
fi

if [ -n "$PATCHES_DIR" ]; then
	shopt -s nullglob
	for patch in "${PATCHES_DIR}"/*; do
		if [[ -f "$patch" ]]; then
			cp "$patch" "${PATCHES_DIRECTORY}"
		fi
	done
	shopt -u nullglob
fi
cp -r debian "${BUILD_DIRECTORY}"
cd "${BUILD_DIRECTORY}"

if [ -z "$REF" ]; then
	REF="v${VERSION}"
fi

git clone https://github.com/leil-io/saunafs/
cd saunafs
git checkout "${REF}"
GIT_COMMIT=$(git rev-parse HEAD)
export GIT_COMMIT
GIT_BRANCH="$(basename "$(git name-rev "$GIT_COMMIT" | awk '{print $2}')")"
GIT_BRANCH="$(sanitize_deb_version_component "$GIT_BRANCH")"
export GIT_BRANCH
cd ..

if [ "$SNAPSHOT" = true ]; then
	SNAPSHOT_TS=$(date +%Y.%m.%d~%H.%M.%S)
	SNAPSHOT_COMMIT=""
	SNAPSHOT_BRANCH=""
	SNAPSHOT_COMMIT="~$GIT_COMMIT"
	SNAPSHOT_BRANCH="~$(sanitize_deb_version_component "$GIT_BRANCH")"
	UPSTREAM_VERSION="${VERSION}~${SNAPSHOT_TS}${SNAPSHOT_BRANCH}${SNAPSHOT_COMMIT}"
	DEB_VERSION="${UPSTREAM_VERSION}-${REVISION}"
	# Disable git commit/branch inclusion, speeds up compilation
	GIT_COMMIT="N/A due to snapshot, see deb package name"
	GIT_BRANCH="N/A due to snapshot, see deb package name"
	export GIT_COMMIT
	export GIT_BRANCH
else
	UPSTREAM_VERSION="${VERSION}"
	DEB_VERSION="${VERSION}-${REVISION}"
fi

mv saunafs saunafs-"${UPSTREAM_VERSION}"
SOURCE_TAR="saunafs_${UPSTREAM_VERSION}.orig.tar.gz"
tar --exclude-vcs -czf "${SOURCE_TAR}" saunafs-"${UPSTREAM_VERSION}"
rm -rf saunafs

cp "${SOURCE_TAR}" "${OUTPUT_DIR}"
tar xf "${SOURCE_TAR}"

SOURCE_DIR="${BUILD_DIRECTORY}/saunafs-${UPSTREAM_VERSION}"
rm "${SOURCE_DIR}/debian" -rf
cp -r "${BUILD_DIRECTORY}/debian" "${SOURCE_DIR}"

cd "$SOURCE_DIR"

if [ -n "$(ls -A "${PATCHES_DIRECTORY}")" ]; then
	for patch in "${PATCHES_DIRECTORY}"/*; do
		QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index" QUILT_PATCHES=debian/patches \
			quilt import "${patch}"
	done
fi

git submodule update --init
cd "vcpkg"
./bootstrap-vcpkg.sh
export VCPKG_ROOT="$(pwd)"
cd ${SOURCE_DIR}
"${VCPKG_ROOT}/vcpkg" install

if [ "$SNAPSHOT" = true ]; then
	sed -i "1 s/(${VERSION}-${REVISION})/(${DEB_VERSION})/" debian/changelog
	# TODO(Urmas): Maybe consider for non-snapshot as well?
	export CCACHE_NOHASHDIR=true
fi
export CCACHE_BASEDIR=$PWD

cat debian/changelog

debuild \
	--prepend-path=/usr/lib/ccache \
	--preserve-envvar=VERSION_SUFFIX \
	--preserve-envvar=X_VCPKG_ASSET_SOURCES \
	--preserve-envvar=VCPKG_ROOT \
	--preserve-envvar=CCACHE_NOHASHDIR \
	--preserve-envvar=CCACHE_BASEDIR \
	--set-envvar=GIT_COMMIT="$GIT_COMMIT" \
	--set-envvar=GIT_BRANCH="$GIT_BRANCH" \
	-us -uc


# Package metadata
cp "${BUILD_DIRECTORY}/saunafs_"* "${OUTPUT_DIR}"
# Actual packages
cp "${BUILD_DIRECTORY}/saunafs-"*".deb" "${OUTPUT_DIR}"
rm -rf "${BUILD_DIRECTORY:?}"
