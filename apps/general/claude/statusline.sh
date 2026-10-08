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
  def dim: "\u001b[2m\(.)\u001b[22m";
  def script: "\u001b[3m\(.)\u001b[23m";
  def tone($percent): if $percent > 90 then "\u001b[31m\(.)\u001b[39m"
                      elif $percent > 70 then "\u001b[33m\(.)\u001b[39m"
                      else dim end;

  (.context_window.used_percentage // 0) as $percent
  | [
      ([.model.id // "no-model", (.effort.level // empty)] | join(" • ") | dim),
      ([
        (if (.cost.total_cost_usd // 0) > 0
         then "$\(.cost.total_cost_usd * 1000 | round / 1000)" | dim else empty end),
        ("\($percent | one)%/\((.context_window.context_window_size // 0) | tokens)" | tone($percent))
      ] | join(" ")),
      (.output_style.name // "default" | select(. != "default") | ascii_downcase | "\u001b[35m\(.)\u001b[39m")
    ]
  | join(" │ " | dim)
  | script
'
