#!/bin/bash

scriptname=$0
set -e

TARGET_VERSION="4.11.0-2"

usage() {
	{
		echo "Downgrade master, metalogger, and uraft server script"
		echo "This script will downgrade the master, metalogger, and uraft servers from version 5.0.0 to $TARGET_VERSION."
		echo ""
		echo "Usage:"
		echo "${scriptname} -h | --help"
		echo "	  Displays this help message."
		echo "${scriptname} [-d <MASTER_DATA_DIR>]"
		echo "	  Downgrades the master, metalogger, and uraft server services to version $TARGET_VERSION."
		echo "	  Includes the following steps:"
		echo "	      1. Stop the master, metalogger, and uraft server services."
		echo "	      2. Run data migration/fixes."
		echo "	      3. Downgrade the master, metalogger, and uraft server packages."
		echo "	      4. Start the master, metalogger, and uraft server services."
		echo ""
		echo "	  Logging is handled by the migration script and will be saved to /var/log/saunafs/downgrade/changelog.log."
		echo "	  Options:"
		echo "	     -d <MASTER_DATA_DIR>	The path to the master data directory. Default is /var/lib/saunafs."
	} >&2
exit 0
}

if [[ $1 == "-h" || $1 == "--help" ]]; then
	usage
fi

MASTER_DATA_DIR=/var/lib/saunafs

while getopts "d:" opt; do
	case ${opt} in
		d)
			MASTER_DATA_DIR=${OPTARG}
			;;
		\?)
			echo "Invalid option: -${OPTARG}" >&2
			usage
			;;
		:)
			echo "Option -${OPTARG} requires an argument." >&2
			usage
			;;
	esac
done

# Global variables to store installation status and active status
# Anything other than 0 means not installed
IS_MASTER_INSTALLED=1
IS_METALOGGER_INSTALLED=1
IS_URAFT_INSTALLED=1
IS_CHUNKSERVER_INSTALLED=1

MASTER_CURRENT_VERSION="unknown"
METALOGGER_CURRENT_VERSION="unknown"
URAFT_CURRENT_VERSION="unknown"
CHUNKSERVER_CURRENT_VERSION="unknown"

WAS_MASTER_ACTIVE=0
WAS_METALOGGER_ACTIVE=0
WAS_URAFT_ACTIVE=0

# Logging is now handled by the migration script itself
log_message() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

# Function to compare versions (greater than or equal to)
version_gt() {
	dpkg --compare-versions "$1" "gt" "$2"
}

# Function to check if a specific package version exists in apt
check_package_version_in_apt() {
	local package_name=$1
	local version=$2
	log_message "Checking if ${package_name} version ${version} is available in apt..."
	if apt-cache policy "${package_name}" | grep -q "${version}"; then
		log_message "${package_name} version ${version} is available in apt."
		return 0
	else
		log_message "Error: ${package_name} version ${version} is NOT available in apt. Please ensure the correct repositories are configured."
		return 1
	fi
}

check_installed_packages() {
	# Check saunafs-master
	if dpkg -s saunafs-master &>/dev/null; then
		IS_MASTER_INSTALLED=0
		MASTER_CURRENT_VERSION=$(dpkg -s saunafs-master | grep Version | awk '{print $2}')
	fi

	# Check saunafs-metalogger
	if dpkg -s saunafs-metalogger &>/dev/null; then
		IS_METALOGGER_INSTALLED=0
		METALOGGER_CURRENT_VERSION=$(dpkg -s saunafs-metalogger | grep Version | awk '{print $2}')
	fi

	# Check saunafs-uraft
	if dpkg -s saunafs-uraft &>/dev/null; then
		IS_URAFT_INSTALLED=0
		URAFT_CURRENT_VERSION=$(dpkg -s saunafs-uraft | grep Version | awk '{print $2}')
	fi

	# Check saunafs-chunkserver
	if dpkg -s saunafs-chunkserver &>/dev/null; then
		IS_CHUNKSERVER_INSTALLED=0
		CHUNKSERVER_CURRENT_VERSION=$(dpkg -s saunafs-chunkserver | grep Version | awk '{print $2}')
	fi

	if [ "$IS_MASTER_INSTALLED" -ne 0 ] && [ "$IS_METALOGGER_INSTALLED" -ne 0 ] && [ "$IS_URAFT_INSTALLED" -ne 0 ]; then
		log_message "Neither saunafs-master, saunafs-metalogger nor saunafs-uraft packages are installed. Exiting."
		exit 1
	fi
}

