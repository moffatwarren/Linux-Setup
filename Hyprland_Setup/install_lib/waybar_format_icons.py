#!/usr/bin/env python3
"""Get or set the "pulseaudio".format-icons block in a waybar config, so
install.sh can preserve the live value across a config overwrite.

Usage:
    waybar_format_icons.py get <config_file>
    waybar_format_icons.py set <config_file> <new_value>
"""
import re
import sys


def find_format_icons_span(content):
    pulse_match = re.search(r'"pulseaudio"\s*:\s*\{', content)
    if not pulse_match:
        return None

    start_idx = pulse_match.end() - 1
    brace_count = 0
    end_idx = -1
    for i in range(start_idx, len(content)):
        if content[i] == "{":
            brace_count += 1
        elif content[i] == "}":
            brace_count -= 1
            if brace_count == 0:
                end_idx = i + 1
                break
    if end_idx == -1:
        return None

    pulse_block = content[start_idx:end_idx]
    icons_match = re.search(r'"format-icons"\s*:\s*([{\[])', pulse_block)
    if not icons_match:
        return None

    open_char = icons_match.group(1)
    close_char = "}" if open_char == "{" else "]"
    icons_start_idx = start_idx + icons_match.start()
    count = 0
    icons_end_idx = -1
    for i in range(start_idx + icons_match.end() - 1, len(content)):
        if content[i] == open_char:
            count += 1
        elif content[i] == close_char:
            count -= 1
            if count == 0:
                icons_end_idx = i + 1
                break
    if icons_end_idx == -1:
        return None

    return icons_start_idx, icons_end_idx


def main():
    mode = sys.argv[1]
    file_path = sys.argv[2]

    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read()

    span = find_format_icons_span(content)

    if mode == "get":
        if span:
            sys.stdout.write(content[span[0]:span[1]])
    elif mode == "set":
        new_value = sys.argv[3]
        if span and new_value:
            new_content = content[:span[0]] + new_value + content[span[1]:]
            with open(file_path, "w", encoding="utf-8") as f:
                f.write(new_content)
    else:
        raise ValueError(f"unknown mode: {mode}")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        sys.stderr.write(str(e))
