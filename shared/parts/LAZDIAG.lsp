;;; ======================================================================
;;; LAZDIAG.lsp  --  when a calofin command fails, say so and write the
;;;                  whole failure out as a DXF to send in
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  LAZDIAG     write the last failure's report again -- and,
;;;                        when nothing has failed, prove the whole path
;;;                        works by writing a test report to the same
;;;                        folder a real one would go to
;;;            LAZDIAGVER  print the loaded version
;;;
;;; SHARED BUILD: requires CALOFIN-LIB.lsp (load via CALOFIN-LOADER.lsp).
;;; Generic helpers live there under cal: - see STANDARDS.md.
;;;
;;;  This file is not a drafting tool.  It is the thing every other tool
;;;  calls when it falls over, and what it does is turn a failure into a
;;;  file somebody can diagnose from.
;;;
;;;  WHAT A FAILURE USED TO LOOK LIKE.  A tool's *error* handler put the
;;;  user's settings back, closed the undo group and printed one line:
;;;
;;;      POOL error: bad argument type: numberp: nil
;;;
;;;  That line is true and nearly useless.  It does not say which of
;;;  POOL's forty prompts had been answered, what was typed into them,
;;;  which geometry was on screen, or what the drawing looked like when
;;;  it happened.  The drafter reads it, shrugs, and tries again; if it
;;;  fails the same way twice they send a message saying "POOL is
;;;  broken", and the whole diagnosis starts from nothing.
;;;
;;;  WHAT IT LOOKS LIKE NOW.  The same failure prints
;;;
;;;      POOL error: bad argument type: numberp: nil
;;;
;;;      [calofin] POOL v2.7 has failed -- this is a bug, not something
;;;      [calofin] you did wrong.  An error report has been written to
;;;      [calofin]     C:\Users\dm\Downloads\POOL-v2.7-error-2026-09-11-1432.dxf
;;;      [calofin] Send that file in for diagnosis.  It holds a copy of
;;;      [calofin] the geometry, every prompt and answer of the run, and
;;;      [calofin] what AutoCAD was doing when it stopped.  Your drawing
;;;      [calofin] has not been touched.
;;;
;;;  and the file it names holds, as DXF entities anyone can open:
;;;
;;;    * a COPY of the geometry -- everything the run drew, plus whatever
;;;      it had registered as its input (lzd:watch) and every point that
;;;      was picked, each labelled with the prompt it came from;
;;;    * the transcript, prompt by prompt, from the start of the run;
;;;    * the tool, its version, and whether it came from a standalone
;;;      file or from LAZPASS;
;;;    * the error text, the last step the tool got to, AutoCAD's own
;;;      ERRNO / CMDNAMES / LASTPROMPT, and the sysvars that matter.
;;;
;;;  WHY A SEPARATE FILE AND NOT THE USER'S DRAWING.  The first design
;;;  put the report into the open drawing and asked the user to click
;;;  somewhere clear of their work to land it.  That is worse in every
;;;  direction: it asks somebody who has just been told their command
;;;  crashed to make a careful decision, it writes into the file they
;;;  care about at the exact moment they trust it least, "somewhere
;;;  clear" is a guess that lands on top of a viewport as often as not,
;;;  and what they then have to send is the whole job drawing.  A DXF in
;;;  the Downloads folder asks nothing, touches nothing, and is the one
;;;  thing that is safe to hand over -- it holds the failure and no more
;;;  of the drawing than the failure needed.
;;;
;;;  The click-into-the-drawing path still exists -- lzd:paste, reached
;;;  by typing LAZDIAG after a report that could not be written -- and it
;;;  is a LAST RESORT, for the machine where no candidate folder would
;;;  open.  Nothing reaches it automatically.
;;;
;;;  NOTHING HERE MAY THROW.  This code runs from inside *error*, which
;;;  is the one place in AutoLISP where an error has nowhere to go: a
;;;  second failure inside a handler leaves the undo group open, the
;;;  sysvars wrong and no message at all.  So lzd:report is a guard
;;;  around lzd:report-1: the work is done under vl-catch-all-apply, a
;;;  re-entry while the reporter is already running is refused rather
;;;  than nested, and every path -- including the one where the report
;;;  itself fails -- still prints a line telling the user what happened.
;;;  The rule for anything added below: if it can fail, it fails INSIDE
;;;  that catch, and the user still gets told.
;;;
;;;  WHAT IT CANNOT DO.  AutoLISP hands *error* a message and nothing
;;;  else: there is no stack, no file, and no line number, and no amount
;;;  of cleverness here invents one.  What stands in for a line number is
;;;  the breadcrumb -- lzd:step, which the ask helpers set for themselves
;;;  so a form-driven tool leaves a trail without being asked -- plus the
;;;  transcript and LASTPROMPT.  Together they say which prompt the run
;;;  died at, which is the question a line number would have answered.
;;;  The report says so in as many words rather than implying it knows
;;;  more than it does.
;;;
;;;  R12 DXF, ON PURPOSE.  The file is written by hand, group code by
;;;  group code, as AC1009 -- the oldest DXF there is.  Three reasons:
;;;  the writing happens inside an error handler, where (command) is
;;;  refused and DXFOUT is not reachable; AC1009 needs no handles, no
;;;  classes and no objects section, so there is no bookkeeping to get
;;;  wrong at the worst possible moment; and every AutoCAD since has read
;;;  it.  Modern entities are flattened down to R12 primitives on the way
;;;  out (lzd:flatten) -- an LWPOLYLINE becomes a POLYLINE with its
;;;  bulges intact, an MTEXT becomes TEXT -- and anything with no R12
;;;  spelling is written as its bounding box with a label naming the type,
;;;  so a reader can see something was there rather than silently not.
;;; ======================================================================

(setq *lazdiag-version* "v1.1")  ; announced on load; release_lisp.py
                                 ; stamps releases/ from this line

;; lzd:bbox reaches ActiveX for the bounding box of an entity with no R12
;; spelling, and the folder walk uses vl-mkdir.  At the top of the file,
;; not inside a command: this one has to be ready before the FIRST
;; failure, and a command body that has already died is not going to run
;; it.  (The grouped build gets it from CALOFIN-LIB too; loading the VL
;; extensions twice is a no-op, and a standalone file has to load alone.)
(vl-load-com)

;;; -------------------- tunables ----------------------------------------

;; How many entities a report will copy.  A run that drew ten thousand
;; things before falling over is a real failure mode, and a DXF of all
;; of them is one nobody can mail.  The report says when it truncated.
(setq lzd:*max-ents* 400)

;; How many transcript lines are kept.  A tutorial loop can princ for
;; ever; the last 200 lines are the ones that led to the failure.
(setq lzd:*max-log* 200)

;; Where reports go, tried in order.  The first that accepts the file
;; wins.  "" means "ask the drawing" -- see lzd:candidates.
(setq lzd:*subdir* "Downloads")

