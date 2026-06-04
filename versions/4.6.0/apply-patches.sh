#!/bin/sh
# Apply HarmonyOS-specific patches to R 4.6.0 source tree.
# Run from the project root:  bash versions/4.6.0/apply-patches.sh
#
# This script assumes src/R-4.6.0/ contains the original R 4.6.0 source
# (extracted from the CRAN tarball, unmodified).

set -e

R_SRC=src/R-4.6.0
PATCHES=versions/4.6.0/patches

if [ ! -d "$R_SRC" ]; then
    echo "Error: $R_SRC not found. Extract R-4.6.0 source first:"
    echo "  tar xzf src/R-4.6.0.tar.gz -C src/"
    exit 1
fi

if [ ! -d "$PATCHES" ]; then
    echo "Error: $PATCHES directory not found."
    exit 1
fi

cd "$R_SRC"

echo "=== Applying R 4.6.0 HarmonyOS patches ==="

for pf in ../../$PATCHES/*.patch; do
    name=$(basename "$pf")
    echo "  Applying $name ..."
    if patch -p1 -s < "$pf" 2>/dev/null; then
        echo "    $name applied successfully"
    else
        echo "    WARNING: $name failed (may already be applied)" >&2
    fi
done

echo "  Verifying all patches ..."
PATCH_OK=0
PATCH_FAIL=0
for pf in ../../$PATCHES/*.patch; do
    name=$(basename "$pf")
    # Determine the target file from the patch header
    target=$(head -1 "$pf" | sed 's/^--- //; s/\.orig//; s/.*\///')
    if [ -z "$target" ]; then
        echo "    [WARN] $name: could not determine target file" >&2
        PATCH_FAIL=$((PATCH_FAIL + 1))
        continue
    fi
    # Check if the patch's changes are already reflected
    # Look for a unique context line in the patch and verify it exists in the target
    context=$(grep '^[+]' "$pf" | grep -v '^+++' | head -1 | sed 's/^+//')
    if [ -n "$context" ] && grep -qF "$context" "$target" 2>/dev/null; then
        echo "    [OK] $name ($target)"
        PATCH_OK=$((PATCH_OK + 1))
    else
        echo "    [WARN] $name: patch content not found in $target" >&2
        PATCH_FAIL=$((PATCH_FAIL + 1))
    fi
done
echo "  Patches: $PATCH_OK OK, $PATCH_FAIL failed"

# Fix Rmath.h0.in: remove the Rlog1p declaration entirely (it was wrapped
# in 'extern "C"' which is C++ syntax, and keeping it in C mode conflicts
# with arithmetic.c's 'static double Rlog1p()'.  nmath/log1p.c provides the
# global Rlog1p definition when HAVE_WORKING_LOG1P is not defined.)
echo "  Fixing Rmath.h0.in (remove Rlog1p declaration) ..."
python3 -c "
with open('src/include/Rmath.h0.in', 'r') as f:
    c = f.read()
old = '''/* remap to avoid problems with getting the right entry point */
extern \"C\" {
double  Rlog1p(double);
}
#define log1p Rlog1p'''
new = '''#define log1p Rlog1p'''
if old in c:
    c = c.replace(old, new)
    with open('src/include/Rmath.h0.in', 'w') as f:
        f.write(c)
    print('    Fixed Rmath.h0.in')
else:
    print('    Rmath.h0.in already fixed or pattern not found')
" 2>&1 || echo '    Warning: could not fix Rmath.h0.in'

# Fix eval.c: add forward declaration for Rlog1p (needed because Rmath.h
# no longer declares it, but eval.c uses log1p as a function pointer in
# the builtin table which expands to Rlog1p via the macro)
echo "  Fixing eval.c (add Rlog1p forward decl) ..."
python3 -c "
with open('src/main/eval.c', 'r') as f:
    c = f.read()
old = '#include <Rmath.h>'
new = '#include <Rmath.h>\n/* HarmonyOS: forward decl for Rlog1p (defined in nmath/log1p.c) */\nextern double Rlog1p(double);'
if old in c:
    c = c.replace(old, new)
    with open('src/main/eval.c', 'w') as f:
        f.write(c)
    print('    Fixed eval.c')
else:
    print('    eval.c already fixed or pattern not found')
" 2>&1 || echo '    Warning: could not fix eval.c'

# Copy new files
echo "  Installing new files ..."
for nf in ../../$PATCHES/new-files/*; do
    name=$(basename "$nf")
    case "$name" in
        ohos_stubs.c)
            mkdir -p src/extra/ohos_stubs
            cp "$nf" src/extra/ohos_stubs/
            echo "    Created src/extra/ohos_stubs/$name"
            ;;
        Makefile.in)
            mkdir -p src/extra/ohos_stubs
            cp "$nf" src/extra/ohos_stubs/
            echo "    Created src/extra/ohos_stubs/Makefile.in"
            ;;
    esac
done

echo "=== Patches applied successfully ==="
