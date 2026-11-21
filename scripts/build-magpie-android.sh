#!/usr/bin/env bash
# Build magpie's gateway for Android and put it where the app finds it.
#
# Each ABI becomes android/app/src/main/jniLibs/<abi>/libmagpie.so: an APK can
# only carry an executable as a library, and the one directory Android lets an
# app exec from is its native library directory.
#
# The gateway uses cgo for Bionic's DNS resolver. On an x86_64 build host this
# script uses the NDK's own clang wrappers. On an ARM64 Linux host (for
# example a phone running Ubuntu under proot) the NDK's host binaries are
# x86_64 only, so it uses the distro's native clang-19 with the NDK sysroot.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPSTREAM="${UPSTREAM:-$ROOT/upstream}"
VERSION="$(sed -n 's/^versionName=//p' "$ROOT/android/version.properties")"
ABIS="${ABIS:-arm64-v8a,x86_64}"
API_LEVEL="${API_LEVEL:-37}"

if [[ ! -f "$UPSTREAM/go.mod" ]] || ! grep -q '^module github.com/yetone/magpie' "$UPSTREAM/go.mod"; then
    echo "not a magpie source tree: $UPSTREAM" >&2
    exit 1
fi

find_ndk() {
    local candidate
    for candidate in "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}" "${ANDROID_NDK:-}" \
        "${ANDROID_HOME:-}/ndk/30.0.16248370" "${ANDROID_SDK_ROOT:-}/ndk/30.0.16248370" \
        "$ROOT/.toolchains/android-sdk/ndk/30.0.16248370"; do
        [[ -n "$candidate" && -d "$candidate/toolchains/llvm/prebuilt" ]] && { echo "$candidate"; return; }
    done
    echo "Android NDK r30 not found; set ANDROID_NDK_HOME" >&2
    exit 1
}

NDK="$(find_ndk)"
NDK_PREBUILT="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
NDK_BIN="$NDK_PREBUILT/bin"
SYSROOT="$NDK_PREBUILT/sysroot"
BUILD_TOOLS="$ROOT/android/build/toolchains"
mkdir -p "$BUILD_TOOLS"

GO_BIN="${GO_BIN:-$(command -v go || true)}"
if [[ -z "$GO_BIN" || ! -x "$GO_BIN" ]]; then
    echo "go not found; install Go 1.27.4 or set GO_BIN" >&2
    exit 1
fi

host_arch="$(uname -m)"
native_clang="$(command -v clang-19 || command -v clang || true)"
native_lld="$(command -v ld.lld-19 || command -v ld.lld || true)"

make_native_cc() {
    local target_arch="$1" goarch="$2"
    local clang="$native_clang" lld="$native_lld"
    if [[ -z "$clang" || -z "$lld" ]]; then
        echo "native clang/lld not found; on ARM64 install clang-19 and lld-19" >&2
        exit 1
    fi
    local builtins="$NDK_PREBUILT/lib/clang/21/lib/linux/libclang_rt.builtins-${target_arch}-android.a"
    if [[ ! -f "$builtins" ]]; then
        builtins="$(find "$NDK_PREBUILT/lib/clang" -name "libclang_rt.builtins-${target_arch}-android.a" | head -1)"
    fi
    [[ -f "$builtins" ]] || { echo "no compiler-rt builtins for $target_arch" >&2; exit 1; }
    local libdir="$BUILD_TOOLS/libgcc-$goarch"
    mkdir -p "$libdir"
    ln -sf "$builtins" "$libdir/libgcc.a"
    local wrapper="$BUILD_TOOLS/cc-$goarch"
    cat > "$wrapper" <<WRAP
#!/bin/sh
exec "$clang" --target=${target_arch}-linux-android${API_LEVEL} --sysroot="$SYSROOT" \
  -fuse-ld=lld --ld-path="$lld" -Wno-unused-command-line-argument -L"$libdir" "\$@"
WRAP
    chmod +x "$wrapper"
    echo "$wrapper"
}

build_one() {
    local abi="$1" goarch target cc
    case "$abi" in
        arm64-v8a) goarch=arm64; target=aarch64 ;;
        x86_64) goarch=amd64; target=x86_64 ;;
        *) echo "unsupported ABI: $abi (arm64-v8a, x86_64)" >&2; exit 1 ;;
    esac
    if [[ "$host_arch" == "aarch64" || "$host_arch" == "arm64" ]]; then
        cc="$(make_native_cc "$target" "$goarch")"
    else
        cc="$NDK_BIN/${target}-linux-android${API_LEVEL}-clang"
        [[ -x "$cc" ]] || { echo "missing NDK compiler: $cc" >&2; exit 1; }
    fi
    local out="$ROOT/android/app/src/main/jniLibs/$abi/libmagpie.so"
    mkdir -p "$(dirname "$out")"
    echo "  $abi  android/$goarch"
    (
        cd "$UPSTREAM"
        CGO_ENABLED=1 GOOS=android GOARCH="$goarch" CC="$cc" \
        GOTOOLCHAIN=local GOPROXY="${GOPROXY:-https://goproxy.cn,direct}" \
        "$GO_BIN" build -tags nogui -trimpath -buildvcs=false \
            -ldflags="-s -w -X main.version=$VERSION" -o "$out" .
    )
    chmod 755 "$out"
    echo "        -> ${out#$ROOT/} ($(du -h "$out" | cut -f1))"
}

echo "magpie source: $UPSTREAM"
echo "version:       $VERSION"
echo "NDK:           $NDK"
IFS=',' read -ra requested <<< "$ABIS"
for abi in "${requested[@]}"; do
    abi="${abi// /}"
    [[ -n "$abi" ]] && build_one "$abi"
done
echo "done. build the app with scripts/build-apk.sh"
