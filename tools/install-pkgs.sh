#!/bin/sh
# Install remaining R 4.6.0 packages — fully automatic
set -e

TOP_SRC=/storage/Users/currentUser/R-harmonyos/src/R-4.6.0
TOP_BUILD=/storage/Users/currentUser/R-harmonyos/build
TOP_ICU=/storage/Users/currentUser/.local/R-deps
ICU_DATA=${TOP_ICU}/share/icu/78.3
OHOS_LLVM_LIB=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/lib/aarch64-linux-ohos

# Use exec/R directly to bypass the R wrapper script's ldpaths override.
# ldpaths prepends .harmonybrew/lib to LD_LIBRARY_PATH, which causes
# the dynamic linker to load harmonybrew's ICU (missing libc++_shared.so)
# instead of our self-built ICU at TOP_ICU/lib.
LD_LIBRARY_PATH="${TOP_BUILD}/lib:${TOP_ICU}/lib:${OHOS_LLVM_LIB}"
R_EXE="${TOP_BUILD}/bin/exec/R --vanilla --no-echo"

# R environment for running package commands
R_ENV="R_DEFAULT_PACKAGES=NULL ICU_DATA=$ICU_DATA LC_ALL=C LD_LIBRARY_PATH=$LD_LIBRARY_PATH"

R_CMD() {
    env $R_ENV $R_EXE "$@"
}

