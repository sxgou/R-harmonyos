#!/bin/sh
# R for HarmonyOS post-install script
# Run after make install to apply all post-install fixes.
#
# Usage: cd /path/to/R-harmonyos && bash post-install-R.sh
#
# Actions:
#   1. Generate methods lazy-load database (required by stats4 and others)
#   2. Generate NEWS.rds / NEWS.2.rds / NEWS.3.rds (missing these causes make install to fail)
#   3. Verify installation integrity

set -e

# Derive project root from script location (works regardless of CWD)
PROJECT_ROOT=$(cd "$(dirname "$0")" && pwd)

# Version selection:  bash post-install-R.sh [version]
# Default is R 4.4.3.
R_VERSION="${1:-4.4.3}"

# ------ Config ------
# R_HOME auto-detection (prefers installed path, falls back to build path)
# Load toolchain paths (for OHOS_CLANG in CC17/CC23 fix)
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "${SCRIPT_DIR}/config.sh" 2>/dev/null || true

if [ -x "$HOME/.local/R/lib/R/bin/R" ]; then
    R_BIN="$HOME/.local/R/lib/R/bin/R"
    R_HOME="$HOME/.local/R/lib/R"
elif [ -x "build/bin/R" ]; then
    R_BIN="$(pwd)/build/bin/R"
    R_HOME="$(pwd)/build"
else
    echo "Error: R binary not found. Run make install or complete the build first."
    echo "  Looked in: $HOME/.local/R/lib/R/bin/R"
    echo "           build/bin/R"
    exit 1
fi

BUILD_DIR="${PROJECT_ROOT}/build"
R_SRC="${PROJECT_ROOT}/src/R-${R_VERSION}"

echo "=== R for HarmonyOS Post-Install ==="
echo "R binary:     $R_BIN"
echo "R_HOME:       $R_HOME"
echo "Build dir:    $BUILD_DIR"
echo ""

# ------ 1. Build libohos_stubs.so ------
echo "--- [1/6] Build libohos_stubs.so ---"
OHOS_STUBS_SRC="${R_SRC}/src/extra/ohos_stubs/ohos_stubs.c"
OHOS_STUBS_DEST="$R_HOME/lib/libohos_stubs.so"
if [ -f "$OHOS_STUBS_DEST" ]; then
    echo "  [Skipped] $OHOS_STUBS_DEST already exists"
elif [ ! -f "$OHOS_STUBS_SRC" ]; then
    echo "  [Skipped] $OHOS_STUBS_SRC not found"
    echo "  (Run configure-R.sh or apply-patches.sh first to copy new files)"
else
    OHOS_CLANG="/data/service/hnp/bin/aarch64-unknown-linux-ohos-clang"
    if [ ! -x "$OHOS_CLANG" ]; then
        echo "  [ERROR] OHOS clang not found: $OHOS_CLANG"
        echo "  (Install OHOS SDK first)"
    else
        echo "  Building libohos_stubs.so ..."
        BUILD_TMP=$(mktemp -p "${TMPDIR:-${PROJECT_ROOT}/tmp}" -d ohos_stubs_build_XXXXXX)
        "$OHOS_CLANG" -c -fPIC "$OHOS_STUBS_SRC" -o "$BUILD_TMP/ohos_stubs.o"
        "$OHOS_CLANG" -shared -o "$BUILD_TMP/libohos_stubs.so" "$BUILD_TMP/ohos_stubs.o"
        cp "$BUILD_TMP/libohos_stubs.so" "$OHOS_STUBS_DEST"
        rm -rf "$BUILD_TMP"
        echo "  [Done] libohos_stubs.so installed to $OHOS_STUBS_DEST"
    fi
fi
echo ""

# ------ 2. Generate methods package lazy-load database ------
echo "--- [2/6] Generate methods package lazy-load database ---"
METHODS_DIR="$R_HOME/library/methods/R"
if [ -f "$METHODS_DIR/methods.rdb" ] && [ -f "$METHODS_DIR/methods.rdx" ]; then
    echo "  [Skipped] methods lazy-load database already exists:"
    echo "    $METHODS_DIR/methods.rdb"
    echo "    $METHODS_DIR/methods.rdx"
