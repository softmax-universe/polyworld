#!/usr/bin/env python3
"""Build a leafy, head-fitted Elemental wreath on the Zeus head rig.

The Zeus GLB supplies the skin, gold materials and independently selectable
headgear nodes. Replace its tiara and vertically stretched blades with two
curved sprigs and overlapping, faceted leaves, all weighted to the Head joint.
Coordinates are in the source GLB's Y-up bind space.
"""
import json
import math
import struct
from pathlib import Path

ART = Path(__file__).resolve().parents[3] / "polyworld_art/characters/chargen"
source = ART / "hats/gota_zeus_headgear.glb"
target = ART / "hats/lvd_elemental_laurel.glb"
raw = source.read_bytes()
magic, version, total = struct.unpack_from("<4sII", raw)
assert magic == b"glTF" and version == 2 and total == len(raw)
jlen, jtype = struct.unpack_from("<I4s", raw, 12)
assert jtype == b"JSON"
doc = json.loads(raw[20:20+jlen])
pos = 20 + jlen
blen, btype = struct.unpack_from("<I4s", raw, pos)
assert btype == b"BIN\0" and pos + 8 + blen == len(raw)
data = bytearray(raw[pos+8:])
head = doc["skins"][0]["joints"].index(next(i for i, node in enumerate(doc["nodes"]) if node.get("name") == "Head"))
assert head < 256
old_prefix, new_prefix = "Gota_zeus_", "Lvd_elemental_"


def vector_view(values, fmt, kind, component, target_hint=None):
    """Append a tightly packed glTF accessor, keeping each view aligned."""
    data.extend(b"\0" * (-len(data) % 4))
    offset = len(data)
    for value in values:
        data.extend(struct.pack(fmt, *value))
    view = {"buffer": 0, "byteOffset": offset, "byteLength": len(data) - offset}
    if target_hint:
        view["target"] = target_hint
    doc["bufferViews"].append(view)
    accessor = {"bufferView": len(doc["bufferViews"]) - 1, "componentType": component,
                "count": len(values), "type": kind}
    if kind == "VEC3" and component == 5126:
        accessor["min"] = [min(v[i] for v in values) for i in range(3)]
        accessor["max"] = [max(v[i] for v in values) for i in range(3)]
    doc["accessors"].append(accessor)
    return len(doc["accessors"]) - 1


def mesh_data(vertices, normals, triangles):
    assert len(vertices) == len(normals)
    attrs = {
        "POSITION": vector_view(vertices, "<3f", "VEC3", 5126, 34962),
        "NORMAL": vector_view(normals, "<3f", "VEC3", 5126, 34962),
        "JOINTS_0": vector_view([(head, 0, 0, 0)] * len(vertices), "<4B", "VEC4", 5121, 34962),
        "WEIGHTS_0": vector_view([(1, 0, 0, 0)] * len(vertices), "<4f", "VEC4", 5126, 34962),
    }
    indices = vector_view([(i,) for tri in triangles for i in tri], "<H", "SCALAR", 5123, 34963)
    return attrs, indices


def ring_point(theta, y, radius):
    return (radius * math.sin(theta), y, -0.015 + radius * math.cos(theta))


def sprig(sign):
    # Fine stem follows the side of the head, rather than floating above it.
    vertices, normals, faces = [], [], []
    segments, sides = 32, 6
    for i in range(segments + 1):
        theta = sign * (0.08 + 3.00 * i / segments)
        p = ring_point(theta, 2.735, 0.525)
        radial = (math.sin(theta), 0, math.cos(theta))
        for j in range(sides):
            a = math.tau * j / sides
            n = (radial[0] * math.cos(a), math.sin(a), radial[2] * math.cos(a))
            vertices.append(tuple(p[k] + 0.016 * n[k] for k in range(3)))
            normals.append(n)
    for i in range(segments):
        for j in range(sides):
            a, b = i*sides+j, i*sides+(j+1)%sides
            faces.extend([(a, b, b+sides), (a, b+sides, a+sides)])
    return vertices, normals, faces


