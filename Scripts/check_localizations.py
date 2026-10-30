#!/usr/bin/env python3
"""Fail CI for untranslated keys, invalid format arguments, or inline Han text."""
from pathlib import Path
import json, re, subprocess, sys
ROOT = Path(__file__).resolve().parent.parent
catalog = json.loads((ROOT / 'Localization/Strings.json').read_text())
languages = {'en', 'zh-Hans', 'zh-Hant'}
errors = []
placeholder = re.compile(r'%(\d+)\$(ld|@)')


def localization_keys(source):
    """Read single-line and formatter-wrapped multiline Swift localization keys."""
    pattern = r'L10n\.(?:text|format)\(\s*("""[\s\S]*?"""|"(?:\\.|[^"\\])*")'
    escapes = {'0': '\0', 't': '\t', 'n': '\n', 'r': '\r', '"': '"', "'": "'", '\\': '\\'}
    for literal in re.findall(pattern, source):
        if literal.startswith('"""'):
            lines = literal[3:-3].splitlines()
            indentation = lines[-1]
            content = '\n'.join(line[len(indentation):] for line in lines[1:-1])
            content = re.sub(r'\\\r?\n', '', content)
        else:
            content = literal[1:-1]

        def decode(match):
            escape = match.group(1)
            return chr(int(escape[2:-1], 16)) if escape.startswith('u{') else escapes[escape]

        yield re.sub(r'\\(u\{[0-9a-fA-F]+\}|[0tnr"\'\\])', decode, content)


for key, values in catalog.items():
    expected = sorted(placeholder.findall(values['en']))
    for language in languages:
        value = values.get(language)
        if not isinstance(value, str) or not value:
            errors.append(f'{key}: missing {language}')
        elif sorted(placeholder.findall(value)) != expected:
            errors.append(f'{key}: placeholder mismatch in {language}')
    if 'plural' in values:
        for category in ('one', 'other'):
            if sorted(placeholder.findall(values['plural'][category])) != expected:
                errors.append(f'{key}: placeholder mismatch in plural {category}')
for folder in ['Sources', 'Apps']:
    for path in (ROOT / folder).rglob('*.swift'):
        source = path.read_text()
        for index, line in enumerate(source.splitlines(), 1):
            if re.search(r'[\u3400-\u9fff]', line) and not line.lstrip().startswith('//'):
                errors.append(f'{path.relative_to(ROOT)}:{index}: inline Han text')
        for key in localization_keys(source):
            if key not in catalog:
                errors.append(f'{path.relative_to(ROOT)}: missing key {key}')
result = subprocess.run([sys.executable, str(ROOT / 'Scripts/generate_localizations.py'), '--check'], capture_output=True, text=True)
web_messages = json.loads((ROOT / 'Web/WiFiUpload/src/messages.json').read_text())
for key in web_messages.values():
    if key not in catalog:
        errors.append(f'Wi-Fi Upload: missing key {key}')
for path in (ROOT / 'Web/WiFiUpload/src').glob('*.tsx'):
    if not path.name.endswith('.test.tsx') and re.search(r'[\u3400-\u9fff]', path.read_text()):
        errors.append(f'{path.relative_to(ROOT)}: inline Han text')
if result.returncode:
    errors.append(result.stdout + result.stderr)
if errors:
    print('\n'.join(errors), file=sys.stderr)
    raise SystemExit(1)
print(f'Validated {len(catalog)} keys, 3 languages, plural formats, source coverage, and generated resources.')
