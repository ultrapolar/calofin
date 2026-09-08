# LINTXTCHK — Liner Text Checklist (AutoLISP)

An AutoLISP command for AutoCAD that stamps the vinyl pool-liner drawing
checklist into a drawing. Each checklist line is placed as its **own TEXT
entity** at a point you pick, using **12" text**, spaced out vertically
automatically. Sub-items are indented under their parent item.

## Install

1. In AutoCAD run `APPLOAD`.
2. Browse to `LINTXTCHK.lsp` and load it (add it to the *Startup Suite* to
   have it load every session).

## Use

1. Type `LINTXTCHK` at the command line.
2. Pick the top-left point for the checklist.

The full checklist is written downward from that point, one clickable TEXT
line at a time. Because every line is a separate entity, you can move,
edit, erase, or grip-drag each item independently as you work through the
drawing.

## Tunables

Every value LINTXTCHK reads that you might want to change sits in one
`TUNABLES` block at the top of `LINTXTCHK.lsp`, each with a comment saying
what it does, its units, and what raising or lowering it changes. Edit
the value and APPLOAD the file again, or type the `setq` at the command
line to try a value for one session -- every knob is read when the
command runs, not when the file loads.

The tables below are the block, read off it:

**How the column is laid out**

| Global | Default | Meaning |
| --- | --- | --- |
| `ltc:*height*` | `12.0` | Text height, in drawing units (1 unit = 1 inch on the shop's sheets). The next two are multiples of it, so changing this alone rescales the whole block and keeps its proportions |
| `ltc:*spacing*` | `1.6` | Vertical distance between lines, and the horizontal indent per sub-level, both as multiples of the text height. 1.6 leaves a comfortable gap; under about 1.2 the lines start to touch |
| `ltc:*indent*` | `1.5` | Vertical distance between lines, and the horizontal indent per sub-level, both as multiples of the text height. 1.6 leaves a comfortable gap; under about 1.2 the lines start to touch |
| `ltc:*bullet*` | `"- "` | What every line is prefixed with. "" gives a plain column, "[ ] " gives boxes to tick |

These carry a table or a list rather than a single value, so they are named here rather than tabled with a default:

- `ltc:*items*` -- Each entry is (indent-level . "line text"). Level 0 is a main item, 1 a sub-item indented under the one above it; a deeper level simply indents further. Inner double quotes and inch marks are escaped with a backslash. This is the shop's checklist, so it is content rather than a setting -- but it sits here, at the top, because editing it is why most people open this file. Add, remove or reword a line and the count in the done message follows on its own
## The checklist

- Read all WSN (White Screen Notes), Notes from Merlin, and Customer Info
  - Does this job actually require a Tech drawing?
- Verify Finished Wall Ht & Pool Depth
  - Finished Wall Ht should be a single value, or "Varies" if needed
- Place liner pattern block (GLP) - Delete "Not Supplied" text
- Verify the type of pool bead, or overlap for AG, etc
- Pool perimeter & overall dims
- Verify orientation: Shallow end to the RIGHT of page
- Report ALL cross dimensions provided by customer
- Pool corners with dimensions
  - Look out special mfgrs like Esther Williams (3x3, 5x5) or Foxx (37" Deep)
- Look for special bottom conditions:
  - Does the shallow end have a Cove?
  - Does the pool have a Safety Ledge?
  - Did the customer provide various depths for the bottom?
  - Does the pool require a side view?
- Are hopper corners radius?
- Did you draw trowel lines accurately?
- Are steps / bench Fiberglass?
  - Place FGS note or draw step outline if dimensions were provided
  - Is the step Straight or Radius? Ask if not given
- Are steps / bench Vinyl-covered?
  - Verify step corner type & dimensions
  - Place Step Attachment block - is the attachment type provided?
  - Place side views for all steps and benches
- Did you scale the titleblock? REDVIEW!
