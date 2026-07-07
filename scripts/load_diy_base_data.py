#!/usr/bin/env python3
"""
load_diy_base_data.py — replaces `sf data tree import --plan` for diy-base.

Strict, idempotent, completeness-checked sample-data loader for the
Data360 Retail Solution Kit. For every record in data/*.json:

  1. Look up the record in the org by its natural key.
  2. If found, use the existing Id.
  3. If not found, insert via Composite REST API.
  4. After each tier, assert: every file row is now mapped to an org Id.
     If not, STOP — do not proceed to dependent tiers.

Never deletes any existing org record. Never silently skips a file row.

Usage:
    python3 scripts/load_diy_base_data.py --target-org <alias>

Exit codes:
    0  every tier passed; all file rows are present in the org
    1  a tier failed completeness — printed which rows are missing
    2  hard error (no auth, file missing, etc.)
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

SF_CMD = os.environ.get("SF_CMD") or (
    "C:/Program Files/sf/bin/sf.cmd" if os.name == "nt" else "sf"
)
DATA_DIR = Path("data")
API_VERSION = "v60.0"
COMPOSITE_BATCH = 200
REF_RE = re.compile(r"^@(\w+)$")

# ---------------------------------------------------------------------------
# Tier plan — parents before children. Same order as data/plan.json.
# Each entry is a 4-tuple:
#   (file, sObject, list of natural-key field names, optional extra WHERE clause)
# ---------------------------------------------------------------------------

TIERS = [
    # Tier 0 — no FK deps
    ("accounts.json",            "Account",            ["FirstName", "LastName", "PersonEmail"], "isDIYRecord__pc = true"),
    ("products.json",            "Product2",           ["StockKeepingUnit"],                     None),
    ("pricebooks.json",          "Pricebook2",         ["Name"],                                 "IsStandard = false"),
    ("promotions.json",          "Promotion",          ["PromotionCode"],                        None),
    # Tier 1 — FK to Tier 0
    ("pricebookentries.json",    "PricebookEntry",     ["Pricebook2Id", "Product2Id"],           None),
    ("assets.json",               "Asset",             ["SerialNumber"],                         None),
    ("promotionproducts.json",   "PromotionProduct",   ["PromotionId", "ProductId"],             None),
    # Tier 2 — FK to Tier 1
    ("assetwarranties.json",     "AssetWarranty",      ["AssetId", "StartDate"],                 None),
    # Tier 3 — FK to Tier 0+1
    ("orders.json",              "Order",              ["AccountId", "Name"],                    None),
    # Tier 4 — FK to Tier 3+0+1
    ("orderitems.json",          "OrderItem",          ["OrderId", "Product2Id"],                None),
    # Tier 5 — FK to Tier 0
    ("serviceappointments.json", "ServiceAppointment", ["ParentRecordId", "Subject"],            None),
]

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def die(msg: str, code: int = 2) -> None:
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)

import re as _re
_DATE_RE = _re.compile(r'^\d{4}-\d{2}-\d{2}$')
_DATETIME_RE = _re.compile(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}')

def soql_escape(v) -> str:
    """Escape a Python value into a SOQL literal suitable for WHERE clauses.

    Rules:
    - None → null
    - bool → true/false (unquoted)
    - ISO date string 'YYYY-MM-DD' → unquoted (SOQL date literals)
    - ISO datetime string → unquoted (SOQL datetime literals)
    - int/float that look like Salesforce numeric IDs will be passed as
      quoted strings — all natural-key fields are text in Salesforce.
    - Everything else → single-quoted string
    """
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    s = str(v)
    # Date and datetime literals must NOT be quoted in SOQL
    if _DATE_RE.match(s) or _DATETIME_RE.match(s):
        return s
    s = s.replace("\\", "\\\\").replace("'", "\\'")
    return f"'{s}'"

def get_org_creds(org_alias: str) -> tuple[str, str]:
    """Run `sf org display` and return (instance_url, access_token)."""
    out = subprocess.run(
        [SF_CMD, "org", "display", "--target-org", org_alias, "--json"],
        capture_output=True, text=True, timeout=60,
    )
    if out.returncode != 0:
        die(f"sf org display failed: {out.stderr[:300]}")
    d = json.loads(out.stdout)
    r = d.get("result", {})
    inst = r.get("instanceUrl") or ""
    tok = r.get("accessToken") or ""
    if not inst or not tok:
        die("sf org display did not return instanceUrl/accessToken")
    return inst, tok

def http_post(url: str, token: str, body: dict) -> tuple[int, dict]:
    """Use curl via subprocess to avoid a Python `requests` dependency."""
    payload_path = Path(f"_curl_body_{os.getpid()}.json")
    payload_path.write_text(json.dumps(body))
    try:
        out = subprocess.run(
            [
                "curl", "-s", "-w", "\n%{http_code}", "-X", "POST",
                "-H", f"Authorization: Bearer {token}",
                "-H", "Content-Type: application/json",
                "-d", f"@{payload_path}",
                url,
            ],
            capture_output=True, text=True, timeout=120,
        )
    finally:
        try: payload_path.unlink()
        except FileNotFoundError: pass
    text = out.stdout.strip()
    nl = text.rfind("\n")
    if nl < 0:
        return 0, {"raw": text}
    body_text, code_text = text[:nl], text[nl+1:]
    try:
        body_obj = json.loads(body_text) if body_text else {}
    except json.JSONDecodeError:
        body_obj = {"raw": body_text}
    try:
        code = int(code_text)
    except ValueError:
        code = 0
    return code, body_obj

def http_get_query(instance_url: str, token: str, soql: str) -> list[dict]:
    """Run a SOQL query and return all records (handles pagination)."""
    import urllib.parse
    url = f"{instance_url}/services/data/{API_VERSION}/query?q={urllib.parse.quote(soql)}"
    records: list[dict] = []
    while True:
        out = subprocess.run(
            ["curl", "-s", "-X", "GET", "-H", f"Authorization: Bearer {token}", url],
            capture_output=True, text=True, timeout=120,
        )
        try:
            d = json.loads(out.stdout)
        except json.JSONDecodeError:
            die(f"SOQL response was not JSON. SOQL={soql!r}\nResponse head: {out.stdout[:200]!r}")
        if isinstance(d, list):
            die(f"SOQL error: {d}")
        if "records" not in d:
            die(f"SOQL unexpected shape: {json.dumps(d)[:300]}")
        records.extend(d["records"])
        if d.get("done"):
            break
        next_url = d.get("nextRecordsUrl")
        if not next_url:
            break
        url = f"{instance_url}{next_url}"
    return records

def composite_sobjects_insert(instance_url: str, token: str, sobject_type: str,
                              records: list[dict]) -> list[dict]:
    """
    Insert up to COMPOSITE_BATCH records via:
      POST /services/data/<v>/composite/sobjects
    Returns the per-record results array.
    """
    results: list[dict] = []
    for i in range(0, len(records), COMPOSITE_BATCH):
        chunk = records[i:i + COMPOSITE_BATCH]
        body = {
            "allOrNone": False,
            "records": [{**r, "attributes": {"type": sobject_type}} for r in chunk],
        }
        url = f"{instance_url}/services/data/{API_VERSION}/composite/sobjects"
        code, resp = http_post(url, token, body)
        if code != 200 or not isinstance(resp, list):
            die(f"composite/sobjects POST failed (HTTP {code}). Resp: {json.dumps(resp)[:600]}")
        results.extend(resp)
    return results

# ---------------------------------------------------------------------------
# Reference resolution
# ---------------------------------------------------------------------------

def resolve_value(v, ref_map: dict[str, str]):
    """Replace any '@xxxxRef1' literal with its resolved Id (if known)."""
    if isinstance(v, str):
        m = REF_RE.match(v)
        if m and m.group(1) in ref_map:
            return ref_map[m.group(1)]
    return v

def resolve_record(rec: dict, ref_map: dict[str, str]) -> dict:
    """Return a copy of rec with all @ref fields resolved + STANDARD_PRICEBOOK_ID swapped."""
    out = {}
    for k, v in rec.items():
        if k == "attributes":
            continue
        nv = resolve_value(v, ref_map)
        # Special literal placeholder used by pricebookentries.json
        if isinstance(nv, str) and nv == "STANDARD_PRICEBOOK_ID" and "STANDARD_PRICEBOOK_ID" in ref_map:
            nv = ref_map["STANDARD_PRICEBOOK_ID"]
        out[k] = nv
    return out

# ---------------------------------------------------------------------------
# Per-tier processing
# ---------------------------------------------------------------------------

def file_natural_key(rec: dict, key_fields: list[str], ref_map: dict[str, str]) -> tuple | None:
    """
    Build the natural-key tuple for a file row, resolving @refs along the way.
    Returns None if any key field is missing or contains an unresolved @ref
    (caller treats None as 'cannot match any org row yet').
    """
    vals = []
    for kf in key_fields:
        raw = rec.get(kf)
        if raw is None:
            return None
        v = resolve_value(raw, ref_map)
        if v == "STANDARD_PRICEBOOK_ID" and "STANDARD_PRICEBOOK_ID" in ref_map:
            v = ref_map["STANDARD_PRICEBOOK_ID"]
        if isinstance(v, str) and REF_RE.match(v):
            return None  # unresolved @ref → can't search the org for this row yet
        vals.append(v)
    return tuple(vals)

def lookup_existing_records(instance_url: str, token: str,
                            sobject_type: str, key_fields: list[str],
                            file_keys: list[tuple],
                            extra_where: str | None,
                            raw_file_keys: list[tuple] | None = None) -> dict[tuple, dict]:
    """
    Query the org for any rows that match any of the file_keys.
    Returns a dict keyed by the (case-folded for strings) key tuple.
    Each value is the org row (dict with Id, CreatedDate, ...).

    raw_file_keys: optional parallel list of pre-canonical key tuples to use in
    the SOQL IN clause. This preserves original case (e.g. 'ROCKSALT10') so that
    Salesforce fields with case-sensitive lookup (PromotionCode, etc.) are matched
    correctly. file_keys (canonical/lowercased) are still used for the return dict
    so callers can match with canonical(org_value).
    """
    if not file_keys:
        return {}
    soql_keys = raw_file_keys if raw_file_keys is not None else file_keys
    select_fields = ", ".join(["Id", "CreatedDate", *key_fields])
    where_parts: list[str] = []
    if extra_where:
        where_parts.append(f"({extra_where})")

    # Single-key fast path: WHERE k IN (...)
    if len(key_fields) == 1:
        kf = key_fields[0]
        # dedupe the SOQL values (preserve original case for the query)
        seen = set()
        in_vals = []
        for k in soql_keys:
            v = k[0]
            cv = canonical(v)
            if cv in seen: continue
            seen.add(cv)
            in_vals.append(v)  # original case for SOQL
        # chunk to keep SOQL under ~10k chars
        out: dict[tuple, dict] = {}
        chunk = 250
        for i in range(0, len(in_vals), chunk):
            in_clause = ", ".join(soql_escape(v) for v in in_vals[i:i+chunk])
            soql = f"SELECT {select_fields} FROM {sobject_type} WHERE {kf} IN ({in_clause})"
            if where_parts:
                soql += " AND " + " AND ".join(where_parts)
            soql += " ORDER BY CreatedDate ASC"
            for r in http_get_query(instance_url, token, soql):
                k = (canonical(r.get(kf)),)
                # Keep the OLDEST per natural key (we ORDER BY ASC so first wins)
                out.setdefault(k, r)
        return out

    # Composite key path: build OR-clause of (k1=v1 AND k2=v2)
    # Use soql_keys (original case) for the SOQL query values
    out: dict[tuple, dict] = {}
    chunk = 50
    for i in range(0, len(soql_keys), chunk):
        clauses = []
        for tup in soql_keys[i:i+chunk]:
            parts = " AND ".join(f"{kf} = {soql_escape(v)}" for kf, v in zip(key_fields, tup))
            clauses.append(f"({parts})")
        soql = (
            f"SELECT {select_fields} FROM {sobject_type} WHERE "
            + " OR ".join(clauses)
        )
        if where_parts:
            soql = f"SELECT {select_fields} FROM {sobject_type} WHERE ({' OR '.join(clauses)}) AND " + " AND ".join(where_parts)
        soql += " ORDER BY CreatedDate ASC"
        for r in http_get_query(instance_url, token, soql):
            k = tuple(canonical(r.get(kf)) for kf in key_fields)
            out.setdefault(k, r)
    return out

def canonical(v):
    """Case-insensitive comparison helper for natural-key matching on strings."""
    if isinstance(v, str):
        return v.strip().lower()
    return v

def process_tier(instance_url: str, token: str,
                 file_name: str, sobject: str, key_fields: list[str],
                 extra_where: str | None,
                 ref_map: dict[str, str]) -> tuple[int, int, list[dict]]:
    """
    Process one tier (one file). Returns (matched_count, inserted_count, missing_rows).
    Updates ref_map in-place for every successfully resolved row.
    On strict-completeness violation, returns missing_rows = list of rows that
    didn't end up in the org. Caller decides whether to halt.
    """
    path = DATA_DIR / file_name
    if not path.exists():
        die(f"data file not found: {path}")
    with open(path, encoding="utf-8") as f:
        doc = json.load(f)
    records = doc.get("records", [])
    print(f"\n=== {sobject} ({file_name}) — {len(records)} file rows ===")
    if not records:
        return (0, 0, [])

    # Build per-row keys (with @refs resolved as much as possible)
    file_keys = []      # canonical (lowercased) — used for dict matching
    raw_file_keys = []  # original case — used for SOQL IN clause (case-sensitive fields)
    rows_with_keys = []
    rows_with_missing_keys = []
    for rec in records:
        key = file_natural_key(rec, key_fields, ref_map)
        if key is None:
            rows_with_missing_keys.append(rec)
        else:
            raw_file_keys.append(tuple(key))  # preserve original case for SOQL
            file_keys.append(tuple(canonical(v) for v in key))
            rows_with_keys.append((rec, tuple(canonical(v) for v in key)))

    # SOQL the org for matches — pass raw_file_keys so original case goes into the query
    existing = lookup_existing_records(
        instance_url, token, sobject, key_fields, file_keys, extra_where,
        raw_file_keys=raw_file_keys,
    )
    print(f"  Org matches found: {len(existing)} (oldest CreatedDate per key when dups)")

    # Decide insert vs match
    to_insert: list[tuple[dict, dict]] = []  # (file_rec, resolved_payload)
    matched_count = 0
    for rec, key in rows_with_keys:
        ref_id = (rec.get("attributes") or {}).get("referenceId")
        org_row = existing.get(key)
        if org_row:
            ref_map[ref_id] = org_row["Id"]
            matched_count += 1
        else:
            payload = resolve_record(rec, ref_map)
            to_insert.append((rec, payload))

    # Re-build payloads for rows that had unresolved-key issues — insert them anyway,
    # since their @refs may have been resolved by an earlier tier.
    for rec in rows_with_missing_keys:
        payload = resolve_record(rec, ref_map)
        # If after resolution the payload still contains an @ref, that's a hard error
        # (parent tier should have populated it). Surface it.
        unresolved = [k for k, v in payload.items() if isinstance(v, str) and REF_RE.match(v)]
        if unresolved:
            print(f"  ⚠️  {rec.get('attributes',{}).get('referenceId')}: still has unresolved @refs in {unresolved} — will attempt insert; SF will reject if FK invalid")
        to_insert.append((rec, payload))

    # Insert
    inserted_count = 0
    failures: list[dict] = []
    if to_insert:
        print(f"  Inserting {len(to_insert)} new rows via Composite REST...")
        results = composite_sobjects_insert(
            instance_url, token, sobject, [p for _, p in to_insert]
        )
        for (rec, _), res in zip(to_insert, results):
            ref_id = (rec.get("attributes") or {}).get("referenceId")
            if res.get("success"):
                ref_map[ref_id] = res["id"]
                inserted_count += 1
            else:
                failures.append({
                    "referenceId": ref_id,
                    "errors": res.get("errors", []),
                    "row_summary": {k: rec.get(k) for k in key_fields},
                })

    print(f"  ✅ matched={matched_count}  ➕ inserted={inserted_count}  ❌ failures={len(failures)}")

    # Strict completeness check
    accounted_for = matched_count + inserted_count
    missing: list[dict] = []
    if accounted_for != len(records):
        missing = failures
        print(f"\n  ❌ COMPLETENESS FAILURE for {sobject}:")
        print(f"     File rows: {len(records)}")
        print(f"     Matched in org: {matched_count}")
        print(f"     Newly inserted: {inserted_count}")
        print(f"     Missing/failed: {len(records) - accounted_for}")
        for f in failures[:20]:
            print(f"       - refId={f['referenceId']} keys={f['row_summary']}")
            for e in f.get("errors", []):
                print(f"           {e.get('statusCode','?')}: {e.get('message','?')}")
    return (matched_count, inserted_count, missing)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--target-org", required=True, help="Salesforce CLI org alias or username")
    args = ap.parse_args()

    print(f"=== Data360 Retail base data loader ===")
    print(f"Target org : {args.target_org}")
    print(f"Data dir   : {DATA_DIR.absolute()}")
    print(f"Time       : {time.strftime('%Y-%m-%d %H:%M:%S')}")

    if not (DATA_DIR / "plan.json").exists():
        die("data/plan.json not found — are you running from the repo root?")

    instance_url, access_token = get_org_creds(args.target_org)
    print(f"Instance   : {instance_url}")

    ref_map: dict[str, str] = {}

    # Resolve Standard Pricebook ONCE; pricebookentries.json uses the literal placeholder.
    print("\n=== Resolving Standard Pricebook Id ===")
    rows = http_get_query(
        instance_url, access_token,
        "SELECT Id FROM Pricebook2 WHERE IsStandard = true AND IsActive = true LIMIT 1",
    )
    if not rows:
        die("No active Standard Pricebook in org — run scripts/apex/activatePricebook.apex first")
    ref_map["STANDARD_PRICEBOOK_ID"] = rows[0]["Id"]
    print(f"  STANDARD_PRICEBOOK_ID -> {ref_map['STANDARD_PRICEBOOK_ID']}")

    # Run tiers in order. STOP on first completeness failure.
    grand_matched = 0
    grand_inserted = 0
    for file_name, sobject, key_fields, extra_where in TIERS:
        m, i, missing = process_tier(
            instance_url, access_token,
            file_name, sobject, key_fields, extra_where, ref_map,
        )
        grand_matched += m
        grand_inserted += i
        if missing:
            print("\n🛑 STOPPING — completeness check failed at this tier.")
            print("   Per design, dependent tiers will not run because their @refs would be broken.")
            print("   Fix the underlying issue (validation rule, missing field, etc.) and re-run.")
            return 1

    # Final summary
    print("\n=== Final Summary ===")
    print(f"  Total resolved referenceIds: {len([k for k in ref_map if k != 'STANDARD_PRICEBOOK_ID'])}")
    print(f"  Total matched in org       : {grand_matched}")
    print(f"  Total newly inserted       : {grand_inserted}")
    print("✅ All file rows are present in the org.")
    return 0


if __name__ == "__main__":
    try:
        rc = main()
    finally:
        # Mandatory cleanup per Workspace Hygiene rule.
        # We don't write any persistent state to disk; the only transient is the
        # _curl_body_<pid>.json file created/deleted inside http_post().
        # Belt-and-suspenders sweep:
        for p in Path(".").glob("_curl_body_*.json"):
            try: p.unlink()
            except: pass
    sys.exit(rc)