def leaves(sign, pair):
    """Two pointed, curved lenticular blades growing along each sprig."""
    vertices, normals, faces = [], [], []
    for sub in range(2):
        index = pair * 2 + sub
        start = 0.40 + index * 0.38
        # Leaves sweep toward the meeting point at the forehead, not straight up.
        # Width is perpendicular to the sloping midrib in the tangent/Y plane.
        advance, rise = 0.43, 0.20
        width = 0.080
        mid_radius = 0.56
        axis_t = mid_radius * advance
        axis_len = math.hypot(axis_t, rise)
        perpendicular_t, perpendicular_y = rise / axis_len, axis_t / axis_len
        base = len(vertices)
        stations = [(0.0, 0.0), (0.22, 0.72), (0.50, 1.0), (0.76, 0.76), (1.0, 0.0)]
        for t, profile in stations:
            theta = sign * (start - advance * t)
            radial = (math.sin(theta), 0, math.cos(theta))
            tangent = (sign * math.cos(theta), 0, -sign * math.sin(theta))
            center = ring_point(theta, 2.735 + rise*t, mid_radius + 0.016*math.sin(math.pi*t))
            for side in (-1, 0, 1):
                w = side * width * profile
                ridge = 0.025 * profile * (1 - abs(side))
                p = (center[0] + tangent[0]*perpendicular_t*w + radial[0]*ridge,
                     center[1] + perpendicular_y*w,
                     center[2] + tangent[2]*perpendicular_t*w + radial[2]*ridge)
                vertices.append(p)
                # Subtle normals on the central fold bring out the leaf facets.
                n = (radial[0] + side*0.28*tangent[0], side*0.12, radial[2] + side*0.28*tangent[2])
                length = math.sqrt(sum(x*x for x in n))
                normals.append(tuple(x/length for x in n))
        for row in range(len(stations)-1):
            for col in range(2):
                a = base + row*3 + col
                faces.extend([(a, a+3, a+4), (a, a+4, a+1)])
    return vertices, normals, faces


for mesh in doc["meshes"]:
    name = mesh["name"]
    assert name.startswith(old_prefix)
    mesh["name"] = name.replace(old_prefix, new_prefix, 1)
    suffix = name[len(old_prefix):]
    if suffix.startswith("laurel_stem_"):
        geometry = sprig(int(suffix.rsplit("_", 1)[1]))
    elif suffix.startswith("laurel_") and suffix != "laurel_band":
        _, sign, pair = suffix.split("_")
        geometry = leaves(int(sign), int(pair))
    else:
        continue
    assert len(mesh["primitives"]) == 1
    attrs, indices = mesh_data(*geometry)
    mesh["primitives"][0]["attributes"] = attrs
    mesh["primitives"][0]["indices"] = indices
for node in doc["nodes"]:
    if node.get("name", "").startswith(old_prefix):
        node["name"] = node["name"].replace(old_prefix, new_prefix, 1)
# Leave the original band and gemstone dormant: the leafy branches are the crown.
doc["buffers"][0]["byteLength"] = len(data)
data.extend(b"\0" * (-len(data) % 4))
encoded = json.dumps(doc, separators=(",", ":")).encode()
encoded += b" " * (-len(encoded) % 4)
target.write_bytes(struct.pack("<4sII", magic, version, 12 + 8 + len(encoded) + 8 + len(data)) +
                   struct.pack("<I4s", len(encoded), b"JSON") + encoded +
                   struct.pack("<I4s", len(data), b"BIN\0") + data)
sidecar = json.loads((ART / "hats/gota_zeus_headgear.json").read_text())
sidecar["id"] = "hats/lvd_elemental_laurel"
sidecar["name"] = "Elemental grand laurel crown"
sidecar["files"] = ["hats/lvd_elemental_laurel.glb"]
sidecar["nodes"] = [n.replace(old_prefix, new_prefix, 1) for n in sidecar["nodes"]
                    if "laurel_band" not in n and "gem" not in n]
(ART / "hats/lvd_elemental_laurel.json").write_text(json.dumps(sidecar, indent=2) + "\n")
print("Built", target)
