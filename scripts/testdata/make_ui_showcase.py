#!/usr/bin/env python3
"""One GLB that fills every sidebar section.

File → two scenes → a group tree of meshes, cameras and lights, plus materials,
a skin, morph targets and an animation clip. Geometry is one triangle so the
renderer can draw it. Regen: python3 scripts/testdata/make_ui_showcase.py
"""
import json
import struct
from pathlib import Path

DEST = Path(__file__).resolve().parents[2] / "TestModels" / "Fixture Models" / "ui-showcase.glb"

FLOAT = 5126
USHORT = 5123
UBYTE = 5121


class Blob:
    def __init__(self):
        self.data = bytearray()
        self.views = []
        self.accessors = []

    def view(self, raw, target=None):
        while len(self.data) % 4:
            self.data.append(0)
        offset = len(self.data)
        self.data += raw
        view = {"buffer": 0, "byteOffset": offset, "byteLength": len(raw)}
        if target:
            view["target"] = target
        index = len(self.views)
        self.views.append(view)
        return index

    def accessor(self, view, count, type_, component, min_=None, max_=None):
        acc = {
            "bufferView": view,
            "componentType": component,
            "count": count,
            "type": type_,
        }
        if min_ is not None:
            acc["min"] = min_
        if max_ is not None:
            acc["max"] = max_
        index = len(self.accessors)
        self.accessors.append(acc)
        return index


def floats(values):
    return struct.pack("<" + "f" * len(values), *[float(v) for v in values])


