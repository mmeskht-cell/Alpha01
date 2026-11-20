#!/usr/bin/env python3
"""Validate the small official PO subset; extract POT; convert PO to safe pack JSON.
No dependencies. Multi-line message bodies/plurals need an explicit future extension.
"""
import argparse
import ast
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f'duplicate JSON key: {key}')
        result[key] = value
    return result

def read_po(path):
    result = {}
    current = None
    for line in path.read_text(encoding='utf-8').splitlines():
        if line.startswith('msgid '):
            current = ast.literal_eval(line[6:])
            if current in result:
                raise ValueError(f'duplicate key: {current}')
        elif line.startswith('msgstr '):
            if current is None:
                raise ValueError('msgstr without msgid')
            result[current] = ast.literal_eval(line[7:])
        elif line.startswith('"') and current:
            raise ValueError('multi-line messages require parser extension')
    result.pop('', None)
    return result

def validate(messages, schema, complete=True):
    if (complete and set(messages) != set(schema)) or not set(messages) <= set(schema):
        raise ValueError('missing/unknown keys')
    for key, value in messages.items():
        if not isinstance(value, str) or not value or len(value) > 1024 or any(c in value for c in '[]<>'):
            raise ValueError(f'invalid plain text: {key}')
        if any((ord(c) < 32 and c != '\n') or ord(c) == 127 or 0x202a <= ord(c) <= 0x202e or 0x2066 <= ord(c) <= 0x2069 for c in value):
            raise ValueError(f'control character: {key}')
        placeholders = re.findall(r'\{([a-z_]+)\}', value)
        stripped = re.sub(r'\{([a-z_]+)\}', '', value)
        if sorted(placeholders) != sorted(schema[key]) or '{' in stripped or '}' in stripped:
            raise ValueError(f'placeholder mismatch: {key}')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--pot', type=Path)
    parser.add_argument('--pack-po', type=Path)
    parser.add_argument('--locale')
    parser.add_argument('--author')
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    schema = json.loads((ROOT / 'locales/keys.json').read_text(), object_pairs_hook=unique_pairs)
    for locale in ('ko', 'en'):
        validate(read_po(ROOT / f'locales/{locale}/core.po'), schema)
    # All current fixture definitions must reference known text and an explicit no-art key.
    for relative in ('data/catalog/foundation.json', 'data/campaign/gate1_1/catalog.json', 'data/campaign/gate1_day_one/catalog.json', 'data/catalog/component_preview.json'):
        catalog = json.loads((ROOT / relative).read_text(encoding='utf-8'), object_pairs_hook=unique_pairs)
        for definition in catalog['definitions']:
            if definition['localization_key'] not in schema or definition['render_key'] != 'placeholder_none':
                raise ValueError(f'unresolved text/render key: {relative}')
    reference = json.loads((ROOT / 'data/campaign/gate1_1/appraisal_reference.json').read_text(encoding='utf-8'), object_pairs_hook=unique_pairs)
    for model in reference['model_candidates']:
        for field in ('name_key', 'description_key'):
            if model[field] not in schema or schema[model[field]]:
                raise ValueError(f'unresolved catalog key: {model[field]}')
    for condition in reference['appearance_candidates']:
        if condition['label_key'] not in schema or schema[condition['label_key']]:
            raise ValueError('unresolved condition key')
    source_key = reference['source']['label_key']
    if source_key not in schema or schema[source_key]:
        raise ValueError('unresolved reference source key')
    material = json.loads((ROOT / 'data/campaign/gate1_1/material_reference.json').read_text(encoding='utf-8'), object_pairs_hook=unique_pairs)
    for group in ('materials', 'batches'):
        for entry in material[group]:
            for field in ('label_key', 'description_key'):
                if entry[field] not in schema or schema[entry[field]]:
                    raise ValueError(f'unresolved appraisal handbook key: {entry[field]}')
    profiles = json.loads((ROOT / "data/campaign/component_preview/profiles.json").read_text(encoding="utf-8"), object_pairs_hook=unique_pairs)
    for regions in profiles["regions_by_definition"].values():
        for region in regions:
            if region["label_key"] not in schema or schema[region["label_key"]]:
                raise ValueError(f"unresolved component region key: {region['label_key']}")
    if args.pot:
        text = '# Stable keys; use ko/core.po for meaning, comments and placeholders.\n'
        text += 'msgid ""\nmsgstr ""\n"Content-Type: text/plain; charset=UTF-8\\n"\n\n'
        for key, placeholders in schema.items():
            text += f'#. Named arguments: {", ".join(placeholders) or "none"}; plain text.\nmsgid {json.dumps(key)}\nmsgstr ""\n\n'
        args.pot.write_text(text, encoding='utf-8')
    if args.pack_po:
        if not args.output or not args.author or not args.locale or not re.fullmatch(r'[a-z]{2,3}(_[A-Z]{2})?', args.locale):
            raise ValueError('pack requires output, author, locale')
        messages = read_po(args.pack_po)
        validate(messages, schema, complete=False)
        args.output.write_text(json.dumps({'format_version': 1, 'content_version': '0.1.0', 'locale': args.locale, 'author': args.author, 'strings': messages}, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'L01: ko/en, {len(schema)} keys; duplicate/key/placeholder/catalog checks passed')

if __name__ == '__main__':
    main()
