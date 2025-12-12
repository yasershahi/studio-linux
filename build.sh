#!/bin/bash
set -euo pipefail

# Check arguments
VERSION="${1:-}"
if [ -z "$VERSION" ]; then
    echo "Error: Version parameter required"
    exit 1
fi

# Configuration
WORK_DIR="$(pwd)/workspace"
DOWNLOAD_CACHE="$(pwd)/cache"
APPDIR="$WORK_DIR/AppDir"
NODE_VERSION="22.12.0"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# Ensure directories exist
mkdir -p "$WORK_DIR"
mkdir -p "$DOWNLOAD_CACHE"
mkdir -p "$APPDIR"/{usr/{bin,lib},opt/studio}

echo "=== Preparing Environment ==="

# Setup Node.js
if [ ! -d "$WORK_DIR/node" ]; then
    echo "Setting up Node.js..."
    if [ ! -f "$DOWNLOAD_CACHE/node-v${NODE_VERSION}-linux-x64.tar.xz" ]; then
        curl -L "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" -o "$DOWNLOAD_CACHE/node-v${NODE_VERSION}-linux-x64.tar.xz"
    fi
    tar xJf "$DOWNLOAD_CACHE/node-v${NODE_VERSION}-linux-x64.tar.xz" -C "$WORK_DIR"
    mv "$WORK_DIR/node-v${NODE_VERSION}-linux-x64" "$WORK_DIR/node"
fi
export PATH="$WORK_DIR/node/bin:$PATH"

# Setup Studio Source
echo "=== Getting Studio Source ==="
cd "$WORK_DIR"
if [ ! -d "studio-src" ]; then
    if [ ! -f "$DOWNLOAD_CACHE/studio-$VERSION.tar.gz" ]; then
        echo "Downloading Studio $VERSION..."
        curl -L "https://github.com/Automattic/studio/archive/refs/tags/$VERSION.tar.gz" -o "$DOWNLOAD_CACHE/studio-$VERSION.tar.gz"
    fi
    tar xzf "$DOWNLOAD_CACHE/studio-$VERSION.tar.gz"
    mv studio-* studio-src
fi

echo "=== Building Studio ==="
cd studio-src

# Install Dependencies
if [ ! -d "node_modules" ]; then
    echo "Installing dependencies..."
    npm ci
fi

# Build and Package
# Using 'package' script which typically runs vite build + forge package
if [ ! -d "out/Studio-linux-x64" ]; then
    echo "Packaging application..."
    npm run package
fi

# Critical Optimization: Prune IN PLACE
PACKAGE_ROOT="out/Studio-linux-x64/resources/app"
if [ -d "$PACKAGE_ROOT" ]; then
    echo "=== Optimizing Size (In-Place Pruning) ==="
    pushd "$PACKAGE_ROOT" > /dev/null
    
    # Prune dev dependencies from the PACKAGED app
    npm prune --production
    
    # Remove obvious clutter that npm prune might miss
    echo "Removing unnecessary files..."
    find . -type d -name "test" -exec rm -rf {} +
    find . -type d -name "tests" -exec rm -rf {} +
    find . -type d -name ".github" -exec rm -rf {} +
    find . -type f -name "*.ts" -delete
    find . -type f -name "*.map" -delete
    find . -type f -name "*.md" -delete
    
    popd > /dev/null
    
    # Remove unused locales (Keep en-US*, en-GB* approximately)
    if [ -d "out/Studio-linux-x64/locales" ]; then
        echo "Cleaning locales..."
        find "out/Studio-linux-x64/locales" -type f -name "*.pak" ! -name "en-US.pak" ! -name "en-GB.pak" -delete
    fi
fi

echo "=== Creating AppDir structure ==="
# Clear previous content if any
rm -rf "$APPDIR/usr/bin/"*
cp -r out/Studio-linux-x64/* "$APPDIR/usr/bin/"
chmod +x "$APPDIR/usr/bin/studio"

# Remove unnecessary files from AppDir (Secondary cleanup)
find "$APPDIR" -name "*.a" -delete
find "$APPDIR" -name "*.la" -delete
find "$APPDIR" -name "*.pdb" -delete
find "$APPDIR" -name "*.dll.lib" -delete
find "$APPDIR" -type f -name "LICENSE*" -delete
find "$APPDIR" -type f -name "README*" -delete

# Remove bundled font libraries if present (Forces use of system fonts to fix spacing issues)
find "$APPDIR" -name "libfreetype*" -delete
find "$APPDIR" -name "libfontconfig*" -delete
find "$APPDIR" -name "libharfbuzz*" -delete

# Create AppRun (Wrapper script instead of symlink)
# This ensures arguments (URL handlers) are passed correctly and environment is sane.
cat > "$APPDIR/AppRun" << 'EOFAPP'
#!/bin/bash
HERE="$(dirname "$(readlink -f "${0}")")"
export APPDIR="${HERE}"
export PATH="${HERE}/usr/bin:${PATH}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${LD_LIBRARY_PATH}"
exec "${HERE}/usr/bin/studio" "$@"
EOFAPP
chmod +x "$APPDIR/AppRun"

# Copy icon
mkdir -p "$APPDIR/usr/share/icons/hicolor/256x256/apps/"
# Check if icon exists in source or script dir
if [ -f "$SCRIPT_DIR/studio.png" ]; then
    cp "$SCRIPT_DIR/studio.png" "$APPDIR/studio.png"
    cp "$SCRIPT_DIR/studio.png" "$APPDIR/usr/share/icons/hicolor/256x256/apps/studio.png"
fi

# Create desktop entry
cat > "$APPDIR/studio.desktop" << EOF
[Desktop Entry]
Name=Studio
Exec=studio %U
Icon=studio
Type=Application
Terminal=false
StartupWMClass=Studio
Categories=Development;
MimeType=x-scheme-handler/wpcom-local-dev;
Version=1.0
X-AppImage-Version=$VERSION
X-AppImage-UpdateInformation=github-releases-with-tag-based-channels:yasershahi/studio-appimage
EOF

echo "=== Building AppImage ==="
cd "$WORK_DIR"
if [ ! -f "appimagetool-x86_64.AppImage" ]; then
    wget -q "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x appimagetool-x86_64.AppImage
fi

export APPIMAGE_COMPRESS_TYPE="xz"
export APPIMAGE_COMPRESS_LEVEL="9"
# Use Update Information
export UPDATE_INFORMATION="github-releases-with-tag-based-channels:yasershahi/studio-appimage"

ARCH=x86_64 ./appimagetool-x86_64.AppImage --u --comp xz "$APPDIR" "Studio-$VERSION-x86_64.AppImage"

echo "=== Build Complete ==="
echo "AppImage created at: $WORK_DIR/Studio-$VERSION-x86_64.AppImage"