# NUT values are text, not a typed schema: preserve leading zeroes and precision.
# A key may also be a prefix (driver.version and driver.version.data). _value
# retains the prefix's scalar without making output depend on record order.
def insert($path; $value):
  if ($path | length) == 0 then
    if . == null then $value
    elif type == "object" and (has("_value") | not) then . + {_value: $value}
    else error("duplicate NUT key") end
  else
    (if . == null then {} elif type == "object" then . else {_value: .} end)
    | .[$path[0]] |= insert($path[1:]; $value)
  end;
def nut_tree:
  split("\n") | map(rtrimstr("\r")) | map(select(length > 0))
  | if length == 0 then error("empty NUT response") else . end
  | reduce .[] as $line ({};
      ($line | index(": ")) as $separator
      | if $separator == null then error("malformed NUT record") else . end
      | ($line[:$separator] | split(".")) as $path
      | if any($path[]; . == "" or . == "_value") then error("empty or reserved NUT key component") else . end
      | insert($path; $line[$separator + 2:]));
(if $nut_ok then
   try {value: ($nut | nut_tree), errors: []}
   catch {value: null, errors: [{source: "nut", message: .}]}
 else {value: null, errors: [{source: "nut", message: "NUT query failed or timed out"}]} end) as $n
| (try {value: ($monitor | fromjson | if type == "object" then . else error("monitor status must be an object") end), errors: []}
   catch {value: null, errors: [{source: "monitor", message: .}]}) as $m
| {nut: $n.value, monitor: $m.value, errors: ($n.errors + $m.errors)}
