#!/usr/bin/env python3
"""Build Gassi-Depot Mülleimer-Kacheln from an OSM extract (ADR 0006).

Usage:
    python3 pipeline/build_tiles.py <extract.osm.pbf> [<more.osm.pbf> ...] --out server/public

Needs the `osmium` command line tool (osmium-tool). Standard library only.

Tile scheme (version t1), also described in docs/spec-server.md:
  - Fixed root grid of ROOT_DEG x ROOT_DEG degrees:
        ri = floor((lat + 90) / ROOT_DEG), rj = floor((lon + 180) / ROOT_DEG)
  - Each root is a quadtree; a node is split into 4 children
    (0 = SW, 1 = SE, 2 = NW, 3 = NE) while it holds more than MAX_LEAF bins
    and is shallower than MAX_DEPTH.
  - t1/<ri>_<rj>/i.json   {"s": "<preorder>"}  '1' = split, '0' = leaf with
                          bins, '-' = empty leaf
  - t1/<ri>_<rj>/<path>.json  leaf data, path = child digits ("r" for the root):
        {"d": "<dog bins>", "g": "<general bins>"}
    Each bin is "<dlat>,<dlon>;" in units of 1e-5 degrees (~1 m) relative to
    the SW corner of the leaf.
  - t1/meta.json  {"v": 1, "date": "...", "bins": n, "roots": n, "leaves": n}
Roots without any bin get no files: the watch then falls back to Overpass.
"""
import argparse
import datetime
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile

ROOT_DEG = 0.4
MAX_LEAF = 400
MAX_DEPTH = 6
UNIT = 1e-5
VERSION = "t1"

FILTERS = [
    "n/amenity=waste_basket",
    "n/vending=excrement_bags",
    "n/waste=dog_excrement",
]


def is_dog(tags):
    waste = tags.get("waste", "")
    return "dog_excrement" in waste.split(";") or tags.get("vending") == "excrement_bags"


def read_bins(pbf):
    """Yield (lat, lon, dog) for every matching node of one extract."""
    with tempfile.TemporaryDirectory() as tmp:
        filtered = os.path.join(tmp, "bins.osm.pbf")
        subprocess.run(["osmium", "tags-filter", "-R", "--overwrite", pbf, *FILTERS, "-o", filtered],
                       check=True)
        proc = subprocess.Popen(["osmium", "export", "-f", "geojsonseq", "-u", "type_id", filtered],
                                stdout=subprocess.PIPE, text=True)
        for line in proc.stdout:
            line = line.strip().lstrip("\x1e")
            if not line:
                continue
            feature = json.loads(line)
            geometry = feature.get("geometry") or {}
            if geometry.get("type") != "Point":
                continue
            lon, lat = geometry["coordinates"][:2]
            yield lat, lon, is_dog(feature.get("properties") or {})
        if proc.wait() != 0:
            raise SystemExit("osmium export failed")


def root_of(lat, lon):
    return math.floor((lat + 90) / ROOT_DEG), math.floor((lon + 180) / ROOT_DEG)


def root_origin(ri, rj):
    return ri * ROOT_DEG - 90, rj * ROOT_DEG - 180


class Builder:
    def __init__(self, out_dir):
        self.out = out_dir
        self.leaves = 0
        self.max_bytes = 0

    def build_root(self, ri, rj, bins):
        lat0, lon0 = root_origin(ri, rj)
        folder = os.path.join(self.out, VERSION, "%d_%d" % (ri, rj))
        os.makedirs(folder, exist_ok=True)
        preorder = []
        self.node(folder, "", lat0, lon0, ROOT_DEG, bins, 0, preorder)
        with open(os.path.join(folder, "i.json"), "w") as f:
            json.dump({"s": "".join(preorder)}, f, separators=(",", ":"))

    def node(self, folder, path, lat0, lon0, size, bins, depth, preorder):
        if not bins:
            preorder.append("-")
            return
        if len(bins) > MAX_LEAF and depth < MAX_DEPTH:
            preorder.append("1")
            half = size / 2
            parts = [[], [], [], []]
            for b in bins:
                north = b[0] >= lat0 + half
                east = b[1] >= lon0 + half
                parts[(2 if north else 0) + (1 if east else 0)].append(b)
            corners = [(lat0, lon0), (lat0, lon0 + half), (lat0 + half, lon0), (lat0 + half, lon0 + half)]
            for k in range(4):
                self.node(folder, path + str(k), corners[k][0], corners[k][1], half, parts[k], depth + 1,
                          preorder)
            return
        preorder.append("0")
        self.write_leaf(folder, path or "r", lat0, lon0, size, bins)

    def write_leaf(self, folder, name, lat0, lon0, size, bins):
        top = int(round(size / UNIT))
        dog, gen = [], []
        for lat, lon, is_dog_bin in sorted(bins):
            dlat = min(top, max(0, int(round((lat - lat0) / UNIT))))
            dlon = min(top, max(0, int(round((lon - lon0) / UNIT))))
            (dog if is_dog_bin else gen).append("%d,%d;" % (dlat, dlon))
        data = json.dumps({"d": "".join(dog), "g": "".join(gen)}, separators=(",", ":"))
        with open(os.path.join(folder, name + ".json"), "w") as f:
            f.write(data)
        self.leaves += 1
        self.max_bytes = max(self.max_bytes, len(data))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("extracts", nargs="+")
    parser.add_argument("--out", required=True, help="web root, e.g. server/public")
    args = parser.parse_args()

    # Deduplicate bins that appear in several (overlapping) extracts.
    seen = set()
    roots = {}
    for pbf in args.extracts:
        print("reading", pbf, file=sys.stderr)
        for lat, lon, dog in read_bins(pbf):
            key = (round(lat, 6), round(lon, 6))
            if key in seen:
                continue
            seen.add(key)
            roots.setdefault(root_of(lat, lon), []).append((lat, lon, dog))

    target = os.path.join(args.out, VERSION)
    if os.path.isdir(target):
        shutil.rmtree(target)
    builder = Builder(args.out)
    for (ri, rj), bins in sorted(roots.items()):
        builder.build_root(ri, rj, bins)

    meta = {
        "v": 1,
        "date": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%MZ"),
        "bins": len(seen),
        "roots": len(roots),
        "leaves": builder.leaves,
        "maxLeafBytes": builder.max_bytes,
    }
    with open(os.path.join(target, "meta.json"), "w") as f:
        json.dump(meta, f, separators=(",", ":"))
    print(json.dumps(meta), file=sys.stderr)


if __name__ == "__main__":
    main()
