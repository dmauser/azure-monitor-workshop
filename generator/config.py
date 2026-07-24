"""LabConfig — loads config/lab.env and exposes runtime settings to the generator.

Parsing rules (no extra deps):
 - Read the file line-by-line; skip blanks and lines beginning with '#'
 - Split each line on the FIRST '=' only
 - Environment variables override file values
 - Raises ValueError on missing required vars unless dry_run=True
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Optional

_LAB_ENV_PATH = Path(__file__).parent.parent / "config" / "lab.env"

SCENARIO_KEYS = ("virtualmachines", "appservice", "aks", "azuresql", "apm")

# Maps scenario key → UPPER_SNAKE env suffix used in var names
_SCENARIO_ENV_SUFFIX: Dict[str, str] = {
    "virtualmachines": "VIRTUAL_MACHINES",
    "appservice": "APP_SERVICE",
    "aks": "AKS",
    "azuresql": "AZURE_SQL",
    "apm": "APM",
}

# Default stream/table values from the contract (hardcoded per convention)
_SCENARIO_STREAM_DEFAULTS: Dict[str, str] = {
    "virtualmachines": "Custom-VirtualMachines_CL",
    "appservice": "Custom-AppService_CL",
    "aks": "Custom-AKS_CL",
    "azuresql": "Custom-AzureSQL_CL",
    "apm": "Custom-APM_CL",
}

_SCENARIO_TABLE_DEFAULTS: Dict[str, str] = {
    "virtualmachines": "VirtualMachines_CL",
    "appservice": "AppService_CL",
    "aks": "AKS_CL",
    "azuresql": "AzureSQL_CL",
    "apm": "APM_CL",
}


def _read_env_file(path: Path) -> Dict[str, str]:
    """Parse a dotenv-style file into a dict of key→value."""
    if not path.exists():
        return {}
    result: Dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if "=" not in stripped:
            continue
        key, _, value = stripped.partition("=")
        result[key.strip()] = value.strip()
    return result


@dataclass(frozen=True)
class ScenarioConfig:
    dcr_immutable_id: str
    stream: str
    table: str


@dataclass(frozen=True)
class LabConfig:
    location: str
    resource_group: str
    subscription_id: str
    law_name: str
    law_id: str
    dce_endpoint: str
    scenarios: Dict[str, ScenarioConfig]

    @classmethod
    def load(cls, dry_run: bool = False) -> "LabConfig":
        """Load from config/lab.env with environment variable overrides."""
        file_vars = _read_env_file(_LAB_ENV_PATH)

        def get(key: str, required: bool = True, default: str = "") -> str:
            value = os.environ.get(key) or file_vars.get(key, default)
            if required and not dry_run and not value:
                raise ValueError(
                    f"Required config variable '{key}' is missing. "
                    f"Set it in config/lab.env or as an environment variable."
                )
            return value or default

        location = get("LAB_LOCATION", required=False, default="southcentralus")
        resource_group = get("LAB_RESOURCE_GROUP")
        subscription_id = get("LAB_SUBSCRIPTION_ID")
        law_name = get("LAW_NAME")
        law_id = get("LAW_ID")
        dce_endpoint = get("DCE_LOGS_INGESTION_ENDPOINT")

        scenarios: Dict[str, ScenarioConfig] = {}
        for scenario_key in SCENARIO_KEYS:
            suffix = _SCENARIO_ENV_SUFFIX[scenario_key]
            dcr_id = get(f"DCR_IMMUTABLE_ID_{suffix}", required=not dry_run)
            stream = get(
                f"STREAM_{suffix}",
                required=False,
                default=_SCENARIO_STREAM_DEFAULTS[scenario_key],
            )
            table = get(
                f"TABLE_{suffix}",
                required=False,
                default=_SCENARIO_TABLE_DEFAULTS[scenario_key],
            )
            scenarios[scenario_key] = ScenarioConfig(
                dcr_immutable_id=dcr_id,
                stream=stream,
                table=table,
            )

        return cls(
            location=location,
            resource_group=resource_group,
            subscription_id=subscription_id,
            law_name=law_name,
            law_id=law_id,
            dce_endpoint=dce_endpoint,
            scenarios=scenarios,
        )
