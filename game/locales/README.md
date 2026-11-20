# Localization foundation
ko/core.po is the Korean source with context comments; en/core.po is the initial English verification locale. keys.json defines stable keys and named placeholders. core.pot is generated; never store translated strings in domain saves.
```sh
python3 tools/localization.py
python3 tools/localization.py --pot locales/core.pot
python3 tools/localization.py --pack-po locales/en/core.po --locale en --author Translator --output /tmp/example-pack.json
```
Run from game/. Tool checks duplicates, missing/unknown keys, named placeholders and fixture references. Supported PO subset: header continuations, comments, single-line msgid/msgstr; message continuations/plurals need future extension. Runtime uses Godot TranslationServer and Translation resources.
Community JSON: exact fields format_version=1, content_version="0.1.0", locale, author, strings. UTF-8, <=64 KiB; known keys only; partial maps allowed with logged Korean fallback. Strings <=1024 characters, plain text, exact named placeholders, no markup or bidi controls. Supply display arguments as validated plain strings. Author <=80 characters. Text-only files cannot change game logic/data/resources.
Put JSON under user://localization and explicitly call install_pack(basename); it validates completely before switching. No auto-discovery/loading. Failed install preserves current selection; clear_pack restores Korean. Switching official languages retains domain state. Additional language IDs follow xx/xxx or xx_YY; engine-normalized locale must match.
Missing source keys produce diagnostic and key, and fail static source checks. Missing selected translation falls back to Korean. Diagnostic messages are developer-only.
No CJK fonts or UI provided yet. Expanded-text fixture is headless only: wrapping, glyph coverage, RTL, plural/context expansion and real import UI must be verified at later gates. Language setting persistence is not implemented.