else
    echo 'tools:::makeLazyLoading("methods", compress = FALSE)' | \
        R_DEFAULT_PACKAGES=NULL LC_ALL=C "$R_BIN" --vanilla --no-echo
    echo "  [Done] methods lazy-load database generated"
fi
echo ""

# ------ 3. Generate NEWS.rds ------
echo "--- [3/6] Generate NEWS.rds ---"
# Save original directory for later restoration
OLD_PWD=$(pwd)
if [ ! -d "$BUILD_DIR/doc" ]; then
    echo "  [Skipped] $BUILD_DIR/doc not found, skipping NEWS.rds generation"
    echo "  (make install may need manual handling for this)"
else
    cd "$BUILD_DIR/doc"

    for news_rd in NEWS.Rd NEWS.2.Rd NEWS.3.Rd; do
        news_rds="${news_rd%.Rd}.rds"
        if [ -f "$news_rds" ]; then
            echo "  [Skipped] $news_rds already exists"
            continue
        fi
        # Check if source file exists
        src_rd="../../src/R-${R_VERSION}/doc/$news_rd"
        if [ ! -f "$src_rd" ]; then
            echo "  [Skipped] $src_rd not found"
            continue
        fi
        echo "  Generating $news_rds ..."
        LC_ALL=C "$R_BIN" --vanilla --no-echo -e \
            'options(warn=1); saveRDS(tools:::prepare_Rd(tools::parse_Rd(
              "'"$src_rd"'",
              macros = "../share/Rd/macros/system.Rd"), stages = "install",
              warningCalls = FALSE), "'"$news_rds"'")' 2>/dev/null || \
        echo "  [Warning] $news_rds generation failed (make install may retry)"
    done

    cd "$OLD_PWD"
    echo "  [Done] NEWS.rds generated"
fi
echo ""

# ------ 4. Fix CC17/CC23 in installed Makeconf ------
echo "--- [4/6] Fix CC17/CC23 in installed Makeconf ---"
for mc in "$R_HOME/etc/Makeconf" "$BUILD_DIR/etc/Makeconf"; do
    if [ -f "$mc" ]; then
        for cv in CC17 CC23; do
            if grep -q "^${cv} = \$" "$mc" 2>/dev/null; then
                sed -i "s|^${cv} = \$|${cv} = ${OHOS_CLANG:-/data/service/hnp/bin/aarch64-unknown-linux-ohos-clang}|" "$mc"
                echo "  [OK] ${cv} fixed in $mc"
            fi
        done
    fi
done
echo ""

# ------ 5. Configure user R environment (~/.Rprofile) ------
echo "--- [5/6] Configure user R environment (~/.Rprofile) ---"
RPROFILE="${HOME}/.Rprofile"
TMPDIR_DEFAULT="/data/storage/el4/base/R-build"
PATCH_RCPP_SCRIPT="$(pwd)/versions/4.6.0/patch-rcpp.sh"

mkdir -p "$TMPDIR_DEFAULT"
mkdir -p "${HOME}/.R"

if [ -f "$RPROFILE" ] && ! grep -q "HarmonyOS" "$RPROFILE" 2>/dev/null; then
    cp "$RPROFILE" "${RPROFILE}.bak.$(date +%Y%m%d_%H%M%S)"
fi

cat > "$RPROFILE" << RPROFILE_EOF
# =============================================================
# HarmonyOS R configuration (auto-generated by post-install-R.sh)
# =============================================================

# ---- TMPDIR ----
TMPDIR <- "${TMPDIR_DEFAULT}"
dir.create(TMPDIR, showWarnings = FALSE, recursive = TRUE)
Sys.setenv(TMPDIR = TMPDIR)

# ---- .libPaths ----
r_lib <- "${R_HOME}/library"
if (r_lib %in% .libPaths()) {
    .libPaths(c(r_lib, .libPaths()[-which(.libPaths() == r_lib)]))
}

