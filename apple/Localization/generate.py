#!/usr/bin/env python3
"""Writes the native string tables from the English text the app passes to `l10n`.

English text is the key, so the English table is the identity. Other languages carry the legacy translation from
`strings/<code>.json` only where `legacy-equivalents.json` names a key with the same meaning and the translation is
usable: present, without markup, and with the same `{n}` placeholders. Everything else stays in English.

English wording with more than one meaning is looked up with a `NativeTextContext`, as in `l10n("Light", context: .theme)`.
Its key is `theme::Light`, in the sources, `dynamic-keys.json`, `legacy-equivalents.json` and the tables alike, and the
English table maps it back to `Light`.

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
SOURCES = [APPLE / 'App', APPLE / 'Playback', APPLE / 'Diagnostics' / 'Sources', LOCALIZATION / 'Sources', APPLE / 'Export' / 'Sources',
           REPOSITORY / 'tvos' / 'App']
RESOURCES = LOCALIZATION / 'Sources' / 'NativeLocalization' / 'Resources'
TABLE = 'NativeStrings.strings'
# `copy("…")` marks English templates in renderers that receive `NativeStrings.copy` instead of looking text up.
CALL = re.compile(r'(?<![\w.])(?:l10n|strings|copy|NativeStrings\.current)\(')
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
        set(PLACEHOLDER.findall(candidate)) == set(PLACEHOLDER.findall(english(key)))


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
            table = {key: english(key) for key in keys}
        else:
            legacy = json.loads((REPOSITORY / 'strings' / f'{code}.json').read_text())
            table = {native: legacy[key] for native, key in mapping.items() if usable(legacy.get(key, ''), native)}
        body = ''.join(f'"{escape(key)}" = "{escape(table[key])}";\n' for key in sorted(table))
        files[RESOURCES / f'{localization}.lproj' / TABLE] = '/* Generated by apple/Localization/generate.py. */\n' + body
        rows.append((code, localization, len(table)))
    report = ['# Native localization coverage', '',
              'Generated by `apple/Localization/generate.py`. Native screens show {0} distinct texts. {1} of them have a legacy '
              'key with the same meaning (`legacy-equivalents.json`); a language shows a translation only where its legacy '
              'file has a usable value for that key. All other text stays in English, and the Language screen says so. '
              'Wording with several meanings counts once per meaning (`theme::Light`, `hapticStrength::Light`).'
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
