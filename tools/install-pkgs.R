# R script to install remaining base packages
# Run: R --vanilla --no-echo < install-pkgs.R

srcdir <- "/storage/Users/currentUser/R-harmonyos/src/R-4.6.0"
builddir <- "/storage/Users/currentUser/R-harmonyos/build"
pkglib <- file.path(builddir, "library")

# Packages that need to be installed (not yet in library/)
pkgs <- c("datasets", "methods", "splines", "parallel", "grid", "stats", "stats4")

for (pkg in pkgs) {
  cat("=== Installing package:", pkg, "===\n")

  pkgdir <- file.path(pkglib, pkg)
  srcpkg <- file.path(srcdir, "src", "library", pkg)

  # Create directories
  dir.create(file.path(pkgdir, "R"), recursive = TRUE, showWarnings = FALSE)
  dir.create(file.path(pkgdir, "help"), showWarnings = FALSE)
  dir.create(file.path(pkgdir, "html"), showWarnings = FALSE)
  dir.create(file.path(pkgdir, "Meta"), showWarnings = FALSE)

  # Copy DESCRIPTION from build tree (might have been processed by configure)
  desc_src <- file.path(builddir, "src", "library", pkg, "DESCRIPTION")
  if (file.exists(desc_src)) {
    file.copy(desc_src, pkgdir, overwrite = TRUE)
  } else {
    desc_src2 <- file.path(srcpkg, "DESCRIPTION.in")
    if (file.exists(desc_src2)) {
      warning("DESCRIPTION.in not processed for ", pkg)
    }
  }

  # Copy NAMESPACE
  ns_src <- file.path(srcpkg, "NAMESPACE")
  if (file.exists(ns_src)) {
    file.copy(ns_src, pkgdir, overwrite = TRUE)
  }

  # Copy R source files (common + platform-specific)
  r_src <- file.path(srcpkg, "R")
  if (dir.exists(r_src)) {
    r_files <- list.files(r_src, pattern = "\\.(R|r)$", full.names = TRUE)
    if (length(r_files) > 0) {
      file.copy(r_files, file.path(pkgdir, "R"), overwrite = TRUE)
    }
    # Also copy unix platform files for packages like parallel, utils, etc.
    unix_src <- file.path(r_src, "unix")
    if (dir.exists(unix_src)) {
      unix_files <- list.files(unix_src, pattern = "\\.(R|r)$", full.names = TRUE)
      if (length(unix_files) > 0) {
        file.copy(unix_files, file.path(pkgdir, "R"), overwrite = TRUE)
      }
    }
  }

  # Copy data files
  data_src <- file.path(srcpkg, "data")
  if (dir.exists(data_src)) {
    dir.create(file.path(pkgdir, "data"), showWarnings = FALSE)
    data_files <- list.files(data_src, full.names = TRUE)
    if (length(data_files) > 0) {
      file.copy(data_files, file.path(pkgdir, "data"), overwrite = TRUE)
      # Remove Rdata.* files (internal)
      unlink(file.path(pkgdir, "data", "Rdata.*"))
    }
  }

  # Copy .so files if they exist (compiled packages)
  src_so <- file.path(builddir, "src", "library", pkg, "src", paste0(pkg, ".so"))
  if (file.exists(src_so)) {
    dir.create(file.path(pkgdir, "libs"), showWarnings = FALSE)
    file.copy(src_so, file.path(pkgdir, "libs", paste0(pkg, ".so")), overwrite = TRUE)
    cat("  Copied .so:", src_so, "\n")
  }

  # Also check in build/library (where make already installed them)
  lib_so <- file.path(pkglib, pkg, "libs", paste0(pkg, ".so"))
  if (file.exists(lib_so)) {
    cat("  .so already in place:", lib_so, "\n")
  }

  # Create lazy load database using R's internal function
  cat("  Creating lazy load DB...\n")
  tryCatch({
    tools::makeLazyLoadDB(pkgdir, compress = TRUE)
    cat("  Lazy load DB created.\n")
  }, error = function(e) {
    cat("  Warning: lazy load failed:", conditionMessage(e), "\n")
  })

  cat("=== Done:", pkg, "===\n\n")
}

cat("All packages installed.\n")
cat("Installed packages:", paste(list.files(pkglib), collapse = ", "), "\n")
