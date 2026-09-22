;;; ======================================================================
;;; TOOLNAME.lsp  --  one-line purpose of the tool
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  TOOLNAME     what it does
;;;            TOOLNAMEVER  print the loaded version
;;; ======================================================================
;;;
;;;  The prose block.  Say what problem this solves and what the drafter
;;;  used to do instead -- that is the house style, and it is what makes
;;;  the tree readable a year later.  Then the picks, in order, then
;;;  WHAT IT DOES NOT DO, which is as much a part of the contract as
;;;  what it does.
;;; ======================================================================

(setq *toolname-version* "v1.0")   ; announced on load; release_lisp.py
                                   ; reads this banner and stamps the
                                   ; dated twin in releases/ from it

(vl-load-com)

;;; -------------------- tunables ----------------------------------------
;;; Everything a shop might want changed, all in one block; nothing
;;; settable lives anywhere else in this file.  Each says what CHANGING
;;; it does -- not what it is.  setq any of them after loading and the
;;; next run reads the new value.

;; The layer the tool's output is drawn on.  Change it and the results
;; land somewhere else in the drawing's layer list.
(setq tool:*outlayer* "TOOL-OUTPUT")

;; The colour that layer is CREATED with, as an ACI number.  A layer
;; record outlives the command and colours everything ByLayer on it for
;; whoever opens the drawing next, so this is a number and never 'auto.
(setq tool:*outcolor* 3)