;;; -------------------- the run context ---------------------------------
;;; Set by lzd:begin at the top of a command and dropped by lzd:end at
;;; the bottom.  Globals rather than locals because *error* runs after
;;; the command's own locals have gone.

;; One setq each, declared at top level, because check_scope reads this
;; block to decide which lzd:* names a defun is allowed to assign.
(setq lzd:*tool* nil)      ; the command that is running, as typed
(setq lzd:*ver* nil)       ; its version banner, or nil
(setq lzd:*started* nil)   ; when the run began, as a human date
(setq lzd:*mark* nil)      ; entlast at the start: what this run drew is
                           ; everything after it
(setq lzd:*log* nil)       ; the transcript, newest first
(setq lzd:*step* nil)      ; the last breadcrumb
(setq lzd:*watch* nil)     ; enames the tool registered as its input
(setq lzd:*pts* nil)       ; (label . point) for every point picked
(setq lzd:*inside* nil)    ; the reporter is running -- refuse re-entry
(setq lzd:*last* nil)      ; the last report, for LAZDIAG to write again
(setq lzd:*lastfile* nil)  ; where it went, nil if it could not be written

;;; -------------------- small helpers -----------------------------------

;; A DXF real.  rtos mode 2 is DECIMAL whatever LUNITS says -- the
;; default mode would write 25'-6" into a group 10 on an architectural
;; drawing, which is not a number and would not load.
(defun lzd:num (v)
  (if (numberp v) (rtos (float v) 2 8) "0.0"))

;; Group codes are conventionally right-justified in three columns.  No
;; reader needs it; an editor showing the file to a human does.
(defun lzd:pad3 (n / s)
  (setq s (itoa n))
  (while (< (strlen s) 3) (setq s (strcat " " s)))
  s)

;; "2026-09-11-143207" -- the stamp in a report's file name.  CDATE
;; decoded arithmetically, never through rtos: DIMZIN trims rtos output
;; and would drop the seconds, and two reports a minute apart would then
;; fight over one name.
(defun lzd:stamp ( / d dd tt)
  (setq d  (getvar "CDATE")
        dd (fix d)
        tt (- d dd))
  (strcat (itoa (fix (/ dd 10000))) "-"
          (cal:zeropad2 (rem (fix (/ dd 100)) 100)) "-"
          (cal:zeropad2 (rem dd 100)) "-"
          (cal:zeropad2 (fix (+ (* tt 100) 1e-6))) 
          (cal:zeropad2 (rem (fix (+ (* tt 10000) 1e-4)) 100))
          (cal:zeropad2 (rem (fix (+ (* tt 1000000) 1e-2)) 100))))

