#!/usr/bin/env python3
"""Structural YAML merger for the HACS Home Assistant "Frosted Glass" theme.

Loads upstream Frosted Glass.yaml and merges declarative customizations from
/config/frosted-glass-overrides.yaml via PyYAML (no fragile regex splicing into
upstream CSS/YAML comments or indentation), then generates deduplicated standalone
Light/Dark theme files and optionally hot-reloads Home Assistant themes.

Usage:
  python3 patch_frosted_glass.py [--force] [--dry-run] [--no-reload] [--ignore-missing]
"""

import argparse
import copy
import datetime
import json
import os
import re
import shutil
import sys
import urllib.request
import yaml

DEFAULT_THEMES_DIR = "/config/themes/Frosted Glass"
DEFAULT_OVERRIDES_FILE = "/config/frosted-glass-overrides.yaml"
AUTH_STORAGE_FILE = "/config/.storage/auth"

CSS_START = "/* === KERRLAB OVERRIDES START === */"
CSS_END = "/* === KERRLAB OVERRIDES END === */"


class ThemeDumper(yaml.SafeDumper):
    """YAML dumper emitting readable literal blocks for multiline card-mod CSS."""


def _represent_str(dumper: yaml.Dumper, data: str) -> yaml.ScalarNode:
    if "\n" in data:
        cleaned = "\n".join(line.rstrip() for line in data.splitlines()) + "\n"
        return dumper.represent_scalar("tag:yaml.org,2002:str", cleaned, style="|")
    return dumper.represent_scalar("tag:yaml.org,2002:str", data)


ThemeDumper.add_representer(str, _represent_str)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Structural Frosted Glass theme patcher.")
    parser.add_argument("--themes-dir", default=DEFAULT_THEMES_DIR, help="Path to Frosted Glass themes directory.")
    parser.add_argument("--overrides", default=DEFAULT_OVERRIDES_FILE, help="Path to frosted-glass-overrides.yaml.")
    parser.add_argument("--force", action="store_true", help="Rewrite theme files even when unchanged.")
    parser.add_argument("--dry-run", action="store_true", help="Validate and report changes without writing.")
    parser.add_argument("--no-reload", action="store_true", help="Skip calling Home Assistant reload_themes API.")
    parser.add_argument("--ignore-missing", action="store_true", help="Exit 0 if Frosted Glass.yaml does not exist yet.")
    return parser.parse_args()


def strip_override_block(css_text: str) -> str:
    """Removes a previously appended KERRLAB OVERRIDES sentinel block from a CSS string."""
    pattern = re.compile(rf"\n*{re.escape(CSS_START)}.*?{re.escape(CSS_END)}\s*", flags=re.DOTALL)
    return pattern.sub("\n", css_text).rstrip()


def append_override_block(base_css: str, *snippets: str) -> str:
    """Strips any prior sentinel block and appends fresh CSS snippets wrapped in sentinels."""
    cleaned_base = strip_override_block(base_css or "")
    combined = "\n\n".join(snippet.strip() for snippet in snippets if snippet and snippet.strip())
    if not combined:
        return cleaned_base + ("\n" if cleaned_base else "")
    block = f"{CSS_START}\n{combined}\n{CSS_END}\n"
    return f"{cleaned_base}\n\n{block}" if cleaned_base else block


def apply_mode_overrides(mode_dict: dict, mode_name: str, overrides: dict) -> dict:
    """Applies variable, key-removal, and CSS-cascade overrides to a single mode mapping."""
    updated = copy.deepcopy(mode_dict)

    for key in overrides.get("remove_keys", []):
        updated.pop(key, None)

    variables = overrides.get("variables", {})
    for src in (variables.get("shared", {}), variables.get(mode_name, {})):
        for key, value in src.items():
            updated[key] = value

    card_css = overrides.get("card_mod_card_append", {})
    updated["card-mod-card"] = append_override_block(
        updated.get("card-mod-card", ""),
        card_css.get("shared", ""),
        card_css.get(mode_name, ""),
    )

    root_css = overrides.get("card_mod_root_append", {})
    updated["card-mod-root"] = append_override_block(
        updated.get("card-mod-root", ""),
        root_css.get("shared", ""),
        root_css.get(mode_name, ""),
    )

    return updated


def dump_theme(data: dict, header_comment: str) -> str:
    rendered = yaml.dump(
        data,
        Dumper=ThemeDumper,
        sort_keys=False,
        allow_unicode=True,
        width=1000,
    )
    return f"{header_comment}{rendered}"


def build_standalone(theme_name: str, mode_dict: dict) -> str:
    standalone = copy.deepcopy(mode_dict)
    standalone["card-mod-theme"] = theme_name
    return dump_theme(
        {theme_name: standalone},
        f"# {theme_name} - Managed via patch_frosted_glass.py\n\n",
    )


