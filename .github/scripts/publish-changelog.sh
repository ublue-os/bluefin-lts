#!/bin/bash

# Script to check for new tags and publish changelogs only when needed
# This prevents the issue where the same tag (20250602) is always processed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAST_PUBLISHED_TAG_FILE="${SCRIPT_DIR}/last_published_tag.txt"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Function to get the latest git tag
get_latest_tag() {
    # Get the latest tag that matches the lts-* pattern
    git tag --sort=-version:refname | grep -E "^lts-[0-9]{8}$" | head -n1 || echo ""
}

# Function to get the last published tag from file
get_last_published_tag() {
    if [[ -f "${LAST_PUBLISHED_TAG_FILE}" ]]; then
        cat "${LAST_PUBLISHED_TAG_FILE}"
    else
        echo ""
    fi
}

# Function to update the last published tag file
update_last_published_tag() {
    local tag="$1"
    echo "${tag}" > "${LAST_PUBLISHED_TAG_FILE}"
    echo "Updated last published tag to: ${tag}"
}

# Function to generate changelog using the existing Python script
generate_changelog() {
    local target="$1"
    local handwritten="${2:-}"
    
    echo "Generating changelog for target: ${target}"
    
    # Use the existing changelogs.py script
    cd "${REPO_ROOT}"
    
    # Run the changelog generation
    if [[ -n "${handwritten}" ]]; then
        if ! python3 .github/changelogs.py --workdir . "${target}" ./output.env ./changelog.md --handwritten "${handwritten}"; then
            echo "Error: Failed to generate changelog with handwritten content"
            exit 1
        fi
    else
        if ! python3 .github/changelogs.py --workdir . "${target}" ./output.env ./changelog.md; then
            echo "Error: Failed to generate changelog"
            exit 1
        fi
    fi
    
    # Verify output files exist
    if [[ ! -f ./output.env ]]; then
        echo "Error: output.env file was not created"
        exit 1
    fi
    
    if [[ ! -f ./changelog.md ]]; then
        echo "Error: changelog.md file was not created"
        exit 1
    fi
    
    # Source the output to get title and tag
    source ./output.env
    
    # Verify required variables exist
    if [[ -z "${TAG:-}" ]] || [[ -z "${TITLE:-}" ]]; then
        echo "Error: TAG or TITLE not found in output.env"
        exit 1
    fi
    
    echo "Generated changelog for tag: ${TAG}"
    echo "Title: ${TITLE}"
    
    # Return the tag and title via output variables
    echo "CHANGELOG_TAG=${TAG}" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    echo "CHANGELOG_TITLE=${TITLE}" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    echo "CHANGELOG_PATH=${REPO_ROOT}/changelog.md" >> "${GITHUB_OUTPUT:-/dev/stdout}"
}

# Main logic
main() {
    local target="${1:-lts}"
    local handwritten="${2:-}"
    local force="${3:-false}"
    
    echo "=== Changelog Publisher ==="
    echo "Target: ${target}"
    echo "Handwritten: ${handwritten}"
    echo "Force: ${force}"
    echo ""
    
    # Get current latest tag
    latest_tag=$(get_latest_tag)
    if [[ -z "${latest_tag}" ]]; then
        echo "Error: No LTS tags found in repository"
        exit 1
    fi
    
    # Get last published tag
    last_published_tag=$(get_last_published_tag)
    
    echo "Latest tag: ${latest_tag}"
    echo "Last published tag: ${last_published_tag}"
    echo ""
    
    # Check if we need to publish
    if [[ "${force}" == "true" ]]; then
        echo "Force mode enabled - generating changelog regardless of tag status"
    elif [[ "${latest_tag}" == "${last_published_tag}" ]]; then
        echo "No new tag detected. Latest tag ${latest_tag} has already been published."
        echo "SKIP_CHANGELOG=true" >> "${GITHUB_OUTPUT:-/dev/stdout}"
        exit 0
    else
        echo "New tag detected! Generating changelog for ${latest_tag}"
    fi
    
    # Generate the changelog
    generate_changelog "${target}" "${handwritten}"
    
    # Update the last published tag
    update_last_published_tag "${latest_tag}"
    
    echo "SKIP_CHANGELOG=false" >> "${GITHUB_OUTPUT:-/dev/stdout}"
    echo "Changelog generation completed successfully!"
}

# Run main function with all arguments
main "$@"