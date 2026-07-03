import json
import sys
from pathlib import Path

import pytest

# Make the package importable without an install.
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

FIXTURE = Path(__file__).parent / "fixtures" / "sample_extract.json"


@pytest.fixture
def fixture_path() -> str:
    return str(FIXTURE)


@pytest.fixture
def envelope() -> dict:
    with FIXTURE.open() as fh:
        return json.load(fh)


@pytest.fixture
def atoms(envelope) -> dict:
    return envelope["data"]
