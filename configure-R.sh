#!/bin/sh
# Configure R 4.4.3 for HarmonyOS (OpenHarmony) — optimized for brew
# Run this from the project root to (re)configure the build.
# After configuring, run: cd build && make
#
# Changes from previous version:
#   - R deps now installed via brew instead of manual cross-compilation
#   - readline enabled (brew provides ncurses + readline)
#   - ICU enabled (brew provides icu4c@78)
#   - System libs used where available (zlib, bzip2, pcre2, xz, curl)
#   - PKG_CONFIG_PATH set to brew's pkgconfig for auto-detection
#   - Removed redundant R-deps paths (only 4 libs remain there: fftw, zeromq, ANN, mpfr)
#   - lld instead of bfd: hmdfs requires .codesign section (lld only) and rejects
#     bfd-linked shared libs with EACCES at dlopen() time
#   - -Wl,-rpath in LDFLAGS: lld doesn't auto-embed -L paths as rpath like bfd did
#   - X11 enabled (brew provides libX11, libXext, libXt, plus cairo-X11 backend)
#   - libtiff enabled (brew provides libtiff, auto-detected via pkg-config)
#   - cairo: --no-as-needed wrappers in X11/cairo Makefiles force libcairo.so/freetype
#     into NEEDED since lld strips them with default --as-needed
#   - Stale libcairo.a/libfreetype.a in R-deps/lib removed: they took precedence over
#     brew's libcairo.so in -L search order, causing static linking and missing NEEDED
#
# ================================================================
# R System Library Dependencies for HarmonyOS aarch64
# ================================================================
#
# brew provides (all static + shared libs available):
#   bzip2, xz, pcre2, curl, libpng, freetype, cairo, geos, gmp,
#   libxml2, unixodbc, expat, fontconfig, glpk, pixman, icu4c@78,
#   libjpeg-turbo, readline, ncurses, harfbuzz, fribidi
# brew also provides X11 stack (auto-detected via pkg-config):
#   libX11, libXext, libXt, libSM, libICE, libxcb, xorgproto
# brew provides libtiff (auto-detected via pkg-config)
#
# Manual (R-deps, ~/.local/R-deps):
#   fftw3, zeromq, ANN, mpfr  — not yet in brew
#
# BLAS/LAPACK: R's internal reference BLAS (no OpenBLAS in brew)
# Java: BiSheng JDK 17.0.13 (system path)
# Fortran: gfortran 14.2.0 (manual, ~/.local/gfortran)
#
# ================================================================
set -e

# Version selection:  bash configure-R.sh [version]
# Default is R 4.4.3.  Examples:
#   bash configure-R.sh          # configure R 4.4.3
#   bash configure-R.sh 4.6.0    # configure R 4.6.0
R_VERSION="${1:-4.4.3}"

export TMPDIR=/storage/Users/currentUser/R-harmonyos/tmp
export CONFIG_SHELL=/data/service/hnp/bin/bash
export SHELL=/data/service/hnp/bin/bash
umask 022
mkdir -p "$TMPDIR"

R_SRC=/storage/Users/currentUser/R-harmonyos/src/R-${R_VERSION}
BUILD_DIR=/storage/Users/currentUser/R-harmonyos/build
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

OHOS_CLANG=/data/service/hnp/bin/aarch64-unknown-linux-ohos-clang
OHOS_CLANGXX=/data/service/hnp/bin/aarch64-unknown-linux-ohos-clang++
GFORTRAN=/storage/Users/currentUser/.local/gfortran/bin/gfortran
SYSROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot
OHOS_LLVM_ROOT=${SYSROOT%/sysroot}/llvm
OHOS_LLVM_LIB=${OHOS_LLVM_ROOT}/lib
GFORTRAN_LIB=/storage/Users/currentUser/.local/gfortran/lib64
GCC_LIB=/storage/Users/currentUser/.local/gfortran/lib/gcc/aarch64-unknown-linux-ohos/14.2.0
RDEPS=/storage/Users/currentUser/.local/R-deps
HOMEBREW_PREFIX=/storage/Users/currentUser/.harmonybrew

# Java (BiSheng JDK 17) - for JNI header detection and Java class compilation
JAVA_HOME=/data/service/hnp/bishengjdk17.0.13_06.org/bishengjdk17.0.13_06_0.13_06
JAVA=/data/service/hnp/bin/java
JAVAC=/data/service/hnp/bin/javac
JAR=/data/service/hnp/bin/jar
JAVA_CPPFLAGS="-I${JAVA_HOME}/include -I${JAVA_HOME}/include/linux"
JAVA_LIBS="-L${JAVA_HOME}/lib/server -ljvm"
export JAVA_HOME JAVA JAVAC JAR JAVA_CPPFLAGS JAVA_LIBS

