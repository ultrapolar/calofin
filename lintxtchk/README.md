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

## Layout parameters

These are set near the top of `LINTXTCHK.lsp` and are easy to tweak:

| Variable  | Default        | Meaning |
| --------- | -------------- | --- |
| `height`  | `12.0`         | Text height (12") |
| `spacing` | `height * 1.6` | Vertical distance between successive lines |
| `indent`  | `height * 1.5` | Horizontal indent applied per sub-level |

The command saves and restores `OSMODE`, so running snaps won't pull the
text off its grid, and your osnap settings are left as they were.

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
