#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from collections import defaultdict
from pathlib import Path

LIB_NAME_RE = re.compile(
    r"^(Ace[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*-\d+\.\d+|CallbackHandler-\d+\.\d+|LibStub)$"
)
TOC_META_RE = re.compile(r"^##\s*([^:]+):\s*(.*)$")
LIBSTUB_RE = re.compile(r'LibStub\(\s*["\']([^"\']+)["\']')
QUOTED_LIB_RE = re.compile(
    r'["\']((?:Ace[A-Za-z0-9]+(?:-[A-Za-z0-9]+)*-\d+\.\d+|CallbackHandler-\d+\.\d+|LibStub))["\']'
)

FEATURE_PATTERNS = {
    "AceAddon lifecycle or modules": [
        re.compile(r":NewAddon\("),
        re.compile(r":NewModule\("),
        re.compile(r"\bOnInitialize\b"),
        re.compile(r"\bOnEnable\b"),
        re.compile(r"\bOnDisable\b"),
    ],
    "AceConsole slash commands": [
        re.compile(r":RegisterChatCommand\("),
    ],
    "AceDB persistence or profiles": [
        re.compile(r"AceDB-3\.0"),
        re.compile(r":RegisterNamespace\("),
        re.compile(r"\.db\.profile\b"),
        re.compile(r"\.db\.char\b"),
    ],
    "AceConfig options tables": [
        re.compile(r":RegisterOptionsTable\("),
        re.compile(r'type\s*=\s*"group"'),
        re.compile(r'type\s*=\s*"toggle"'),
        re.compile(r'type\s*=\s*"range"'),
        re.compile(r'type\s*=\s*"keybinding"'),
    ],
    "AceConfigDialog Blizzard settings": [
        re.compile(r":AddToBlizOptions\("),
        re.compile(r"Settings\.OpenToCategory"),
        re.compile(r"InterfaceOptionsFrame_OpenToCategory"),
    ],
    "AceConfigRegistry refresh": [
        re.compile(r":NotifyChange\("),
    ],
    "AceGUI custom UI": [
        re.compile(r'AceGUI[^\\n]*:Create\("'),
        re.compile(r":ReleaseChildren\("),
        re.compile(r'SetLayout\("'),
        re.compile(r'SetCallback\("OnClose"'),
    ],
    "AceEvent events or messages": [
        re.compile(r":RegisterEvent\("),
        re.compile(r":RegisterMessage\("),
        re.compile(r":SendMessage\("),
    ],
    "AceHook integration": [
        re.compile(r":SecureHook\("),
        re.compile(r":Hook\("),
        re.compile(r":RawHook\("),
        re.compile(r":Unhook\("),
    ],
    "AceTimer scheduling": [
        re.compile(r":ScheduleTimer\("),
        re.compile(r":ScheduleRepeatingTimer\("),
        re.compile(r":CancelTimer\("),
        re.compile(r":CancelAllTimers\("),
    ],
    "AceBucket event coalescing": [
        re.compile(r":RegisterBucketEvent\("),
        re.compile(r":RegisterBucketMessage\("),
        re.compile(r":UnregisterBucket\("),
    ],
    "AceComm addon traffic": [
        re.compile(r":RegisterComm\("),
        re.compile(r":SendCommMessage\("),
    ],
    "AceSerializer structured payloads": [
        re.compile(r":Serialize\("),
        re.compile(r":Deserialize\("),
    ],
    "AceLocale localization": [
        re.compile(r":NewLocale\("),
        re.compile(r":GetLocale\("),
    ],
}


def read_text(path: Path) -> str:
    for encoding in ("utf-8", "utf-8-sig", "latin-1"):
        try:
            return path.read_text(encoding=encoding)
        except UnicodeDecodeError:
            continue
    return path.read_text(errors="replace")


def relpath(path: Path, root: Path) -> str:
    try:
        return path.relative_to(root).as_posix()
    except ValueError:
        return str(path)


def split_csv(value: str) -> list[str]:
    return [item.strip() for item in value.split(",") if item.strip()]


def detect_lib_name(path: Path) -> str | None:
    for part in reversed(path.parts):
        if LIB_NAME_RE.match(part):
            return part
    if LIB_NAME_RE.match(path.stem):
        return path.stem
    return None


def parse_toc(path: Path) -> dict:
    metadata: dict[str, str] = {}
    entries: list[str] = []

    for raw_line in read_text(path).splitlines():
        line = raw_line.strip()
        if not line:
            continue
        meta_match = TOC_META_RE.match(line)
        if meta_match:
            metadata[meta_match.group(1).strip()] = meta_match.group(2).strip()
            continue
        if line.startswith("#"):
            continue
        entries.append(line)

    return {
        "path": path,
        "metadata": metadata,
        "entries": entries,
    }


