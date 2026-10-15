"""Extract Harding fences from authoritative website Markdown, not generated HTML."""
from pathlib import Path

PAGES = ("website/content/docs.md", "website/content/index.md", "website/content/features.md")


def snippets(root: Path):
    found = {}
    for page in PAGES:
        path = root / page
        if not path.is_file():
            continue
        heading = ""
        fence_counts = {}
        source = None
        key = None
        for line in path.read_text().splitlines(keepends=True):
            stripped = line.strip()
            if source is not None:
                if stripped == "```":
                    found[key] = "".join(source)
                    source = None
                else:
                    source.append(line)
            elif stripped == "```harding":
                count = fence_counts.get(heading, 0) + 1
                fence_counts[heading] = count
                label = heading if count == 1 else f"{heading} [{count}]"
                key = (page, label)
                if key in found:
                    raise ValueError(f"Duplicate Harding fence key: {key}")
                source = []
            elif stripped.startswith("#"):
                heading = stripped.lstrip("#").strip()
        if source is not None:
            raise ValueError(f"Unclosed Harding fence in {page}: {heading}")
    return found
