#!/usr/bin/env python3
"""Generate a skinned, animated GLB candidate from the repository-owned static player.

The first-pass weights are deterministic spatial weights for the project's deliberately
low-poly disconnected mesh parts. This is an integration prototype, not a substitute for
artist-authored weights. It uses only Python's standard library.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import math
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "assets/characters/player/player.glb"
DEFAULT_OUTPUT = ROOT / "assets/characters/player/player_rigged_candidate.glb"
ARRAY_BUFFER = 34962
ELEMENT_ARRAY_BUFFER = 34963
FLOAT = 5126
UNSIGNED_SHORT = 5123
JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942

# All bone pivots are in model-local meters; +Y is up, forward is -Z.
BONES = [
    ("Hips", (0.0, 0.72, 0.0)),
    ("Spine", (0.0, 0.88, 0.0)),
    ("Chest", (0.0, 1.10, 0.0)),
    ("Head", (0.0, 1.46, 0.0)),
    ("UpperArm_L", (-0.29, 1.26, 0.0)),
    ("LowerArm_L", (-0.415, 1.14, -0.005)),
    ("Hand_L", (-0.485, 1.00, -0.02)),
    ("UpperArm_R", (0.29, 1.26, 0.0)),
    ("LowerArm_R", (0.415, 1.14, -0.005)),
    ("Hand_R", (0.485, 1.00, -0.02)),
    ("UpperLeg_L", (-0.14, 0.63, 0.0)),
    ("LowerLeg_L", (-0.13, 0.38, 0.0)),
    ("Foot_L", (-0.14, 0.15, -0.04)),
    ("UpperLeg_R", (0.14, 0.63, 0.0)),
    ("LowerLeg_R", (0.13, 0.38, 0.0)),
    ("Foot_R", (0.14, 0.15, -0.04)),
    ("Cape", (0.0, 0.92, 0.27)),
]
BONE_INDEX = {name: i for i, (name, _) in enumerate(BONES)}


def parse_glb(data: bytes):
    if len(data) < 28:
        raise ValueError("source GLB is too small")
    magic, version, total = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or total != len(data):
        raise ValueError("invalid GLB 2.0 header or total length")
    offset, document, binary = 12, None, None
    while offset + 8 <= len(data):
        size, kind = struct.unpack_from("<II", data, offset)
        offset += 8
        if offset + size > len(data):
            raise ValueError("GLB chunk exceeds file boundary")
        chunk = data[offset:offset + size]
        offset += size
        if kind == JSON_CHUNK:
            document = json.loads(chunk.decode("utf-8").rstrip(" \t\r\n\x00"))
        elif kind == BIN_CHUNK:
            binary = chunk
    if document is None or binary is None:
        raise ValueError("GLB must contain JSON and BIN chunks")
    buffers = document.get("buffers", [])
    if not buffers or not isinstance(buffers[0].get("byteLength"), int):
        raise ValueError("missing embedded buffer declaration")
    declared = buffers[0]["byteLength"]
    if declared < 0 or declared > len(binary):
        raise ValueError("embedded buffer byteLength exceeds BIN chunk")
    return document, bytearray(binary[:declared])


def append_bytes(document, binary, payload, target=None):
    while len(binary) % 4:
        binary.append(0)
    offset = len(binary)
    binary.extend(payload)
    view = {"buffer": 0, "byteOffset": offset, "byteLength": len(payload)}
    if target is not None:
        view["target"] = target
    view_index = len(document.setdefault("bufferViews", []))
    document["bufferViews"].append(view)
    return view_index


def append_float_accessor(document, binary, values, kind, target=None, include_bounds=False):
    payload = struct.pack("<" + "f" * len(values), *values)
    view = append_bytes(document, binary, payload, target)
    element_width = {"SCALAR": 1, "VEC3": 3, "VEC4": 4, "MAT4": 16}[kind]
    accessor = {
        "bufferView": view,
        "componentType": FLOAT,
        "count": len(values) // element_width,
        "type": kind,
    }
    if include_bounds and kind == "SCALAR" and values:
        accessor["min"] = [min(values)]
        accessor["max"] = [max(values)]
    index = len(document.setdefault("accessors", []))
    document["accessors"].append(accessor)
    return index


def get_accessor_payload(document, binary, accessor_index):
    accessors = document["accessors"]
    views = document["bufferViews"]
    accessor = accessors[accessor_index]
    view = views[accessor["bufferView"]]
    if accessor.get("componentType") != FLOAT or accessor.get("type") != "VEC3":
        raise ValueError("source POSITION accessor must be float VEC3")
    stride = view.get("byteStride", 12)
    if stride != 12:
        raise ValueError("unexpected interleaved POSITION buffer; refusing unsafe conversion")
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    count = accessor["count"]
    if start < 0 or start + count * stride > len(binary):
        raise ValueError("POSITION accessor exceeds embedded binary")
    return [struct.unpack_from("<fff", binary, start + i * stride) for i in range(count)]


def component_bone(center, material_index):
    x, y, z = center
    ax = abs(x)
    # Assign an entire edge-connected mesh component to one pivot. This model is
    # composed of disconnected low-poly parts; per-triangle weights caused visible spikes.
    if material_index == 7:
        return BONE_INDEX["Cape"]
    if material_index == 5 or y >= 1.42:
        return BONE_INDEX["Head"]
    side = "L" if x < 0 else "R"
    if material_index == 2 and y < 0.56 and ax < 0.27:
        return BONE_INDEX[f"LowerLeg_{side}"]
    if material_index == 6 and y < 0.70 and ax < 0.27:
        return BONE_INDEX[f"LowerLeg_{side}"] if y < 0.30 else BONE_INDEX[f"UpperLeg_{side}"]
    if material_index == 1 and y < 0.22 and 0.035 < ax < 0.25:
        return BONE_INDEX[f"Foot_{side}"]
    if material_index == 1 and ax >= 0.25 and z > 0.08 and 0.30 <= y < 0.86:
        return BONE_INDEX["Hand_R"]
    if ax >= 0.25 and y >= 0.86:
        if ax >= 0.45 or y < 1.04:
            return BONE_INDEX[f"Hand_{side}"]
        if ax >= 0.36:
            return BONE_INDEX[f"LowerArm_{side}"]
        return BONE_INDEX[f"UpperArm_{side}"]
    if y < 0.82:
        return BONE_INDEX["Hips"]
    if y < 0.99:
        return BONE_INDEX["Spine"]
    return BONE_INDEX["Chest"]

def position_key(point):
    return tuple(round(float(value), 5) for value in point)

def connected_face_components(positions, indices):
    face_count = len(indices) // 3
    parents = list(range(face_count))
    def find(item):
        while parents[item] != item:
            parents[item] = parents[parents[item]]
            item = parents[item]
        return item
    def union(left, right):
        lroot, rroot = find(left), find(right)
        if lroot != rroot:
            parents[rroot] = lroot
    edge_faces = {}
    for face_index in range(face_count):
        face = indices[face_index * 3:face_index * 3 + 3]
        keys = [position_key(positions[index]) for index in face]
        for edge in ((keys[0], keys[1]), (keys[1], keys[2]), (keys[2], keys[0])):
            edge_key = tuple(sorted(edge))
            if edge_key in edge_faces:
                union(face_index, edge_faces[edge_key])
            else:
                edge_faces[edge_key] = face_index
    components = {}
    for face_index in range(face_count):
        components.setdefault(find(face_index), []).append(face_index)
    return list(components.values())

def add_skin_attributes(document, binary, primitive):
    attrs = primitive.get("attributes", {})
    if "POSITION" not in attrs or "JOINTS_0" in attrs or "WEIGHTS_0" in attrs:
        raise ValueError("expected unskinned player POSITION attributes")
    positions = get_accessor_payload(document, binary, attrs["POSITION"])
    idx_accessor = document["accessors"][primitive["indices"]]
    idx_view = document["bufferViews"][idx_accessor["bufferView"]]
    if idx_accessor.get("componentType") != UNSIGNED_SHORT or idx_accessor.get("type") != "SCALAR":
        raise ValueError("source player must use unsigned-short triangle indices")
    istart = idx_view.get("byteOffset", 0) + idx_accessor.get("byteOffset", 0)
    icount = idx_accessor["count"]
    if istart < 0 or istart + icount * 2 > len(binary) or icount % 3:
        raise ValueError("invalid index accessor bounds or triangle count")
    indices = struct.unpack_from("<" + "H" * icount, binary, istart)
    if indices and max(indices) >= len(positions):
        raise ValueError("index references vertex outside POSITION accessor")

    vertex_joint = [None] * len(positions)
    material_index = primitive.get("material", -1)
    for faces in connected_face_components(positions, indices):
        component_vertices = sorted({indices[face * 3 + corner] for face in faces for corner in range(3)})
        center = tuple(sum(positions[index][axis] for index in component_vertices) / len(component_vertices) for axis in range(3))
        joint = component_bone(center, material_index)
        for vertex in component_vertices:
            previous = vertex_joint[vertex]
            if previous is not None and previous != joint:
                raise ValueError("source vertex is shared by components that resolve to different joints")
            vertex_joint[vertex] = joint
    if any(value is None for value in vertex_joint):
        raise ValueError("source player contains unreferenced vertices; rig assignment is ambiguous")

    joint_values = []
    weight_values = []
    for joint in vertex_joint:
        joint_values.extend((int(joint), 0, 0, 0))
        weight_values.extend((1.0, 0.0, 0.0, 0.0))
    joint_payload = struct.pack("<" + "H" * len(joint_values), *joint_values)
    joint_view = append_bytes(document, binary, joint_payload, ARRAY_BUFFER)
    joint_accessor = len(document.setdefault("accessors", []))
    document["accessors"].append({
        "bufferView": joint_view, "componentType": UNSIGNED_SHORT,
        "count": len(positions), "type": "VEC4",
        "min": [min(vertex_joint), 0, 0, 0],
        "max": [max(vertex_joint), 0, 0, 0],
    })
    weight_accessor = append_float_accessor(document, binary, weight_values, "VEC4", ARRAY_BUFFER)
    attrs["JOINTS_0"] = joint_accessor
    attrs["WEIGHTS_0"] = weight_accessor


def matrix_inverse_translation(pivot):
    x, y, z = pivot
    # glTF MAT4 accessor values use column-major order.
    return (1.0,0.0,0.0,0.0, 0.0,1.0,0.0,0.0, 0.0,0.0,1.0,0.0, -x,-y,-z,1.0)


def quaternion(axis, angle):
    norm = math.sqrt(sum(v * v for v in axis))
    if norm == 0:
        raise ValueError("rotation axis must be non-zero")
    x, y, z = (v / norm for v in axis)
    s = math.sin(angle / 2.0)
    return [x * s, y * s, z * s, math.cos(angle / 2.0)]


def add_animation(document, binary, name, times, channel_specs, joint_node_map):
    samplers, channels = [], []
    for bone_name, path, axis, angles in channel_specs:
        if bone_name not in joint_node_map:
            raise ValueError(f"unknown animation bone: {bone_name}")
        input_values = [float(t) for t in times]
        input_accessor = append_float_accessor(document, binary, input_values, "SCALAR", include_bounds=True)
        if path == "rotation":
            output_values = [v for angle in angles for v in quaternion(axis, angle)]
            output_kind = "VEC4"
        elif path == "translation":
            output_values = [float(v) for sample in angles for v in sample]
            output_kind = "VEC3"
        else:
            raise ValueError(f"unsupported animation target path: {path}")
        if len(angles) != len(times):
            raise ValueError(f"channel key count does not match times in {name}/{bone_name}")
        output_accessor = append_float_accessor(document, binary, output_values, output_kind)
        sampler_index = len(samplers)
        samplers.append({"input": input_accessor, "output": output_accessor, "interpolation": "LINEAR"})
        channels.append({"sampler": sampler_index, "target": {"node": joint_node_map[bone_name], "path": path}})
    document.setdefault("animations", []).append({"name": name, "samplers": samplers, "channels": channels})


def add_animations(document, binary, joint_node_map, pivots):
    R = lambda bone, axis, angles: (bone, "rotation", axis, angles)
    T = lambda bone, values: (bone, "translation", None, values)
    add_animation(document, binary, "Idle_01", [0, 1, 2], [
        R("Spine", [1,0,0], [0, -0.012, 0]),
        R("Chest", [1,0,0], [0, 0.018, 0]),
        R("Cape", [1,0,0], [0, 0.025, 0]),
        R("UpperArm_L", [0,0,1], [0, -0.02, 0]),
        R("UpperArm_R", [0,0,1], [0, 0.02, 0]),
    ], joint_node_map)
    add_animation(document, binary, "Walking", [0, .25, .5, .75, 1.0], [
        R("UpperLeg_L", [1,0,0], [0, .42, 0, -.42, 0]),
        R("UpperLeg_R", [1,0,0], [0, -.42, 0, .42, 0]),
        R("LowerLeg_L", [1,0,0], [0, .16, 0, -.16, 0]),
        R("LowerLeg_R", [1,0,0], [0, -.16, 0, .16, 0]),
        R("Foot_L", [1,0,0], [0, -.08, 0, .08, 0]),
        R("Foot_R", [1,0,0], [0, .08, 0, -.08, 0]),
        R("UpperArm_L", [1,0,0], [0, -.25, 0, .25, 0]),
        R("UpperArm_R", [1,0,0], [0, .25, 0, -.25, 0]),
        R("Cape", [1,0,0], [0, .045, 0, -.03, 0]),
    ], joint_node_map)
    add_animation(document, binary, "Running", [0, .175, .35, .525, .7], [
        R("UpperLeg_L", [1,0,0], [0, .68, 0, -.68, 0]),
        R("UpperLeg_R", [1,0,0], [0, -.68, 0, .68, 0]),
        R("LowerLeg_L", [1,0,0], [0, .27, 0, -.27, 0]),
        R("LowerLeg_R", [1,0,0], [0, -.27, 0, .27, 0]),
        R("Foot_L", [1,0,0], [0, -.15, 0, .15, 0]),
        R("Foot_R", [1,0,0], [0, .15, 0, -.15, 0]),
        R("UpperArm_L", [1,0,0], [0, -.43, 0, .43, 0]),
        R("UpperArm_R", [1,0,0], [0, .43, 0, -.43, 0]),
        R("Cape", [1,0,0], [0, .08, 0, -.05, 0]),
    ], joint_node_map)
    add_animation(document, binary, "Jump", [0, .18, .4, .62, .8], [
        R("UpperLeg_L", [1,0,0], [0, .28, .12, -.05, 0]),
        R("UpperLeg_R", [1,0,0], [0, -.22, -.12, .05, 0]),
        R("LowerLeg_L", [1,0,0], [0, -.12, -.18, -.05, 0]),
        R("LowerLeg_R", [1,0,0], [0, -.12, .18, .05, 0]),
        R("Foot_L", [1,0,0], [0, -.08, .10, .02, 0]),
        R("Foot_R", [1,0,0], [0, -.08, -.10, -.02, 0]),
        R("UpperArm_L", [1,0,0], [0, -.38, -.6, -.2, 0]),
        R("UpperArm_R", [1,0,0], [0, -.38, -.6, -.2, 0]),
        R("Cape", [1,0,0], [0, .12, .28, .15, 0]),
    ], joint_node_map)
    add_animation(document, binary, "HeavyAttack", [0, .15, .30, .48, .68], [
        R("UpperArm_R", [1,0,0], [0, -.38, 1.2, .65, 0]),
        R("LowerArm_R", [1,0,0], [0, -.12, -.72, .28, 0]),
        R("Hand_R", [0,0,1], [0, -.20, -1.00, .40, 0]),
        R("Chest", [0,1,0], [0, -.16, -.35, .1, 0]),
        R("Cape", [1,0,0], [0, .06, .2, -.1, 0]),
    ], joint_node_map)
    add_animation(document, binary, "Hit", [0, .08, .20, .34], [
        R("Chest", [1,0,0], [0, -.12, .06, 0]),
        R("UpperArm_L", [0,0,1], [0, -.18, .08, 0]),
        R("UpperArm_R", [0,0,1], [0, .18, -.08, 0]),
    ], joint_node_map)
    add_animation(document, binary, "Death", [0, .2, .55, .9, 1.2], [
        R("Spine", [1,0,0], [0, -.12, -.48, -.72, -.78]),
        R("Chest", [1,0,0], [0, -.08, -.35, -.55, -.6]),
        R("UpperLeg_L", [1,0,0], [0, .08, -.22, -.35, -.38]),
        R("UpperLeg_R", [1,0,0], [0, -.08, .18, .3, .33]),
        R("UpperArm_L", [1,0,0], [0, -.2, -.4, -.2, -.16]),
        R("UpperArm_R", [1,0,0], [0, .16, .3, .2, .15]),
        R("Cape", [1,0,0], [0, .1, .3, .22, .15]),
    ], joint_node_map)


def build_glb(document, binary):
    document.setdefault("buffers", [{}])
    document["buffers"][0]["byteLength"] = len(binary)
    json_bytes = json.dumps(document, separators=(",", ":"), ensure_ascii=True).encode("ascii")
    json_bytes += b" " * ((-len(json_bytes)) % 4)
    binary_chunk = bytes(binary) + b"\x00" * ((-len(binary)) % 4)
    total = 12 + 8 + len(json_bytes) + 8 + len(binary_chunk)
    return (
        struct.pack("<4sII", b"glTF", 2, total)
        + struct.pack("<II", len(json_bytes), JSON_CHUNK) + json_bytes
        + struct.pack("<II", len(binary_chunk), BIN_CHUNK) + binary_chunk
    )


def transform(source: bytes) -> bytes:
    document, binary = parse_glb(source)
    if document.get("skins") or document.get("animations"):
        raise ValueError("refusing to rig a source that already contains a skin or animation")
    nodes = document.get("nodes", [])
    meshes = document.get("meshes", [])
    if len(nodes) != 1 or len(meshes) != 1 or nodes[0].get("mesh") != 0:
        raise ValueError("source layout changed; expected the documented single-root player GLB")
    primitives = meshes[0].get("primitives", [])
    if len(primitives) < 7:
        raise ValueError("source player no longer has the expected multi-material primitives")
    for primitive in primitives:
        add_skin_attributes(document, binary, primitive)

    armature_index = len(nodes)
    joint_node_map = {}
    joint_indices = []
    joint_nodes = []
    for name, pivot in BONES:
        node_index = len(nodes)
        nodes.append({"name": name, "translation": list(pivot)})
        joint_node_map[name] = node_index
        joint_indices.append(node_index)
        joint_nodes.append(matrix_inverse_translation(pivot))
    nodes.insert(armature_index, {
        "name": "Armature",
        "children": [idx + 1 for idx in joint_indices],
    })
    # Inserting the Armature shifts every joint node index by one.
    joint_node_map = {name: idx + 1 for name, idx in joint_node_map.items()}
    joint_indices = [idx + 1 for idx in joint_indices]

    inverse_bind_accessor = append_float_accessor(
        document, binary, [v for matrix in joint_nodes for v in matrix], "MAT4"
    )
    document.setdefault("skins", []).append({
        "name": "AshenKingdoms_Humanoid_Prototype",
        "inverseBindMatrices": inverse_bind_accessor,
        "skeleton": armature_index,
        "joints": joint_indices,
    })
    document["nodes"][0]["skin"] = 0
    scenes = document.get("scenes", [])
    if not scenes:
        raise ValueError("source GLB has no scene")
    roots = scenes[document.get("scene", 0)].setdefault("nodes", [0])
    if armature_index not in roots:
        roots.append(armature_index)
    document["asset"]["generator"] = "AshenKingdoms Rigged Player Candidate Generator"
    add_animations(document, binary, joint_node_map, dict(BONES))
    # Run cheap schema checks before writing.
    for primitive in primitives:
        attrs = primitive["attributes"]
        for key in ("POSITION", "NORMAL", "JOINTS_0", "WEIGHTS_0"):
            if key not in attrs:
                raise ValueError(f"rigged primitive lacks {key}")
        if document["accessors"][attrs["JOINTS_0"]]["count"] != document["accessors"][attrs["POSITION"]]["count"]:
            raise ValueError("joint count does not match position count")
        if document["accessors"][attrs["WEIGHTS_0"]]["count"] != document["accessors"][attrs["POSITION"]]["count"]:
            raise ValueError("weight count does not match position count")
    return build_glb(document, binary)


def main():
    parser = argparse.ArgumentParser(description="Create a deterministic rigged/animated player candidate GLB.")
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    try:
        source = args.source.read_bytes()
        result = transform(source)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_bytes(result)
        print(json.dumps({
            "output": str(args.output),
            "bytes": len(result),
            "sha256": hashlib.sha256(result).hexdigest(),
            "bone_count": len(BONES),
            "animations": ["Idle_01", "Walking", "Running", "Jump", "HeavyAttack", "Hit", "Death"],
            "note": "prototype weights are spatially assigned and require visual inspection before production use",
        }, ensure_ascii=False))
    except (OSError, ValueError, KeyError, IndexError, TypeError, struct.error, json.JSONDecodeError) as exc:
        parser.exit(2, f"ERROR: {exc}\n")


if __name__ == "__main__":
    main()
