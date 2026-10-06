"""Take the embedded textures out of .glb files and point them at the PNGs beside the model.

    python tools/strip_glb_textures.py models/vehicles/*/*.glb        # strip in place
    python tools/strip_glb_textures.py --check models/vehicles/*/*.glb

Godot's importer already extracts every embedded image next to the model as
<model>_<image name>.png (embedded_image_handling = Extract), so a .glb carrying them too
holds every texture twice: the largest were over GitHub's 100 MB file limit. This rewrites each
image as an external `uri` to that same PNG - Godot and the Maya car builder both read it
from there - and repacks the binary without the image data. Geometry, materials and node
tree are byte-for-byte what they were.

An image whose PNG isn't there (or differs from the embedded bytes) is written out first, so
nothing is ever lost. Images that are already external are left alone. No dependencies.
"""
from __future__ import annotations

import json
import os
import struct
import sys
from urllib.parse import quote

MAGIC, JSON_CHUNK, BIN_CHUNK = 0x46546C67, 0x4E4F534A, 0x004E4942
EXT = {"image/png": ".png", "image/jpeg": ".jpg"}


def read_glb(path):
    with open(path, "rb") as fh:
        data = fh.read()
    magic, version, _ = struct.unpack_from("<III", data, 0)
    if magic != MAGIC or version != 2:
        raise ValueError("not a glTF 2.0 binary: %s" % path)
    off, js, bn = 12, None, b""
    while off < len(data):
        n, kind = struct.unpack_from("<II", data, off)
        chunk = data[off + 8: off + 8 + n]
        if kind == JSON_CHUNK:
            js = json.loads(chunk.decode("utf-8"))
        elif kind == BIN_CHUNK:
            bn = chunk
        off += 8 + n
    return js, bn


def write_glb(path, js, bn):
    j = json.dumps(js, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    j += b" " * (-len(j) % 4)
    bn += b"\x00" * (-len(bn) % 4)
    total = 12 + 8 + len(j) + (8 + len(bn) if bn else 0)
    tmp = path + ".tmp"
    with open(tmp, "wb") as fh:
        fh.write(struct.pack("<III", MAGIC, 2, total))
        fh.write(struct.pack("<II", len(j), JSON_CHUNK) + j)
        if bn:
            fh.write(struct.pack("<II", len(bn), BIN_CHUNK) + bn)
    os.replace(tmp, path)


def texture_file(glb_path, image, index):
    """Where Godot extracts this image: <model>_<name without extension><ext>."""
    stem = os.path.splitext(os.path.basename(glb_path))[0]
    name = os.path.splitext(image.get("name") or "image%d" % index)[0]
    return "%s_%s%s" % (stem, name, EXT.get(image.get("mimeType"), ".png"))


def strip(glb_path, check=False):
    js, bn = read_glb(glb_path)
    views = js.get("bufferViews", [])
    images = js.get("images", [])
    embedded = [i for i, im in enumerate(images) if "bufferView" in im]
    if not embedded:
        return "%s: no embedded images" % os.path.basename(glb_path)
    folder = os.path.dirname(os.path.abspath(glb_path))
    image_views = {images[i]["bufferView"] for i in embedded}
    # a view shared with geometry would be dropped with the image - never seen, but refuse
    used_elsewhere = set()
    for a in js.get("accessors", []):
        if "bufferView" in a:
            used_elsewhere.add(a["bufferView"])
        sp = a.get("sparse")
        if sp:
            used_elsewhere.update((sp["indices"]["bufferView"], sp["values"]["bufferView"]))
    if image_views & used_elsewhere:
        raise ValueError("%s: an image shares a buffer view with geometry" % glb_path)
    written = 0
    for i in embedded:
        im = images[i]
        bv = views[im["bufferView"]]
        data = bn[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]]
        name = texture_file(glb_path, im, i)
        path = os.path.join(folder, name)
        same = os.path.isfile(path) and open(path, "rb").read() == data
        if not same and not check:
            with open(path, "wb") as fh:
                fh.write(data)
            written += 1
        im["uri"] = quote(name)
        del im["bufferView"]
        im.pop("mimeType", None)
    saved = sum(views[k]["byteLength"] for k in image_views)
    if check:
        return "%s: %d embedded images, %.1f MB -> %.1f MB" % (
            os.path.basename(glb_path), len(embedded), os.path.getsize(glb_path) / 1048576.0,
            (os.path.getsize(glb_path) - saved) / 1048576.0)
    # repack the binary with only the views that remain, in their original order
    remap, new_views, out = {}, [], bytearray()
    for k, v in enumerate(views):
        if k in image_views:
            continue
        start = v.get("byteOffset", 0)
        chunk = bn[start: start + v["byteLength"]]
        out += b"\x00" * (-len(out) % 4)
        nv = dict(v)
        nv["byteOffset"] = len(out)
        out += chunk
        remap[k] = len(new_views)
        new_views.append(nv)
    for a in js.get("accessors", []):
        if "bufferView" in a:
            a["bufferView"] = remap[a["bufferView"]]
        sp = a.get("sparse")
        if sp:
            sp["indices"]["bufferView"] = remap[sp["indices"]["bufferView"]]
            sp["values"]["bufferView"] = remap[sp["values"]["bufferView"]]
    js["bufferViews"] = new_views
    js["buffers"] = [{"byteLength": len(out)}] if out else []
    before = os.path.getsize(glb_path)
    write_glb(glb_path, js, bytes(out))
    return "%s: %d images now external (%d written), %.1f MB -> %.1f MB" % (
        os.path.basename(glb_path), len(embedded), written, before / 1048576.0,
        os.path.getsize(glb_path) / 1048576.0)


def main(argv):
    check = "--check" in argv
    paths = [a for a in argv if not a.startswith("--")]
    if not paths:
        print(__doc__)
        return 1
    for p in paths:
        print(strip(p, check))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