def parse_xml_recursive(
    path: Path,
    visited: set[Path],
    loaded_files: set[Path],
    loaded_libs: set[str],
    missing_files: set[Path],
) -> None:
    if path in visited:
        return
    visited.add(path)
    loaded_files.add(path)

    lib_name = detect_lib_name(path)
    if lib_name:
        loaded_libs.add(lib_name)

    try:
        root = ET.fromstring(read_text(path))
    except ET.ParseError:
        return

    for elem in root.iter():
        if not (elem.tag.endswith("Include") or elem.tag.endswith("Script")):
            continue
        relative_file = elem.attrib.get("file")
        if not relative_file:
            continue
        child = (path.parent / relative_file.replace("\\", "/")).resolve()
        if not child.exists():
            missing_files.add(child)
            continue
        loaded_files.add(child)
        child_lib = detect_lib_name(child)
        if child_lib:
            loaded_libs.add(child_lib)
        if child.suffix.lower() == ".xml":
            parse_xml_recursive(child, visited, loaded_files, loaded_libs, missing_files)


def collect_loaded_libraries(tocs: list[dict]) -> tuple[set[str], set[Path], set[Path]]:
    loaded_libs: set[str] = set()
    loaded_files: set[Path] = set()
    missing_files: set[Path] = set()
    visited_xml: set[Path] = set()

    for toc in tocs:
        toc_dir = toc["path"].parent
        for entry in toc["entries"]:
            candidate = (toc_dir / entry.replace("\\", "/")).resolve()
            if not candidate.exists():
                missing_files.add(candidate)
                continue
            loaded_files.add(candidate)
            lib_name = detect_lib_name(candidate)
            if lib_name:
                loaded_libs.add(lib_name)
            if candidate.suffix.lower() == ".xml":
                parse_xml_recursive(
                    candidate, visited_xml, loaded_files, loaded_libs, missing_files
                )

    return loaded_libs, loaded_files, missing_files


def discover_vendored_libs(root: Path) -> set[str]:
    libs_root = root / "Libs"
    if not libs_root.exists():
        return set()

    vendored: set[str] = set()
    for path in libs_root.rglob("*"):
        if path.is_dir() and LIB_NAME_RE.match(path.name):
            vendored.add(path.name)
    return vendored


def scan_lua_files(root: Path) -> tuple[dict[str, list[dict]], dict[str, list[dict]]]:
    library_hits: dict[str, list[dict]] = defaultdict(list)
    feature_hits: dict[str, list[dict]] = defaultdict(list)

    for path in sorted(root.rglob("*.lua")):
        relative_parts = {part.lower() for part in path.relative_to(root).parts}
        if "libs" in relative_parts:
            continue

        for lineno, line in enumerate(read_text(path).splitlines(), start=1):
            seen_libs: set[str] = set()
            for match in LIBSTUB_RE.finditer(line):
                seen_libs.add(match.group(1))
            for match in QUOTED_LIB_RE.finditer(line):
                seen_libs.add(match.group(1))

            for lib_name in sorted(seen_libs):
                library_hits[lib_name].append(
                    {"file": relpath(path, root), "line": lineno, "text": line.strip()}
                )

            for feature_name, patterns in FEATURE_PATTERNS.items():
                if any(pattern.search(line) for pattern in patterns):
                    feature_hits[feature_name].append(
                        {"file": relpath(path, root), "line": lineno, "text": line.strip()}
                    )

    return library_hits, feature_hits


def summarize_toc(toc: dict, root: Path) -> dict:
    metadata = toc["metadata"]
    return {
        "path": relpath(toc["path"], root),
        "title": metadata.get("Title"),
        "interface": metadata.get("Interface"),
        "dependencies": split_csv(metadata.get("Dependencies", "")),
        "optional_dependencies": split_csv(metadata.get("OptionalDeps", "")),
        "saved_variables": split_csv(metadata.get("SavedVariables", "")),
        "saved_variables_per_character": split_csv(
            metadata.get("SavedVariablesPerCharacter", "")
        ),
        "entry_count": len(toc["entries"]),
    }


def trim_hits(hits: list[dict], limit: int = 5) -> list[str]:
    rendered = [f'{hit["file"]}:{hit["line"]}' for hit in hits[:limit]]
    extra = len(hits) - limit
    if extra > 0:
        rendered.append(f"... +{extra} more")
    return rendered


