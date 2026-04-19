#!/usr/bin/env bash
# Build hlsl2asm.wasm from vkd3d-compiler source.
# Run from this directory. Requires: clang 13 (with wasm-ld 13), WinFlexBison 2.5.25, perl.
# See CLAUDE.md for full setup instructions.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VKD3D=/tmp/vkd3d
BUILD=/tmp/vkd3d-build
SYSROOT=/tmp/wasi-sysroot-20
BUILTINS=/tmp/builtins-20
CLANG="/c/Program Files/LLVM/bin/clang"
WIN_FLEX="/c/tools/win_flex_bison/win_flex.exe"
WIN_BISON="/c/tools/win_flex_bison/win_bison.exe"
SPIRV_INCLUDE=/tmp/spirv-include

mkdir -p "$BUILD"

echo "=== Generating parser files ==="
# HLSL parser
"$WIN_BISON" -d -o "$BUILD/hlsl.tab.c" "$VKD3D/libs/vkd3d-shader/hlsl.y"
"$WIN_FLEX" -o "$BUILD/hlsl.yy.c" "$VKD3D/libs/vkd3d-shader/hlsl.l"
# Preprocessor parser
"$WIN_BISON" -d -o "$BUILD/preproc.tab.c" "$VKD3D/libs/vkd3d-shader/preproc.y"
"$WIN_FLEX" -o "$BUILD/preproc.yy.c" "$VKD3D/libs/vkd3d-shader/preproc.l"

echo "=== Installing generated headers ==="
# Place generated/hand-crafted headers where the source expects them
cp "$SCRIPT_DIR/generated-headers/config.h" "$VKD3D/include/private/config.h"
cp "$SCRIPT_DIR/generated-headers/vkd3d_version.h" "$VKD3D/include/private/vkd3d_version.h"
cp "$SCRIPT_DIR/generated-headers/spirv_grammar.h" "$VKD3D/include/private/spirv_grammar.h"
cp "$SCRIPT_DIR/generated-headers/vkd3d_d3dcommon.h" "$VKD3D/include/vkd3d_d3dcommon.h"
cp "$SCRIPT_DIR/generated-headers/vkd3d_d3dx9shader.h" "$VKD3D/include/vkd3d_d3dx9shader.h"

# Install parser outputs into the source tree (vkd3d-shader includes them by path)
cp "$BUILD/hlsl.tab.c" "$BUILD/hlsl.tab.h" "$BUILD/hlsl.yy.c" \
   "$BUILD/preproc.tab.c" "$BUILD/preproc.tab.h" "$BUILD/preproc.yy.c" \
   "$VKD3D/libs/vkd3d-shader/" 2>/dev/null || true

INCLUDES=(
  -I"$VKD3D/include/private"
  -I"$VKD3D/include"
  -I"$SPIRV_INCLUDE"
  -I"$BUILD"
)

CFLAGS=(
  -target wasm32-wasi
  --sysroot="$SYSROOT"
  -resource-dir "$BUILTINS"
  -Oz -ffunction-sections -fdata-sections
  -D_POSIX_C_SOURCE=200809L
  "${INCLUDES[@]}"
)

echo "=== Compiling shader sources ==="
compile() {
  local src="$1" out="$2"
  echo "  $src"
  "$CLANG" "${CFLAGS[@]}" -c "$src" -o "$out"
}

