#!/usr/bin/env python3
"""Validate skinning and animation structure for an in-project GLB candidate."""
from __future__ import annotations
import argparse
import json
import math
import struct
import sys
from pathlib import Path

JSON_CHUNK = 0x4E4F534A
BIN_CHUNK = 0x004E4942
FLOAT = 5126
UNSIGNED_SHORT = 5123
WIDTH = {"SCALAR": 1, "VEC3": 3, "VEC4": 4, "MAT4": 16}
REQUIRED_ANIMATIONS = {"Idle_01", "Walking", "Running", "Jump", "HeavyAttack", "Hit", "Death"}


class InvalidGLB(ValueError):
    pass


def read_glb(path: Path):
    data = path.read_bytes()
    if len(data) < 28:
        raise InvalidGLB("GLB is too small")
    magic, version, total = struct.unpack_from("<4sII", data, 0)
    if magic != b"glTF" or version != 2 or total != len(data):
        raise InvalidGLB("invalid GLB magic, version, or total byte length")
    offset, document, binary = 12, None, None
    while offset + 8 <= len(data):
        size, kind = struct.unpack_from("<II", data, offset)
        offset += 8
        if size < 0 or offset + size > len(data):
            raise InvalidGLB("chunk exceeds file boundary")
        payload = data[offset:offset + size]
        offset += size
        if kind == JSON_CHUNK:
            document = json.loads(payload.decode("utf-8").rstrip(" \t\r\n\x00"))
        elif kind == BIN_CHUNK:
            binary = payload
    if offset != len(data) or document is None or binary is None:
        raise InvalidGLB("missing GLB chunk or invalid chunk alignment")
    buffers = document.get("buffers", [])
    if not buffers or not isinstance(buffers[0].get("byteLength"), int):
        raise InvalidGLB("missing embedded buffer byteLength")
    declared = buffers[0]["byteLength"]
    if declared < 0 or declared > len(binary):
        raise InvalidGLB("buffer byteLength exceeds BIN chunk")
    if any("uri" in buffer for buffer in buffers):
        raise InvalidGLB("external buffer URI is not permitted in this candidate")
    return document, binary[:declared], len(data)


def accessor_values(document, binary, accessor_index, expected_type=None, expected_component=None):
    accessors = document.get("accessors", [])
    views = document.get("bufferViews", [])
    if not 0 <= accessor_index < len(accessors):
        raise InvalidGLB("accessor index out of range")
    acc = accessors[accessor_index]
    kind = acc.get("type")
    component = acc.get("componentType")
    count = acc.get("count")
    if expected_type and kind != expected_type:
        raise InvalidGLB(f"accessor {accessor_index}: expected {expected_type}, got {kind}")
    if expected_component and component != expected_component:
        raise InvalidGLB(f"accessor {accessor_index}: unexpected componentType {component}")
    if kind not in WIDTH or not isinstance(count, int) or count < 0:
        raise InvalidGLB(f"accessor {accessor_index}: invalid type or count")
    if not 0 <= acc.get("bufferView", -1) < len(views):
        raise InvalidGLB(f"accessor {accessor_index}: bufferView out of range")
    view = views[acc["bufferView"]]
    width = WIDTH[kind]
    if component == FLOAT:
        scalar_size, fmt = 4, "f"
    elif component == UNSIGNED_SHORT:
        scalar_size, fmt = 2, "H"
    else:
        raise InvalidGLB(f"accessor {accessor_index}: unsupported component type")
    element_size = width * scalar_size
    stride = view.get("byteStride", element_size)
    if stride < element_size:
        raise InvalidGLB(f"accessor {accessor_index}: stride is smaller than element")
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    end = start if count == 0 else start + (count - 1) * stride + element_size
    if start < 0 or end > len(binary):
        raise InvalidGLB(f"accessor {accessor_index}: data exceeds binary bounds")
    rows = []
    for index in range(count):
        values = struct.unpack_from("<" + fmt * width, binary, start + index * stride)
        if component == FLOAT and not all(math.isfinite(v) for v in values):
            raise InvalidGLB(f"accessor {accessor_index}: non-finite floating-point value")
        rows.append(values)
    return rows, acc


