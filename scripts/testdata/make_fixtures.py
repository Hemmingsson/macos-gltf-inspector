#!/usr/bin/env python3
"""Generate the adaptive-UI test fixtures under `TestModels/Fixture Models/`.

One tiny, self-contained glTF per capability the new UI shows/hides (DESIGN.md
"show only what the model has"). Geometry is the flat unit triangle used by the
in-memory test builders, so every file is byte-small and known to load through
GLTFKit2 / EntityLoader. Buffers are embedded as base64 `data:` URIs — single
file, no `.bin` sidecar, nothing to download.

These mirror the JSON that the passing Swift builders emit
(`SceneGraphConvertTests`, `SessionDocumentTests`, `MorphSkeletonTests`), so they
stay valid. Catalogue: `scripts/testdata/README.md`. Accessor: `GLTFInspectorTests/TestFixtures.swift`.

Pure stdlib. Re-run after editing:  python3 scripts/testdata/make_fixtures.py
"""
import base64
import json
import struct
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEST = HERE.parents[1] / "TestModels" / "Fixture Models"

# Flat triangle: (0,0,0) (1,0,0) (0,1,0) — matches floatTrianglePositions() in the tests.
TRI = [0, 0, 0, 1, 0, 0, 0, 1, 0]


def floats(values):
    return b"".join(struct.pack("<f", float(v)) for v in values)


def ushorts(values):
    return b"".join(struct.pack("<H", int(v)) for v in values)


def data_uri(raw: bytes) -> str:
    return "data:application/octet-stream;base64," + base64.b64encode(raw).decode("ascii")


def write(rel: str, doc: dict) -> None:
    out = DEST / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(doc, indent=2) + "\n")
    print(f"wrote {out.relative_to(DEST.parents[1])}  ({out.stat().st_size} B)")


def base_doc(bin_blob: bytes, extra: dict) -> dict:
    doc = {
        "asset": {"version": "2.0", "generator": "glb-preview make_fixtures.py"},
        "buffers": [{"byteLength": len(bin_blob), "uri": data_uri(bin_blob)}],
    }
    doc.update(extra)
    return doc


def tri_position_accessor(offset=0):
    return {
        "bufferView": 0,
        "byteOffset": 0,
        "componentType": 5126,  # FLOAT
        "count": 3,
        "type": "VEC3",
        "max": [1, 1, 0],
        "min": [0, 0, 0],
    }


# --- multiscene: two scenes so the Scene switcher appears --------------------
def make_multiscene():
    blob = floats(TRI)
    doc = base_doc(blob, {
        "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(blob)}],
        "accessors": [tri_position_accessor()],
        "meshes": [
            {"name": "MeshA", "primitives": [{"attributes": {"POSITION": 0}}]},
            {"name": "MeshB", "primitives": [{"attributes": {"POSITION": 0}}]},
        ],
        "nodes": [
            {"name": "RootA", "mesh": 0},
            {"name": "RootB", "mesh": 1},
        ],
        "scenes": [
            {"name": "SceneA", "nodes": [0]},
            {"name": "SceneB", "nodes": [1]},
        ],
        "scene": 0,
    })
    write("multiscene/two-scenes.gltf", doc)


# --- lights: KHR_lights_punctual point + directional + spot ------------------
def make_lights():
    blob = floats(TRI)
    doc = base_doc(blob, {
        "extensionsUsed": ["KHR_lights_punctual"],
        "extensions": {"KHR_lights_punctual": {"lights": [
            {"name": "Key", "type": "point", "color": [1, 0.95, 0.9], "intensity": 12},
            {"name": "Sun", "type": "directional", "color": [1, 1, 1], "intensity": 2.5},
            {"name": "Spot", "type": "spot", "color": [0.8, 0.8, 1], "intensity": 8,
             "spot": {"innerConeAngle": 0.2, "outerConeAngle": 0.6}},
        ]}},
        "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(blob)}],
        "accessors": [tri_position_accessor()],
        "meshes": [{"name": "Lit", "primitives": [{"attributes": {"POSITION": 0}}]}],
        "nodes": [
            {"name": "Mesh", "mesh": 0, "extensions": {"KHR_lights_punctual": {"light": 0}}},
            {"name": "Sun", "extensions": {"KHR_lights_punctual": {"light": 1}}},
            {"name": "Spot", "translation": [0, 2, 0], "extensions": {"KHR_lights_punctual": {"light": 2}}},
        ],
        "scenes": [{"name": "Default", "nodes": [0, 1, 2]}],
        "scene": 0,
    })
    write("lights/punctual-lights.gltf", doc)


