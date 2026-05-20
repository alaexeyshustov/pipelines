---
status: proposed
---

# Replace string-based executor dispatch with an explicit registry

`PipelineRunner` dispatches to `Executable` services by calling `constantize` on a stored class name string. The `Executable` concern documents `.call(input, params) → Hash` but does not enforce it — it is a comment-only contract. Four executors exist, making this a real seam, but adding a fifth requires touching the concern, the new file, and `PipelineRunner`'s dispatch logic. Tests must stub `constantize` rather than satisfy an interface.

Register executors explicitly (a hash or a small registry object) and remove the `constantize` call. `PipelineRunner` calls through the registry without knowing the class name. Test doubles satisfy the actual `#call` interface. Adding a new executor is one class plus one registration entry.
