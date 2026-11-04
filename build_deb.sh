#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VERSION=$(grep -Po '^Version:\s*\K.*' pkg/DEBIAN/control | tr -d '[:space:]')
PKG_NAME="rpi-suspend_${VERSION}_all.deb"

echo "Building ${PKG_NAME}..."

BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

cp -a pkg "$BUILD_DIR/rpi-suspend"
find "$BUILD_DIR/rpi-suspend" -name ".gitkeep" -delete
find "$BUILD_DIR/rpi-suspend" -name "__pycache__" -type d -exec rm -rf {} +
find "$BUILD_DIR/rpi-suspend" -name "*.pyc" -delete

chmod 0755 "$BUILD_DIR/rpi-suspend/DEBIAN"
chmod 0755 "$BUILD_DIR/rpi-suspend/DEBIAN/postinst"
chmod 0755 "$BUILD_DIR/rpi-suspend/DEBIAN/prerm"
chmod 0755 "$BUILD_DIR/rpi-suspend/DEBIAN/postrm"
chmod 0755 "$BUILD_DIR/rpi-suspend/usr/bin/rpi-suspend"

dpkg-deb --root-owner-group --build "$BUILD_DIR/rpi-suspend" "$SCRIPT_DIR/$PKG_NAME"
cp -f "$SCRIPT_DIR/$PKG_NAME" "$SCRIPT_DIR/rpi-suspend.deb"

echo "Successfully built: $SCRIPT_DIR/$PKG_NAME"
