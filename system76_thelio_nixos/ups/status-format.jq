# Presentation only: all formats consume the same losslessly nested document.
def toml_string: @json | gsub("\u007f"; "\\u007f");
def toml_value:
  if type == "object" then
    "{ " + ([to_entries[] | select(.value != null) |
      (.key | toml_string) + " = " + (.value | toml_value)] | join(", ")) + " }"
  elif type == "array" then "[" + (map(toml_value) | join(", ")) + "]"
  elif type == "null" then error("TOML cannot represent null array members")
  elif type == "string" then toml_string else tojson end;
def toml_tables($path):
  (to_entries | sort_by(.key) | .[] | select(.value != null and (.value | type) != "object") |
    (.key | toml_string) + " = " + (.value | toml_value)),
  (to_entries | sort_by(.key) | .[] | select((.value | type) == "object") |
    ($path + [.key]) as $next |
    "\n[" + ($next | map(toml_string) | join(".")) + "]",
    (.value | toml_tables($next)));
def xml_text:
  tostring | if test("[\u0000-\u0008\u000b\u000c\u000e-\u001f\ufffe\uffff]") then
    error("value contains characters forbidden by XML 1.0") else . end
  | @html | gsub("\r"; "&#13;");
def xml($key; $indent):
  type as $kind |
  ($key | test("^[A-Za-z_][A-Za-z0-9_.-]*$")) as $simple |
  (if $simple then $key else "field" end) as $tag |
  ($indent + "<" + $tag + (if $simple then "" else " name=\"" + ($key | xml_text | gsub("\n"; "&#10;") | gsub("\t"; "&#9;")) + "\"" end)
    + " type=\"" + $kind + "\">") as $open |
  ("</" + $tag + ">") as $close |
  if $kind == "object" then
    $open + "\n" + ([to_entries | sort_by(.key) | .[] | .key as $k | .value | xml($k; $indent + "  ")] | join("\n"))
      + "\n" + $indent + $close
  elif $kind == "array" then
    $open + "\n" + ([.[] | xml("item"; $indent + "  ")] | join("\n")) + "\n" + $indent + $close
  else $open + (if $kind == "null" then "" else xml_text end) + $close end;
def bash_exports:
  . as $root |
  [paths as $path | $root | getpath($path) as $v |
    select($v != null and ($v | type) != "object") |
    {name: ("UPS_STATUS_" + ($path | map(tostring | ascii_upcase | gsub("[^A-Z0-9_]"; "_")) | join("_"))
      + (if ($v | type) == "array" then "_LENGTH" else "" end)),
     value: (if ($v | type) == "array" then ($v | length | tostring) else ($v | tostring) end)}]
  | if (group_by(.name) | any(.[]; length > 1)) then error("Bash variable name collision") else . end
  | if any(.[]; .value | contains("\u0000")) then error("Bash environment cannot contain NUL") else . end
  | sort_by(.name)
  | ["# Reserved namespace: replace the previous UPS_STATUS_ snapshot.",
     "for UPS_STATUS__KEY in \"${!UPS_STATUS_@}\"; do unset \"$UPS_STATUS__KEY\"; done; unset UPS_STATUS__KEY;",
     (.[] | "export " + .name + "=" + (.value | @sh))] | join("\n");
if $format == "json" then .
elif $format == "toml" then toml_tables([])
elif $format == "xml" then "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" + xml("ups-status"; "")
elif $format == "bash" then bash_exports
else error("unknown output format") end
