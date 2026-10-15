# Task 4 — Prompt history for the visualisation

Complete, in-order record of every AI prompt used to create `booth_visualisation.html`, as required
for submission ("the complete history of prompts used to create the visualisation, together with
any skills files or other relevant Markdown files used"). Prompts are pasted verbatim.

| Field | Value |
|---|---|
| Enhancement visualised (Task 3) | Radix-2 Booth signed multiplication in `MCycle.v` (MCycleOp = 00) |
| Part 1 — original page | Hin Lok, 14 Oct 2026 (tool/model: *to be filled in by Hin Lok*) |
| Part 2 — enhancements | Claude (Anthropic), model Claude Opus 5.5, 15 Oct 2026 |

---

## Part 1 — Original visualisation (Hin Lok)

> **TODO (Hin Lok):** paste every prompt from your `PROMPT_HISTORY.md` here, verbatim and in order,
> including follow-ups and fixes, and state the tool/model and date. Add your `GUIDE.md` (and any
> skills or other Markdown files you gave the model) to this folder and list them below.
> `MCycle.v` mentions both files.

### Files given to the model
- *(to be filled in)*

### Prompts
- *(to be filled in)*

---

## Part 2 — Enhancements (Claude)

### Files given to the model
- `booth_visualisation.html` (Part 1 output)
- `MCycle.v` with the radix-2 Booth enhancement (Hin Lok)
- `CG3207_Task1_Division_Dataflow.html` (Qi Ye's division study aid)
- The group chat excerpt quoted in the prompt below, together with the rest of the session
  (the Assignment 3 manual, the group's MCycle.v / RV.v / Decoder.v and testbenches)

### Prompt 1 (15 Oct 2026)
```
[group chat excerpt, 14–15 Oct 2026 — summarised here, not verbatim: the group agrees to use
 Hin Lok's radix-2 Booth implementation for Tasks 3 and 4; Hin Lok shares booth_visualisation.html
 and MCycle.v; Qi Ye shares CG3207_Task1_Division_Dataflow.html]

combine these works in and enhance them as needed
```
The instruction line is verbatim. If the full chat text is needed, paste it in place of the
bracketed summary.

### What was changed in response
The algorithm/model code (`<script id="booth-model">`) was **not** changed. It was checked against
the RTL: every 4- and 6-bit operand pair gives the right product, and the A / Q / Q₋₁ values after
every clock edge equal an Icarus Verilog simulation of `MCycle.v` (4-, 8- and 32-bit cases,
including −2^31 × −1). Added:

1. A **datapath diagram** card (SVG). It shows M, the −M (= ~M + 1) path, the 3-way select
   (+M / −M / 0) driven by the Booth control reading {Q₀, Q₋₁}, the (w+1)-bit adder, the
   arithmetic right shift, and the A / Q / Q₋₁ registers. The path used at the current edge is
   highlighted, with live hex values on the wires. It addresses the brief's "state of the relevant
   registers and other important datapath elements".
2. **Cycle counts including the write-back cycle** (Booth w+1 vs template 2w+1, e.g. 33 vs 65 at
   32 bits), matching the CPU testbench and the cycle counter on the board.
3. **Hex operand input** (e.g. `0xFFFFFFFD`), so values read off the board's 7-segment display can
   be typed in directly, with an error message for invalid input.
4. A footer note that the page was checked against the RTL.
