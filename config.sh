# ================================================================
# config.sh — Environment-specific paths for R-HarmonyOS build
# ================================================================
# Source this from all build scripts:
#   source "$(cd "$(dirname "$0")" && pwd)/config.sh"
#
# Each user must update these paths to match their local environment.
# ================================================================

# OHOS SDK
export SYSROOT=/data/service/hnp/ohos-sdk.org/ohos-sdk_26.0.0.18/ohos/native/sysroot
export OHOS_CLANG=/data/service/hnp/bin/aarch64-unknown-linux-ohos-clang
export OHOS_CLANGXX=/data/service/hnp/bin/aarch64-unknown-linux-ohos-clang++

# LLVM (part of OHOS SDK)
export OHOS_LLVM_ROOT=${SYSROOT%/sysroot}/llvm
export OHOS_LLVM_LIB=${OHOS_LLVM_ROOT}/lib

# gfortran cross-compiler
#   Download from: https://github.com/sxgou/gfortran-harmonyos
export GFORTRAN=/storage/Users/currentUser/.local/gfortran/bin/gfortran
export GFORTRAN_LIB=/storage/Users/currentUser/.local/gfortran/lib64
export GCC_LIB=/storage/Users/currentUser/.local/gfortran/lib/gcc/aarch64-unknown-linux-ohos/14.2.0

# R dependency libraries (brew-managed)
#   harmonybrew: https://gitcode.com/Harmonybrew/homebrew-harmony
export HOMEBREW_PREFIX=/storage/Users/currentUser/.harmonybrew

# R dependency libraries (manually compiled, not yet in brew)
export RDEPS=/storage/Users/currentUser/.local/R-deps

# lld wrapper (needed for .codesign section generation)
export LLD_WRAPPER=/storage/Users/currentUser/.local/bin/ohos-lld-wrapper

# ICU data directory (for ICU collation/locale support)
export ICU_INSTALL="${RDEPS}"

# Java (BiSheng JDK 17)
export JAVA_HOME=/data/service/hnp/bishengjdk17.0.13_06.org/bishengjdk17.0.13_06_0.13_06
export JAVA=/data/service/hnp/bin/java
export JAVAC=/data/service/hnp/bin/javac
export JAR=/data/service/hnp/bin/jar
