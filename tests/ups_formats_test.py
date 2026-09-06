"""Independent format readers verify the renderer's actual wire formats."""
import json
import os
import subprocess
import sys
import tomllib
import xml.etree.ElementTree as ET

data = {"nut": {"driver": {"version": {"_value": "2.8.4", "data": 'A&B <HID> "quoted"\n雪'}}},
        "monitor": {"shutdown_enabled": False, "elapsed": 42.5}, "errors": []}

def render(kind, value, export=False, declaration=False, null_value=None):
    return subprocess.check_output(["jq", "-rS", "--arg", "format", kind,
                                   "--argjson", "declaration", json.dumps(declaration),
                                   "--argjson", "null_value_set", json.dumps(null_value is not None),
                                   "--argjson", "null_value", json.dumps(null_value),
                                   "--argjson", "export_vars", json.dumps(export), "-f", sys.argv[1]],
                                   input=json.dumps(value), text=True)

def xml_value(element):
    kind = element.attrib['type']
    if kind == 'object':
        return {c.attrib.get('name', c.tag): xml_value(c) for c in element}
    if kind == 'array':
        return [xml_value(c) for c in element]
    if kind == 'null':
        return None
    if kind == 'boolean':
        return element.text == 'true'
    if kind == 'number':
        return float(element.text)
    return element.text or ''

for value in [data, {'nut': None, 'monitor': {'status': 'OL'}, 'errors': [{'source': 'nut', 'message': 'unavailable'}]},
              {'spaces & quotes "': {'empty': '', 'array': [1, False, 'a\tb\rc'], 'unicode': '雪'}}]:
    assert json.loads(render('json', value)) == value
    plain_xml = render('xml', value)
    declared_xml = render('xml', value, declaration=True)
    assert plain_xml.startswith('<ups-status ')
    assert declared_xml == '<?xml version="1.0" encoding="UTF-8"?>\n' + plain_xml
    assert xml_value(ET.fromstring(plain_xml)) == value
    assert xml_value(ET.fromstring(declared_xml)) == value
    assert tomllib.loads(render('toml', value)) == {k: v for k, v in value.items() if v is not None}
print('12 independent JSON/TOML/XML round-trip checks passed, including optional XML declaration')

null_fixture = {'missing': None, 'nested': {'missing': None},
                'items': [None, {'missing': None}], 'literal': ':null'}
def replace_nulls(value, sentinel):
    if value is None:
        return sentinel
    if isinstance(value, dict):
        return {k: replace_nulls(v, sentinel) for k, v in value.items()}
    if isinstance(value, list):
        return [replace_nulls(v, sentinel) for v in value]
    return value
for sentinel in [':null', '', '"quoted"\\value\n雪', 'false', '0']:
    assert tomllib.loads(render('toml', null_fixture, null_value=sentinel)) == replace_nulls(null_fixture, sentinel)
assert tomllib.loads(render('toml', {'a': None, 'b': {'c': None}})) == {'b': {}}
print('TOML null omission and explicit string sentinels round-trip at every nesting level')

payload = "$(printf injected) `printf injected` ' \" ; exit 99 #\nsecond line"
value = {'nut': {'model': payload, 'status': 'OL'}, 'monitor': {'shutdown_enabled': False}, 'errors': []}
env = {k: v for k,v in os.environ.items() if not k.startswith('UPS_STATUS_')}
env.update(UPS_STATUS_STALE='preserve caller state', KEEP_ME='untouched')
for export in [False, True]:
    script = render('bash', value, export)
    lines = script.splitlines()
    assert len(lines) == 4, 'one physical assignment line per value, no preamble'
    assert all(line.startswith('export UPS_STATUS_' if export else 'UPS_STATUS_') for line in lines)
    tail = '\nprintf "%s\\0%s\\0%s\\0" "$UPS_STATUS_NUT_MODEL" "$UPS_STATUS_MONITOR_SHUTDOWN_ENABLED" "$UPS_STATUS_ERRORS_LENGTH"; env -0'
    result = subprocess.check_output(['bash', '-c', script + tail], env=env)
    model, boolean, length, remainder = result.split(b'\0', 3)
    assert model.decode() == payload and boolean == b'false' and length == b'0'
    fields = dict(item.split(b'=', 1) for item in remainder.split(b'\0') if item)
    assert (b'UPS_STATUS_NUT_MODEL' in fields) == export
    assert fields[b'UPS_STATUS_STALE'] == b'preserve caller state' and fields[b'KEEP_ME'] == b'untouched'
# All non-NUL ASCII controls, quotes, backslashes, and Unicode survive shell evaluation.
controls = ''.join(map(chr, range(1, 32))) + "\\'\"雪\x7f"
script = render('bash', {'x': controls})
assert len(script.splitlines()) == 1
assert subprocess.check_output(['bash', '-c', script + '\nprintf %s "$UPS_STATUS_X"']).decode() == controls
for invalid in [{'a-b': 1, 'a_b': 2}, {'x': 'contains\0NUL'}]:
    result = subprocess.run(['jq', '-r', '--arg', 'format', 'bash', '-f', sys.argv[1]],
                            input=json.dumps(invalid), text=True, capture_output=True)
    assert result.returncode != 0 and result.stdout == ''
print('Bash assignment-only output, opt-in export, literal quoting, caller-state preservation and rejection checks passed')
