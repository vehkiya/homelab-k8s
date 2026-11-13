#!/usr/bin/env python3
"""Idempotent customizer for the HACS Home Assistant "Frosted Glass" theme.

Re-applies our local customizations on top of upstream HACS Frosted Glass theme
updates without storing forked full-theme YAML files in GitOps:
  1. Removes unused uix-theme and legacy card-mod-view-yaml / CARDS RADIUS overrides
  2. Applies pill radii (32px cards, 20px sub-buttons, 50% icons, 28px navbar/ha-card)
  3. Sets Milky Frost backdrop filter, less-muted card glass tint, and popup blur
  4. Points light/dark background-image URLs to local ambient BPR wallpapers
  5. Preserves active slider card glass rim shine (::after z-index: 2, range-fill 0.48)
  6. Adds frosted pill styling for Bubble Card horizontal-buttons-stack
  7. Excludes Bubble Card separators cleanly (preserving centered pill_separator layout)
  8. Moves the HA header bar to the bottom on other views while hiding it on mobile-dashboard
  9. Regenerates deduplicated standalone "Frosted Glass Light" and "Frosted Glass Dark" themes
 10. Optionally hot-reloads Home Assistant themes via local auth API

Usage:
  python3 patch_frosted_glass.py [--force] [--dry-run] [--no-reload] [--ignore-missing]
"""

import argparse
import datetime
import json
import os
import re
import shutil
import sys
import urllib.request
import yaml

DEFAULT_THEMES_DIR = "/config/themes/Frosted Glass"
AUTH_STORAGE_FILE = "/config/.storage/auth"

INJECTED_BUBBLE_CSS = """
        /* Render glass rim shine above slider fill so active/on cards keep their specular edge */
        .bubble-container:not(.bubble-separator)::after {
          content: '';
          position: absolute;
          inset: 0;
          border-radius: inherit;
          pointer-events: none;
          background: transparent;
          box-shadow: var(--ha-card-glass-inset-shadow);
          z-index: 2;
        }
        .bubble-range-fill {
          opacity: 0.48 !important;
          background-image: linear-gradient(180deg, rgba(255, 255, 255, 0.14) 0%, rgba(255, 255, 255, 0.02) 50%, rgba(0, 0, 0, 0.06) 100%) !important;
        }

        /* Horizontal Buttons Stack: higher-opacity frosted glass pills */
        .horizontal-buttons-stack-container .bubble-button .bubble-background {
          opacity: 1 !important;
          background: color-mix(in srgb, var(--frosted-glass-menu-surface, var(--card-background-color)) 62%, transparent) !important;
          backdrop-filter: blur(18px) saturate(1.35) contrast(var(--frosted-glass-contrast, 1)) !important;
          -webkit-backdrop-filter: blur(18px) saturate(1.35) contrast(var(--frosted-glass-contrast, 1)) !important;
          box-shadow: var(--ha-card-glass-inset-shadow), var(--frosted-glass-card-depth-shadow) !important;
        }
        .horizontal-buttons-stack-container .bubble-button .bubble-background-color {
          border: var(--bubble-border, var(--ha-card-border)) !important;
        }
        .horizontal-buttons-stack-container .bubble-button.highlight {
          animation: none !important;
        }
        .horizontal-buttons-stack-container .bubble-button.highlight .bubble-background {
          background: color-mix(in srgb, var(--bubble-accent-color) 30%, color-mix(in srgb, var(--frosted-glass-menu-surface, var(--card-background-color)) 68%, transparent)) !important;
        }
        .horizontal-buttons-stack-container .bubble-button.highlight .bubble-background-color {
          border: 1px solid color-mix(in srgb, var(--bubble-accent-color) 70%, transparent) !important;
        }

        /* Exclude separators from glass background and pseudo-element */
        :host(.type-custom-bubble-card) .bubble-separator,
        .bubble-separator,
        .bubble-container.bubble-separator {
          background: none !important;
          box-shadow: none !important;
          backdrop-filter: none !important;
          -webkit-backdrop-filter: none !important;
          border: none !important;
        }
        .bubble-separator::before,
        .bubble-container.bubble-separator::before {
          box-shadow: none !important;
          backdrop-filter: none !important;
          -webkit-backdrop-filter: none !important;
        }

        /* Performance preservation: prevent sub-button/icon nested blur lag */
        :host(.type-custom-bubble-card) .bubble-sub-button {
          border-radius: var(--bubble-sub-button-border-radius, 20px) !important;
          backdrop-filter: none !important;
          -webkit-backdrop-filter: none !important;
        }
        :host(.type-custom-bubble-card) .bubble-icon-container {
          border-radius: var(--bubble-icon-border-radius, 50%) !important;
          backdrop-filter: none !important;
          -webkit-backdrop-filter: none !important;
        }"""

