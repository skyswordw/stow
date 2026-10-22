#!/usr/bin/env python3
"""Builds the GitHub Pages site into _site/.

- website/ is the home page, as is (with {{REPO_URL}} filled in).
- README, ROADMAP, PARITY and DESIGN become pages under docs/, rendered by GitHub's own Markdown API
  (so tables, task lists and anchors look exactly as they do on github.com) and wrapped in a page that
  uses the website's design tokens.

Environment: GITHUB_REPOSITORY ("owner/name") and GITHUB_TOKEN. Locally:

    GITHUB_REPOSITORY=owner/stow GITHUB_TOKEN=$(gh auth token) python3 scripts/build-site.py
"""
import html
import json
import os
import re
import shutil
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "_site"
REPO = os.environ.get("GITHUB_REPOSITORY", "")
TOKEN = os.environ.get("GITHUB_TOKEN", "")
if not REPO:
    sys.exit("GITHUB_REPOSITORY is required (owner/name)")
REPO_URL = f"https://github.com/{REPO}"

# Source → (page, title shown in the nav)
DOCS = {
    "README.md": ("readme.html", "Read me"),
    "ROADMAP.md": ("roadmap.html", "Roadmap"),
    "PARITY.md": ("parity.html", "Feature parity"),
    "DESIGN.md": ("design.html", "Design language"),
}


def render(markdown: str) -> str:
    body = json.dumps({"text": markdown, "mode": "gfm", "context": REPO}).encode()
    request = urllib.request.Request("https://api.github.com/markdown", data=body, method="POST")
    request.add_header("Accept", "application/vnd.github+json")
    request.add_header("X-GitHub-Api-Version", "2022-11-28")
    if TOKEN:
        request.add_header("Authorization", f"Bearer {TOKEN}")
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode()


def fix_links(page: str) -> str:
    """Links between the four documents stay on the site; anything else in the repo goes to GitHub."""
    def repl(match: re.Match) -> str:
        attr, target = match.group(1), match.group(2)
        if re.match(r"^[a-z][a-z0-9+.-]*:|^#|^//", target):
            return match.group(0)
        path, _, anchor = target.partition("#")
        path = path.lstrip("./")
        if path in DOCS:
            new = DOCS[path][0] + (f"#{anchor}" if anchor else "")
        else:
            kind = "tree" if (ROOT / path).is_dir() else "blob"
            new = f"{REPO_URL}/{kind}/main/{path}" + (f"#{anchor}" if anchor else "")
        return f'{attr}="{new}"'

    return re.sub(r'(href|src)="([^"]+)"', repl, page)


def add_heading_ids(page: str) -> str:
    """GitHub's slugs ("Build & run" → "build--run"), so links written for github.com work here."""
    seen: dict[str, int] = {}

    def repl(match: re.Match) -> str:
        level, attrs, inner = match.group(1), match.group(2), match.group(3)
        if " id=" in attrs:
            return match.group(0)
        text = html.unescape(re.sub(r"<[^>]+>", "", inner)).strip().lower()
        slug = re.sub(r"[^\w\- ]", "", text).replace(" ", "-")
        count = seen.get(slug, 0)
        seen[slug] = count + 1
        if count:
            slug = f"{slug}-{count}"
        return f'<h{level} id="{slug}"{attrs}>{inner}</h{level}>'

    # The API adds attributes such as dir="auto" to headings, so match those too and keep them.
    return re.sub(r"<h([1-4])((?:\s[^>]*)?)>(.*?)</h\1>", repl, page, flags=re.S)


