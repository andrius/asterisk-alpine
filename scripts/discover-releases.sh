#!/bin/sh
# discover-releases.sh - detect new upstream Asterisk releases for the tracked
# lines, by scraping downloads.asterisk.org.
#
# For each tracked line, compares the latest upstream release to the pkgver
# pinned in packages/<line>/APKBUILD. Prints one bump record per line that has a
# newer upstream release (tab-separated):
#   <line>	<current_pkgver>	<new_pkgver>	<certN|->	<major|base>
# Regular lines (23, 22, 20, 18, 16): scrape .../asterisk/releases/ for the
#   newest <major>.x.y; source uses $pkgver so only pkgver + sha512 bump.
# Certified (22-cert): scrape .../certified-asterisk/releases/ for the newest
#   asterisk-certified-<base>-cert<N>; the -certN is the 4th pkgver component
#   (22.8.0.<N>), and source + builddir also embed "cert<N>".
#
# Exit 0 always; the caller checks stdout for bumps. No output = nothing new.
set -eu

REGULAR_URL="https://downloads.asterisk.org/pub/telephony/asterisk/releases"
CERTIFIED_URL="https://downloads.asterisk.org/pub/telephony/certified-asterisk/releases"

# Tracked regular lines (dir names whose major == first pkgver component).
REGULAR_LINES="23 22 20 18 16"
CERTIFIED_LINE="22-cert"

pkgver_of() { grep -m1 '^pkgver=' "packages/$1/APKBUILD" | cut -d= -f2; }
major_of()  { printf '%s' "$1" | cut -d. -f1; }

# strictly_greater a b : is a a newer version than b? (sort -V)
strictly_greater() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | tail -1)" = "$1" ]
}

echo "# discover: $(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" >&2
INDEX_REGULAR=$(curl -fsSL --retry 2 "$REGULAR_URL/" 2>/dev/null || true)
INDEX_CERTIFIED=$(curl -fsSL --retry 2 "$CERTIFIED_URL/" 2>/dev/null || true)

# --- regular lines ---
for line in $REGULAR_LINES; do
  cur=$(pkgver_of "$line")
  maj=$(major_of "$cur")
  latest=$(printf '%s' "$INDEX_REGULAR" \
    | grep -oE "asterisk-${maj}\.[0-9]+\.[0-9]+\.tar\.gz" \
    | sed -e 's/^asterisk-//' -e 's/\.tar\.gz$//' \
    | sort -V | tail -1)
  if [ -n "$latest" ] && strictly_greater "$latest" "$cur"; then
    printf '%s\t%s\t%s\t-\t%s\n' "$line" "$cur" "$latest" "$maj"
    echo "# $line: $cur -> $latest" >&2
  else
    echo "# $line: current ($cur)" >&2
  fi
done

# --- certified 22-cert ---
cur=$(pkgver_of "$CERTIFIED_LINE")          # 22.8.0.3
cur_cert=$(printf '%s' "$cur" | cut -d. -f4) # 3
base=$(printf '%s' "$cur" | cut -d. -f1-2)   # 22.8
latest_cert=$(printf '%s' "$INDEX_CERTIFIED" \
  | grep -oE "asterisk-certified-${base}-cert[0-9]+\.tar\.gz" \
  | sed -E "s/^asterisk-certified-${base}-cert([0-9]+)\.tar\.gz$/\1/" \
  | sort -n | tail -1)
if [ -n "$latest_cert" ] && strictly_greater "$latest_cert" "$cur_cert"; then
  new_pkgver="${base}.0.${latest_cert}"      # 22.8.0.<certN>
  printf '%s\t%s\t%s\t%s\t%s\n' "$CERTIFIED_LINE" "$cur" "$new_pkgver" "$latest_cert" "$base"
  echo "# $CERTIFIED_LINE: $cur -> $new_pkgver (cert${latest_cert})" >&2
else
  echo "# $CERTIFIED_LINE: current ($cur, cert${cur_cert})" >&2
fi
