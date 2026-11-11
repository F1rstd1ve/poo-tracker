// Gassi-Server (ADR 0006), Etappe B: shared Mülleimer.
//
// Contract: docs/spec-server.md, section "Etappe B – Geteilte Mülleimer".
// Static files (tiles under /t1, pages) are served by the assets binding;
// this script runs only for /api/* (run_worker_first in wrangler.jsonc).
//
//   POST /api/v1/c            batch of up to 10 events (a / r / f / x)
//   GET  /api/v1/s/<ri>_<rj>  shared layer of one 0.4 degree root
//   scheduled()               daily cleanup
//
// Plain ES module, no build step, no dependencies.

const ROOT_DEG = 0.4;
const ROOT_UNITS = 40000; // ROOT_DEG in 1e-5 degrees
const SAME_BIN_M = 8;
const FAR_M = 50000;
const MAX_EVENTS = 10;
const MAX_BODY = 16384;
const MAX_ADDS = 30;
const MAX_OTHER = 30;
const LAYER_TTL = 3600;
const DAY_S = 86400;
const UNCONFIRMED_DAYS = 180;
const REPORT_DAYS = 365;
const EARTH_M = 6371008.8;
// Public default; set the secret IP_SALT to make the IP hashes unguessable.
const IP_SALT = "gassi-depot-ip-v1";

const KINDS = { g: 1, d: 2 };
const UID_RE = /^[0-9a-fA-F]{32}$/;
const LAYER_RE = /^\/api\/v1\/s\/(\d{1,3})_(\d{1,3})$/;

const OK = { ok: 1 };
const BAD = { err: "bad" };
const LIMIT = { err: "limit" };
const FAR = { err: "far" };

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;
    if (path === "/api/v1/c") {
      if (request.method !== "POST") return methodNotAllowed("POST");
      return contribute(request, env, url);
    }
    const m = LAYER_RE.exec(path);
    if (m) {
      if (request.method !== "GET") return methodNotAllowed("GET");
      return layer(env, ctx, url, Number(m[1]), Number(m[2]));
    }
    return env.ASSETS.fetch(request);
  },

  async scheduled(controller, env, ctx) {
    ctx.waitUntil(cleanup(env));
  },
};

// ---------------------------------------------------------------- helpers

function json(obj, status = 200, headers = {}) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...headers },
  });
}

function badRequest(msg) {
  return json({ err: msg }, 400, { "Cache-Control": "no-store" });
}

function methodNotAllowed(allow) {
  return json({ err: "method" }, 405, { Allow: allow });
}

function rootOf(lat, lon) {
  // Same formula as pipeline/build_tiles.py.
  return [Math.floor((lat + 90) / ROOT_DEG), Math.floor((lon + 180) / ROOT_DEG)];
}

function rootKey(lat, lon) {
  const [ri, rj] = rootOf(lat, lon);
  return ri + "_" + rj;
}

function validCoord(lat, lon) {
  return (
    typeof lat === "number" && typeof lon === "number" &&
    Number.isFinite(lat) && Number.isFinite(lon) &&
    lat >= -90 && lat < 90 && lon >= -180 && lon < 180
  );
}

function validId(s) {
  return Number.isSafeInteger(s) && s > 0;
}

function distM(lat1, lon1, lat2, lon2) {
  const r = Math.PI / 180;
  const dLat = (lat2 - lat1) * r;
  const dLon = (lon2 - lon1) * r;
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(lat1 * r) * Math.cos(lat2 * r) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_M * Math.asin(Math.min(1, Math.sqrt(a)));
}

