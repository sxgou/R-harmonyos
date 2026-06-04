# R for HarmonyOS

Cross-compile R for HarmonyOS (aarch64-linux-ohos).

Currently supported R versions:

| Version | Status | Patches |
|---------|--------|---------|
| 4.4.3   | ✓ Verified | `versions/4.4.3/patches/` (3) |
| 4.5.2   | ✓ Verified | `versions/4.5.2/patches/` (5) |
| 4.6.0   | ✓ Verified | `versions/4.6.0/patches/` (4) |

## Quick Start

```bash
# Step 1: Clone this project
git clone https://github.com/sxgou/R-harmonyos.git
cd R-harmonyos

# Step 2: Install dependency libraries (brew installs all R prerequisites)
bash build-deps.sh

# Step 3: Download R 4.4.3 source (or 4.6.0)
mkdir -p src
curl -L https://cran.r-project.org/src/base/R-4/R-4.4.3.tar.gz | tar xz -C src/

# Step 4: Configure (auto-patches + cross-compile config). Default 4.4.3:
#   bash configure-R.sh          # uses R 4.4.3
#   bash configure-R.sh 4.6.0    # uses R 4.6.0
bash configure-R.sh

# Step 5: Compile
cd build && make && make R

# Step 6: Install to ~/.local/R/
make install

# Step 7: Post-install (generate methods lazy-load DB + NEWS.rds + verify)
bash post-install-R.sh
```

> **Note**: The steps above assume you have the HarmonyOS cross-compilation toolchain ready (OHOS SDK Clang + gfortran + lld wrapper). If not, read the full build guide first.

**Full build guide** (toolchain setup, environment requirements, known issues, troubleshooting): [doc/BUILD-HarmonyOS.md](doc/BUILD-HarmonyOS.md)

---

## Usage

After installation, start R via the wrapper script:

```bash
~/.local/R/lib/R/bin/R                          # R REPL
~/.local/R/lib/R/bin/R -e 'print(1+1)'          # Run expression
~/.local/R/lib/R/bin/R --vanilla -e \
  'install.packages("jsonlite", repos="https://cloud.r-project.org")'
```

---

## Project Structure

```
├── build/                    # Build output (compilation results)
├── src/                      # R source directory (from CRAN, not in git)
│   ├── R-4.4.3/              #   R 4.4.3 source
│   └── R-4.6.0/              #   R 4.6.0 source
├── versions/                 # Per-version patches and configuration
│   ├── 4.4.3/
│   │   ├── patches/          #   3 HarmonyOS patches
│   │   │   ├── *.patch
│   │   │   └── new-files/    #   New files (ohos_stubs.c + Makefile.in)
│   │   └── patch-rcpp.sh     #   Rcpp patch script
│   ├── 4.5.2/
│   │   ├── patches/          #   5 HarmonyOS patches
│   │   │   ├── *.patch
│   │   │   └── new-files/
│   │   └── patch-rcpp.sh
│   └── 4.6.0/
│       ├── patches/          #   4 HarmonyOS patches
│       │   ├── *.patch
│       │   └── new-files/
│       └── patch-rcpp.sh
├── doc/
│   └── BUILD-HarmonyOS.md    # Full build guide
├── apply-patches.sh          # Patch entry point: bash apply-patches.sh [version]
├── build-deps.sh             # Dependency installation script
├── configure-R.sh            # Configuration entry point: bash configure-R.sh [version]
├── post-install-R.sh         # Post-install: bash post-install-R.sh [version]
└── README.md                 # This file
```

---

## Script Reference

| Script | When to Run | Purpose |
|--------|-------------|---------|
| `build-deps.sh` | After cloning, Step 1 | Install dependencies via harmonybrew (bzip2, curl, pcre2, cairo, pango, cmake, ninja, etc.) |
| `apply-patches.sh [version]` | After extracting source (auto-called by configure-R.sh) | Apply version-specific HarmonyOS patches to `src/R-version/`. `bash apply-patches.sh 4.6.0` |
| `configure-R.sh [version]` | After patching (auto-invokes apply-patches.sh) | Configure cross-compilation and run R's configure. Default 4.4.3, `bash configure-R.sh 4.6.0` |
| `post-install-R.sh [version]` | After `make install` | Generate methods lazy-load DB, NEWS.rds, verify installation |

All scripts accept an optional version argument. Default is R 4.4.3.

---

## Current Configuration

| Option | Value |
|--------|-------|
| Target Platform | aarch64-linux-ohos, HarmonyOS HongMeng Kernel 1.12.0 |
| Toolchain | OHOS SDK 26.0.0.18 (Clang 15.0.4) + [gfortran 14.2.0](https://github.com/sxgou/gfortran-harmonyos) |
| Linker | lld (hmdfs requires `.codesign` section) |
| BLAS/LAPACK | [OpenBLAS 0.3.29](https://github.com/sxgou/openblas-harmonyos) (1000x1000 MM ~0.48s) |
| Package Manager | [harmonybrew](https://gitcode.com/Harmonybrew/homebrew-harmony) (84 formulae) |
| Cairo + Pango | Supported (brew cairo + pango, PNG/SVG/PDF backends, Pango text layout) |
| readline | Enabled (Tab completion and arrow keys) |
| Java | BiSheng JDK 17 |

---

## Test Status

| Feature | Status |
|---------|--------|
| gzfile() / gzopen compressed file I/O (zlib-ng-compat) | ✓ |
| saveRDS/readRDS compressed serialization (gzip/bzip2/xz) | ✓ |
| memCompress/memDecompress in-memory compression/decompression | ✓ |
| PDF device afm font metrics loading | ✓ |
| R REPL interactive use (readline Tab completion) | ✓ |
| All 15 base packages build successfully | ✓ |
| 12 loadable packages load correctly | ✓ |
| Matrix operations (OpenBLAS optimized) | ✓ 0.48s / 1000x1000 MM |
| Linear models / ANOVA / MLE | ✓ |
| Fortran numerical routines | ✓ |
| libcurl networking | ✓ |
| OpenMP parallelism (20 cores) | ✓ |
| `install.packages()` / `R CMD INSTALL` | ✓ |
| `Rscript` script execution | ✓ |
| ggplot2 + CairoPNG rendering | ✓ |
| Jupyter IRkernel | ✓ |

---

## Known Limitations

- ~~**gzfile() / gzopen / R_compress1 / R_decompress1 unavailable**~~ **Fixed** (2026-06-02): OHOS SDK's libz.so uses custom syscalls blocked by seccomp. By adding brew's `zlib-ng-compat` path to `LD_LIBRARY_PATH` in `etc/ldpaths`, R loads zlib-ng-compat instead of SDK libz at startup, restoring all compression/decompression. See [doc/BUILD-HarmonyOS.md](doc/BUILD-HarmonyOS.md) §12.
- **No X11 / Tcl/Tk**: Not available on HarmonyOS
- **Cannot strip ELF binaries**: hmdfs security isolation context is destroyed

---

*Full build guide: [doc/BUILD-HarmonyOS.md](doc/BUILD-HarmonyOS.md)*
