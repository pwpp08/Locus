# Notice

Edge is an independent, open-source project (AGPL-3.0, see `LICENSE`; versions up to
commit 1140dac1 were MIT, see `NOTICE`). It
is not affiliated with, sponsored by, or endorsed by WHOOP, Inc. or any of its
trademarks.

No WHOOP source code, binaries, firmware, or copyrighted assets are included
in this repository.

## wger exercise data

`lib/ui2/activity/wger_exercises.g.dart` contains selected fields (names,
aliases, muscles, equipment, categories) from the [wger](https://wger.de)
exercise database, limited to the movements listed in
`tool/wger_weightlifting_selection.dart`. Each entry is available under
CC BY-SA 3.0, CC BY-SA 4.0 or CC0, and each row keeps its source UUID and the
author/license credits of its base data and translations. This data stays under
those licenses, separate from the AGPL-licensed code. Refresh with
`dart run tool/update_wger_exercises.dart`.

## Free Exercise DB

`lib/ui2/activity/free_exercises.g.dart`, `assets/exercises/` (two photos per
exercise, shrunk) and `assets/exercises/instructions.json` come from
[free-exercise-db](https://github.com/yuhonas/free-exercise-db), released into
the public domain under the Unlicense. Strength work only; regenerate with
`python3 tool/gen_free_exercises.py`.
