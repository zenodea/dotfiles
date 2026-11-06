#!/bin/sh
payload="$(cat)"

orca="$HOME/.orca/agent-hooks/claude-statusline.sh"
[ -x "$orca" ] && printf '%s' "$payload" | /bin/sh "$orca" >/dev/null 2>&1

command -v jq >/dev/null 2>&1 || exit 0

printf '%s' "$payload" | jq -r '
  def one: (. * 10 | round) as $tenths | "\($tenths / 10 | floor).\($tenths % 10)";
  def tokens: if . >= 1000000 then "\(. / 1000000 | one)M"
              elif . >= 1000 then "\(. / 1000 | round)k"
              else tostring end;
  # Every span opens its own italic: the statusline renderer does not carry
  # one line-wide italic across the colour changes inside it.
  def paint($on; $off): "\u001b[3;\($on)m\(.)\u001b[23;\($off)m";
  def dim: paint("2"; "22");
  def tone($percent): if $percent > 90 then paint("31"; "39")
                      elif $percent > 70 then paint("33"; "39")
                      else dim end;

  (.context_window.used_percentage // 0) as $percent
  | [
      ([.model.id // "no-model", (.effort.level // empty)] | join(" • ") | dim),
      ([
        (if (.cost.total_cost_usd // 0) > 0
         then "$\(.cost.total_cost_usd * 1000 | round / 1000)" | dim else empty end),
        ("\($percent | one)%/\((.context_window.context_window_size // 0) | tokens)" | tone($percent))
      ] | join(" ")),
      (.output_style.name // "default" | select(. != "default") | ascii_downcase | paint("35"; "39"))
    ]
  | join(" │ " | dim)
'