# ---- harmony_install() ----
harmony_install <- function(pkgs,
                             repos = NULL,
                             bioc = FALSE, github = FALSE, ...) {
    # ---- Auto-detect brew prefix and set env vars ----
    brew_prefix <- Sys.getenv("HOMEBREW_PREFIX",
      default = file.path(Sys.getenv("HOME"), ".harmonybrew"))
    pkg_config <- paste(
      file.path(brew_prefix, "lib/pkgconfig"),
      file.path(brew_prefix, "share/pkgconfig"),
      sep = ":")
    Sys.setenv(PKG_CONFIG_PATH = pkg_config)
    Sys.setenv(OPENBLAS_CORETYPE = "NEON")

    # ---- Default repo chain: harmony-cran -> CRAN ----
    if (is.null(repos)) {
        cran_url <- "https://cloud.r-project.org"
        harmony_cran <- "https://sxgou.github.io/harmony-cran"
        # Test reachability (only once per session, cache result)
        if (isTRUE(getOption("harmony_cran_ok", NULL))) {
            repos <- c(harmony_cran = harmony_cran, CRAN = cran_url)
        } else if (isFALSE(getOption("harmony_cran_ok", NULL))) {
            repos <- c(CRAN = cran_url)
        } else {
            reachable <- tryCatch(
                length(readLines(harmony_cran, n = 1)) > 0,
                error = function(e) FALSE)
            if (reachable) {
                options(harmony_cran_ok = TRUE)
                repos <- c(harmony_cran = harmony_cran, CRAN = cran_url)
                message("harmony-cran repo reachable: ", harmony_cran)
            } else {
                options(harmony_cran_ok = FALSE)
                repos <- c(CRAN = cran_url)
                message("harmony-cran repo not reachable, using CRAN only")
            }
        }
    }

    # ---- Log file under R installation directory ----
    r_home <- Sys.getenv("R_HOME")
    if (nzchar(r_home)) {
        log_dir <- file.path(dirname(dirname(r_home)), "var", "log")
    } else {
        log_dir <- file.path(Sys.getenv("HOME"), ".local", "R", "var", "log")
    }
    dir.create(log_dir, showWarnings = FALSE, recursive = TRUE)
    log_file <- file.path(log_dir, "harmony-install.log")

    log_install <- function(pkg, source, status, extra = "") {
        ts <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
        cat(sprintf("[%s] %s source: %s status: %s %s\n",
            ts, pkg, source, status, extra),
            file = log_file, append = TRUE)
    }

    # ---- Install remotes if needed for Bioc/GitHub ----
    if (bioc || github) {
        if (!requireNamespace("remotes", quietly = TRUE)) {
            message("Installing remotes ...")
            tryCatch(
                install.packages("remotes", repos = repos,
                    configure.args = "--host=aarch64-linux-ohos",
                    INSTALL_opts = "--no-test-load"),
                error = function(e) {
                    install.packages("remotes", repos = repos,
                        INSTALL_opts = "--no-test-load")
                })
        }
    }
    if (bioc && !requireNamespace("BiocManager", quietly = TRUE)) {
        message("Installing BiocManager ...")
        tryCatch(
            install.packages("BiocManager", repos = repos,
                configure.args = "--host=aarch64-linux-ohos",
                INSTALL_opts = "--no-test-load"),
            error = function(e) {
                install.packages("BiocManager", repos = repos,
                    INSTALL_opts = "--no-test-load")
            })
    }

    # ---- Install each package ----
    for (pkg in pkgs) {
        message("Installing: ", pkg)
        tryCatch({
            if (bioc) {
                BiocManager::install(pkg,
                    configure.args = "--host=aarch64-linux-ohos",
                    INSTALL_opts = "--no-test-load",
                    ...)
            } else if (github) {
                remotes::install_github(pkg,
                    configure.args = "--host=aarch64-linux-ohos",
                    INSTALL_opts = "--no-test-load",
                    ...)
            } else {
                install.packages(pkg,
                    repos = repos,
                    configure.args = "--host=aarch64-linux-ohos",
                    INSTALL_opts = "--no-test-load",
                    ...)
            }
            log_install(pkg,
                if (grepl("harmony_cran", deparse(repos)[1])) "harmony-cran" else "CRAN",
                "OK")
        }, error = function(e) {
            message("Retrying without configure.args: ", pkg)
            tryCatch({
                if (bioc) {
                    BiocManager::install(pkg,
                        INSTALL_opts = "--no-test-load", ...)
                } else if (github) {
                    remotes::install_github(pkg,
                        INSTALL_opts = "--no-test-load", ...)
                } else {
                    install.packages(pkg,
                        repos = repos,
                        INSTALL_opts = "--no-test-load", ...)
                }
                log_install(pkg, "CRAN (retry)", "OK")
            }, error = function(e2) {
                log_install(pkg, "CRAN", "FAIL",
                    paste("error:", gsub("[[:space:]]+", " ", e2$message)))
                message("Failed to install: ", pkg)
            })
        })
    }
    # Auto-patch Rcpp undoRmath.h when Rcpp is installed
    if ("Rcpp" %in% rownames(installed.packages())) {
        undo_file <- file.path(.libPaths()[1], "Rcpp", "include",
                               "Rcpp", "sugar", "undoRmath.h")
        if (file.exists(undo_file)) {
            tx <- readLines(undo_file)
            if (!any(grepl("^#undef log1p\$", tx))) {
                idx <- grep("^#undef log1pmx\$", tx)
                if (length(idx) == 1) {
                    tx <- append(tx, "#undef log1p", after = idx[1] - 1)
                    writeLines(tx, undo_file)
                    message("Patched Rcpp undoRmath.h (undef log1p)")
                }
            }
        }
    }
}

