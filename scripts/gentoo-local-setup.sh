#!/bin/bash
# This script sets up a local Gentoo overlay, configures repos.conf,
# and creates custom profiles for specified architectures and init systems.
# It populates common profile configuration files and adjusts parent profiles
# based on observed Gentoo profile hierarchy (e.g., 23.0 structure).
#
# NEW: Profile paths within the local overlay are now 'hardened/linux/' for RISC-V
#      and 'default/linux/' for AMD64/ARM64.

# --- Configuration Variables ---

# Define CPU architectures
ARCHITECTURES=("amd64" "arm64" "riscv64")

# Define init systems
INIT_SYSTEMS=("openrc" "systemd")

# Overlay configuration
OVERLAY_NAME="gentoo-local"
# Set the overlay base directory
OVERLAY_BASE_DIR="/var/db/repos/" # Your custom overlays will live under /var/db/repos/gentoo-local
OVERLAY_LOCATION="${OVERLAY_BASE_DIR}/${OVERLAY_NAME}"

# Gentoo's main repository base directory
GENTOO_REPO_BASE="/var/db/repos/gentoo"

# --- Script Logic ---

# Ensure overlay directories exist
echo "Creating overlay directory structure at ${OVERLAY_LOCATION}..."
mkdir -p "${OVERLAY_LOCATION}/metadata"
mkdir -p "${OVERLAY_LOCATION}/profiles"

# Configure repos.conf for the new overlay
echo "Configuring /etc/portage/repos.conf/${OVERLAY_NAME}.conf..."
printf "[%s]\nlocation = %s\nmasters = gentoo\npriority = 100\nauto-sync = no\n" \
    "${OVERLAY_NAME}" "${OVERLAY_LOCATION}" | sudo tee "/etc/portage/repos.conf/${OVERLAY_NAME}.conf" > /dev/null

# Configure overlay metadata
echo "Configuring overlay metadata for ${OVERLAY_NAME}..."
echo "masters = gentoo" | tee "${OVERLAY_LOCATION}/metadata/layout.conf" > /dev/null
echo "profile-formats = portage-2" >> "${OVERLAY_LOCATION}/metadata/layout.conf"
echo "${OVERLAY_NAME}" | tee "${OVERLAY_LOCATION}/profiles/repo_name" > /dev/null

# Clear profiles.desc file at the start to ensure clean rebuild on re-run
# This is important if you change profile paths/aliases.
echo "Clearing existing profiles.desc for ${OVERLAY_NAME}..."
true > "${OVERLAY_LOCATION}/profiles/profiles.desc"


echo "Setting up custom profiles for each architecture and init system..."

# Define the array of standard profile configuration files to be created
declare -a config_files=(
    "make.defaults"
    "package.mask"
    "package.use"
    "package.use.force"
    "package.use.mask"
    "packages.build"
    "use.mask"
)

