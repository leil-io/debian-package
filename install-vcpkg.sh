## Script to install vcpkg packages beforehand, useful for caching
git clone https://github.com/leil-io/saunafs
cd saunafs || exit 1
git checkout "${REFERENCE}"
git submodule update --init
cd vcpkg || exit 1
./bootstrap-vcpkg.sh -disableMetrics
cd ..

./vcpkg/vcpkg install