;; Anything at all, as something safe to put in a one-line DXF string.
;; Newlines and tabs would end the value early and shift every group
;; code after it by one line, which is a file that will not load.
(defun lzd:str (v / s out i c n)
  (setq s (cond ((null v) "nil")
                ((= (type v) 'STR) v)
                ((= (type v) 'INT) (itoa v))
                ((= (type v) 'REAL) (lzd:num v))
                ((= (type v) 'SYM) (vl-princ-to-string v))
                ((and (listp v) (numberp (car v)))
                 (strcat "(" (lzd:num (car v)) " " (lzd:num (cadr v)) ")"))
                (t (vl-princ-to-string v))))
  (setq out "" i 1 n (strlen s))
  (while (<= i n)
    (setq c (substr s i 1))
    (setq out (strcat out (if (or (< (ascii c) 32) (> (ascii c) 126))
                              " " c))
          i (1+ i)))
  (if (> (strlen out) 240) (substr out 1 240) out))

;; T when MSG is a plain cancel rather than a real failure.  Esc is not
;; a bug and must never write a report -- a drafter who backs out of
;; POOL twenty times a day would otherwise find twenty DXFs in
;; Downloads.  STANDARDS section 5's canonical test.
(defun lzd:cancel-p (msg)
  (and msg (= (type msg) 'STR)
       (wcmatch (strcase msg) "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))

;;; -------------------- the transcript ----------------------------------
;;; What the tool and the user said to each other, in order.  Everything
;;; here is cheap and silent: a tool that calls these on every prompt
;;; must not pay for it on the runs that do not fail.

;; Start a run.  TOOL is the command name as the user typed it, VER the
;; tool's own version global (or nil).  Called at the top of every
;; command, and at the top of every helper that carries an *error*
;; handler of its own.
;;
;; A DIFFERENT tool's context is dropped; the SAME tool's is kept and
;; added to.  Both halves of that matter:
;;
;;   dropped, because a run that ended cleanly leaves its transcript
;;   behind, and handing POOL's prompts to ABCDEF's failure would
;;   produce a report that is wrong and looks right -- the one outcome
;;   worse than no report at all.  lzd:mine-p makes the same judgement
;;   at report time, so this is belt and braces.
;;
;;   kept, because a tool is often two defuns with a handler each --
;;   c:COVERCHECK sets a drawing up and cchk:scan walks it, and both
;;   begin.  Resetting on the second would throw away the first phase's
;;   prompts AND move lzd:*mark* past the geometry phase one drew, so
;;   the report would be missing exactly the half that explains the
;;   other.  Each entry prints its own "--- started" line, so a
;;   transcript that does span two runs of one tool says so rather than
;;   running them together.
(defun lzd:begin (tool ver)
  (if (not (lzd:mine-p tool))
    (setq lzd:*tool*    (lzd:str tool)
          lzd:*started* (cal:datestr)
          lzd:*mark*    (entlast)
          lzd:*log*     nil
          lzd:*step*    nil
          lzd:*watch*   nil
          lzd:*pts*     nil))
  (setq lzd:*ver* ver)
  (lzd:say (strcat "--- " (lzd:str tool) " started"
                   (if ver (strcat " " (lzd:str ver)) "")))
  tool)

;; There is deliberately no lazy "open a context on the first prompt"
;; here.  One mechanism opens a context -- lzd:begin, at the top of a
;; command -- and that is what makes the transcript trustworthy: it is
;; the one moment that is definitely inside the run that is about to
;; fail.  A prompt recorded with no context still lands in lzd:*log*,
;; where the cap keeps it from growing, and lzd:mine-p throws it away at
;; report time rather than attributing it to the wrong tool.

;; A clean finish.  Drops the context so the NEXT failure does not
;; report this run's prompts -- a stale transcript is worse than none,
;; because it is wrong and looks right.
;; Through lzd:mine-p, so "is this my context" is decided in ONE place
;; and case-insensitively -- a tool that ended a context it did not own
;; would throw away the prompts of the run still going on around it.
(defun lzd:end (tool)
  (if (or (null tool) (null lzd:*tool*) (lzd:mine-p tool))
    (lzd:disown))
  nil)

;; One line of transcript.  The list is NEWEST first, so capping it is
;; taking the first lzd:*max-log* of it and no reversing at all: a
;; tutorial loop that princ'd for an hour must lose its opening, not the
;; prompts that led to the failure a moment ago.
(defun lzd:say (line)
  (setq lzd:*log* (cons (lzd:str line) lzd:*log*))
  (if (> (length lzd:*log*) lzd:*max-log*)
    (setq lzd:*log* (lzd:firstn lzd:*log* lzd:*max-log*)))
  nil)

(defun lzd:firstn (lst n / out)
  (while (and lst (> n 0))
    (setq out (cons (car lst) out) lst (cdr lst) n (1- n)))
  (reverse out))

;; A prompt and what came back.  This is the call the ask helpers make,
;; and it is the whole reason a report can say which question the run
;; died on.
(defun lzd:ask (prompt answer)
  (lzd:step prompt)
  (lzd:say (strcat "  ? " (lzd:str prompt)
                   "   -> " (lzd:str answer)))
  answer)

;; The breadcrumb that stands in for a line number.  The last one set is
;; the last place in the tool the run is known to have reached.
(defun lzd:step (label)
  (setq lzd:*step* (lzd:str label))
  nil)

;; Register geometry the tool did not draw but is working ON -- the
;; selection it was handed, the entity it was asked to measure.  Takes an
;; ename, a selection set, or a list of either.
(defun lzd:watch (x / i e)
  (cond
    ((null x) nil)
    ((= (type x) 'ENAME) (setq lzd:*watch* (cons x lzd:*watch*)))
    ((= (type x) 'PICKSET)
     (setq i 0)
     (while (< i (sslength x))
       (setq lzd:*watch* (cons (ssname x i) lzd:*watch*) i (1+ i))))
    ((listp x) (foreach e x (lzd:watch e))))
  nil)

;; A point the user picked, with the prompt it answered.  These are
;; drawn into the report as labelled points: for half the tools here the
;; picks ARE the geometry that caused the failure.
(defun lzd:pt (label p)
  (if (and p (listp p) (numberp (car p)))
    (setq lzd:*pts* (cons (cons (lzd:str label) p) lzd:*pts*)))
  p)

;;; -------------------- gathering the geometry --------------------------

;; Everything drawn since lzd:begin.  entlast was snapshotted then, so
;; the run's own output is whatever comes after it -- and a nil mark
;; means the drawing was empty, in which case everything is the run's.
;; Entities the run drew and then erased come back nil from entget and
;; are dropped rather than crashing the walk.
(defun lzd:drawn ( / e out n)
  (setq e (if lzd:*mark* (entnext lzd:*mark*) (entnext))
        n 0)
  (while (and e (< n lzd:*max-ents*))
    (if (entget e) (setq out (cons e out) n (1+ n)))
    (setq e (entnext e)))
  (reverse out))

;; The run's input and its output together, each entity once.  Input
;; first: it is the geometry that was already on the sheet, and reading
;; the report that is what you want to see before what the tool made of
;; it.
;; CAPPED, and capped over the WHOLE list rather than over each half.
;; lzd:drawn stops at lzd:*max-ents* on its own, but the watched input
;; had no limit at all: a tool that selects a hundred dimensions and
;; then draws is two hundred entities in a file somebody has to mail,
;; and one that selects a thousand is a report nobody can open.  The
;; count is in the report, and it says when it truncated.
(defun lzd:gather ( / out e n)
  (setq n 0)
  (foreach e (reverse lzd:*watch*)
    (if (and (< n lzd:*max-ents*) (entget e) (not (member e out)))
      (setq out (cons e out) n (1+ n))))
  (foreach e (lzd:drawn)
    (if (and (< n lzd:*max-ents*) (not (member e out)))
      (setq out (cons e out) n (1+ n))))
  (reverse out))

;;; -------------------- flattening to R12 -------------------------------
;;; Every entity becomes zero or more primitives, each a list whose car
;;; names it:
;;;    ("LINE"   lay p1 p2)
;;;    ("CIRCLE" lay centre radius)
;;;    ("ARC"    lay centre radius from-deg to-deg)
;;;    ("POINT"  lay p)
;;;    ("TEXT"   lay p height string rotation-deg)
;;;    ("PLINE"  lay closed-flag ((x y bulge) ...))
;;; Two reasons for the intermediate form rather than writing straight
;;; out: the report's text block has to be placed clear of the geometry,
;;; which means knowing its extent BEFORE anything is written, and a
;;; list of primitives is something a test can read back and assert on
;;; without parsing a DXF.

(defun lzd:dxf (code ed) (cdr (assoc code ed)))

(defun lzd:lay (ed / v) (if (setq v (lzd:dxf 8 ed)) v "0"))

(defun lzd:deg (r) (if (numberp r) (/ (* r 180.0) pi) 0.0))

;; MTEXT's formatting codes are noise in a report.  The braces and the
;; \f \H \A runs go; \P is the line break MTEXT uses, and becomes a
;; space so the whole string stays one DXF line.
(defun lzd:demtext (s / out i n c)
  (setq out "" i 1 n (strlen s))
  (while (<= i n)
    (setq c (substr s i 1))
    (cond
      ((= c "\\")
       (cond
         ((= (strcase (substr s (1+ i) 1)) "P")
          (setq out (strcat out " ") i (+ i 2)))
         (t ;; a formatting run: skip to its ; terminator, or one char
            (setq i (1+ i))
            (if (wcmatch (strcase (substr s i 1)) "C,F,H,W,Q,T,A,L,O,K")
              (progn
                (while (and (<= i n) (/= (substr s i 1) ";"))
                  (setq i (1+ i)))
                (setq i (1+ i)))
              (setq i (1+ i))))))
      ((or (= c "{") (= c "}")) (setq i (1+ i)))
      (t (setq out (strcat out c) i (1+ i)))))
  out)

;; An LWPOLYLINE's vertices, as (x y bulge).  entget repeats group 10,
;; and the 42 that FOLLOWS a 10 belongs to it -- a vertex with no bulge
;; has no 42 at all, so the pairing has to be positional and cannot be
;; an assoc.
(defun lzd:lwverts (ed / out p code val pair)
  (foreach pair ed
    (setq code (car pair) val (cdr pair))
    (cond
      ((= code 10) (if p (setq out (cons p out)))
                   (setq p (list (car val) (cadr val) 0.0)))
      ((and (= code 42) p) (setq p (list (car p) (cadr p) val)))))
  (if p (setq out (cons p out)))
  (reverse out))

;; An old-style POLYLINE's vertices, walked off its VERTEX children.
(defun lzd:plverts (e / v ed out p)
  (setq v (entnext e))
  (while (and v (setq ed (entget v)) (= (lzd:dxf 0 ed) "VERTEX"))
    (setq p (lzd:dxf 10 ed))
    (if p (setq out (cons (list (car p) (cadr p)
                                (if (lzd:dxf 42 ed) (lzd:dxf 42 ed) 0.0))
                          out)))
    (setq v (entnext v)))
  (reverse out))

;; The bounding box of an entity, through ActiveX, or nil.  Wrapped
;; because this is the one call here that reaches outside AutoLISP, and
;; it is reached from inside an error handler: a failure has to come
;; back as nil and let the caller fall through to its label-only form.
(defun lzd:bbox (e / r mn mx obj)
  ;; the '() is REQUIRED, even for a lambda that takes nothing:
  ;; vl-catch-all-apply with one argument is an error of its own, and
  ;; one it cannot catch -- it is the call to vl-catch-all-apply that is
  ;; malformed.  Written without it, every entity with no R12 spelling
  ;; took the whole report down instead of being labelled.
  (setq r (vl-catch-all-apply
            '(lambda ()
               (setq obj (vlax-ename->vla-object e))
               (vla-getboundingbox obj 'mn 'mx)
               (list (vlax-safearray->list mn) (vlax-safearray->list mx)))
            '()))
  (if (vl-catch-all-error-p r) nil r))

;; The fallback for an entity with no R12 spelling: its bounding box as
;; a rectangle, labelled with the type, so the report shows that
;; something was there and what kind of thing it was.  Better than
;; dropping it silently, which would make the report lie by omission.
(defun lzd:asbox (e ed / bb lo hi lay ty)
  (setq lay (lzd:lay ed) ty (lzd:dxf 0 ed) bb (lzd:bbox e))
  (if bb
    (progn
      (setq lo (car bb) hi (cadr bb))
      (list (list "PLINE" lay 1
                  (list (list (car lo) (cadr lo) 0.0)
                        (list (car hi) (cadr lo) 0.0)
                        (list (car hi) (cadr hi) 0.0)
                        (list (car lo) (cadr hi) 0.0)))
            (list "TEXT" lay (list (car lo) (cadr hi) 0.0) 0.0
                  (strcat "<" ty " not copied>") 0.0)))
    (if (lzd:dxf 10 ed)
      (list (list "POINT" lay (lzd:dxf 10 ed))
            (list "TEXT" lay (lzd:dxf 10 ed) 0.0
                  (strcat "<" ty " not copied>") 0.0)))))

(defun lzd:flatten (e / ed ty lay p)
  (setq ed (entget e))
  (if (null ed)
    nil
    (progn
      (setq ty (lzd:dxf 0 ed) lay (lzd:lay ed))
      (cond
        ((= ty "LINE")
         (list (list "LINE" lay (lzd:dxf 10 ed) (lzd:dxf 11 ed))))
        ((= ty "CIRCLE")
         (list (list "CIRCLE" lay (lzd:dxf 10 ed) (lzd:dxf 40 ed))))
        ((= ty "ARC")
         (list (list "ARC" lay (lzd:dxf 10 ed) (lzd:dxf 40 ed)
                     (lzd:deg (lzd:dxf 50 ed)) (lzd:deg (lzd:dxf 51 ed)))))
        ((= ty "POINT")
         (list (list "POINT" lay (lzd:dxf 10 ed))))
        ((= ty "TEXT")
         (list (list "TEXT" lay (lzd:dxf 10 ed) (lzd:dxf 40 ed)
                     (lzd:dxf 1 ed) (lzd:deg (lzd:dxf 50 ed)))))
        ((= ty "MTEXT")
         (list (list "TEXT" lay (lzd:dxf 10 ed) (lzd:dxf 40 ed)
                     (lzd:demtext (lzd:dxf 1 ed))
                     (lzd:deg (lzd:dxf 50 ed)))))
        ((= ty "LWPOLYLINE")
         (list (list "PLINE" lay (logand 1 (if (lzd:dxf 70 ed)
                                               (lzd:dxf 70 ed) 0))
                     (lzd:lwverts ed))))
        ((= ty "POLYLINE")
         (list (list "PLINE" lay (logand 1 (if (lzd:dxf 70 ed)
                                               (lzd:dxf 70 ed) 0))
                     (lzd:plverts e))))
        ((= ty "SOLID")
         (list (list "PLINE" lay 1
                     (list (lzd:dxf 10 ed) (lzd:dxf 11 ed)
                           (lzd:dxf 13 ed) (lzd:dxf 12 ed)))))
        ;; A dimension is a block in the drawing and has no R12 form
        ;; worth rebuilding.  What a diagnosis needs off one is what it
        ;; was measuring and what it said: the two extension-line
        ;; origins as a line, and the measurement as text.
        ((= ty "DIMENSION")
         (setq p (lzd:dxf 11 ed))
         (append
           (if (and (lzd:dxf 13 ed) (lzd:dxf 14 ed))
             (list (list "LINE" lay (lzd:dxf 13 ed) (lzd:dxf 14 ed))))
           (if p
             (list (list "TEXT" lay p 0.0
                         (strcat "<DIM "
                                 (if (and (lzd:dxf 1 ed)
                                          (/= (lzd:dxf 1 ed) ""))
                                   (lzd:dxf 1 ed)
                                   (lzd:num (lzd:dxf 42 ed)))
                                 ">")
                         0.0)))))
        ((= ty "INSERT")
         (list (list "POINT" lay (lzd:dxf 10 ed))
               (list "TEXT" lay (lzd:dxf 10 ed) 0.0
                     (strcat "<INSERT " (lzd:str (lzd:dxf 2 ed)) ">") 0.0)))
        (t (lzd:asbox e ed))))))

;; Every point a primitive occupies, for the extent below.
(defun lzd:prim-pts (pr)
  (cond
    ((= (car pr) "LINE")   (list (caddr pr) (cadddr pr)))
    ((= (car pr) "POINT")  (list (caddr pr)))
    ((= (car pr) "TEXT")   (list (caddr pr)))
    ((or (= (car pr) "CIRCLE") (= (car pr) "ARC"))
     (list (list (- (car (caddr pr)) (cadddr pr))
                 (- (cadr (caddr pr)) (cadddr pr)))
           (list (+ (car (caddr pr)) (cadddr pr))
                 (+ (cadr (caddr pr)) (cadddr pr)))))
    ((= (car pr) "PLINE")  (nth 3 pr))))

;; (minx miny maxx maxy) over a list of primitives, or nil for none.
(defun lzd:extent (prims / lo hi x y out pr p)
  (foreach pr prims
    (foreach p (lzd:prim-pts pr)
      (if (and p (numberp (car p)) (numberp (cadr p)))
        (progn
          (setq x (car p) y (cadr p))
          (if (null out)
            (setq out (list x y x y))
            (setq out (list (min x (car out)) (min y (cadr out))
                            (max x (caddr out)) (max y (cadddr out)))))))))
  out)

;;; -------------------- writing the DXF ---------------------------------
;;; AC1009 by hand.  lzd:g is the whole format: a group code on its own
;;; line, its value on the next.  Everything below is that call with the
;;; codes filled in, which is why there is no DXF library here to get
;;; out of step with what AutoCAD actually reads.

(setq lzd:*errlayer*  "CALOFIN-ERROR"    ; the report text
      lzd:*picklayer* "CALOFIN-PICKS")   ; the points the user clicked

(defun lzd:g (fp code val)
  (write-line (lzd:pad3 code) fp)
  (write-line val fp))

(defun lzd:gn (fp code v) (lzd:g fp code (lzd:num v)))
(defun lzd:gi (fp code v) (lzd:g fp code (itoa (fix v))))
(defun lzd:gs (fp code s) (lzd:g fp code (lzd:str s)))

;; A point at group BASE -- 10 writes 10/20/30, 11 writes 11/21/31.
(defun lzd:gp (fp base p)
  (lzd:gn fp base       (car p))
  (lzd:gn fp (+ base 10) (cadr p))
  (lzd:gn fp (+ base 20) (if (and (caddr p) (numberp (caddr p)))
                             (caddr p) 0.0)))

(defun lzd:sec (fp name) (lzd:g fp 0 "SECTION") (lzd:g fp 2 name))
(defun lzd:endsec (fp)   (lzd:g fp 0 "ENDSEC"))

(defun lzd:header (fp ext / lo hi)
  (setq lo (if ext (list (car ext) (cadr ext)) '(0.0 0.0))
        hi (if ext (list (caddr ext) (cadddr ext)) '(0.0 0.0)))
  (lzd:sec fp "HEADER")
  (lzd:g fp 9 "$ACADVER")   (lzd:g fp 1 "AC1009")
  (lzd:g fp 9 "$INSBASE")   (lzd:gp fp 10 '(0.0 0.0 0.0))
  (lzd:g fp 9 "$EXTMIN")    (lzd:gp fp 10 lo)
  (lzd:g fp 9 "$EXTMAX")    (lzd:gp fp 10 hi)
  ;; decimal units in the report, whatever the job drawing used: every
  ;; number in here was written by lzd:num as a decimal and must read
  ;; back as one
  (lzd:g fp 9 "$LUNITS")    (lzd:gi fp 70 2)
  (lzd:endsec fp))

(defun lzd:tables (fp layers / l)
  (lzd:sec fp "TABLES")
  ;; CONTINUOUS has to exist before a layer may name it
  (lzd:g fp 0 "TABLE") (lzd:g fp 2 "LTYPE") (lzd:gi fp 70 1)
  (lzd:g fp 0 "LTYPE") (lzd:g fp 2 "CONTINUOUS") (lzd:gi fp 70 0)
  (lzd:g fp 3 "Solid line") (lzd:gi fp 72 65) (lzd:gi fp 73 0)
  (lzd:gn fp 40 0.0)
  (lzd:g fp 0 "ENDTAB")
  (lzd:g fp 0 "TABLE") (lzd:g fp 2 "LAYER") (lzd:gi fp 70 (length layers))
  (foreach l layers
    (lzd:g fp 0 "LAYER") (lzd:gs fp 2 l) (lzd:gi fp 70 0)
    ;; red for the report's own layers, so the diagnosis stands out from
    ;; the copied drawing rather than hiding in it
    (lzd:gi fp 62 (if (or (= l lzd:*errlayer*) (= l lzd:*picklayer*)) 1 7))
    (lzd:g fp 6 "CONTINUOUS"))
  (lzd:g fp 0 "ENDTAB")
  (lzd:endsec fp))

(defun lzd:prim-out (fp pr / ty lay v)
  (setq ty (car pr) lay (cadr pr))
  (cond
    ((= ty "LINE")
     (lzd:g fp 0 "LINE") (lzd:gs fp 8 lay)
     (lzd:gp fp 10 (caddr pr)) (lzd:gp fp 11 (cadddr pr)))
    ((= ty "CIRCLE")
     (lzd:g fp 0 "CIRCLE") (lzd:gs fp 8 lay)
     (lzd:gp fp 10 (caddr pr)) (lzd:gn fp 40 (cadddr pr)))
    ((= ty "ARC")
     (lzd:g fp 0 "ARC") (lzd:gs fp 8 lay)
     (lzd:gp fp 10 (caddr pr)) (lzd:gn fp 40 (cadddr pr))
     (lzd:gn fp 50 (nth 4 pr)) (lzd:gn fp 51 (nth 5 pr)))
    ((= ty "POINT")
     (lzd:g fp 0 "POINT") (lzd:gs fp 8 lay) (lzd:gp fp 10 (caddr pr)))
    ((= ty "TEXT")
     (lzd:g fp 0 "TEXT") (lzd:gs fp 8 lay)
     (lzd:gp fp 10 (caddr pr))
     (lzd:gn fp 40 (if (and (cadddr pr) (> (cadddr pr) 0.0))
                       (cadddr pr) 1.0))
     (lzd:gs fp 1 (nth 4 pr))
     (lzd:gn fp 50 (if (nth 5 pr) (nth 5 pr) 0.0)))
    ((= ty "PLINE")
     (lzd:g fp 0 "POLYLINE") (lzd:gs fp 8 lay)
     (lzd:gi fp 66 1) (lzd:gi fp 70 (if (caddr pr) (caddr pr) 0))
     (lzd:gp fp 10 '(0.0 0.0 0.0))
     (foreach v (nth 3 pr)
       (lzd:g fp 0 "VERTEX") (lzd:gs fp 8 lay)
       ;; x and y explicitly, Z always zero: a vertex here is
       ;; (x y bulge), and handing the whole triple to lzd:gp would
       ;; write the bulge into group 30 and lose the curve twice over
       (lzd:gp fp 10 (list (car v) (cadr v) 0.0))
       (if (and (caddr v) (numberp (caddr v)) (/= (caddr v) 0.0))
         (lzd:gn fp 42 (caddr v))))
     (lzd:g fp 0 "SEQEND") (lzd:gs fp 8 lay))))

;; Every layer the primitives name, plus the report's own two.  A layer
;; an entity sits on but the table does not list is the one way this
;; file fails to load.
(defun lzd:layers (prims / out l pr)
  (setq out (list "0" lzd:*errlayer* lzd:*picklayer*))
  (foreach pr prims
    (setq l (cadr pr))
    (if (and l (= (type l) 'STR) (not (member l out)))
      (setq out (cons l out))))
  (reverse out))

;; Write it.  Returns the path on success and nil when the file would
;; not open, which is the signal lzd:write walks its candidate folders
;; on.  Nothing in here may throw: it is called from inside *error*.
(defun lzd:dxfwrite (path prims / fp ext pr)
  (setq fp (open path "w"))
  (if (null fp)
    nil
    (progn
      (setq ext (lzd:extent prims))
      (lzd:header fp ext)
      (lzd:tables fp (lzd:layers prims))
      (lzd:sec fp "ENTITIES")
      (foreach pr prims (lzd:prim-out fp pr))
      (lzd:endsec fp)
      (lzd:g fp 0 "EOF")
      (close fp)
      path)))

;;; -------------------- where the file goes -----------------------------

;; Downloads, and four ways to still write something if it is not there.
;; In order: an explicit override for a shop that wants reports
;; elsewhere; the two spellings of the user's profile; the folder the
;; job drawing is in; AutoCAD's own temp folder, which is writable on
;; every machine that can run AutoCAD at all.
;; Add DIR to the list unless it is nothing, or already on it.  Both
;; halves are real: an unsaved drawing answers DWGPREFIX with "" and
;; only nil is false in AutoLISP, so the empty string would go on the
;; list and the report would be written to whatever AutoCAD's working
;; directory happened to be, under a name with no folder in front of it
;; -- the one outcome worse than not writing it, because the message
;; then tells the user to send a file they cannot find.  And the two
;; spellings of the profile usually name the SAME folder, which would
;; otherwise be tried twice and listed twice when it failed.
(defun lzd:addcand (lst dir)
  (if (and dir (= (type dir) 'STR) (/= dir "") (not (member dir lst)))
    (cons dir lst)
    lst))

(defun lzd:candidates ( / out h)
  (setq out (lzd:addcand out (getenv "CalofinErrorDir")))
  (if (setq h (getenv "USERPROFILE"))
    (setq out (lzd:addcand out (strcat h "\\" lzd:*subdir*))))
  (if (and (setq h (getenv "HOMEDRIVE")) (getenv "HOMEPATH"))
    (setq out (lzd:addcand out (strcat h (getenv "HOMEPATH")
                                       "\\" lzd:*subdir*))))
  (setq out (lzd:addcand out (getvar "DWGPREFIX")))
  (setq out (lzd:addcand out (getvar "TEMPPREFIX")))
  (reverse out))

(defun lzd:join (dir name)
  (cond
    ((or (null dir) (= dir "")) name)
    ((= (substr dir (strlen dir) 1) "\\") (strcat dir name))
    (t (strcat dir "\\" name))))

;; A file name with nothing in it a file system will argue about.
(defun lzd:safe (s / out i c n)
  (setq out "" i 1 n (strlen s))
  (while (<= i n)
    (setq c (substr s i 1))
    (setq out (strcat out (if (wcmatch c "[A-Za-z0-9._-]") c "-"))
          i (1+ i)))
  (if (= out "") "LISP" out))

;; "POOL-v2.7-error-2026-09-11-143207.dxf" -- tool, version, what it is
;; and when, with the seconds on the end so two failures a minute apart
;; do not overwrite each other.
(defun lzd:filename-kind (tool ver kind)
  (strcat (lzd:safe (if tool (lzd:str tool) "LISP")) "-"
          (lzd:safe (if ver (lzd:str ver) "noversion")) "-" kind "-"
          (lzd:stamp) ".dxf"))

(defun lzd:filename (tool ver) (lzd:filename-kind tool ver "error"))

;; Try each candidate folder until one takes the file.  Returns the full
;; path written, or nil if every one of them refused -- which is the
;; only thing that puts the user on the click-into-the-drawing path.
(defun lzd:write (name prims / path got d)
  (foreach d (lzd:candidates)
    (if (null got)
      (progn
        (vl-mkdir d)    ; a profile that has never downloaded anything
        (setq path (vl-catch-all-apply 'lzd:dxfwrite
                                       (list (lzd:join d name) prims)))
        (if (and (not (vl-catch-all-error-p path)) path)
          (setq got path)))))
  got)

;;; -------------------- the report text ---------------------------------

(defun lzd:pair (k v)
  (strcat "  " (lzd:str k) (substr "              " 1
                                   (max 1 (- 14 (strlen (lzd:str k)))))
          (lzd:str v)))

;; Which build this is.  cal:*version* exists only when CALOFIN-LIB is
;; loaded, so an unbound read here is the standalone answer rather than
;; a missing one -- and knowing which of the two tiers failed is half of
;; reproducing it, since the whole point of shared/ is that the two are
;; meant to behave identically.
(defun lzd:build ()
  (if cal:*version*
    (strcat "LAZPASS / shared build (CALOFIN-LIB " cal:*version* ")")
    "standalone file from lisp/"))

(defun lzd:report-lines (tool ver msg nents / out)
  (setq out
    (list
      "CALOFIN ERROR REPORT"
      "===================="
      ""
      (lzd:pair "tool" (strcat (lzd:str tool) " "
                               (if ver (lzd:str ver) "(no version banner)")))
      (lzd:pair "build" (lzd:build))
      (lzd:pair "lazdiag" *lazdiag-version*)
      (lzd:pair "run started" (if lzd:*started* lzd:*started* "(not recorded)"))
      (lzd:pair "failed at" (cal:datestr))
      ""
      "THE ERROR"
      (lzd:pair "message" msg)
      (lzd:pair "last step" (if lzd:*step* lzd:*step*
                                "(none - it failed before the first prompt)"))
      (lzd:pair "ERRNO" (getvar "ERRNO"))
      (lzd:pair "CMDNAMES" (getvar "CMDNAMES"))
      (lzd:pair "LASTPROMPT" (getvar "LASTPROMPT"))
      ""
      "THE DRAWING"
      (lzd:pair "DWGNAME" (getvar "DWGNAME"))
      (lzd:pair "DWGPREFIX" (getvar "DWGPREFIX"))
      (lzd:pair "CLAYER" (getvar "CLAYER"))
      (lzd:pair "OSMODE" (getvar "OSMODE"))
      (lzd:pair "LUNITS" (getvar "LUNITS"))
      (lzd:pair "INSUNITS" (getvar "INSUNITS"))
      (lzd:pair "DIMSTYLE" (getvar "DIMSTYLE"))
      (lzd:pair "DIMSCALE" (getvar "DIMSCALE"))
      (lzd:pair "CMDECHO" (getvar "CMDECHO"))
      (lzd:pair "UNDOCTL" (getvar "UNDOCTL"))
      ""
      "GEOMETRY COPIED INTO THIS FILE"
      (lzd:pair "entities" (strcat (itoa nents)
                                   (if (>= nents lzd:*max-ents*)
                                     (strcat " (TRUNCATED at lzd:*max-ents* = "
                                             (itoa lzd:*max-ents*) ")")
                                     "")))
      (lzd:pair "picked points" (length lzd:*pts*))
      (lzd:pair "on layers" (strcat lzd:*errlayer* " = this report, "
                                    lzd:*picklayer* " = the clicks"))
      ""
      "WHAT THIS REPORT CANNOT TELL YOU"
      "  AutoLISP hands an error handler a message and nothing else: no"
      "  stack, no file, no line number.  'last step' above is the"
      "  nearest thing -- the last prompt the run reached -- and the"
      "  transcript below says how it got there.  Between them they name"
      "  the prompt it died at, which is the question a line number"
      "  would have answered."
      ""
      "THE RUN, PROMPT BY PROMPT"))
  (setq out (append out
                    (if lzd:*log*
                      (reverse lzd:*log*)
                      (list "  (nothing recorded - the tool does not call"
                            "   lzd:begin, or it failed before its first"
                            "   prompt)"))))
  (append out
          (list ""
                "Send this file to whoever maintains calofin.  It holds"
                "the failure and no more of your drawing than the failure"
                "needed; your own drawing was not changed.")))

;;; -------------------- building the whole report -----------------------

(defun lzd:textheight (ext / d)
  (setq d (if ext (distance (list (car ext) (cadr ext))
                            (list (caddr ext) (cadddr ext)))
              0.0))
  (if (> d 1.0) (/ d 140.0) 1.0))

;; The report as TEXT, placed to the LEFT of everything copied and
;; top-aligned with it.  Left rather than on top of it: a report written
;; over the geometry it is describing is one you have to move before you
;; can read either.
(defun lzd:textblock (lines ext h / x y w n out l)
  (setq n 0)
  (foreach l lines (if (> (strlen l) n) (setq n (strlen l))))
  (setq w (* n h 0.7))
  (if ext
    (setq x (- (car ext) w (* h 6.0)) y (cadddr ext))
    (setq x 0.0 y 0.0))
  (foreach l lines
    (setq out (cons (list "TEXT" lzd:*errlayer* (list x y 0.0) h l 0.0) out)
          y (- y (* h 1.7))))
  (reverse out))

;; Every point the user clicked, as a point and its prompt.  For the
;; tools that take measurements rather than select geometry, this IS the
;; geometry that caused the failure.
(defun lzd:pickpts ()
  (mapcar '(lambda (pr) (list "POINT" lzd:*picklayer* (cdr pr)))
          (reverse lzd:*pts*)))

(defun lzd:picklabels (h / out i pr)
  (setq i 0)
  (foreach pr (reverse lzd:*pts*)
    (setq i (1+ i)
          out (cons (list "TEXT" lzd:*picklayer* (cdr pr) h
                          (strcat (itoa i) ". " (car pr)) 0.0)
                    out)))
  (reverse out))

;; Geometry, clicks and report text as one list of primitives.  The
;; order is deliberate: the extent is measured off the drawing content
;; only, so the labels and the report are placed against the geometry
;; rather than against themselves.
;; One entity's primitives, or a label saying it could not be read.
;; Per entity and not per report: a single entity this cannot flatten
;; must cost its own shape and nothing else.  Before the catch was here
;; one unconvertible entity took the WHOLE report down -- the drafter
;; got "could not be written to a file" and no diagnosis at all, for a
;; drawing the tool had merely been asked to copy.
(defun lzd:flatten-safe (e / r)
  (setq r (vl-catch-all-apply 'lzd:flatten (list e)))
  (if (vl-catch-all-error-p r)
    (list (list "TEXT" lzd:*errlayer* '(0.0 0.0 0.0) 0.0
                (strcat "<entity not readable: "
                        (lzd:str (vl-catch-all-error-message r)) ">")
                0.0))
    r))

(defun lzd:build-prims (tool ver msg / geo pts ext h nents e)
  (setq geo nil nents 0)
  (foreach e (lzd:gather)
    (setq geo (append geo (lzd:flatten-safe e)) nents (1+ nents)))
  (setq pts (lzd:pickpts)
        ext (lzd:extent (append geo pts))
        h   (lzd:textheight ext))
  (append geo pts (lzd:picklabels h)
          (lzd:textblock (lzd:report-lines tool ver msg nents) ext h)))

;;; -------------------- what the user is told ---------------------------

(defun lzd:announce (tool ver path)
  (princ (strcat "\n[calofin] " (lzd:str tool)
                 (if ver (strcat " " (lzd:str ver)) "")
                 " has FAILED -- this is a bug, not"))
  (princ "\n[calofin] something you did wrong.  An error report has been")
  (princ "\n[calofin] written to")
  (princ (strcat "\n[calofin]     " path))
  (princ "\n[calofin] SEND THAT FILE IN FOR DIAGNOSIS.  It holds a copy of")
  (princ "\n[calofin] the geometry, every prompt and answer of the run, and")
  (princ "\n[calofin] what AutoCAD was doing when it stopped.  Your own")
  (princ "\n[calofin] drawing has not been touched.")
  (princ))

;; Every candidate folder refused the file, or the report itself blew
;; up.  The user still has to be told -- a failure that says nothing is
;; the thing this whole file exists to stop -- and LAZDIAG is where they
;; go next, because that runs from a clean command line where a prompt
;; is safe and this does not.
(defun lzd:nofile (tool ver msg why / d)
  (princ (strcat "\n[calofin] " (lzd:str tool)
                 (if ver (strcat " " (lzd:str ver)) "")
                 " has FAILED: " (lzd:str msg)))
  (princ "\n[calofin] The error report could NOT be written to a file.")
  ;; Either the report broke -- in which case the reason is the whole
  ;; story and the folder list is noise -- or every folder refused it,
  ;; in which case which ones were tried is the whole story.
  (if why
    (princ (strcat "\n[calofin]   " (lzd:str why)))
    (foreach d (lzd:candidates) (princ (strcat "\n[calofin]   tried " d))))
  (princ "\n[calofin] Type LAZDIAG to try again, or to place the report")
  (princ "\n[calofin] into this drawing instead as a last resort.")
  (if (null lzd:*last*) (setq lzd:*last* (list tool ver msg nil nil)))
  (princ))

;;; -------------------- the entry point from *error* --------------------
;;; Every tool's handler ends with a call to this.  Three things it must
;;; never do, because the caller is an *error* handler and has nowhere to
;;; put a failure of its own:
;;;   - throw.  The work happens under vl-catch-all-apply, and the catch
;;;     is what turns a broken reporter into a printed line rather than a
;;;     handler that dies halfway and leaves the undo group open.
;;;   - re-enter.  lzd:*inside* refuses a second report raised by the
;;;     first one, which would otherwise recurse until AutoCAD gave up.
;;;   - prompt.  Nothing here asks the user anything; that is LAZDIAG's
;;;     job, from a clean command line.

;; T when the stored context belongs to the tool now reporting.  A run
;; that finished cleanly leaves its transcript behind, and handing it to
;; the NEXT tool's failure would produce a report that is wrong and
;; looks right -- the one outcome worse than no report at all.
(defun lzd:mine-p (tool)
  (and lzd:*tool* tool
       (= (strcase (lzd:str tool)) (strcase lzd:*tool*))))

(defun lzd:disown ()
  (setq lzd:*tool* nil lzd:*ver* nil lzd:*log* nil lzd:*step* nil
        lzd:*watch* nil lzd:*pts* nil lzd:*mark* nil)
  nil)

(defun lzd:report-1 (tool ver msg / prims name path)
  (if (not (lzd:mine-p tool)) (lzd:disown))
  (setq prims (lzd:build-prims tool ver msg)
        name  (lzd:filename tool ver)
        path  (lzd:write name prims)
        lzd:*last* (list tool ver msg prims name)
        lzd:*lastfile* path)
  (if path (lzd:announce tool ver path) (lzd:nofile tool ver msg nil))
  (lzd:end tool)
  path)

(defun lzd:report (tool ver msg / r)
  (cond
    ;; Esc is not a bug.  A drafter who backs out of POOL twenty times a
    ;; day must not find twenty DXFs in Downloads.
    ((lzd:cancel-p msg) nil)
    (lzd:*inside*
     (princ "\n[calofin] The error reporter failed while reporting an")
     (princ "\n[calofin] error -- no file written.  The original error was:")
     (princ (strcat "\n[calofin]     " (lzd:str msg))))
    (t
     (setq lzd:*inside* T
           r (vl-catch-all-apply 'lzd:report-1 (list tool ver msg))
           lzd:*inside* nil)
     (if (vl-catch-all-error-p r)
       (lzd:nofile tool ver msg (vl-catch-all-error-message r)))))
  (princ))

;;; -------------------- LAZDIAG, the command ----------------------------

;; THE LAST RESORT.  Only reached by typing LAZDIAG after a report that
;; could not be written to any folder -- never automatically, and never
;; from inside an error handler.  This is the one path that asks the user
;; to click, and the one path that writes into the drawing they are
;; working in, which is why it is last and why it says so first.
(defun lzd:paste (lines / p h y n l)
  (princ "\n[calofin] LAST RESORT: no folder would take the file, so the")
  (princ "\n[calofin] report has to go into THIS drawing as text.  Pick a")
  (princ "\n[calofin] spot well clear of your work -- off to one side of")
  (princ "\n[calofin] everything, not on the sheet.")
  (setq p (getpoint "\nPlace the error report, far from the drawing: "))
  (if (null p)
    (progn (princ "\n[calofin] Nothing placed.") nil)
    (progn
      (cal:ensure-layer lzd:*errlayer* 1)
      (setq h (/ (getvar "VIEWSIZE") 90.0))
      (if (or (null h) (<= h 0.0)) (setq h 1.0))
      (setq y (cadr p) n 0)
      (foreach l lines
        (entmakex (list '(0 . "TEXT") (cons 8 lzd:*errlayer*)
                        (cons 10 (list (car p) y 0.0))
                        (cons 40 h) (cons 1 (lzd:str l))))
        (setq y (- y (* h 1.7)) n (1+ n)))
      (princ (strcat "\n[calofin] " (itoa n) " lines placed on layer "
                     lzd:*errlayer* "."))
      (princ "\n[calofin] Send this drawing in, or copy those lines out --")
      (princ "\n[calofin] and erase them when the bug is fixed.")
      T)))

;; The lines of the stored report, rebuilt if only the bare facts of it
;; survived (lzd:nofile stores those when the report itself threw).
(defun lzd:last-lines ( / r)
  (setq r lzd:*last*)
  (if (nth 3 r)
    (mapcar '(lambda (pr) (nth 4 pr))
            (vl-remove-if-not
              '(lambda (pr) (and (= (car pr) "TEXT")
                                 (= (cadr pr) lzd:*errlayer*)))
              (nth 3 r)))
    (lzd:report-lines (car r) (cadr r) (caddr r) 0)))

;; Write the last failure's report again -- to a folder that may have
;; become writable, or that the user has just pointed CalofinErrorDir at.
(defun lzd:again ( / r path)
  (setq r    lzd:*last*
        path (lzd:write (if (nth 4 r) (nth 4 r)
                            (lzd:filename (car r) (cadr r)))
                        (if (nth 3 r)
                          (nth 3 r)
                          (lzd:textblock (lzd:last-lines) nil 1.0))))
  (if path
    (progn (setq lzd:*lastfile* path)
           (lzd:announce (car r) (cadr r) path))
    (lzd:paste (lzd:last-lines))))

;; Nothing has failed.  Rather than say so and stop, write a report
;; anyway: it proves the whole path -- folder, permissions, DXF -- works
;; on THIS machine, which is the question somebody asks precisely when
;; they are about to need it and cannot afford to find out then.
(defun lzd:selftest ( / prims path d)
  (princ "\n[calofin] Nothing has failed in this session, so this is a")
  (princ "\n[calofin] self test: a report written exactly where a real")
  (princ "\n[calofin] one would go.")
  (lzd:disown)
  (lzd:say "--- LAZDIAG self test: no failure, nothing wrong")
  (setq prims (lzd:build-prims "LAZDIAG" *lazdiag-version*
                               "(self test - no failure has occurred)")
        path  (lzd:write (lzd:filename-kind "LAZDIAG" *lazdiag-version*
                                            "selftest")
                         prims))
  (if path
    (progn
      (princ (strcat "\n[calofin] Written: " path))
      (princ "\n[calofin] Error reports will reach you.  Delete that file.")
      (setq lzd:*lastfile* path))
    (progn
      (princ "\n[calofin] Could NOT write it.  None of these would take it:")
      (foreach d (lzd:candidates) (princ (strcat "\n[calofin]   " d)))
      (princ "\n[calofin] Set the AutoCAD environment string")
      (princ "\n[calofin] CalofinErrorDir to a folder you can write to:")
      (princ "\n[calofin]   (setenv \"CalofinErrorDir\" \"C:\\\\temp\")")))
  (lzd:disown)
  (princ))

(defun c:LAZDIAG ( / *error* oce)
  (defun *error* (m)
    (if oce (setvar "CMDECHO" oce))
    (if (and m (not (lzd:cancel-p m)))
      (princ (strcat "\nLAZDIAG error: " m)))
    (if lzd:report (lzd:report "LAZDIAG" *lazdiag-version* m))
    (princ))
  (if lzd:begin (lzd:begin "LAZDIAG" *lazdiag-version*))
  (setq oce (getvar "CMDECHO"))
  (setvar "CMDECHO" 0)
  (if lzd:*last* (lzd:again) (lzd:selftest))
  (setvar "CMDECHO" oce)
  (princ))

(defun c:LAZDIAGVER ()
  (princ (strcat "\nLAZDIAG " *lazdiag-version*))
  (princ))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nLAZDIAG " *lazdiag-version*
                 " loaded -- a failed calofin command now writes a DXF"
                 " error report to your Downloads folder; type LAZDIAG to"
                 " prove that works before you ever need it.")))
(princ)
