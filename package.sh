VERSION="4.5.1"
OUTPUT_DIR="$(pwd)/build"
BUILD_DIRECTORY="/tmp/package-saunafs"

SOURCE_TAR="saunafs_${VERSION}.orig.tar.gz"
SOURCE_DIR="${BUILD_DIRECTORY}/saunafs-${VERSION}"

mkdir -p "${OUTPUT_DIR}"
mkdir "${BUILD_DIRECTORY}"
cp -r debian "${BUILD_DIRECTORY}"
cd "${BUILD_DIRECTORY}"
wget https://github.com/leil-io/saunafs/archive/refs/tags/v${VERSION}.tar.gz
mv "v${VERSION}.tar.gz" "${SOURCE_TAR}"
cp "${SOURCE_TAR}" "${OUTPUT_DIR}"

tar xf "${SOURCE_TAR}"
rm "${SOURCE_DIR}/debian" -r
cp -r "${BUILD_DIRECTORY}/debian" "${SOURCE_DIR}"

cd "$SOURCE_DIR"
mk-build-deps
sudo apt install "./saunafs-build-deps_${VERSION}_all.deb"
rm "./saunafs-build-deps_${VERSION}"*
debuild -us -uc
# Package metadata
cp "${BUILD_DIRECTORY}/saunafs_"* "${OUTPUT_DIR}"
# Actual packages
cp "${BUILD_DIRECTORY}/saunafs-"*".deb" "${OUTPUT_DIR}"
rm -r "$BUILD_DIRECTORY"