def build_report(root: Path) -> dict:
    tocs = [parse_toc(path) for path in sorted(root.rglob("*.toc"))]
    loaded_libs, loaded_files, missing_files = collect_loaded_libraries(tocs)
    vendored_libs = discover_vendored_libs(root)
    library_hits, feature_hits = scan_lua_files(root)
    code_referenced_libs = set(library_hits)

    return {
        "root": str(root),
        "tocs": [summarize_toc(toc, root) for toc in tocs],
        "vendored_libraries": sorted(vendored_libs),
        "loaded_libraries": sorted(loaded_libs),
        "loaded_files": sorted(relpath(path, root) for path in loaded_files),
        "code_library_hits": {
            lib: library_hits[lib] for lib in sorted(library_hits)
        },
        "feature_hits": {
            feature: feature_hits[feature] for feature in sorted(feature_hits)
        },
        "gaps": {
            "referenced_in_code_but_not_loaded": sorted(code_referenced_libs - loaded_libs),
            "loaded_but_not_vendored_locally": sorted(loaded_libs - vendored_libs),
            "vendored_but_not_loaded": sorted(vendored_libs - loaded_libs),
            "loaded_but_not_referenced_directly": sorted(loaded_libs - code_referenced_libs),
        },
        "missing_files": sorted(relpath(path, root) for path in missing_files),
    }


def render_text(report: dict) -> str:
    lines: list[str] = []
    lines.append(f'Ace3 audit: {report["root"]}')
    lines.append("")

    lines.append("TOC summary")
    if report["tocs"]:
        for toc in report["tocs"]:
            lines.append(f'- {toc["path"]}')
            if toc["title"]:
                lines.append(f'  Title: {toc["title"]}')
            if toc["interface"]:
                lines.append(f'  Interface: {toc["interface"]}')
            if toc["dependencies"]:
                lines.append(f'  Dependencies: {", ".join(toc["dependencies"])}')
            if toc["optional_dependencies"]:
                lines.append(
                    f'  OptionalDeps: {", ".join(toc["optional_dependencies"])}'
                )
            if toc["saved_variables"]:
                lines.append(
                    f'  SavedVariables: {", ".join(toc["saved_variables"])}'
                )
            if toc["saved_variables_per_character"]:
                lines.append(
                    "  SavedVariablesPerCharacter: "
                    + ", ".join(toc["saved_variables_per_character"])
                )
            lines.append(f'  Entries: {toc["entry_count"]}')
    else:
        lines.append("- No .toc files found")
    lines.append("")

    lines.append("Vendored libraries")
    if report["vendored_libraries"]:
        for name in report["vendored_libraries"]:
            lines.append(f"- {name}")
    else:
        lines.append("- none")
    lines.append("")

    lines.append("Loaded from TOC/XML")
    if report["loaded_libraries"]:
        for name in report["loaded_libraries"]:
            lines.append(f"- {name}")
    else:
        lines.append("- none")
    lines.append("")

    lines.append("Libraries referenced in local Lua")
    if report["code_library_hits"]:
        for lib_name, hits in report["code_library_hits"].items():
            lines.append(f"- {lib_name}: {', '.join(trim_hits(hits))}")
    else:
        lines.append("- none")
    lines.append("")

    lines.append("Feature signals")
    if report["feature_hits"]:
        for feature_name, hits in report["feature_hits"].items():
            lines.append(f"- {feature_name}: {', '.join(trim_hits(hits))}")
    else:
        lines.append("- none")
    lines.append("")

    lines.append("Potential gaps")
    for label, values in report["gaps"].items():
        pretty = label.replace("_", " ")
        if values:
            lines.append(f"- {pretty}: {', '.join(values)}")
        else:
            lines.append(f"- {pretty}: none")

    if report["missing_files"]:
        lines.append("")
        lines.append("Missing files referenced by TOC/XML")
        for path in report["missing_files"]:
            lines.append(f"- {path}")

    return "\n".join(lines)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Audit a WoW addon for Ace3 TOC/XML load order, vendored libraries, "
            "local Lua library usage, and common feature patterns."
        )
    )
    parser.add_argument(
        "addon_root",
        nargs="?",
        default=".",
        help="Path to the addon root directory. Defaults to the current directory.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Emit machine-readable JSON instead of text.",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    root = Path(args.addon_root).resolve()

    if not root.exists():
        print(f"Addon root does not exist: {root}", file=sys.stderr)
        return 1

    report = build_report(root)

    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(render_text(report))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
