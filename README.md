## LeilFS packaging for Debian derivative systems

This repository contains the packaging scripts needed to build .deb packages for
LeilFS. Originally they were located in leil-io/leilfs repository, but have
been moved here to separate packaging and source code concerns.

*NOTE*: Currently, we only support Ubuntu 22.04 and 24.04. Patches for other
distributions and versions are welcome, but these are not supported by Leil.

*ANOTHER NOTE*: The package.sh may not work correctly. This is because the dev
branch is tracking leil-io/leilfs dev branch. If you want to build a stable
package, see the branches and/or tags.
