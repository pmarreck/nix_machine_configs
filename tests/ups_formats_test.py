"""Independent format readers verify the renderer's actual wire formats."""
import json
import os
import subprocess
import sys
import tomllib
import xml.etree.ElementTree as ET

data = {"nut": {"driver": {"version": {"_value": "2.8.4", "data": 'A&B <HID> "quoted"\n雪'}}},
        "monitor": {"shutdown_enabled": False, "elapsed": 42.5}, "errors": []}

def render(kind, value):
    return subprocess.check_output(["jq", "-rS", "--arg", "format", kind, "-f", sys.argv[1]],
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
    assert xml_value(ET.fromstring(render('xml', value))) == value
    assert tomllib.loads(render('toml', value)) == {k: v for k, v in value.items() if v is not None}
print('9 independent JSON/TOML/XML round-trip checks passed')

payload = "$(printf injected) `printf injected` ' \" ; exit 99 #\nsecond line"
value = {'nut': {'model': payload, 'status': 'OL'}, 'monitor': {'shutdown_enabled': False}, 'errors': []}
script = render('bash', value)
env = dict(os.environ, UPS_STATUS_STALE='must disappear', KEEP_ME='untouched')
result = subprocess.check_output(['bash', '-c', script + '\nenv -0'], env=env)
fields = dict(item.split(b'=', 1) for item in result.split(b'\0') if item)
assert fields[b'UPS_STATUS_NUT_MODEL'].decode() == payload
assert fields[b'UPS_STATUS_MONITOR_SHUTDOWN_ENABLED'] == b'false'
assert fields[b'UPS_STATUS_ERRORS_LENGTH'] == b'0'
assert b'UPS_STATUS_STALE' not in fields and fields[b'KEEP_ME'] == b'untouched'
for invalid in [{'a-b': 1, 'a_b': 2}, {'x': 'contains\0NUL'}]:
    result = subprocess.run(['jq', '-r', '--arg', 'format', 'bash', '-f', sys.argv[1]],
                            input=json.dumps(invalid), text=True, capture_output=True)
    assert result.returncode != 0 and result.stdout == ''
print('Bash quoting, false values, array length, stale clearing, collisions and NUL checks passed')
