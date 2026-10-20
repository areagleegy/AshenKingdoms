#!/usr/bin/env python3
"""Rebuild the original static low-poly AshenKingdoms player GLB without external assets."""
from __future__ import annotations
import argparse, json, math, struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "assets" / "characters" / "player" / "player.glb"
MATERIALS = [
    ("Ash cloth", (.06,.07,.09,1), .02,.96), ("Travel leather", (.22,.13,.07,1), .03,.93),
    ("Dark iron", (.18,.21,.25,1), .58,.62), ("Worn bronze", (.47,.30,.13,1), .62,.48),
    ("Skin", (.34,.22,.16,1), 0,.92), ("Eyes", (.015,.018,.025,1), .02,.5),
    ("Undercloth", (.12,.12,.13,1), .01,.98), ("Ash mantle", (.09,.11,.145,1), .01,.98),
]
GROUPS = [{"p": [], "n": [], "i": []} for _ in MATERIALS]
V = lambda x,y,z: (float(x),float(y),float(z))

def sub(a,b): return tuple(a[i]-b[i] for i in range(3))
def cross(a,b): return (a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])
def unit(a):
    n=math.sqrt(sum(x*x for x in a)) or 1.0
    return tuple(x/n for x in a)

def tri(m,a,b,c):
    normal=unit(cross(sub(b,a),sub(c,a))); g=GROUPS[m]; k=len(g["p"])//3
    for point in (a,b,c): g["p"].extend(point); g["n"].extend(normal)
    g["i"].extend((k,k+1,k+2))

def quad(m,a,b,c,d):
    tri(m,a,b,c); tri(m,a,c,d)

def box(m,c,s):
    x,y,z=c; w,h,d=s; x0,x1=x-w/2,x+w/2; y0,y1=y-h/2,y+h/2; z0,z1=z-d/2,z+d/2
    faces=[
        (V(x0,y0,z1),V(x1,y0,z1),V(x1,y1,z1),V(x0,y1,z1)),
        (V(x0,y0,z0),V(x0,y1,z0),V(x1,y1,z0),V(x1,y0,z0)),
        (V(x1,y0,z0),V(x1,y1,z0),V(x1,y1,z1),V(x1,y0,z1)),
        (V(x0,y0,z0),V(x0,y0,z1),V(x0,y1,z1),V(x0,y1,z0)),
        (V(x0,y1,z0),V(x0,y1,z1),V(x1,y1,z1),V(x1,y1,z0)),
        (V(x0,y0,z0),V(x1,y0,z0),V(x1,y0,z1),V(x0,y0,z1)),
    ]
    for f in faces: quad(m,*f)

def ellipsoid(m,c,r,segs=8,rings=5):
    rows=[]
    for j in range(rings+1):
        lat=-math.pi/2+math.pi*j/rings; row=[]
        for i in range(segs+1):
            lon=2*math.pi*i/segs
            row.append(V(c[0]+r[0]*math.cos(lat)*math.cos(lon),c[1]+r[1]*math.sin(lat),c[2]+r[2]*math.cos(lat)*math.sin(lon)))
        rows.append(row)
    for j in range(rings):
        for i in range(segs): quad(m,rows[j][i],rows[j+1][i],rows[j+1][i+1],rows[j][i+1])

def cylinder(m,a,b,r,segs=8):
    direction=unit(sub(b,a)); ref=V(0,1,0) if abs(direction[1])<.9 else V(1,0,0)
    u=unit(cross(direction,ref)); v=unit(cross(direction,u)); lo=[]; hi=[]
    for i in range(segs):
        t=2*math.pi*i/segs; off=tuple(r*(u[k]*math.cos(t)+v[k]*math.sin(t)) for k in range(3))
        lo.append(tuple(a[k]+off[k] for k in range(3))); hi.append(tuple(b[k]+off[k] for k in range(3)))
    for i in range(segs):
        j=(i+1)%segs; quad(m,lo[i],lo[j],hi[j],hi[i]); tri(m,a,lo[j],lo[i]); tri(m,b,hi[i],hi[j])

