VERSION="4.5.1"
BUILD_DIRECTORY="/tmp/dev-saunafs"
DEBIAN_DIR="$(pwd)/debian"

SOURCE_TAR="saunafs_${VERSION}.orig.tar.gz"
SOURCE_DIR="${BUILD_DIRECTORY}/saunafs-${VERSION}"

mkdir $BUILD_DIRECTORY
cd $BUILD_DIRECTORY
wget https://github.com/leil-io/saunafs/archive/refs/tags/v${VERSION}.tar.gz
mv "v${VERSION}.tar.gz" $SOURCE_TAR

tar xf $SOURCE_TAR
rm "$SOURCE_DIR/debian" -r
ln -s $DEBIAN_DIR $SOURCE_DIR

export QUILT_PATCHES=debian/patches
export QUILT_REFRESH_ARGS="-p ab --no-timestamps --no-index"

cd $SOURCE_DIR
