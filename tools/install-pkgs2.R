# R script to install remaining base packages
# Uses the correct makeLazyLoading function

srcdir <- "/storage/Users/currentUser/R-harmonyos/src/R-4.6.0"
builddir <- "/storage/Users/currentUser/R-harmonyos/build"
pkglib <- file.path(builddir, "library")
r_exe <- file.path(builddir, "bin", "R")

# Packages that need R code + lazy loading
pkgs <- c("datasets", "methods", "splines", "parallel", "grid", "stats", "stats4")

# Also install .so files for compiled packages
so_pkgs <- c("splines", "parallel", "grid", "stats")

for (pkg in so_pkgs) {
  # Copy .so from src build dir to library
  src_so <- file.path(builddir, "src", "library", pkg, "src", paste0(pkg, ".so"))
  dst_dir <- file.path(pkglib, pkg, "libs")
  if (file.exists(src_so)) {
    dir.create(dst_dir, showWarnings = FALSE, recursive = TRUE)
    file.copy(src_so, file.path(dst_dir, paste0(pkg, ".so")), overwrite = TRUE)
    cat("Copied .so for", pkg, "\n")
  }
}

for (pkg in pkgs) {
  cat("=== Installing", pkg, "===\n")
  pkgdir <- file.path(pkglib, pkg)
  srcpkg <- file.path(srcdir, "src", "library", pkg)

  # Create directories
  dir.create(file.path(pkgdir, "R"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(pkgdir, "help"), showWarnings = FALSE)
  dir.create(file.path(pkgdir, "html"), showWarnings = FALSE)
  dir.create(file.path(pkgdir, "Meta"), showWarnings = FALSE)

  # Copy DESCRIPTION from build tree
  desc_src <- file.path(builddir, "src", "library", pkg, "DESCRIPTION")
  if (file.exists(desc_src)) file.copy(desc_src, pkgdir, overwrite = TRUE)

  # Copy NAMESPACE
  ns_src <- file.path(srcpkg, "NAMESPACE")
  if (file.exists(ns_src)) file.copy(ns_src, pkgdir, overwrite = TRUE)

  # Copy R source files (common + platform-specific)
  r_src <- file.path(srcpkg, "R")
  if (dir.exists(r_src)) {
    r_files <- list.files(r_src, pattern = "\\.(R|r)$", full.names = TRUE)
    if (length(r_files) > 0) file.copy(r_files, file.path(pkgdir, "R"), overwrite = TRUE)
    # Also copy unix platform files for packages like parallel, utils, etc.
    unix_src <- file.path(r_src, "unix")
    if (dir.exists(unix_src)) {
      unix_files <- list.files(unix_src, pattern = "\\.(R|r)$", full.names = TRUE)
      if (length(unix_files) > 0) file.copy(unix_files, file.path(pkgdir, "R"), overwrite = TRUE)
    }
  }

  # Create all.R from R files
  r_files_in_pkg <- list.files(file.path(pkgdir, "R"), pattern = "\\.(R|r)$", full.names = TRUE)
  all_r <- file.path(pkgdir, "R", "all.R")
  cat("", file = all_r)
  for (f in r_files_in_pkg) {
    cat(readLines(f, warn = FALSE), file = all_r, sep = "\n", append = TRUE)
    cat("\n", file = all_r, append = TRUE)
  }

  # Copy data files
  data_src <- file.path(srcpkg, "data")
  if (dir.exists(data_src)) {
    dir.create(file.path(pkgdir, "data"), showWarnings = FALSE)
    data_files <- list.files(data_src, full.names = TRUE)
    if (length(data_files) > 0) file.copy(data_files, file.path(pkgdir, "data"), overwrite = TRUE)
    unlink(file.path(pkgdir, "data", "Rdata.*"))
  }

  cat("Done with file copy for", pkg, "\n")
}

cat("\nNow running R to create lazy load databases...\n")
cat("Run: R_DEFAULT_PACKAGES=tools LC_ALL=C $R_EXE\n")

# Run makeLazyLoading for each package via R
for (pkg in pkgs) {
  cat("Lazy loading", pkg, "...\n")
  cmd <- sprintf(
    'tools:::makeLazyLoading("%s")',
    pkg
  )
  system2(r_exe, args = c("--vanilla", "--no-echo"),
          env = c(paste0("R_DEFAULT_PACKAGES=tools"),
                  "LC_ALL=C",
                  paste0("ICU_DATA=", Sys.getenv("ICU_DATA", "/storage/Users/currentUser/.local/R-deps/share/icu/78.3")),
                  paste0("LD_LIBRARY_PATH=", Sys.getenv("LD_LIBRARY_PATH"))),
          input = cmd,
          stdout = FALSE, stderr = FALSE)
  cat("Done lazy loading", pkg, "\n")
}

cat("\nAll packages processed.\n")
cat("Packages in library:", paste(list.files(pkglib), collapse = ", "), "\n")