if (interactive()) {
    message("R on HarmonyOS | TMPDIR=", Sys.getenv("TMPDIR"))
    message("Use harmony_install() for packages with configure scripts")
    message("Install log: ", file.path(
        if (nzchar(Sys.getenv("R_HOME")))
            dirname(dirname(Sys.getenv("R_HOME")))
        else
            file.path(Sys.getenv("HOME"), ".local", "R"),
        "var", "log", "harmony-install.log"))
}
RPROFILE_EOF

echo "  [OK] $RPROFILE created"

# Also add TMPDIR to shell profile if not already there
SHELL_PROFILE="${HOME}/.bashrc"
if [ -f "$SHELL_PROFILE" ]; then
    if ! grep -q "export TMPDIR=${TMPDIR_DEFAULT}" "$SHELL_PROFILE" 2>/dev/null; then
        echo "" >> "$SHELL_PROFILE"
        echo "# HarmonyOS R build temp directory" >> "$SHELL_PROFILE"
        echo "export TMPDIR=${TMPDIR_DEFAULT}" >> "$SHELL_PROFILE"
        echo "  [OK] TMPDIR added to $SHELL_PROFILE"
    else
        echo "  [Skipped] TMPDIR already set in $SHELL_PROFILE"
    fi
fi
echo ""

# ------ 6. Verify installation integrity ------
echo "--- [6/6] Verify installation integrity ---"
ERRORS=0

check_file() {
    local file="$1" desc="$2"
    if [ -f "$file" ]; then
        echo "  [OK] $desc"
    else
        echo "  [ERR] $desc: missing $file"
        ERRORS=$((ERRORS + 1))
    fi
}

check_file "$R_HOME/bin/exec/R" "R main binary"
check_file "$R_HOME/lib/libR.so" "libR.so"
check_file "$R_HOME/library/base/R/base" "base package"
check_file "$R_HOME/library/methods/R/methods" "methods package (nspackloader)"
check_file "$R_HOME/library/methods/R/methods.rdb" "methods.rdb"
check_file "$R_HOME/library/methods/R/methods.rdx" "methods.rdx"
check_file "$R_HOME/library/stats/R/stats" "stats package"
check_file "$R_HOME/library/graphics/R/graphics" "graphics package"
check_file "$R_HOME/library/grDevices/R/grDevices" "grDevices package"
check_file "$R_HOME/library/utils/R/utils" "utils package"
check_file "$R_HOME/lib/libohos_stubs.so" "libohos_stubs.so"

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "=== Post-install complete, all checks passed ==="
else
    echo "=== Done ($ERRORS files missing, check [ERR] entries above) ==="
fi
