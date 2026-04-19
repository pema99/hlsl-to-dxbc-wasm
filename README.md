# hlsl-to-dxbc-wasm

A WebAssembly build of [vkd3d-compiler](https://gitlab.winehq.org/wine/vkd3d), the HLSL shader compiler frontend from the vkd3d project. The resulting binary reads HLSL source from stdin and outputs human-readable DXBC disassembly to stdout.

## Usage

```
echo "float4 main() : SV_Target { return 1; }" | wasmtime hlsl2asm.wasm --profile ps_5_0 -b d3d-asm --entry main
```

See `CLAUDE.md` for full build instructions.

## License

vkd3d-compiler is part of the vkd3d project, licensed under the
GNU Lesser General Public License v2.1 (LGPL-2.1).
See: https://gitlab.winehq.org/wine/vkd3d/-/blob/master/LICENSE
