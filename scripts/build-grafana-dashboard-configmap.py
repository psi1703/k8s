#!/usr/bin/env python3
"""Generate Grafana dashboard ConfigMap YAML from dashboard JSON.

The JSON dashboard file is the single source of truth. This script embeds it
into a Kubernetes ConfigMap with the grafana_dashboard=1 label watched by the
kube-prometheus-stack Grafana sidecar.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path


DEFAULT_SOURCE = Path("k8s/observability/dashboards/otp-relay-live.json")
DEFAULT_OUTPUT = Path("k8s/observability/grafana-dashboard-otp-relay-live.yaml")
DEFAULT_CONFIGMAP_NAME = "otp-relay-live-dashboard"
DEFAULT_NAMESPACE = "observability"
DEFAULT_KEY = "otp-relay-live.json"


def _indent_literal_block(text: str, spaces: int = 4) -> str:
    prefix = " " * spaces
    return "".join(prefix + line if line.strip() else "\n" for line in text.splitlines(True))


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
