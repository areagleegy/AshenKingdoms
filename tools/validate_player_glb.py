#!/usr/bin/env python3
"""Validate GLB 2.0 structure, embedded buffers, triangle indices and expected player dimensions."""
from __future__ import annotations
import argparse, hashlib, json, struct, sys
from pathlib import Path

def fail(message: str) -> int:
    print(f"ERROR: {message}", file=sys.stderr)
    return 1

def validate(path: Path) -> int:
    try:
        data=path.read_bytes()
    except OSError as exc:
        return fail(f"cannot read {path}: {exc}")
    if len(data)<28:
        return fail("GLB is too small to hold a header and two chunks")
    magic,version,total=struct.unpack_from("<4sII",data,0)
    if magic!=b"glTF" or version!=2 or total!=len(data):
        return fail("invalid GLB magic/version/total-length")
    jlen,jtype=struct.unpack_from("<II",data,12)
    if jtype!=0x4E4F534A or 20+jlen>len(data):
        return fail("invalid JSON chunk")
    try:
        doc=json.loads(data[20:20+jlen].decode("utf-8").rstrip(" \0"))
    except (UnicodeDecodeError,json.JSONDecodeError) as exc:
        return fail(f"invalid GLB JSON: {exc}")
    bpos=20+jlen
    if bpos+8>len(data):
        return fail("missing BIN chunk")
    blen,btype=struct.unpack_from("<II",data,bpos)
    if btype!=0x004E4942 or bpos+8+blen!=len(data):
        return fail("invalid BIN chunk type or size")
    binary=data[bpos+8:bpos+8+blen]
    buffers=doc.get("buffers",[])
    if not buffers or not isinstance(buffers[0].get("byteLength"),int) or buffers[0]["byteLength"]>len(binary):
        return fail("embedded buffer byteLength is invalid")
    if any("uri" in item for item in buffers):
        return fail("player model should be self-contained; external buffer URI found")
    meshes=doc.get("meshes",[]); nodes=doc.get("nodes",[]); views=doc.get("bufferViews",[]); accessors=doc.get("accessors",[])
    if not nodes or not meshes or not any(isinstance(node.get("mesh"),int) for node in nodes):
        return fail("scene has no node referencing a mesh")
    points=[]; triangles=0; primitive_count=0
    for mesh in meshes:
        for prim in mesh.get("primitives",[]):
            primitive_count+=1; attrs=prim.get("attributes",{})
            if "POSITION" not in attrs or "NORMAL" not in attrs or "indices" not in prim:
                return fail("primitive must declare POSITION, NORMAL and indices")
            try:
                pa,na,ia=(accessors[idx] for idx in (attrs["POSITION"],attrs["NORMAL"],prim["indices"]))
                if pa.get("type")!="VEC3" or na.get("type")!="VEC3" or ia.get("type")!="SCALAR":
                    return fail("accessor types are inconsistent")
                if pa.get("componentType")!=5126 or na.get("componentType")!=5126 or ia.get("componentType")!=5123:
                    return fail("expected float position/normal and unsigned-short indices")
                if pa.get("count")!=na.get("count") or ia.get("count",0)%3:
                    return fail("position/normal count mismatch or non-triangular index count")
                pview=views[pa["bufferView"]]; start=pview.get("byteOffset",0)+pa.get("byteOffset",0); length=pa["count"]*12
                if start<0 or start+length>len(binary): return fail("position accessor exceeds BIN data")
                for offset in range(start,start+length,12):
                    points.append(struct.unpack_from("<fff",binary,offset))
                iview=views[ia["bufferView"]]; istart=iview.get("byteOffset",0)+ia.get("byteOffset",0); ilen=ia["count"]*2
                if istart<0 or istart+ilen>len(binary): return fail("index accessor exceeds BIN data")
                indices=struct.unpack_from("<"+"H"*ia["count"],binary,istart)
                if indices and max(indices)>=pa["count"]: return fail("index references a vertex outside its primitive")
                triangles+=len(indices)//3
            except (KeyError,IndexError,struct.error,TypeError) as exc:
                return fail(f"malformed mesh accessor: {exc}")
    if primitive_count<7 or not points:
        return fail(f"expected a multi-material player mesh, got {primitive_count} primitive(s)")
    xs=[p[0] for p in points]; ys=[p[1] for p in points]; zs=[p[2] for p in points]
    bounds={"min":[round(min(xs),4),round(min(ys),4),round(min(zs),4)],"max":[round(max(xs),4),round(max(ys),4),round(max(zs),4)]}
    width=max(xs)-min(xs); height=max(ys)-min(ys); depth=max(zs)-min(zs)
    if min(ys)<-.005 or not 1.70<height<2.05:
        return fail(f"player origin/height outside expected range: {bounds}")
    if not .75<width<1.5 or not .25<depth<1.1:
        return fail(f"player width/depth outside expected range: {bounds}")
    report={"path":str(path),"bytes":len(data),"sha256":hashlib.sha256(data).hexdigest(),"format":"GLB 2.0",
            "material_count":len(doc.get("materials",[])),"primitive_count":primitive_count,"triangle_count":triangles,
            "bounds_m":bounds,"height_m":round(height,3)}
    print(json.dumps(report,ensure_ascii=False,indent=2))
    print("Player GLB validation passed.")
    return 0

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("path",type=Path,nargs="?",default=Path("assets/characters/player/player.glb"))
    args=parser.parse_args()
    return validate(args.path)

if __name__=="__main__":
    raise SystemExit(main())
