#!/bin/bash -e -o pipefail

source ~/utils/utils.sh

LATEST_RELEASE_URL="https://api.github.com/repos/realm/SwiftLint/releases/latest"
DOWNLOAD_URL=$(curl -s $LATEST_RELEASE_URL | jq -r '.assets[].browser_download_url | select(contains("SwiftLint.pkg"))')
download_with_retries $LATEST_RELEASE_URL /tmp "SwiftLint.pkg"
sudo installer -pkg /tmp/SwiftLint.pkg -target /