def build_geometry():
    box(1,V(-.14,.09,-.06),V(.23,.18,.34)); box(1,V(.14,.09,-.06),V(.23,.18,.34))
    cylinder(6,V(-.14,.15,0),V(-.13,.62,0),.078); cylinder(6,V(.14,.15,0),V(.13,.62,0),.078)
    box(2,V(-.13,.39,-.082),V(.14,.18,.05)); box(2,V(.13,.39,-.082),V(.14,.18,.05))
    box(1,V(0,.68,0),V(.37,.28,.28)); box(6,V(0,1.02,0),V(.44,.57,.28))
    box(2,V(0,1.08,-.157),V(.34,.38,.055)); box(3,V(0,1.08,-.19),V(.07,.30,.018))
    box(3,V(0,1.27,-.195),V(.30,.025,.014)); box(1,V(0,.80,0),V(.45,.09,.31))
    box(3,V(0,.80,-.17),V(.09,.07,.02))
    ellipsoid(2,V(-.285,1.29,0),V(.135,.14,.15)); ellipsoid(2,V(.285,1.29,0),V(.135,.14,.15))
    cylinder(1,V(-.30,1.27,0),V(-.415,1.14,-.005),.067); cylinder(1,V(-.415,1.14,-.005),V(-.485,1.005,-.02),.052)
    cylinder(1,V(.30,1.27,0),V(.415,1.14,-.005),.067); cylinder(1,V(.415,1.14,-.005),V(.485,1.005,-.02),.052)
    cylinder(2,V(-.443,1.105,-.012),V(-.475,1.045,-.018),.059); cylinder(2,V(.443,1.105,-.012),V(.475,1.045,-.018),.059)
    ellipsoid(1,V(-.49,.975,-.025),V(.058,.065,.052)); ellipsoid(1,V(.49,.975,-.025),V(.058,.065,.052))
    cylinder(4,V(0,1.34,0),V(0,1.45,0),.055); ellipsoid(0,V(0,1.57,.035),V(.16,.20,.15),8,6)
    ellipsoid(4,V(0,1.565,-.075),V(.105,.13,.08),8,6)
    ellipsoid(5,V(-.038,1.595,-.145),V(.012,.008,.006),6,4); ellipsoid(5,V(.038,1.595,-.145),V(.012,.008,.006),6,4)
    a,b,c,d=V(-.17,1.4,.13),V(.17,1.4,.13),V(.29,.30,.4),V(-.29,.30,.4)
    aa,bb,cc,dd=V(-.17,1.4,.2),V(.17,1.4,.2),V(.29,.30,.46),V(-.29,.30,.46)
    quad(7,a,b,c,d); quad(7,bb,aa,dd,cc); quad(7,aa,bb,b,a); quad(7,d,c,cc,dd); quad(7,a,d,dd,aa); quad(7,b,bb,cc,c)
    ellipsoid(3,V(0,1.345,-.18),V(.045,.045,.022),6,4)
    cylinder(1,V(.31,.48,.14),V(.43,.94,.13),.035); cylinder(3,V(.43,.93,.13),V(.49,1.08,.12),.024)
    box(3,V(.43,.94,.13),V(.13,.027,.045))
    ellipsoid(3,V(-.21,1.31,-.12),V(.024,.024,.018),6,4); ellipsoid(3,V(.21,1.31,-.12),V(.024,.024,.018),6,4)

def make_glb():
    build_geometry(); binary=bytearray(); views=[]; accessors=[]; primitives=[]
    def aligned(): 
        while len(binary)%4: binary.append(0)
    def append(data,target):
        aligned(); offset=len(binary); binary.extend(data)
        views.append({"buffer":0,"byteOffset":offset,"byteLength":len(data),"target":target})
        return len(views)-1
    for material,g in enumerate(GROUPS):
        if not g["i"]: continue
        if len(g["p"])//3>65535: raise ValueError("Too many vertices for 16-bit indices")
        pv=append(struct.pack("<"+"f"*len(g["p"]),*g["p"]),34962)
        nv=append(struct.pack("<"+"f"*len(g["n"]),*g["n"]),34962)
        iv=append(struct.pack("<"+"H"*len(g["i"]),*g["i"]),34963)
        points=list(zip(g["p"][0::3],g["p"][1::3],g["p"][2::3]))
        lo=[min(p[k] for p in points) for k in range(3)]; hi=[max(p[k] for p in points) for k in range(3)]
        pa=len(accessors); accessors.append({"bufferView":pv,"componentType":5126,"count":len(points),"type":"VEC3","min":lo,"max":hi})
        na=len(accessors); accessors.append({"bufferView":nv,"componentType":5126,"count":len(points),"type":"VEC3"})
        ia=len(accessors); accessors.append({"bufferView":iv,"componentType":5123,"count":len(g["i"]),"type":"SCALAR","min":[0],"max":[max(g["i"])]})
        primitives.append({"attributes":{"POSITION":pa,"NORMAL":na},"indices":ia,"material":material,"mode":4})
    materials=[{"name":name,"pbrMetallicRoughness":{"baseColorFactor":list(color),"metallicFactor":metal,"roughnessFactor":rough},"doubleSided":True} for name,color,metal,rough in MATERIALS]
    gltf={"asset":{"version":"2.0","generator":"AshenKingdoms Procedural Low-Poly Hero Generator"},
          "scene":0,"scenes":[{"name":"Ashen Kingdoms Player","nodes":[0]}],"nodes":[{"name":"AshenKingdoms_Player","mesh":0}],
          "meshes":[{"name":"AshenKnight_StaticMesh","primitives":primitives}],"materials":materials,
          "bufferViews":views,"accessors":accessors,"buffers":[{"byteLength":len(binary)}]}
    js=json.dumps(gltf,separators=(",",":"),ensure_ascii=True).encode("ascii")
    js+=b" "*((-len(js))%4); bin_chunk=bytes(binary)+b"\0"*((-len(binary))%4)
    total=12+8+len(js)+8+len(bin_chunk)
    return struct.pack("<4sII",b"glTF",2,total)+struct.pack("<II",len(js),0x4E4F534A)+js+struct.pack("<II",len(bin_chunk),0x004E4942)+bin_chunk

def main():
    parser=argparse.ArgumentParser(description="Rebuild the original static AshenKingdoms player GLB.")
    parser.add_argument("--output",type=Path,default=DEFAULT_OUTPUT)
    args=parser.parse_args(); args.output.parent.mkdir(parents=True,exist_ok=True)
    data=make_glb(); args.output.write_bytes(data)
    import hashlib
    print(f"Wrote {args.output} ({len(data)} bytes, SHA-256 {hashlib.sha256(data).hexdigest()})")

if __name__=="__main__": main()
