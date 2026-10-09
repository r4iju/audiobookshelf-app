#!/usr/bin/env python3
"""Generate Apple string tables from independently maintained native translations.

English literals are stable lookup keys. Missing translations use English at runtime.
No inherited Audiobookshelf translation files are read or bundled by this generator.
Run with --check to verify generated tables and coverage without writing them.
"""
from collections import Counter
import json
import pathlib
import re
import sys

LOCALIZATION = pathlib.Path(__file__).resolve().parent
APPLE = LOCALIZATION.parent
REPOSITORY = APPLE.parent
SOURCES = [APPLE / 'App', APPLE / 'Playback', APPLE / 'Diagnostics' / 'Sources', LOCALIZATION / 'Sources', APPLE / 'Export' / 'Sources',
           REPOSITORY / 'tvos' / 'App', REPOSITORY / 'tvos' / 'Core' / 'Sources', APPLE / 'Adoption']
RESOURCES = LOCALIZATION / 'Sources' / 'NativeLocalization' / 'Resources'
TABLE = 'NativeStrings.strings'
# `copy("…")` marks English templates in renderers that receive `NativeStrings.copy` instead of looking text up.
# `CoreText.text("…")` marks the shared core's English text, which the apps look up the same way.
CALL = re.compile(r'(?<![\w.])(?:l10n|strings|copy|NativeStrings\.current|CoreText\.text)\(')
PLACEHOLDER = re.compile(r'\{\d+\}')
SEPARATOR = '::'


def languages():
    """The legacy selectable languages, in order, with their `.lproj` names from NativeLanguage.swift."""
    source = (LOCALIZATION / 'Sources' / 'NativeLocalization' / 'NativeLanguage.swift').read_text()
    return re.findall(r'\(code: "([^"]+)", name: "[^"]+", localization: "([^"]+)"\)', source)


def contexts():
    """The `NativeTextContext` cases declared in NativeStrings.swift."""
    source = (LOCALIZATION / 'Sources' / 'NativeLocalization' / 'NativeStrings.swift').read_text()
    body = re.search(r'enum NativeTextContext\b[^{]*\{(.*?)\n\}', source, re.S).group(1)
    return set(re.findall(r'^\s*case (\w+)', body, re.M))


def english(key):
    """The English wording of a key, without its context."""
    return key.split(SEPARATOR, 1)[-1]


def checked(key, origin):
    """A key whose context, if any, is a declared `NativeTextContext` case, and whose English carries no separator."""
    context, _, text = key.rpartition(SEPARATOR)
    if context and context not in contexts():
        raise SystemExit(f'{origin}: "{key}" names an unknown NativeTextContext')
    if SEPARATOR in text or not text:
        raise SystemExit(f'{origin}: "{key}" is not English text with at most one context')
    return key


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


def arguments(text, start):
    """The source of each top-level argument of the call whose parenthesis opens at `start`."""
    depth, index, quoted, begin, found = 0, start, False, start + 1, []
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
                return found + [text[begin:index]]
        elif character == ',' and depth == 1:
            found.append(text[begin:index])
            begin = index + 1
        index += 1


def english_keys():
    keys = set()
    for root in SOURCES:
        for path in sorted(root.rglob('*.swift')) if root.exists() else []:
            text = path.read_text()
            for match in CALL.finditer(text):
                first, *rest = arguments(text, match.end() - 1)
                named = [re.fullmatch(r'\s*context:\s*\.(\w+)\s*', argument) for argument in rest]
                prefix = next((found.group(1) + SEPARATOR for found in named if found), '')
                keys.update(checked(prefix + value, path.name) for value in literals(first))
    dynamic = json.loads((LOCALIZATION / 'dynamic-keys.json').read_text())
    everything = '\n'.join(path.read_text() for root in SOURCES if root.exists() for path in root.rglob('*.swift'))
    for origin, values in dynamic.items():
        for key in values:
            value = english(checked(key, origin))
            if f'"{value}"' not in everything and f'"{value.lower()}"' not in everything and f' {value.lower()}' not in everything:
                raise SystemExit(f'{origin}: "{value}" no longer appears in the sources')
            keys.add(key)
    return sorted(keys)


def usable(candidate, key):
    return bool(candidate and candidate.strip()) and '<' not in candidate and \
        Counter(PLACEHOLDER.findall(candidate)) == Counter(PLACEHOLDER.findall(english(key)))


def maintained(code, keys):
    """Validate independently maintained translations for current native text."""
    path = LOCALIZATION / 'translations' / f'{code}.json'
    if not path.exists():
        return {}
    found = json.loads(path.read_text())
    origin = path.relative_to(REPOSITORY)
    stale = sorted(set(found) - set(keys))
    if stale:
        raise SystemExit(f'{origin} translates text the app no longer shows: {stale}')
    unusable = sorted(key for key, value in found.items() if not usable(value, key))
    if unusable:
        raise SystemExit(f'{origin} has empty, marked-up or placeholder-changing translations: {unusable}')
    return found


def escape(value):
    return value.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n').replace('\t', '\\t')


def outputs():
    keys = english_keys()
    files, rows = {}, []
    for code, localization in languages():
        if code == 'en-us':
            table = {key: english(key) for key in keys}
        else:
            table = maintained(code, keys)
        body = ''.join(f'"{escape(key)}" = "{escape(table[key])}";\n' for key in sorted(table))
        files[RESOURCES / f'{localization}.lproj' / TABLE] = '/* Generated by apple/Localization/generate.py. */\n' + body
        rows.append((code, localization, len(table)))
    report = ['# Native localization coverage', '',
              f'Generated from {len(keys)} native texts and independently maintained translations. '
              'Missing translations use English. No inherited translation tables are read.', '',
              'Translations are machine-drafted and have not had native-speaker review. '
              'This beta retains incomplete language coverage; language selection and saved preferences remain.', '',
              '| Language | Resources | Native translations | English fallback | Translated |',
              '| --- | --- | ---: | ---: | ---: |']
    for code, localization, count in rows:
        report.append(f'| `{code}` | `{localization}.lproj` | {count} | {len(keys) - count} | '
                      f'{100 * count // len(keys)}% |')
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
