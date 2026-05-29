from __future__ import annotations

import requests

from .blueprint import api

# Import endpoint modules for their route registrations.
from . import assets as _assets
from . import backups as _backups
from . import chat as _chat
from . import gallery as _gallery
from . import jobs as _jobs
from . import system as _system

__all__ = ["api"]
