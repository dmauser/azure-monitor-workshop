"""ingestion_client — thin wrapper over azure-monitor-ingestion LogsIngestionClient.

In dry_run mode no Azure credentials are required; the client is never
instantiated and upload() simply prints a summary and returns counts.

HttpResponseError from the SDK is caught and re-raised with a clearer message.
"""

from __future__ import annotations

import json
from typing import Any, Dict, List

from generator.config import LabConfig


class IngestionClient:
    """Wraps LogsIngestionClient + DefaultAzureCredential.

    Args:
        config: Loaded LabConfig.
        dry_run: When True, skip all Azure calls.
    """

    def __init__(self, config: LabConfig, dry_run: bool = False) -> None:
        self._config = config
        self._dry_run = dry_run
        self._client = None

        if not dry_run:
            # Deferred import so dry-run requires no azure packages at import time
            # (they are installed, but we avoid credential resolution).
            from azure.identity import DefaultAzureCredential
            from azure.monitor.ingestion import LogsIngestionClient as _SDK

            credential = DefaultAzureCredential()
            self._client = _SDK(
                endpoint=config.dce_endpoint,
                credential=credential,
            )

    def upload(
        self,
        scenario_key: str,
        records: List[Dict[str, Any]],
    ) -> int:
        """Upload *records* to the DCE stream for *scenario_key*.

        Returns:
            Number of records successfully submitted (or counted in dry-run).

        Raises:
            KeyError: if *scenario_key* is not found in config.
            RuntimeError: wrapping HttpResponseError on upload failure.
        """
        if not records:
            return 0

        scenario = self._config.scenarios[scenario_key]

        if self._dry_run:
            print(
                f"  [dry-run] {scenario_key}: would upload {len(records)} records "
                f"-> stream={scenario.stream} dcr={scenario.dcr_immutable_id or '(not set)'}"
            )
            return len(records)

        try:
            self._client.upload(  # type: ignore[union-attr]
                rule_id=scenario.dcr_immutable_id,
                stream_name=scenario.stream,
                logs=records,
            )
        except Exception as exc:
            # Catch azure.core.exceptions.HttpResponseError (and anything else)
            raise RuntimeError(
                f"Upload failed for scenario '{scenario_key}' "
                f"(stream={scenario.stream}): {exc}"
            ) from exc

        return len(records)
