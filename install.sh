#!/bin/sh
# Openness installer for Linux and macOS (amd64, arm64).
#
#   curl -fsSL https://raw.githubusercontent.com/s4e-io/openness/main/install.sh | sh
#
# Installs the latest releases of:
#   openness-collector (collector, from github.com/s4e-io/openness-collector)
#   openness-resolver  (resolver,  from github.com/s4e-io/openness-resolver)
#
# Every download is verified against the release's SHA256SUMS file before it
# is installed. Nothing is installed system wide and nothing runs as root.
#
# Environment variables:
#   OPENNESS_INSTALL_DIR        install directory (default: $HOME/.local/bin)
#   GITHUB_TOKEN or GH_TOKEN    GitHub token, sent as a Bearer token. Needed while
#                               a release needs authentication.
#   OPENNESS_COMPONENTS         space separated subset of "collector resolver"
#                               (default: both)
#   OPENNESS_COLLECTOR_VERSION  release tag to install instead of the latest (e.g. v0.4.9)
#   OPENNESS_RESOLVER_VERSION   release tag to install instead of the latest (e.g. v0.1.0)
#   OPENNESS_DRY_RUN=1          resolve versions and assets, print the plan, install nothing
#
# Testing overrides (not needed for normal use):
#   OPENNESS_OS, OPENNESS_ARCH  pretend to be another platform (linux|darwin, amd64|arm64)
#   OPENNESS_LOCAL_RELEASES     read releases from a local directory instead of GitHub.
#                               Layout: <dir>/<repo>/LATEST (contains the tag, e.g. v0.4.9)
#                                       <dir>/<repo>/<tag>/<asset files and SHA256SUMS>

set -eu

GITHUB_OWNER="s4e-io"
COLLECTOR_REPO="openness-collector"
RESOLVER_REPO="openness-resolver"
GITHUB_API="https://api.github.com"

INSTALL_DIR="${OPENNESS_INSTALL_DIR:-$HOME/.local/bin}"
TOKEN="${GITHUB_TOKEN:-${GH_TOKEN:-}}"
COMPONENTS="${OPENNESS_COMPONENTS:-collector resolver}"
DRY_RUN="${OPENNESS_DRY_RUN:-0}"
LOCAL_RELEASES="${OPENNESS_LOCAL_RELEASES:-}"

TMP_DIR=""
INSTALLED=""
FAILED=""

say() { printf '%s\n' "$*"; }
warn() { printf 'openness-install: %s\n' "$*" >&2; }
die() {
	warn "error: $*"
	exit 1
}

cleanup() {
	if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
		rm -rf "$TMP_DIR"
	fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

has() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------

detect_os() {
	if [ -n "${OPENNESS_OS:-}" ]; then
		printf '%s' "$OPENNESS_OS"
		return
	fi
	case "$(uname -s)" in
	Linux) printf 'linux' ;;
	Darwin) printf 'darwin' ;;
	MINGW* | MSYS* | CYGWIN* | Windows_NT)
		die "this is Windows. Use the PowerShell installer instead:
  irm https://raw.githubusercontent.com/s4e-io/openness/main/install.ps1 | iex"
		;;
	*) die "unsupported operating system: $(uname -s). Supported: Linux, macOS (and Windows via install.ps1)." ;;
	esac
}

detect_arch() {
	if [ -n "${OPENNESS_ARCH:-}" ]; then
		printf '%s' "$OPENNESS_ARCH"
		return
	fi
	_m="$(uname -m)"
	case "$_m" in
	x86_64 | amd64)
		# A shell running under Rosetta reports x86_64 on Apple silicon.
		if [ "$(uname -s)" = "Darwin" ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" = "1" ]; then
			printf 'arm64'
		else
			printf 'amd64'
		fi
		;;
	aarch64 | arm64) printf 'arm64' ;;
	*) die "unsupported CPU architecture: $_m. Supported: amd64 (x86_64), arm64 (aarch64)." ;;
	esac
}

# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

