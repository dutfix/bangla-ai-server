#!/usr/bin/env bash
# Regenerates lib/l10n/app_localizations*.dart from the .arb files.
#
# gen-l10n still writes the delegates from package:flutter_localizations,
# which only cover package:flutter/material.dart. This app's widgets come
# from package:material_ui, which has its own MaterialLocalizations type, so
# with those delegates there are no Material strings in Bangla and every
# TextField and Drawer throws (a grey box in release builds). This swaps in
# material_ui's delegates, which bundle the Material, Cupertino and Widgets
# ones.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter gen-l10n
python3 - <<'PY'
import re
p = 'lib/l10n/app_localizations.dart'
s = open(p).read()
s = s.replace(
    "import 'package:flutter_localizations/flutter_localizations.dart';",
    "import 'package:material_ui/material_ui.dart'\n    show GlobalMaterialLocalizations;",
)
s = re.sub(
    r"        delegate,\n        GlobalMaterialLocalizations\.delegate,\n"
    r"        GlobalCupertinoLocalizations\.delegate,\n"
    r"        GlobalWidgetsLocalizations\.delegate,\n",
    "        delegate,\n        ...GlobalMaterialLocalizations.delegates,\n",
    s,
)
assert '        GlobalCupertinoLocalizations.delegate,' not in s, 'delegate list changed'
open(p, 'w').write(s)
PY
dart format lib/l10n >/dev/null
