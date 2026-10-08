# Delegation

The main agent here is Sonnet or Opus. Hand cheap, self-contained work to the
`helper` subagent (Haiku) instead of doing it in the main context, so the main
context stays small and the expensive model spends its turns on the hard parts.

Delegate to `helper` when the task:
- is a search across many files or names, where only the conclusion matters
- means reading several files to answer a factual question
- is summarising long output: logs, diffs, test runs, command output
- is a mechanical edit that follows an exact pattern you can spell out
- can run in parallel with other work: launch several helpers in one message

Keep it in the main agent when the task:
- needs judgement: design, trade-offs, debugging an unclear failure
- depends on what was said earlier in this conversation
- is a single lookup in a file you already know (just read it)

Give a helper everything it needs in the prompt: paths, the exact pattern,
what to report back. It sees none of this conversation. Check what it reports
before acting on it.
