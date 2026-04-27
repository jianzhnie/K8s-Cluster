#!/bin/bash
# Sync distribution files to remote hosts
# Usage: bash sync_dist.sh [--with-large] [--with-npuslim] [host ...]
#   --with-large   Include large tarball files (~9GB)
#   --with-npuslim Also sync npuslim source code
#   host ...       Target hosts (default: 10.42.15.195 10.42.15.196 10.42.15.197 10.42.15.198 10.42.15.199 10.42.15.200 10.42.15.201)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="${SCRIPT_DIR}/distribution"
NPUSLIM_DIR="/home/lichc/projects/npuslim"
TARGET_DIR="~/docker"

# Defaults
WITH_LARGE=false
WITH_NPUSLIM=false
# HOSTS=(10.42.15.195 10.42.15.196 10.42.15.197 10.42.15.198 10.42.15.199 10.42.15.201 10.42.15.202)
HOSTS=(10.42.15.200)

# Parse args
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case $1 in
        --with-large) WITH_LARGE=true; shift ;;
        --with-npuslim) WITH_NPUSLIM=true; shift ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done
[[ ${#POSITIONAL[@]} -gt 0 ]] && HOSTS=("${POSITIONAL[@]}")

if $WITH_LARGE; then
    EXCLUDE_OPTS=()
else
    EXCLUDE_OPTS=(--exclude='*.tar.gz' --exclude='*.tgz')
fi

echo "========================================"
echo "Sync Distribution"
echo "========================================"
echo "Source:   ${DIST_DIR}"
echo "Npuslim:  ${WITH_NPUSLIM}"
echo "Hosts:    ${HOSTS[*]}"
echo "Target:   ~/docker/"
echo "Large:    ${WITH_LARGE}"
echo ""

for host in "${HOSTS[@]}"; do
    echo "--- Syncing to ${host} ---"
    ssh "lichc@${host}" "mkdir -p ${TARGET_DIR}" 2>/dev/null
    rsync -avP "${EXCLUDE_OPTS[@]}" "${DIST_DIR}/" "lichc@${host}:${TARGET_DIR}/"
    if $WITH_NPUSLIM; then
        ssh "lichc@${host}" "mkdir -p ${TARGET_DIR}/npuslim" 2>/dev/null
        rsync -avP --exclude='.git' --exclude='__pycache__' --exclude='*.egg-info' \
            "${NPUSLIM_DIR}/" "lichc@${host}:${TARGET_DIR}/npuslim/"
    fi
    echo ""
done

echo "========================================"
echo "All hosts synced."
echo "========================================"
