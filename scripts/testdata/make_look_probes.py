#!/usr/bin/env python3
"""Generate the look-probe fixtures under `TestModels/Fixture Models/probes/`.

Synthetic scenes that isolate one look quantity each, rendered on both renderers by
`GLTFInspectorTests/CrossRenderer/LookProbeTests.swift` (opt-in; see that file). Results live in
`.agents/research/2026-09-30-look-probes.md`.

- `env-wheel.hdr`       equirect whose colour encodes longitude only:
                        R = 0.4 (1 + cos 2πu), G = 0.4 (1 + sin 2πu), B = 0.4, u = column / width.
                        Any renderer that is linear up to a common scale decodes the longitude
                        it reflected as atan2(G/B - 1, R/B - 1), independent of that scale.
- `mirror-sphere.gltf`  unit UV sphere, metallic 1 / roughness 0 / white. No lights.
- `plane-directional.gltf`  white Lambert-ish plane (metallic 0, roughness 1) in XY facing +Z,
                        lit by one KHR_lights_punctual directional of 1 lux pointing −Z.
- `plane-point.gltf`    same plane, one point light of 1 cd at (0, 0, 1).
- `plane-spot.gltf`     same plane, one spot of 1 cd at (0, 0, 1) aiming −Z, cone 0 … π/4.
- `emissive-ramp.gltf`  six black quads in a row with achromatic emissive factor f and
                        KHR_materials_emissive_strength 2 (> 1, so the baked-emissive policy
                        keeps them), plus a 0-lux directional so the web page does not add its
                        default key+fill.

Pure stdlib, buffers embedded as data: URIs.  Re-run:  python3 scripts/testdata/make_look_probes.py
"""
import base64
import json
import math
import struct
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEST = HERE.parents[1] / "TestModels" / "Fixture Models" / "probes"

EMISSIVE_FACTORS = [0.0125, 0.025, 0.05, 0.1, 0.2, 0.4]
EMISSIVE_STRENGTH = 2.0


def data_uri(raw: bytes) -> str:
    return "data:application/octet-stream;base64," + base64.b64encode(raw).decode("ascii")


def pack(fmt, values):
    return b"".join(struct.pack("<" + fmt, v) for v in values)