# Loop through architectures and init systems to create profiles
for ARCH in "${ARCHITECTURES[@]}"; do
    # Determine the subdirectory within profiles/ for the current profile
    # This changes based on whether it's RISC-V or other architectures.
    local PROFILE_SUBDIR="" # Declare locally to avoid clashes
    if [[ "$ARCH" == "riscv64" ]]; then
        PROFILE_SUBDIR="hardened/linux/${ARCH}" # For RISC-V, use 'hardened/linux/' path in overlay
    else
        PROFILE_SUBDIR="default/linux/${ARCH}" # For AMD64/ARM64, use 'default/linux/' path in overlay
    fi

    for INIT in "${INIT_SYSTEMS[@]}"; do
        # Construct the full path for the current custom profile in the local overlay
        PROFILE_DIR="${OVERLAY_LOCATION}/profiles/${PROFILE_SUBDIR}/${INIT}-llvm-desktop"
        
        echo "  - Creating profile: ${OVERLAY_NAME}:${PROFILE_SUBDIR}/${INIT}-llvm-desktop"
        
        # Create the profile directory
        mkdir -p "${PROFILE_DIR}"

        # Create the common profile configuration files
        echo "    - Creating common config files in ${PROFILE_DIR}..."
        for file in "${config_files[@]}"; do
            touch "${PROFILE_DIR}/${file}"
            echo "      - Created: ${file}"
        done

        # --- Populate make.defaults with arch-specific USE flags ---
        MAKE_DEFAULTS_FILE="${PROFILE_DIR}/make.defaults"
        
        # Only add specific USE flags for RISC-V in the local profile's make.defaults
        if [[ "$ARCH" == "riscv64" ]]; then
            # For RISC-V, use both pic (Position-Independent Code) and cfi (Control-Flow Integrity)
            echo 'USE="pic cfi"' >> "${MAKE_DEFAULTS_FILE}"
            echo "      - Added 'USE=\"pic cfi spectre\"' to ${MAKE_DEFAULTS_FILE}"
        fi

        # EAPI for the custom profile
        echo "    - Setting EAPI for ${PROFILE_DIR}..."
        echo "6" > "${PROFILE_DIR}/eapi"

        # --- Define parent profiles based on Gentoo's profiles.desc ---
        # Initialize an empty array for parent profiles for each iteration
        PARENT_PROFILES=() 

        # Add the architecture's base profile and common features from the main Gentoo repo
        if [[ "$ARCH" == "riscv64" ]]; then
            # RISC-V has a specific base profile path as per profiles.desc
            PARENT_PROFILES+=("${GENTOO_REPO_BASE}/profiles/default/linux/riscv/23.0/rv64/split-usr/lp64d")
            # Append LLVM for RISC-V based on common patterns
            PARENT_PROFILES+=("${GENTOO_REPO_BASE}/profiles/default/linux/riscv/23.0/rv64/split-usr/lp64d/llvm")
            # For RISC-V, explicitly add the generic hardened feature if a specific one isn't clearly
            # part of the base profile path in profiles.desc.
            PARENT_PROFILES+=("${GENTOO_REPO_BASE}/profiles/features/hardened")
        else
            # For amd64 and arm64, use the standard 23.0 default/linux path
            PARENT_PROFILES+=("${GENTOO_REPO_BASE}/profiles/default/linux/${ARCH}/23.0")
            # Add common features as separate parent entries for these architectures
            PARENT_PROFILES+=("${GENTOO_REPO_BASE}/profiles/default/linux/${ARCH}/23.0/llvm")
            PARENT_PROFILES+=("${GENTOO_REPO_BASE}/profiles/default/linux/${ARCH}/23.0/split-usr")
            PARENT_PROFILES+=("${GENTOO_REPO_BASE}/profiles/default/linux/${ARCH}/23.0/hardened")
        fi

        # Add common desktop target profile for all architectures
        PARENT_PROFILES+=("${GENTOO_REPO_BASE}/profiles/targets/desktop")
        
        # Add init-specific parent profile
        if [[ "$INIT" == "systemd" ]]; then
            # For systemd, append the specific systemd profile layer
            if [[ "$ARCH" == "riscv64" ]]; then
                # Assuming systemd for RISC-V would layer on top of lp64d
                PARENT_PROFILES+=("${GENTOO_REPO_BASE}/profiles/default/linux/riscv/23.0/rv64/split-usr/lp64d/systemd")
            else
                PARENT_PROFILES+=("${GENTOO_REPO_BASE}/profiles/default/linux/${ARCH}/23.0/systemd")
            fi
        elif [[ "$INIT" == "openrc" ]]; then
            # For OpenRC, use the generic targets/openrc feature profile
            PARENT_PROFILES+=("${GENTOO_REPO_BASE}/profiles/targets/openrc")
        fi

        # Write parent profiles to the 'parent' file
        echo "    - Writing parent profiles to ${PROFILE_DIR}/parent..."
        printf "%s\n" "${PARENT_PROFILES[@]}" > "${PROFILE_DIR}/parent"
        
        # Add profile description to profiles.desc in the overlay's profiles/ directory
        # Format: <arch> <path/to/profile> <status> [alias]
        # Use the dynamically determined PROFILE_SUBDIR
        printf "%s\t%s\t%s\t%s\n" \
            "${ARCH}" \
            "${PROFILE_SUBDIR}/${INIT}-llvm-desktop" \
            "exp" \
            "llvm-${INIT}-desktop-${ARCH}" \
            >> "${OVERLAY_LOCATION}/profiles/profiles.desc"
    done
done

echo ""
echo "Script finished. Your local overlay and custom profiles are set up."
echo "You can now try to select your profile, e.g.:"
echo "  sudo emerge --sync" # Sync to pick up the new repos.conf
echo "  eselect profile list"
echo "  eselect profile set ${OVERLAY_NAME}:default/linux/amd64/systemd-llvm-desktop" # Example for AMD64
echo "  eselect profile set ${OVERLAY_NAME}:hardened/linux/riscv64/openrc-llvm-desktop" # Example for RISC-V
echo "Or using the alias (e.g., for amd64/systemd):"
echo "  eselect profile set ${OVERLAY_NAME}:llvm-systemd-desktop-amd64" # Alias now includes arch for uniqueness

echo ""
echo "Remember to adjust your /etc/portage/make.conf for ACCEPT_KEYWORDS, etc."
echo 'Example: ACCEPT_KEYWORDS="~* **"'
echo 'Example: FEATURES="split-usr hardened"'