def build():
    blob = Blob()
    positions = [0, 0, 0, 1, 0, 0, 0, 1, 0]
    morph = [0, 0, 0.4, 1, 0, 0.4, 0, 1, 0.4]
    indices = struct.pack("<HHH", 0, 1, 2)
    joints = struct.pack("<" + "BBBB" * 3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    weights = floats([1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0])
    times = floats([0, 1])
    translation = floats([0, 0, 0, 0, 0.35, 0])
    morph_weights = floats([0, 1])
    identity = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
    ibms = floats(identity + identity)

    position = blob.accessor(
        blob.view(floats(positions), 34962), 3, "VEC3", FLOAT, [0, 0, 0], [1, 1, 0]
    )
    index = blob.accessor(blob.view(indices, 34963), 3, "SCALAR", USHORT)
    morph_position = blob.accessor(
        blob.view(floats(morph)), 3, "VEC3", FLOAT, [0, 0, 0.4], [1, 1, 0.4]
    )
    joint_acc = blob.accessor(blob.view(joints), 3, "VEC4", UBYTE)
    weight_acc = blob.accessor(blob.view(weights), 3, "VEC4", FLOAT)
    time_acc = blob.accessor(blob.view(times), 2, "SCALAR", FLOAT, [0], [1])
    translation_acc = blob.accessor(blob.view(translation), 2, "VEC3", FLOAT)
    weight_anim = blob.accessor(blob.view(morph_weights), 2, "SCALAR", FLOAT, [0], [1])
    ibm_acc = blob.accessor(blob.view(ibms), 2, "MAT4", FLOAT)

    light = lambda index: {"KHR_lights_punctual": {"light": index}}
    doc = {
        "asset": {"version": "2.0", "generator": "glb-preview make_ui_showcase.py"},
        "extensionsUsed": ["KHR_lights_punctual"],
        "extensions": {
            "KHR_lights_punctual": {
                "lights": [
                    {"name": "Sun", "type": "directional", "color": [1, 0.96, 0.9], "intensity": 3},
                    {"name": "Lamp", "type": "point", "color": [1, 0.85, 0.6], "intensity": 20, "range": 6},
                    {
                        "name": "Spot",
                        "type": "spot",
                        "color": [0.7, 0.8, 1],
                        "intensity": 40,
                        "range": 8,
                        "spot": {"innerConeAngle": 0.2, "outerConeAngle": 0.5},
                    },
                ]
            }
        },
        "buffers": [{"byteLength": len(blob.data)}],
        "bufferViews": blob.views,
        "accessors": blob.accessors,
        "materials": [
            {"name": "Clay", "pbrMetallicRoughness": {"baseColorFactor": [0.8, 0.45, 0.3, 1], "roughnessFactor": 0.8}},
            {"name": "Metal", "pbrMetallicRoughness": {"baseColorFactor": [0.7, 0.72, 0.75, 1], "metallicFactor": 1, "roughnessFactor": 0.25}},
        ],
        "meshes": [
            {"name": "Body", "primitives": [{"attributes": {"POSITION": position}, "indices": index, "material": 0}]},
            {
                "name": "Arm",
                "primitives": [{
                    "attributes": {"POSITION": position, "JOINTS_0": joint_acc, "WEIGHTS_0": weight_acc},
                    "indices": index,
                    "material": 1,
                }],
            },
            {
                "name": "Blob",
                "weights": [0],
                "extras": {"targetNames": ["Squash"]},
                "primitives": [{
                    "attributes": {"POSITION": position},
                    "indices": index,
                    "material": 0,
                    "targets": [{"POSITION": morph_position}],
                }],
            },
        ],
        "cameras": [
            {"name": "Main Camera", "type": "perspective", "perspective": {"yfov": 0.6, "znear": 0.1, "zfar": 50}},
            {"name": "Top Camera", "type": "orthographic", "orthographic": {"xmag": 2, "ymag": 2, "znear": 0.1, "zfar": 20}},
        ],
        "skins": [{"name": "Armature", "joints": [6, 7], "inverseBindMatrices": ibm_acc, "skeleton": 6}],
        "nodes": [
            {"name": "Stage", "children": [1, 4, 9, 12]},          # 0 group
            {"name": "Props", "children": [2, 3]},                  # 1 group
            {"name": "Body", "mesh": 0, "translation": [-0.6, 0, 0]},  # 2 mesh
            {"name": "Blob", "mesh": 2, "translation": [0.8, 0, 0]},   # 3 morph mesh
            {"name": "Rig", "children": [5, 8]},                    # 4 group
            {"name": "Shoulder", "children": [6, 7], "translation": [1.4, 0.2, 0]},  # 5 group
            {"name": "Upper Arm", "translation": [0, 0.4, 0]},     # 6 joint
            {"name": "Forearm", "translation": [0, 0.8, 0]},        # 7 joint
            {"name": "Arm", "mesh": 1, "skin": 0},                  # 8 skinned mesh
            {"name": "Cameras", "children": [10, 11]},              # 9 group
            {"name": "Main Camera", "camera": 0, "translation": [0, 0.6, 3]},
            {"name": "Top Camera", "camera": 1, "translation": [0, 3, 0]},
            {"name": "Lights", "children": [13, 14, 15]},           # 12 group
            {"name": "Sun", "extensions": light(0), "translation": [0, 2, 2]},
            {"name": "Lamp", "extensions": light(1), "translation": [-1, 1.5, 1]},
            {"name": "Spot", "extensions": light(2), "translation": [1, 1.5, 1]},
            {"name": "Hero", "mesh": 2},                            # 16 close-up only
        ],
        "animations": [
            {
                "name": "Bounce",
                "samplers": [{"input": time_acc, "output": translation_acc, "interpolation": "LINEAR"}],
                "channels": [{"sampler": 0, "target": {"node": 2, "path": "translation"}}],
            },
            {
                "name": "Squash",
                "samplers": [{"input": time_acc, "output": weight_anim, "interpolation": "LINEAR"}],
                "channels": [{"sampler": 0, "target": {"node": 3, "path": "weights"}}],
            },
        ],
        "scenes": [
            {"name": "Studio", "nodes": [0]},
            {"name": "Close-up", "nodes": [16]},
        ],
        "scene": 0,
    }
    return doc, bytes(blob.data)


def glb(doc, binary):
    json_chunk = json.dumps(doc, separators=(",", ":")).encode()
    json_chunk += b" " * ((4 - len(json_chunk) % 4) % 4)
    binary += b"\x00" * ((4 - len(binary) % 4) % 4)
    total = 12 + 8 + len(json_chunk) + 8 + len(binary)
    return b"".join([
        struct.pack("<III", 0x46546C67, 2, total),
        struct.pack("<II", len(json_chunk), 0x4E4F534A),
        json_chunk,
        struct.pack("<II", len(binary), 0x004E4942),
        binary,
    ])


def main():
    doc, binary = build()
    DEST.parent.mkdir(parents=True, exist_ok=True)
    DEST.write_bytes(glb(doc, binary))
    print(f"wrote {DEST} ({DEST.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