# --- cameras: one perspective + one orthographic ----------------------------
def make_cameras():
    blob = floats(TRI)
    doc = base_doc(blob, {
        "cameras": [
            {"name": "Persp", "type": "perspective",
             "perspective": {"yfov": 0.7, "znear": 0.1, "zfar": 100}},
            {"name": "Ortho", "type": "orthographic",
             "orthographic": {"xmag": 1, "ymag": 1, "znear": 0.1, "zfar": 100}},
        ],
        "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(blob)}],
        "accessors": [tri_position_accessor()],
        "meshes": [{"name": "Framed", "primitives": [{"attributes": {"POSITION": 0}}]}],
        "nodes": [
            {"name": "Mesh", "mesh": 0},
            {"name": "CamPersp", "camera": 0, "translation": [0, 0, 3]},
            {"name": "CamOrtho", "camera": 1, "translation": [3, 0, 0]},
        ],
        "scenes": [{"name": "Default", "nodes": [0, 1, 2]}],
        "scene": 0,
    })
    write("cameras/persp-and-ortho.gltf", doc)


# --- missing-channels: baseColor factor only, no textures -------------------
# View-mode menu shortens; material chips omit absent maps.
def make_missing_channels():
    blob = floats(TRI)
    doc = base_doc(blob, {
        "materials": [{
            "name": "BaseOnly",
            "pbrMetallicRoughness": {
                "baseColorFactor": [0.82, 0.32, 0.30, 1],
                "metallicFactor": 0.0,
                "roughnessFactor": 0.6,
            },
        }],
        "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(blob)}],
        "accessors": [tri_position_accessor()],
        "meshes": [{"name": "Plain", "primitives": [{"attributes": {"POSITION": 0}, "material": 0}]}],
        "nodes": [{"name": "Mesh", "mesh": 0}],
        "scenes": [{"name": "Default", "nodes": [0]}],
        "scene": 0,
    })
    write("missing-channels/basecolor-only.gltf", doc)


# --- missing-texture: valid JSON, image URI that does not exist -------------
def make_missing_texture():
    blob = floats(TRI)
    doc = base_doc(blob, {
        "images": [{"uri": "does-not-exist.png"}],
        "textures": [{"source": 0}],
        "materials": [{
            "name": "MissingMap",
            "pbrMetallicRoughness": {
                "baseColorTexture": {"index": 0},
                "metallicFactor": 0.0,
                "roughnessFactor": 0.6,
            },
        }],
        "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(blob)}],
        "accessors": [tri_position_accessor()],
        "meshes": [{"name": "Textured", "primitives": [
            {"attributes": {"POSITION": 0}, "material": 0},
        ]}],
        "nodes": [{"name": "Mesh", "mesh": 0}],
        "scenes": [{"name": "Default", "nodes": [0]}],
        "scene": 0,
    })
    write("missing-texture/missing-image.gltf", doc)