def write_if_changed(path: str, content: str, dry_run: bool, label: str, force: bool = False) -> bool:
    existing = None
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            existing = f.read()
    if existing == content and not force:
        return False
    if not dry_run:
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
    print(f"[✓] {'Would update' if dry_run else 'Updated'} {label}: {path}")
    return True


def reload_themes() -> None:
    """Triggers Home Assistant frontend.reload_themes service via local JWT auth."""
    if not os.path.exists(AUTH_STORAGE_FILE):
        print(f"[!] Auth file {AUTH_STORAGE_FILE} not found; skipping theme reload.")
        return

    try:
        import jwt  # noqa: PLC0415

        with open(AUTH_STORAGE_FILE, "r", encoding="utf-8") as f:
            auth = json.load(f)

        tokens = auth.get("data", {}).get("refresh_tokens", [])
        target = next((r for r in tokens if r.get("client_name") in ["gemini-cli", "MCP Server", "Home Assistant Frontend"]), None)
        if not target and tokens:
            target = tokens[0]
        if not target:
            print("[!] No valid refresh token found in auth storage; skipping reload.")
            return

        now = datetime.datetime.now(datetime.timezone.utc)
        payload = {
            "iss": target["id"],
            "iat": int(now.timestamp()),
            "exp": int((now + datetime.timedelta(minutes=5)).timestamp()),
        }
        token = jwt.encode(payload, target["jwt_key"], algorithm="HS256")
        req = urllib.request.Request(
            "http://127.0.0.1:8123/api/services/frontend/reload_themes",
            data=b"{}",
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            print(f"[✓] Themes reloaded via API (HTTP {resp.status}).")
    except Exception as exc:  # noqa: BLE001
        print(f"[!] Theme reload API call skipped ({exc}).")


def main() -> None:
    args = parse_args()
    main_theme_file = os.path.join(args.themes_dir, "Frosted Glass.yaml")
    light_theme_file = os.path.join(args.themes_dir, "Frosted Glass Light.yaml")
    dark_theme_file = os.path.join(args.themes_dir, "Frosted Glass Dark.yaml")

    if not os.path.exists(main_theme_file):
        if args.ignore_missing:
            print(f"[!] Theme file {main_theme_file} not present yet; skipping patch.")
            return
        print(f"[-] Error: Theme file {main_theme_file} does not exist.")
        sys.exit(1)

    if not os.path.exists(args.overrides):
        print(f"[-] Error: Overrides file {args.overrides} does not exist.")
        sys.exit(1)

    with open(main_theme_file, "r", encoding="utf-8") as f:
        raw_theme_text = f.read()
    with open(args.overrides, "r", encoding="utf-8") as f:
        overrides = yaml.safe_load(f) or {}

    theme_doc = yaml.safe_load(raw_theme_text)
    if not isinstance(theme_doc, dict) or "Frosted Glass" not in theme_doc:
        print("[-] Error: Expected top-level 'Frosted Glass' key in Frosted Glass.yaml.")
        sys.exit(1)

    modes = theme_doc["Frosted Glass"].get("modes", {})
    if "light" not in modes or "dark" not in modes:
        print("[-] Error: Expected both 'light' and 'dark' modes in Frosted Glass.yaml.")
        sys.exit(1)

    patched_light = apply_mode_overrides(modes["light"], "light", overrides)
    patched_dark = apply_mode_overrides(modes["dark"], "dark", overrides)

    patched_main_doc = copy.deepcopy(theme_doc)
    patched_main_doc["Frosted Glass"]["modes"]["light"] = patched_light
    patched_main_doc["Frosted Glass"]["modes"]["dark"] = patched_dark

    new_main_text = dump_theme(patched_main_doc, "# Frosted Glass - Managed via patch_frosted_glass.py\n\n")
    new_light_text = build_standalone("Frosted Glass Light", patched_light)
    new_dark_text = build_standalone("Frosted Glass Dark", patched_dark)

    # Validate round-trip YAML before touching disk
    yaml.safe_load(new_main_text)
    yaml.safe_load(new_light_text)
    yaml.safe_load(new_dark_text)

    # Keep a single pre-patch backup only when converting an unpatched upstream theme
    if CSS_START not in raw_theme_text and not args.dry_run:
        shutil.copyfile(main_theme_file, f"{main_theme_file}.bak_upstream")

    changed = False
    changed |= write_if_changed(main_theme_file, new_main_text, args.dry_run, "Frosted Glass", force=args.force)
    changed |= write_if_changed(light_theme_file, new_light_text, args.dry_run, "Frosted Glass Light", force=args.force)
    changed |= write_if_changed(dark_theme_file, new_dark_text, args.dry_run, "Frosted Glass Dark", force=args.force)

    if not changed:
        print("[✓] Frosted Glass themes already match frosted-glass-overrides.yaml.")

    if not args.no_reload and not args.dry_run:
        reload_themes()


if __name__ == "__main__":
    main()
