#!/bin/bash
# Get the version and revision number from the debian/changelog file
# Capture the upstream version with \1 and revison number with \2
# e.g (4.6.0-rc3-1), upstream version will 4.6.0-rc3 and revision will be 1
VERSION=$(head -n 1 ./debian/changelog | sed -n 's/.*(\(.*\)-\([0-9]*\)).*/\1/p')
REVISION=$(head -n 1 ./debian/changelog | sed -n 's/.*(\(.*\)-\([0-9]*\)).*/\2/p')

echo $VERSION
echo $REVISION
