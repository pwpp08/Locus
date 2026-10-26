#!/usr/bin/env python3
"""Imports the Free Exercise DB (https://github.com/yuhonas/free-exercise-db,
Unlicense / public domain) into the app.

  python3 tool/gen_free_exercises.py <dir with exercises.json and thumbs/>

`thumbs/` holds `<id>_0.jpg` and `<id>_1.jpg` (192x128, the two photos of each
exercise cropped to 3:2 and shrunk; see the fetch script in this header's
history). Writes:

  lib/ui2/activity/free_exercises.g.dart   the const catalogue rows
  assets/exercises/<id>_<n>.jpg            the photos
  assets/exercises/instructions.json       id -> [steps], read on demand

Only strength work is kept: stretching and cardio entries are left out, since
the trainer logs sets, reps and loads.
"""
import json
import os
import shutil
import sys

src = sys.argv[1]
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
data = json.load(open(os.path.join(src, 'exercises.json'), encoding='utf-8'))

CATEGORY = {
    'chest': 'Chest',
    'lats': 'Back', 'middle back': 'Back', 'lower back': 'Back', 'traps': 'Back',
    'shoulders': 'Shoulders', 'neck': 'Shoulders',
    'biceps': 'Arms', 'triceps': 'Arms', 'forearms': 'Arms',
    'quadriceps': 'Legs', 'hamstrings': 'Legs', 'glutes': 'Legs',
    'adductors': 'Legs', 'abductors': 'Legs',
    'calves': 'Calves',
    'abdominals': 'Abs',
}
EQUIPMENT = {
    'body only': 'Bodyweight', 'barbell': 'Barbell', 'dumbbell': 'Dumbbell',
    'cable': 'Cable machine', 'machine': 'Machine', 'kettlebells': 'Kettlebell',
    'bands': 'Bands', 'medicine ball': 'Medicine ball',
    'exercise ball': 'Exercise ball', 'foam roll': 'Foam roll',
    'e-z curl bar': 'EZ bar', 'other': 'Other',
}


def title(s):
    return s[:1].upper() + s[1:]


def q(s):
    return json.dumps(s, ensure_ascii=False).replace('$', '\\$')


kept = [e for e in data if e['category'] not in ('stretching', 'cardio')]
kept.sort(key=lambda e: e['name'].lower())

out_assets = os.path.join(root, 'assets', 'exercises')
shutil.rmtree(out_assets, ignore_errors=True)
os.makedirs(out_assets)

rows = []
steps = {}
for e in kept:
    frames = 0
    for i in (0, 1):
        f = os.path.join(src, 'thumbs', f"{e['id']}_{i}.jpg")
        if os.path.exists(f):
            shutil.copy(f, os.path.join(out_assets, f"{e['id']}_{i}.jpg"))
            frames += 1
    if frames == 0:
        continue
    prim = [m for m in e['primaryMuscles']]
    sec = [m for m in e['secondaryMuscles']]
    cat = CATEGORY.get(prim[0], 'Arms') if prim else 'Arms'
    eq = EQUIPMENT.get(e.get('equipment') or '', None)
    bodyweight = (e.get('equipment') == 'body only')
    step = 2.0 if e.get('equipment') in ('dumbbell', 'kettlebells') else 2.5
    steps[e['id']] = e['instructions']
    rows.append(f"""  ExerciseDef(
    {q('fx:' + e['id'])},
    {q(e['name'])},
    [{', '.join(q(title(m)) for m in prim)}],
    secondaryMuscles: [{', '.join(q(title(m)) for m in sec)}],
    category: {q(cat)},
    equipment: [{q(eq) if eq else ''}],
    step: {step},
    bodyweight: {'true' if bodyweight else 'false'},
    imageId: {q(e['id'])},
    imageFrames: {frames},
  ),""")

with open(os.path.join(root, 'assets', 'exercises', 'instructions.json'), 'w',
          encoding='utf-8') as f:
    json.dump(steps, f, ensure_ascii=False, separators=(',', ':'))

with open(os.path.join(root, 'lib', 'ui2', 'activity', 'free_exercises.g.dart'),
          'w', encoding='utf-8') as f:
    f.write("""// GENERATED FILE — DO NOT EDIT.
// Refresh with: python3 tool/gen_free_exercises.py <dir>
// Source: https://github.com/yuhonas/free-exercise-db (Unlicense: public
// domain, photos included). Strength work only; two photos each, bundled as
// assets/exercises/<id>_0.jpg and _1.jpg.

part of 'catalogue.dart';

const _freeExerciseLibrary = <ExerciseDef>[
""")
    f.write('\n'.join(rows))
    f.write('\n];\n')
print(len(rows), 'exercises', len(os.listdir(out_assets)), 'asset files')