SHADER_DIR="$VKD3D/libs/vkd3d-shader"
compile "$VKD3D/programs/vkd3d-compiler/main.c"    "$BUILD/main_oz.o"
compile "$SHADER_DIR/checksum.c"                    "$BUILD/checksum_oz.o"
compile "$SHADER_DIR/d3d_asm.c"                     "$BUILD/d3d_asm_oz.o"
compile "$SHADER_DIR/d3dbc.c"                       "$BUILD/d3dbc_oz.o"
compile "$SHADER_DIR/dxbc.c"                        "$BUILD/dxbc_oz.o"
compile "$SHADER_DIR/dxil.c"                        "$BUILD/dxil_oz.o"
compile "$SHADER_DIR/fx.c"                          "$BUILD/fx_oz.o"
compile "$SHADER_DIR/glsl.c"                        "$BUILD/glsl_oz.o"
compile "$SHADER_DIR/hlsl.c"                        "$BUILD/hlsl_oz.o"
compile "$SHADER_DIR/hlsl_codegen.c"                "$BUILD/hlsl_codegen_oz.o"
compile "$SHADER_DIR/hlsl_constant_ops.c"           "$BUILD/hlsl_constant_ops_oz.o"
compile "$SHADER_DIR/ir.c"                          "$BUILD/ir_oz.o"
compile "$SHADER_DIR/msl.c"                         "$BUILD/msl_oz.o"
compile "$SHADER_DIR/spirv.c"                       "$BUILD/spirv_oz.o"
compile "$SHADER_DIR/tpf.c"                         "$BUILD/tpf_oz.o"
compile "$SHADER_DIR/vkd3d_shader_main.c"           "$BUILD/vkd3d_shader_main_oz.o"
compile "$BUILD/hlsl.tab.c"                         "$BUILD/hlsl.tab_oz.o"
compile "$BUILD/hlsl.yy.c"                          "$BUILD/hlsl.yy_oz.o"
compile "$BUILD/preproc.tab.c"                      "$BUILD/preproc.tab_oz.o"
compile "$BUILD/preproc.yy.c"                       "$BUILD/preproc.yy_oz.o"
# vkd3d-common (blob.c excluded — needs COM/vkd3d.h)
compile "$VKD3D/libs/vkd3d-common/debug.c"          "$BUILD/debug_oz.o"
compile "$VKD3D/libs/vkd3d-common/error.c"          "$BUILD/error_oz.o"
compile "$VKD3D/libs/vkd3d-common/memory.c"         "$BUILD/memory_oz.o"
compile "$VKD3D/libs/vkd3d-common/utf8.c"           "$BUILD/utf8_oz.o"

echo "=== Linking ==="
OBJS=(
  "$BUILD/main_oz.o"
  "$BUILD/checksum_oz.o"  "$BUILD/d3d_asm_oz.o"    "$BUILD/d3dbc_oz.o"
  "$BUILD/dxbc_oz.o"      "$BUILD/dxil_oz.o"       "$BUILD/fx_oz.o"
  "$BUILD/glsl_oz.o"      "$BUILD/hlsl_oz.o"       "$BUILD/hlsl_codegen_oz.o"
  "$BUILD/hlsl_constant_ops_oz.o" "$BUILD/ir_oz.o" "$BUILD/msl_oz.o"
  "$BUILD/spirv_oz.o"     "$BUILD/tpf_oz.o"        "$BUILD/vkd3d_shader_main_oz.o"
  "$BUILD/hlsl.tab_oz.o"  "$BUILD/hlsl.yy_oz.o"
  "$BUILD/preproc.tab_oz.o" "$BUILD/preproc.yy_oz.o"
  "$BUILD/debug_oz.o"     "$BUILD/error_oz.o"
  "$BUILD/memory_oz.o"    "$BUILD/utf8_oz.o"
)

"$CLANG" -target wasm32-wasi --sysroot="$SYSROOT" -resource-dir "$BUILTINS" \
  -Wl,--strip-all -Wl,--gc-sections \
  "${OBJS[@]}" -lm -o "$BUILD/hlsl2asm_new.wasm"

cp "$BUILD/hlsl2asm_new.wasm" "$SCRIPT_DIR/hlsl2asm.wasm"
echo "=== Done: $SCRIPT_DIR/hlsl2asm.wasm ($(du -h "$SCRIPT_DIR/hlsl2asm.wasm" | cut -f1)) ==="