def validate(path: Path):
    document, binary, size_bytes = read_glb(path)
    nodes = document.get("nodes", [])
    meshes = document.get("meshes", [])
    skins = document.get("skins", [])
    animations = document.get("animations", [])
    if len(skins) != 1:
        raise InvalidGLB(f"expected exactly one skin; got {len(skins)}")
    if not nodes or not meshes:
        raise InvalidGLB("missing nodes or meshes")
    skin = skins[0]
    joints = skin.get("joints", [])
    if len(joints) < 15 or len(set(joints)) != len(joints):
        raise InvalidGLB("skin needs at least 15 unique joint nodes")
    if any(not isinstance(j, int) or j < 0 or j >= len(nodes) for j in joints):
        raise InvalidGLB("skin contains invalid joint node index")
    skeleton = skin.get("skeleton")
    if not isinstance(skeleton, int) or skeleton < 0 or skeleton >= len(nodes):
        raise InvalidGLB("skin skeleton node is invalid")
    if nodes[skeleton].get("name") != "Armature":
        raise InvalidGLB("expected named Armature skeleton root")
    if not all(j in nodes[skeleton].get("children", []) for j in joints):
        raise InvalidGLB("all candidate joints must be children of Armature")
    inverse_bind_accessor = skin.get("inverseBindMatrices")
    if not isinstance(inverse_bind_accessor, int):
        raise InvalidGLB("skin lacks inverseBindMatrices")
    inverse_bind, ib_accessor = accessor_values(document, binary, inverse_bind_accessor, "MAT4", FLOAT)
    if len(inverse_bind) != len(joints) or ib_accessor.get("count") != len(joints):
        raise InvalidGLB("inverse bind matrix count differs from joints")

    primitive_count = 0
    vertex_count = 0
    weighted_vertices = 0
    for mesh in meshes:
        for primitive in mesh.get("primitives", []):
            primitive_count += 1
            attributes = primitive.get("attributes", {})
            for key in ("POSITION", "JOINTS_0", "WEIGHTS_0"):
                if key not in attributes:
                    raise InvalidGLB(f"primitive is missing {key}")
            positions, pa = accessor_values(document, binary, attributes["POSITION"], "VEC3", FLOAT)
            joint_rows, ja = accessor_values(document, binary, attributes["JOINTS_0"], "VEC4", UNSIGNED_SHORT)
            weight_rows, wa = accessor_values(document, binary, attributes["WEIGHTS_0"], "VEC4", FLOAT)
            if len(positions) != len(joint_rows) or len(positions) != len(weight_rows):
                raise InvalidGLB("position/joint/weight vertex counts differ")
            if ja.get("count") != pa.get("count") or wa.get("count") != pa.get("count"):
                raise InvalidGLB("position/joint/weight accessor counts differ")
            for row_index, (js, ws) in enumerate(zip(joint_rows, weight_rows)):
                if any(j >= len(joints) for j, w in zip(js, ws) if w > 0.0):
                    raise InvalidGLB(f"vertex {row_index} references joint outside skin")
                if any(w < -1e-6 for w in ws):
                    raise InvalidGLB(f"vertex {row_index} has negative joint weight")
                total = sum(ws)
                if abs(total - 1.0) > 1e-4:
                    raise InvalidGLB(f"vertex {row_index} weights sum to {total}, not 1")
                weighted_vertices += 1
            vertex_count += len(positions)
    if primitive_count < 7 or vertex_count == 0 or weighted_vertices != vertex_count:
        raise InvalidGLB("mesh/vertex counts do not satisfy candidate requirements")

    animation_names = {anim.get("name") for anim in animations}
    missing = sorted(REQUIRED_ANIMATIONS - animation_names)
    if missing:
        raise InvalidGLB("missing animation clips: " + ", ".join(missing))
    channel_count = 0
    for animation in animations:
        samplers = animation.get("samplers", [])
        channels = animation.get("channels", [])
        if not samplers or not channels:
            raise InvalidGLB(f"animation {animation.get('name')} has no samplers/channels")
        for channel in channels:
            channel_count += 1
            target = channel.get("target", {})
            if target.get("node") not in joints:
                raise InvalidGLB("animation channel targets a node outside the candidate skin")
            if target.get("path") not in {"rotation", "translation", "scale"}:
                raise InvalidGLB("animation channel has invalid target path")
            sampler_index = channel.get("sampler", -1)
            if not isinstance(sampler_index, int) or not 0 <= sampler_index < len(samplers):
                raise InvalidGLB("animation channel has invalid sampler index")
            sampler = samplers[sampler_index]
            times, ta = accessor_values(document, binary, sampler.get("input", -1), "SCALAR", FLOAT)
            if len(times) < 2 or any(times[i][0] >= times[i+1][0] for i in range(len(times)-1)):
                raise InvalidGLB("animation input key times must be strictly increasing")
            output_type = "VEC4" if target["path"] == "rotation" else "VEC3"
            values, oa = accessor_values(document, binary, sampler.get("output", -1), output_type, FLOAT)
            if len(values) != len(times) or oa.get("count") != ta.get("count"):
                raise InvalidGLB("animation input/output sample counts differ")
            if target["path"] == "rotation":
                for q in values:
                    norm = math.sqrt(sum(component * component for component in q))
                    if abs(norm - 1.0) > 1e-3:
                        raise InvalidGLB("animation contains non-normalized quaternion")
    report = {
        "path": str(path),
        "bytes": size_bytes,
        "bone_count": len(joints),
        "primitive_count": primitive_count,
        "skinned_vertex_count": vertex_count,
        "animation_count": len(animations),
        "animations": sorted(animation_names),
        "animation_channel_count": channel_count,
        "result": "PASS",
        "limitation": "spatially assigned first-pass weights; visual deformation review required",
    }
    return report


def main():
    parser = argparse.ArgumentParser(description="Validate rigged candidate GLB skin weights and animation clips.")
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    try:
        print(json.dumps(validate(args.path), ensure_ascii=False, indent=2))
        return 0
    except (OSError, ValueError, KeyError, IndexError, TypeError, struct.error, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
