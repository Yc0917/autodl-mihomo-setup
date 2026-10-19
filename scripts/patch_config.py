#!/usr/bin/env python3
"""Patch downloaded Mihomo YAML; fail closed when group/node cannot be verified."""
import pathlib
import sys
import yaml

if len(sys.argv) != 4:
    raise SystemExit("usage: patch_config.py CONFIG GROUP NODE")

path = pathlib.Path(sys.argv[1])
group_name, node_name = sys.argv[2:]
data = yaml.safe_load(path.read_text(encoding="utf-8"))
if not isinstance(data, dict):
    raise SystemExit("Downloaded subscription is not a YAML mapping")
groups = data.get("proxy-groups")
if not isinstance(groups, list):
    raise SystemExit("Missing proxy-groups in subscription")
selected = [g for g in groups if isinstance(g, dict) and g.get("name") == group_name]
if len(selected) != 1:
    raise SystemExit(f"Expected exactly one group {group_name!r}, found {len(selected)}")
group = selected[0]
if str(group.get("type", "")).lower() != "select":
    raise SystemExit(f"Group {group_name!r} is not type select")
if node_name not in group.get("proxies", []):
    raise SystemExit(f"Node {node_name!r} not found in group {group_name!r}")
group["default-selected"] = node_name
profile = data.setdefault("profile", {})
if not isinstance(profile, dict):
    raise SystemExit("profile must be a mapping")
profile["store-selected"] = False
# Preserve YAML semantics including non-ASCII proxy names (formatting may change).
path.write_text(
    yaml.safe_dump(data, allow_unicode=True, sort_keys=False),
    encoding="utf-8",
)
print(f"Patched default node: {node_name}")