TEMPLATE = """<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{title} · Stow</title>
<meta name="color-scheme" content="light dark">
<link rel="icon" type="image/svg+xml" href="../favicon.svg">
<style>
:root {{
  --bg: #fbfaf8; --bg-2: #f3f1ed; --surface: #fff; --ink: #1d1d1f; --ink-2: #5f5f64; --ink-3: #8e8e93;
  --line: rgba(0,0,0,.08); --accent: #d97b2b; --accent-ink: #a8541a; --accent-soft: rgba(217,123,43,.12);
  --glass: rgba(251,250,248,.72);
  --font: -apple-system, BlinkMacSystemFont, "SF Pro Text", system-ui, "Segoe UI", Roboto, sans-serif;
  --display: -apple-system, BlinkMacSystemFont, "SF Pro Display", system-ui, "Segoe UI", Roboto, sans-serif;
  --mono: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
}}
@media (prefers-color-scheme: dark) {{
  :root {{
    --bg: #0e0e0f; --bg-2: #161618; --surface: #1c1c1e; --ink: #f5f5f7; --ink-2: #a8a8ae; --ink-3: #7c7c82;
    --line: rgba(255,255,255,.09); --accent: #f0954a; --accent-ink: #f5a766; --accent-soft: rgba(240,149,74,.14);
    --glass: rgba(14,14,15,.7);
  }}
}}
* {{ box-sizing: border-box; }}
body {{ margin: 0; background: var(--bg); color: var(--ink); font: 16px/1.65 var(--font); -webkit-font-smoothing: antialiased; }}
a {{ color: var(--accent-ink); text-decoration: none; }}
a:hover {{ text-decoration: underline; text-underline-offset: 3px; }}
:focus-visible {{ outline: 2px solid var(--accent); outline-offset: 3px; border-radius: 4px; }}
.nav {{ position: sticky; top: 0; z-index: 10; background: var(--glass); -webkit-backdrop-filter: saturate(180%) blur(20px);
  backdrop-filter: saturate(180%) blur(20px); border-bottom: 1px solid var(--line); }}
.nav-inner {{ max-width: 1100px; margin: 0 auto; padding: 0 16px; height: 56px; display: flex; align-items: center; gap: 24px; }}
.brand {{ display: inline-flex; align-items: center; gap: 9px; font-weight: 700; color: var(--ink); letter-spacing: -.02em; }}
.brand:hover {{ text-decoration: none; }}
.links {{ display: flex; gap: 18px; font-size: 14px; overflow-x: auto; scrollbar-width: none; }}
.links a {{ color: var(--ink-2); white-space: nowrap; }}
.links a[aria-current] {{ color: var(--ink); font-weight: 600; }}
main {{ max-width: 860px; margin: 0 auto; padding: 48px 16px 96px; }}
.markdown-body h1, .markdown-body h2, .markdown-body h3 {{ font-family: var(--display); letter-spacing: -.02em; line-height: 1.2; scroll-margin-top: 72px; }}
.markdown-body h1 {{ font-size: clamp(34px, 5vw, 48px); letter-spacing: -.035em; margin: 0 0 16px; }}
.markdown-body h2 {{ font-size: 28px; margin: 56px 0 12px; padding-top: 8px; }}
.markdown-body h3 {{ font-size: 20px; margin: 32px 0 8px; }}
.markdown-body p, .markdown-body li {{ color: var(--ink-2); }}
.markdown-body strong {{ color: var(--ink); }}
.markdown-body hr {{ border: 0; border-top: 1px solid var(--line); margin: 48px 0; }}
.markdown-body blockquote {{ margin: 0; padding: 12px 18px; border-left: 3px solid var(--accent); background: var(--accent-soft); border-radius: 0 10px 10px 0; }}
.markdown-body code {{ font: .88em var(--mono); background: var(--bg-2); padding: .15em .4em; border-radius: 6px; }}
.markdown-body pre {{ background: var(--bg-2); padding: 16px 18px; border-radius: 12px; overflow-x: auto; }}
.markdown-body pre code {{ background: none; padding: 0; }}
.markdown-body table {{ display: block; overflow-x: auto; border-collapse: collapse; width: 100%; font-size: 14.5px; margin: 16px 0;
  border-radius: 12px; box-shadow: 0 0 0 1px var(--line); }}
.markdown-body th, .markdown-body td {{ padding: 10px 14px; text-align: left; vertical-align: top; border-top: 1px solid var(--line); }}
.markdown-body thead th {{ border-top: 0; background: var(--bg-2); font-size: 12.5px; text-transform: uppercase; letter-spacing: .04em; color: var(--ink-3); }}
.markdown-body td {{ color: var(--ink-2); }}
.markdown-body img {{ max-width: 100%; }}
.markdown-body .anchor {{ display: none; }}
footer {{ border-top: 1px solid var(--line); padding: 28px 16px 48px; text-align: center; font-size: 13px; color: var(--ink-3); }}
</style>
</head>
<body>
<header class="nav">
  <div class="nav-inner">
    <a class="brand" href="../"><img src="../favicon.svg" width="24" height="24" alt="">Stow</a>
    <nav class="links" aria-label="Documents">{nav}<a href="{repo_url}">GitHub</a></nav>
  </div>
</header>
<main class="markdown-body">
{body}
</main>
<footer>Stow is free software under the GPL-3.0 · <a href="{repo_url}/edit/main/{source}">Edit this page</a></footer>
</body>
</html>
"""


def main() -> None:
    if OUT.exists():
        shutil.rmtree(OUT)
    shutil.copytree(ROOT / "website", OUT)
    index = OUT / "index.html"
    index.write_text(index.read_text().replace("{{REPO_URL}}", REPO_URL))

    docs = OUT / "docs"
    docs.mkdir()
    for source, (page, title) in DOCS.items():
        current = ' aria-current="page"'
        nav = "".join(
            f'<a href="{p}"{current if p == page else ""}>{html.escape(t)}</a>' for p, t in DOCS.values()
        )
        body = add_heading_ids(fix_links(render((ROOT / source).read_text())))
        (docs / page).write_text(TEMPLATE.format(title=html.escape(title), nav=nav, body=body,
                                                 repo_url=REPO_URL, source=source))
        print(f"docs/{page}")
    (OUT / ".nojekyll").write_text("")
    print(f"built {OUT}")


if __name__ == "__main__":
    main()
