#!/bin/bash

set -x
apt-get install --yes equivs devscripts
mk-build-deps
apt-get install --yes "./saunafs-build-deps_${VERSION}-${REVISION}_all.deb"
rm "./saunafs-build-deps_${VERSION}-${REVISION}"*
