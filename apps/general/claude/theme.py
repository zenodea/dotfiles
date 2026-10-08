import json
import os
import sys

path, base = sys.argv[1:3]


def rgb(name: str) -> tuple[int, int, int]:
    value = os.environ[name].lstrip("#")
    return tuple(int(value[i : i + 2], 16) for i in (0, 2, 4))


def css(color: tuple[int, ...]) -> str:
    return "rgb({},{},{})".format(*color)


def mix(a: str, b: str, t: float) -> tuple[int, ...]:
    return tuple(round(x * t + y * (1 - t)) for x, y in zip(rgb(a), rgb(b)))


def c(name: str) -> str:
    return css(rgb(name))


def shimmer(name: str) -> str:
    return css(mix(name, "FG", 0.6))


def tint(name: str, t: float) -> str:
    return css(mix(name, "BG", t))


overrides = {
    "claude": c("ACCENT"),
    "claudeShimmer": shimmer("ACCENT"),
    "claudeBlue_FOR_SYSTEM_SPINNER": c("BLUE"),
    "claudeBlueShimmer_FOR_SYSTEM_SPINNER": shimmer("BLUE"),
    "permission": c("BLUE"),
    "permissionShimmer": shimmer("BLUE"),
    "autoAccept": c("PURPLE"),
    "autoAcceptShimmer": shimmer("PURPLE"),
    "skill": c("PURPLE"),
    "planMode": c("GREEN"),
    "ide": c("BLUE"),
    "bashBorder": c("GREEN"),
    "fastMode": c("ORANGE"),
    "fastModeShimmer": shimmer("ORANGE"),
    "effortUltra": c("PURPLE"),
    "text": c("FG"),
    "inverseText": c("BG"),
    "background": c("BG"),
    "inactive": c("MUTED"),
    "inactiveShimmer": shimmer("MUTED"),
    "subtle": c("BORDER"),
    "promptBorder": c("BORDER"),
    "promptBorderShimmer": c("MUTED"),
    "suggestion": c("BLUE"),
    "remember": c("BLUE"),
    "selectionBg": c("BG_ALT"),
    "rate_limit_fill": c("ACCENT"),
    "rate_limit_empty": c("BORDER"),
    "success": c("GREEN"),
    "error": c("RED"),
    "warning": c("YELLOW"),
    "warningShimmer": shimmer("YELLOW"),
    "merged": c("PURPLE"),
    "diffAdded": tint("GREEN", 0.25),
    "diffRemoved": tint("RED", 0.25),
    "diffAddedDimmed": tint("GREEN", 0.12),
    "diffRemovedDimmed": tint("RED", 0.12),
    "diffAddedWord": tint("GREEN", 0.45),
    "diffRemovedWord": tint("RED", 0.45),
    "userMessageBackground": c("BG_ALT"),
    "userMessageBackgroundHover": c("SURFACE"),
    "bashMessageBackgroundColor": c("SURFACE"),
    "memoryBackgroundColor": c("SURFACE"),
    "red_FOR_SUBAGENTS_ONLY": c("RED"),
    "blue_FOR_SUBAGENTS_ONLY": c("BLUE"),
    "green_FOR_SUBAGENTS_ONLY": c("GREEN"),
    "yellow_FOR_SUBAGENTS_ONLY": c("YELLOW"),
    "purple_FOR_SUBAGENTS_ONLY": c("PURPLE"),
    "orange_FOR_SUBAGENTS_ONLY": c("ORANGE"),
}

theme = {"name": "dotfiles", "base": base if base in ("dark", "light") else "dark", "overrides": overrides}
with open(path, "w") as f:
    f.write(json.dumps(theme, indent=2) + "\n")
