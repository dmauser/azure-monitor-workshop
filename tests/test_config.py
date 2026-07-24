"""test_config.py — LabConfig.load(dry_run=True) contract tests.

Covers:
- dry_run=True succeeds without Azure creds or a populated lab.env
- Location defaults to southcentralus; DCR IDs empty in dry_run mode
- Environment variable overrides are picked up
- Dotenv parsing rules (blanks, comments, first-'=' split, whitespace)
"""

import os
import pytest
from pathlib import Path

from generator.config import LabConfig, _read_env_file, SCENARIO_KEYS


# ---------------------------------------------------------------------------
# dry_run=True safe-defaults contract
# ---------------------------------------------------------------------------

class TestDryRun:
    def test_load_succeeds_without_creds(self):
        """dry_run=True must not raise even with no env vars or lab.env."""
        cfg = LabConfig.load(dry_run=True)
        assert cfg is not None

    def test_default_location_southcentralus(self):
        """LAB_LOCATION defaults to 'southcentralus' when unset."""
        cfg = LabConfig.load(dry_run=True)
        assert cfg.location == "southcentralus"

    def test_dcr_ids_empty_in_dry_run(self):
        """All five DCR immutable IDs are empty strings in dry_run mode."""
        cfg = LabConfig.load(dry_run=True)
        for key in SCENARIO_KEYS:
            assert cfg.scenarios[key].dcr_immutable_id == "", (
                f"Expected empty DCR ID for '{key}', got: "
                f"'{cfg.scenarios[key].dcr_immutable_id}'"
            )

    def test_stream_defaults(self):
        """Stream names default to Custom-<Scenario>_CL for every scenario."""
        cfg = LabConfig.load(dry_run=True)
        expected = {
            "virtualmachines": "Custom-VirtualMachines_CL",
            "appservice":       "Custom-AppService_CL",
            "aks":              "Custom-AKS_CL",
            "azuresql":         "Custom-AzureSQL_CL",
            "apm":              "Custom-APM_CL",
        }
        for key, stream in expected.items():
            assert cfg.scenarios[key].stream == stream

    def test_table_defaults(self):
        """Table names default to <Scenario>_CL for every scenario."""
        cfg = LabConfig.load(dry_run=True)
        expected = {
            "virtualmachines": "VirtualMachines_CL",
            "appservice":       "AppService_CL",
            "aks":              "AKS_CL",
            "azuresql":         "AzureSQL_CL",
            "apm":              "APM_CL",
        }
        for key, table in expected.items():
            assert cfg.scenarios[key].table == table

    def test_all_scenario_keys_present(self):
        """Scenarios dict contains exactly the five expected keys."""
        cfg = LabConfig.load(dry_run=True)
        assert set(cfg.scenarios.keys()) == set(SCENARIO_KEYS)

    def test_config_is_frozen(self):
        """LabConfig is a frozen dataclass — mutation must raise."""
        cfg = LabConfig.load(dry_run=True)
        with pytest.raises((AttributeError, TypeError)):
            cfg.location = "westus"  # type: ignore[misc]


# ---------------------------------------------------------------------------
# Environment variable overrides
# ---------------------------------------------------------------------------

class TestEnvVarOverride:
    def test_location_override(self, monkeypatch):
        """LAB_LOCATION env var overrides the default."""
        monkeypatch.setenv("LAB_LOCATION", "eastus")
        cfg = LabConfig.load(dry_run=True)
        assert cfg.location == "eastus"

    def test_resource_group_override(self, monkeypatch):
        """LAB_RESOURCE_GROUP env var is returned as resource_group."""
        monkeypatch.setenv("LAB_RESOURCE_GROUP", "rg-test")
        cfg = LabConfig.load(dry_run=True)
        assert cfg.resource_group == "rg-test"

    def test_subscription_id_override(self, monkeypatch):
        """LAB_SUBSCRIPTION_ID env var is picked up."""
        monkeypatch.setenv("LAB_SUBSCRIPTION_ID", "aaaabbbb-cccc-dddd-eeee-ffffffffffff")
        cfg = LabConfig.load(dry_run=True)
        assert cfg.subscription_id == "aaaabbbb-cccc-dddd-eeee-ffffffffffff"

    def test_dcr_id_override_virtualmachines(self, monkeypatch):
        """DCR_IMMUTABLE_ID_VIRTUAL_MACHINES env var overrides empty default."""
        monkeypatch.setenv("DCR_IMMUTABLE_ID_VIRTUAL_MACHINES", "dcr-abc123")
        cfg = LabConfig.load(dry_run=True)
        assert cfg.scenarios["virtualmachines"].dcr_immutable_id == "dcr-abc123"

    def test_dcr_id_override_apm(self, monkeypatch):
        """DCR_IMMUTABLE_ID_APM env var overrides empty default."""
        monkeypatch.setenv("DCR_IMMUTABLE_ID_APM", "dcr-apm-xyz")
        cfg = LabConfig.load(dry_run=True)
        assert cfg.scenarios["apm"].dcr_immutable_id == "dcr-apm-xyz"

    def test_stream_override(self, monkeypatch):
        """STREAM_AKS env var overrides the default stream name."""
        monkeypatch.setenv("STREAM_AKS", "Custom-AKS_CL_v2")
        cfg = LabConfig.load(dry_run=True)
        assert cfg.scenarios["aks"].stream == "Custom-AKS_CL_v2"

    def test_env_var_isolation(self, monkeypatch):
        """After monkeypatch scope, location reverts to default."""
        monkeypatch.setenv("LAB_LOCATION", "westeurope")
        cfg = LabConfig.load(dry_run=True)
        assert cfg.location == "westeurope"
        # After this test, monkeypatch undoes the change — verified by ordering
        # the test above that checks for 'southcentralus'