LEGACY_HOST_TOKEN_KEYS = (
    "--ha-card-border-radius",
    "--ha-border-radius-card",
    "--ha-border-radius-large",
    "--bubble-border-radius",
    "--bubble-button-border-radius",
    "--bubble-card-type-border-radius",
    "--bubble-sub-button-border-radius",
    "--bubble-icon-border-radius",
    "--bubble-horizontal-buttons-stack-border-radius",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Idempotent customizer for Frosted Glass theme.")
    parser.add_argument("--themes-dir", default=DEFAULT_THEMES_DIR, help="Path to Frosted Glass themes directory.")
    parser.add_argument("--force", action="store_true", help="Write patched files even when main theme is unchanged.")
    parser.add_argument("--dry-run", action="store_true", help="Simulate changes without writing to disk.")
    parser.add_argument("--no-reload", action="store_true", help="Skip calling Home Assistant reload_themes API.")
    parser.add_argument("--ignore-missing", action="store_true", help="Exit 0 if Frosted Glass.yaml does not exist yet.")
    return parser.parse_args()


def set_yaml_var(text: str, key: str, quoted_value: str) -> str:
    """Replaces an existing 6-space indented YAML variable inside a mode block."""
    return re.sub(
        rf"^( {{6}}{re.escape(key)}:\s*).*$",
        rf"\g<1>{quoted_value}",
        text,
        flags=re.MULTILINE,
    )


def ensure_yaml_var_after(text: str, after_key: str, key: str, quoted_value: str) -> str:
    """Ensures a 6-space mode YAML variable exists, updating or inserting after after_key."""
    if re.search(rf"^ {{6}}{re.escape(key)}:", text, flags=re.MULTILINE):
        return set_yaml_var(text, key, quoted_value)
    return re.sub(
        rf"^( {{6}})({re.escape(after_key)}:\s*.*)$",
        rf"\1\2\n\1{key}: {quoted_value}",
        text,
        count=1,
        flags=re.MULTILINE,
    )


def patch_mode_variables(text: str, is_dark: bool) -> str:
    """Updates theme variables for pill radii, Milky Frost blur/tint, and local BPR wallpapers."""
    text = re.sub(r"^ {6}uix-theme:.*\n", "", text, flags=re.MULTILINE)

    text = set_yaml_var(text, "bubble-border-radius", "'32px'")
    text = ensure_yaml_var_after(text, "bubble-border-radius", "bubble-button-border-radius", "'32px'")
    text = ensure_yaml_var_after(text, "bubble-button-border-radius", "bubble-card-type-border-radius", "'32px'")
    text = set_yaml_var(text, "bubble-icon-border-radius", "'50%'")
    text = set_yaml_var(text, "bubble-sub-button-border-radius", "'20px'")
    text = set_yaml_var(text, "bubble-horizontal-buttons-stack-border-radius", "'32px'")
    text = set_yaml_var(text, "navbar-border-radius", "'28px'")
    text = set_yaml_var(text, "ha-card-border-radius", "'28px'")
    text = set_yaml_var(text, "border-radius", "'28px'")

    tint = "'rgba(22, 30, 44, 0.26)'" if is_dark else "'rgba(254, 244, 242, 0.24)'"
    wallpaper = (
        '"center / cover no-repeat fixed url(\'/local/themes/frosted-glass-dark-bpr.jpg\')"'
        if is_dark
        else '"center / cover no-repeat fixed url(\'/local/themes/frosted-glass-light-bpr.jpg\')"'
    )

    text = set_yaml_var(
        text,
        "ha-card-backdrop-filter",
        "'blur(22px) saturate(1.55) contrast(var(--frosted-glass-contrast, 1))'",
    )
    text = set_yaml_var(text, "ha-card-glass-tint", tint)
    text = set_yaml_var(text, "frosted-glass-popup-backdrop-filter", "'blur(24px) saturate(1.3)'")
    text = set_yaml_var(text, "background-image", wallpaper)
    return text


def patch_card_mod_card(text: str) -> str:
    """Patches Bubble Card container/before/after, range-fill, horizontal-buttons-stack, and separator CSS."""
    # Scope .bubble-container and ensure pill border-radius
    text = re.sub(
        r"(\n[ \t]*)\.bubble-container\s*\{([^}]*)\}",
        lambda m: (
            f"{m.group(1)}.bubble-container:not(.bubble-separator) {{"
            + (
                m.group(2)
                if "border-radius:" in m.group(2)
                else m.group(2).rstrip() + "\n          border-radius: var(--bubble-border-radius, 32px) !important;\n        "
            )
            + "}"
        ),
        text,
        count=1,
    )

    # Keep .bubble-background transparent everywhere except horizontal-buttons-stack pills
    text = re.sub(
        r"(\n[ \t]*)\.bubble-background\s*\{([^}]*)\}",
        r"\1.bubble-background:not(.horizontal-buttons-stack-container .bubble-background) {\2}",
        text,
        count=1,
    )

    # Scope .bubble-container::before, move inset shadow to ::after, and ensure glass tint background
    def update_bubble_before(match: re.Match) -> str:
        prefix = match.group(1)
        body = match.group(2)
        body = re.sub(r"\n[ \t]*box-shadow:\s*var\(--ha-card-glass-inset-shadow\);", "", body)
        if "background: var(--ha-card-glass-tint);" not in body:
            body = re.sub(
                r"(\n[ \t]*backdrop-filter:)",
                r"\n          background: var(--ha-card-glass-tint);\1",
                body,
                count=1,
            )
        return f"{prefix}.bubble-container:not(.bubble-separator)::before {{{body}}}"

    text = re.sub(
        r"(\n[ \t]*)\.bubble-container(?::not\(\.bubble-separator\))?::before\s*\{([^}]*)\}",
        update_bubble_before,
        text,
        count=1,
    )

    # Strip any older/existing custom Bubble Card suffix blocks before inserting canonical INJECTED_BUBBLE_CSS
    stop_lookahead = r"(?=\n*[ \t]*(?:/\* Transparent Hue surfaces|:host\(hue-like-light-card\)|# )|\Z)"
    for marker in (
        r"/\* Render glass rim shine above slider fill",
        r"/\* Horizontal Buttons Stack:",
        r"/\* Exclude separators from glass background and pseudo-element \*/",
    ):
        text = re.sub(rf"\n*[ \t]*{marker}.*?{stop_lookahead}", "", text, flags=re.DOTALL)

    anchor = re.search(r"\.bubble-container:not\(\.bubble-separator\)::before\s*\{[^}]*\}", text)
    if anchor:
        rest = text[anchor.end():].lstrip("\n")
        text = text[:anchor.end()] + "\n" + INJECTED_BUBBLE_CSS.strip("\n") + "\n\n" + rest

    return text


def build_bottom_navbar_css(is_dark: bool) -> str:
    shadow = "0 -4px 20px rgba(0, 0, 0, 0.35) !important;" if is_dark else "0 -4px 20px rgba(0, 0, 0, 0.15) !important;"
    border = (
        "0.5px solid var(--ha-card-border-color, rgba(255, 255, 255, 0.15)) !important;"
        if is_dark
        else "0.5px solid var(--ha-card-border-color, rgba(255, 255, 255, 0.3)) !important;"
    )
    return f"""

        /* =========================
           BOTTOM NAVIGATION BAR
           ========================= */
        .header,
        app-header {{
          top: auto !important;
          bottom: 0 !important;
          position: fixed !important;
          left: var(--ha-sidebar-width, 0px) !important;
          right: 0 !important;
          width: calc(var(--ha-top-app-bar-width, 100%) - var(--safe-area-inset-right, 0px)) !important;
          box-sizing: border-box !important;
          transition: left var(--ha-animation-duration-normal, 250ms) ease, width var(--ha-animation-duration-normal, 250ms) ease !important;
          padding-top: 0px !important;
          padding-bottom: env(safe-area-inset-bottom, 0px) !important;
          box-shadow: {shadow}
          border-top: {border}
        }}

        .narrow .header {{
          left: var(--ha-sidebar-width, 0px) !important;
          width: calc(var(--ha-top-app-bar-width, 100%) - var(--safe-area-inset-left, 0px) - var(--safe-area-inset-right, 0px)) !important;
          padding-left: var(--safe-area-inset-left) !important;
        }}

        .edit-mode .header {{
          top: 0 !important;
          bottom: auto !important;
          padding-top: env(safe-area-inset-top, 0px) !important;
          padding-bottom: 0px !important;
          border-top: none !important;
        }}

        #view,
        hui-view-container,
        hui-view-container.has-tab-bar,
        ha-app-layout {{
          padding-top: calc(env(safe-area-inset-top, 0px) + var(--view-container-padding-top, 8px)) !important;
          padding-bottom: calc(var(--header-height, 56px) + env(safe-area-inset-bottom, 0px) + 20px) !important;
        }}

        .edit-mode #view,
        .edit-mode hui-view-container {{
          padding-top: calc(var(--header-height, 56px) + var(--tab-bar-height, 56px) + env(safe-area-inset-top, 0px)) !important;
          padding-bottom: env(safe-area-inset-bottom, 0px) !important;
        }}

        /* Hide bottom navbar on mobile-dashboard (replaced by Bubble Card horizontal-buttons-stack),
           while keeping edit-mode toolbar and other dashboards intact. */
        div:not(.edit-mode) > .header:has(ha-tab-group ha-tab-group-tab:nth-of-type(6)),
        div:not(.edit-mode) > .header:has(ha-icon[title="Hallway"]) {{
          display: none !important;
        }}

        div:not(.edit-mode):has(> .header ha-tab-group ha-tab-group-tab:nth-of-type(6)) > #view,
        div:not(.edit-mode):has(> .header ha-icon[title="Hallway"]) > #view {{
          padding-bottom: env(safe-area-inset-bottom, 0px) !important;
        }}"""


def patch_card_mod_root(text: str, is_dark: bool) -> str:
    """Updates :host radius tokens and replaces any legacy CARDS RADIUS / BOTTOM NAVIGATION BAR blocks."""
    text = re.sub(r"--token-size-radius-small:\s*\d+px;", "--token-size-radius-small: 12px;", text)
    text = re.sub(r"--token-size-radius-medium:\s*\d+px;", "--token-size-radius-medium: 18px;", text)
    text = re.sub(r"--token-size-radius-large:\s*\d+px;", "--token-size-radius-large: 28px;", text)

    # Remove duplicate host radius tokens left by earlier patch versions
    for token_key in LEGACY_HOST_TOKEN_KEYS:
        text = re.sub(rf"\n[ \t]*{re.escape(token_key)}:[^\n]*;", "", text)

    # Remove legacy CARDS RADIUS block and any existing BOTTOM NAVIGATION BAR block cleanly
    text = re.sub(
        r"\n*[ \t]*/\* CARDS RADIUS \*/.*?ha-card ha-card\s*\{[^}]*\}",
        "",
        text,
        flags=re.DOTALL,
    )
    text = re.sub(
        r"\n*[ \t]*/\* =========================\n[ \t]*BOTTOM NAVIGATION BAR\n[ \t]*========================= \*/.*?(?=\n*[ \t]*# =========================\n[ \t]*# TYPOGRAPHY|\Z)",
        "",
        text,
        flags=re.DOTALL,
    )

    bottom_navbar_css = build_bottom_navbar_css(is_dark)
    host_close = re.search(r"(card-mod-root:\s*\|.*?:host\s*\{.*?\n)([ \t]*\}\n)", text, flags=re.DOTALL)
    if host_close:
        rest = text[host_close.end():].lstrip("\n")
        text = text[:host_close.end()] + "\n" + bottom_navbar_css.strip("\n") + "\n\n" + rest
    return text


def remove_legacy_card_mod_view(text: str) -> str:
    """Removes legacy card-mod-view-yaml block if present from older patch versions."""
    return re.sub(
        r"\n*[ \t]*# =========================\n[ \t]*# SECTIONS VIEW \(Card-Mod View\)\n[ \t]*# =========================\n[ \t]*card-mod-view-yaml:.*?(?=\n {6}[a-zA-Z0-9_-]+:|\n {6}# |\Z)",
        "",
        text,
        flags=re.DOTALL,
    )


def process_mode_block(mode_text: str, is_dark: bool) -> str:
    text = patch_mode_variables(mode_text, is_dark=is_dark)
    text = patch_card_mod_card(text)
    text = patch_card_mod_root(text, is_dark=is_dark)
    text = remove_legacy_card_mod_view(text)
    return text


def dedent_mode_lines(raw_lines: list[str]) -> list[str]:
    """Converts 6-space mode entries from Frosted Glass.yaml into 2-space standalone theme entries."""
    out = []
    for line in raw_lines:
        stripped = line.strip()
        if stripped.startswith("card-mod-theme:") or stripped.startswith("uix-theme:"):
            continue
        if line.startswith("    "):
            out.append(line[4:])
        elif stripped == "":
            out.append("\n")
        else:
            out.append(line)
    return out


def generate_standalone(theme_name: str, quote_char: str, raw_lines: list[str], version_line: str) -> str:
    header = [
        f"# {theme_name}\n",
        version_line,
        "\n",
        f"{theme_name}:\n",
        f"  card-mod-theme: {quote_char}{theme_name}{quote_char}\n",
    ]
    body = "".join(dedent_mode_lines(raw_lines)).strip("\n") + "\n"
    return "".join(header) + body


def write_if_changed(path: str, content: str, dry_run: bool, label: str) -> bool:
    existing = None
    if os.path.exists(path):
        with open(path, "r", encoding="utf-8") as f:
            existing = f.read()
    if existing == content:
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

    with open(main_theme_file, "r", encoding="utf-8") as f:
        original_content = f.read()

    lines = original_content.splitlines(keepends=True)
    light_idx = next((i for i, line in enumerate(lines) if line.strip() == "light:"), None)
    dark_idx = next((i for i, line in enumerate(lines) if line.strip() == "dark:"), None)

    if light_idx is None or dark_idx is None or dark_idx <= light_idx:
        print("[-] Error: Could not locate 'light:' and 'dark:' mode blocks in theme file.")
        sys.exit(1)

    header_lines = lines[:light_idx + 1]
    version_line = next((line for line in header_lines if line.lstrip().startswith("# ver.")), "# ver. 1.4.0\n")
    light_text = "".join(lines[light_idx + 1:dark_idx])
    dark_text = "".join(lines[dark_idx + 1:])

    new_light_text = process_mode_block(light_text, is_dark=False)
    new_dark_text = process_mode_block(dark_text, is_dark=True)

    new_full_content = (
        "".join(header_lines)
        + new_light_text.rstrip()
        + "\n\n"
        + lines[dark_idx].lstrip("\n")
        + new_dark_text.strip("\n")
        + "\n"
    )

    try:
        yaml.safe_load(new_full_content)
    except yaml.YAMLError as exc:
        print(f"[-] Error: Patched Frosted Glass YAML failed validation: {exc}")
        sys.exit(1)

    light_standalone = generate_standalone("Frosted Glass Light", '"', new_light_text.splitlines(keepends=True), version_line)
    dark_standalone = generate_standalone("Frosted Glass Dark", "'", new_dark_text.splitlines(keepends=True), version_line)

    try:
        yaml.safe_load(light_standalone)
        yaml.safe_load(dark_standalone)
    except yaml.YAMLError as exc:
        print(f"[-] Error: Generated standalone YAML failed validation: {exc}")
        sys.exit(1)

    if new_full_content == original_content and not args.force:
        print("[✓] Frosted Glass.yaml already contains all patches.")
    else:
        if not args.dry_run:
            timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            backup_path = f"{main_theme_file}.bak_{timestamp}"
            shutil.copyfile(main_theme_file, backup_path)
            with open(main_theme_file, "w", encoding="utf-8") as f:
                f.write(new_full_content)
            print(f"[✓] Backed up to {backup_path} and patched {main_theme_file}")
        else:
            print(f"[✓] Dry run: would patch {main_theme_file}")

    write_if_changed(light_theme_file, light_standalone, args.dry_run, "Frosted Glass Light")
    write_if_changed(dark_theme_file, dark_standalone, args.dry_run, "Frosted Glass Dark")

    if not args.no_reload and not args.dry_run:
        reload_themes()


if __name__ == "__main__":
    main()