# --- rigged: two-joint skin (ports writeTempTwoJointSkinGLB) -----------------
def make_rigged():
    positions = floats(TRI)                                   # 36 B
    joints = ushorts([0, 0, 0, 0] * 3)                        # 3× UNSIGNED_SHORT VEC4 = 24 B
    weights = floats([1, 0, 0, 0] * 3)                        # 3× FLOAT VEC4 = 48 B
    identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    ibm = floats(identity * 2)                                # 2× MAT4 = 128 B
    blob = positions + joints + weights + ibm
    p, j, w = len(positions), len(joints), len(weights)
    doc = base_doc(blob, {
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": p},
            {"buffer": 0, "byteOffset": p, "byteLength": j},
            {"buffer": 0, "byteOffset": p + j, "byteLength": w},
            {"buffer": 0, "byteOffset": p + j + w, "byteLength": len(ibm)},
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
             "max": [1, 1, 0], "min": [0, 0, 0]},
            {"bufferView": 1, "componentType": 5123, "count": 3, "type": "VEC4"},
            {"bufferView": 2, "componentType": 5126, "count": 3, "type": "VEC4"},
            {"bufferView": 3, "componentType": 5126, "count": 2, "type": "MAT4"},
        ],
        "meshes": [{"name": "SkinnedTri", "primitives": [{"attributes": {
            "POSITION": 0, "JOINTS_0": 1, "WEIGHTS_0": 2}}]}],
        "skins": [{"name": "Arm", "joints": [1, 2], "inverseBindMatrices": 3}],
        "nodes": [
            {"name": "Mesh", "mesh": 0, "skin": 0, "children": [1]},
            {"name": "Hip", "children": [2], "translation": [0, 0, 0]},
            {"name": "Knee", "translation": [0, 1, 0]},
        ],
        "scenes": [{"name": "Default", "nodes": [0]}],
        "scene": 0,
    })
    write("rigged/two-joint-skin.gltf", doc)


# --- morph: one morph target with a name (ports morphTriangleGLB) -----------
def make_morph():
    base = floats(TRI)                                       # 36 B
    target = floats([0, 0, 1, 0, 0, 0, 0, 0, 0])            # delta on vertex 0
    blob = base + target
    doc = base_doc(blob, {
        "bufferViews": [
            {"buffer": 0, "byteOffset": 0, "byteLength": len(base)},
            {"buffer": 0, "byteOffset": len(base), "byteLength": len(target)},
        ],
        "accessors": [
            {"bufferView": 0, "componentType": 5126, "count": 3, "type": "VEC3",
             "max": [1, 1, 0], "min": [0, 0, 0]},
            {"bufferView": 1, "componentType": 5126, "count": 3, "type": "VEC3",
             "max": [0, 0, 1], "min": [0, 0, 0]},
        ],
        "meshes": [{
            "name": "MorphTri",
            "primitives": [{"attributes": {"POSITION": 0}, "targets": [{"POSITION": 1}]}],
            "weights": [0],
            "extras": {"targetNames": ["Blink"]},
        }],
        "nodes": [{"name": "Mesh", "mesh": 0}],
        "scenes": [{"name": "Default", "nodes": [0]}],
        "scene": 0,
    })
    write("morph/morph-triangle.gltf", doc)


# --- corrupt: valid magic, lying chunk length, truncated body ----------------
# Distinct from invalid/unresolved-mesh.gltf (which is *semantically* invalid but
# parseable). This one fails at the container level — the hard-failure path.
def make_corrupt():
    body = b'{"asset":{"vers'  # truncated JSON, and the header lies about lengths
    header = b"glTF"
    header += struct.pack("<I", 2)          # version 2
    header += struct.pack("<I", 4096)       # total length — far larger than the file
    header += struct.pack("<I", 4096)       # JSON chunk length — also a lie
    header += b"JSON"
    out = DEST / "corrupt/truncated.glb"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(header + body)
    print(f"wrote {out.relative_to(DEST.parents[1])}  ({out.stat().st_size} B, intentionally corrupt)")


def main():
    make_multiscene()
    make_lights()
    make_cameras()
    make_missing_channels()
    make_missing_texture()
    make_rigged()
    make_morph()
    make_corrupt()


if __name__ == "__main__":
    main()
