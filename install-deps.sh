#!/bin/bash

. ./version.sh

set -x
apt-get update
apt-get install --yes equivs devscripts
mk-build-deps
apt-get install --yes "./saunafs-build-deps_${VERSION}-${REVISION}_all.deb"
rm "./saunafs-build-deps_${VERSION}-${REVISION}"*
