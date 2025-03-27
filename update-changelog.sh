export NAME="Saunafs Team"
export EMAIL="support@saunafs.com"
dch -v "${1}" "Update SaunaFS version"
dch -v "${1}" --distribution stable ""
