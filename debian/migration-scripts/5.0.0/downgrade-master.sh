#!/usr/bin/env bash
set -eu -o pipefail
declare script="${BASH_SOURCE[0]}"
declare script_name="${script##*/}"

target_version="4.11.0-2"

usage() {
	{
		echo "Downgrade master, metalogger, and uraft server script"
		echo "This script will downgrade the master, metalogger, and uraft servers from version 5.0.0 to ${target_version}."
		echo ""
		echo "Usage:"
		echo "> ./${script_name} -h | --help"
		echo "      Displays this help message."
		echo "> ./${script_name} [-d <master_data_dir>]"
		echo "      Downgrades the master, metalogger, and uraft server services to version ${target_version}."
		echo "      Includes the following steps:"
		echo "          1. Stop the master, metalogger, and uraft server services."
		echo "          2. Run data migration/fixes."
		echo "          3. Downgrade the master, metalogger, and uraft server packages."
		echo "          4. Start the master, metalogger, and uraft server services."
		echo ""
		echo "      Logging is handled by the migration script and will be saved to /var/log/saunafs/downgrade/changelog.log."
		echo "      Options:"
		echo "         -d <master_data_dir>    The path to the master data directory. Default is /var/lib/saunafs."
		echo "         --dry-run               Run the script in dry-run mode."
		echo "         --help                  Display this help message."
	} >&2
exit 0
}

## error handling
show_error_context() {
	local err_code="${1:-0}"
	local err_line="${2:-0}"
	{
		if [[ ${err_code} -eq 0 ]]; then
			return 0
		fi
		if [[ ${_is_error} == false ]]; then
			echo -e "\n\033[1;31m[FATAL]\033[0m Script ended with exit code (${err_code}).\n"
			return "${err_code}"
		fi
		echo -e "\n\033[1;31m[ERROR]\033[0m Unexpected failure about line ${err_line} on ${0}:\n"
		awk -v err_line="${err_line}" -v context=2 \
			-v red="\033[1;31m" -v reset="\033[0m" '
		NR >= err_line - context && NR <= err_line + context {
			if (NR == err_line)
				print red ">>> " NR ": " $0 reset;
			else
				print "    " NR ": " $0;
		}' "${0}"
	} >&2
}
declare _is_error=false
trap '_ec=$?; _is_error=true; show_error_context ${_ec} ${LINENO}' ERR
trap '_ec=$?; [[ ${_is_error} == false ]] && show_error_context ${_ec}' EXIT
## end of error handling

## Logging functions
declare red="$(tput setaf 1)"
declare bold="$(tput bold)"
declare blue="$(tput setaf 4)"
declare reset="$(tput sgr0)"
log() { echo -e "[$(date -u '+%Y-%m-%d %H:%M:%S')] ${bold}${*}${reset}" >&2; }
die() { log "${red}[ERROR]${reset} ${*}"; exit 1; }
trace() { log "${blue}[TRACE]${reset} ${*}"; "${@}"; }

## decorate the function with mock to enable dry-run mode
mock() {
	if [[ "${dry_run}" == true ]]; then
		log "${blue}Mocking command:${reset} ${*}"
	else
		trace "${@}"
	fi
}

## Boolean functions

is_package_installed() { dpkg-query -Wf'${db:Status-abbrev}' "${1}" 2>/dev/null | grep -q '^i'; }
is_service_active() { systemctl is-active --quiet "${1}"; }
was_service_installed() { [[ "${installed_packages[${1}]}" -eq 0 ]]; }
was_service_active() { [[ "${active_services[${1}]}" -eq 0 ]]; }

## Get functions
get_version() { dpkg -s "${1}" | grep Version | awk '{print $2}'; }

# Function to compare versions (greater than or equal to)
version_gt() { dpkg --compare-versions "${1}" "gt" "${2}"; }

## Check functions

# Function to check if a specific package version exists in apt
check_package_version_in_apt() {
	local package_name="${1}"
	local version="${2}"
	log "Checking if ${package_name} version ${version} is available in apt..."
	if [ -z "$(apt-cache policy "${package_name}" | grep "${version}" || true)" ]; then
		die "${package_name} version ${version} is NOT available in apt. Please ensure the correct repositories are configured."
	fi
	log "${package_name} version ${version} is available in apt."
}

check_installed_packages() {
	for service in "${services[@]}"; do
		if is_package_installed "${service}"; then
			installed_packages[${service}]=0
		fi
		if was_service_installed "${service}"; then
			current_versions[${service}]="$(get_version "${service}")"
		fi
	done

	if ! was_service_installed saunafs-master && \
		! was_service_installed saunafs-metalogger; then
		die "Neither saunafs-master nor saunafs-metalogger packages are installed. Exiting."
	fi
}

