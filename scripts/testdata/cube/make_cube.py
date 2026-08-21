#!/usr/bin/env python3
"""Generate the `cube` sidecar fixture: cube.gltf + cube.bin + cube.png.

A unit cube with six axis-coloured faces. Unlike the flat `tiny.glb` triangle it
reads as a solid from every angle, so still-render proofs stay legible from the
side and back. Standard metallic-roughness + FLOAT attributes + a PNG texture, so
it loads through EntityLoader's *skip-packing* sidecar path (no temp GLB) — the
live path that unit tests otherwise never exercise on a real on-disk file.

Pure stdlib (struct/zlib/json). Re-run after editing:  python3 make_cube.py
"""
import json
import struct
import zlib
from pathlib import Path

HERE = Path(__file__).resolve().parent

# Face table: center, u (right), v (up); normal = u x v points outward.
# Colours follow the axis convention (+X red, -X cyan, +Y green, -Y magenta,
# +Z blue, -Z yellow) so orientation is unambiguous in a render.
H = 0.5
FACES = [
    # name        center            u_dir         v_dir        atlas cell (col,row)  rgb
    ("+X", (H, 0, 0), (0, 0, -1), (0, 1, 0), (0, 0), (0xD4, 0x3A, 0x2F)),
    ("-X", (-H, 0, 0), (0, 0, 1), (0, 1, 0), (1, 0), (0x2F, 0xB8, 0xC4)),
    ("+Y", (0, H, 0), (1, 0, 0), (0, 0, -1), (2, 0), (0x4C, 0xB0, 0x4C)),
    ("-Y", (0, -H, 0), (1, 0, 0), (0, 0, 1), (0, 1), (0xC4, 0x3C, 0xA8)),
    ("+Z", (0, 0, H), (1, 0, 0), (0, 1, 0), (1, 1), (0x35, 0x6C, 0xD4)),
    ("-Z", (0, 0, -H), (-1, 0, 0), (0, 1, 0), (2, 1), (0xE0, 0xC2, 0x3A)),
]
COLS, ROWS = 3, 2
CELL = 64  # px per atlas cell


def build_geometry():
    positions, normals, uvs, indices = [], [], [], []
    for _, c, u, v, (col, row) in [(f[0], f[1], f[2], f[3], f[4]) for f in FACES]:
        n = (
            u[1] * v[2] - u[2] * v[1],
            u[2] * v[0] - u[0] * v[2],
            u[0] * v[1] - u[1] * v[0],
        )
        # Corners BL, BR, TR, TL (CCW seen from outside).
        corners = [
            (-1, -1), (1, -1), (1, 1), (-1, 1),
        ]
        base = len(positions) // 3
        # Inset UVs by half a texel so linear sampling never bleeds across cells.
        eps = 0.5 / (CELL)
        u0, u1 = col / COLS + eps, (col + 1) / COLS - eps
        v0, v1 = row / ROWS + eps, (row + 1) / ROWS - eps
        uv_corners = [(u0, v1), (u1, v1), (u1, v0), (u0, v0)]
        for (su, sv), (tu, tv) in zip(corners, uv_corners):
            p = (
                c[0] + u[0] * su * H + v[0] * sv * H,
                c[1] + u[1] * su * H + v[1] * sv * H,
                c[2] + u[2] * su * H + v[2] * sv * H,
            )
            positions += list(p)
            normals += list(n)
            uvs += [tu, tv]
        indices += [base, base + 1, base + 2, base, base + 2, base + 3]
    return positions, normals, uvs, indices


def pack_bin(positions, normals, uvs, indices):
    def f32(vals):
        return b"".join(struct.pack("<f", v) for v in vals)

    pos_b, nrm_b, uv_b = f32(positions), f32(normals), f32(uvs)
    idx_b = b"".join(struct.pack("<H", i) for i in indices)
    # 4-byte align each view; float blocks already are, indices padded to 4.
    while len(idx_b) % 4:
        idx_b += b"\x00"
    return pos_b, nrm_b, uv_b, idx_b


def write_png(path, rgb_cells):
    """Minimal RGBA PNG: solid-colour atlas, COLS x ROWS cells of CELL px."""
    w, h = COLS * CELL, ROWS * CELL
    grid = {(col, row): rgb for (col, row), rgb in rgb_cells}
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter type 0 (none) per scanline
        row = y // CELL
        for x in range(w):
            col = x // CELL
            r, g, b = grid[(col, row)]
            raw += bytes((r, g, b, 255))

    def chunk(tag, data):
        out = struct.pack(">I", len(data)) + tag + data
        return out + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)  # 8-bit RGBA
    idat = zlib.compress(bytes(raw), 9)
    path.write_bytes(sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b""))


def main():
    positions, normals, uvs, indices = build_geometry()
    pos_b, nrm_b, uv_b, idx_b = pack_bin(positions, normals, uvs, indices)

    off_pos = 0
    off_nrm = off_pos + len(pos_b)
    off_uv = off_nrm + len(nrm_b)
    off_idx = off_uv + len(uv_b)
    bin_data = pos_b + nrm_b + uv_b + idx_b

    count = len(positions) // 3
    xs, ys, zs = positions[0::3], positions[1::3], positions[2::3]

    gltf = {
        "asset": {"version": "2.0", "generator": "glb-preview cube fixture"},
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": "Cube"}],
        "meshes": [{
            "name": "Cube",
            "primitives": [{
                "attributes": {"POSITION": 0, "NORMAL": 1, "TEXCOORD_0": 2},
                "indices": 3,
                "material": 0,
            }],
        }],
        "materials": [{
            "name": "Faces",
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": 0},
                "metallicFactor": 0.0,
                "roughnessFactor": 0.6,
            },
        }],
        "textures": [{"source": 0, "sampler": 0}],
        "images": [{"uri": "cube.png"}],
        "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 33071, "wrapT": 33071}],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": count, "type": "VEC3",
             "min": [min(xs), min(ys), min(zs)], "max": [max(xs), max(ys), max(zs)]},
            {"bufferView": 1, "componentType": 5126, "count": count, "type": "VEC3"},
            {"bufferView": 2, "componentType": 5126, "count": count, "type": "VEC2"},
            {"bufferView": 3, "componentType": 5123, "count": len(indices), "type": "SCALAR"},
        ],
        "bufferViews": [
            {"buffer": 0, "byteOffset": off_pos, "byteLength": len(pos_b), "target": 34962},
            {"buffer": 0, "byteOffset": off_nrm, "byteLength": len(nrm_b), "target": 34962},
            {"buffer": 0, "byteOffset": off_uv, "byteLength": len(uv_b), "target": 34962},
            {"buffer": 0, "byteOffset": off_idx, "byteLength": len(idx_b), "target": 34963},
        ],
        "buffers": [{"uri": "cube.bin", "byteLength": len(bin_data)}],
    }

    (HERE / "cube.bin").write_bytes(bin_data)
    write_png(HERE / "cube.png", [(f[4], f[5]) for f in FACES])
    (HERE / "cube.gltf").write_text(json.dumps(gltf, indent=1) + "\n")
    print(f"wrote cube.gltf ({len(json.dumps(gltf))} B json), "
          f"cube.bin ({len(bin_data)} B), cube.png ({(HERE / 'cube.png').stat().st_size} B)")


if __name__ == "__main__":
    main()
