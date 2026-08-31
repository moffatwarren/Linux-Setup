#!/usr/bin/env python3
"""Replace whole lines matching a regex pattern with a given replacement line,
so install.sh can restore live values (audio sinks, monitor name, ...) into a
config file it just overwrote.

Usage:
    replace_line.py <file> <pattern> <replacement> [<pattern> <replacement> ...]

A pattern with an empty replacement is skipped (nothing was captured live).
"""
import re
import sys


def main():
    file_path = sys.argv[1]
    pairs = list(zip(sys.argv[2::2], sys.argv[3::2]))

    with open(file_path, "r", encoding="utf-8") as f:
        lines = f.readlines()

    new_lines = []
    for line in lines:
        replaced = line
        for pattern, replacement in pairs:
            if replacement and re.match(pattern, line):
                replaced = replacement + "\n"
                break
        new_lines.append(replaced)

    with open(file_path, "w", encoding="utf-8") as f:
        f.writelines(new_lines)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        sys.stderr.write(str(e))
