#!/bin/sh
# Create a self-signed code signing certificate for local Ghostty builds.
#
# Why: Xcode signs local builds ad-hoc, and an ad-hoc signature is identified
# only by the binary's hash. macOS TCC remembers permission grants against a
# code signing identity, so with ad-hoc signing every rebuild looks like a new
# app and you get re-prompted forever ("Ghostty.app would like to access data
# from other apps", Accessibility, etc.).
#
# A certificate gives a stable identity, so one Allow sticks across rebuilds.
#
# Run once. build.sh picks the identity up automatically. Expect a macOS
# authorization prompt when the certificate is marked as trusted.
set -eu

NAME=${1:-Ghostty Local Signing}

if security find-identity -v -p codesigning 2>/dev/null | grep -qF "$NAME"; then
  echo "Identity '$NAME' already exists. Nothing to do."
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT INT TERM

echo "==> Generating a 10-year certificate"
openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" \
  -subj "/CN=$NAME" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# macOS `security` cannot read OpenSSL 3's default PKCS#12 encryption, so ask
# for the legacy algorithms it does understand.
openssl pkcs12 -export -out "$tmp/bundle.p12" \
  -inkey "$tmp/key.pem" -in "$tmp/cert.pem" \
  -passout pass:ghostty -name "$NAME" \
  -macalg sha1 -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES

echo "==> Importing into the login keychain"
security import "$tmp/bundle.p12" \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  -P ghostty -T /usr/bin/codesign -T /usr/bin/security

echo "==> Marking it trusted for code signing (expect an auth prompt)"
security add-trusted-cert -r trustRoot -p codeSign \
  -k "$HOME/Library/Keychains/login.keychain-db" "$tmp/cert.pem"

echo "==> Done:"
security find-identity -v -p codesigning | grep -F "$NAME"
