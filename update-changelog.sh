export NAME="LeilFS Team"
export EMAIL="support@leil.io"
dch --package leil -v "${1}" "Update LeilFS version"
dch --package leil -v "${1}" --distribution stable ""