class Builder:
    """Minimal single-buffer glTF assembler."""

    def __init__(self):
        self.blob = b""
        self.views = []
        self.accessors = []

    def _align(self):
        while len(self.blob) % 4:
            self.blob += b"\0"

    def add(self, raw, target, component, count, kind, minmax=None):
        self._align()
        self.views.append({"buffer": 0, "byteOffset": len(self.blob), "byteLength": len(raw), "target": target})
        self.blob += raw
        accessor = {"bufferView": len(self.views) - 1, "componentType": component, "count": count, "type": kind}
        if minmax:
            accessor["min"], accessor["max"] = minmax
        self.accessors.append(accessor)
        return len(self.accessors) - 1

    def mesh(self, positions, normals, indices):
        xs, ys, zs = positions[0::3], positions[1::3], positions[2::3]
        p = self.add(pack("f", positions), 34962, 5126, len(positions) // 3, "VEC3",
                     ([min(xs), min(ys), min(zs)], [max(xs), max(ys), max(zs)]))
        n = self.add(pack("f", normals), 34962, 5126, len(normals) // 3, "VEC3")
        i = self.add(pack("H", indices), 34963, 5123, len(indices), "SCALAR")
        return {"attributes": {"POSITION": p, "NORMAL": n}, "indices": i}

    def document(self, extra):
        self._align()
        doc = {
            "asset": {"version": "2.0", "generator": "glb-preview make_look_probes.py"},
            "buffers": [{"byteLength": len(self.blob), "uri": data_uri(self.blob)}],
            "bufferViews": self.views,
            "accessors": self.accessors,
        }
        doc.update(extra)
        return doc


def quad(cx, cy, half):
    positions = [cx - half, cy - half, 0, cx + half, cy - half, 0, cx + half, cy + half, 0, cx - half, cy + half, 0]
    return positions, [0, 0, 1] * 4, [0, 1, 2, 0, 2, 3]


def sphere(segments=48, rings=24):
    positions, normals, indices = [], [], []
    for r in range(rings + 1):
        theta = math.pi * r / rings
        for s in range(segments + 1):
            phi = 2 * math.pi * s / segments
            n = [math.sin(theta) * math.sin(phi), math.cos(theta), math.sin(theta) * math.cos(phi)]
            positions += n
            normals += n
    for r in range(rings):
        for s in range(segments):
            a = r * (segments + 1) + s
            b = a + segments + 1
            indices += [a, b, a + 1, a + 1, b, b + 1]
    return positions, normals, indices


def write(name, doc):
    out = DEST / name
    out.write_text(json.dumps(doc, separators=(",", ":")) + "\n")
    print(f"wrote {out.relative_to(DEST.parents[2])}  ({out.stat().st_size} B)")


def plane_doc(light):
    b = Builder()
    mesh = b.mesh(*quad(0, 0, 3))
    nodes = [{"mesh": 0, "name": "plane"}, {"name": "light", "extensions": {"KHR_lights_punctual": {"light": 0}}}]
    if "translation" in light:
        nodes[1]["translation"] = light.pop("translation")
    return b.document({
        "extensionsUsed": ["KHR_lights_punctual"],
        "extensions": {"KHR_lights_punctual": {"lights": [light]}},
        "scene": 0,
        "scenes": [{"nodes": [0, 1]}],
        "nodes": nodes,
        "meshes": [{"primitives": [dict(mesh, material=0)]}],
        "materials": [{"name": "lambert", "pbrMetallicRoughness": {
            "baseColorFactor": [1, 1, 1, 1], "metallicFactor": 0, "roughnessFactor": 1}}],
    })


def write_hdr(name, width=128, height=64):
    def rgbe(r, g, b):
        m = max(r, g, b)
        if m < 1e-32:
            return bytes([0, 0, 0, 0])
        e = math.frexp(m)[1]
        scale = math.ldexp(1.0, -e) * 256
        return bytes([int(r * scale), int(g * scale), int(b * scale), e + 128])

    header = f"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y {height} +X {width}\n".encode("ascii")
    row = b"".join(
        rgbe(0.4 * (1 + math.cos(2 * math.pi * (x + 0.5) / width)),
             0.4 * (1 + math.sin(2 * math.pi * (x + 0.5) / width)),
             0.4)
        for x in range(width)
    )
    out = DEST / name
    out.write_bytes(header + row * height)
    print(f"wrote {out.relative_to(DEST.parents[2])}  ({out.stat().st_size} B)")


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    write_hdr("env-wheel.hdr")

    b = Builder()
    mesh = b.mesh(*sphere())
    write("mirror-sphere.gltf", b.document({
        "scene": 0,
        "scenes": [{"nodes": [0]}],
        "nodes": [{"mesh": 0, "name": "mirror"}],
        "meshes": [{"primitives": [dict(mesh, material=0)]}],
        "materials": [{"name": "mirror", "pbrMetallicRoughness": {
            "baseColorFactor": [1, 1, 1, 1], "metallicFactor": 1, "roughnessFactor": 0}}],
    }))

    write("plane-directional.gltf", plane_doc({"type": "directional", "intensity": 1.0}))
    write("plane-point.gltf", plane_doc({"type": "point", "intensity": 1.0, "translation": [0, 0, 1]}))
    write("plane-spot.gltf", plane_doc({"type": "spot", "intensity": 1.0, "translation": [0, 0, 1],
                                        "spot": {"innerConeAngle": 0.0, "outerConeAngle": math.pi / 4}}))

    b = Builder()
    meshes, materials, nodes = [], [], []
    for i, f in enumerate(EMISSIVE_FACTORS):
        meshes.append({"primitives": [dict(b.mesh(*quad(-2.5 + i, 0, 0.4)), material=i)]})
        materials.append({
            "name": f"emissive-{f}",
            "pbrMetallicRoughness": {"baseColorFactor": [0, 0, 0, 1], "metallicFactor": 0, "roughnessFactor": 1},
            "emissiveFactor": [f, f, f],
            "extensions": {"KHR_materials_emissive_strength": {"emissiveStrength": EMISSIVE_STRENGTH}},
        })
        nodes.append({"mesh": i, "name": f"quad{i}"})
    nodes.append({"name": "dark", "extensions": {"KHR_lights_punctual": {"light": 0}}})
    write("emissive-ramp.gltf", b.document({
        "extensionsUsed": ["KHR_lights_punctual", "KHR_materials_emissive_strength"],
        "extensions": {"KHR_lights_punctual": {"lights": [{"type": "directional", "intensity": 0.0}]}},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": materials,
    }))


if __name__ == "__main__":
    main()
