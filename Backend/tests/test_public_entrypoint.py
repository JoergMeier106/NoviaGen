from __future__ import annotations

import unittest

from Backend import create_app, load_active_assets
from Backend.app.app.assets import load_active_assets as factory_load_active_assets
from Backend.app.app.factory import create_app as factory_create_app


class PublicEntrypointTests(unittest.TestCase):
    def test_backend_package_reexports_app_factory_helpers(self) -> None:
        self.assertIs(create_app, factory_create_app)
        self.assertIs(load_active_assets, factory_load_active_assets)


if __name__ == "__main__":
    unittest.main()
