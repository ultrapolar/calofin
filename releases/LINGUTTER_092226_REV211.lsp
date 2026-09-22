;;; ======================================================================
;;; LINGUTTER.lsp  --  gut a highlighted area back to its perimeter, the
;;;                    dimensions worth keeping, and PADDLE's pads
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; Commands:  LINGUTTER       gut the highlighted area, then run PADDLE
;;;            LINGUTTERSCAN   report what it would keep and erase, and stop
;;;            LINGUTTERVER    print the loaded version
;;;
;;;  A finished as-built sheet carries far more than the next station
;;;  needs: the hopper and its slope lines, steps, survey points and
;;;  their labels, the notes.  LINGUTTER cuts one pool back to three
;;;  things and then pads what is left.
;;;
;;;  IT WORKS ONLY INSIDE THE HIGHLIGHT.  Window the pool -- before
;;;  typing the command or at its prompt -- and everything below happens
;;;  to that selection and nothing else.  What you did not highlight is
;;;  not traced from, not counted, and not erased, so a second pool, the
;;;  title block and the rest of the sheet are all safe from it.
;;;
;;;    1. TRACE.  It does not look for a closed loop and hope one of
;;;       them is the pool.  It walks the OUTER FACE of the highlighted
;;;       geometry and draws its own perimeter over it -- the outline
;;;       you would get walking round the outside with your hand on the
;;;       wall.  Ends closer than a snap tolerance count as one point,
;;;       so a drafting gap heals; the walk always takes the hardest
;;;       available right turn, which is what keeps it outside -- the
;;;       hopper, the steps and a bottom break are never stepped onto,
;;;       because reaching them needs a left turn.  Three tolerances are
;;;       tried in turn (lg:*snaps*), tightest first, and the result is
;;;       measured against what was highlighted before it is believed.
;;;       What comes out is redrawn as ONE closed LWPOLYLINE on the
;;;       "POOL" layer, ByLayer, arcs carried as bulges -- a single
;;;       object however it was drawn going in: one polyline, or fifty
;;;       loose lines and arcs.
;;;
;;;       Four things the walk reads that are not lines on the outline,
;;;       and every one of them is a step or a bench a pool really has:
;;;         * a T.  A drafter does not break the wall where a tanning
;;;           ledge meets it, so the wall is one line the full height
;;;           of the pool and the ledge runs up to the MIDDLE of it.
;;;           Every segment is split where another one's END lands on
;;;           it before the graph is built (lg:split-tees).  Only ends:
;;;           two lines that merely cross mid-span still are not a
;;;           junction;
;;;         * a BLOCK reference.  A fiberglass step is an FG_STEP
;;;           reference bolted to a wall and its three sides ARE the
;;;           perimeter there, so a reference contributes its
;;;           definition's geometry carried onto the insertion point
;;;           (lg:ins-segs).  lg:*skipblocks* keeps pads and drains out;
;;;         * WHICH FACE.  Every face of every piece is walked and the
;;;           one enclosing the most area wins (lg:all-faces), because
;;;           which face a walk traces is decided by the dart it starts
;;;           on and that used to be guessed.  Guessed wrong -- and an
;;;           arc leaving a component's lowest node and dipping below
;;;           it is enough to get it wrong -- the walk hugs the INSIDE,
;;;           which is how a bench and a step drawn as arcs OVER the
;;;           pool's own chords came back as the chords;
;;;         * and a RUN.  Splitting at a T puts a node in the middle of
;;;           a wall, so a run of edges that is one straight line or
;;;           one arc about one centre is welded back into one edge
;;;           (lg:weld).  The drafter gets the outline they drew, not a
;;;           vertex for every tread that touched it.
;;;
;;;       When no exterior can be walked at any tolerance it still draws
;;;       a perimeter: the convex hull of everything highlighted.  That
;;;       is reported as the wrap it is, because a hull has no concave
;;;       features and PADDLE will find nothing to pad.
;;;
;;;;    2. KEEP.  Three rules, and nothing else highlighted survives them:
;;;         * a RADIUS or DIAMETER dimension of the perimeter is kept
;;;           regardless of its style.  Group 10 of a radius dim is the
;;;           arc's CENTRE and group 15 is the point on the curve, so
;;;           three shapes count as "of the perimeter": the point on
;;;           the curve is on the loop, or the dim NAMES an arc of the
;;;           loop (same centre, same radius -- a leader dragged round
;;;           to read well puts its arrow past the end of the drawn
;;;           arc), or its centre sits on a VERTEX of the loop ("R3
;;;           typ." on a corner drawn sharp).  Without this rule the
;;;           call-out for the very corner PADDLE is about to pad is
;;;           the thing erased -- and it was, on every pool with a
;;;           radius drawn on it, because a 24" corner's centre sits
;;;           24" inside the loop;
;;;         * LINGUTTER asks once, "Keep CROSS DIMENSIONS?".  Answered
;;;           Yes, a dimension in a lg:*anystyles* style ("CROSS DIM*",
;;;           which catches "CROSS DIM", "CROSS DIMENSIONS" and "CROSS
;;;           DIMENSIONS 0.5") is kept when it reads as a genuine cross
;;;           measurement of THIS pool: both attachment points belong
;;;           to the perimeter at all (inside it, or on it), AND either
;;;           the two points span at least lg:*crossspan* of the
;;;           perimeter's own width or height -- "goes full X" or "goes
;;;           full Y" -- or they sit at two of its VERTICES, corner to
;;;           corner along one whole edge however short.  A dim from
;;;           one corner to some other point along that SAME edge --
;;;           the start of a line to a point in the middle of it -- is
;;;           never kept, regardless of span: it is reading a fraction
;;;           of one side, not the pool.  Answered No, none of these
;;;           dimensions gets any exemption and each is judged like any
;;;           other style below;
;;;         * a dimension in a lg:*perimstyles* style is kept only when
;;;           it is a dimension OF the perimeter: every one of its
;;;           attachment points within lg:*ontol* of the loop, AND the
;;;           two of them not a partial read along one single edge.
;;;           The same style measuring a hopper or a step goes with the
;;;           rest -- including a step built against a pool wall, whose
;;;           treads are dimensioned along that wall and so have both
;;;           ends exactly on the perimeter.  The styles are wildcards
;;;           and cover the whole STANDARD family: "STANDARD INCHES" is
;;;           what AUTODIM puts a 1" corner chamfer in, and "STANDARD-1"
;;;           is what AutoCAD renames STANDARD to on a paste.
;;;       Everything else highlighted is erased: text, blocks, points,
;;;       hatches, the geometry the perimeter was traced from, and
;;;       dimensions in any other style.  Name a layer in
;;;       lg:*keeplayers* to spare it even inside the highlight.
;;;
;;;    3. PADDLE.  The new perimeter is handed over as a pickfirst
;;;       selection and PADDLE pads its concave features.  Handed, not
;;;       hunted: PADDLE's own auto-detect reads the WHOLE drawing for
;;;       its largest closed loop, which after a scoped gut may well be
;;;       a title block border rather than the pool.
;;;
;;;  LINGUTTER erases a great deal of what you highlight, and does so
;;;  straight through -- no confirmation asked, just the report of
;;;  exactly what it found before it erases it.  LINGUTTERSCAN prints
;;;  the same report and stops without touching the drawing; run it
;;;  first on a sheet you care about.  The whole run is one undo
;;;  group: a single U puts the drawing back.
;;;  (In a drawing with undo control off there is no group to open, so
;;;  the gut still happens but a U will not take it back in one step.)
;;;
;;;  Usage
;;;    Command: LINGUTTER       highlight the area before typing it and
;;;                             that selection is used as-is; otherwise
;;;                             it asks for one.  There is no "the whole
;;;                             drawing" answer -- it erases what it
;;;                             sweeps, so it sweeps only what you showed
;;;                             it.  Then it asks "Keep CROSS DIMENSIONS?"
;;;                             <Yes> before reporting what it found
;;;    Command: LINGUTTERSCAN   the same two prompts and the same report
;;;                             -- nothing else changes in the drawing
;;;    Command: LINGUTTERVER    prints the version
;;;
;;;  Tunables (setq them after loading if a drawing needs different
;;;  names, e.g. in a startup file):
;;;    lg:*poollayer*    layer the perimeter is drawn on    ("POOL")
;;;    lg:*poolcolor*    its colour when the layer has to be created
;;;    lg:*anystyles*    dim styles kept when "Keep CROSS DIMENSIONS?"
;;;                      is answered Yes and the dim is a genuine cross
;;;                      measurement of this pool (see lg:cross-ok-p
;;;                      and lg:*crossspan*), as wildcard patterns
;;;                      matched against the style name
;;;    lg:*perimstyles*  dim styles kept only on the perimeter, and
;;;                      only when the dim reads the WHOLE of a side
;;;                      rather than a part of one
;;;    lg:*keeplayers*   layers left alone entirely (nil = none)
;;;    lg:*skiplayers*   layers the perimeter is never traced from,
;;;                      inside a block reference as well as out
;;;    lg:*skipblocks*   BLOCK NAMES the perimeter is never traced from
;;;                      -- pads and drains, which sit on the pool
;;;                      rather than bounding it
;;;    lg:*ontol*        how far a dimension's attachment point may sit
;;;                      off the perimeter and still count as on it
;;;    lg:*snaps*        the snap ladder: how far apart two ends may be
;;;                      and still count as one point, tried tightest
;;;                      first -- sorted for you, so the order it is
;;;                      typed in cannot change what the report claims
;;;    lg:*cover*        how much of the highlight's extent a traced
;;;                      exterior must span before it is believed
;;;    lg:*crossspan*    how much of the perimeter's own bounding box a
;;;                      kept lg:*anystyles* dim must span, in X or Y,
;;;                      to count as a full cross measurement rather
;;;                      than a small local one
;;;    lg:*runpaddle*    T to run PADDLE at the end, nil to stop after
;;;                      the gut
;;;
;;;  Notes
;;;    * A crossing window takes in whatever it touches, so a dimension
;;;      half inside the highlight is in the sweep and one wholly
;;;      outside it is not -- the highlight is the whole of the rule.
;;;    * Snapping MOVES a corner, by up to the tolerance that healed it.
;;;      A rung is only climbed when the one below could not produce an
;;;      exterior covering the highlight, and the report always names the
;;;      rung that worked.
;;;    * Highlighting two pools at once traces the bigger one and warns
;;;      that it covers only part of what you showed it.  That warning is
;;;      never a veto -- the alternative to a partial answer is a convex
;;;      hull, which is worse.
;;;    * lg:*perimstyles* covers the STANDARD FAMILY by wildcard, so a
;;;      perimeter side or a 1" corner chamfer that AUTODIM put in
;;;      "STANDARD INCHES" is kept, and so is the "STANDARD-1" AutoCAD
;;;      renames STANDARD to when a paste brings in a second definition.
;;;      What stops that widening from keeping a step's tread dimensions
;;;      is the partial-read half of the rule, not the style list: a
;;;      step against a wall has both ends of every tread dim ON the
;;;      perimeter.  Narrow the list to the two exact names to go back
;;;      to the old behaviour; either way the report counts every
;;;      dropped dimension and says which of the two it failed.
;;;    * A block reference is TRACED FROM but still swept: the new
;;;      perimeter replaces a step's own lines the way it replaces the
;;;      pool's.  lg:*skipblocks* is what keeps PADDLE's pads out -- a
;;;      pad sits centred ON a corner, half of it outside the loop, so
;;;      a pool gutted twice would trace round its own pads.
;;;    * "Keep CROSS DIMENSIONS?" answered No drops every lg:*anystyles*
;;;      dimension like any other style not in lg:*perimstyles* -- counted
;;;      in the report, not silently.
;;;    * A lg:*anystyles* dim is judged by SHAPE as well as location: a
;;;      small one entirely inside the pool, touching nothing, is kept
;;;      no more than a stray one outside it is -- lg:*crossspan* and
;;;      lg:vertex-to-vertex-p are what a genuine cross measurement has
;;;      to satisfy, and "start of one edge to a random point along
;;;      that SAME edge" satisfies neither one, on purpose.
;;;    * The perimeter is always redrawn, even when it was already one
;;;      closed polyline on POOL, so the result is the same object
;;;      whatever went in.  An associative dimension attached to the old
;;;      geometry loses its association (the measurement and the
;;;      definition points do not move -- the new polyline is drawn
;;;      through the same points).
;;;    * VIEWPORT entities are never erased, however they were caught.
;;;    * A locked layer is unlocked for the erase and locked again
;;;      afterwards.
;;;    * PADDLE lives in its own file.  When this session has not
;;;      loaded it the gut still happens and LINGUTTER says so instead
;;;      of failing.
;;;    * CLAYER, CMDECHO and OSMODE in force before the command are
;;;      restored afterwards, on a clean finish, an error, or Esc.
;;; ======================================================================

(setq *lingutter-version* "v2.11")  ; announced on load; release_lisp.py
                                   ; reads this banner and stamps the
                                   ; dated twin in releases/ from it

;;; -------------------- the knobs ---------------------------------------
;;; Everything a drawing might want changed, all in one block; nothing
;;; settable lives anywhere else in this file.  setq any of them after
;;; loading -- in a startup file, say.  Each is read fresh when a
;;; command runs, so a value changed between two runs takes effect on
;;; the second without reloading the file.  WHAT each does is here;
;;; WHY, and what it costs to move it, is in the Notes at the head of
;;; this file and in lisp/lingutter/README.md.
;;;
;;; The two STYLE lists are wildcard patterns matched against the
;;; dimension's style name -- "CROSS DIM*" is what catches both a
;;; drawing spelled "CROSS DIM" and this repo's "CROSS DIMENSIONS".
;;; The two LAYER lists are whole names, no wildcards.  Both kinds are
;;; matched with case folded, because wcmatch and member do not.

(setq lg:*poollayer*   "POOL")     ; layer the traced perimeter is drawn
                                   ; on; made if missing, and thawed /
                                   ; switched on / unlocked if it exists
                                   ; but cannot be drawn on
(setq lg:*poolcolor*   4)          ; its colour when the layer has to be
                                   ; created -- ACI 4 = cyan, POOL's own.
                                   ; Ignored when the layer already exists
(setq lg:*anystyles*   '("CROSS DIM*"))
                                   ; dim styles kept WHEREVER they sit: a
                                   ; cross dim spans the pool, so most of
                                   ; it is nowhere near the edge
(setq lg:*perimstyles* '("STANDARD*" "SIDE STANDARD*" "ALT STANDARD*"))
                                   ; dim styles kept only ON the
                                   ; perimeter -- every attachment point
                                   ; within lg:*ontol* of the loop.  The
                                   ; same style on a hopper or step goes.
                                   ; Wildcards, and they cover the whole
                                   ; STANDARD FAMILY on purpose:
                                   ; "STANDARD INCHES" is what AUTODIM
                                   ; puts a perimeter side or a 1" corner
                                   ; chamfer in, "SIDE STANDARD 0.5" and
                                   ; "STANDARD(2X)" are the same style at
                                   ; another scale, and "STANDARD-1" is
                                   ; what AutoCAD renames STANDARD to
                                   ; when a paste brings in a second
                                   ; definition.  A chamfer call-out on
                                   ; the very corner PADDLE is about to
                                   ; pad is not the thing to erase
(setq lg:*keeplayers*  nil)        ; layers left alone entirely, even
                                   ; inside the highlight; nil = none,
                                   ; e.g. '("TITLEBLOCK") to spare one
(setq lg:*skiplayers*  '("DEFPOINTS" "DIMENSION"))
                                   ; layers the perimeter is never traced
                                   ; FROM -- inside a block reference as
                                   ; well as out.  They are still swept:
                                   ; this keeps dimension geometry out of
                                   ; the walk, it does not spare it
(setq lg:*skipblocks*  '("PAD*" "DRAIN*"))
                                   ; BLOCK NAMES never traced from, as
                                   ; wildcard patterns.  A block on the
                                   ; pool is part of the pool -- a
                                   ; fiberglass step bolted to a wall is
                                   ; drawn as an FG_STEP reference and
                                   ; its outline IS the perimeter there
                                   ; -- but two families never are, and
                                   ; both are ours: PADDLE's own pads sit
                                   ; centred ON a corner, half of each
                                   ; one outside the loop, so a pool
                                   ; gutted twice would trace round its
                                   ; own pads the second time; a drain
                                   ; block sits in the floor.  They are
                                   ; still swept like anything else
(setq lg:*ontol*       1.0)        ; how far a dimension's attachment
                                   ; point may sit off the perimeter and
                                   ; still count as on it.  Drawing
                                   ; units, so inches on these sheets
(setq lg:*snaps*  '(0.05 6.0 24.0)) ; the snap ladder: how far apart two
                                   ; ends may be and still be treated as
                                   ; one node.  Tried TIGHTEST FIRST, a
                                   ; rung at a time, and only climbed
                                   ; when the rung below could not
                                   ; produce an exterior covering
                                   ; lg:*cover* of the highlight.
                                   ; Order and junk are not yours to get
                                   ; right -- lg:ladder sorts the list
                                   ; and drops anything that is not a
                                   ; tolerance above zero.  Snapping
                                   ; MOVES a corner by up to the rung
                                   ; that healed it, which is why the
                                   ; report always names that rung
(setq lg:*cover*       0.8)        ; how much of the highlight's extent a
                                   ; traced exterior has to span, both
                                   ; ways, to be believed as the
                                   ; perimeter: a fraction, 0.8 = 80%.
                                   ; Falling short is a warning, never a
                                   ; veto -- see the Notes
(setq lg:*crossspan*   0.8)        ; how much of the PERIMETER's own
                                   ; bounding box a kept lg:*anystyles*
                                   ; dim has to span, in X or in Y, to
                                   ; count as a full cross measurement
                                   ; rather than a small local one; a
                                   ; fraction, 0.8 = 80%.  A dim short
                                   ; of this is still kept when it runs
                                   ; corner to corner along one whole
                                   ; edge instead -- see lg:cross-ok-p
(setq lg:*runpaddle*   t)          ; T to hand the new perimeter to
                                   ; PADDLE and pad it; nil to stop after
                                   ; the gut and leave it unpadded

;; The layers a run leaves alone: the setting when it is a list of
;; NAMES, and nil - none - when it holds anything else.  A knob is
;; whatever somebody left in it, and this one is reachable: it SHIPS
;; nil, and LAZTUNE reads a nil-shipped knob as "off, or a value", so
;; it takes any ATOM - which is both the only thing it will accept
;; here and the one shape this setting cannot be.  Read rather than
;; trusted, then: the names go to strcase and strcat, and a T reaching
;; either is "bad argument type" thrown in the middle of the sweep.
(defun lg:keeplayers ( / bad s)
  (if (= (type lg:*keeplayers*) 'LIST)
    (progn
      (foreach s lg:*keeplayers* (if (/= (type s) 'STR) (setq bad T)))
      (if (not bad) lg:*keeplayers*))))

;;; -------------------- ask layer ---------------------------------------
;;; STANDARDS.md section 4, copied from the library so this file loads
;;; alone.  kws is the canonical keyword string -- it is BOTH the initget
;;; list and the bracket text, so the two can never drift.

(defun lg:askkw (msg kws hidden dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (strcat kws
                   (if hidden (strcat " " hidden) "")
                   (if back " Back Undo" "")))
  (setq v (getkword (strcat "\n" msg " ["
                            (vl-string-translate " " "/" kws)
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (if lzd:ask (lzd:ask msg v) v)
  (cond ((member v '("Back" "Undo")) 'LG-BACK)
        ((null v) (if dflt dflt (lg:askkw msg kws hidden dflt back)))
        (t v)))

;; Yes/No.  dflt is always shown; destructive actions default "No".
(defun lg:askyn (msg dflt back / v)
  (setq v (lg:askkw msg "Yes No" nil dflt back))
  (if (eq v 'LG-BACK) v (= v "Yes")))

;;; -------------------- drawing state -----------------------------------
;;; The sysvars this tool moves, saved in restore order -- OSMODE first,
;;; because object snaps are the setting the user misses most if a run is
;;; ever cut short partway.

(setq lg:*sysold*      nil)        ; sysvar snapshot, live only mid-run.
                                   ; Working state, NOT a knob -- it is
                                   ; down here so the block above is
                                   ; only ever things meant to be set

(defun lg:syssave (vars / v)
  (if (not lg:*sysold*)
    (foreach v vars
      (if (/= nil (getvar v))
        (setq lg:*sysold*
              (append lg:*sysold* (list (cons v (getvar v)))))))))

(defun lg:sysrestore ( / p)
  (foreach p lg:*sysold* (setvar (car p) (cdr p)))
  (setq lg:*sysold* nil))

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
;; Returns the layer NAME in every case.
(defun lg:ensure-layer (name color / rec ed flags col fixed)
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
          (princ (strcat "\nLINGUTTER: layer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible."))))))
  name)

;; Unlock every named layer that is locked, and hand back the list of
;; those that were -- entdel refuses an entity on a locked layer, so a
;; run that skipped this would quietly leave half the drawing behind.
(defun lg:unlock (names / out n rec ed f)
  (foreach n names
    (if (setq rec (tblobjname "LAYER" n))
      (progn
        (setq ed (entget rec)
              f  (cdr (assoc 70 ed)))
        (if (/= 0 (logand 4 f))
          (progn
            (entmod (subst (cons 70 (- f 4)) (assoc 70 ed) ed))
            (setq out (cons n out)))))))
  out)

(defun lg:relock (names / n rec ed f)
  (foreach n names
    (if (setq rec (tblobjname "LAYER" n))
      (progn
        (setq ed (entget rec)
              f  (cdr (assoc 70 ed)))
        (if (= 0 (logand 4 f))
          (entmod (subst (cons 70 (+ f 4)) (assoc 70 ed) ed)))))))

;;; -------------------- 2-D vector helpers ------------------------------
;;; Copied from the library, this file's prefix.  Strictly 2-element
;;; results; inputs may be 2- or 3-element (the Z is dropped).

(defun lg:2d (p) (list (car p) (cadr p)))
(defun lg:v- (a b) (mapcar '- (lg:2d a) (lg:2d b)))
(defun lg:v+ (a b) (mapcar '+ (lg:2d a) (lg:2d b)))
(defun lg:v* (v s) (list (* (car v) s) (* (cadr v) s)))
(defun lg:dot (a b) (+ (* (car a) (car b)) (* (cadr a) (cadr b))))

;; normalize an angle into [0, 2pi)
(defun lg:angnorm (a)
  (while (< a 0.0) (setq a (+ a pi pi)))
  (while (>= a (+ pi pi)) (setq a (- a pi pi)))
  a)

(defun lg:dir (a) (list (cos a) (sin a)))    ; unit vector at angle a

;;; -------------------- entities -> segments ----------------------------
;;; A segment is (p1 p2 bulge) with 2-D points, and a loop is a list of
;;; (x y bulge) vertices whose bulge belongs to the segment LEAVING it --
;;; PADDLE's shapes exactly, so a loop traced here can be handed to it.
;;; The readers below are ports of paddle--arcdata, --area, --lwverts,
;;; --plverts, --vts->segs and --ent-segs (lisp/paddle/PADDLE.lsp).
;;; LINGUTTER is a standalone file and cannot call into PADDLE's, so
;;; tests/test_lingutter.py runs the two side by side on the same
;;; geometry and fails when they part company.
;;;
;;; PADDLE's --chain is NOT among them, and deliberately: chaining
;;; segments end to end finds a loop, which is the guess this tool
;;; exists to stop making.  What reads these segments here is the
;;; outer-face walk below.

;; Segment data for vertex A -> B with bulge b (b /= 0):
;; returns (theta radius center start-tangent end-tangent)
;; theta = signed included angle (CCW positive), tangents are angles.
(defun lg:arcdata (a b blg / theta chord r phi ts cen)
  (setq theta (* 4.0 (atan blg))
        chord (distance a b)
        r     (/ chord (* 2.0 (sin (/ (abs theta) 2.0))))
        phi   (angle a b)
        ts    (- phi (/ theta 2.0))
        cen   (lg:v+ a (lg:v* (lg:dir (+ ts (if (> blg 0.0)
                                              (/ pi 2.0)
                                              (/ pi -2.0))))
                              r)))
  (list theta r cen ts (+ phi (/ theta 2.0))))

;; Signed area of a closed vertex list (shoelace + circular segments).
(defun lg:area (vts / n i a b blg area theta r seg)
  (setq n (length vts) i 0 area 0.0)
  (repeat n
    (setq a   (nth i vts)
          b   (nth (rem (1+ i) n) vts)
          blg (caddr a))
    (setq area (+ area (* 0.5 (- (* (car a) (cadr b)) (* (car b) (cadr a))))))
    (if (/= blg 0.0)
      (progn
        (setq seg   (lg:arcdata a b blg)
              theta (abs (car seg))
              r     (cadr seg))
        (setq area (+ area (* (if (> blg 0.0) 1.0 -1.0)
                              0.5 r r (- theta (sin theta)))))))
    (setq i (1+ i)))
  area)

;; Length once round a closed vertex list, arcs measured along the arc.
(defun lg:perim-len (vts / n i a b blg total seg)
  (setq n (length vts) i 0 total 0.0)
  (repeat n
    (setq a   (nth i vts)
          b   (nth (rem (1+ i) n) vts)
          blg (caddr a))
    (setq total
          (+ total
             (if (/= blg 0.0)
               (progn (setq seg (lg:arcdata a b blg))
                      (* (abs (car seg)) (cadr seg)))
               (distance (lg:2d a) (lg:2d b)))))
    (setq i (1+ i)))
  total)

;; LWPOLYLINE -> (closed-flag . vts)
(defun lg:lwverts (ent / ed out grp)
  (setq ed (entget ent))
  (foreach grp ed
    (cond
      ((= (car grp) 10)
       (setq out (cons (list (cadr grp) (caddr grp) 0.0) out)))
      ((= (car grp) 42)
       (if out (setq out (cons (list (caar out) (cadr (car out)) (cdr grp))
                               (cdr out)))))))
  (cons (= 1 (logand 1 (cdr (assoc 70 ed)))) (reverse out)))

;; heavy 2D POLYLINE -> (closed-flag . vts), nil for 3D/mesh plines
(defun lg:plverts (ent / ed flags e ved out p)
  (setq ed (entget ent) flags (cdr (assoc 70 ed)))
  (if (zerop (logand 112 flags))     ; skip 3D polylines / meshes / faces
    (progn
      (setq e (entnext ent))
      (while (and e (= "VERTEX" (cdr (assoc 0 (setq ved (entget e))))))
        (if (zerop (logand 16 (cond ((cdr (assoc 70 ved))) (0))))
          (progn
            (setq p (cdr (assoc 10 ved)))
            (setq out (cons (list (car p) (cadr p)
                                  (cond ((cdr (assoc 42 ved))) (0.0)))
                            out))))
        (setq e (entnext e)))
      (cons (= 1 (logand 1 flags)) (reverse out)))))

;; vertex list -> segments (wrapping when closed)
(defun lg:vts->segs (closed vts / n i segs a b)
  (setq n (length vts) i 0)
  (repeat (if closed n (max 0 (1- n)))
    (setq a (nth i vts)
          b (nth (rem (1+ i) n) vts))
    (setq segs (cons (list (lg:2d a) (lg:2d b) (caddr a)) segs))
    (setq i (1+ i)))
  (reverse segs))

;; any supported entity -> list of segments
(defun lg:ent-segs (ent / ed typ cen r sa ea sweep cv)
  (setq ed (entget ent) typ (cdr (assoc 0 ed)))
  (cond
    ((= typ "LINE")
     (list (list (lg:2d (cdr (assoc 10 ed)))
                 (lg:2d (cdr (assoc 11 ed))) 0.0)))
    ((= typ "ARC")
     (setq cen   (lg:2d (cdr (assoc 10 ed)))
           r     (cdr (assoc 40 ed))
           sa    (cdr (assoc 50 ed))
           ea    (cdr (assoc 51 ed))
           sweep (- ea sa))
     (if (<= sweep 0.0) (setq sweep (+ sweep pi pi)))
     (list (list (lg:v+ cen (lg:v* (lg:dir sa) r))
                 (lg:v+ cen (lg:v* (lg:dir ea) r))
                 (/ (sin (/ sweep 4.0)) (cos (/ sweep 4.0))))))
    ((= typ "LWPOLYLINE")
     (setq cv (lg:lwverts ent))
     (lg:vts->segs (car cv) (cdr cv)))
    ((= typ "POLYLINE")
     (setq cv (lg:plverts ent))
     (if cv (lg:vts->segs (car cv) (cdr cv))))))

;;; -------------------- geometry inside a block -------------------------
;;; A fiberglass step is not drawn line by line on the pool: it is an
;;; FG_STEP reference bolted to the wall, and its three sides ARE the
;;; perimeter where it sits.  Read straight past it and the step is not
;;; in the trace, not in the report, and not padded -- which is what used
;;; to happen, because the walk only ever saw LINEs, ARCs and polylines.
;;;
;;; So a block reference contributes its definition's own geometry,
;;; carried onto the insertion point: p' = ins + R(rot) . S . (p - base).
;;; lg:*skipblocks* is what keeps a pad out (see the knob), and
;;; lg:*skiplayers* applies inside the definition exactly as it does
;;; outside it.  Nesting recurses, capped, and a definition that contains
;;; itself therefore stops rather than running the stack out.
;;;
;;; The reference itself is still swept: the traced perimeter replaces
;;; the step's own lines the same way it replaces the pool's.

(setq lg:*blkdepth* 4)             ; how deep nested block references are
                                   ; followed.  Not a knob -- it is the
                                   ; recursion guard, and four is deeper
                                   ; than any pool drawing nests

;; (ins cos sin sx sy) for INSERT data ED with block base point BASE:
;; everything lg:xform-pt needs, measured once per reference.
(defun lg:ins-xform (ed base / rot sx sy)
  (setq rot (cond ((cdr (assoc 50 ed))) (0.0))
        sx  (cond ((cdr (assoc 41 ed))) (1.0))
        sy  (cond ((cdr (assoc 42 ed))) (1.0)))
  (if (zerop sx) (setq sx 1.0))
  (if (zerop sy) (setq sy 1.0))
  (list (lg:2d (cdr (assoc 10 ed))) (cos rot) (sin rot) sx sy (lg:2d base)))

(defun lg:xform-pt (p xf / q)
  (setq q (list (* (nth 3 xf) (- (car (lg:2d p)) (car (nth 5 xf))))
                (* (nth 4 xf) (- (cadr (lg:2d p)) (cadr (nth 5 xf))))))
  (lg:v+ (car xf)
         (list (- (* (nth 1 xf) (car q)) (* (nth 2 xf) (cadr q)))
               (+ (* (nth 2 xf) (car q)) (* (nth 1 xf) (cadr q))))))

;; SEGS carried through XF.  A rotation and a uniform scale keep an arc
;; an arc, and a MIRROR (one scale negative) reverses which way it
;; turns, so the bulge changes sign.  A block scaled unevenly turns its
;; arcs into ellipses, which a bulge cannot hold: those become their own
;; chords, which is the one place this reading is approximate.
(defun lg:xform-segs (segs xf / s blg mir uni out)
  (setq mir (< (* (nth 3 xf) (nth 4 xf)) 0.0)
        uni (equal (abs (nth 3 xf)) (abs (nth 4 xf)) 1e-9))
  (foreach s segs
    (setq blg (caddr s))
    (setq out (cons (list (lg:xform-pt (car s) xf)
                          (lg:xform-pt (cadr s) xf)
                          (cond ((not uni) 0.0)
                                (mir (- blg))
                                (t blg)))
                    out)))
  (reverse out))

;; the block definition's base point, (0 0) when it has none
(defun lg:blk-base (name / rec p)
  (setq rec (tblsearch "BLOCK" name)
        p   (if rec (cdr (assoc 10 rec))))
  (if p (lg:2d p) '(0.0 0.0)))

;; The definition's segments in the BLOCK's own coordinates.  Group -2 of
;; the block table record is its first entity and entnext walks the rest,
;; ENDBLK ending the run; a VERTEX or a SEQEND is stepped over here
;; because lg:plverts reads a heavy polyline's vertices itself.
(defun lg:blk-segs (name depth / rec e ed typ skip out)
  (setq rec  (tblsearch "BLOCK" name)
        e    (if rec (cdr (assoc -2 rec)))
        skip (mapcar 'strcase lg:*skiplayers*))
  (while (and e (setq ed (entget e))
              (/= "ENDBLK" (cdr (assoc 0 ed))))
    (setq typ (cdr (assoc 0 ed)))
    (if (not (member (strcase (cond ((cdr (assoc 8 ed))) ("0"))) skip))
      (cond
        ((member typ '("LINE" "ARC" "LWPOLYLINE" "POLYLINE"))
         (setq out (append out (lg:ent-segs e))))
        ((= typ "INSERT")
         (setq out (append out (lg:ins-segs e (1+ depth)))))))
    (setq e (entnext e)))
  out)

;; A block reference's segments in world coordinates.  nil for a name in
;; lg:*skipblocks*, a name with no definition, or a nest deeper than
;; lg:*blkdepth*.
(defun lg:ins-segs (ent depth / ed name)
  (setq ed   (entget ent)
        name (cdr (assoc 2 ed)))
  (if (and name
           (< depth lg:*blkdepth*)
           (not (lg:stylep name lg:*skipblocks*))
           (tblsearch "BLOCK" name))
    (lg:xform-segs (lg:blk-segs name depth)
                   (lg:ins-xform ed (lg:blk-base name)))))

;;; -------------------- tracing the exterior ----------------------------
;;; LINGUTTER does not look for a closed loop and hope one is the pool.
;;; It walks the OUTER FACE of the highlighted geometry and draws its own
;;; perimeter over it -- the outline you would get by walking round the
;;; outside of everything with your hand on the wall.
;;;
;;; Endpoints closer together than the snap tolerance become one node, so
;;; a drafting gap heals; every segment becomes two darts, one each way;
;;; and from the lowest node of each connected piece the walk always takes
;;; the hardest available RIGHT turn.  That rule is what hugs the outside:
;;; interior geometry -- the hopper, the steps, a bottom break -- is never
;;; stepped onto, because reaching it always needs a left turn.
;;;
;;; Three things follow, and they are the three ways the old
;;; largest-closed-loop guess got it wrong:
;;;   * a perimeter with a gap in it encloses nothing once its spurs are
;;;     pruned, so it fails LOUDLY at the tight tolerance instead of
;;;     quietly handing over whatever else did close;
;;;   * a hopper that closed while the outline did not can never win,
;;;     because it fails the coverage test below;
;;;   * and when no exterior can be walked at any tolerance there is
;;;     still an answer: the convex hull of everything highlighted.

;; A handful of points along one segment, its two ends included -- what
;; the coverage test measures and what the hull is wrapped round.  An arc
;; gets interior samples too: its bulge can carry it well outside the
;; straight line between its ends.
(defun lg:seg-pts (seg / a b blg dat cen r sa th i n out)
  (setq a   (car seg)
        b   (cadr seg)
        blg (caddr seg)
        out (list (lg:2d a) (lg:2d b)))
  (if (/= blg 0.0)
    (progn
      (setq dat (lg:arcdata a b blg)
            th  (car dat)
            r   (cadr dat)
            cen (caddr dat)
            sa  (angle cen a)
            n   6
            i   1)
      (repeat (1- n)
        (setq out (cons (lg:v+ cen (lg:v* (lg:dir (+ sa (* th (/ (float i) n))))
                                          r))
                        out)
              i   (1+ i)))))
  out)

(defun lg:segs-pts (segs / s out)
  (foreach s segs (setq out (append (lg:seg-pts s) out)))
  out)

;;; A drafter does not break a wall where something lands on it.  The
;;; right-hand wall of a pool with a tanning ledge in it is ONE line the
;;; full height of the pool, and the ledge's two sides run up to the
;;; middle of it -- a T, not a corner.  Endpoint connectivity cannot see
;;; a T: the wall has no node where the ledge meets it, so the walk runs
;;; straight past and the ledge, with nothing but two loose ends, prunes
;;; away as a spur.  That is how a pool came back as a plain rectangle
;;; with its ledge, its four ledge dimensions and its two corner radii
;;; all erased.
;;;
;;; So every segment is split wherever ANOTHER segment's END lands in the
;;; middle of it, before the graph is built and at the same tolerance.
;;; Only endpoints: two lines that merely CROSS mid-span still are not a
;;; junction, which is the promise the walk has always made and costs
;;; nothing on a CAD outline.

(defun lg:seg-ends (segs / s out)
  (foreach s segs (setq out (cons (car s) (cons (cadr s) out))))
  out)

;; OFFS as ascending offsets with none closer together than TOL, so a
;; split cannot make a zero-length piece out of two ends landing together
(defun lg:thin-offs (offs tol / o out last)
  (setq offs (vl-sort offs '<))
  (foreach o offs
    (if (or (null last) (> (- o last) tol))
      (setq out (cons o out) last o)))
  (reverse out))

;; T when P is inside the box A-B grown by TOL -- the cheap test that
;; keeps the split below from projecting every end onto every segment
(defun lg:near-box-p (p a b tol)
  (and (>= (car p) (- (min (car a) (car b)) tol))
       (<= (car p) (+ (max (car a) (car b)) tol))
       (>= (cadr p) (- (min (cadr a) (cadr b)) tol))
       (<= (cadr p) (+ (max (cadr a) (cadr b)) tol))))

;; A -> B straight, split at every end in ENDS that lands on it
(defun lg:split-line (a b ends tol / len v p u q offs out prev o)
  (setq len (distance a b) v (lg:v- b a))
  (if (<= len (* 2.0 tol))
    (list (list a b 0.0))
    (progn
      (foreach p ends
        (if (lg:near-box-p p a b tol)
          (progn
            (setq u (/ (lg:dot (lg:v- p a) v) (* len len)))
            (if (and (> u 0.0) (< u 1.0))
              (progn
                (setq q (lg:v+ a (lg:v* v u)))
                (if (and (<= (distance (lg:2d p) q) tol)
                         (> (* u len) tol) (> (* (- 1.0 u) len) tol))
                  (setq offs (cons (* u len) offs))))))))
      (if (null offs)
        (list (list a b 0.0))
        (progn
          (setq prev a)
          (foreach o (lg:thin-offs offs tol)
            (setq q    (lg:v+ a (lg:v* v (/ o len)))
                  out  (cons (list prev q 0.0) out)
                  prev q))
          (reverse (cons (list prev b 0.0) out)))))))

;; A -> B of bulge BLG, split the same way.  Offsets are swept ANGLES
;; here and each piece keeps its own bulge, so an arc stays an arc.
(defun lg:split-arc (a b blg ends tol / dat th r cen sa sgn sw p off q
                                        offs out prev o pang)
  (setq dat (lg:arcdata a b blg)
        th  (car dat)
        r   (cadr dat)
        cen (caddr dat)
        sa  (angle cen a)
        sgn (if (> th 0.0) 1.0 -1.0)
        sw  (abs th))
  (if (or (<= (* sw r) (* 2.0 tol)) (<= r 1e-9))
    (list (list a b blg))
    (progn
      (foreach p ends
        ;; off the circle by more than TOL cannot be on the arc, and that
        ;; is one distance instead of a point-on-arc projection
        (if (<= (abs (- (distance cen (lg:2d p)) r)) tol)
          (progn
            (setq pang (angle cen (lg:2d p))
                  off  (if (> th 0.0) (lg:angnorm (- pang sa))
                                      (lg:angnorm (- sa pang))))
            (if (and (> off 0.0) (< off sw))
              (progn
                (setq q (lg:v+ cen (lg:v* (lg:dir (+ sa (* sgn off))) r)))
                (if (and (<= (distance (lg:2d p) q) tol)
                         (> (* off r) tol) (> (* (- sw off) r) tol))
                  (setq offs (cons off offs))))))))
      (if (null offs)
        (list (list a b blg))
        (progn
          (setq prev a o 0.0)
          (foreach off (lg:thin-offs offs (/ tol r))
            (setq q    (lg:v+ cen (lg:v* (lg:dir (+ sa (* sgn off))) r))
                  out  (cons (list prev q (lg:bulge-of (* sgn (- off o))))
                             out)
                  prev q
                  o    off))
          (reverse (cons (list prev b (lg:bulge-of (* sgn (- sw o)))) out)))))))

;; the bulge of an arc that sweeps TH radians (tan of a quarter of it --
;; AutoLISP has no tan, the same way lg:ent-segs spells it)
(defun lg:bulge-of (th) (/ (sin (/ th 4.0)) (cos (/ th 4.0))))

(defun lg:split-tees (segs tol / ends s out)
  (setq ends (lg:seg-ends segs))
  (foreach s segs
    (setq out (append out
                      (if (equal (caddr s) 0.0 1e-12)
                        (lg:split-line (car s) (cadr s) ends tol)
                        (lg:split-arc (car s) (cadr s) (caddr s) ends tol)))))
  out)

;; The index of the node at P, adding P as a new node when nothing within
;; TOL is already there.  Returns (index nodelist).  Scanned oldest
;; first and stopped at the first hit, so when two nodes are both within
;; TOL the lower index is the one P joins; a walk that runs off the end
;; has counted the list, which is the index a new node gets.
(defun lg:node-of (p tol nodes / q i rest found)
  (setq q (lg:2d p) i 0 rest nodes found nil)
  (while (and rest (null found))
    (if (<= (distance q (car rest)) tol) (setq found i))
    (setq i (1+ i) rest (cdr rest)))
  (if found
    (list found nodes)
    (list i (append nodes (list q)))))

;; SEGS as a graph at snap tolerance TOL: (nodes segments), where each
;; segment is (node-a node-b bulge).  A segment whose two ends land on
;; the same node is dropped -- it is shorter than the tolerance and has
;; no direction left to walk in.
(defun lg:build-graph (segs tol / nodes segn s r ia ib)
  (foreach s segs
    (setq r     (lg:node-of (car s) tol nodes)
          ia    (car r)
          nodes (cadr r)
          r     (lg:node-of (cadr s) tol nodes)
          ib    (car r)
          nodes (cadr r))
    (if (/= ia ib) (setq segn (cons (list ia ib (caddr s)) segn))))
  (list nodes (reverse segn)))

;; The tangent angles of a segment travelled A -> B: (departing arriving).
;; A straight one departs and arrives on the same heading; an arc does
;; not, which is why the walk cannot just use (angle a b).
(defun lg:dart-tangents (a b blg / dat)
  (if (equal blg 0.0 1e-12)
    (list (angle a b) (angle a b))
    (progn
      (setq dat (lg:arcdata a b blg))
      (list (nth 3 dat) (nth 4 dat)))))

;; The dart for segment index I travelled DIR (1 = a->b, -1 = b->a):
;; (seg dir to departing arriving bulge).
(defun lg:dart (i dir seg nodes / a b blg tg)
  (setq blg (if (= dir 1) (caddr seg) (- (caddr seg)))
        a   (nth (if (= dir 1) (car seg) (cadr seg)) nodes)
        b   (nth (if (= dir 1) (cadr seg) (car seg)) nodes)
        tg  (lg:dart-tangents a b blg))
  (list i dir (if (= dir 1) (cadr seg) (car seg))
        (car tg) (cadr tg) blg))

;; One number per dart, so a face walk can mark the darts it used
(defun lg:dart-id (d) (+ (* 2 (car d)) (if (= 1 (cadr d)) 0 1)))

;; Every dart leaving every node, built once per graph: (nth V table) is
;; the darts leaving node V in segment order, which is the order
;; lg:next-dart's strict < breaks a tie in.  A face walk used to rescan
;; every segment at every step to find them -- the whole graph once per
;; dart travelled, on every rung of the snap ladder.
;;
;; AutoLISP has no array to push into, so each dart is tagged with its
;; node and its lg:dart-id, sorted on the pair -- unique, so vl-sort
;; drops nothing -- and cut into one slot per node, nil where nothing
;; leaves (a node whose only segment was too short to keep).
(defun lg:dart-table (nodes segn / i s d tagged v slot out)
  (setq i 0)
  (foreach s segn
    (setq d      (lg:dart i 1 s nodes)
          tagged (cons (list (car s) (lg:dart-id d) d) tagged)
          d      (lg:dart i -1 s nodes)
          tagged (cons (list (cadr s) (lg:dart-id d) d) tagged)
          i      (1+ i)))
  (setq tagged (vl-sort tagged '(lambda (a b)
                                  (if (= (car a) (car b))
                                    (< (cadr a) (cadr b))
                                    (< (car a) (car b)))))
        v      0)
  (repeat (length nodes)
    (setq slot nil)
    (while (and tagged (= (caar tagged) v))
      (setq slot   (cons (caddr (car tagged)) slot)
            tagged (cdr tagged)))
    (setq out (cons (reverse slot) out)
          v   (1+ v)))
  (reverse out))

(defun lg:same-dart (a b)
  (and a b (= (car a) (car b)) (= (cadr a) (cadr b))))

(defun lg:reverse-dart-p (a b)
  (and a b (= (car a) (car b)) (= (cadr a) (- (cadr b)))))

;; Arriving at V travelling at AIN, the next dart of the outer face: the
;; hardest right turn there is.  Measured as the smallest angle from the
;; way back (AIN + pi) round to the dart's departing tangent, taken over
;; (0, 2pi] so that turning straight back is the last resort rather than
;; the first choice.  Swap the sense of this one comparison and the same
;; walk traces interior faces instead.  ADJ is lg:dart-table's.
(defun lg:next-dart (v ain adj / darts d t2 best bt)
  (setq darts (nth v adj))
  (foreach d darts
    (setq t2 (lg:angnorm (- (nth 3 d) ain pi)))
    (if (<= t2 1e-9) (setq t2 (+ t2 pi pi)))
    (if (or (null best) (< t2 bt)) (setq best d bt t2)))
  best)

;; Walk the face that lies to the left of FIRST, leaving node START
;; along it.  Returns the darts travelled, each consed onto the node it
;; left, or nil when the walk never closed (which a sound graph does not
;; do -- the guard is there so a pathological one cannot hang AutoCAD).
;; ADJ is the graph's lg:dart-table; SEGN is there only to size the guard.
(defun lg:walk-from (start first adj segn / cur v ain out done guard lim)
  (setq cur   first
        v     start
        guard 0
        lim   (+ 10 (* 4 (length segn))))
  (while (not done)
    (setq out   (cons (cons v cur) out)
          ain   (nth 4 cur)
          v     (nth 2 cur)
          cur   (lg:next-dart v ain adj)
          guard (1+ guard))
    (if (or (null cur) (> guard lim)
            (and (= v start) (lg:same-dart cur first)))
      (setq done T)))
  (if (> guard lim) nil (reverse out)))

;; EVERY face of the graph, once each.
;;
;; Which face a walk traces is decided entirely by the dart it starts on:
;; lg:next-dart keeps the same side all the way round, so one dart
;; belongs to exactly one face and every dart belongs to one.  Guessing
;; the right starting dart is what used to be done, and it was a guess:
;; the shallowest dart at a component's lowest NODE is on the outer face
;; only while no arc leaving that node dips below it.  One that does --
;; the bottom of a free-form pool is full of them -- starts the walk the
;; other way round, and a walk going the other way round hugs the INSIDE.
;; That is how a pool came back without the bench and the step arcs that
;; were drawn over its own chords: the inner route was one turn tighter
;; at every node, which is exactly what the walk was asking for.
;;
;; So nothing is guessed.  Every face is walked, and lg:exterior keeps
;; the one enclosing the most area -- which is the outer boundary of the
;; whole component, since it is the face that contains all the others.
;; It costs no more work: each dart is still travelled exactly once.
(defun lg:all-faces (nodes segn / adj used i s dir d walk w out)
  (setq adj (lg:dart-table nodes segn)
        i   0)
  (foreach s segn
    (foreach dir '(1 -1)
      (setq d (lg:dart i dir s nodes))
      (if (not (member (lg:dart-id d) used))
        (progn
          (setq used (cons (lg:dart-id d) used)
                walk (lg:walk-from (if (= dir 1) (car s) (cadr s))
                                   d adj segn))
          (if walk
            (progn
              (foreach w walk
                (setq used (cons (lg:dart-id (cdr w)) used)))
              (setq out (cons walk out)))))))
    (setq i (1+ i)))
  (reverse out))

;; Drop every out-and-back excursion.  A dart followed by itself reversed
;; is a spur -- a tick mark, a stray line, or the whole of an outline that
;; never closed -- and the outer face really does run up it and back.  It
;; encloses nothing either way, and left in, PADDLE would read it as a
;; 180-degree inside corner and pad it.
(defun lg:prune (walk / out changed rest a b)
  (setq changed T)
  (while (and changed walk)
    (setq changed nil out nil rest walk)
    (while rest
      (setq a (car rest) b (cadr rest))
      (if (and b (lg:reverse-dart-p (cdr a) (cdr b)))
        (setq rest (cddr rest) changed T)
        (setq out (cons a out) rest (cdr rest))))
    (setq walk (reverse out))
    ;; the loop wraps, so its last dart and its first are neighbours too
    (if (and (> (length walk) 1)
             (lg:reverse-dart-p (cdr (last walk)) (cdr (car walk))))
      (setq walk    (reverse (cdr (reverse (cdr walk))))
            changed T)))
  walk)

(defun lg:walk-vts (walk nodes / w p out)
  (foreach w walk
    (setq p   (nth (car w) nodes)
          out (cons (list (car p) (cadr p) (nth 6 w)) out)))
  (reverse out))

;;; Splitting at a T puts a node in the middle of a wall, and the walk
;;; then reports the wall as two edges meeting dead straight -- or a
;;; traced arc as seven pieces of one circle, which is what the bottom of
;;; a radius-corner step does to the step outline running past it.  They
;;; are the same curve, so they come back out: a run of consecutive edges
;;; that is one straight line, or one arc about one centre, is welded
;;; into a single edge.  What the drafter gets is the outline they drew,
;;; not a polyline carrying a vertex for every tread that touched it --
;;; and PADDLE is not offered a string of 180-degree corners to pad.

;; smallest signed angular difference (to - from), in (-pi, pi] -- the
;; library's cal:signed-dang, copied so this file loads alone
(defun lg:signed-dang (from to / d)
  (setq d (lg:angnorm (- to from)))
  (if (> d pi) (- d (* 2.0 pi)) d))

(setq lg:*weldtol* 1.0e-6)         ; not a knob: how nearly two edges have
                                   ; to BE one curve before they are welded
                                   ; into one.  A millionth of an inch --
                                   ; the split points it undoes are exact,
                                   ; so this is float noise, not a
                                   ; drafting tolerance

;; T when edge A->B and edge B->C are one curve (A and B carry the
;; bulges of the edges leaving them, as everywhere else here)
(defun lg:weldable-p (a b c / b1 b2 d1 d2)
  (setq b1 (caddr a) b2 (caddr b))
  (cond
    ((and (equal b1 0.0 1e-12) (equal b2 0.0 1e-12))
     (<= (abs (lg:signed-dang (angle (lg:2d a) (lg:2d b))
                              (angle (lg:2d b) (lg:2d c))))
         1e-9))
    ((or (equal b1 0.0 1e-12) (equal b2 0.0 1e-12)) nil)
    ((< (* b1 b2) 0.0) nil)                ; turning opposite ways
    (t
     (setq d1 (lg:arcdata (lg:2d a) (lg:2d b) b1)
           d2 (lg:arcdata (lg:2d b) (lg:2d c) b2))
     (and (<= (distance (caddr d1) (caddr d2)) lg:*weldtol*)
          (<= (abs (- (cadr d1) (cadr d2))) lg:*weldtol*)
          ;; never weld a run the whole way round: a full circle has no
          ;; bulge to carry it
          (< (+ (abs (car d1)) (abs (car d2))) (- (+ pi pi) 1e-9))))))

;; the bulge edge A->C needs once B is gone
(defun lg:weld-blg (a b c / b1 b2)
  (setq b1 (caddr a) b2 (caddr b))
  (if (and (equal b1 0.0 1e-12) (equal b2 0.0 1e-12))
    0.0
    (lg:bulge-of (+ (car (lg:arcdata (lg:2d a) (lg:2d b) b1))
                    (car (lg:arcdata (lg:2d b) (lg:2d c) b2))))))

(defun lg:weld (vts / changed n i a b c out drops)
  (setq changed T)
  (while (and changed (> (length vts) 3))
    (setq changed nil
          n       (length vts)
          drops   0
          out     nil
          a       (car vts)
          i       1)
    (while (< i n)
      (setq b (nth i vts)
            c (nth (rem (1+ i) n) vts))
      ;; never below three vertices: a loop needs them, and a run that
      ;; goes the whole way round has no bulge that could carry it
      (if (and (> (- n drops) 3) (lg:weldable-p a b c))
        (setq a       (list (car a) (cadr a) (lg:weld-blg a b c))
              drops   (1+ drops)
              changed T)
        (setq out (cons a out) a b))
      (setq i (1+ i)))
    (setq vts (reverse (cons a out)))
    ;; the sweep above never gets to drop the FIRST vertex, and a run
    ;; that straddles the wrap has one there.  Turn the loop by one and
    ;; the next pass meets it in the middle.
    (if (and (> (length vts) 3)
             (lg:weldable-p (last vts) (car vts) (cadr vts)))
      (setq vts     (append (cdr vts) (list (car vts)))
            changed T)))
  vts)

;; The largest exterior the highlight can be walked round at tolerance
;; TOL.  Every face of every connected piece is walked and the one
;; enclosing the most area wins -- which is both the outer boundary of
;; its own piece and, across pieces, the pool rather than the stray line
;; or the smaller second pool beside it.  Nothing has to rank them and
;; nothing has to guess where to start.
(defun lg:exterior (segs tol / g nodes segn face walk vts a best bestarea)
  (setq g        (lg:build-graph (lg:split-tees segs tol) tol)
        nodes    (car g)
        segn     (cadr g)
        bestarea 0.0)
  (foreach face (lg:all-faces nodes segn)
    (setq walk (lg:prune face))
    (if (> (length walk) 2)
      (progn
        (setq vts (lg:weld (lg:walk-vts walk nodes))
              a   (abs (lg:area vts)))
        (if (> a bestarea) (setq bestarea a best vts)))))
  best)

(defun lg:bbox (pts / p mnx mny mxx mxy)
  (foreach p pts
    (if (null mnx)
      (setq mnx (car p) mxx (car p) mny (cadr p) mxy (cadr p))
      (setq mnx (min mnx (car p)) mxx (max mxx (car p))
            mny (min mny (cadr p)) mxy (max mxy (cadr p)))))
  (if mnx (list mnx mny mxx mxy)))

;; T when the traced loop spans at least lg:*cover* of what was
;; highlighted, both ways.  This is the "is that really the perimeter?"
;; test, and it is the one the old code did not have: a hopper rectangle
;; traced because the outline round it never closed is a perfectly good
;; closed loop and a perfectly wrong answer.  Its extent gives it away.
(defun lg:covers-p (vts pts / lb pb w h)
  (setq lb (lg:bbox (lg:segs-pts (lg:vts->segs T vts)))
        pb (lg:bbox pts))
  (if (and lb pb)
    (progn
      (setq w (- (nth 2 pb) (car pb))
            h (- (nth 3 pb) (cadr pb)))
      (and (or (<= w 1e-9) (>= (/ (- (nth 2 lb) (car lb)) w) lg:*cover*))
           (or (<= h 1e-9) (>= (/ (- (nth 3 lb) (cadr lb)) h) lg:*cover*))))))

(defun lg:cross3 (o a b)
  (- (* (- (car a) (car o)) (- (cadr b) (cadr o)))
     (* (- (cadr a) (cadr o)) (- (car b) (car o)))))

;; Convex hull of PTS (Andrew's monotone chain).  The last resort: when no
;; exterior can be walked at any tolerance LINGUTTER still draws a
;; perimeter, and this one is guaranteed to enclose every bit of what was
;; highlighted.  It is reported as what it is -- a wrap, not a trace --
;; because it straightens out every concave feature PADDLE exists to find.
(defun lg:hull (pts / srt lower upper p out)
  (setq srt (vl-sort pts '(lambda (a b)
                            (if (equal (car a) (car b) 1e-9)
                              (< (cadr a) (cadr b))
                              (< (car a) (car b))))))
  (foreach p srt
    (while (and (cdr lower) (<= (lg:cross3 (cadr lower) (car lower) p) 0.0))
      (setq lower (cdr lower)))
    (setq lower (cons p lower)))
  (foreach p (reverse srt)
    (while (and (cdr upper) (<= (lg:cross3 (cadr upper) (car upper) p) 0.0))
      (setq upper (cdr upper)))
    (setq upper (cons p upper)))
  (setq out (append (reverse (cdr lower)) (reverse (cdr upper))))
  (if (> (length out) 2)
    (mapcar '(lambda (q) (list (car q) (cadr q) 0.0)) out)))

;; The snap ladder as the walk needs it: numbers above zero, tightest
;; first.  The ORDER is not the drafter's to choose -- lg:perimeter
;; climbs a rung at a time and reports the rung that worked, and it
;; calls the first rung "nothing had to be moved".  A ladder typed
;; loosest-first would therefore heal a 24" gap and report that nothing
;; moved, which is the one thing this tool promises never to be quiet
;; about.  Sorting here makes "tightest first" true however it was
;; typed, and drops anything that is not a usable tolerance.
;;
;; Nothing usable left means no snapping at all rather than no walk at
;; all: a hairline rung still traces an outline that was drawn closed,
;; where an empty ladder would send even a clean pool to the hull.
(defun lg:ladder ( / out)
  (setq out (vl-sort (vl-remove-if-not
                       '(lambda (x) (and (numberp x) (> x 0.0)))
                       lg:*snaps*)
                     '<))
  (if out out (list 1e-6)))

;; The perimeter of the highlighted geometry, and how it was arrived at.
;; Returns (vts (tol short)), where tol is
;;   nil     the exterior was walked with nothing moved,
;;   <n>     ...after ends that far apart were treated as one to close it,
;;   HULL    no exterior could be walked at all, so the geometry was
;;           simply wrapped,
;; and short is T when what was traced spans less of the highlight than
;; lg:*cover* asks -- a warning, never a veto.  Coverage decides whether
;; to try a looser tolerance, and the loosest run still wins over nothing:
;; a pool highlighted alongside a long stray line fails the test through
;; no fault of its own, and answering that with a convex hull would be
;; worse than answering it with the pool and a word of warning.
;; nil when there is not enough geometry to draw a perimeter round.
(defun lg:perimeter (segs / pts tol vts a out fall falla falltol tight
                            rungs)
  (setq pts   (lg:segs-pts segs)
        falla 0.0
        rungs (lg:ladder)
        tight (car rungs))
  (foreach tol rungs
    (if (null out)
      (progn
        (setq vts (lg:exterior segs tol))
        (if vts
          (if (lg:covers-p vts pts)
            (setq out (list vts (list (if (equal tol tight 1e-12) nil tol)
                                      nil)))
            (progn
              (setq a (abs (lg:area vts)))
              (if (> a falla) (setq fall vts falla a falltol tol))))))))
  (if (and (null out) fall)
    (setq out (list fall (list (if (equal falltol tight 1e-12) nil falltol)
                               T))))
  (if (and (null out) pts)
    (progn
      (setq vts (lg:hull pts))
      (if vts (setq out (list vts (list 'HULL nil))))))
  out)

;;; -------------------- is it on the perimeter? -------------------------

;; distance from P to the straight segment A-B
(defun lg:pt-seg-dist (p a b / v w l u)
  (setq v (lg:v- b a)
        w (lg:v- p a)
        l (lg:dot v v))
  (if (<= l 1e-18)
    (distance (lg:2d p) a)
    (progn
      (setq u (/ (lg:dot w v) l)
            u (max 0.0 (min 1.0 u)))
      (distance (lg:2d p) (lg:v+ a (lg:v* v u))))))

;; distance from P to the arc A-B of bulge BLG: off the radius while P
;; lies within the sweep, off the nearer end once it does not
(defun lg:pt-arc-dist (p a b blg / dat cen th sa ap off)
  (setq dat (lg:arcdata a b blg)
        th  (car dat)
        cen (caddr dat)
        sa  (angle cen a)
        ap  (angle cen (lg:2d p))
        off (if (> th 0.0) (lg:angnorm (- ap sa)) (lg:angnorm (- sa ap))))
  (if (<= off (abs th))
    (abs (- (distance cen (lg:2d p)) (cadr dat)))
    (min (distance (lg:2d p) a) (distance (lg:2d p) b))))

(defun lg:pt-loop-dist (p vts / n i a b blg d best)
  (setq n (length vts) i 0 best nil)
  (repeat n
    (setq a   (nth i vts)
          b   (nth (rem (1+ i) n) vts)
          blg (caddr a)
          d   (if (/= blg 0.0)
                (lg:pt-arc-dist p (lg:2d a) (lg:2d b) blg)
                (lg:pt-seg-dist p (lg:2d a) (lg:2d b))))
    (if (or (null best) (< d best)) (setq best d))
    (setq i (1+ i)))
  best)

;; The definition points that say what a LINEAR dimension is attached
;; to.  13 and 14 are the two measured points of a linear, aligned,
;; ordinate or angular dim.  Everything else in the entity -- 11 (the
;; text), 16 (an angular dim's arc) -- places the dimension rather than
;; attaching it, so it is not tested.  A radius or diameter dim carries
;; no 13/14 at all and is read by lg:radial-on-perim-p below instead --
;; which is why the group 10 fallback here EXCLUDES a radial dim: 10 is
;; that dim's centre, and a centre can sit exactly on the loop by
;; coincidence (the centre of a radius-corner step's tread arcs sits on
;; the step outline running past them), which would keep an interior
;; call-out as a perimeter one.  The fallback is for a dim carrying
;; neither, which a sound drawing does not produce.
(defun lg:dim-pts (ed / out p c)
  (foreach c '(13 14)
    (if (setq p (cdr (assoc c ed))) (setq out (cons p out))))
  (if (and (null out) (not (lg:radial-p ed)))
    (if (setq p (cdr (assoc 10 ed))) (setq out (list p))))
  out)

;; T when ED is a RADIUS or DIAMETER dimension -- DXF 70's low three
;; bits are 4 for radius, 3 for diameter.  Read from the type flag
;; rather than "has no 13/14": a malformed dim is then just "not
;; radial", not a silent radial match.
(defun lg:radial-p (ed / k)
  (setq k (logand 7 (cdr (assoc 70 ed))))
  (or (= k 3) (= k 4)))

;;; A radius dimension does NOT hang off group 10.  Group 10 is the
;;; CENTRE of the arc it calls out and group 15 is the point on the
;;; curve -- the other way round from what this file used to assume, and
;;; the reason every corner-radius call-out on a pool was erased: the
;;; centre of a 24" corner sits 24" inside the loop, so "within
;;; lg:*ontol* of the perimeter" was never true of it.  (A DIAMETER
;;; dim's 10 and 15 are the two ends of a diameter, both on the curve.)
;;;
;;; So a radial dim is kept when any one of three things is true, and
;;; they are three real shapes on these sheets:
;;;   * its point ON the curve is on the perimeter -- an arc the walk
;;;     traced and the arrow landing inside the swept part of it;
;;;   * it NAMES an arc of the perimeter -- same centre, same radius.
;;;     This is the one that matters, because a leader is routinely
;;;     dragged round to where it reads well and its arrow then lands
;;;     on the same circle but past the end of the drawn arc;
;;;   * its centre sits on a VERTEX of the perimeter -- "R3 typ." on a
;;;     corner that is drawn sharp and is meant to be filleted.  A
;;;     vertex, not merely somewhere along an edge: the centre of an
;;;     interior tread arc can sit exactly ON an outer arc by
;;;     coincidence, and does on a radius-corner step.

;; (centre radius), or nil when ED does not carry enough to say
(defun lg:radial-cr (ed / p10 p15 k)
  (setq p10 (cdr (assoc 10 ed))
        p15 (cdr (assoc 15 ed))
        k   (logand 7 (cdr (assoc 70 ed))))
  (if (and p10 p15)
    (if (= k 3)
      (list (lg:v* (lg:v+ p10 p15) 0.5) (/ (distance (lg:2d p10) (lg:2d p15))
                                          2.0))
      (list (lg:2d p10) (distance (lg:2d p10) (lg:2d p15))))))

;; the points of ED that really are on the curve: 15 always, and 10 too
;; for a diameter dim.  Group 10 alone when there is no 15 to go on.
(defun lg:radial-pts (ed / p10 p15)
  (setq p10 (cdr (assoc 10 ed))
        p15 (cdr (assoc 15 ed)))
  (cond
    ((null p15) (if p10 (list p10)))
    ((= 3 (logand 7 (cdr (assoc 70 ed)))) (list p15 p10))
    (t (list p15))))

;; T when VTS has an arc edge of centre CEN and radius R, both within
;; lg:*ontol*
(defun lg:loop-arc-p (cen r vts / n i a b blg dat hit)
  (setq n (length vts) i 0)
  (repeat n
    (setq a   (nth i vts)
          b   (nth (rem (1+ i) n) vts)
          blg (caddr a))
    (if (/= blg 0.0)
      (progn
        (setq dat (lg:arcdata (lg:2d a) (lg:2d b) blg))
        (if (and (<= (distance (caddr dat) (lg:2d cen)) lg:*ontol*)
                 (<= (abs (- (cadr dat) r)) lg:*ontol*))
          (setq hit t))))
    (setq i (1+ i)))
  hit)

(defun lg:radial-on-perim-p (ed vts / pts p cr ok)
  (setq pts (lg:radial-pts ed)
        cr  (lg:radial-cr ed))
  (foreach p pts
    (if (<= (lg:pt-loop-dist p vts) lg:*ontol*) (setq ok t)))
  (if (and (not ok) cr (lg:loop-arc-p (car cr) (cadr cr) vts)) (setq ok t))
  (if (and (not ok) cr (lg:at-vertex-p (car cr) vts)) (setq ok t))
  ok)

;; T when every attachment point sits within lg:*ontol* of the loop.
;; Every, not any: a dim running from the pool edge in to the hopper is
;; measuring the hopper, and one end on the perimeter does not make it a
;; perimeter dimension.
(defun lg:on-perim-p (ed vts / pts ok p)
  (setq pts (lg:dim-pts ed)
        ok  (and pts t))
  (foreach p pts
    (if (> (lg:pt-loop-dist p vts) lg:*ontol*) (setq ok nil)))
  ok)

;; T when P lies inside the polygon VTS by the even-odd rule.  A curved
;; side is taken as its own straight chord here -- close enough to tell
;; "inside" from "outside" deep in the pool, and a point that is instead
;; RIGHT AT a curved side is caught by lg:pt-loop-dist's true arc math in
;; lg:cross-ok-p below, not by this approximation.
(defun lg:pt-inside-p (p vts / n i a b xi yi xj yj px py inside)
  (setq px     (car (lg:2d p))
        py     (cadr (lg:2d p))
        n      (length vts)
        i      0
        inside nil)
  (repeat n
    (setq a  (nth i vts)
          b  (nth (rem (1+ i) n) vts)
          xi (car a) yi (cadr a)
          xj (car b) yj (cadr b))
    (if (and (not (eq (> yi py) (> yj py)))
             (< px (+ xi (/ (* (- xj xi) (- py yi)) (- yj yi)))))
      (setq inside (not inside)))
    (setq i (1+ i)))
  inside)

;; T when P sits inside the perimeter, or on it -- the baseline "does
;; this point belong to the pool LINGUTTER just gutted at all" test.  A
;; point that fails this is not a fraction of an inch off; it is a
;; stray dim, or one measuring a second pool in the same highlight.
(defun lg:pt-belongs-p (p vts)
  (or (lg:pt-inside-p p vts) (<= (lg:pt-loop-dist p vts) lg:*ontol*)))

;; T when P sits within lg:*ontol* of a VERTEX of the perimeter -- a
;; true corner, not merely somewhere along the edge leaving or
;; arriving at it.
(defun lg:at-vertex-p (p vts / hit v)
  (foreach v vts
    (if (<= (distance (lg:2d p) (lg:2d v)) lg:*ontol*) (setq hit t)))
  hit)

;; T when P1 and P2 both sit on some ONE perimeter edge and are NOT
;; that edge's own two endpoints -- the start of a line to some random
;; point in the middle of that same line.  A cross dim shaped like this
;; measures a fraction of one side, not the pool, and is never kept
;; regardless of span: a long enough side could otherwise make a
;; partial reading look like it spans the pool by accident.
;; Every edge is checked in its own right rather than classifying each
;; point to "the" edge it sits on first: a point sitting exactly at a
;; shared VERTEX sits on the two edges that meet there, and picking
;; only one by iteration order could clear a partial read on whichever
;; edge it did not pick.
(defun lg:same-edge-partial-p (p1 p2 vts / n i a b blg d1 d2 veto)
  (setq n (length vts) i 0 veto nil)
  (repeat n
    (setq a   (nth i vts)
          b   (nth (rem (1+ i) n) vts)
          blg (caddr a)
          d1  (if (/= blg 0.0)
                (lg:pt-arc-dist p1 (lg:2d a) (lg:2d b) blg)
                (lg:pt-seg-dist p1 (lg:2d a) (lg:2d b)))
          d2  (if (/= blg 0.0)
                (lg:pt-arc-dist p2 (lg:2d a) (lg:2d b) blg)
                (lg:pt-seg-dist p2 (lg:2d a) (lg:2d b))))
    (if (and (<= d1 lg:*ontol*) (<= d2 lg:*ontol*)
             (not (or (and (<= (distance (lg:2d p1) (lg:2d a)) lg:*ontol*)
                           (<= (distance (lg:2d p2) (lg:2d b)) lg:*ontol*))
                      (and (<= (distance (lg:2d p1) (lg:2d b)) lg:*ontol*)
                           (<= (distance (lg:2d p2) (lg:2d a)) lg:*ontol*)))))
      (setq veto t))
    (setq i (1+ i)))
  veto)

;; T when a lg:*perimstyles* dimension is a dimension OF THE PERIMETER:
;; every attachment point on the loop, and the two of them not a partial
;; read along one single edge.
;;
;; The second half is the same test the cross-dim rule has always
;; applied, and it is here for the same reason.  A step built against a
;; pool wall has its risers and its treads dimensioned ALONG that wall,
;; so both ends of a 16" tread dim sit exactly on the perimeter while the
;; thing being measured is the step.  "The start of one side to the end
;; of it" is a side dimension; "two points partway along one side" is a
;; reading of something that happens to lie against it, and it goes with
;; the rest of the step.
(defun lg:perim-dim-p (ed vts / pts)
  (setq pts (lg:dim-pts ed))
  (and (lg:on-perim-p ed vts)
       (or (/= (length pts) 2)
           (not (lg:same-edge-partial-p (car pts) (cadr pts) vts)))))

;; T when P1-P2 spans at least lg:*crossspan* of the perimeter's own
;; bounding box, in X or in Y -- "goes full X" or "goes full Y", an
;; overall check dimension from one side to the other, corners or not.
(defun lg:full-span-p (p1 p2 vts / bb w h dx dy)
  (setq bb (lg:bbox (lg:segs-pts (lg:vts->segs T vts))))
  (if bb
    (progn
      (setq w  (- (nth 2 bb) (car bb))
            h  (- (nth 3 bb) (cadr bb))
            dx (abs (- (car (lg:2d p1)) (car (lg:2d p2))))
            dy (abs (- (cadr (lg:2d p1)) (cadr (lg:2d p2)))))
      (or (and (> w 1e-9) (>= (/ dx w) lg:*crossspan*))
          (and (> h 1e-9) (>= (/ dy h) lg:*crossspan*))))))

;; T when P1 and P2 are each within lg:*ontol* of SOME vertex of the
;; perimeter -- corner to corner, "the start of a line to the end of a
;; line", whichever two corners they are and however short that run is.
;; A short notch side would otherwise never pass lg:full-span-p.
(defun lg:vertex-to-vertex-p (p1 p2 vts)
  (and (lg:at-vertex-p p1 vts) (lg:at-vertex-p p2 vts)))

;; T when a lg:*anystyles* dimension is a genuine cross dim OF THIS
;; POOL: both attachment points belong to the perimeter at all, neither
;; is a partial read along one same edge, and together they either span
;; most of the pool (lg:full-span-p) or run corner to corner along one
;; full edge (lg:vertex-to-vertex-p).  Anything else highlighted in
;; this style -- a small dimension entirely inside touching nothing, a
;; stray one answering to a different pool -- goes with the rest.
(defun lg:cross-ok-p (ed vts / pts p1 p2)
  (setq pts (lg:dim-pts ed))
  (and (= (length pts) 2)
       (setq p1 (car pts) p2 (cadr pts))
       (lg:pt-belongs-p p1 vts)
       (lg:pt-belongs-p p2 vts)
       (not (lg:same-edge-partial-p p1 p2 vts))
       (or (lg:full-span-p p1 p2 vts)
           (lg:vertex-to-vertex-p p1 p2 vts))))

;;; -------------------- styles and tallies ------------------------------

;; the dimension's style name, "" when it has none
(defun lg:dim-style (ed / s)
  (setq s (cdr (assoc 3 ed)))
  (if s s ""))

;; T when STY matches one of PATS.  The patterns are wildcards so that
;; "CROSS DIM*" covers a drawing whose style is spelled "CROSS DIM" and
;; one whose style is this repo's "CROSS DIMENSIONS"; case is folded,
;; because wcmatch is not.
(defun lg:stylep (sty pats / hit p)
  (setq sty (strcase sty))
  (foreach p pats
    (if (wcmatch sty (strcase p)) (setq hit t)))
  hit)

;; ((key . count) ...) with KEY's count raised by one
(defun lg:tally (key lst / p)
  (if (setq p (assoc key lst))
    (subst (cons key (1+ (cdr p))) p lst)
    (append lst (list (cons key 1)))))

;; Why a highlighted DIMENSION in style STY would be dropped, for the
;; report's tally -- a reason, not a raw style name, is the whole point
;; of counting drops at all.  A style already ruled out by the caller
;; (lg:radial-p and lg:radial-on-perim-p, ahead of this in lg:analyze)
;; never reaches here on THAT ground, so a lg:*anystyles* style always
;; means either the CROSS DIMENSIONS question or lg:cross-ok-p is why it
;; goes.  ONP is whether a lg:*perimstyles* dim reached the perimeter at
;; all, so the two ways one of those can fail read differently in the
;; tally: nowhere near the loop, or on it but reading a part of one side.
(defun lg:drop-reason (sty keepcross onp)
  (strcat (if (= sty "") "(no style)" sty)
          (cond
            ((lg:stylep sty lg:*anystyles*)
             (if keepcross
               " - not a full span or a full perimeter edge"
               " - \"Keep CROSS DIMENSIONS?\" answered No"))
            ((and (lg:stylep sty lg:*perimstyles*) onp)
             " - a part of one side, not the perimeter")
            ((lg:stylep sty lg:*perimstyles*) " - not on the perimeter")
            (t " - style not kept"))))

(defun lg:s (n) (if (= n 1) "" "s"))

;; "A, B and C" from a list of strings
(defun lg:names (lst / n out)
  (setq out "")
  (while lst
    (setq n   (car lst)
          lst (cdr lst)
          out (cond ((= out "") n)
                    ((null lst) (strcat out " and " n))
                    (t (strcat out ", " n)))))
  out)

;;; -------------------- reading the drawing -----------------------------

;; every entity in the current tab, as a list of enames
;; The highlighted set: a pickfirst selection when there is one,
;; otherwise ask for it.  There is no "the whole drawing" answer --
;; LINGUTTER erases what it sweeps, so it sweeps only what you showed
;; it, and nothing outside the highlight is read, kept or erased.
(defun lg:highlight ( / ss)
  (setq ss (ssget "_I"))
  (if lzd:watch (lzd:watch ss) ss)
  (if (null ss)
    (progn
      (princ "\nHighlight the area to gut: ")
      (setq ss (ssget))
      (if lzd:watch (lzd:watch ss) ss)))
  ss)

;; the highlighted set as a list of enames
(defun lg:ss-ents (ss / i out)
  (setq i 0)
  (if ss
    (repeat (sslength ss)
      (setq out (cons (ssname ss i) out)
            i   (1+ i))))
  (reverse out))

;; The segments the perimeter may be traced from: the drawn geometry
;; INSIDE the highlight, less the layers lg:*skiplayers* names -- and a
;; BLOCK REFERENCE's own geometry with it, because a step bolted to a
;; wall is drawn as one (lg:ins-segs, and lg:*skipblocks* for the two
;; families that are never part of the outline).
(defun lg:trace-segs (ss / i out en ed typ skip)
  (setq i 0 skip (mapcar 'strcase lg:*skiplayers*))
  (if ss
    (repeat (sslength ss)
      (setq en  (ssname ss i)
            ed  (entget en)
            typ (cdr (assoc 0 ed))
            i   (1+ i))
      (if (not (member (strcase (cond ((cdr (assoc 8 ed))) ("0"))) skip))
        (cond
          ((member typ '("LINE" "ARC" "LWPOLYLINE" "POLYLINE"))
           (setq out (append out (lg:ent-segs en))))
          ((= typ "INSERT")
           (setq out (append out (lg:ins-segs en 0))))))))
  out)

;; Everything both commands need to know about the highlighted set SS,
;; worked out without changing a thing.  Nothing outside SS is looked
;; at: the perimeter is traced from the geometry in it, and only what
;; is in it can be kept or erased.  KEEPCROSS is the answer to "Keep
;; CROSS DIMENSIONS?" -- T to spare lg:*anystyles* dims that are inside
;; the perimeter or connected to it, nil to give them no exemption.
;; Returns (vts gap kill nany nperim nrad dropped nother nspared):
;;   vts      the perimeter as (x y bulge) vertices, nil when none found
;;   how      (tol short) from lg:perimeter: how the perimeter was
;;            arrived at, and whether it covers the highlight
;;   kill     the entities that would be erased
;;   nany     lg:*anystyles* dims kept (KEEPCROSS, inside or connected)
;;   nperim   dims kept because they sit on the perimeter, by style
;;   nrad     radius/diameter dims kept because they sit on the
;;            perimeter, REGARDLESS of style
;;   dropped  ((reason . count) ...) for the dimensions that would go
;;   nother   objects that would go which are not dimensions
;;   nspared  objects left alone because lg:*keeplayers* names their layer
(defun lg:analyze (ss keepcross / best vts how kill nany nperim nrad
                       dropped nother nspared en ed typ sty lay spare)
  (setq best    (lg:perimeter (lg:trace-segs ss))
        vts     (car best)
        how     (cadr best)
        nany    0
        nperim  0
        nrad    0
        nother  0
        nspared 0
        spare   (mapcar 'strcase (lg:keeplayers)))
  (if vts
    (foreach en (lg:ss-ents ss)
      (setq ed  (entget en)
            typ (cdr (assoc 0 ed))
            lay (strcase (cond ((cdr (assoc 8 ed))) ("0"))))
      (cond
        ((= typ "VIEWPORT") nil)             ; never ours to erase
        ((member lay spare) (setq nspared (1+ nspared)))
        ((= typ "DIMENSION")
         (setq sty (lg:dim-style ed))
         (cond
           ((and (lg:radial-p ed) (lg:radial-on-perim-p ed vts))
            (setq nrad (1+ nrad)))
           ((and keepcross (lg:stylep sty lg:*anystyles*)
                 (lg:cross-ok-p ed vts))
            (setq nany (1+ nany)))
           ((and (lg:stylep sty lg:*perimstyles*) (lg:perim-dim-p ed vts))
            (setq nperim (1+ nperim)))
           (t
            (setq dropped (lg:tally (lg:drop-reason
                                      sty keepcross
                                      (and (lg:stylep sty lg:*perimstyles*)
                                           (lg:on-perim-p ed vts)))
                                    dropped)
                  kill    (cons en kill)))))
        (t (setq nother (1+ nother)
                 kill   (cons en kill))))))
  (list vts how (reverse kill) nany nperim nrad dropped nother nspared))

;;; -------------------- writing the drawing -----------------------------

;; One closed LWPOLYLINE through VTS on LAY, ByLayer -- no per-entity
;; colour, linetype or lineweight, so the perimeter looks like whatever
;; the POOL layer says, the way POOL and DRONE leave it.
(defun lg:draw-perim (vts lay / dxf v)
  (setq dxf (list '(0 . "LWPOLYLINE")
                  '(100 . "AcDbEntity")
                  (cons 8 lay)
                  '(100 . "AcDbPolyline")
                  (cons 90 (length vts))
                  '(70 . 1)))
  (foreach v vts
    (setq dxf (append dxf (list (cons 10 (list (car v) (cadr v))))))
    (if (/= 0.0 (caddr v))
      (setq dxf (append dxf (list (cons 42 (caddr v)))))))
  (entmakex dxf))

;; the layers the erase has to reach, so the locked ones among them can
;; be opened first
(defun lg:kill-layers (kill / out en ed lay)
  (foreach en kill
    (setq ed  (entget en)
          lay (cond ((cdr (assoc 8 ed))) ("0")))
    (if (not (member lay out)) (setq out (cons lay out))))
  out)

;;; -------------------- the report --------------------------------------

(defun lg:report (res keepcross / vts how kill nany nperim nrad dropped
                        nother nspared d)
  (setq vts     (nth 0 res)
        how     (nth 1 res)
        kill    (nth 2 res)
        nany    (nth 3 res)
        nperim  (nth 4 res)
        nrad    (nth 5 res)
        dropped (nth 6 res)
        nother  (nth 7 res)
        nspared (nth 8 res))
  (if (null vts)
    (princ (strcat "\nLINGUTTER: nothing to draw a perimeter round - the"
                   " highlight holds no lines, arcs or polylines, or none"
                   " off " (lg:names lg:*skiplayers*) "."))
    (progn
      (princ (strcat "\nLINGUTTER: perimeter "
                     (if (eq (car how) 'HULL) "wrapped" "traced") " - "
                     (itoa (length vts)) " vertice" (lg:s (length vts)) ", "
                     (rtos (lg:perim-len vts)) " around."))
      (cond
        ((eq (car how) 'HULL)
         (princ (strcat "\n** No exterior could be walked at any tolerance"
                        " up to " (rtos (last (lg:ladder)) 2 2) " - the"
                        " highlight is wrapped in its convex hull instead."
                        "  That straightens out every concave feature, so"
                        " PADDLE will find nothing to pad: close the"
                        " outline and run it again.")))
        ((car how)
         (princ (strcat "\nLINGUTTER: it would not close as drawn - ends up"
                        " to " (rtos (car how)) " apart were treated as one"
                        " to walk round it."))))
      (if (cadr how)
        (princ (strcat "\n** What was traced spans less than "
                       (rtos (* 100.0 lg:*cover*) 2 0) "% of what you"
                       " highlighted.  Check it really is the pool before"
                       " answering Yes - highlighting less, or closing the"
                       " outline, is what fixes it.")))
      (if keepcross
        (princ (strcat "\nLINGUTTER: keeping " (itoa nany) " dimension"
                       (lg:s nany) " in " (lg:names lg:*anystyles*)
                       " as a full-span or full-edge cross measurement"
                       " of the pool."))
        (princ (strcat "\nLINGUTTER: \"Keep CROSS DIMENSIONS?\" answered"
                       " No - dimensions in " (lg:names lg:*anystyles*)
                       " get no exemption.")))
      (princ (strcat "\nLINGUTTER: keeping " (itoa nperim) " dimension"
                     (lg:s nperim) " that dimension the perimeter, in "
                     (lg:names lg:*perimstyles*)
                     " - on it, and not a part of one side."))
      (princ (strcat "\nLINGUTTER: keeping " (itoa nrad) " radius/diameter"
                     " dimension" (lg:s nrad) " of the perimeter,"
                     " regardless of style."))
      (princ (strcat "\nLINGUTTER: erasing " (itoa (length kill))
                     " highlighted object" (lg:s (length kill)) " - "
                     (itoa nother)
                     " drawn object" (lg:s nother) " and "
                     (itoa (apply '+ (cons 0 (mapcar 'cdr dropped))))
                     " dimension"
                     (lg:s (apply '+ (cons 0 (mapcar 'cdr dropped))))
                     (if dropped ":" ".")))
      (foreach d dropped
        (princ (strcat "\n             " (itoa (cdr d)) " x " (car d))))
      (if (> nspared 0)
        (princ (strcat "\nLINGUTTER: " (itoa nspared) " object"
                       (lg:s nspared) " left alone on "
                       (lg:names (lg:keeplayers)) ".")))))
  (princ))

;;; -------------------- handing over to PADDLE --------------------------

;; Hand PERIM over as a pickfirst selection rather than letting PADDLE
;; hunt for it: PADDLE auto-detects the largest closed loop in the WHOLE
;; drawing, and LINGUTTER only ever gutted the highlighted area -- a
;; title block border still standing outside it is a bigger loop than
;; the pool.  Highlighted, PADDLE pads what we drew and asks nothing.
;;
;; PADDLE is its own file, so it may not be in this session.  When it is
;; not, the gut has still happened and saying so beats dying on an
;; undefined function.
(defun lg:paddle (perim / ss)
  (cond
    ((not lg:*runpaddle*)
     (princ "\nLINGUTTER: lg:*runpaddle* is nil - stopping before PADDLE."))
    (c:PADDLE
     (if perim
       (progn
         (setq ss (ssadd))
         (ssadd perim ss)
         (sssetfirst nil ss)))
     (princ "\nLINGUTTER: handing the new perimeter to PADDLE.")
     (c:PADDLE))
    (t
     (princ (strcat "\nLINGUTTER: PADDLE is not loaded, so no pads were"
                    " placed.  APPLOAD PADDLE.lsp (or the shared"
                    " LAZPASS.lsp build) and type PADDLE."))))
  (princ))

;;; -------------------- the commands ------------------------------------

(defun c:LINGUTTER ( / *error* undo-open ss keepcross res vts kill
                       locked en perim)

  ;; The user's settings come back FIRST so nothing below can skip them,
  ;; then the undo group is closed - or the next U would swallow the
  ;; user's own work along with this run - and any layer this command
  ;; unlocked is locked again.
  (defun *error* (m)
    (lg:sysrestore)
    (if locked (lg:relock locked))
    (if undo-open
      (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if (and m (not (wcmatch (strcase m)
                             "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLINGUTTER error: " m)))
    (if lzd:report (lzd:report "LINGUTTER" *lingutter-version* m))
    (princ))
  (if lzd:begin (lzd:begin "LINGUTTER" *lingutter-version*))

  (lg:syssave '("OSMODE" "CMDECHO" "CLAYER"))
  (princ (strcat "\nLINGUTTER " *lingutter-version*))

  (setq ss (lg:highlight))
  (if (null ss)
    (princ "\nLINGUTTER: nothing highlighted - nothing to gut.")
    (progn
      (setq keepcross (lg:askyn "Keep CROSS DIMENSIONS?" "Yes" nil)
            res       (lg:analyze ss keepcross)
            vts       (nth 0 res)
            kill      (nth 2 res))
      (lg:report res keepcross)))

  ;; no perimeter, nothing to erase: without one there is no telling
  ;; which of the highlighted lines was the pool
  (if vts
    (progn
      (setvar "CMDECHO" 0)
      (setvar "OSMODE" 0)
      ;; only when undo is recording - _Begin in a drawing with UNDO
      ;; off (bit 1 of UNDOCTL clear) errors out of the command
      (if (= 1 (logand 1 (getvar "UNDOCTL")))
        (progn
          (command "_.UNDO" "_Begin")
          (setq undo-open T)))
      ;; entdel refuses an entity on a locked layer, so open the ones
      ;; this erase has to reach and shut them again afterwards
      (setq locked (lg:unlock (lg:kill-layers kill)))
      (foreach en kill (if (entget en) (entdel en)))
      (setvar "CLAYER" (lg:ensure-layer lg:*poollayer* lg:*poolcolor*))
      (setq perim (lg:draw-perim vts lg:*poollayer*))
      (lg:relock locked)
      (setq locked nil)
      ;; closed only if one was opened: with undo control off there
      ;; is no group of this command's to end, and closing one it
      ;; never opened is an error out of the command -- the same
      ;; guard the handler above already makes
      (if undo-open
        (progn
          (command "_.UNDO" "_End")
          (setq undo-open nil)))
      (princ (strcat "\nLINGUTTER: " (itoa (length kill))
                     " highlighted object" (lg:s (length kill))
                     " erased; the perimeter is one closed polyline"
                     " on layer " lg:*poollayer*
                     ".  Nothing outside the highlight was touched."))
      ;; the sysvars go back BEFORE PADDLE runs: it is a command in its
      ;; own right and must start from the user's settings, not this
      ;; one's zeroed OSMODE
      (lg:sysrestore)
      (lg:paddle perim)))

  (lg:sysrestore)
  (if lzd:end (lzd:end "LINGUTTER"))
  (princ))

(defun c:LINGUTTERSCAN ( / *error* ss keepcross)
  (defun *error* (m)
    (if (and m (not (wcmatch (strcase m)
                             "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLINGUTTERSCAN error: " m)))
    (if lzd:report (lzd:report "LINGUTTERSCAN" *lingutter-version* m))
    (princ))
  (if lzd:begin (lzd:begin "LINGUTTERSCAN" *lingutter-version*))
  (princ (strcat "\nLINGUTTERSCAN " *lingutter-version*
                 " - reading only, nothing in the drawing is changed."))
  (setq ss (lg:highlight))
  (if (null ss)
    (princ "\nLINGUTTERSCAN: nothing highlighted - nothing to report on.")
    (progn
      (setq keepcross (lg:askyn "Keep CROSS DIMENSIONS?" "Yes" nil))
      (lg:report (lg:analyze ss keepcross) keepcross)
      (princ "\nLINGUTTERSCAN: nothing changed.  Type LINGUTTER to do it.")))
  (if lzd:end (lzd:end "LINGUTTERSCAN"))
  (princ))

(defun c:LINGUTTERVER ()
  (princ (strcat "\nLINGUTTER " *lingutter-version*))
  (princ))

;; Quiet inside the whole build: LAZPASS.lsp and
;; CALOFIN-LOADER.lsp set the flag while they load their members,
;; because one file's greeting is a greeting and sixty-three of
;; them is a wall the drafter scrolls past in every drawing they
;; open.  APPLOADed alone the flag is nil and this prints, which
;; is the one time somebody wants to be told.  CALVER reports the
;; whole roster whenever it is asked.
(if (not *calofin-quiet*)
  (princ (strcat "\nLINGUTTER " *lingutter-version*
                 " loaded -- highlight an area: its perimeter goes onto \""
                 lg:*poollayer* "\", the rest of it is erased, PADDLE runs."
                 "\nLINGUTTERSCAN reports what it would do and changes"
                 " nothing.")))
(princ)