install_pkg() {
    pkg=$1
    echo "=== Installing $pkg ==="
    pkgdir="${TOP_BUILD}/library/$pkg"
    srcpkg="${TOP_SRC}/src/library/$pkg"

    mkdir -p "$pkgdir/R" "$pkgdir/help" "$pkgdir/html" "$pkgdir/Meta"

    # Copy DESCRIPTION
    if [ -f "${TOP_BUILD}/src/library/$pkg/DESCRIPTION" ]; then
        cp "${TOP_BUILD}/src/library/$pkg/DESCRIPTION" "$pkgdir/"
    fi

    # Copy NAMESPACE
    if [ -f "$srcpkg/NAMESPACE" ]; then
        cp "$srcpkg/NAMESPACE" "$pkgdir/"
    fi

    # Copy and concatenate R files (common + platform-specific)
    if [ -d "$srcpkg/R" ]; then
        for f in "$srcpkg/R"/*.R "$srcpkg/R"/*.r; do
            [ -f "$f" ] && cp "$f" "$pkgdir/R/"
        done 2>/dev/null || true
        if [ -d "$srcpkg/R/unix" ]; then
            for f in "$srcpkg/R/unix"/*.R "$srcpkg/R/unix"/*.r; do
                [ -f "$f" ] && cp "$f" "$pkgdir/R/"
            done 2>/dev/null || true
        fi
        # all.R = common + unix files; skip windows stubs
        cat "$srcpkg/R"/*.R "$srcpkg/R/unix"/*.R 2>/dev/null > "$pkgdir/R/all.R" || true
        cp "$pkgdir/R/all.R" "$pkgdir/R/$pkg"
    fi

    # Copy data
    if [ -d "$srcpkg/data" ]; then
        mkdir -p "$pkgdir/data"
        for f in "$srcpkg/data"/*; do
            [ -f "$f" ] && cp "$f" "$pkgdir/data/"
        done 2>/dev/null || true
    fi

    # Copy .so if exists
    for so in "${TOP_BUILD}/src/library/$pkg/src/$pkg.so" "${TOP_BUILD}/library/$pkg/libs/$pkg.so"; do
        if [ -f "$so" ]; then
            mkdir -p "$pkgdir/libs"
            cp "$so" "$pkgdir/libs/$pkg.so" 2>/dev/null || true
        fi
    done

    echo "=== $pkg: files copied ==="
}

# ---- Step 1: Copy all files for all packages ----
for pkg in datasets methods splines parallel grid stats stats4; do
    install_pkg $pkg
done

# ---- Step 2: Create Meta files for ALL packages ----
# This must happen BEFORE lazy-load DB creation because loadNamespace()
# reads Meta/package.rds and Meta/features.rds to validate the package.
# In particular, methods' R code calls loadNamespace("stats") internally,
# so stats needs valid Meta files before methods can be sourced.
echo "=== Creating Meta files ==="
R_CMD --no-save << 'EOF' 2>&1
lib <- "/storage/Users/currentUser/R-harmonyos/build/library"
id <- .Internal(internalsID())
rv <- package_version("4.6.0")
class(rv) <- c("R_system_version", "package_version", "numeric_version")

# Include all install pkgs + deps that already exist in the library
pkgs <- c("datasets", "methods", "splines", "parallel", "grid", "stats", "stats4")
for (pkg in pkgs) {
  pkgdir <- file.path(lib, pkg)
  if (!dir.exists(pkgdir)) { cat("  ", pkg, ": SKIP (no dir)\n", sep = ""); next }

  saveRDS(list(compiled = TRUE, internalsID = id),
          file.path(pkgdir, "Meta", "features.rds"))

  desc_file <- file.path(pkgdir, "DESCRIPTION")
  if (file.exists(desc_file)) {
    desc <- read.dcf(desc_file)
    built <- list(R = rv,
                  Platform = "aarch64-pc-linux-musl",
                  Date = format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"),
                  OStype = "unix")
    dvec <- desc[1,]; names(dvec) <- colnames(desc)
    res <- list(DESCRIPTION = dvec, Built = built,
                Rdepends = NULL, Rdepends2 = NULL,
                Depends = list(), Suggests = list(),
                Imports = list(), LinkingTo = list())
    class(res) <- "packageDescription2"
    saveRDS(res, file.path(pkgdir, "Meta", "package.rds"))
  }
  cat("  ", pkg, ": Meta created\n", sep = "")
}
EOF

# ---- Step 3: Build lazy-load databases ----
# methods uses loadNamespace directly (makeLazyLoading does not work for it)
# stats gets loaded as a side-effect of methods (via .getFromStandardPackages),
# so we process stats now too while it's already loaded.
echo "=== Building methods and stats lazy-load DBs ==="
R_CMD --no-save << 'EOF' 2>&1
lib <- "/storage/Users/currentUser/R-harmonyos/build/library"

invisible(loadNamespace("methods", lib.loc = lib))
cat("methods: loadNamespace OK\n")

# stats was loaded as a side-effect (via .getFromStandardPackages).
# makeLazyLoading refuses to work if namespace is already loaded,
# so use makeLazyLoadDB directly on the loaded namespace instead.
ns <- getNamespace("stats")
tools:::makeLazyLoadDB(ns, file.path(lib, "stats", "R", "stats"), compress = TRUE)
cat("stats: makeLazyLoadDB OK\n")

# Install nspackloader for both
for (pkg in c("methods", "stats")) {
  loader <- file.path(R.home("share"), "R", "nspackloader.R")
  file.copy(loader, file.path(lib, pkg, "R", pkg), overwrite = TRUE)
}
cat("nspackloader.R installed for methods and stats\n")
EOF

# Other packages: use makeLazyLoading in a single R session (skip stats)
# datasets has no R code, so skip it too (nspackloader would break)
echo "=== Building remaining packages lazy-load DBs ==="
R_CMD --no-save << 'EOF' 2>&1
lib <- "/storage/Users/currentUser/R-harmonyos/build/library"
library(methods, lib.loc = lib)
pkgs <- c("splines", "parallel", "grid", "stats4")
for (pkg in pkgs) {
  cat("  ", pkg, "... ", sep = "")
  allfile <- file.path(lib, pkg, "R", "all.R")
  srcfile <- file.path(lib, pkg, "R", pkg)
  if (file.exists(allfile) && (!file.exists(srcfile) || file.size(srcfile) != file.size(allfile))) {
    file.copy(allfile, srcfile, overwrite = TRUE)
  }
  r <- tryCatch({
    tools:::makeLazyLoading(pkg, lib)
    "OK"
  }, error = function(e) paste("FAIL:", conditionMessage(e)))
  cat(r, "\n")
}
# Install nspackloader.R for each remaining package
for (pkg in pkgs) {
  loader <- file.path(R.home("share"), "R", "nspackloader.R")
  file.copy(loader, file.path(lib, pkg, "R", pkg), overwrite = TRUE)
}
cat("nspackloader.R installed for remaining packages\n")
EOF

# datasets has no R code, so remove the bogus nspackloader file
rm -f "${TOP_BUILD}/library/datasets/R/datasets"
echo "datasets: R code file removed (data-only package)"

# ---- Step 4: Verify all packages load correctly ----
echo "=== Verification ==="
R_CMD --no-save << 'EOF' 2>&1
lib <- "/storage/Users/currentUser/R-harmonyos/build/library"
pkgs <- c("datasets", "methods", "splines", "parallel", "grid", "stats", "stats4")
all_ok <- TRUE
for (pkg in pkgs) {
  r <- tryCatch({ library(pkg, lib.loc = lib, character.only = TRUE); "OK" },
                error = function(e) paste("FAIL:", conditionMessage(e)))
  cat(sprintf("  %-10s %s\n", pkg, r))
  if (r != "OK") all_ok <- FALSE
}
if (all_ok) cat("\nAll packages OK\n") else cat("\nSome packages FAILED\n")
EOF

echo ""
echo "=== All done ==="
ls "${TOP_BUILD}/library/" | sort
