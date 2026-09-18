#!/usr/bin/env bash
# Install the coding standards markdown files from GitHub into ~/.claude/

set -euo pipefail

RAW_BASE_URL="https://raw.githubusercontent.com/Androsh7/CLAUDE.md/main"
DESTINATION_DIRECTORY="${HOME}/.claude"
STANDARD_FILES=(CLAUDE.md GIT.md DOCKER.md PYTHON.md REACT.md)

mkdir -p "${DESTINATION_DIRECTORY}"

for standard_file in "${STANDARD_FILES[@]}"; do
    destination_path="${DESTINATION_DIRECTORY}/${standard_file}"

    if [[ -e "${destination_path}" ]]; then
        read -r -p "Overwrite ${destination_path}? [y/N] " answer < /dev/tty
        if [[ "${answer}" != "y" && "${answer}" != "Y" ]]; then
            echo "Skipped   ${standard_file}"
            continue
        fi
    fi

    temporary_path="$(mktemp)"
    curl --fail --silent --show-error --location "${RAW_BASE_URL}/${standard_file}" --output "${temporary_path}"
    mv "${temporary_path}" "${destination_path}"
    echo "Installed ${standard_file}"
done
