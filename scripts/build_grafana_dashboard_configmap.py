#!/usr/bin/env python3
"""Generate Grafana dashboard ConfigMap YAML from dashboard JSON.

The JSON dashboard file is the single source of truth. This script embeds it
into a Kubernetes ConfigMap with the grafana_dashboard=1 label watched by the
kube-prometheus-stack Grafana sidecar.

It supports both:
  - classic Grafana dashboard JSON
  - Grafana dashboard.grafana.app/v2 export JSON

The sidecar provisioning path expects classic dashboard JSON, so v2 exports are
converted before being embedded into the ConfigMap.
"""

from __future__ import annotations

import argparse
import copy
import json
from pathlib import Path
from typing import Any


DEFAULT_SOURCE = Path("k8s/observability/dashboards/otp-relay-live.json")
DEFAULT_OUTPUT = Path("k8s/observability/grafana-dashboard-otp-relay-live.yaml")
DEFAULT_CONFIGMAP_NAME = "otp-relay-live-dashboard"
DEFAULT_NAMESPACE = "observability"
DEFAULT_KEY = "otp-relay-live.json"


def _indent_literal_block(text: str, spaces: int = 4) -> str:
    prefix = " " * spaces
    return "".join(prefix + line if line.strip() else "\n" for line in text.splitlines(True))


