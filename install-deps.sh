#!/bin/bash

. ./version.sh

export DEBIAN_FRONTEND=noninteractive
set -x
apt-get update
apt-get install --yes equivs devscripts curl zip unzip tar bison
mk-build-deps
apt-get install --yes "./leil-build-deps_${VERSION}-${REVISION}_all.deb"
rm "./leil-build-deps_${VERSION}-${REVISION}"*