stop_master_server() {
	if [ "$IS_URAFT_INSTALLED" -eq 0 ]; then
		if systemctl is-active --quiet saunafs-uraft; then
			log_message "saunafs-uraft is active. Stopping saunafs-uraft instead of saunafs-master..."
			if systemctl stop saunafs-uraft; then
				log_message "saunafs-uraft stop command executed successfully"
				WAS_URAFT_ACTIVE=1
			else
				log_message "saunafs-uraft stop command executed with errors"
				exit 1
			fi
		else
			log_message "saunafs-uraft is installed but not active, skipping stop."
		fi
	fi

	# If uraft was not handled, or not installed, try to stop master
	if [ "$WAS_URAFT_ACTIVE" -eq 0 ] && [ "$IS_MASTER_INSTALLED" -eq 0 ]; then
		if systemctl is-active --quiet saunafs-master; then
			log_message "Stopping master server..."
			if systemctl stop saunafs-master; then
				log_message "Master stop command executed successfully"
				WAS_MASTER_ACTIVE=1
			else
				log_message "Master stop command executed with errors"
				exit 1
			fi
		else
			log_message "Master server is already stopped, skipping stop."
		fi
	elif [ "$WAS_URAFT_ACTIVE" -eq 1 ]; then
		log_message "saunafs-master stop skipped as saunafs-uraft was stopped."
	else
		log_message "saunafs-master not installed, skipping stop."
	fi
}

stop_metalogger_server() {
	if [ "$IS_METALOGGER_INSTALLED" -eq 0 ]; then
		if systemctl is-active --quiet saunafs-metalogger; then
			log_message "Stopping metalogger server..."
			if systemctl stop saunafs-metalogger; then
				log_message "Metalogger stop command executed successfully"
				WAS_METALOGGER_ACTIVE=1
			else
				log_message "Metalogger stop command executed with errors"
				exit 1
			fi
		else
			log_message "Metalogger server is already stopped, skipping stop."
		fi
	else
		log_message "saunafs-metalogger not installed, skipping stop."
	fi
}

run_data_migration() {
	log_message "Running data migration script..."
	# Call the saunafs-pro migration script, passing the data directory
	if bash /usr/lib/saunafs/migrations/5.0.0/rollback/downgrade-changelogs.sh -d "${MASTER_DATA_DIR}"; then
		log_message "Data migration script executed successfully"
	else
		log_message "Data migration script executed with errors"
		exit 1
	fi
}

downgrade_master_package() {
	if [ "$IS_MASTER_INSTALLED" -eq 0 ]; then
		log_message "Downgrading master server package to version ${TARGET_VERSION}..."
		if apt install saunafs-master=${TARGET_VERSION} --yes --allow-downgrades; then
			log_message "Master package downgrade command executed successfully"
		else
			log_message "Master package downgrade command executed with errors"
			exit 1
		fi
		log_message "Master server package downgraded to version ${TARGET_VERSION}"
	else
		log_message "saunafs-master not installed, skipping package downgrade."
	fi
}

downgrade_metalogger_package() {
	if [ "$IS_METALOGGER_INSTALLED" -eq 0 ]; then
		log_message "Downgrading metalogger server package to version ${TARGET_VERSION}..."
		if apt install saunafs-metalogger=${TARGET_VERSION} --yes --allow-downgrades; then
			log_message "Metalogger package downgrade command executed successfully"
		else
			log_message "Metalogger package downgrade command executed with errors"
			exit 1
		fi
		log_message "Metalogger server package downgraded to version ${TARGET_VERSION}"
	else
		log_message "saunafs-metalogger not installed, skipping package downgrade."
	fi
}

