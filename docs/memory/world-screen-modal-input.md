---
name: world-screen-modal-input
description: a world-screen menu or text box must swallow both the opening key's textinput and the polled WASD/E/F intents
metadata:
  type: context
---

**Why:** LÖVE fires `keypressed` before `textinput` for the same key, so a key that opens a search box also types its character into it. Separately, `Input.updateIntents` (`src/app/input.lua`) polls `love.keyboard.isDown` every fixed step, whatever screen UI is open. Typing "e" or "w" in a box would then harvest or walk.
**How to apply:** Any world-screen UI that takes keys or text (the context menu, the building picker). Drop the `textinput` that arrives in the frame the UI opened, and send empty intents while it is open.
