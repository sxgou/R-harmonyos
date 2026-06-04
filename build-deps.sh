#!/bin/sh
# R dependencies for HarmonyOS
# ============================================================
# harmonybrew: https://gitcode.com/Harmonybrew/homebrew-harmony
# gfortran:    https://github.com/sxgou/gfortran-harmonyos
# OpenBLAS:    https://github.com/sxgou/openblas-harmonyos
#
# Preferred: install via harmonybrew
#   brew install bzip2 xz pcre2 openssl curl libpng freetype \
#              cairo geos gmp libxml2 pixman libjpeg unixodbc \
#              expat fontconfig pango cmake ninja libtiff \
#              pkgconf autoconf automake bison flex sccache \
#              libgit2 libsodium proj webp giflib mpfr
#
# Fallback (not yet in brew — manual build):
#   glpk, fftw, ANN, zeromq
#   Use build-all-simple.sh from ohos-libs, or build manually.
# ============================================================
set -e

# Derive project root from script location
PROJECT_ROOT=$(cd "$(dirname "$0")" && pwd)

export TMPDIR="${PROJECT_ROOT}/tmp"
mkdir -p "$TMPDIR"

HOMEBREW_PREFIX=/storage/Users/currentUser/.harmonybrew
BREW=$HOMEBREW_PREFIX/bin/brew

echo "=== Installing R dependencies via harmonybrew ==="
echo ""

# Install all brew-available dependencies
# The --formula flag ensures we don't accidentally install a cask
$BREW install --formula 2>/dev/null \
  bzip2 xz pcre2 curl libpng freetype cairo geos gmp \
  libxml2 pixman libjpeg unixodbc expat fontconfig \
  pango cmake ninja libtiff pkgconf autoconf automake \
  bison flex sccache libgit2 libsodium proj webp giflib mpfr

# openssl@3 is likely already installed (ohos-sdk dep), but ensure it
$BREW install --formula openssl@3 2>/dev/null || true

echo ""
echo "=== Brew packages installed ==="
echo ""

# Create R-deps directory for non-brew packages
PREFIX=/storage/Users/currentUser/.local/R-deps
mkdir -p "$PREFIX/lib" "$PREFIX/include"

# --- Packages below this line are NOT yet in brew ---
# They were cross-compiled using ohos-libs and are available
# at ~/.local/R-deps/.  The brew equivalents (installed above)
# are at $HOMEBREW_PREFIX/{include,lib}.
#
# If you need glpk, fftw, ANN, or zeromq, install them manually:
#   git clone https://github.com/sxgou/ohos-libs.git
#   cd ohos-libs/scripts && bash build-all-simple.sh
echo ""
echo "=== Manual packages still at ~/.local/R-deps/ ==="
echo "  GLPK, FFTW, ANN, zeromq — still not yet in brew."
echo "  mpfr was previously manual, now available via brew."
echo "  Build via ohos-libs if needed."
echo ""

# Verify key headers/libs are findable
echo "=== Verification ==="
for lib in libbz2.a liblzma.a libpcre2-8.a libpng.a libjpeg.a libgmp.a; do
  if [ -f "$HOMEBREW_PREFIX/lib/$lib" ] || [ -f "$HOMEBREW_PREFIX/opt/*/lib/$lib" ]; then
    echo "  [OK] $lib found (brew)"
  elif [ -f "$PREFIX/lib/$lib" ]; then
    echo "  [OK] $lib found (manual)"
  else
    echo "  [WARN] $lib not found"
  fi
done

echo ""
echo "=== Done ==="
echo "Run ./configure-R.sh to configure R with the installed dependencies."