# Library path for running test binaries
# NOTE: Do NOT add ${HOMEBREW_PREFIX}/lib here — brew's libxml2.so.16
# conflicts with OHOS SDK's libxml2 (lld needs the SDK's version at runtime).
# Instead add OHOS_LLVM_LIB so lld can find its own libxml2 dependency.
export LD_LIBRARY_PATH="${OHOS_LLVM_LIB}:${HOMEBREW_PREFIX}/lib:${GFORTRAN_LIB}:${GCC_LIB}:$LD_LIBRARY_PATH"

# Use lld wrapper instead of GNU ld (bfd) because hmdfs requires the .codesign
# section that only lld generates.  Without .codesign, hmdfs refuses to
# execute binaries and dlopen() rejects shared libraries with EACCES.
#
# The wrapper sets LD_LIBRARY_PATH so lld can find its own libxml2 at runtime
# (HarmonyOS musl ld.so doesn't support $ORIGIN in RUNPATH).
LLD_WRAPPER=/storage/Users/currentUser/.local/bin/ohos-lld-wrapper
USE_LD="-fuse-ld=${LLD_WRAPPER}"

# Timezone
export TZ=CST-8

# Apply HarmonyOS patches to R source tree
echo "Applying HarmonyOS patches to ${R_SRC} (R-${R_VERSION})..."
bash "${R_SRC}/../../apply-patches.sh" "${R_VERSION}" 2>&1 || {
    echo "Warning: patch application failed. Continuing anyway."
    echo "Some patches may already be applied."
}

# Clean build directory to avoid stale cache
rm -f config.cache config.status

# PKG_CONFIG_PATH: brew provides all .pc files.
# Custom ICU (locally-built with valid .codesign) takes precedence.
# Note: share/pkgconfig needed for xorgproto (X11 proto .pc files)
ICU_INSTALL=/storage/Users/currentUser/.local/R-deps
export PKG_CONFIG_PATH="${ICU_INSTALL}/lib/pkgconfig:${HOMEBREW_PREFIX}/lib/pkgconfig:${HOMEBREW_PREFIX}/share/pkgconfig:${RDEPS}/lib/pkgconfig"

# ICU data: the prebuilt icudt78l.dat provides full locale/collation/break data.
# The stub libicudata.so (locally compiled) only provides the entry point symbol;
# ICU loads the actual data from this file at runtime.
export ICU_DATA="${ICU_INSTALL}/share/icu/78.3"

# Pre-seed configure cache variables to skip runtime tests (blocked by seccomp)
# and link tests that fail due to missing libraries on HarmonyOS
for cv in \
    r_cv_mixed_c_fortran=yes \
    r_cv_double_complex_agree=yes \
    r_cv_working_mktime=yes \
    r_cv_working_mktime1=yes \
    r_cv_working_mktime2=yes \
    r_cv_working_calloc=yes \
    r_cv_working_isfinite=yes \
    r_cv_working_log1p=yes \
    r_cv_ftell_append=yes \
    r_cv_working_sigaction=yes \
    ac_cv_prog_cc_cross=yes \
    cross_compiling=yes \
    r_cv_header_zlib_h=yes \
    r_cv_have_bzlib=yes \
    r_cv_have_lzma=yes \
    r_cv_have_pcre2utf=yes \
    r_cv_have_curl728=yes \
    r_cv_have_curl_https=yes \
    r_cv_size_max=yes \
    ac_cv_have_decl_SIZE_MAX=yes \
    ac_cv_lib_m_cos=yes \
    ac_cv_lib_m_sin=yes \
    ac_cv_lib_dl_dlopen=yes \
    ac_cv_func_iconv=yes \
    ac_cv_have_decl_mbrtowc=yes \
    ac_cv_have_decl_wcrtomb=yes \
    ac_cv_have_decl_wcscoll=yes \
    ac_cv_have_decl_wcsftime=yes \
    ac_cv_have_decl_wcstod=yes \
    ac_cv_have_decl_mbstowcs=yes \
    ac_cv_have_decl_wcstombs=yes \
    ac_cv_have_decl_wctrans=yes \
    ac_cv_have_decl_wctype=yes \
    ac_cv_have_decl_iswctype=yes \
    ac_cv_have_decl_wcwidth=yes \
    ac_cv_have_decl_wcswidth=yes \
    ac_cv_type_wctrans_t=yes \
    ac_cv_type_mbstate_t=yes \
    lt_cv_truncate_bin="/usr/bin/dd bs=4096 count=1" \
    ac_cv_have_decl_size_max=yes \
    r_cv_cairo_works=yes \
    r_cv_icu=yes \
    ac_cv_lib_readline_rl_callback_read_char=yes \
    ac_cv_lib_ncurses_main=yes \
    ac_cv_lib_termcap_main=yes \
    ac_cv_lib_termlib_main=yes \
    ac_cv_lib_tinfo_main=yes; do
    export "$cv"