# ---------------------------------------------------------------------------
# Dotenv parsing (_read_env_file)
# ---------------------------------------------------------------------------

class TestDotenvParsing:
    def test_blank_lines_skipped(self, tmp_path):
        """Blank lines are ignored."""
        env_file = tmp_path / "test.env"
        env_file.write_text("\n\nFOO=bar\n\n", encoding="utf-8")
        result = _read_env_file(env_file)
        assert result == {"FOO": "bar"}

    def test_comment_lines_skipped(self, tmp_path):
        """Lines beginning with '#' are ignored."""
        env_file = tmp_path / "test.env"
        env_file.write_text("# comment\nFOO=bar\n# another comment\n", encoding="utf-8")
        result = _read_env_file(env_file)
        assert result == {"FOO": "bar"}

    def test_first_equals_only(self, tmp_path):
        """Value containing '=' is preserved — only split on first '='."""
        env_file = tmp_path / "test.env"
        env_file.write_text("URL=https://example.com/path?a=1&b=2\n", encoding="utf-8")
        result = _read_env_file(env_file)
        assert result == {"URL": "https://example.com/path?a=1&b=2"}

    def test_missing_file_returns_empty(self, tmp_path):
        """Non-existent file returns empty dict without raising."""
        result = _read_env_file(tmp_path / "nonexistent.env")
        assert result == {}

    def test_whitespace_stripped(self, tmp_path):
        """Leading/trailing whitespace on keys and values is stripped."""
        env_file = tmp_path / "test.env"
        env_file.write_text("  KEY  =  value  \n", encoding="utf-8")
        result = _read_env_file(env_file)
        assert result == {"KEY": "value"}

    def test_no_equals_line_skipped(self, tmp_path):
        """Lines without '=' are silently skipped."""
        env_file = tmp_path / "test.env"
        env_file.write_text("NOEQUALS\nFOO=bar\n", encoding="utf-8")
        result = _read_env_file(env_file)
        assert result == {"FOO": "bar"}

    def test_multiple_entries(self, tmp_path):
        """Multiple key=value pairs are all captured."""
        env_file = tmp_path / "test.env"
        env_file.write_text("A=1\nB=2\nC=three\n", encoding="utf-8")
        result = _read_env_file(env_file)
        assert result == {"A": "1", "B": "2", "C": "three"}

    def test_empty_value(self, tmp_path):
        """Key with empty value (KEY=) is parsed as empty string."""
        env_file = tmp_path / "test.env"
        env_file.write_text("KEY=\n", encoding="utf-8")
        result = _read_env_file(env_file)
        assert "KEY" in result
        assert result["KEY"] == ""


# ---------------------------------------------------------------------------
# Non-dry-run: missing required vars raise ValueError
# ---------------------------------------------------------------------------

class TestRequiredVarsEnforced:
    def test_missing_resource_group_raises(self, monkeypatch):
        """Without dry_run=True, missing LAB_RESOURCE_GROUP must raise ValueError."""
        for var in (
            "LAB_RESOURCE_GROUP", "LAB_SUBSCRIPTION_ID", "LAW_NAME", "LAW_ID",
            "DCE_LOGS_INGESTION_ENDPOINT",
            "DCR_IMMUTABLE_ID_VIRTUAL_MACHINES", "DCR_IMMUTABLE_ID_APP_SERVICE",
            "DCR_IMMUTABLE_ID_AKS", "DCR_IMMUTABLE_ID_AZURE_SQL", "DCR_IMMUTABLE_ID_APM",
        ):
            monkeypatch.delenv(var, raising=False)

        with pytest.raises(ValueError, match="Required config variable"):
            LabConfig.load(dry_run=False)
