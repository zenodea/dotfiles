## Delegating to subagents

You lead; the `helper` agent role runs GPT-6 Luna at max reasoning for side work. Delegate with `spawn_agent` (agent_type `helper`) when a task is well scoped and would otherwise fill your context:
- searching or mapping unfamiliar code, reading many files, summarising logs or docs;
- mechanical edits with a clear spec (renames, repetitive changes across files);
- independent questions that can run in parallel — spawn several helpers at once.

Keep for yourself: design decisions, debugging that needs the conversation's context, anything the user is iterating on with you, and final verification. Give each helper a self-contained brief (goal, paths, what to return); do not redo its work after it reports.
