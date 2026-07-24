"""main.py — CLI entry point for the azure-monitor-lab telemetry generator.

Usage examples::

    # Dry-run all scenarios, 5-minute backfill, seeded
    python generator/main.py --dry-run --backfill-minutes 5 --seed 42

    # Upload only AKS with a crashloop anomaly injected
    python generator/main.py --scenario aks --anomaly crashloop

    # Continuous loop, 60-second interval
    python generator/main.py --scenario virtualmachines --loop --interval-seconds 60

Exit codes: 0 = success, 1 = failure.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from typing import Any, Dict, List, Optional

from generator.config import LabConfig
from generator.ingestion_client import IngestionClient
from generator.time_window import generate_timestamps
from generator.validation import validate_record

# ---------------------------------------------------------------------------
# Scenario registry
# ---------------------------------------------------------------------------

def _load_scenario_fn(scenario_key: str):
    """Import and return the generate() function for a scenario key."""
    if scenario_key == "virtualmachines":
        from generator.scenarios.virtual_machines import generate
    elif scenario_key == "appservice":
        from generator.scenarios.app_service import generate
    elif scenario_key == "aks":
        from generator.scenarios.aks import generate
    elif scenario_key == "azuresql":
        from generator.scenarios.azure_sql import generate
    elif scenario_key == "apm":
        from generator.scenarios.apm import generate
    else:
        raise ValueError(f"Unknown scenario key: '{scenario_key}'")
    return generate


ALL_SCENARIOS = ["virtualmachines", "appservice", "aks", "azuresql", "apm"]

# ---------------------------------------------------------------------------
# Core run logic (single pass)
# ---------------------------------------------------------------------------

def run_once(
    config: LabConfig,
    client: IngestionClient,
    scenarios: List[str],
    backfill_minutes: int,
    interval_seconds: int,
    anomaly: Optional[str],
    seed: Optional[int],
    dry_run: bool,
) -> Dict[str, int]:
    """Generate + validate + upload one pass.  Returns {scenario: row_count}."""
    ticks = generate_timestamps(
        backfill_minutes=backfill_minutes,
        interval_seconds=interval_seconds,
        seed=seed,
    )

    summary: Dict[str, int] = {}
    errors_found = False

    for scenario_key in scenarios:
        generate_fn = _load_scenario_fn(scenario_key)
        records: List[Dict[str, Any]] = generate_fn(
            config,
            ticks,
            anomaly=anomaly,
            seed=seed,
        )

        # Validate all records
        validation_errors: List[str] = []
        for rec in records:
            errs = validate_record(scenario_key, rec)
            validation_errors.extend(errs)

        if validation_errors:
            errors_found = True
            print(
                f"  [WARN] {scenario_key}: {len(validation_errors)} validation error(s):",
                file=sys.stderr,
            )
            for e in validation_errors[:5]:
                print(f"    - {e}", file=sys.stderr)
            if len(validation_errors) > 5:
                print(
                    f"    ... and {len(validation_errors)-5} more", file=sys.stderr
                )

        # Sample record (first record if available)
        if records and dry_run:
            print(f"\n  [dry-run] {scenario_key}: {len(records)} records generated")
            print(f"  Sample record:")
            print("  " + json.dumps(records[0], indent=4, default=str).replace("\n", "\n  "))

        uploaded = client.upload(scenario_key, records)
        summary[scenario_key] = uploaded

    return summary


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m generator.main",
        description="Azure Monitor Lab — telemetry generator",
    )
    parser.add_argument(
        "--scenario",
        choices=["all"] + ALL_SCENARIOS,
        default="all",
        help="Scenario(s) to generate (default: all)",
    )
    parser.add_argument(
        "--backfill-minutes",
        type=int,
        default=15,
        metavar="N",
        help="Minutes of history to backfill on first run (default: 15)",
    )
    parser.add_argument(
        "--interval-seconds",
        type=int,
        default=60,
        metavar="N",
        help="Tick spacing in seconds (default: 60)",
    )
    parser.add_argument(
        "--anomaly",
        default=None,
        metavar="KEY",
        help="Inject an alert-triggering anomaly into the chosen scenario",
    )
    parser.add_argument(
        "--seed",
        type=int,
        default=None,
        metavar="N",
        help="Random seed for reproducible output",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Skip Azure upload; print counts + sample records to stdout",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--once",
        action="store_true",
        default=True,
        help="Run a single pass then exit (default)",
    )
    mode.add_argument(
        "--loop",
        action="store_true",
        help="Run continuously, one pass per --interval-seconds",
    )
    return parser


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main(argv: Optional[List[str]] = None) -> int:
    parser = _build_parser()
    args = parser.parse_args(argv)

    # Normalise scenarios
    scenarios = ALL_SCENARIOS if args.scenario == "all" else [args.scenario]

    # Load config (dry-run skips required-var checks)
    try:
        config = LabConfig.load(dry_run=args.dry_run)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    client = IngestionClient(config, dry_run=args.dry_run)

    loop_mode: bool = args.loop

    print(
        f"azure-monitor-lab generator  "
        f"[{'dry-run' if args.dry_run else 'LIVE'}]  "
        f"scenarios={scenarios}  "
        f"backfill={args.backfill_minutes}min  "
        f"interval={args.interval_seconds}s"
        + (f"  anomaly={args.anomaly}" if args.anomaly else "")
    )

    try:
        while True:
            summary = run_once(
                config=config,
                client=client,
                scenarios=scenarios,
                backfill_minutes=args.backfill_minutes,
                interval_seconds=args.interval_seconds,
                anomaly=args.anomaly,
                seed=args.seed,
                dry_run=args.dry_run,
            )

            # Print per-scenario summary
            print("\n--- Summary ---")
            total = 0
            for scenario_key, count in summary.items():
                print(f"  {scenario_key:20s}: {count:6d} rows")
                total += count
            print(f"  {'TOTAL':20s}: {total:6d} rows")

            if not loop_mode:
                break

            print(f"\nSleeping {args.interval_seconds}s before next pass…")
            time.sleep(args.interval_seconds)

    except KeyboardInterrupt:
        print("\nInterrupted.")

    except RuntimeError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
