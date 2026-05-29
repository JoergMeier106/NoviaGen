"""Test package bootstrap for backend unittest discovery."""

from pathlib import Path
import sys

_BACKEND_ROOT = Path(__file__).resolve().parents[1]
_BACKEND_ROOT_TEXT = str(_BACKEND_ROOT)

if _BACKEND_ROOT_TEXT not in sys.path:
    sys.path.insert(0, _BACKEND_ROOT_TEXT)