;; The colour of the on-screen CUE this tool draws and then takes away
;; again.  'auto resolves against the drafter's background at the point
;; of use; a NUMBER here is used exactly as given.
(setq tool:*cuecolor* 'auto)

;; The sysvars this command changes.  OSMODE leads: it is the setting
;; the drafter notices last and misses most.  Do NOT list one the tool
;; never moves -- that hands back the opening value over anything the
;; drafter ticked while it ran.
(setq tool:*sysvars* '("OSMODE" "CMDECHO" "CLAYER"))

;;; -------------------- state -------------------------------------------
;;; Not knobs: written as the tool runs.

(setq tool:*sysold* nil)

;;; -------------------- session ------------------------------------------

;; Snapshot the drafter's settings, once per run.  It refuses to
;; overwrite an existing snapshot: a second save mid-run would capture
;; the muted OSMODE and "restore" 0 for ever.
(defun tool:syssave (vars / v)
  (if (not tool:*sysold*)
    (setq tool:*sysold*
          (mapcar '(lambda (v) (cons v (getvar v))) vars))))

;; Put them back and DROP the snapshot.  The drop must not sit behind
;; anything that can throw, or every later run restores this run's
;; values over whatever the drafter has changed since.
(defun tool:sysrestore ( / v p)
  (foreach v tool:*sysvars*
    (setq p (assoc v tool:*sysold*))
    (if p (setvar v (cdr p))))
  (setq tool:*sysold* nil))

;;; -------------------- colour -------------------------------------------

;; Resolve a colour knob.  'auto picks one that reads against whatever
;; background the drafter is on; a number is used exactly as given.
;; Copy the library's cal:ink body here -- do not invent a table.
;; Resolve ONCE into a local before a loop: the measurement is a COM
;; round trip.
(defun tool:ink (knob role)
  (if (= (type knob) 'INT)
    knob
    (cond ((eq role 'fade) 8)
          ((eq role 'guide) 7)
          (t 7))))

;;; -------------------- layers -------------------------------------------

;; Create the output layer, or -- when it already exists -- make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
(defun tool:ensure-layer (name color / rec ed flags col fixed)
  (if (not (tblsearch "LAYER" name))
    (entmakex (list '(0 . "LAYER") '(100 . "AcDbSymbolTableRecord")
                    '(100 . "AcDbLayerTableRecord")
                    (cons 2 name) '(70 . 0) (cons 62 color)
                    '(6 . "Continuous")))
    (progn
      (setq rec   (tblobjname "LAYER" name)
            ed    (entget rec)
            flags (cdr (assoc 70 ed))
            col   (cdr (assoc 62 ed))
            fixed nil)
      (if (/= 0 (logand 5 flags))          ; frozen (1) or locked (4)
        (setq ed    (subst (cons 70 (- flags (logand 5 flags)))
                           (assoc 70 ed) ed)
              fixed T))
      (if (< col 0)                        ; layer switched off
        (setq ed    (subst (cons 62 (abs col)) (assoc 62 ed) ed)
              fixed T))
      (if fixed
        (progn
          (entmod ed)
          (princ (strcat "\nTOOLNAME: layer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible.")))))))

;;; -------------------- asking -------------------------------------------

;; Keyword question.  KWS is the canonical keyword string -- it is BOTH
;; the initget list and the bracket text, so the two can never drift.
;; HIDDEN holds extra accepted spellings that are never shown; spell
;; them ALL-CAPS so they must be typed in full and cannot steal a
;; canonical hotkey.  DFLT nil = an answer is required.  Returns the
;; keyword, or TOOL-BACK for Back/Undo.
(defun tool:askkw (msg kws hidden dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (strcat kws
                   (if hidden (strcat " " hidden) "")
                   (if back " Back Undo" "")))
  (setq v (getkword (strcat "\n" msg " ["
                            (vl-string-translate " " "/" kws)
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  ;; Every answer the drafter gives is in the transcript -- inside the
  ;; ask helpers too, not only at the call sites.  check_lazdiag --fix
  ;; writes this line; do not hand-write it.
  (if lzd:ask (lzd:ask msg v) v)
  (cond ((member v '("Back" "Undo")) 'TOOL-BACK)
        ((null v) (if dflt dflt (tool:askkw msg kws hidden dflt back)))
        (t v)))

;; Yes/No.  DFLT is "Yes" or "No" and is always shown; destructive
;; actions default "No".  Returns T, nil or TOOL-BACK.
(defun tool:askyn (msg dflt back / v)
  (setq v (tool:askkw msg "Yes No" nil dflt back))
  (if (eq v 'TOOL-BACK) v (= v "Yes")))

;;; -------------------- the command ---------------------------------------

(defun c:TOOLNAME ( / *error* undo-open ss pt keep cue)
  (defun *error* (msg)
    ;; The drafter's settings come back FIRST, so nothing below can skip
    ;; them.  A setvar of a value this run captured cannot throw; a bare
    ;; (command ...) can, and an error inside *error* aborts the handler
    ;; -- every line after the throwing one is skipped.
    (tool:sysrestore)
    ;; command-s, never plain command: a 2015+ engine rejects (command)
    ;; inside *error* unless the error mode was pushed beforehand.
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nTOOLNAME error: " msg)))
    ;; AFTER the restore, BEFORE the trailing (princ) -- which is the
    ;; handler's return value.
    (if lzd:report (lzd:report "TOOLNAME" *toolname-version* msg))
    (princ))

  (if lzd:begin (lzd:begin "TOOLNAME" *toolname-version*))
  (tool:syssave tool:*sysvars*)
  (setvar "CMDECHO" 0)
  ;; Mute running osnap so the computed points this tool feeds to
  ;; (command ...) land where it worked them out, instead of being
  ;; pulled onto nearby geometry.  This is a BORROW: OSMODE is in the
  ;; table above only because of this line, and it is put back on the
  ;; clean exit AND from the handler.  If your tool never does this,
  ;; take OSMODE out of tool:*sysvars* -- check_osnap.py fails a table
  ;; that lists a sysvar the tool does not move.
  (setvar "OSMODE" 0)
  ;; Opened only when undo is recording: _Begin in a drawing whose
  ;; UNDOCTL has bit 1 clear errors out of the command.
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undo-open T)))

  (tool:ensure-layer tool:*outlayer* tool:*outcolor*)
  ;; Move the current layer so the output lands where it belongs.  This
  ;; is the other BORROW: CLAYER is what every line the drafter draws
  ;; AFTER this command is born with, so it is in the table above and
  ;; comes back on both paths.  Same rule as OSMODE -- if your tool
  ;; never moves it, take "CLAYER" out of tool:*sysvars*.
  (setvar "CLAYER" tool:*outlayer*)

  ;; A selection: the lzd:watch line records the geometry the run was
  ;; HANDED, not just what it drew.  The else branch is load-bearing --
  ;; it makes the whole form evaluate to SS whether LAZDIAG is loaded
  ;; or not.
  (princ "\nSelect the work: ")
  (setq ss (ssget))
  (if lzd:watch (lzd:watch ss) ss)

  ;; An input that is a body statement takes the lzd:ask line after it.
  (setq pt (getpoint "\nInsertion base point <0,0>: "))
  (if lzd:ask (lzd:ask "Insertion base point" pt) pt)

  (setq keep (tool:askyn "Keep the guides?" "No" T))
  (if lzd:ask (lzd:ask "Keep the guides?" keep) keep)

  ;; A CUE -- drawn and then taken away again -- so its colour resolves
  ;; through ink.  Resolved ONCE into a local: behind 'auto is a COM
  ;; round trip, and this would otherwise be measured on every pass.
  ;; Anything STILL in the drawing when the command returns takes a
  ;; plain ACI number instead (tool:*outcolor* above).
  (setq cue (tool:ink tool:*cuecolor* 'guide))
  (if pt
    (grdraw (list (- (car pt) 1.0) (cadr pt))
            (list (+ (car pt) 1.0) (cadr pt)) cue))

  ;; ... the tool ...

  ;; Closed only if one was opened -- the same question the handler
  ;; asks.  An _End on no group is an error of its own, and it lands
  ;; HERE, after everything has been drawn, with the restore below it
  ;; never reached.
  (if undo-open
    (progn
      (command "_.UNDO" "_End")
      (setq undo-open nil)))
  (tool:sysrestore)
  (if lzd:end (lzd:end "TOOLNAME"))
  (princ))

(defun c:TOOLNAMEVER ()
  (princ (strcat "\nTOOLNAME " *toolname-version*))
  (princ))

;;; -------------------- load banner ---------------------------------------
;;; Quiet inside the build: LAZPASS.lsp and CALOFIN-LOADER.lsp set
;;; *calofin-quiet* while they load their members.  The flag is
;;; deliberately NOT a cal: symbol -- a lisp/ file may not touch one.

(if (not *calofin-quiet*)
  (princ (strcat "\nTOOLNAME " *toolname-version*
                 " loaded.  Type TOOLNAME to run.")))
(princ)
