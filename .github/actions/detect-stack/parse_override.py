#!/usr/bin/env python3
"""Read a project's .github/ci.yml override and emit shell assignments.

Deliberately not PyYAML: the override schema is a small, fixed, two-level
subset (documented in docs/OVERRIDES.md) and depending on a package that may
or may not be present on a runner image is exactly the kind of unrelated CI
failure this system exists to avoid.

Unknown keys are ignored rather than fatal, so a newer override file never
breaks an older pinned hub version. A file that cannot be read at all emits
nothing, and detect.sh falls back to auto-detection with a note in the summary.
"""

import re
import shlex
import sys

BOOLS = {"true": "true", "yes": "true", "on": "true",
         "false": "false", "no": "false", "off": "false"}

# override key -> shell variable. Anything not listed here is ignored.
FLAT = {
    ("os-matrix",): "OV_OS_MATRIX",
}
NESTED = {
    ("stacks", "cpp", "enabled"): "OV_CPP_ENABLED",
    ("stacks", "cpp", "root"): "OV_CPP_ROOT",
    ("stacks", "cpp", "build-system"): "OV_CPP_BUILD_SYSTEM",
    ("stacks", "dotnet", "enabled"): "OV_DOTNET_ENABLED",
    ("stacks", "dotnet", "project"): "OV_DOTNET_PROJECT",
}

LINE = re.compile(r"^(?P<indent>\s*)(?P<key>[A-Za-z0-9_.-]+)\s*:\s*(?P<value>.*?)\s*$")


def clean(value):
    """Strip comments and surrounding quotes from a scalar."""
    if value and value[0] in "\"'":
        quote = value[0]
        end = value.find(quote, 1)
        if end != -1:
            return value[1:end]
    value = value.split(" #", 1)[0].strip()
    return value


def parse(text):
    """Return {(path,tuple): value} for the documented subset."""
    found = {}
    stack = []  # list of (indent, key)

    for raw in text.splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        m = LINE.match(raw)
        if not m:
            continue  # lists and flow mappings are outside the subset
        indent = len(m.group("indent").expandtabs(2))
        key = m.group("key")
        value = clean(m.group("value"))

        while stack and stack[-1][0] >= indent:
            stack.pop()

        path = tuple(k for _, k in stack) + (key,)
        if value == "":
            stack.append((indent, key))
        else:
            found[path] = value
    return found


def main():
    if len(sys.argv) < 2:
        return 1
    try:
        with open(sys.argv[1], "r", encoding="utf-8") as handle:
            text = handle.read()
    except OSError:
        return 1

    found = parse(text)
    out = []
    for path, var in list(FLAT.items()) + list(NESTED.items()):
        if path not in found:
            continue
        value = found[path]
        if var.endswith("_ENABLED"):
            value = BOOLS.get(value.lower())
            if value is None:
                continue  # not a recognisable boolean; ignore rather than guess
        if value:
            out.append("%s=%s" % (var, shlex.quote(value)))

    # Emitted last so detect.sh can distinguish "parsed, nothing recognised"
    # from "could not parse at all".
    out.append("OV_PARSED=1")
    print("\n".join(out))
    return 0


if __name__ == "__main__":
    sys.exit(main())
