VERSION="4.6.0-rc3"
BUILD_DIRECTORY="/tmp/dev-leil"
DEBIAN_DIR="$(pwd)/debian"

SOURCE_TAR="leil_${VERSION}.orig.tar.gz"
SOURCE_DIR="${BUILD_DIRECTORY}/leil-${VERSION}"

mkdir $BUILD_DIRECTORY
cd $BUILD_DIRECTORY
wget https://github.com/leil-io/leilfs/archive/refs/tags/v${VERSION}.tar.gz
mv "v${VERSION}.tar.gz" ${SOURCE_TAR}

tar xf ${SOURCE_TAR}
rm "$SOURCE_DIR/debian" -r
ln -s ${DEBIAN_DIR} ${SOURCE_DIR}

cd $SOURCE_DIR
QUILT_PATCHES=debian/patches QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index" bash
rm -r $BUILD_DIRECTORY
