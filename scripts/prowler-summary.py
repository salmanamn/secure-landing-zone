#!/usr/bin/env python3
"""Split a Prowler CSV into findings on the stack's RG vs subscription-level findings."""
import csv, sys, collections
status = lambda r: "MUTED" if r.get("MUTED", "").lower() == "true" else r["STATUS"]
rows = list(csv.DictReader(open(sys.argv[1], newline=""), delimiter=";"))
in_rg = lambda r: "/resourcegroups/rg-slz-azure/" in r["RESOURCE_UID"].lower()
for scope, keep in (("stack (rg-slz-azure)", in_rg), ("subscription-level", lambda r: not in_rg(r))):
    sel = [r for r in rows if keep(r)]
    c = collections.Counter(status(r) for r in sel)
    print(f"\n== {scope}: FAIL {c['FAIL']} / MUTED {c['MUTED']} / PASS {c['PASS']}")
    for r in sorted(sel, key=lambda r: (r["SERVICE_NAME"], r["CHECK_ID"])):
        if status(r) in ("FAIL", "MUTED"):
            print(f"  {status(r):<5} {r['SEVERITY']:<7} {r['CHECK_ID']:<58} {r['RESOURCE_NAME']}")
