"""Extract Harding fences from authoritative website Markdown, not generated HTML."""
from pathlib import Path

# Start with the getting-started page and landing-page example. Features and
# tutorial fragments require their own fixtures/host dependencies in a later slice.
PAGES = ("website/content/docs.md", "website/content/index.md")


def snippets(root: Path):
    found = {}
    for page in PAGES:
        path = root / page
        if not path.is_file():
            continue
        heading = ""
        source = None
        key = None
        for line in path.read_text().splitlines(keepends=True):
            stripped = line.strip()
            if source is not None:
                if stripped == "```":
                    if key in found:
                        raise ValueError(f"Duplicate Harding fence: {key}")
                    found[key] = "".join(source)
                    source = None
                else:
                    source.append(line)
            elif stripped == "```harding":
                key = (page, heading)
                source = []
            elif stripped.startswith("#"):
                heading = stripped.lstrip("#").strip()
        if source is not None:
            raise ValueError(f"Unclosed Harding fence in {page}: {heading}")
    return found
