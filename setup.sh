#!/usr/bin/env bash
# setup.sh - Local development environment setup for Metrolist
#
# Run this script once after cloning the repository to prepare your environment:
#   bash setup.sh
#
# Tested on Linux. macOS users may need Homebrew for some tools (see comments below).

set -euo pipefail

# ---------------------------------------------------------------------------
# Helper utilities
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

info()    { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
step()    { echo -e "\n${GREEN}==>${NC} $*"; }

# ---------------------------------------------------------------------------
# 1. Prerequisite checks
# ---------------------------------------------------------------------------
step "Checking prerequisites..."

# Java 21
if ! command -v java &>/dev/null; then
    error "Java is not installed. Please install JDK 21."
    echo "  Linux (apt):  sudo apt-get install -y openjdk-21-jdk"
    echo "  macOS (brew): brew install openjdk@21"
    echo "  Or download from: https://adoptium.net/"
    exit 1
fi

JAVA_VER_STRING=$(java -version 2>&1 | head -1)
# Try quoted format first: openjdk version "21.0.1" ...
JAVA_MAJOR=$(echo "${JAVA_VER_STRING}" | grep -oE '"[0-9]+' | grep -oE '[0-9]+' | head -1)
# Fallback: some distributions may output without quotes (e.g. "version 21" or "21.0.1")
if [ -z "${JAVA_MAJOR}" ]; then
    JAVA_MAJOR=$(echo "${JAVA_VER_STRING}" | grep -oE '\b[0-9]{2,}\b' | head -1)
fi
# Validate that we got a numeric value
if ! echo "${JAVA_MAJOR}" | grep -qE '^[0-9]+$'; then
    error "Could not determine Java major version from: ${JAVA_VER_STRING}"
    echo "  Please ensure JDK 21 is installed and 'java' is in your PATH."
    exit 1
fi
if [ "${JAVA_MAJOR}" -lt 21 ]; then
    error "JDK 21 or newer is required. Found Java major version '${JAVA_MAJOR}'."
    echo "  Download JDK 21 from: https://adoptium.net/"
    exit 1
fi
info "Java major version ${JAVA_MAJOR} detected. ✓"

# protobuf-compiler
if ! command -v protoc &>/dev/null; then
    warn "protoc (protobuf compiler) not found. Attempting to install..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get update -qq && sudo apt-get install -y protobuf-compiler
    elif command -v brew &>/dev/null; then
        brew install protobuf
    else
        error "Cannot install protoc automatically. Please install protobuf-compiler >= v3.21."
        echo "  Linux (apt):  sudo apt-get install -y protobuf-compiler"
        echo "  macOS (brew): brew install protobuf"
        echo "  Or download from: https://github.com/protocolbuffers/protobuf/releases"
        exit 1
    fi
fi

PROTOC_VERSION=$(protoc --version 2>&1 | awk '{print $2}')
info "protoc version ${PROTOC_VERSION} detected. ✓"

# keytool (part of JDK)
if ! command -v keytool &>/dev/null; then
    error "keytool not found. Make sure JDK 21 is properly installed and in your PATH."
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. Git submodules
# ---------------------------------------------------------------------------
step "Initialising git submodules..."
git submodule update --init --recursive
info "Submodules initialised. ✓"

# ---------------------------------------------------------------------------
# 3. Generate protobuf files
# ---------------------------------------------------------------------------
step "Generating protobuf files..."
(cd app && bash generate_proto.sh)
info "Protobuf files generated. ✓"

# ---------------------------------------------------------------------------
# 4. Debug keystore
# ---------------------------------------------------------------------------
KEYSTORE_PATH="app/persistent-debug.keystore"
step "Checking debug keystore..."
if [ ! -f "${KEYSTORE_PATH}" ]; then
    info "Generating persistent debug keystore at ${KEYSTORE_PATH}..."
    keytool -genkeypair -v \
        -keystore "${KEYSTORE_PATH}" \
        -storepass android \
        -keypass android \
        -alias androiddebugkey \
        -keyalg RSA \
        -keysize 2048 \
        -validity 10000 \
        -dname "CN=Android Debug,O=Android,C=US"
    info "Debug keystore created. ✓"
else
    info "Debug keystore already exists. ✓"
fi

# ---------------------------------------------------------------------------
# 5. local.properties
# ---------------------------------------------------------------------------
step "Checking local.properties..."
if [ ! -f "local.properties" ]; then
    if [ -f "local.properties.example" ]; then
        cp local.properties.example local.properties
        info "Created local.properties from local.properties.example."
    else
        # Minimal local.properties so the build can find the SDK dir if set
        touch local.properties
        info "Created empty local.properties."
    fi
    warn "If you want LastFM features, edit local.properties and add your API keys."
    warn "  Get keys at: https://www.last.fm/api/account/create"
else
    info "local.properties already exists. ✓"
fi

# ---------------------------------------------------------------------------
# 6. Clear Gradle configuration cache (avoids stale cache problems)
# ---------------------------------------------------------------------------
step "Clearing Gradle configuration cache..."
if [ -d ".gradle/configuration-cache" ]; then
    rm -rf .gradle/configuration-cache
    info "Gradle configuration cache cleared. ✓"
else
    info "No Gradle configuration cache to clear. ✓"
fi

# ---------------------------------------------------------------------------
# 7. Ensure gradlew is executable
# ---------------------------------------------------------------------------
step "Setting gradlew permissions..."
chmod +x gradlew
info "gradlew is now executable. ✓"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}Setup complete!${NC}"
echo ""
echo "Next steps:"
echo "  1. (Optional) Add your LastFM API keys to local.properties"
echo "  2. Build a debug APK:"
echo "       ./gradlew :app:assembleFossDebug"
echo "  3. Find the APK at:"
echo "       app/build/outputs/apk/universalFoss/debug/app-universal-foss-debug.apk"
echo ""
echo "Available build flavors: foss (default), gms, izzy"
echo "  e.g. ./gradlew :app:assembleGmsDebug"
echo ""
