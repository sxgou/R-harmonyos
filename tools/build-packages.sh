#!/bin/sh
# Build remaining R 4.6.0 packages directly
set -e

export ICU_DATA=/storage/Users/currentUser/.local/R-deps/share/icu/78.3
export LD_LIBRARY_PATH="/storage/Users/currentUser/R-harmonyos/build/lib:/storage/Users/currentUser/.local/R-deps/lib:/storage/Users/currentUser/.harmonybrew/lib:/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/lib:/storage/Users/currentUser/.local/gfortran/lib64:/storage/Users/currentUser/.local/gfortran/lib/gcc/aarch64-unknown-linux-ohos/14.2.0"

R_EXE="/storage/Users/currentUser/R-harmonyos/build/bin/R --vanilla --no-echo"
TOP_BUILDDIR=/storage/Users/currentUser/R-harmonyos/build
TOP_SRCDIR=/storage/Users/currentUser/R-harmonyos/src/R-4.6.0

build_pkg_no_src() {
    pkg=$1
    echo "=== Building package: $pkg ==="
    pkgdir=$TOP_BUILDDIR/library/$pkg

    # Create package directory
    mkdir -p $pkgdir/R $pkgdir/help $pkgdir/html $pkgdir/Meta

    # Install DESCRIPTION
    if [ -f $TOP_BUILDDIR/src/library/$pkg/DESCRIPTION ]; then
        cp $TOP_BUILDDIR/src/library/$pkg/DESCRIPTION $pkgdir/
    fi

    # Install NAMESPACE
    if [ -f $TOP_SRCDIR/src/library/$pkg/NAMESPACE ]; then
        cp $TOP_SRCDIR/src/library/$pkg/NAMESPACE $pkgdir/
    fi

    # Install R code (common + platform-specific)
    if [ -d $TOP_SRCDIR/src/library/$pkg/R ]; then
        for f in $TOP_SRCDIR/src/library/$pkg/R/*.R; do
            [ -f "$f" ] && cp "$f" $pkgdir/R/
        done
        for f in $TOP_SRCDIR/src/library/$pkg/R/*.r; do
            [ -f "$f" ] && cp "$f" $pkgdir/R/
        done
        # Also copy unix platform files (HarmonyOS: R_OSTYPE=unix)
        if [ -d $TOP_SRCDIR/src/library/$pkg/R/unix ]; then
            for f in $TOP_SRCDIR/src/library/$pkg/R/unix/*.R; do
                [ -f "$f" ] && cp "$f" $pkgdir/R/
            done
        fi
    fi

    # Install data
    if [ -d $TOP_SRCDIR/src/library/$pkg/data ]; then
        mkdir -p $pkgdir/data
        for f in $TOP_SRCDIR/src/library/$pkg/data/*; do
            [ -f "$f" ] && cp "$f" $pkgdir/data/
        done
    fi

    # Run R to create lazy load database
    echo "tools:::makeLazyLoadDB(\"$TOP_BUILDDIR/library/$pkg\", compress=TRUE)" | \
        R_DEFAULT_PACKAGES=NULL LC_ALL=C $R_EXE > /dev/null 2>&1 || \
        echo "Warning: lazy load for $pkg failed"

    echo "=== $pkg done ==="
}

build_pkg_stats() {
    echo "=== Building package: stats (installing) ==="
    pkgdir=$TOP_BUILDDIR/library/stats

    # Install DESCRIPTION
    if [ -f $TOP_BUILDDIR/src/library/stats/DESCRIPTION ]; then
        cp $TOP_BUILDDIR/src/library/stats/DESCRIPTION $pkgdir/
    fi

    echo "tools:::makeLazyLoadDB(\"$TOP_BUILDDIR/library/stats\", compress=TRUE)" | \
        R_DEFAULT_PACKAGES=NULL LC_ALL=C $R_EXE > /dev/null 2>&1 || \
        echo "Warning: lazy load for stats failed"

    echo "=== stats done ==="
}

# Build pure R packages first
for pkg in datasets methods; do
    build_pkg_no_src $pkg
done

# Build packages with compiled code
for pkg in splines parallel grid stats4 tcltk; do
    echo "=== Building $pkg (compiled) ==="
    if [ -d $TOP_BUILDDIR/src/library/$pkg/src ]; then
        # Check if there's a shared lib to build
        cd $TOP_BUILDDIR/src/library/$pkg/src
        # Try make -j1 with jobserver-style=pipe
        /data/service/hnp/bin/make -j1 --jobserver-style=pipe 2>&1 || echo "Warning: make failed for $pkg"
    fi
    build_pkg_no_src $pkg
done

echo "=== All packages built ==="
