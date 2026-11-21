#!/usr/bin/env bash
# Build the Android APK: magpie's gateway first, then the app around it.
#
#   ./scripts/build-apk.sh                     # both ABIs, release-signed
#   ./scripts/build-apk.sh --abis arm64-v8a    # one ABI (the phone build)
#   ./scripts/build-apk.sh --skip-gateway      # reuse the last gateway build
#   ./scripts/build-apk.sh --no-bun            # no bundled plugin runtime
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ANDROID="$ROOT/android"
VERSION="$(sed -n 's/^versionName=//p' "$ANDROID/version.properties")"
ABIS="${ABIS:-arm64-v8a,x86_64}"
SKIP_GATEWAY=0
NO_BUN=0
DEBUG=0
BUN_MIRROR="${MAGPIE_BUN_MIRROR:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --abis) ABIS="${2:?--abis needs a value}"; shift 2 ;;
        --skip-gateway) SKIP_GATEWAY=1; shift ;;
        --no-bun) NO_BUN=1; shift ;;
        --debug) DEBUG=1; shift ;;
        --bun-mirror) BUN_MIRROR="${2:?--bun-mirror needs a value}"; shift 2 ;;
        -h|--help) sed -n '1,20p' "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 1 ;;
    esac
done

# ---------------------------------------------------------------------------
# Bun: the external plugins' runtime. It goes in as
# jniLibs/<abi>/libmagpiebun.so, the one directory Android lets an app exec
# from; the shell points MAGPIE_BUN at it.
# ---------------------------------------------------------------------------
BUN_VERSION="1.4.5"
BUN_RELEASE="https://github.com/oven-sh/bun/releases/download"
declare -A BUN_TARGET=(
    ["arm64-v8a"]="bun-linux-aarch64-android"
    ["x86_64"]="bun-linux-x64-android-baseline"
)
declare -A BUN_SHA=(
    ["arm64-v8a"]="587471d26c8cc685debc5655cd5bf6d95d052a3b4a4956bdc922f8c6f1779396"
    ["x86_64"]="be89f1a91fe28f560a4fa51db860766e967109bdd6fcf370ff74d79228222c97"
)

fetch_bun() {
    local abi="$1" target="${BUN_TARGET[$1]}" want="${BUN_SHA[$1]}"
    local cache="$ANDROID/build/bun-cache/${target}.zip"
    local out="$ANDROID/app/src/main/jniLibs/${abi}/libmagpiebun.so"
    mkdir -p "$(dirname "$cache")" "$(dirname "$out")"
    if [[ -f "$cache" ]] && [[ "$(sha256sum "$cache" | cut -d' ' -f1)" == "$want" ]]; then
        echo "  $abi  cached ${cache#$ROOT/}"
    else
        local url="${BUN_RELEASE}/bun-v${BUN_VERSION}/${target}.zip"
        local source
        for source in ${BUN_MIRROR:+"${BUN_MIRROR%/}/$url"} "$url" "https://gh-proxy.com/$url"; do
            echo "  $abi  downloading $source"
            if curl -L --fail --retry 2 --connect-timeout 20 --speed-time 60 --speed-limit 1024 \
                --output "$cache.part" "$source"; then
                mv "$cache.part" "$cache"
                break
            fi
            rm -f "$cache.part"
        done
        if [[ ! -f "$cache" ]]; then
            rm -f "$out"
            echo "  no source had Bun $BUN_VERSION for $abi; leaving plugins off this build" >&2
            return 0
        fi
        local got
        got="$(sha256sum "$cache" | cut -d' ' -f1)"
        if [[ "$got" != "$want" ]]; then
            echo "  Bun $abi checksum mismatch: $got; plugins are left off" >&2
            rm -f "$cache"
            return 0
        fi
    fi
    unzip -p "$cache" "${target}/bun" > "$out"
    chmod 755 "$out"
    echo "        -> ${out#$ROOT/} ($(du -h "$out" | cut -f1))"
}