done

# Run configure
# Brew provides readline, ICU, libcurl, libpng, jpeg, etc.
# R's configure auto-detects them via pkg-config with PKG_CONFIG_PATH set.
#
# Intentionally disabled (not available or not useful on HarmonyOS):
#   --without-tcltk       (no Tcl/Tk)
#   --without-aqua        (macOS only)
#
# X11 (libx11 + xorgproto) and libtiff are now provided by brew and auto-detected
# via pkg-config.  X11 requires a running X server (XWayland or SSH -X), but
# Cairo's PNG/SVG/PDF backends work without it.  libtiff is used by the tiff()
# graphics device.
#
# Known limitations:
#   - cairo_ps() fails: cairo's PS backend uses tmpfile()/mkstemp() in /tmp,
#     which is read-only on HarmonyOS. cairo_pdf/svg/png(type="cairo") work.
#   - Stale libcairo.a/libfreetype.a in ~/.local/R-deps/lib: if present, lld
#     finds them before brew's libcairo.so (since -L R-deps comes before -L brew
#     in search path), resulting in static linking and missing DT_NEEDED entries.
#     Remove them if you see "symbol not found" errors for cairo_xlib_surface_create
#     at runtime:  mv ~/.local/R-deps/lib/libcairo*.a ~/.local/R-deps/lib/stale/
#
# OpenBLAS is used via harmonybrew: --with-blas="-lopenblas" enables SIMD
# optimized BLAS + LAPACK (10-50x speedup vs R's internal reference BLAS).
#
# Some system libs are explicitly requested so R uses brew's versions
# instead of bundled copies. Others (libcurl, libpng, libjpeg, readline,
# ICU, X11) are auto-detected via pkg-config and don't need explicit flags.
#
# LD_LIBRARY_PATH must be set directly on the configure command line because
# HarmonyOS's bash doesn't always propagate exported env vars to linker
# subprocesses (lld needs OHOS_LLVM_LIB for libxml2 at runtime).
LD_LIBRARY_PATH="${OHOS_LLVM_LIB}:${GFORTRAN_LIB}:${GCC_LIB}:${LD_LIBRARY_PATH}" \
"$R_SRC/configure" \
    --build=x86_64-pc-linux-gnu \
    --host=aarch64-pc-linux-musl \
    --prefix=/storage/Users/currentUser/.local/R \
    --enable-R-shlib \
    --without-tcltk \
    --without-aqua \
    --with-blas="-lopenblas" \
    --with-lapack \
    --with-readline \
    --enable-java \
    --with-pcre2 \
    CC="$OHOS_CLANG" \
    CXX="$OHOS_CLANGXX" \
    FC="$GFORTRAN" \
    F77="$GFORTRAN" \
    CFLAGS="-O2 -g0 --sysroot=$SYSROOT -I${HOMEBREW_PREFIX}/include -I${ICU_INSTALL}/include -I${RDEPS}/include" \
    CXXFLAGS="-O2 -g0 --sysroot=$SYSROOT -I${HOMEBREW_PREFIX}/include -I${ICU_INSTALL}/include -I${RDEPS}/include" \
    FCFLAGS="-O2 -g0" \
    FFLAGS="-O2 -g0" \
    LDFLAGS="${USE_LD} -Wl,--allow-shlib-undefined -Wl,--no-as-needed -Wl,-rpath,${BUILD_DIR}/lib -Wl,-rpath,${ICU_INSTALL}/lib -Wl,-rpath,${HOMEBREW_PREFIX}/lib -Wl,-rpath,${SYSROOT}/usr/lib/aarch64-linux-ohos -Wl,-rpath,${GFORTRAN_LIB} -Wl,-rpath,${GCC_LIB} -Wl,-rpath,${OHOS_LLVM_LIB} --sysroot=$SYSROOT -L${GFORTRAN_LIB} -L${ICU_INSTALL}/lib -L${HOMEBREW_PREFIX}/lib -L${SYSROOT}/usr/lib/aarch64-linux-ohos -L${RDEPS}/lib -L${JAVA_HOME}/lib/server" \
    LIBS="-lm" \
    CPPFLAGS="-DSIZE_MAX=18446744073709551615UL -I${HOMEBREW_PREFIX}/include -I${ICU_INSTALL}/include -I${RDEPS}/include -DENABLE_LEGACY_NONAPI -DUSE_MATH_THREADS ${JAVA_CPPFLAGS}" \
    CPP="${OHOS_CLANG} -E --sysroot=$SYSROOT -I${HOMEBREW_PREFIX}/include -I${ICU_INSTALL}/include -I${RDEPS}/include" \
    CXXCPP="${OHOS_CLANGXX} -E --sysroot=$SYSROOT -I${HOMEBREW_PREFIX}/include -I${RDEPS}/include" 2>&1 | tee /storage/Users/currentUser/R-harmonyos/build/configure.log || true