async function sha256Hex(text) {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function clientIp(request, env) {
  // TEST_IP_HEADER is only for local tests (wrangler dev --var); never set it
  // in production, it would let clients choose their own IP for the limits.
  if (env.TEST_IP_HEADER) {
    const v = request.headers.get(env.TEST_IP_HEADER);
    if (v) return v;
  }
  return request.headers.get("CF-Connecting-IP") || "0.0.0.0";
}

function layerCacheKey(origin, root) {
  return new Request(origin + "/api/v1/s/" + root, { method: "GET" });
}

// ------------------------------------------------------- POST /api/v1/c

async function contribute(request, env, url) {
  const text = await request.text();
  if (text.length > MAX_BODY) return badRequest("size");
  let body;
  try {
    body = JSON.parse(text);
  } catch {
    return badRequest("json");
  }
  if (!body || typeof body !== "object" || Array.isArray(body)) return badRequest("json");
  if (typeof body.u !== "string" || !UID_RE.test(body.u)) return badRequest("u");
  if (!Array.isArray(body.e) || body.e.length > MAX_EVENTS) return badRequest("e");

  const now = Math.floor(Date.now() / 1000);
  const day = new Date(now * 1000).toISOString().slice(0, 10);
  const uid = body.u.toLowerCase();
  const ip = clientIp(request, env);
  const ipKey = "ip:" + (await sha256Hex(day + "|" + (env.IP_SALT || IP_SALT) + "|" + ip));
  const uKey = "u:" + uid;

  const { results: rows } = await env.DB
    .prepare("SELECT key, n_add, n_other, anchor_lat, anchor_lon FROM counters WHERE day = ? AND key IN (?, ?)")
    .bind(day, uKey, ipKey)
    .all();
  const counter = (key) => {
    const row = rows.find((r) => r.key === key);
    return {
      key,
      add: row ? row.n_add : 0,
      other: row ? row.n_other : 0,
      anchorLat: row ? row.anchor_lat : null,
      anchorLon: row ? row.anchor_lon : null,
      dAdd: 0,
      dOther: 0,
    };
  };

  const c = {
    env, uid, now,
    u: counter(uKey),
    ip: counter(ipKey),
    touched: new Set(), // roots whose cached layer must be purged
  };

  const out = [];
  for (const ev of body.e) out.push(await handleEvent(c, ev));

  // Persist counters (atomic increments; the anchor is set only once a day).
  const stmts = [];
  for (const k of [c.u, c.ip]) {
    if (!k.dAdd && !k.dOther) continue;
    const anchor = k === c.u ? k : { anchorLat: null, anchorLon: null };
    stmts.push(env.DB.prepare(
      "INSERT INTO counters (day, key, n_add, n_other, anchor_lat, anchor_lon) VALUES (?, ?, ?, ?, ?, ?) " +
      "ON CONFLICT (day, key) DO UPDATE SET n_add = n_add + excluded.n_add, n_other = n_other + excluded.n_other, " +
      "anchor_lat = COALESCE(anchor_lat, excluded.anchor_lat), anchor_lon = COALESCE(anchor_lon, excluded.anchor_lon)",
    ).bind(day, k.key, k.dAdd, k.dOther, anchor.anchorLat, anchor.anchorLon));
  }
  if (stmts.length) await env.DB.batch(stmts);

  // Purge the cached layer of changed roots (this data centre only; elsewhere
  // the 1 h TTL applies, as on the watch).
  if (c.touched.size) {
    const cache = caches.default;
    await Promise.all([...c.touched].map((root) => cache.delete(layerCacheKey(url.origin, root)).catch(() => false)));
  }

  return json({ r: out }, 200, { "Cache-Control": "no-store" });
}

function overLimit(c, what) {
  return what === "add"
    ? c.u.add >= MAX_ADDS || c.ip.add >= MAX_ADDS
    : c.u.other >= MAX_OTHER || c.ip.other >= MAX_OTHER;
}

function count(c, what) {
  for (const k of [c.u, c.ip]) {
    if (what === "add") {
      k.add++;
      k.dAdd++;
    } else {
      k.other++;
      k.dOther++;
    }
  }
}

async function handleEvent(c, ev) {
  if (!ev || typeof ev !== "object" || Array.isArray(ev)) return BAD;
  switch (ev.t) {
    case "a": return add(c, ev);
    case "r": return report(c, ev);
    case "f": return confirmByDisposal(c, ev);
    case "x": return removeOwn(c, ev);
    default: return BAD;
  }
}

// Bins of one kind within SAME_BIN_M of a point, nearest first.
async function nearBins(env, kind, lat, lon) {
  const m = SAME_BIN_M + 2;
  const dLat = m / 111000;
  const dLon = m / (111000 * Math.max(0.01, Math.cos((lat * Math.PI) / 180)));
  const { results } = await env.DB
    .prepare("SELECT id, lat, lon, uid, confirmed, root FROM bins WHERE kind = ? AND lat BETWEEN ? AND ? AND lon BETWEEN ? AND ?")
    .bind(kind, lat - dLat, lat + dLat, lon - dLon, lon + dLon)
    .all();
  return results
    .map((b) => ({ ...b, d: distM(lat, lon, b.lat, b.lon) }))
    .filter((b) => b.d <= SAME_BIN_M)
    .sort((a, b) => a.d - b.d || a.id - b.id);
}

// "a": add a shared bin.
async function add(c, ev) {
  const kind = KINDS[ev.k];
  const lat = ev.la;
  const lon = ev.lo;
  if (!kind || !validCoord(lat, lon)) return BAD;
  const imprecise = ev.i === 1 || ev.i === true;
  if (overLimit(c, "add")) return LIMIT;
  if (c.u.anchorLat != null && distM(c.u.anchorLat, c.u.anchorLon, lat, lon) > FAR_M) return FAR;

  const near = await nearBins(c.env, kind, lat, lon);
  let res;
  const own = near.find((b) => b.uid === c.uid);
  if (own) {
    // Same uid: no duplicate, answer with the existing entry.
    res = { s: own.id, f: own.confirmed ? 1 : 0 };
  } else if (!imprecise && near.length) {
    // Another uid with precise GPS confirms the nearest existing bin.
    const b = near[0];
    if (!b.confirmed) {
      await c.env.DB.prepare("UPDATE bins SET confirmed = 1, confirmed_at = ? WHERE id = ? AND confirmed = 0")
        .bind(c.now, b.id).run();
      c.touched.add(b.root);
    }
    res = { s: b.id, f: 1 };
  } else {
    // New (or imprecise) contribution: own unconfirmed entry.
    const root = rootKey(lat, lon);
    const row = await c.env.DB
      .prepare("INSERT INTO bins (lat, lon, kind, confirmed, uid, imprecise, created, root) VALUES (?, ?, ?, 0, ?, ?, ?, ?) RETURNING id")
      .bind(lat, lon, kind, c.uid, imprecise ? 1 : 0, c.now, root)
      .first();
    c.touched.add(root);
    res = { s: row.id, f: 0 };
  }

  count(c, "add");
  if (c.u.anchorLat == null) {
    c.u.anchorLat = lat;
    c.u.anchorLon = lon;
  }
  return res;
}

// "r": report "Hier ist kein Mülleimer" for a shared (s > 0) or OSM (s = 0) bin.
async function report(c, ev) {
  const db = c.env.DB;
  if (validId(ev.s)) {
    if (overLimit(c, "other")) return LIMIT;
    count(c, "other");
    const target = "s:" + ev.s;
    const [, cnt, bin] = await db.batch([
      db.prepare("INSERT OR IGNORE INTO reports (target, uid, created) VALUES (?, ?, ?)").bind(target, c.uid, c.now),
      db.prepare("SELECT COUNT(*) AS n FROM reports WHERE target = ?").bind(target),
      db.prepare("SELECT root FROM bins WHERE id = ?").bind(ev.s),
    ]);
    if (cnt.results[0].n >= 2 && bin.results.length) {
      await db.prepare("DELETE FROM bins WHERE id = ?").bind(ev.s).run();
      c.touched.add(bin.results[0].root);
    }
    return OK;
  }
  if (ev.s !== 0 && ev.s !== undefined) return BAD;

  // OSM bin, recognised by kind and coordinate rounded to 1e-5 degrees.
  const kind = KINDS[ev.k];
  if (!kind || !validCoord(ev.la, ev.lo)) return BAD;
  if (overLimit(c, "other")) return LIMIT;
  count(c, "other");
  const lat5 = Math.round(ev.la * 1e5);
  const lon5 = Math.round(ev.lo * 1e5);
  const target = "o:" + kind + ":" + lat5 + ":" + lon5;
  const [, cnt] = await db.batch([
    db.prepare("INSERT OR IGNORE INTO reports (target, uid, created) VALUES (?, ?, ?)").bind(target, c.uid, c.now),
    db.prepare("SELECT COUNT(*) AS n FROM reports WHERE target = ?").bind(target),
  ]);
  if (cnt.results[0].n >= 2) {
    const root = rootKey(lat5 / 1e5, lon5 / 1e5);
    const res = await db
      .prepare("INSERT OR IGNORE INTO hidden_osm (kind, lat5, lon5, root, created) VALUES (?, ?, ?, ?, ?)")
      .bind(kind, lat5, lon5, root, c.now)
      .run();
    if (res.meta.changes) c.touched.add(root);
  }
  return OK;
}

// "f": disposal near a shared bin of another uid confirms it.
async function confirmByDisposal(c, ev) {
  if (!validId(ev.s)) return BAD;
  if (overLimit(c, "other")) return LIMIT;
  count(c, "other");
  const b = await c.env.DB.prepare("SELECT uid, confirmed, root FROM bins WHERE id = ?").bind(ev.s).first();
  if (!b) return BAD;
  if (b.uid !== c.uid && !b.confirmed) {
    await c.env.DB.prepare("UPDATE bins SET confirmed = 1, confirmed_at = ? WHERE id = ? AND confirmed = 0")
      .bind(c.now, ev.s).run();
    c.touched.add(b.root);
  }
  return OK;
}

// "x": delete an own, still unconfirmed bin.
async function removeOwn(c, ev) {
  if (!validId(ev.s)) return BAD;
  if (overLimit(c, "other")) return LIMIT;
  count(c, "other");
  const b = await c.env.DB.prepare("SELECT uid, confirmed, root FROM bins WHERE id = ?").bind(ev.s).first();
  if (!b) return OK; // already gone
  if (b.uid !== c.uid || b.confirmed) return BAD;
  await c.env.DB.prepare("DELETE FROM bins WHERE id = ? AND uid = ? AND confirmed = 0").bind(ev.s, c.uid).run();
  c.touched.add(b.root);
  return OK;
}

// ------------------------------------------------- GET /api/v1/s/<ri>_<rj>

async function layer(env, ctx, url, ri, rj) {
  if (ri >= 180 / ROOT_DEG || rj >= 360 / ROOT_DEG) return badRequest("root");
  const root = ri + "_" + rj;
  const key = layerCacheKey(url.origin, root);
  const cache = caches.default;
  const hit = await cache.match(key);
  if (hit) return hit;

  const [bins, hidden] = await env.DB.batch([
    env.DB.prepare("SELECT id, kind, confirmed, lat, lon FROM bins WHERE root = ? ORDER BY id").bind(root),
    env.DB.prepare("SELECT kind, lat5, lon5 FROM hidden_osm WHERE root = ? ORDER BY kind, lat5, lon5").bind(root),
  ]);
  // SW corner of the root in 1e-5 degrees (integers, no rounding drift).
  const lat0 = ri * ROOT_UNITS - 90 * 1e5;
  const lon0 = rj * ROOT_UNITS - 180 * 1e5;
  const clamp = (v) => Math.min(ROOT_UNITS, Math.max(0, v));
  let b = "";
  for (const r of bins.results) {
    const dlat = clamp(Math.round(r.lat * 1e5) - lat0);
    const dlon = clamp(Math.round(r.lon * 1e5) - lon0);
    b += r.id + "," + r.kind + "," + (r.confirmed ? 1 : 0) + "," + dlat + "," + dlon + ";";
  }
  let h = "";
  for (const r of hidden.results) {
    h += r.kind + "," + clamp(r.lat5 - lat0) + "," + clamp(r.lon5 - lon0) + ";";
  }

  const resp = json({ b, h }, 200, {
    "Cache-Control": "public, max-age=" + LAYER_TTL,
    "Access-Control-Allow-Origin": "*",
  });
  ctx.waitUntil(cache.put(key, resp.clone()).catch(() => {}));
  return resp;
}

// ------------------------------------------------------- daily cleanup

async function cleanup(env) {
  const now = Math.floor(Date.now() / 1000);
  const today = new Date(now * 1000).toISOString().slice(0, 10);
  const db = env.DB;
  const res = await db.batch([
    db.prepare("DELETE FROM bins WHERE confirmed = 0 AND created < ?").bind(now - UNCONFIRMED_DAYS * DAY_S),
    db.prepare("DELETE FROM reports WHERE created < ?").bind(now - REPORT_DAYS * DAY_S),
    db.prepare("DELETE FROM counters WHERE day < ?").bind(today),
  ]);
  console.log("cleanup", JSON.stringify(res.map((r) => r.meta.changes)));
}
