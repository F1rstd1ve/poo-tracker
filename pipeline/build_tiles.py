#!/usr/bin/env python3
"""Build Gassi-Depot Mülleimer-Kacheln from an OSM extract (ADR 0006).

Usage:
    python3 pipeline/build_tiles.py <extract.osm.pbf> [<more.osm.pbf> ...] --out server/public
        [--shared shared.json --delete-sql delete.sql]

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

Shared bins (Etappe B, optional): --shared takes the JSON output of
    wrangler d1 execute poo-tracker --remote --json \
        --command "SELECT id,lat,lon,kind,confirmed FROM bins"
("same bin" = same kind and at most SAME_BIN_M metres apart; kind 1 = general
bin, 2 = dog bin):
  - an OSM bin near a CONFIRMED shared bin is left out of the tiles;
  - an UNCONFIRMED shared bin near an OSM bin (one that stays in the tiles) is
    deleted on the server: --delete-sql gets the DELETE statements (the file is
    always written, empty if there is nothing to delete).
A missing or unreadable --shared file only prints a warning; the tiles are
then built from OSM alone.
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
SAME_BIN_M = 8.0
METRES_PER_DEG = 6371008.8 * math.pi / 180
CELL_DEG = 2e-4  # grid hash cell for the "same bin" search (~22 m north-south)
DELETE_CHUNK = 200

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


def kind_of(dog):
    return 2 if dog else 1


def dist_m(lat1, lon1, lat2, lon2):
    """Equirectangular distance in metres, exact enough for a few metres."""
    x = (lon2 - lon1) * math.cos(math.radians((lat1 + lat2) / 2))
    return math.hypot(lat2 - lat1, x) * METRES_PER_DEG


def parse_wrangler_json(text):
    """Return the row dicts of `wrangler d1 execute --json` output.

    The output is a list with one entry per SQL statement:
        [{"results": [{"id": 1, "lat": 48.2, ...}, ...], "success": true, "meta": {...}}]
    Tolerates log lines before the JSON and a plain list of rows.
    """
    text = text.strip()
    try:
        data = json.loads(text)
    except ValueError:
        starts = [i for i in (text.find("["), text.find("{")) if i >= 0]
        if not starts:
            raise
        data, _ = json.JSONDecoder().raw_decode(text[min(starts):])
    rows = []

    def collect(node):
        if isinstance(node, list):
            for item in node:
                collect(item)
        elif isinstance(node, dict):
            if isinstance(node.get("results"), list):
                collect(node["results"])
            elif "lat" in node and "lon" in node:
                rows.append(node)
            elif node.get("success") is False or "error" in node:
                raise ValueError("wrangler reported an error: %s" % json.dumps(node)[:300])

    collect(data)
    return rows


def load_shared(path):
    """Shared bins as (id, lat, lon, kind, confirmed), or None if unusable."""
    try:
        with open(path, encoding="utf-8") as f:
            rows = parse_wrangler_json(f.read())
        shared = []
        for r in rows:
            shared.append((int(r["id"]), float(r["lat"]), float(r["lon"]), int(r["kind"]),
                           1 if int(r.get("confirmed") or 0) else 0))
        return shared
    except (OSError, ValueError, KeyError, TypeError) as e:
        print("WARNING: shared bins not usable (%s: %s); building tiles from OSM only"
              % (path, e), file=sys.stderr)
        return None


def cell_of(lat, lon):
    return math.floor(lat / CELL_DEG), math.floor(lon / CELL_DEG)


class NearIndex:
    """Grid hash for "is there a point of this kind within SAME_BIN_M?".

    Every point is registered in all cells its SAME_BIN_M circle can touch,
    so a query is a single dict lookup plus a few distance checks.
    """

    def __init__(self, points):
        self.cells = {}
        dlat = int(math.ceil(SAME_BIN_M / (METRES_PER_DEG * CELL_DEG)))
        for p in points:
            lat, lon = p[0], p[1]
            cos = max(0.01, math.cos(math.radians(lat)))
            dlon = int(math.ceil(SAME_BIN_M / (METRES_PER_DEG * cos * CELL_DEG)))
            ci, cj = cell_of(lat, lon)
            for i in range(ci - dlat, ci + dlat + 1):
                for j in range(cj - dlon, cj + dlon + 1):
                    self.cells.setdefault((i, j), []).append(p)

    def near(self, lat, lon, kind):
        """Points (lat, lon, kind, ...) of `kind` within SAME_BIN_M."""
        found = self.cells.get(cell_of(lat, lon))
        if not found:
            return []
        return [p for p in found if p[2] == kind and dist_m(lat, lon, p[0], p[1]) <= SAME_BIN_M]


def apply_shared(osm_bins, shared):
    """Merge rules OSM <-> shared bins (docs/spec-server.md, Etappe B).

    osm_bins: list of (lat, lon, dog); shared: list of (id, lat, lon, kind, confirmed).
    Returns (kept OSM bins, ids of unconfirmed shared bins to delete).
    """
    confirmed = NearIndex([(lat, lon, kind) for _, lat, lon, kind, c in shared if c])
    kept = [b for b in osm_bins if not confirmed.near(b[0], b[1], kind_of(b[2]))]
    unconfirmed = [(lat, lon, kind, sid) for sid, lat, lon, kind, c in shared if not c]
    doomed = set()
    if unconfirmed:
        index = NearIndex(unconfirmed)
        for lat, lon, dog in kept:
            for p in index.near(lat, lon, kind_of(dog)):
                doomed.add(p[3])
    return kept, sorted(doomed)


def write_delete_sql(path, ids):
    with open(path, "w") as f:
        for k in range(0, len(ids), DELETE_CHUNK):
            chunk = ids[k:k + DELETE_CHUNK]
            # confirmed = 0 again: a bin confirmed since the export stays.
            f.write("DELETE FROM bins WHERE confirmed = 0 AND id IN (%s);\n" % ",".join(map(str, chunk)))


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
    parser.add_argument("--shared", help="shared bins: JSON of wrangler d1 execute --json (optional)")
    parser.add_argument("--delete-sql", help="write DELETE statements for redundant unconfirmed shared bins")
    args = parser.parse_args()

    # Deduplicate bins that appear in several (overlapping) extracts.
    seen = set()
    osm_bins = []
    for pbf in args.extracts:
        print("reading", pbf, file=sys.stderr)
        for lat, lon, dog in read_bins(pbf):
            key = (round(lat, 6), round(lon, 6))
            if key in seen:
                continue
            seen.add(key)
            osm_bins.append((lat, lon, dog))

    doomed = []
    if args.shared:
        shared = load_shared(args.shared)
        if shared is not None:
            before = len(osm_bins)
            osm_bins, doomed = apply_shared(osm_bins, shared)
            print("shared bins: %d (%d confirmed); OSM bins left out: %d; unconfirmed shared to delete: %d"
                  % (len(shared), sum(1 for s in shared if s[4]), before - len(osm_bins), len(doomed)),
                  file=sys.stderr)
    if args.delete_sql:
        write_delete_sql(args.delete_sql, doomed)

    roots = {}
    for b in osm_bins:
        roots.setdefault(root_of(b[0], b[1]), []).append(b)

    target = os.path.join(args.out, VERSION)
    if os.path.isdir(target):
        shutil.rmtree(target)
    builder = Builder(args.out)
    for (ri, rj), bins in sorted(roots.items()):
        builder.build_root(ri, rj, bins)

    meta = {
        "v": 1,
        "date": datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%MZ"),
        "bins": len(osm_bins),
        "roots": len(roots),
        "leaves": builder.leaves,
        "maxLeafBytes": builder.max_bytes,
    }
    with open(os.path.join(target, "meta.json"), "w") as f:
        json.dump(meta, f, separators=(",", ":"))
    print(json.dumps(meta), file=sys.stderr)


if __name__ == "__main__":
    main()