if [[ "$NO_BUN" == 1 ]]; then
    echo "plugins: --no-bun, external plugins will not run"
    IFS=',' read -ra requested <<< "$ABIS"
    for abi in "${requested[@]}"; do
        rm -f "$ANDROID/app/src/main/jniLibs/${abi// /}/libmagpiebun.so"
    done
else
    echo "plugins: Bun $BUN_VERSION"
    IFS=',' read -ra requested <<< "$ABIS"
    for abi in "${requested[@]}"; do
        abi="${abi// /}"
        [[ -n "$abi" ]] && fetch_bun "$abi"
    done
fi

if [[ "$SKIP_GATEWAY" == 0 ]]; then
    ABIS="$ABIS" "$ROOT/scripts/build-magpie-android.sh"
fi

# Gradle wants the SDK path; Android Studio writes this file itself.
SDK_ROOT="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-}}"
if [[ -z "$SDK_ROOT" ]]; then
    for candidate in "$ROOT/.toolchains/android-sdk" "$HOME/Android/Sdk" "/opt/android-sdk"; do
        [[ -d "$candidate" ]] && { SDK_ROOT="$candidate"; break; }
    done
fi
[[ -n "$SDK_ROOT" && -d "$SDK_ROOT" ]] || { echo "Android SDK not found; set ANDROID_HOME" >&2; exit 1; }
printf 'sdk.dir=%s\n' "$SDK_ROOT" > "$ANDROID/local.properties"

# AGP runs AAPT2, which Google ships only as an x86_64 Linux binary. On an
# ARM64 build host run it through qemu-user; on x86_64 use AGP's own copy.
GRADLE_ARGS=(--console=plain "-Pabis=$ABIS")
if [[ "$(uname -m)" == "aarch64" || "$(uname -m)" == "arm64" ]]; then
    command -v qemu-x86_64-static >/dev/null || { echo "qemu-x86_64-static is needed to run AAPT2 on ARM64" >&2; exit 1; }
    AAPT2="$SDK_ROOT/build-tools/37.0.0/aapt2"
    [[ -x "$AAPT2" ]] || { echo "missing $AAPT2" >&2; exit 1; }
    WRAPPER="$ANDROID/build/toolchains/aapt2"
    mkdir -p "$(dirname "$WRAPPER")"
    printf '#!/bin/sh\nexec qemu-x86_64-static -L / %q "$@"\n' "$AAPT2" > "$WRAPPER"
    chmod +x "$WRAPPER"
    GRADLE_ARGS+=("-Pandroid.aapt2FromMavenOverride=$WRAPPER")
fi

TASK=assembleRelease
[[ "$DEBUG" == 1 ]] && TASK=assembleDebug
if [[ -z "${JAVA_HOME:-}" ]]; then
    JAVA_BIN="$(command -v javac || true)"
    [[ -n "$JAVA_BIN" ]] && JAVA_HOME="$(dirname "$(dirname "$(readlink -f "$JAVA_BIN")")")"
fi
(
    cd "$ANDROID"
    ./gradlew "$TASK" "${GRADLE_ARGS[@]}"
)

APK="$ANDROID/app/build/outputs/apk/$( [[ "$DEBUG" == 1 ]] && echo debug || echo release )/app-$( [[ "$DEBUG" == 1 ]] && echo debug || echo release ).apk"
[[ -f "$APK" ]] || { echo "APK not found: $APK" >&2; exit 1; }
mkdir -p "$ROOT/dist"
if [[ "$ABIS" == *,* ]]; then
    NAME="magpie-android-universal.apk"
else
    NAME="magpie-android-${ABIS// /}.apk"
fi
cp "$APK" "$ROOT/dist/$NAME"
echo
echo "APK: ${ROOT#$ROOT/}/dist/$NAME ($(du -h "$ROOT/dist/$NAME" | cut -f1))"
echo "sha256: $(sha256sum "$ROOT/dist/$NAME" | cut -d' ' -f1)"
