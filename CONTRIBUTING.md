# Contributing

Thanks for considering a contribution.

## Development

- Keep the app model- and workflow-neutral. Do not commit model weights,
  workflow files, generated media, databases, logs, or machine-local config.
- Backend checks: from the repository root, run `python -m compileall -q Backend` and
  `python -m unittest discover -s Backend/tests -q`.
- Frontend checks: from `App`, run `flutter pub get`,
  `flutter analyze`, and `flutter test`.
- Keep tests synthetic. Use fixture paths and placeholder media only.

## Licensing

Contributions are accepted under GPL-3.0. Only submit code and assets you have
the right to license for this project.
