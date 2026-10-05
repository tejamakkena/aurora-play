#!/usr/bin/env python3
"""Grow the committed content library with new, de-duplicated items.

    OPENAI_API_KEY=sk-... python scripts/grow_content.py            # every kind
    OPENAI_API_KEY=sk-... python scripts/grow_content.py herd hot_take --target 400

For each kind it asks the model (OpenAI, then Gemini) for batches of new
items, validates them exactly like the server does, drops anything that
already exists, and appends the rest to games/content_library/<kind>.json
until the kind has --target items (or a batch adds nothing new). Review
the diff and commit it: committed content survives server restarts, which
the runtime pool on a free host does not.

Cost: one batch is ~30 items for a fraction of a cent with gpt-4o-mini.
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault("CONTENT_AUTO_REFILL", "0")

from games import content_service as cs  # noqa: E402
from games import llm_json  # noqa: E402


def grow(kind: str, target: int, max_batches: int) -> int:
    spec = cs.KINDS[kind]
    path = cs.library_path(kind)
    try:
        library = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        library = []
    added = 0
    for _ in range(max_batches):
        if len(cs.all_items(kind)) >= target:
            break
        new = cs.generate(kind, cs.REFILL_BATCH)
        if not new:
            break
        library.extend(spec.dump(i) for i in new)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(library, ensure_ascii=False, indent=1) + "\n",
                        encoding="utf-8")
        cs._items_cache.pop(kind, None)   # re-read the library next time
        added += len(new)
        print(f"  {kind}: +{len(new)} (total {len(cs.all_items(kind))})")
    return added


def main() -> int:
    kinds = [k for k, s in cs.KINDS.items() if s.ask]
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("kinds", nargs="*", metavar="kind",
                        help="kinds to grow (default: all): " + ", ".join(kinds))
    parser.add_argument("--target", type=int, default=300,
                        help="stop once a kind has this many items (default 300)")
    parser.add_argument("--max-batches", type=int, default=10)
    args = parser.parse_args()
    unknown = [k for k in args.kinds if k not in kinds]
    if unknown:
        parser.error(f"unknown kind(s): {', '.join(unknown)}")
    if not llm_json.configured():
        print("Set OPENAI_API_KEY (or GEMINI_API_KEY) first.", file=sys.stderr)
        return 1
    total = 0
    for kind in args.kinds or kinds:
        total += grow(kind, args.target, args.max_batches)
    print(f"Added {total} items. Review with git diff, then commit.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
