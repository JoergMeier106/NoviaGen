from __future__ import annotations

from .blueprint import api

# Import route modules for blueprint registration side effects.
from . import routes_assets as _routes_assets
from . import routes_backups as _routes_backups
from . import routes_chat as _routes_chat
from . import routes_gallery as _routes_gallery
from . import routes_jobs as _routes_jobs
from . import routes_system as _routes_system

__all__ = ["api"]
