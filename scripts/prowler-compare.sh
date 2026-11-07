#!/usr/bin/env bash
# Markdown before/after table by Prowler service.
# Usage: scripts/prowler-compare.sh <before.ocsf.json> <after.ocsf.json>
set -euo pipefail
[ $# -eq 2 ] || { echo "usage: $0 <before.ocsf.json> <after.ocsf.json>" >&2; exit 2; }

jq -nr --slurpfile b "$1" --slurpfile a "$2" '
  def svc: .metadata.event_code | split("_")[0];
  def st:  if .status == "Suppressed" then "MUTED" else .status_code end;

  ($b[0] | map(select(st == "FAIL")) | group_by(svc)
         | map({key: (.[0] | svc), value: length}) | from_entries) as $bf
  | ($a[0] | group_by(svc)
         | map({key: (.[0] | svc),
                value: (group_by(st) | map({key: (.[0] | st), value: length}) | from_entries)})
         | from_entries) as $af
  | ((($bf | keys) + ($af | keys)) | unique) as $svcs
  | "| Service | Before FAIL | After FAIL | After muted | After PASS |",
    "|---|---:|---:|---:|---:|",
    ($svcs[] as $s
      | "| \($s) | \($bf[$s] // 0) | \($af[$s].FAIL // 0) | \($af[$s].MUTED // 0) | \($af[$s].PASS // 0) |"),
    "| **Total** | **\([$bf[]] | add // 0)** | **\([$af[] | .FAIL // 0] | add)** | **\([$af[] | .MUTED // 0] | add)** | **\([$af[] | .PASS // 0] | add)** |"
'