# http_get <url> <output file> [accept header]
# Prints the HTTP status code on stdout. Returns non-zero on transport errors.
http_get() {
	_url="$1"
	_out="$2"
	_accept="${3:-application/vnd.github+json}"
	if has curl; then
		if [ -n "$TOKEN" ]; then
			# curl drops the Authorization header when a redirect leaves the
			# original host, so the token never reaches the asset CDN.
			curl -sSL --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 20 \
				-H "Accept: $_accept" \
				-H "Authorization: Bearer $TOKEN" \
				-H "X-GitHub-Api-Version: 2022-11-28" \
				-o "$_out" -w '%{http_code}' "$_url"
		else
			curl -sSL --proto '=https' --tlsv1.2 --retry 3 --connect-timeout 20 \
				-H "Accept: $_accept" \
				-o "$_out" -w '%{http_code}' "$_url"
		fi
	elif has wget; then
		if [ -n "$TOKEN" ]; then
			# wget may forward the Authorization header across redirects,
			# which the asset CDN rejects. Require curl in that case.
			die "a GitHub token is set but curl is not installed. Install curl and retry."
		fi
		if wget -q --header="Accept: $_accept" -O "$_out" "$_url"; then
			printf '200'
		else
			printf '000'
		fi
	else
		die "neither curl nor wget is installed. Install curl and retry."
	fi
}

api_hint() {
	if [ -z "$TOKEN" ]; then
		say "The release could not be fetched without authentication. Set GH_TOKEN (or GITHUB_TOKEN)
to a token of a GitHub account that has access, for example:
  GH_TOKEN=\$(gh auth token) sh install.sh"
	else
		say "Check that the token is valid and that its account has access to github.com/$GITHUB_OWNER/<repo>."
	fi
}

# ---------------------------------------------------------------------------
# Release lookup
# ---------------------------------------------------------------------------

# fetch_release <repo> <tag or empty> <output json file>
# Writes the release JSON and prints the tag name.
fetch_release() {
	_repo="$1"
	_want="$2"
	_json="$3"

	if [ -n "$LOCAL_RELEASES" ]; then
		if [ -n "$_want" ]; then
			_tag="$_want"
		else
			[ -f "$LOCAL_RELEASES/$_repo/LATEST" ] || die "local release dir has no $_repo/LATEST file"
			_tag="$(tr -d ' \t\r\n' <"$LOCAL_RELEASES/$_repo/LATEST")"
		fi
		[ -d "$LOCAL_RELEASES/$_repo/$_tag" ] || die "local release dir has no $_repo/$_tag"
		: >"$_json"
		printf '%s' "$_tag"
		return
	fi

	if [ -n "$_want" ]; then
		_url="$GITHUB_API/repos/$GITHUB_OWNER/$_repo/releases/tags/$_want"
	else
		_url="$GITHUB_API/repos/$GITHUB_OWNER/$_repo/releases/latest"
	fi
	_code="$(http_get "$_url" "$_json")" || die "could not reach $GITHUB_API (network error)"
	case "$_code" in
	200) ;;
	401)
		api_hint >&2
		die "GitHub rejected the token (HTTP 401) for $_repo"
		;;
	403 | 429)
		api_hint >&2
		die "GitHub refused the request for $_repo (HTTP $_code, possibly the anonymous rate limit)"
		;;
	404)
		api_hint >&2
		if [ -n "$_want" ]; then
			die "release $_want of $GITHUB_OWNER/$_repo was not found (HTTP 404)"
		fi
		die "no release of $GITHUB_OWNER/$_repo was found (HTTP 404)"
		;;
	*) die "unexpected HTTP $_code from $_url" ;;
	esac

	_tag="$(tr -d '\n\r' <"$_json" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
	[ -n "$_tag" ] || die "could not read tag_name from the $_repo release"
	printf '%s' "$_tag"
}

