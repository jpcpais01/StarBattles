"""Builds the GitHub release body (Markdown) from data/patch_notes.json.

The newest group goes first; older groups follow under "Earlier updates" so
the in-game updater can show what changed since any older build.
"""
import json
import sys

MAX_GROUPS = 4


def main() -> None:
    with open("data/patch_notes.json", encoding="utf-8") as f:
        groups = json.load(f).get("groups", [])
    out = []
    for i, g in enumerate(groups[:MAX_GROUPS]):
        if i == 1:
            out.append("")
            out.append("### Earlier updates")
        out.append(("## " if i == 0 else "**") + g.get("title", "Update") + ("" if i == 0 else "**"))
        for e in g.get("entries", []):
            out.append(f"- {e}")
        out.append("")
    sys.stdout.write("\n".join(out).strip() + "\n")


if __name__ == "__main__":
    main()
