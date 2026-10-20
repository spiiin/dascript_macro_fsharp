"""Independent Draft 2020-12 meta-schema and instance checks (test dependency: jsonschema)."""
import argparse
import copy
import json
import os
from pathlib import Path
import subprocess
from jsonschema import Draft202012Validator

parser = argparse.ArgumentParser()
parser.add_argument('--daslang', default=os.environ.get('DASLANG_EXE', 'C:/src/daslang-0.6.5-RC2/sdk/daslang_bundle/bin/daslang.exe'))
parser.add_argument('--jit', action='store_true')
parser.add_argument('--output-log', type=Path)
parser.add_argument('--workflow-output-log', type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]

def output(script):
    cmd = [args.daslang, str(root / 'examples' / script), '-no-module-cache']
    if args.jit:
        cmd += ['-jit', '-jit-no-cache']
    completed = subprocess.run(cmd, capture_output=True, timeout=240, check=True)
    return completed.stdout.decode('utf-8-sig')

text = args.output_log.read_text(encoding='utf-8-sig') if args.output_log else output('schema_demo.das')
names = {'STRICT', 'LOOSE', 'TREE', 'ACTION', 'ROLE', 'ARRAY', 'FIXED', 'FIELD', 'PRESENCE', 'INT8', 'UINT64', 'MATRIX', 'NUMBERS', 'LOOKALIKE'}
schemas = {}
for line in text.splitlines():
    key, _, value = line.partition(' ')
    if key in names:
        schemas[key] = json.loads(value)
assert schemas.keys() == names
for schema in schemas.values():
    Draft202012Validator.check_schema(schema)
validators = {key: Draft202012Validator(schema) for key, schema in schemas.items()}
checks = 0

def check(key, value, expected=True):
    global checks
    valid = validators[key].is_valid(value)
    if valid != expected:
        raise AssertionError((key, value, expected, list(validators[key].iter_errors(value))))
    checks += 1

base = {'displayName': 'Alice', 'role': 'Warrior', 'stats': {'health': 100}, 'inventory': [{'id': 1, 'count': 3}]}
check('STRICT', base)
for role in ['Mage', 'Wizard']:
    check('STRICT', dict(base, role=role))
for role in ['rogue', 1]:
    check('STRICT', dict(base, role=role), False)
for field in ['displayName', 'role', 'stats', 'inventory']:
    missing = copy.deepcopy(base)
    del missing[field]
    check('STRICT', missing, False)
for alias in [None, 'hello']:
    check('STRICT', dict(base, alias=alias))
check('STRICT', dict(base, alias=1), False)
for bio in [None, 'hello']:
    check('STRICT', dict(base, bio=bio))
check('STRICT', dict(base, bio=False), False)
check('STRICT', dict(base, displayName=''), False)
check('STRICT', dict(base, inventory=[]), False)
check('STRICT', dict(base, stats={'health': -1}), False)
check('STRICT', dict(base, stats={'health': 101}), False)
check('STRICT', dict(base, stats={}), False)  # default is metadata, does not fill required.
check('STRICT', dict(base, inventory=[{'id': 1, 'count': 0}]), False)
check('STRICT', dict(base, inventory=[{'id': 'bad', 'count': 1}]), False)
for unknown in ['extra', 'session']:
    check('STRICT', dict(base, **{unknown: 1}), False)
    check('LOOSE', dict(base, **{unknown: 1}))
check('STRICT', dict(base, stats={'health': 100, 'extra': 1}), False)
check('LOOSE', dict(base, stats={'health': 100, 'extra': 1}))
check('STRICT', dict(base, action={'case': 'idle'}))
check('STRICT', dict(base, action={'case': 'idle', 'extra': 1}), False)
check('LOOSE', dict(base, action={'case': 'idle', 'extra': 1}))
for key in ['STRICT', 'LOOSE']:
    check(key, dict(base, action={'case': 'idle', 'value': None}), False)
    check(key, dict(base, action={'case': 'unknown'}), False)
