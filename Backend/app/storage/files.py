from __future__ import annotations

import os
import shutil
import zipfile
from pathlib import Path


def remove_file_if_present(file_path: Path) -> None:
    if file_path.exists():
        try:
            os.remove(file_path)
        except (FileNotFoundError, PermissionError):
            pass


def replace_directory_contents(destination_dir: Path, source_dir: Path | None) -> None:
    destination_dir.mkdir(parents=True, exist_ok=True)
    for child in destination_dir.iterdir():
        if child.is_dir():
            shutil.rmtree(child)
        else:
            remove_file_if_present(child)

    copy_missing_tree(source_dir=source_dir, destination_dir=destination_dir, overwrite=True)


def merge_directory_contents(destination_dir: Path, source_dir: Path | None) -> None:
    destination_dir.mkdir(parents=True, exist_ok=True)
    copy_missing_tree(source_dir=source_dir, destination_dir=destination_dir, overwrite=False)


def copy_missing_tree(
    *,
    source_dir: Path | None,
    destination_dir: Path,
    overwrite: bool,
) -> None:
    if source_dir is None or not source_dir.exists():
        return

    for source_path in sorted(source_dir.rglob("*")):
        if not source_path.is_file():
            continue
        destination_path = destination_dir / source_path.relative_to(source_dir)
        if destination_path.exists() and not overwrite:
            continue
        destination_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source_path, destination_path)


def extract_archive_subtree(
    archive: zipfile.ZipFile,
    root_name: str,
    destination_dir: Path,
) -> None:
    for info in archive.infolist():
        relative_path = archive_subpath(info.filename, root_name)
        if relative_path is None:
            continue
        target_path = destination_dir / relative_path
        target_path.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(info, "r") as source_file, target_path.open("wb") as target_file:
            shutil.copyfileobj(source_file, target_file)


def archive_subpath(archive_name: str, root_name: str) -> Path | None:
    normalized = archive_name.replace("\\", "/").strip("/")
    if not normalized:
        return None
    parts = Path(normalized).parts
    if not parts or parts[0] != root_name:
        return None
    relative_parts = parts[1:]
    if not relative_parts:
        return None
    if any(part in {"", ".", ".."} for part in relative_parts):
        raise ValueError(f"Invalid archive entry: {archive_name}")
    return Path(*relative_parts)

