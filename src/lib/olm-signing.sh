# Sourced by src/setup-olmapp.sh, never run. Makes this Mac's signing identity for Olm.app once and
# names it for app/build.sh, step 2 of the permissions plan in
# dotfiles/hammerspoon/.hammerspoon/Spoons/Olm.spoon/docs/DESIGN-APP-PLUGINS.md.
#
# Why. Olm.app holds the macOS permissions every plugin asks it to use. Signed ad hoc with a
# requirement naming only its bundle id, any program signed as local.olm.Olm matched that
# requirement, and anyone can sign that way with no key. Signed with a certificate made here, the
# requirement names the certificate too, so only a program signed with this Mac's key matches.
# decisions/olm-standalone.md has the day.
#
# The identity lives in a keychain of Olm's own, ~/.olm/state/signing/olm.keychain-db, never the
# login keychain, with a random password in a file beside it readable by this account alone. So a
# build unlocks it and signs with no question for the person, and nothing is added to the
# keychains macOS searches. The certificate is self signed for code signing and needs no trust
# setting, since codesign signs with it as it is and macOS's privacy system compares the
# certificate's hash, not its trust.
#
# Losing the folder makes a new certificate on the next run, and macOS then asks for each
# permission again, since a grant names the certificate it was given to.

OLM_SIGN_DIR="$HOME/.olm/state/signing"
OLM_SIGN_KEYCHAIN="$OLM_SIGN_DIR/olm.keychain-db"
OLM_SIGN_PASSWORD_FILE="$OLM_SIGN_DIR/password"
OLM_SIGN_IDENTITY="Olm Local Signing"

# olm_signing_ready, answers 0 with the three OLM_SIGN_ names exported once the identity is there,
# made now when it is not, and 1 with a line on stderr when it cannot be made.
olm_signing_ready() {
  if [ -f "$OLM_SIGN_KEYCHAIN" ] && [ -f "$OLM_SIGN_PASSWORD_FILE" ]; then
    export OLM_SIGN_KEYCHAIN OLM_SIGN_PASSWORD_FILE OLM_SIGN_IDENTITY
    return 0
  fi
  if [ -e "$OLM_SIGN_KEYCHAIN" ] || [ -e "$OLM_SIGN_PASSWORD_FILE" ]; then
    echo "olm signing: $OLM_SIGN_DIR holds a keychain or a password without the other, left as it is" >&2
    return 1
  fi
  echo "==> Making Olm.app's signing certificate, once for this Mac"
  local work password
  work="$(mktemp -d)"
  ( umask 077; mkdir -p "$OLM_SIGN_DIR" )
  chmod 700 "$OLM_SIGN_DIR"
  password="$(/usr/bin/openssl rand -hex 32)"
  cat > "$work/cert.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Olm Local Signing
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF
  # The p12's own password lives only for this run.
  local transfer
  transfer="$(/usr/bin/openssl rand -hex 16)"
  if ! /usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$work/cert.cnf" \
      -keyout "$work/key.pem" -out "$work/cert.pem" >/dev/null 2>&1 \
    || ! /usr/bin/openssl pkcs12 -export -inkey "$work/key.pem" -in "$work/cert.pem" \
      -name "$OLM_SIGN_IDENTITY" -passout "pass:$transfer" -out "$work/id.p12" >/dev/null 2>&1 \
    || ! security create-keychain -p "$password" "$OLM_SIGN_KEYCHAIN" >/dev/null 2>&1 \
    || ! security set-keychain-settings "$OLM_SIGN_KEYCHAIN" >/dev/null 2>&1 \
    || ! security import "$work/id.p12" -k "$OLM_SIGN_KEYCHAIN" -f pkcs12 -P "$transfer" \
      -T /usr/bin/codesign >/dev/null 2>&1 \
    || ! security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" \
      "$OLM_SIGN_KEYCHAIN" >/dev/null 2>&1; then
    rm -rf "$work"
    [ -f "$OLM_SIGN_KEYCHAIN" ] && security delete-keychain "$OLM_SIGN_KEYCHAIN" >/dev/null 2>&1
    echo "olm signing: the certificate could not be made" >&2
    return 1
  fi
  rm -rf "$work"
  ( umask 077; printf '%s' "$password" > "$OLM_SIGN_PASSWORD_FILE" )
  export OLM_SIGN_KEYCHAIN OLM_SIGN_PASSWORD_FILE OLM_SIGN_IDENTITY
  return 0
}