check('ACTION', {'case': 'stats', 'value': {'health': 80}})
check('ACTION', {'case': 'stats', 'value': {'health': -1}}, False)
check('ACTION', {'case': 'text', 'value': 'hello'})
check('ACTION', {'case': 'text'}, False)
check('ACTION', {'case': 'items', 'value': [{'id': 1, 'count': 2}]})
check('ROLE', 'Wizard')
check('ROLE', 2, False)
check('ARRAY', [None, 1, 2])
check('ARRAY', [False], False)
check('FIXED', [1, 2])
check('FIXED', [1], False)
check('FIXED', [1, 2, 3], False)
check('MATRIX', [[1, 2, 3], [4, 5, 6]])
check('MATRIX', [[1, 2], [3, 4], [5, 6]], False)
check('FIELD', None)
check('FIELD', 3)
check('FIELD', '3', False)
check('TREE', {'name': 'root', 'children': [{'name': 'child', 'children': []}]})
check('TREE', {'name': 'root', 'children': [{'name': '', 'children': []}]}, False)
check('TREE', {'name': 'root', 'children': [{'name': 'child', 'children': [], 'extra': 1}]}, False)
check('PRESENCE', {'required': None})  # builder_required is separate from JSON required.
check('PRESENCE', {}, False)
check('PRESENCE', {'required': 1, 'optional': None})
check('PRESENCE', {'required': 1, 'optional': 0}, False)
check('PRESENCE', {'required': 1, 'optional': 10}, False)
check('PRESENCE', {'required': 1, 'optional': 9})
check('INT8', -128)
check('INT8', 127)
check('INT8', -129, False)
check('INT8', 128, False)
check('UINT64', 9223372036854775807)
check('UINT64', 9223372036854775808, False)
check('UINT64', -1, False)
check('NUMBERS', {})
check('NUMBERS', {'x': 0}, False)
check('NUMBERS', {'x': 9223372036854775807})
check('NUMBERS', {'y': 4294967295})
check('NUMBERS', {'y': 4294967296}, False)
check('NUMBERS', {'signed': -9223372036854775808}, False)
check('NUMBERS', {'f': 0.25})
check('NUMBERS', {'f': 0.1})
check('NUMBERS', {'f': 0.01})  # float32 bounds require native validation.
check('NUMBERS', {'g': 'bad'}, False)
check('LOOKALIKE', {'case': 'missing'})
check('LOOKALIKE', {'case': 'null_value', 'value': 'text'})
check('LOOKALIKE', {'case': 'null_value', 'value': None}, False)
check('LOOKALIKE', {'case': 'present', 'value': 3})
check('LOOKALIKE', None, False)
# Explicit boundaries: schema does not execute callbacks or key uniqueness checks.
check('STRICT', dict(base, displayName='forbidden'))
check('STRICT', dict(base, inventory=[{'id': 1, 'count': 1}, {'id': 1, 'count': 2}]))
# byteMinLength=2 accepts the 2-byte UTF-8 e-acute. minLength=2 would wrongly reject it.
check('STRICT', dict(base, code='é'))
check('STRICT', dict(base, code=''), False)
check('STRICT', dict(base, code='x'))  # byte length is left to derive validation.
player = schemas['STRICT']['$defs']['schema_model::SchemaPlayer']
assert player['properties']['code']['default'] == 'ok'
assert schemas['PRESENCE']['$defs']['schema_model::SchemaPresence']['properties']['value']['default'] == 3
assert 'uniqueItems' not in json.dumps(player)
assert 'x-das-validate_unique_by' in json.dumps(player)
assert 'x-das-byteMinLength' in json.dumps(player)
workflow = args.workflow_output_log.read_text(encoding='utf-8-sig') if args.workflow_output_log else output('workflow_demo.das')
serialized, _ = json.JSONDecoder().raw_decode(workflow.partition('Loaded JSON: ')[2])
check('STRICT', serialized)
assert 'code' not in base  # validators must not mutate inputs or apply defaults.
print(f'JSON Schema 2020-12: {len(schemas)} meta-schema checks and {checks} instance checks passed')