# Patch config.status to fix HarmonyOS filesystem incompatibilities:
#   1. umask 077 + mktemp -d creates unwritable dirs ("Permission denied" on subs1.awk)
#   2. print -r -- is a ksh-ism that bash doesn't support
#   3. mktemp with ./confXXXXXX template issues
if [ -f config.status ]; then
    echo "Patching config.status for HarmonyOS compatibility ..."
    python3 -c "
import re
with open('config.status', 'r') as f:
    c = f.read()
# Fix 1: Replace umask 077 + mktemp/mkdir temp dir creation with simple fallback
c = re.sub(
    r'tmp=\`\(\s*umask\s+077\s*&&\s*(mktemp\s+-d\s+\S*|mkdir\s+-p\s+\S*)\)\s*2>/dev/null\`\s*&&\s*test\s+-d\s+\"\\\$\"\s*\}\s*\|\|\s*\{[^}]*\}',
    '{ tmp=./conftmp\n  mkdir -p \"./conftmp\"\n}',
    c, flags=re.DOTALL
)
# Fix 2: standalone umask 077 + mkdir patterns
c = re.sub(r'\(umask\s+077\s*&&\s*mkdir\s+\"\\\$tmp\"\)', 'mkdir -p \"\$tmp\" 2>/dev/null', c)
# Fix 3: umask 077 && mktemp (no subshell wrapper)
c = re.sub(r'umask\s+077\s*&&\s*mktemp\s+-d\s+', 'mkdir -p ', c)
# Fix 4: bare mktemp -d with confXXXXXX template
c = c.replace('mktemp -d \"./confXXXXXX\"', 'mkdir -p ./conftmp')
# Fix 5: ksh-ism 'print -r --' -> 'echo' (bash doesn't support it)
c = c.replace(\"ECHO='print -r --'\", \"ECHO='echo'\")
with open('config.status', 'w') as f:
    f.write(c)
" 2>/dev/null || true
    echo "Re-running config.status ..."
    /bin/sh config.status 2>&1 | tee -a /storage/Users/currentUser/R-harmonyos/build/configure.log
fi

# Inject ICU_DATA into Makeconf so ICU data is found during the build
# (e.g., for the tools package sysdata step which runs R at build time).
MAKECONF="${BUILD_DIR}/etc/Makeconf"
if [ -f "$MAKECONF" ]; then
    if ! grep -q "^ICU_DATA" "$MAKECONF" 2>/dev/null; then
        echo "Injecting ICU_DATA into Makeconf ..."
        echo "" >> "$MAKECONF"
        echo "## ICU data directory (needed at build time for ICU collation)" >> "$MAKECONF"
        echo "ICU_DATA = ${ICU_DATA}" >> "$MAKECONF"
        echo "export ICU_DATA" >> "$MAKECONF"
    fi
fi

# Fix CC17 / C23 in Makeconf: cross-compilation leaves them empty, but
# some packages (e.g. locfit) request C17 standard and fail without CC17.
MAKECONF="${BUILD_DIR}/etc/Makeconf"
if [ -f "$MAKECONF" ]; then
    for cv in CC17 CC23; do
        if grep -q "^${cv} = \$" "$MAKECONF" 2>/dev/null; then
            echo "Fixing ${cv} in Makeconf ..."
            sed -i "s|^${cv} = \$|${cv} = ${OHOS_CLANG}|" "$MAKECONF"
        fi
    done
fi

# Inject ICU_DATA into ldpaths (sourced by bin/R at startup) so ICU
# data is found at runtime too.
LDPATHS="${BUILD_DIR}/etc/ldpaths"
if [ -f "$LDPATHS" ]; then
    if ! grep -q "^export ICU_DATA" "$LDPATHS" 2>/dev/null; then
        echo "Injecting ICU_DATA into ldpaths ..."
        echo "" >> "$LDPATHS"
        echo "## ICU data directory -- must be set before R starts so ICU can find" >> "$LDPATHS"
        echo "## locale/collation data files." >> "$LDPATHS"
        echo ": \${ICU_DATA=\"${ICU_DATA}\"}" >> "$LDPATHS"
        echo "export ICU_DATA" >> "$LDPATHS"
    fi
fi