downgrade_uraft_package() {
	if [ "$IS_URAFT_INSTALLED" -eq 0 ]; then
		log_message "Downgrading uraft server package to version ${TARGET_VERSION}..."
		if apt install saunafs-uraft=${TARGET_VERSION} --yes --allow-downgrades; then
			log_message "Uraft package downgrade command executed successfully"
		else
			log_message "Uraft package downgrade command executed with errors"
			exit 1
		fi
		log_message "Uraft server package downgraded to version ${TARGET_VERSION}"
	else
		log_message "saunafs-uraft not installed, skipping package downgrade."
	fi
}

start_master_server() {
	if [ "$WAS_URAFT_ACTIVE" -eq 1 ]; then
		log_message "Starting saunafs-uraft..."
		if systemctl start saunafs-uraft; then
			log_message "saunafs-uraft start command executed successfully"
		else
			log_message "saunafs-uraft start command executed with errors"
			exit 1
		fi
	elif [ "$WAS_MASTER_ACTIVE" -eq 1 ]; then
		log_message "Starting master server..."
		if systemctl start saunafs-master; then
			log_message "Master start command executed successfully"
		else
			log_message "Master start command executed with errors"
			exit 1
		fi
	else
		log_message "Neither saunafs-master nor saunafs-uraft were active, skipping start."
	fi
}

start_metalogger_server() {
	if [ "$WAS_METALOGGER_ACTIVE" -eq 1 ]; then
		log_message "Starting metalogger server..."
		if systemctl start saunafs-metalogger; then
			log_message "Metalogger start command executed successfully"
		else
			log_message "Metalogger start command executed with errors"
			exit 1
		fi
	else
		log_message "saunafs-metalogger was not active, skipping start."
	fi
}

apt update
check_installed_packages

# Verify TARGET_VERSION exists in apt for relevant packages
if [ "$IS_MASTER_INSTALLED" -eq 0 ]; then
	if ! check_package_version_in_apt "saunafs-master" "${TARGET_VERSION}"; then
		exit 1
	fi
fi

if [ "$IS_METALOGGER_INSTALLED" -eq 0 ]; then
	if ! check_package_version_in_apt "saunafs-metalogger" "${TARGET_VERSION}"; then
		exit 1
	fi
fi

if [ "$IS_URAFT_INSTALLED" -eq 0 ]; then
	if ! check_package_version_in_apt "saunafs-uraft" "${TARGET_VERSION}"; then
		exit 1
	fi
fi

# Check chunkserver version and prevent downgrade if 5.0.0 or later
if [ "$IS_CHUNKSERVER_INSTALLED" -eq 0 ]; then
	if version_gt "${CHUNKSERVER_CURRENT_VERSION}" "$TARGET_VERSION"; then
		log_message "saunafs-chunkserver version ${CHUNKSERVER_CURRENT_VERSION} is not $TARGET_VERSION or earlier. This script is not intended for downgrading chunkserver. Exiting."
		exit 1
	fi
fi

if [ "$IS_MASTER_INSTALLED" -eq 0 ] && ! [ "$IS_URAFT_INSTALLED" -eq 0 ] ; then
	log_message "Downgrading master from version ${MASTER_CURRENT_VERSION} to ${TARGET_VERSION}"
fi

if [ "$IS_METALOGGER_INSTALLED" -eq 0 ]; then
	log_message "Downgrading metalogger from version ${METALOGGER_CURRENT_VERSION} to ${TARGET_VERSION}"
fi

if [ "$IS_URAFT_INSTALLED" -eq 0 ]; then
	log_message "Downgrading uraft from version ${URAFT_CURRENT_VERSION} to ${TARGET_VERSION}"
fi

stop_master_server
stop_metalogger_server
run_data_migration
downgrade_master_package
downgrade_metalogger_package
downgrade_uraft_package
start_master_server
start_metalogger_server
log_message "Downgrade process completed successfully"
