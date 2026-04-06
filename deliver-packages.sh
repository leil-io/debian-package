#!/usr/bin/env bash
set -eu -o pipefail

die() {
	echo "Error: ${*}" >&2
	exit 1
}

if [ -z "${REPO_NAME}" ]; then
	die "\$REPO_NAME must be set"
fi

declare nexus_url="${URL:-https://repo.leil.io}"
if [ -z "${NEXUS_AUTH}" ]; then
	die "\$NEXUS_AUTH must be set (in format of username:password)"
fi

if [ -z ${1:-} ]; then
	die "Provide a directory where the .deb packages are located"
fi


files=$(find "${1}" -type f -name '*.deb')
nexus_upload_url=${nexus_url}/service/rest/v1/components?repository=${REPO_NAME,,}

for file in ${files}; do
	echo "Uploading ${file} to ${nexus_upload_url}..."
	curl --config <(printf 'user = "%s"' "${NEXUS_AUTH}") --fail -X POST \
	"${nexus_upload_url}" \
	-H "accept: application/json" \
	-H "Content-Type: multipart/form-data" \
	-F "apt.asset=@${file}"
done