def _as_dict(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def _as_list(value: Any) -> list[Any]:
    return value if isinstance(value, list) else []


def _drop_none(value: dict[str, Any]) -> dict[str, Any]:
    return {key: item for key, item in value.items() if item is not None}


def _sanitize_metadata(metadata: dict[str, Any]) -> dict[str, Any]:
    metadata = copy.deepcopy(metadata)

    annotations = metadata.get("annotations")
    if isinstance(annotations, dict):
        for key in [
            "grafana.app/folder",
            "grafana.app/folderTitle",
            "grafana.app/folderUrl",
            "grafana.app/createdBy",
            "grafana.app/updatedBy",
            "grafana.app/updatedTimestamp",
            "grafana.app/saved-from-ui",
        ]:
            annotations.pop(key, None)

        if not annotations:
            metadata.pop("annotations", None)

    labels = metadata.get("labels")
    if isinstance(labels, dict):
        labels.pop("grafana.app/deprecatedInternalID", None)
        if not labels:
            metadata.pop("labels", None)

    for key in [
        "resourceVersion",
        "generation",
        "creationTimestamp",
    ]:
        metadata.pop(key, None)

    return metadata


def _convert_time_settings(spec: dict[str, Any]) -> tuple[dict[str, str], str | None, str | None]:
    time_settings = _as_dict(spec.get("timeSettings"))
    classic_time = _as_dict(spec.get("time"))

    time_range = {
        "from": str(
            time_settings.get("from")
            or time_settings.get("fromNow")
            or classic_time.get("from")
            or "now-6h"
        ),
        "to": str(
            time_settings.get("to")
            or classic_time.get("to")
            or "now"
        ),
    }

    refresh = (
        time_settings.get("autoRefresh")
        or time_settings.get("refresh")
        or spec.get("refresh")
    )
    timezone = (
        time_settings.get("timezone")
        or spec.get("timezone")
    )

    return time_range, str(refresh) if refresh else None, str(timezone) if timezone else None


def _annotation_to_classic(annotation: dict[str, Any], index: int) -> dict[str, Any]:
    annotation_spec = _as_dict(annotation.get("spec"))
    query = _as_dict(annotation_spec.get("query"))
    query_spec = _as_dict(query.get("spec"))

    classic = copy.deepcopy(query_spec) if query_spec else {}
    classic.update(
        _drop_none(
            {
                "name": annotation_spec.get("name") or f"Annotation {index}",
                "enable": annotation_spec.get("enable", True),
                "hide": annotation_spec.get("hide", True),
                "iconColor": annotation_spec.get("iconColor"),
                "type": "dashboard",
                "builtIn": 1 if index == 1 else 0,
            }
        )
    )

    datasource = _as_dict(query.get("datasource"))
    if datasource:
        classic["datasource"] = _drop_none(
            {
                "type": datasource.get("type"),
                "uid": datasource.get("uid"),
            }
        ) or datasource.get("name")

    return classic


def _layout_items_by_element(spec: dict[str, Any]) -> dict[str, dict[str, int]]:
    layout = _as_dict(spec.get("layout"))
    layout_spec = _as_dict(layout.get("spec"))
    items = _as_list(layout_spec.get("items"))

    positions: dict[str, dict[str, int]] = {}

    for item in items:
        item_spec = _as_dict(_as_dict(item).get("spec"))
        element = _as_dict(item_spec.get("element"))
        name = element.get("name")
        if not isinstance(name, str):
            continue

        positions[name] = {
            "x": int(item_spec.get("x", 0) or 0),
            "y": int(item_spec.get("y", 0) or 0),
            "w": int(item_spec.get("width", item_spec.get("w", 12)) or 12),
            "h": int(item_spec.get("height", item_spec.get("h", 8)) or 8),
        }

    return positions


def _query_to_target(query: dict[str, Any], index: int) -> dict[str, Any]:
    query_spec = _as_dict(query.get("spec"))
    data_query = _as_dict(query_spec.get("query"))
    data_query_spec = _as_dict(data_query.get("spec"))

    target = copy.deepcopy(data_query_spec) if data_query_spec else copy.deepcopy(query_spec)
    target.setdefault("refId", query_spec.get("refId") or chr(ord("A") + index))

    datasource = _as_dict(data_query.get("datasource")) or _as_dict(target.get("datasource"))
    if datasource:
        target["datasource"] = _drop_none(
            {
                "type": datasource.get("type"),
                "uid": datasource.get("uid"),
            }
        ) or datasource

    return target


def _panel_to_classic(
    name: str,
    element: dict[str, Any],
    grid_pos: dict[str, int],
    panel_id: int,
) -> dict[str, Any]:
    element_spec = _as_dict(element.get("spec"))
    viz_config = _as_dict(element_spec.get("vizConfig"))
    viz_spec = _as_dict(viz_config.get("spec"))
    data = _as_dict(element_spec.get("data"))
    data_spec = _as_dict(data.get("spec"))

    targets = [
        _query_to_target(query, index)
        for index, query in enumerate(_as_list(data_spec.get("queries")))
        if isinstance(query, dict)
    ]

    panel = {
        "id": panel_id,
        "title": element_spec.get("title") or name,
        "type": viz_config.get("kind") or element_spec.get("type") or "timeseries",
        "gridPos": grid_pos,
        "targets": targets,
        "fieldConfig": viz_spec.get("fieldConfig", {"defaults": {}, "overrides": []}),
        "options": viz_spec.get("options", {}),
    }

    datasource = element_spec.get("datasource")
    if datasource is None and targets:
        datasource = targets[0].get("datasource")
    if datasource is not None:
        panel["datasource"] = datasource

    for optional_key in [
        "description",
        "transparent",
        "links",
        "repeat",
        "repeatDirection",
        "maxPerRow",
        "pluginVersion",
    ]:
        if optional_key in element_spec:
            panel[optional_key] = element_spec[optional_key]

    return panel


def _convert_v2_dashboard_to_classic(dashboard: dict[str, Any]) -> dict[str, Any]:
    metadata = _sanitize_metadata(_as_dict(dashboard.get("metadata")))
    spec = copy.deepcopy(_as_dict(dashboard.get("spec")))

    time_range, refresh, timezone = _convert_time_settings(spec)
    positions = _layout_items_by_element(spec)
    elements = _as_dict(spec.get("elements"))

    def panel_sort_key(name: str) -> tuple[int, int, str]:
        pos = positions.get(name, {})
        return (
            int(pos.get("y", 999999)),
            int(pos.get("x", 999999)),
            name,
        )

    panels: list[dict[str, Any]] = []
    for panel_id, name in enumerate(sorted(elements.keys(), key=panel_sort_key), start=1):
        element = _as_dict(elements.get(name))
        if element.get("kind") != "Panel":
            continue

        grid_pos = positions.get(name, {"x": 0, "y": (panel_id - 1) * 8, "w": 12, "h": 8})
        panels.append(_panel_to_classic(name, element, grid_pos, panel_id))

    annotations = [
        _annotation_to_classic(annotation, index)
        for index, annotation in enumerate(_as_list(spec.get("annotations")), start=1)
        if isinstance(annotation, dict)
    ]

    dashboard_uid = metadata.get("uid") or metadata.get("name")
    if isinstance(dashboard_uid, str) and len(dashboard_uid) > 40:
        dashboard_uid = metadata.get("name")

    classic = {
        "uid": dashboard_uid,
        "title": spec.get("title") or metadata.get("name") or "OTP Relay",
        "tags": spec.get("tags", []),
        "timezone": timezone or "browser",
        "schemaVersion": spec.get("schemaVersion", 39),
        "version": spec.get("version", 1),
        "refresh": refresh or "15s",
        "time": time_range,
        "annotations": {"list": annotations},
        "panels": panels,
        "editable": spec.get("editable", True),
        "graphTooltip": spec.get("graphTooltip", 0),
        "fiscalYearStartMonth": spec.get("fiscalYearStartMonth", 0),
    }

    if "description" in spec:
        classic["description"] = spec["description"]
    if "templating" in spec:
        classic["templating"] = spec["templating"]
    if "links" in spec:
        classic["links"] = spec["links"]

    return classic


def _sanitize_dashboard(dashboard: dict[str, Any]) -> dict[str, Any]:
    """Return sidecar-compatible classic dashboard JSON."""

    dashboard = copy.deepcopy(dashboard)

    if (
        isinstance(dashboard.get("apiVersion"), str)
        and dashboard.get("apiVersion", "").startswith("dashboard.grafana.app/")
        and dashboard.get("kind") == "Dashboard"
        and isinstance(dashboard.get("spec"), dict)
    ):
        return _convert_v2_dashboard_to_classic(dashboard)

    metadata = dashboard.get("metadata")
    if isinstance(metadata, dict):
        dashboard["metadata"] = _sanitize_metadata(metadata)

    for key in ["apiVersion", "kind"]:
        dashboard.pop(key, None)

    return dashboard


def build_configmap_yaml(
    source: Path,
    name: str,
    namespace: str,
    key: str,
) -> str:
    try:
        dashboard = json.loads(source.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise SystemExit(f"Dashboard JSON not found: {source}") from exc
    except json.JSONDecodeError as exc:
        raise SystemExit(f"Dashboard JSON is invalid: {source}: {exc}") from exc

    dashboard = _sanitize_dashboard(dashboard)

    # Normalize formatting so generated YAML diffs are stable.
    dashboard_json = json.dumps(dashboard, indent=2, ensure_ascii=False) + "\n"
    embedded = _indent_literal_block(dashboard_json, spaces=4)

    return (
        "apiVersion: v1\n"
        "kind: ConfigMap\n"
        "metadata:\n"
        f"  name: {name}\n"
        f"  namespace: {namespace}\n"
        "  labels:\n"
        '    grafana_dashboard: "1"\n'
        "data:\n"
        f"  {key}: |\n"
        f"{embedded}"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", default=str(DEFAULT_SOURCE), help="Dashboard JSON source file")
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT), help="Generated ConfigMap YAML output file")
    parser.add_argument("--name", default=DEFAULT_CONFIGMAP_NAME, help="ConfigMap name")
    parser.add_argument("--namespace", default=DEFAULT_NAMESPACE, help="ConfigMap namespace")
    parser.add_argument("--key", default=DEFAULT_KEY, help="ConfigMap data key")
    args = parser.parse_args()

    source = Path(args.source)
    output = Path(args.output)

    yaml_text = build_configmap_yaml(
        source=source,
        name=args.name,
        namespace=args.namespace,
        key=args.key,
    )

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(yaml_text, encoding="utf-8")
    print(f"Generated {output} from {source}")


if __name__ == "__main__":
    main()