## Core functions

stop_server() {
	local server_service="${1}"
	local message="${2:-"Stopping ${server_service} server..."}"
	if was_service_installed "${server_service}"; then
		if is_service_active "${server_service}"; then
			log "${message}"
			mock systemctl stop "${server_service}" || \
				die "${server_service} stop command executed with errors."
			log "${server_service} stop command executed successfully."
			active_services[${server_service}]=1
		else
			log "${server_service} is already stopped, skipping stop."
		fi
	else
		log "${server_service} not installed, skipping stop."
	fi
}

run_data_migration() {
	log "Running data migration script..."
	# Call the saunafs-pro migration script, passing the data directory
	mock bash /usr/lib/saunafs/migrations/5.0.0/rollback/downgrade-changelogs.sh -d "${master_data_dir}" || \
		die "Data migration script executed with errors."
	log "Data migration script executed successfully."
}

downgrade_package() {
	local package_name="${1}"
	local target_version="${2}"
	if ! was_service_installed "${package_name}"; then
		log "${package_name} not installed, skipping package downgrade."
		return
	fi
	log "Downgrading ${package_name} server package to version ${target_version}..."
	mock apt install "${package_name}=${target_version}" --yes --allow-downgrades || \
		die "${package_name} package downgrade command executed with errors."
	log "${package_name} server package downgraded to version ${target_version}."
}

start_server() {
	local server_service="${1}"
	local message="${2:-"Starting ${server_service} server..."}"
	if ! was_service_active "${server_service}"; then
		log "${server_service} was not active, skipping start."
		return
	fi
	log "${message}"
	mock systemctl start "${server_service}" || \
		die "${server_service} start command executed with errors."
	log "${server_service} start command executed successfully."
}

## Parse options

parse_options_required_argument() {
	[[ -n "${2:-}" ]] || die "Option ${1} requires an argument."
}

parse_options() {
	while [[ -n "${1:-}" ]]; do
		case "${1}" in
			--help|-h)
				usage
				;;
			--master-data-dir|-d)
				parse_options_required_argument "-d" "${2:-}"
				master_data_dir="${2}"
				shift
				;;
			--dry-run|-r)
				dry_run=true
				;;
			--)
				shift
				break
				;;
			*)
				if [[ "${1}" == -* ]]; then
					echo "Invalid option: ${1}" >&2
					usage
				fi
				;;
		esac
		shift
	done
}

## Main script

main() {
	# Global variables to store installation status and active status
	# Anything other than 0 means not installed

	declare services=(
		saunafs-chunkserver
		saunafs-master
		saunafs-metalogger
		saunafs-uraft
	)

	declare excluded_services_from_downgrade=(
		saunafs-chunkserver
	)

	declare -A installed_packages=()
	declare -A current_versions=()
	declare -A active_services=()

	## Populate variables with default values
	for service in "${services[@]}"; do
		installed_packages+=([${service}]=1)
		current_versions+=([${service}]="unknown")
		active_services+=([${service}]=1)
	done

	## Defaults for options
	declare master_data_dir=/var/lib/saunafs
	declare dry_run=false

	parse_options "${@}"

	mock apt update
	check_installed_packages

	if was_service_installed "saunafs-uraft" && was_service_active "saunafs-uraft"; then
		die "saunafs-uraft is active. You must manually stop uraft and make sure master is stopped as well."
	fi

	for service in "${services[@]}"; do
		if was_service_installed "${service}"; then
			check_package_version_in_apt "${service}" "${target_version}" || \
				die "${service} version ${target_version} is NOT available in apt. Please ensure the correct repositories are configured."
		fi
	done

	for service in "${excluded_services_from_downgrade[@]}"; do
		if was_service_installed "${service}"; then
			if version_gt "${current_versions[${service}]}" "${target_version}"; then
				die "${service} version ${current_versions[${service}]} is not ${target_version} or earlier. This script is not intended for downgrading ${service}. Exiting."
			fi
		fi
	done

	for service in "${services[@]}"; do
		if was_service_installed "${service}"; then
			if [[ "${service}" == "saunafs-master" ]] && was_service_installed "saunafs-uraft"; then
				log "Skipping ${service} downgrade as saunafs-uraft is installed."
				continue
			fi
			log "Downgrading ${service} from version ${current_versions[${service}]} to ${target_version}"
		fi
	done

	stop_server "saunafs-master"
	stop_server "saunafs-metalogger"
	run_data_migration
	downgrade_package "saunafs-master" "${target_version}"
	downgrade_package "saunafs-metalogger" "${target_version}"
	downgrade_package "saunafs-uraft" "${target_version}"
	start_server "saunafs-master"
	start_server "saunafs-metalogger"
	log "Downgrade process completed successfully"
}

main "${@}"