# release_assets <repo> <tag> <release json>
# Prints one asset name per line.
release_assets() {
	if [ -n "$LOCAL_RELEASES" ]; then
		ls -1 "$LOCAL_RELEASES/$1/$2"
		return
	fi
	# Split the JSON at braces so every asset starts a new line, then pick the
	# "name" of each object whose "url" is a release asset URL.
	tr -d '\n\r' <"$3" | tr '{' '\n' | tr '}' '\n' |
		grep '"url"[[:space:]]*:[[:space:]]*"[^"]*/releases/assets/[0-9]*"' |
		sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

# asset_api_url <asset name> <release json>
# Prints the API URL of an asset (works for public and private repositories).
asset_api_url() {
	tr -d '\n\r' <"$2" | tr '{' '\n' | tr '}' '\n' |
		grep "\"name\"[[:space:]]*:[[:space:]]*\"$1\"" |
		sed -n 's/.*"url"[[:space:]]*:[[:space:]]*"\([^"]*\/releases\/assets\/[0-9]*\)".*/\1/p' |
		head -n 1
}

# download_asset <repo> <tag> <asset name> <release json> <output file>
download_asset() {
	_repo="$1"
	_tag="$2"
	_name="$3"
	_json="$4"
	_out="$5"
	if [ -n "$LOCAL_RELEASES" ]; then
		cp "$LOCAL_RELEASES/$_repo/$_tag/$_name" "$_out"
		return
	fi
	if [ -n "$TOKEN" ]; then
		_url="$(asset_api_url "$_name" "$_json")"
		[ -n "$_url" ] || die "could not find the download URL of $_name in the $_repo $_tag release"
		_code="$(http_get "$_url" "$_out" "application/octet-stream")" || die "download of $_name failed (network error)"
	else
		_url="https://github.com/$GITHUB_OWNER/$_repo/releases/download/$_tag/$_name"
		_code="$(http_get "$_url" "$_out" "application/octet-stream")" || die "download of $_name failed (network error)"
	fi
	[ "$_code" = "200" ] || die "download of $_name failed (HTTP $_code)"
}

# ---------------------------------------------------------------------------
# Checksums
# ---------------------------------------------------------------------------

sha256_of() {
	if has sha256sum; then
		sha256sum "$1" | awk '{print $1}'
	elif has shasum; then
		shasum -a 256 "$1" | awk '{print $1}'
	else
		die "neither sha256sum nor shasum is installed, cannot verify downloads"
	fi
}

# verify <file> <asset name> <SHA256SUMS file>
verify() {
	_expected="$(awk -v n="$2" '{ f = $2; sub(/^\*/, "", f); if (f == n) { print $1; exit } }' "$3")"
	[ -n "$_expected" ] || die "$2 is not listed in SHA256SUMS, refusing to install it"
	_actual="$(sha256_of "$1")"
	if [ "$_expected" != "$_actual" ]; then
		die "checksum mismatch for $2
  expected $_expected
  got      $_actual"
	fi
}

# ---------------------------------------------------------------------------
# Install one component
# ---------------------------------------------------------------------------

# install_component <collector|resolver>
install_component() {
	case "$1" in
	collector)
		_repo="$COLLECTOR_REPO"
		_prefix="openness-collector"
		_bin="openness-collector"
		_want="${OPENNESS_COLLECTOR_VERSION:-}"
		;;
	resolver)
		_repo="$RESOLVER_REPO"
		_prefix="openness-resolver"
		_bin="openness-resolver"
		_want="${OPENNESS_RESOLVER_VERSION:-}"
		;;
	*) die "unknown component: $1 (use collector and/or resolver)" ;;
	esac

	_json="$TMP_DIR/$_repo.json"
	_tag="$(fetch_release "$_repo" "$_want" "$_json")"
	_ver="${_tag#v}"
	_asset="${_prefix}_${_ver}_${OS}_${ARCH}"
	_list="$TMP_DIR/$_repo.assets"
	release_assets "$_repo" "$_tag" "$_json" >"$_list"
	# Collector releases before the rename publish openness_<version>_<os>_<arch>.
	if [ "$1" = "collector" ] && ! grep -qxF "$_asset" "$_list" && grep -qxF "openness_${_ver}_${OS}_${ARCH}" "$_list"; then
		_prefix="openness"
		_asset="openness_${_ver}_${OS}_${ARCH}"
	fi

	if ! grep -qxF "$_asset" "$_list"; then
		_avail="$(sed -n "s/^${_prefix}_${_ver}_\(.*\)$/\1/p" "$_list" | sed 's/\.exe$//' | tr '\n' ' ')"
		warn "error: $_repo $_tag has no build for $OS/$ARCH (expected asset $_asset)."
		warn "       platforms in this release: ${_avail:-none}"
		if [ "$OS" = "darwin" ]; then
			if [ "$1" = "collector" ]; then
				warn "       Note: on macOS the collector only runs its CLI helpers (validate, inspect, login)."
				warn "       To collect evidence, run the collector on the Linux or Windows host you want to"
				warn "       assess, or collect from a Mac with Docker. A macOS build of the collector"
				warn "       ships with the next collector release."
			else
				warn "       macOS builds of the resolver ship with the next resolver release."
				warn "       Until then run the Linux build in Docker, or build from source with Go."
			fi
		fi
		FAILED="$FAILED $1"
		return 0
	fi

	if [ "$DRY_RUN" = "1" ]; then
		say "[dry-run] $1: would install $_repo $_tag asset $_asset as $INSTALL_DIR/$_bin"
		INSTALLED="$INSTALLED $_bin"
		return 0
	fi

	grep -qxF "SHA256SUMS" "$_list" || die "$_repo $_tag has no SHA256SUMS file, refusing to install unverified binaries"

	say "Downloading $_asset ($_repo $_tag)"
	download_asset "$_repo" "$_tag" "SHA256SUMS" "$_json" "$TMP_DIR/$_repo.SHA256SUMS"
	download_asset "$_repo" "$_tag" "$_asset" "$_json" "$TMP_DIR/$_asset"
	verify "$TMP_DIR/$_asset" "$_asset" "$TMP_DIR/$_repo.SHA256SUMS"
	say "Checksum OK"

	chmod 0755 "$TMP_DIR/$_asset"
	# Move into place through a temporary name in the target directory so a
	# running binary is never left half written.
	cp "$TMP_DIR/$_asset" "$INSTALL_DIR/.$_bin.tmp.$$"
	mv -f "$INSTALL_DIR/.$_bin.tmp.$$" "$INSTALL_DIR/$_bin"
	INSTALLED="$INSTALLED $_bin"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
	OS="$(detect_os)"
	ARCH="$(detect_arch)"
	case "$OS" in linux | darwin) ;; *) die "unsupported OS override: $OS" ;; esac
	case "$ARCH" in amd64 | arm64) ;; *) die "unsupported arch override: $ARCH" ;; esac

	say "Openness installer (beta)"
	say "Platform: $OS/$ARCH"
	say "Install directory: $INSTALL_DIR"
	if [ -n "$LOCAL_RELEASES" ]; then
		say "Release source: local directory $LOCAL_RELEASES"
	elif [ -n "$TOKEN" ]; then
		say "Release source: GitHub (authenticated)"
	else
		say "Release source: GitHub (anonymous)"
	fi
	say ""

	if [ -z "$LOCAL_RELEASES" ]; then
		if ! has curl; then
			has wget || die "neither curl nor wget is installed. Install curl and retry."
			[ -z "$TOKEN" ] || die "a GitHub token is set but curl is not installed. Install curl and retry."
		fi
	fi
	has sha256sum || has shasum || die "neither sha256sum nor shasum is installed, cannot verify downloads"

	TMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t openness)"
	if [ "$DRY_RUN" != "1" ]; then
		mkdir -p "$INSTALL_DIR" || die "cannot create $INSTALL_DIR"
		[ -w "$INSTALL_DIR" ] || die "$INSTALL_DIR is not writable. Set OPENNESS_INSTALL_DIR to a directory you own."
	fi

	for _c in $COMPONENTS; do
		install_component "$_c"
	done

	if [ -z "$INSTALLED" ]; then
		die "nothing was installed (no build for $OS/$ARCH:$FAILED)."
	fi

	say ""
	if [ "$DRY_RUN" = "1" ]; then
		say "Dry run finished, nothing was installed."
	else
		say "Installed:"
		for _b in $INSTALLED; do
			_v="$("$INSTALL_DIR/$_b" version 2>&1 | head -n 1)" || _v="(could not run '$_b version': $_v)"
			say "  $INSTALL_DIR/$_b  $_v"
		done
	fi

	case ":$PATH:" in
	*":$INSTALL_DIR:"*) ;;
	*)
		say ""
		say "$INSTALL_DIR is not on your PATH. Add it, for example:"
		say "  echo 'export PATH=\"$INSTALL_DIR:\$PATH\"' >> ~/.profile && . ~/.profile"
		;;
	esac

	say ""
	say "Next steps:"
	say "  1. Collect evidence on the host to assess (root gives fuller evidence):"
	say "       sudo \"$INSTALL_DIR/openness-collector\" collect --output ./host.openness"
	if [ "$OS" = "darwin" ]; then
		say "     macOS hosts cannot be collected natively. Run this on a Linux or Windows host,"
		say "     or collect from a Mac with Docker."
	fi
	say "  2. Download only the advisory feeds that evidence needs:"
	say "       openness-resolver feed sync --for ./host.openness --data-dir ./openness-data"
	say "  3. Resolve findings:"
	say "       openness-resolver resolve --input ./host.openness --output findings.json --data-dir ./openness-data"
	say ""
	say "Openness is in beta and licensed under the Apache License 2.0. Developed and maintained by S4E: https://s4e.io"

	if [ -n "$FAILED" ]; then
		say ""
		warn "not installed:$FAILED (see the errors above)"
		exit 1
	fi
}

main "$@"
