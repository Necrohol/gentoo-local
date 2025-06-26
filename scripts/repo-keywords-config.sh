#!/bin/bash
### fix to a post sync repo ie emerge --sync and fix $overlay keywords 
# Define the specific repository and keywords
SPECIFIC_REPO="sakaki-tools"
KEYWORDS="~amd64 ~arm64 ~riscv ~* **"
SPECIFIC_KEYWORDS_FILE="/etc/portage/package.accept_keywords/${SPECIFIC_REPO}-repo"

# Function to append keywords if not present for a specific repository
append_specific_keywords() {
    if ! grep -q "*/*::${SPECIFIC_REPO}" "${SPECIFIC_KEYWORDS_FILE}"; then
        echo "*/*::${SPECIFIC_REPO} ${KEYWORDS}" >> "${SPECIFIC_KEYWORDS_FILE}"
        echo "Keywords appended for ${SPECIFIC_REPO}."
    else
        echo "Keywords already present for ${SPECIFIC_REPO}."
    fi
}

# Run the function for the specific repository
append_specific_keywords

# Find installed Gentoo repositories
installed_repos=$(eselect repository list | awk '{print $1}' | grep -v "^#")

# Configure keywords for each repository using a wildcard
for repo in $installed_repos; do
    if [ "$repo" != "$SPECIFIC_REPO" ]; then
        KEYWORDS_FILE="/etc/portage/package.accept_keywords/${repo}-repo"
        if ! grep -q "*/*::${repo}" "${KEYWORDS_FILE}"; then
            echo "*/*::${repo} ${KEYWORDS}" >> "${KEYWORDS_FILE}"
            echo "Keywords appended for ${repo}."
        else
            echo "Keywords already present for ${repo}."
        fi
    fi
done

echo "Repository keywords configuration completed."
