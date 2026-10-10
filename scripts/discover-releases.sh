#!/bin/sh
# discover-releases.sh - detect new upstream Asterisk releases for the tracked
# lines, by scraping downloads.asterisk.org.
#
# For each tracked line, compares the latest upstream release to the pkgver
# pinned in packages/<line>/APKBUILD. Prints one bump record per line that has a
# newer upstream release (tab-separated):
#   <line>	<current_pkgver>	<new_pkgver>	<certN|->	<major|base>
# Regular lines (24, 23, 22, 20, 18, 16): scrape .../asterisk/releases/ for the
#   newest <major>.x.y; source uses $pkgver so only pkgver + sha512 bump.
#   A line whose pkgver is a pre-release (24.0.0_rc2) also follows upstream
#   -rcN tarballs, spelled _rcN for apk, and a GA outranks every RC of it, so
#   it moves rc2 -> rc3 -> 24.0.0. Lines on a GA pkgver ignore RCs.
# Certified (22-cert): scrape .../certified-asterisk/releases/ for the newest
#   asterisk-certified-<base>-cert<N>; the -certN is the 4th pkgver component
#   (22.8.0.<N>), and source + builddir also embed "cert<N>".
#
# Exit 0 always; the caller checks stdout for bumps. No output = nothing new.
set -eu

REGULAR_URL="${REGULAR_URL:-https://downloads.asterisk.org/pub/telephony/asterisk/releases}"
CERTIFIED_URL="${CERTIFIED_URL:-https://downloads.asterisk.org/pub/telephony/certified-asterisk/releases}"

# Tracked regular lines (dir names whose major == first pkgver component).
REGULAR_LINES="24 23 22 20 18 16"
CERTIFIED_LINE="22-cert"

pkgver_of() { grep -m1 '^pkgver=' "packages/$1/APKBUILD" | cut -d= -f2; }
major_of()  { printf '%s' "$1" | cut -d. -f1; }

# relkey v : sort -V key on which a pre-release sorts below its GA
#   (24.0.0_rc2 -> 24.0.0.2.2, 24.0.0 -> 24.0.0.9.0). Plain sort -V ranks
#   24.0.0_rc2 above 24.0.0, which would hide the GA from an RC line.
relkey() {
  case "$1" in
    *_alpha*) stage=0 ;; *_beta*) stage=1 ;; *_rc*) stage=2 ;; *) stage=9 ;;
  esac
  n=$(printf '%s' "$1" | sed -n -E 's/.*_(alpha|beta|rc)([0-9]*)$/\2/p')
  printf '%s.%s.%s' "${1%%_*}" "$stage" "${n:-0}"
}

# strictly_greater a b : is a a newer version than b? (sort -V on relkey)
strictly_greater() {
  [ "$1" != "$2" ] && [ "$(printf '%s %s\n%s %s\n' "$(relkey "$2")" "$2" "$(relkey "$1")" "$1" | sort -V | tail -1 | cut -d' ' -f2)" = "$1" ]
}

echo "# discover: $(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" >&2
INDEX_REGULAR=$(curl -fsSL --retry 2 "$REGULAR_URL/" 2>/dev/null || true)
INDEX_CERTIFIED=$(curl -fsSL --retry 2 "$CERTIFIED_URL/" 2>/dev/null || true)

# --- regular lines ---
for line in $REGULAR_LINES; do
  cur=$(pkgver_of "$line")
  maj=$(major_of "$cur")
  case "$cur" in
    *_alpha*|*_beta*|*_rc*) pre='(-(alpha|beta|rc)[0-9]+)?' ;;  # RC line: RCs and the GA
    *) pre='' ;;                                               # GA line: GA only
  esac
  latest=$(printf '%s' "$INDEX_REGULAR" \
    | grep -oE "asterisk-${maj}\.[0-9]+\.[0-9]+${pre}\.tar\.gz" \
    | sed -E -e 's/^asterisk-//' -e 's/\.tar\.gz$//' -e 's/-(alpha|beta|rc)/_\1/' \
    | while read -r v; do printf '%s %s\n' "$(relkey "$v")" "$v"; done \
    | sort -V | tail -1 | cut -d' ' -f2)
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
