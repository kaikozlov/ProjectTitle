#!/bin/bash

set -e

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check for required gettext tools
echo "Checking for required gettext tools..."

TOOLS_MISSING=0
if ! command -v xgettext &> /dev/null; then
    echo "Error: xgettext not found in PATH"
    TOOLS_MISSING=1
fi
if ! command -v msgmerge &> /dev/null; then
    echo "Error: msgmerge not found in PATH"
    TOOLS_MISSING=1
fi
if ! command -v msgfmt &> /dev/null; then
    echo "Error: msgfmt not found in PATH"
    TOOLS_MISSING=1
fi

if [ "$TOOLS_MISSING" = "1" ]; then
    echo ""
    echo "Please install gettext tools first"

    # Detect OS and provide appropriate installation instructions
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "- macOS: brew install gettext"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Try to detect the distribution
        if command -v apt-get &> /dev/null; then
            echo "- Debian/Ubuntu: sudo apt-get install gettext"
        elif command -v dnf &> /dev/null; then
            echo "- Fedora/RHEL: sudo dnf install gettext"
        elif command -v yum &> /dev/null; then
            echo "- CentOS/RHEL: sudo yum install gettext"
        elif command -v pacman &> /dev/null; then
            echo "- Arch Linux: sudo pacman -S gettext"
        elif command -v zypper &> /dev/null; then
            echo "- openSUSE: sudo zypper install gettext-tools"
        else
            echo "- Linux: Install the 'gettext' package using your distribution's package manager"
        fi
    else
        echo "- Install the 'gettext' package using your system's package manager"
    fi
    exit 1
fi
echo "All required tools are available."
echo ""

# Compile PO files to MO files
echo "Starting MO files compilation..."
COMPILE_COUNT=0

for dir in l10n/*/; do
    if [ -f "${dir}koreader.po" ]; then
        MO_FILE="${dir}koreader.mo"
        LOCALE_NAME=$(basename "$dir")
        echo "Compiling: ${LOCALE_NAME}/koreader.po -> ${LOCALE_NAME}/koreader.mo"
        if msgfmt -o "$MO_FILE" "${dir}koreader.po"; then
            ((COMPILE_COUNT++))
        else
            echo "Error: Failed to compile ${LOCALE_NAME}/koreader.po!" >&2
        fi
    fi
done
echo "Compilation completed, successfully generated $COMPILE_COUNT MO files"
echo ""

# Make folder
echo "Creating projecttitle.koplugin folder..."
mkdir -p projecttitle.koplugin

# Copy everything into the right folder name
echo "Copying files..."
cp *.lua projecttitle.koplugin/
cp -r fonts projecttitle.koplugin/
cp -r icons projecttitle.koplugin/
cp -r resources projecttitle.koplugin/
cp -r l10n projecttitle.koplugin/

# Cleanup unwanted files
echo "Cleaning up unwanted files..."
rm -f projecttitle.koplugin/resources/collage.jpg
rm -f projecttitle.koplugin/resources/licenses.txt
# rm -f projecttitle.koplugin/**/*.po -- needed for some devices???

# Zip the folder
echo "Creating zip archive..."
if command -v zip &> /dev/null; then
    zip -r projecttitle.zip projecttitle.koplugin
elif command -v 7z &> /dev/null; then
    7z a -tzip projecttitle.zip projecttitle.koplugin
else
    echo "Error: Neither zip nor 7z found in PATH"

    # Detect OS and provide appropriate installation instructions
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "- macOS: zip is usually pre-installed, or install 7z with: brew install p7zip"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Try to detect the distribution
        if command -v apt-get &> /dev/null; then
            echo "- Debian/Ubuntu: sudo apt-get install zip  (or p7zip-full for 7z)"
        elif command -v dnf &> /dev/null; then
            echo "- Fedora/RHEL: sudo dnf install zip  (or p7zip for 7z)"
        elif command -v yum &> /dev/null; then
            echo "- CentOS/RHEL: sudo yum install zip  (or p7zip for 7z)"
        elif command -v pacman &> /dev/null; then
            echo "- Arch Linux: sudo pacman -S zip  (or p7zip for 7z)"
        elif command -v zypper &> /dev/null; then
            echo "- openSUSE: sudo zypper install zip  (or p7zip for 7z)"
        else
            echo "- Linux: Install the 'zip' or 'p7zip' package using your distribution's package manager"
        fi
    else
        echo "- Install the 'zip' or 'p7zip' package using your system's package manager"
    fi
    exit 1
fi

# Delete the folder
echo "Cleaning up temporary folder..."
rm -rf projecttitle.koplugin

echo ""
echo "Build complete! Created projecttitle.zip"
