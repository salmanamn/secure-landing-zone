#!/usr/bin/env bash
S=00000000-0000-0000-0000-000000000001
curl -s "https://localhost:4577/subscriptions/$S/resources?api-version=2021-04-01" \
  | python3 -c 'import sys,json; [print(f"{r["type"]:55} {r["name"]}") for r in json.load(sys.stdin)["value"]]'
