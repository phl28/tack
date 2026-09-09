---
name: example-skill
description: Template skill showing profile gating. Copy it, or delete it.
profiles: [common]
---

# Example skill

`profiles:` in the frontmatter decides which machines this is linked on:

- `common` (or omitting the field entirely) -- linked everywhere
- `[work]` -- linked only when the active profile is `work`
- `[personal, home]` -- linked under either of those profiles

The file is still committed and shared in every case. Profiles filter at *link*
time, so one branch works on every machine; nothing needs to be hidden from git.
Content that genuinely cannot be committed goes in `local/` instead.
