#!/usr/bin/env python3
"""Create a dark spectral Ash Wraith variant from the original in-repository player GLB."""
from __future__ import annotations
import argparse, hashlib, json, struct
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/"assets"/"characters"/"player"/"player.glb"
DEFAULT_OUTPUT=ROOT/"assets"/"characters"/"enemies"/"ash_wraith.glb"
MATERIALS=[
    ("Void silk",(.012,.018,.035,1),.02,.98),("Spectral hide",(.035,.055,.085,1),.01,.95),
    ("Blackened bone",(.055,.075,.105,1),.72,.65),("Aether runes",(.02,.36,.40,1),.5,.42),
    ("Ashen mask",(.12,.19,.22,1),0,.9),("Cinder eyes",(1,.11,.018,1),.12,.3),
    ("Void underlayer",(.025,.035,.055,1),.01,.98),("Wraith shroud",(.018,.045,.085,1),.01,.98),
]

def transform(source: bytes) -> bytes:
    if len(source)<28:
        raise ValueError("source GLB is too small")
    magic,version,total=struct.unpack_from("<4sII",source,0)
    if magic!=b"glTF" or version!=2 or total!=len(source):
        raise ValueError("source is not a valid GLB 2.0 file")
    json_length,json_type=struct.unpack_from("<II",source,12)
    if json_type!=0x4E4F534A or 20+json_length>len(source):
        raise ValueError("source JSON chunk is invalid")
    document=json.loads(source[20:20+json_length].decode("utf-8").rstrip(" \0"))
    binary_offset=20+json_length
    binary_length,binary_type=struct.unpack_from("<II",source,binary_offset)
    if binary_type!=0x004E4942 or binary_offset+8+binary_length!=len(source):
        raise ValueError("source BIN chunk is invalid")
    if len(document.get("materials",[])) != len(MATERIALS):
        raise ValueError("player model material layout changed; update the wraith variant generator")
    for index,(name,color,metallic,roughness) in enumerate(MATERIALS):
        material=document["materials"][index]
        material["name"]=name
        material.setdefault("pbrMetallicRoughness",{})["baseColorFactor"]=list(color)
        material["pbrMetallicRoughness"]["metallicFactor"]=metallic
        material["pbrMetallicRoughness"]["roughnessFactor"]=roughness
        material["doubleSided"]=True
        if index==5:
            material["emissiveFactor"]=[.9,.055,.004]
    document["asset"]["generator"]="AshenKingdoms Procedural Ash Wraith Variant Generator"
    document["nodes"][0]["name"]="AshWraith"
    document["meshes"][0]["name"]="AshWraith_StaticMesh"
    json_chunk=json.dumps(document,separators=(",",":"),ensure_ascii=True).encode("ascii")
    json_chunk+=b" "*((-len(json_chunk))%4)
    bin_chunk=source[binary_offset:binary_offset+8+binary_length]
    full_length=12+8+len(json_chunk)+len(bin_chunk)
    return (struct.pack("<4sII",b"glTF",2,full_length)
            +struct.pack("<II",len(json_chunk),0x4E4F534A)+json_chunk+bin_chunk)

def main() -> int:
    parser=argparse.ArgumentParser(description="Create a spectral Ash Wraith GLB using project-owned geometry.")
    parser.add_argument("--source",type=Path,default=SOURCE)
    parser.add_argument("--output",type=Path,default=DEFAULT_OUTPUT)
    args=parser.parse_args()
    try:
        source=args.source.read_bytes()
        output=transform(source)
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_bytes(output)
        print(f"Wrote {args.output} ({len(output)} bytes; SHA-256 {hashlib.sha256(output).hexdigest()})")
        return 0
    except (OSError,ValueError,KeyError,IndexError,json.JSONDecodeError,struct.error) as exc:
        parser.exit(2,f"ERROR: {exc}\n")
if __name__=="__main__":
    raise SystemExit(main())
