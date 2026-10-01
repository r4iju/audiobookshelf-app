#!/usr/bin/env python3
"""Writes the native string tables from the English text the app passes to `l10n`.

English text is the key, so the English table is the identity. Other languages carry the legacy translation from
`strings/<code>.json` only where `legacy-equivalents.json` names a key with the same meaning and the translation is
usable: present, without markup, and with the same `{n}` placeholders. Everything else stays in English.

    python3 apple/Localization/generate.py          # rewrite tables and COVERAGE.md
    python3 apple/Localization/generate.py --check  # fail when they are stale
"""
import json
import pathlib
import re
import sys

LOCALIZATION = pathlib.Path(__file__).resolve().parent
APPLE = LOCALIZATION.parent
REPOSITORY = APPLE.parent
SOURCES = [APPLE / 'App', APPLE / 'Playback', APPLE / 'Diagnostics' / 'Sources', LOCALIZATION / 'Sources', APPLE / 'Export' / 'Sources']
RESOURCES = LOCALIZATION / 'Sources' / 'NativeLocalization' / 'Resources'
TABLE = 'NativeStrings.strings'
# `copy("…")` marks English templates in renderers that receive `NativeStrings.copy` instead of looking text up.
CALL = re.compile(r'(?<![\w.])(?:l10n|strings|copy|NativeStrings\.current)\(')
PLACEHOLDER = re.compile(r'\{\d+\}')


def languages():
    """The legacy selectable languages, in order, with their `.lproj` names from NativeLanguage.swift."""
    source = (LOCALIZATION / 'Sources' / 'NativeLocalization' / 'NativeLanguage.swift').read_text()
    return re.findall(r'\(code: "([^"]+)", name: "[^"]+", localization: "([^"]+)"\)', source)


def literals(expression):
    """String literals in a Swift expression, except operands of comparisons, which are data rather than text."""
    found, index = [], 0
    while (start := expression.find('"', index)) >= 0:
        end, value = start + 1, ''
        while expression[end] != '"':
            if expression[end] == '\\':
                escaped = expression[end + 1]
                if escaped == '(':
                    raise SystemExit(f'Interpolation inside localized text: {expression}')
                value += {'n': '\n', 't': '\t'}.get(escaped, escaped)
                end += 2
            else:
                value += expression[end]
                end += 1
        before, after = expression[:start].rstrip(), expression[end + 1:].lstrip()
        if not (before.endswith(('==', '!=')) or after.startswith(('==', '!='))):
            found.append(value)
        index = end + 1
    return found


def first_argument(text, start):
    """The source of the first argument of the call whose parenthesis opens at `start`."""
    depth, index, quoted = 0, start, False
    while True:
        character = text[index]
        if quoted:
            if character == '\\':
                index += 1
            elif character == '"':
                quoted = False
        elif character == '"':
            quoted = True
        elif character in '([{':
            depth += 1
        elif character in ')]}':
            depth -= 1
            if depth == 0:
                return text[start + 1:index]
        elif character == ',' and depth == 1:
            return text[start + 1:index]
        index += 1


def english_keys():
    keys = set()
    for root in SOURCES:
        for path in sorted(root.rglob('*.swift')) if root.exists() else []:
            text = path.read_text()
            for match in CALL.finditer(text):
                keys.update(literals(first_argument(text, match.end() - 1)))
    dynamic = json.loads((LOCALIZATION / 'dynamic-keys.json').read_text())
    everything = '\n'.join(path.read_text() for root in SOURCES if root.exists() for path in root.rglob('*.swift'))
    for origin, values in dynamic.items():
        for value in values:
            if f'"{value}"' not in everything and f'"{value.lower()}"' not in everything and f' {value.lower()}' not in everything:
                raise SystemExit(f'{origin}: "{value}" no longer appears in the sources')
            keys.add(value)
    return sorted(keys)


def usable(candidate, english):
    return bool(candidate and candidate.strip()) and '<' not in candidate and \
        set(PLACEHOLDER.findall(candidate)) == set(PLACEHOLDER.findall(english))


def escape(value):
    return value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\t', '\\t')


def outputs():
    keys = english_keys()
    mapping = json.loads((LOCALIZATION / 'legacy-equivalents.json').read_text())
    unknown = sorted(set(mapping) - set(keys))
    if unknown:
        raise SystemExit(f'legacy-equivalents.json maps text the app no longer shows: {unknown}')
    english_legacy = json.loads((REPOSITORY / 'strings' / 'en-us.json').read_text())
    missing = sorted(key for key in mapping.values() if key not in english_legacy)
    if missing:
        raise SystemExit(f'legacy-equivalents.json names keys missing from strings/en-us.json: {missing}')
    files, rows = {}, []
    for code, localization in languages():
        if code == 'en-us':
            table = {key: key for key in keys}
        else:
            legacy = json.loads((REPOSITORY / 'strings' / f'{code}.json').read_text())
            table = {english: legacy[key] for english, key in mapping.items() if usable(legacy.get(key, ''), english)}
        body = ''.join(f'"{escape(key)}" = "{escape(table[key])}";\n' for key in sorted(table))
        files[RESOURCES / f'{localization}.lproj' / TABLE] = '/* Generated by apple/Localization/generate.py. */\n' + body
        rows.append((code, localization, len(table)))
    report = ['# Native localization coverage', '',
              'Generated by `apple/Localization/generate.py`. Native screens show {0} distinct texts. {1} of them have a legacy '
              'key with the same meaning (`legacy-equivalents.json`); a language shows a translation only where its legacy '
              'file has a usable value for that key. All other text stays in English, and the Language screen says so.'
              .format(len(keys), len(mapping)), '',
              '| Language | Resources | Translated texts | Share |', '| --- | --- | ---: | ---: |']
    for code, localization, count in rows:
        report.append(f'| `{code}` | `{localization}.lproj` | {count} | {round(100 * count / len(keys))}% |')
    files[LOCALIZATION / 'COVERAGE.md'] = '\n'.join(report) + '\n'
    return files


def main():
    files = outputs()
    if '--check' in sys.argv:
        stale = [str(path.relative_to(REPOSITORY)) for path, content in files.items()
                 if not path.exists() or path.read_text() != content]
        if stale:
            raise SystemExit('Stale localization output, run apple/Localization/generate.py: ' + ', '.join(stale))
        return
    for path, content in files.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
    print(f'Wrote {len(files) - 1} tables and COVERAGE.md')


if __name__ == '__main__':
    main()
