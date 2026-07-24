"""conftest.py — ensure repo root is on sys.path for all test imports.

Inserting the repo root at sys.path[0] makes ``import generator.*`` work from
any working directory without needing PYTHONPATH to be pre-set.
"""

import sys
from pathlib import Path

repo_root = str(Path(__file__).parent.parent)
if repo_root not in sys.path:
    sys.path.insert(0, repo_root)
