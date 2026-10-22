---
name: Multi-step todo workflow
description: Use for longer, multi-step tasks - creates a todo list with the todowrite tool, works through it item by item, and tracks progress until every item is completed
---

Follow this workflow for multi-step work (refactors, migrations, features spanning several files).

1. First read the relevant code (read/glob/grep) to understand the current state.
2. Create a todo list with the `todowrite` tool: 2-8 concrete, checkable items.
3. Work through the items in order and update the list with `todowrite` as you go
   (status moves pending -> in_progress -> completed).
4. Do not finish while items are still `in_progress` or `pending` - mark them completed or explicitly skipped.
