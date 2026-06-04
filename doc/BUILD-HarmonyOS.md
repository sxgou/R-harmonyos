# R for HarmonyOS — Cross-Compilation Guide

## Overview

Cross-compile R for HarmonyOS (aarch64-linux-ohos) platform.

Currently supported R versions:

| Version | Patches Location | Patch Count |
|---------|------------------|-------------|
| 4.4.3   | `versions/4.4.3/patches/` | 3 |
| 4.5.2   | `versions/4.5.2/patches/` | 5 |
| 4.6.0   | `versions/4.6.0/patches/` | 4 |

- **Target**: aarch64, HarmonyOS HongMeng Kernel 1.12.0
- **Toolchain**: OHOS SDK 26.0.0.18 (Clang 15.0.4) + [gfortran 14.2.0](https://github.com/sxgou/gfortran-harmonyos)
- **Linker**: lld (hmdfs requires `.codesign` section, only lld generates it)
- **BLAS/LAPACK**: [OpenBLAS 0.3.29](https://github.com/sxgou/openblas-harmonyos) (harmonybrew, 1000x1000 MM ~0.48s / ~4.2 GFLOPs)
- **Package Manager**: [harmonybrew](https://gitcode.com/Harmonybrew/homebrew-harmony)
- **Cairo + Pango**: Supported (brew cairo 1.18.4 + pango 1.57.1 + fontconfig 2.17.1, PNG/SVG/PDF backends work, Pango text layout enhanced)
- **readline**: Enabled (brew libreadline + ncurses, Tab completion and arrow keys work)
- **Java**: BiSheng JDK 17

### Script Overview

All scripts accept an optional version argument; default is R 4.4.3:

| Script | When to Run | Purpose |
|--------|-------------|---------|
| `build-deps.sh` | **Step 2** | Automatically install brew dependency libraries |
| `apply-patches.sh [version]` | **Step 4**, or auto-called by configure-R.sh | Apply HarmonyOS patches to `src/R-version/`. `bash apply-patches.sh 4.6.0` |
| `configure-R.sh [version]` | **Step 5** | Configure cross-compilation (auto-invokes apply-patches.sh). `bash configure-R.sh 4.6.0` |
| `post-install-R.sh [version]` | **Step 8** | Build libohos_stubs.so, generate methods lazy-load database, NEWS.rds, fix CC17/CC23, configure ~/.Rprofile, verify installation. `bash post-install-R.sh 4.6.0` |
| `versions/<version>/patch-rcpp.sh` | **Automatic** (via harmony_install) | Patch Rcpp's undoRmath.h to resolve log1p macro conflict. Can also be run manually. |

All steps must be executed **in order** — do not skip or reorder.

---

## Build Environment

| Component | Path | Reference |
|-----------|------|-----------|
| OHOS SDK | `/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/` | Huawei official |
| C/C++ Compiler | `/data/service/hnp/bin/aarch64-unknown-linux-ohos-clang++` | OHOS SDK |
| Fortran | `~/.local/gfortran/bin/gfortran` | [gfortran-harmonyos](https://github.com/sxgou/gfortran-harmonyos) |
| Java | `/data/service/hnp/bishengjdk17.0.13_06.org/` | Huawei official |
| lld wrapper | `~/.local/bin/ohos-lld-wrapper` | Created in Step 1 |
| harmonybrew | `~/.harmonybrew/` | [Harmonybrew](https://gitcode.com/Harmonybrew/homebrew-harmony) |
| OpenBLAS | Provided by harmonybrew | [openblas-harmonyos](https://github.com/sxgou/openblas-harmonyos) |

### Dependency Libraries

Provided by harmonybrew: pcre2, curl, bzip2, xz, openssl@3, libffi, openblas, readline, ncurses, libpng, freetype, cairo, libxml2, expat, pixman, fontconfig, harfbuzz, fribidi, gmp, pango, cmake, ninja, libtiff, pkgconf, autoconf, automake, bison, flex, sccache, libgit2, libsodium, proj, webp, giflib, mpfr

Manually compiled (`~/.local/R-deps`): fftw3, zeromq, ANN, glpk

---

## Build Steps

```
Prerequisites (Step 1)              — Toolchain preparation
       │
  Step 2: build-deps.sh             — Install dependency libraries
       │
  Step 3: tar xzf R-X.Y.Z.tar.gz   — Extract R source for desired version
       │
  Step 4: apply-patches.sh [version] — Apply patches (optional, Step 5 auto-runs)
       │
  Step 5: configure-R.sh [version]  — Configure (auto-runs apply-patches.sh)
       │
  Step 6: cd build && make...       — Compile
       │
  Step 7: make install              — Install
       │
  Step 8: post-install-R.sh [version] — Post-install processing
```

---

### Step 1: Prepare Toolchain

Ensure the following toolchain components are ready:

```bash
# OHOS SDK — verify clang is available
aarch64-unknown-linux-ohos-clang --version

# gfortran cross-compiler (get from project below)
#   https://github.com/sxgou/gfortran-harmonyos
~/.local/gfortran/bin/gfortran --version

# BiSheng JDK 17
java -version

# lld wrapper — see instructions below
~/.local/bin/ohos-lld-wrapper --help
```

**Obtaining each component**:

| Component | How to Get |
|-----------|-----------|
| OHOS SDK + Clang | Huawei official distribution, or bundled with DevEco Studio |
| gfortran cross-compiler | Download prebuilt package from [gfortran-harmonyos](https://github.com/sxgou/gfortran-harmonyos), extract to `~/.local/gfortran/` |
| BiSheng JDK 17 | Huawei official distribution |
| harmonybrew | Install from [Harmonybrew](https://gitcode.com/Harmonybrew/homebrew-harmony), provides pcre2, curl, cairo, openblas and other dependencies |
| OpenBLAS | Bundled with harmonybrew, or build from [openblas-harmonyos](https://github.com/sxgou/openblas-harmonyos) |

**lld wrapper**: Must install `~/.local/bin/ohos-lld-wrapper` with the following content:

```sh
#!/bin/sh
LLVM_LIB=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/llvm/lib
export LD_LIBRARY_PATH="${LLVM_LIB}${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec -a "ld.lld" "$LLVM_LIB/../bin/lld" --code-sign "$@"
```

This wrapper solves two critical problems:
1. **musl does not support `$ORIGIN`** — lld has RUNPATH set to `$ORIGIN/../lib` pointing to OHOS LLVM lib, but musl ld.so ignores this, leaving lld unable to find its own libxml2.so.16 at runtime. The wrapper explicitly sets `LD_LIBRARY_PATH` to the LLVM lib path.
2. **hmdfs requires `.codesign` section** — only lld's `--code-sign` generates this section automatically; bfd linker cannot produce it.

---

### Step 2: Install R Dependency Libraries

**Option A — Automatic installation (recommended)**:

```bash
bash build-deps.sh
```

This script automatically:
- Runs `brew install bzip2 xz pcre2 curl libpng freetype cairo ...` (all brew-available dependencies, including pango/cmake/ninja build tools)
- Creates `~/.local/R-deps/` directory (for libraries not yet in brew)
- Verifies key library files exist

**Option B — Manual installation**:

```bash
brew install bzip2 xz pcre2 curl openssl libpng freetype cairo \
  geos gmp libxml2 pixman libjpeg unixodbc expat fontconfig \
  pango cmake ninja libtiff pkgconf autoconf automake bison flex \
  sccache libgit2 libsodium proj webp giflib mpfr
```

Non-brew libraries (fftw3, zeromq, ANN, glpk) must be cross-compiled manually and installed to `~/.local/R-deps/`.

---

### Step 3: Download and Extract R Source

Choose the R version you want. Currently supports 4.4.3 and 4.6.0:

```bash
# Create src directory if it doesn't exist
mkdir -p src

# Download R 4.4.3
curl -L https://cran.r-project.org/src/base/R-4/R-4.4.3.tar.gz | tar xz -C src/

# Or download R 4.6.0
curl -L https://cran.r-project.org/src/base/R-4/R-4.6.0.tar.gz | tar xz -C src/
```

After extraction, the directory structure:

```
src/R-X.Y.Z/        ← Original R source (will be patched and compiled by subsequent scripts)
```

---

### Step 4: Apply HarmonyOS Patches to R Source

```bash
# Default: apply patches for R 4.4.3
bash apply-patches.sh

# Or specify a version, e.g. R 4.6.0
bash apply-patches.sh 4.6.0
```

This script reads patches from `versions/<version>/patches/` and applies the following to the original source in `src/R-<version>/`:

- Applies **patch files** (modifies existing R source; count varies by version)
  - 4.4.3 / 4.6.0: 2 common patches
  - 4.5.2: 4 patches (2 common + 2 version-specific)
- Copies **2 new files** (ohos_stubs.c + Makefile.in) to `src/extra/ohos_stubs/`
- Runs **inline python fixes** (4.5.2 only: 6 additional fixes for R 4.5.2-specific header reorganization)

Patch coverage:

| Patch File | Modification | 4.4.3 | 4.5.2 | 4.6.0 |
|-----------|-------------|-------|-------|-------|
| `etc-ldpaths.in.patch` | LD_PRELOAD injects libohos_stubs.so; add brew/lib to LD_LIBRARY_PATH for zlib-ng-compat priority | ✓ | ✓ | ✓ |
| `src-unix-Rscript.c.patch` | On execv() failure, dlopen("libR.so") and call Rf_initialize_R + Rf_mainloop directly (bypass seccomp execv blockade) | ✓ | ✓ | ✓ |
| `namespace-assignNativeRoutines.patch` | Fix `assignNativeRoutines` where `if(exists(...))` skips existing bindings. Lazy-loaded `C_*` variables (EXTPTRSXP serialized as NULL) get overwritten by `.Call` registration, breaking all `C_*` calls | ✗ | ✗ | ✓ |
| `Rmath.h0.in.patch` | Wrap `#define log1p Rlog1p` in `#ifndef __cplusplus` guard to prevent `::log1p` from being macro-expanded to `::Rlog1p` in C++ (affects Rcpp, Armadillo, etc.) | ✓ | ✓ | ✓ |
| `src-extra-Makefile.in-ohos_stubs.patch` | Add ohos_stubs to SUBDIRS in `src/extra/Makefile.in` so libohos_stubs.so builds automatically as part of the standard make flow | ✗ | ✓ | ✗ |
| `etc-ldpaths.in-LD_PRELOAD.patch` | Embed LD_PRELOAD configuration in ldpaths.in template so libohos_stubs.so auto-loads on every R startup | ✗ | ✓ | ✗ |
| `configure-umask.patch` | Use `umask 022` instead of `umask 077` when configure creates temp directories, avoiding Permission denied on hmdfs with 0700 permissions (issue #3) | ✗ | ✗ | ✓ |
| `tools-copy-if-change.patch` | `copy-if-change` uses `rm -f && cp` instead of `cp -f` to avoid hmdfs overwrite failures (issue #4) | ✗ | ✗ | ✓ |
| `Makefile.in-install-rm.patch` | `install-libR-exists` does `rm -f` before `$(INSTALL_DATA)` to avoid hmdfs overwrite failure of `libR.so` (issue #4) | ✗ | ✗ | ✓ |

R 4.5.2-specific inline python fixes (integrated into `apply-patches.sh`):

| Fix Target | Resolution |
|-----------|-----------|
| `src/include/Rmath.h0.in` | Remove `extern "C"` wrapping Rlog1p declaration (conflicts in C mode) |
| `src/main/eval.c` | Add Rlog1p forward declaration (Rmath.h no longer declares it) |
| `src/include/Defn.h` | Add Rf_allocVector3 forward declaration (missing in R 4.5.2, present in R 4.6.0) |
| `src/include/Defn.h` | Add unconditional R_popen/R_system declarations (R 4.5.2 places them behind HAVE_POPEN conditional) |
| `src/library/tools/src/gramRd.y` | Add ENABLE_LEGACY_NONAPI define (makes Rf_findVar etc. visible) |
| `src/library/stats/src/distance.c` | Add R_ext/MathThreads.h include |

> **Note**: The original 9–13 zlib compression workaround patches and 2 ineffective patches (baseloader.R, gzio.h) have been removed. These patches worked around compression interface restrictions when R loaded OHOS SDK's libz.so, which triggered seccomp. Since switching to `zlib-ng-compat` (brew) instead of SDK libz, all compression/decompression interfaces work normally without any workarounds.
>
> For R 4.5.2, libohos_stubs.so build is integrated into the R build system (via SUBDIRS entry in `src/extra/Makefile.in` and `src/extra/ohos_stubs/Makefile.in`). The `LD_PRELOAD` injection is embedded in `etc/ldpaths.in`, so libohos_stubs.so auto-loads on every R startup.

**Note**: This step can be skipped — Step 5's `configure-R.sh` automatically calls `apply-patches.sh`. Running it separately is useful for previewing patch effects or testing after modifying patches.

---

### Step 5: Configure R Build

```bash
# Default: configure R 4.4.3
bash configure-R.sh

# Or specify a version, e.g. R 4.6.0
bash configure-R.sh 4.6.0
```

This script performs the following:

1. **Auto-runs `apply-patches.sh <version>`** (if patches haven't been applied yet)
2. **Cleans** `config.cache` and `config.status` from the `build/` directory
3. **Sets environment variables** (PKG_CONFIG_PATH pointing to brew and R-deps, LD_LIBRARY_PATH pointing to OHOS LLVM lib and gfortran)
4. **Pre-seeds cache variables** (~35 `r_cv_*` / `ac_cv_*` variables to skip runtime tests blocked by seccomp)
5. **Runs `src/R-<version>/configure`** with all HarmonyOS cross-compilation parameters
6. **Patches `config.status`** (fixes HarmonyOS toybox compatibility: umask 077 + mktemp failure, ksh `print -r --` not supported by bash)
7. **Re-runs `config.status`** to generate final Makefile

Key configuration options:

```
--host=aarch64-pc-linux-musl      # Cross-compilation target (maps to aarch64-linux-ohos)
--enable-R-shlib                   # Build libR.so (required, hmdfs does not support static linking)
--with-readline                    # readline interactive support
--with-blas=-lopenblas             # OpenBLAS (SIMD optimized)
--with-lapack                      # OpenBLAS LAPACK
--enable-java                      # BiSheng JDK 17
X11 auto-detected via pkg-config       # libX11 + libXt + libSM provided by brew
--without-tcltk                    # No Tcl/Tk
```

---

### Step 6: Compile

```bash
cd build && make && make R
```

Stage details:
- `make`: Compiles R core C/Fortran code and libR.so
- `make R`: Generates the R main binary (PIE) and Rscript

Notes:
- **All 15 base packages** are compiled automatically by `make`
- **Makeconf consistency**: `build/Makeconf` and `build/etc/Makeconf` must stay in sync (generated by configure). If you modify configuration, re-run `configure-R.sh`
- **Two Makeconf files**: If you manually modify one, you must sync to the other, otherwise make will use stale configuration

---

### Step 7: Install

```bash
make install
```

Installs to `--prefix` directory (`~/.local/R/`), result:

| Component | Path |
|-----------|------|
| R Home | `~/.local/R/lib/R/` |
| R Binary | `~/.local/R/lib/R/bin/exec/R` |
| libR.so | `~/.local/R/lib/R/lib/libR.so` |
| Base Packages | `~/.local/R/lib/R/library/*/` |
| Wrapper Script | `~/.local/R/lib/R/bin/R` |

**Note**: hmdfs does not allow overwriting existing files. The `tools/copy-if-change` script has been patched to automatically `rm -f` before installation (see `tools-copy-if-change.patch`), and the `install-libR-exists` target in `Makefile.in` has also been fixed. To reinstall, simply run `make install` again.

---

### Step 8: Post-Install Processing

Run the one-click post-install script (generates methods lazy-load database, NEWS.rds, verifies integrity):

```bash
bash post-install-R.sh
```

This script automatically:

1. **Builds libohos_stubs.so** — compiles from `src/extra/ohos_stubs/ohos_stubs.c` and installs to `$R_HOME/lib/`, filling in missing OHOS libc symbols.
2. **Generates methods package lazy-load database** — creates `library/methods/R/methods`, `methods.rdb` (963 KB), `methods.rdx` (23 KB). Required by packages depending on methods (e.g. stats4).
3. **Generates NEWS.rds / NEWS.2.rds / NEWS.3.rds** — compiled from `NEWS.Rd` if `make install` did not produce them automatically.
4. **Fixes CC17/CC23** — after cross-compilation, CC17/CC23 in Makeconf are empty, causing packages that request C17 standard (e.g. locfit) to fail. This step sets CC17/CC23 to the full OHOS clang path.
5. **Configures user R environment** — auto-creates `~/.Rprofile` with:
   - `TMPDIR` set to a hmfs path (avoids hmdfs restrictions causing configure scripts to fail)
   - `harmony_install()` helper function, automatically handles `--host` and `--no-test-load`
   - Auto-patches `undoRmath.h` after Rcpp installation (fixes `log1p` macro conflict)
   - Appends `TMPDIR` environment variable to `~/.bashrc`
6. **Verifies installation integrity** — checks R binary, libR.so, libohos_stubs.so, and key packages (base/methods/stats) are in place.

The script is idempotent — already completed steps are automatically skipped.

---

## Usage

Start R via the wrapper script:

```bash
~/.local/R/lib/R/bin/R                          # R REPL
~/.local/R/lib/R/bin/R -e 'print(1+1)'          # Run expression
~/.local/R/lib/R/bin/R --vanilla -e \
  'install.packages("jsonlite", repos="https://cloud.r-project.org")'
```

**Note**: In earlier versions, `Rscript` was unusable because seccomp blocked `execv()`. Starting from patch #18 (`src/unix/Rscript.c`), Rscript works by using `dlopen("libR.so")` to directly call `Rf_initialize_R` + `Rf_mainloop` as a workaround.

---

## Installing R Packages

### Recommended: `harmony_install()`

After running `post-install-R.sh`, the `harmony_install()` helper function is defined in `~/.Rprofile`, automatically handling HarmonyOS-specific configuration:

```r
# Install a single package (auto-adds --host=aarch64-linux-ohos)
harmony_install("jsonlite")

# Batch installation
harmony_install(c("dplyr", "ggplot2", "Seurat"))

# Specify a mirror
harmony_install("Seurat", repos = "https://mirrors.tuna.tsinghua.edu.cn/CRAN")

# Bioconductor packages (auto-installs BiocManager + passes HarmonyOS args)
harmony_install("DESeq2", bioc = TRUE)
harmony_install(c("edgeR", "limma"), bioc = TRUE)

# GitHub packages (auto-installs remotes + passes HarmonyOS args)
# Note: must use "owner/repo" format, not just package name, to avoid ambiguous matches
harmony_install("satijalab/seurat-wrappers", github = TRUE)
harmony_install("chris-mcginnis-ucsf/DoubletFinder", github = TRUE)
```

`harmony_install()` automatically handles:

| Problem | Automatic Handling |
|---------|-------------------|
| configure cannot run test programs (SELinux blocked) | Passes `configure.args = "--host=aarch64-linux-ohos"` |
| hmdfs temp file restrictions | Uses `TMPDIR=/data/storage/el4/base/R-build` (hmfs) |
| Rcpp `undoRmath.h` missing `#undef log1p` | Auto-detects and patches after Rcpp installation |
| Package install test-load may fail | Passes `INSTALL_opts = "--no-test-load"` |

### Manual Mode (`--vanilla`)

If you prefer to start R with `--vanilla` (skipping `.Rprofile`), pass the parameters manually:

```r
install.packages("Seurat",
    repos = "https://mirrors.tuna.tsinghua.edu.cn/CRAN",
    configure.args = "--host=aarch64-linux-ohos",
    INSTALL_opts = "--no-test-load")
```

### Installing Seurat

Seurat 5.5.0 has been fully verified on HarmonyOS:

```r
harmony_install("Seurat")
```

Verify the core workflow:

```r
library(Seurat)
obj <- CreateSeuratObject(counts = data)
obj <- NormalizeData(obj, verbose = FALSE)
obj <- FindVariableFeatures(obj, verbose = FALSE)
obj <- ScaleData(obj, verbose = FALSE)
obj <- RunPCA(obj, verbose = FALSE, npcs = 10)
obj <- FindNeighbors(obj, verbose = FALSE, dims = 1:10)
obj <- FindClusters(obj, verbose = FALSE)
obj <- RunUMAP(obj, dims = 1:10, verbose = FALSE)
```

---

## Known Issues and Fixes

### 1. R Startup Crash — "could not find function 'file'"

**Symptom**: R crashes immediately at startup with an error that base function `file()` is not defined.

**File**: `src/library/base/baseloader.R`

**Root Cause**: `readRDS` has a parameter named `file`, and its body calls `file(file, "rb")`. The parameter `file` shadows the `file()` function from the base package. Critically, during base package lazy-loading, `file()` — a non-primitive function — hasn't been defined yet because base itself hasn't finished loading.

**Fix**: Renamed the parameter to `filepath`, and replaced `file(filepath, "rb")` with `.Internal(file(filepath, "rb", TRUE, "", "default", FALSE))`, calling the C-level implementation directly without relying on the R wrapper function.

### 2. Missing methods Package Lazy-Load Database

See Step 8a for details.

### 3. LD_LIBRARY_PATH Causes Startup Failure — "promise already under evaluation"

**Symptom**: R errors with "promise already under evaluation" when started via the wrapper script; running `bin/exec/R` directly works fine.

**File**: `etc/ldpaths.in`

**Root Cause**: configure collects paths from `-L` flags in `LDFLAGS` and writes them to `ldpaths`. These include OHOS SDK sysroot, gfortran, harmonybrew paths, etc. The wrapper script `bin/R` sources `ldpaths` before starting R, adding sysroot paths to `LD_LIBRARY_PATH`. The dynamic linker loads OHOS SDK's libc when searching these paths first, which is incompatible with the build host's musl environment, causing internal state inconsistency during R lazy-loading.

**Fix**: `ldpaths.in` ignores `@R_LD_LIBRARY_PATH@`, keeping only `${R_HOME}/lib`. All dependency paths are already encoded in the binary via RPATH.

### 4. `make install` Missing NEWS.rds

See Step 8b for details.

### 5. `make install` Missing Rscript.1 Man Page

**Root Cause**: `help2man` needs to execute the target platform binary to extract help information, but the cross-compiled Rscript cannot run on the build host (requires HarmonyOS musl dynamic linker).

**Fix**: Create a minimal man page stub.

### 6. ohos-lld-wrapper — musl $ORIGIN Incompatibility

See the lld wrapper description in Step 1 for details.

### 7. hmdfs Filesystem Restrictions

**Symptom**: Static-linked ELF files cannot execute (EACCES), bfd-linked `.so` files fail `dlopen()`, stripped binaries won't run.

**Root Cause**: HarmonyOS hmdfs distributed filesystem security mechanisms require:
- ELF Type must be **DYN (Shared object file)** — i.e., a PIE executable
- Must have **`.codesign` section**: only lld's `--code-sign` generates this automatically
- Cannot strip: `llvm-strip` modifying ELF in-place on hmdfs destroys the security isolation context

**Verification**:
```bash
readelf -h binary | grep 'Type:'
# Type: DYN (Shared object file)
readelf -S binary | grep codesign
# Should have a .codesign section
```

### 8. OHOS libc Truncation — libohos_stubs Shim Library

**Symptom**: `undefined symbol` errors during Rust compilation or R package runtime.

**Root Cause**: OHOS musl libc is a trimmed version, missing some standard symbols.

**Shim Solution**: `src/extra/ohos_stubs/ohos_stubs.c` is compiled in two forms:

| Scenario | Method | Symbols |
|----------|--------|---------|
| Rust compile-time static link | `libohos_stubs.a` | `posix_spawn_file_actions_addchdir_np` (returns ENOSYS), `__xpg_strerror_r` (forwards to strerror_r) |
| R package runtime dynamic injection | `libohos_stubs.so` (LD_PRELOAD) | Same + `pthread_setcanceltype` (returns 0), `pthread_cancel` (returns 0) |

**LD_PRELOAD injection**: The `etc/ldpaths.in` template (R runtime config) embeds the following snippet, which after configure generates the installed `etc/ldpaths`, ensuring automatic preloading on every R startup:

```sh
LD_PRELOAD="${R_HOME}/lib${R_ARCH}/libohos_stubs.so${LD_PRELOAD:+:${LD_PRELOAD}}"
export LD_PRELOAD
```

This mechanism allows R packages using `pthread_setcanceltype` (e.g., `cli`, `purrr`) to work without source modifications.

### 9. OpenBLAS Integration

R is configured with `--with-blas="-lopenblas" --with-lapack`, so libR.so directly links libopenblas.so.0. 1000x1000 matrix multiplication takes ~0.48s (~4.2 GFLOPs) on a 20-core aarch64.

### 10. Stale Files in `bin/exec/` Causing Multi-Arch Build Errors

The `install-bin` target in `src/main/Makefile.in` automatically removes non-R files (R.bfd, test-exec, test-sh) from `bin/exec/`.

### 11. gzfile Compression Causes Vignette Installation Failure

**Fix**: In `src/library/tools/R/admin.R`, `.install_package_vignettes3` adds a fallback for `readRDS` — reads raw bytes, decompresses with `memDecompress()`, then parses with `unserialize()`. R's built-in zlib implementation doesn't depend on `gzfile` connections, bypassing seccomp restrictions.

### 12. seccomp Blocks All zlib Compression Interfaces

**Symptom**: HarmonyOS seccomp filter blocks custom syscalls used by OHOS SDK's bundled libz.so, causing:
- All `gzopen()` / `gzfile()` connection calls fail
- All `saveRDS(compress=TRUE)` calls fail (returns `unknown input format`)
- All `makeLazyLoadDB(compress=TRUE)` calls fail
- System package sysdata compression (R_compress1) fails during installation
- `memDecompress(type="gzip")` in-memory decompression fails

**Root Cause**: R's RUNPATH has OHOS SDK path (`/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot/usr/lib/aarch64-linux-ohos/`) taking priority over brew path, causing the runtime to load SDK's `libz.so` (triggers seccomp) instead of brew's `zlib-ng-compat` (standard syscalls).

**2026-06-02 Update**: By adding brew lib path to `LD_LIBRARY_PATH` in `etc/ldpaths` (musl gives LD_LIBRARY_PATH higher priority than DT_RPATH), R loads zlib-ng-compat from brew instead of SDK libz on startup, restoring all compression/decompression interfaces. Specific change:

```bash
# Added to etc/ldpaths:
R_BREW_LIB="/storage/Users/currentUser/.harmonybrew/lib"
: ${R_LD_LIBRARY_PATH=${R_BREW_LIB}:${R_HOME}/lib}
```

**Patch cleanup note**: All 13 (4.6.0) / 9 (4.4.3) original zlib compression workaround patches and 2 ineffective patches (baseloader.R, gzio.h) have been removed. These patches worked around compression interface restrictions when R loaded OHOS SDK's libz.so which triggered seccomp, using methods such as:
- Replacing `gzfile()` with `file()` to bypass gzopen blockade
- Changing `saveRDS(compress=TRUE)` to `compress=FALSE` to bypass R_compress1 blockade
- Forcing compression off in lazy-load database builds
- Using external `gzip -dc` pipes instead of `gzfile()` reads
- Adding tryCatch fallbacks for `memDecompress()`

Since switching to `zlib-ng-compat` (brew) instead of SDK libz, all compression/decompression interfaces work normally without any workarounds.

> Note: R 4.5.2 has 2 additional version-specific patches on top of the common patches (ohos_stubs build integration + ldpaths.in LD_PRELOAD injection), plus 6 inline python fixes. See the patch coverage table above.

---

## Build Artifacts

| Artifact | Size | Description |
|----------|------|-------------|
| libR.so | 3.2 MB | R shared library |
| R.bin | 22 KB | R main binary (PIE) |
| Rscript | 24 KB | R script frontend (PIE) |
| methods.rdb | 963 KB | methods package lazy-load data |
| methods.rdx | 23 KB | methods package lazy-load index |
| internet.so | 72 KB | Network module |
| lapack.so | 47 KB | LAPACK C wrappers |
| libRlapack.so | 1.7 MB | LAPACK Fortran implementation |
| libohos_stubs.so | — | libc shim library |

---

## Verification

```bash
# Version info
LC_ALL=C ~/.local/R/lib/R/bin/R --version

# Startup and load all key packages
LC_ALL=C ~/.local/R/lib/R/bin/R --vanilla --no-echo \
  -e 'library(methods); library(stats4); cat("OK\n")'

# Matrix multiplication benchmark
LC_ALL=C ~/.local/R/lib/R/bin/R --vanilla --no-echo \
  -e 'm <- matrix(rnorm(1e6), 1000); cat(system.time({m %*% m})[3], "s\n")'
```

## Verified Features

- [x] gzfile() / gzopen compressed file I/O (zlib-ng-compat)
- [x] saveRDS/readRDS compressed serialization (gzip/bzip2/xz)
- [x] memCompress/memDecompress in-memory compression/decompression
- [x] PDF device afm font metrics loading
- [x] R core startup (R 4.4.3)
- [x] All 15 base packages build and load
- [x] stats4 maximum likelihood estimation (MLE)
- [x] libcurl networking
- [x] Base graphics device (grDevices)
- [x] BLAS/LAPACK linear algebra (OpenBLAS 0.3.29)
- [x] `R CMD INSTALL` and `install.packages()`
- [x] ggplot2 + CairoPNG rendering
- [x] readline interactive terminal (Tab completion and arrow keys)
- [x] Jupyter IRkernel
- [x] Seurat 5.5.0 (NormalizeData, RunPCA, FindClusters, RunUMAP, full workflow)
- [x] DESeq2 1.52.0 (makeExampleDESeqDataSet, DESeq, results, differential expression analysis)
- [ ] tcltk (requires Tcl/Tk runtime)
- [ ] Recommended packages — installable on demand via `harmony_install()`

---

*Last updated: 2026-06-03 (added CC17/CC23 fix, DESeq2 verification, namespace.R patch, Seurat support, harmony_install automation)*
