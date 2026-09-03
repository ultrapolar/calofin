;;; ======================================================================
;;; LISPLAB.lsp  --  two AutoLISP lessons: reading the drawing databases,
;;;                  and putting a list in order
;;; ----------------------------------------------------------------------
;;; For AutoCAD 2018 and later (plain AutoLISP, no external libraries).
;;;
;;; A teaching tool, not a drafting tool.  It answers two questions a
;;; new AutoLISP writer runs into on day one:
;;;
;;;   "How do I get at what is already in the drawing?"
;;;   "How do I put a list in the order I want?"
;;;
;;; Each lesson comes in two halves, and you pick which you want:
;;;
;;;   Checks - the written outline.  What each call is, what it gives
;;;            back, what it costs, and the trap that goes with it.
;;;   Demo   - the same thing running.  The database lesson draws a
;;;            sample, then reads it back out of the drawing with the
;;;            calls it just described; the sorting lesson sorts what
;;;            that read back, one algorithm at a time, printing the
;;;            list after every step so the order can be watched
;;;            forming.
;;;
;;; The two lessons are one story when you take Both: lesson 1 grabs
;;; the records, lesson 2 orders them, and the sorted order is drawn
;;; back into the drawing so it can be seen rather than read.
;;;
;;; Every sorting routine below is a real, working implementation --
;;; lab:bubble, lab:selection, lab:insertion, lab:msort, lab:qsort and
;;; lab:sort-by are all callable from your own code, and all take the
;;; comparator as an argument.  The whole run is one UNDO group and
;;; the demo drawing can be erased on the way out.
;;;
;;; Commands:  LISPLAB      run the lessons
;;;            LISPLABVER   print the loaded version
;;; ======================================================================

(setq *lisplab-version* "v1.2")   ; announced on load; release_lisp.py
                                  ; reads this banner and stamps the
                                  ; dated twin in releases/ from it

;;; -------------------- tunables ----------------------------------------
;;; setq these after loading to move the demo off the default layers.

(setq lab:*laya*   "LISPLAB-A")   ; sample circles, first layer
(setq lab:*layb*   "LISPLAB-B")   ; sample circles, second layer
(setq lab:*laytxt* "LISPLAB-NOTES")
(setq lab:*cola*   1)             ; red
(setq lab:*colb*   3)             ; green
(setq lab:*coltxt* 7)

;; The sample the demo draws.  Radii are multiples of the size unit the
;; demo asks for, and 3 appears TWICE on purpose: the duplicate is what
;; makes vl-sort's habit of dropping equal items visible in the demo
;; rather than in your production code.  The second field is the layer:
;; 0 = lab:*laya*, 1 = lab:*layb*.
(setq lab:*sample* '((6 0) (3 1) (9 0) (3 0) (12 1) (5 1) (8 0)))

;;; -------------------- helpers copied from the library -----------------
;;; Copies of the CALOFIN-LIB.lsp originals under this file's prefix, so
;;; the standalone file loads with nothing beside it.  Same bodies as
;;; cal:askkw / cal:pause / cal:ensure-layer / cal:nthcdr / cal:pad /
;;; cal:text / cal:syssave / cal:sysrestore -- see STANDARDS.md section 4.

;; Keyword question.  kws is the initget string, shown the bracketed
;; list, dflt the Enter answer (nil = an answer is required).  Returns
;; the keyword, or LAB-BACK for Back/Undo.
(defun lab:askkw (msg kws shown dflt back / v)
  (initget (if dflt 0 (if back 0 1))
           (if back (strcat kws " Back Undo") kws))
  (setq v (getkword (strcat "\n" msg " [" shown
                            (if back "/Back" "") "]"
                            (if dflt (strcat " <" dflt ">") "") ": ")))
  (cond ((member v '("Back" "Undo")) 'LAB-BACK)
        ((null v) (if dflt dflt (lab:askkw msg kws shown dflt back)))
        (t v)))

(defun lab:pause ()
  (getstring "\n--- press Enter to continue ---")
  (princ))

;; Create the output layer, or - when it already exists - make sure it
;; is on, thawed and unlocked.  Without this a successful run onto a
;; frozen or switched-off layer looks like the command did nothing.
(defun lab:ensure-layer (name color / rec ed flags col fixed)
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
          (princ (strcat "\nLISPLAB: layer " name
                         " was off, frozen or locked - restored so the"
                         " result is visible."))))))
  name)

;; the list from index K on
(defun lab:nthcdr (k lst)
  (while (> k 0) (setq lst (cdr lst) k (1- k)))
  lst)

;; pad S with spaces to width W
(defun lab:pad (s w)
  (while (< (strlen s) w) (setq s (strcat s " ")))
  s)

;; plain TEXT at pt
(defun lab:text (pt hgt str lay)
  (entmake
    (list '(0 . "TEXT") (cons 8 lay)
          (list 10 (car pt) (cadr pt) 0.0)
          (cons 40 hgt) (cons 1 str))))

;; The snapshot lives in a GLOBAL and is taken only when no snapshot is
;; already pending: if a previous run died before restoring, the stale
;; snapshot still holds the user's TRUE settings.  OSMODE first --
;; object snaps are the setting missed most if a run is cut short.
(defun lab:syssave (vars / v)
  (if (not lab:*sysold*)
      (foreach v vars
        (if (/= nil (getvar v))
            (setq lab:*sysold*
                  (append lab:*sysold* (list (cons v (getvar v)))))))))

(defun lab:sysrestore ( / p)
  (foreach p lab:*sysold* (setvar (car p) (cdr p)))
  (setq lab:*sysold* nil))

;;; -------------------- printing ----------------------------------------

;; Print a list of strings, one per line.
(defun lab:say (lines / s)
  (foreach s lines (princ (strcat "\n" s)))
  (princ))

;; A number without AutoLISP's trailing zeros: 12, not 12.000000.
(defun lab:num (x)
  (cond ((null x) "nil")
        ((= (type x) 'STR) x)
        ((= x (fix x)) (rtos x 2 0))
        (t (rtos x 2 2))))

;; "A/15  A/30 ..." -- records as layer-letter / radius pairs, short
;; enough to read on one command-line row.
(defun lab:fmt-recs (recs / s r lay)
  (setq s "")
  (foreach r recs
    (setq lay (lab:lay r))
    (setq s (strcat s (if (= s "") "" "  ")
                    (substr lay (strlen lay) 1)
                    "/" (lab:num (lab:rad r)))))
  s)

;; "(6 3 9 3 12 5 8)" -- a list of numbers or strings as one string.
(defun lab:fmt (lst / s x)
  (setq s "")
  (foreach x lst
    (setq s (strcat s (if (= s "") "" " ") (lab:num x))))
  (strcat "(" s ")"))

;;; ======================================================================
;;; LESSON 1 -- getting things out of the drawing
;;; ======================================================================

;;; -------------------- the notes ---------------------------------------

(defun lab:db-notes-1 ()
  (lab:say
    '("====================================================================="
      " LESSON 1 - GETTING THINGS OUT OF THE DRAWING"
      "====================================================================="
      "A drawing is not one database, it is several.  Knowing which one"
      "a thing lives in tells you which function fetches it:"
      ""
      "  graphical objects  lines, circles, text        entget, ssget"
      "  symbol tables      layers, linetypes, blocks   tblsearch, tblnext"
      "  dictionaries       layouts, groups, styles     dictsearch, dictnext"
      "  extended data      your own tags on an object  entget with an app"
      "  header variables   CLAYER, OSMODE, EXTMIN      getvar"
      ""
      "1. ONE OBJECT AT A TIME - entsel and entget"
      "   (entsel \"\\nSelect a circle: \")  ->  (<Entity name> (x y z))"
      "   (car (entsel))                 ->  just the entity name"
      "   (entget ename)                 ->  the DXF association list"
      ""
      "   That list is dotted pairs, (group-code . value).  The codes"
      "   worth knowing by heart:"
      "      0  entity type \"CIRCLE\"      8  layer name"
      "     10  centre / start point     11  end point"
      "     40  radius, text height      50  rotation, in RADIANS"
      "      1  text string              62  colour (absent = ByLayer)"
      "      5  handle                    2  block or table name"
      "   Pull one out with assoc, and remember the cdr:"
      "     (cdr (assoc 8  ed))  ->  \"POOL\"   the layer"
      "     (cdr (assoc 40 ed))  ->  12.5     the radius"
      ""
      "   An ename is good for THIS session only.  The handle, group 5,"
      "   survives a save; (handent \"2A7\") turns one back into an ename."
      ""
      "   TRAP: assoc finds only the FIRST pair with that code.  A"
      "   polyline carries one (10 . pt) per vertex, so assoc hands you"
      "   vertex 1 and nothing else - walk the list yourself for the rest."
      "   TRAP: entget hands you a COPY.  Editing the list changes"
      "   nothing in the drawing until you hand it back with entmod."
      ""
      "2. THE WHOLE DATABASE, IN ORDER - entnext"
      "   (entnext)     ->  the first object in the drawing"
      "   (entnext e)   ->  the one after e, nil when there is no more"
      "   (entlast)     ->  the newest object - the one you just drew"
      "   Walking to nil visits every graphical object with no selection"
      "   set at all.  (entnext e) on a polyline or a block insert walks"
      "   INTO it - vertices, attributes - and past the SEQEND comes"
      "   back out, which is how you read attribute values."
      ""
      "3. MANY AT ONCE, FILTERED - ssget"
      "   ssget is the fast one: AutoCAD does the filtering, not your"
      "   loop.  Mode strings start with _ so they work in any language."
      "     (ssget \"_X\" '((0 . \"CIRCLE\")))    every circle in the drawing"
      "     (ssget \"_X\" '((8 . \"POOL\")))      everything on layer POOL"
      "     (ssget \"_X\" '((0 . \"CIRCLE\") (8 . \"POOL\")))   both: AND"
      "     (ssget \"_I\")     what was already picked before the command"
      "     (ssget)          ask the user    (ssget \"_P\")  previous set"
      "     (ssget \"_W\" p1 p2)  window      (ssget \"_C\" p1 p2) crossing"
      "     (ssget \"_F\" ptlist) fence       (ssget \"_L\")  last drawn"
      "   Wildcards work in a string field:  '((8 . \"POOL*,DIM*\"))"
      "   OR instead of AND, with the -4 operator pairs:"
      "     '((-4 . \"<OR\") (0 . \"CIRCLE\") (0 . \"ARC\") (-4 . \"OR>\"))"
      "   Walk it BACKWARDS, so deleting as you go cannot shift the"
      "   index out from under you:"
      "     (setq i (sslength ss))"
      "     (while (> (setq i (1- i)) -1) (setq e (ssname ss i)) ... )"
      ""
      "   TRAP: no match gives nil, NOT an empty set - and (sslength"
      "   nil) is an error.  Always test the set before you use it."
      "   TRAP: \"_X\" ignores which space you are in.  Add '((410 ."
      "   \"Model\")) when paper-space copies would spoil the count.")))

(defun lab:db-notes-2 ()
  (lab:say
    '("4. NAMED THINGS - the symbol tables"
      "   (tblsearch \"LAYER\" \"POOL\")  ->  the record, or nil"
      "   (tblnext \"LAYER\" T)        ->  first record (T rewinds)"
      "   (tblnext \"LAYER\")          ->  next, nil at the end"
      "   (tblobjname \"LAYER\" \"POOL\") -> its ENAME, so entget and"
      "                                 entmod can edit it; the list"
      "                                 tblsearch returns cannot be."
      "   Tables: LAYER LTYPE STYLE DIMSTYLE BLOCK UCS VIEW VPORT APPID"
      ""
      "   \"Does this layer exist?\" is the check every drawing routine"
      "   owes the user before it draws.  lab:ensure-layer in this file"
      "   is the full version: it creates the layer, and when the layer"
      "   is already there but frozen, locked or switched off it thaws"
      "   it and says so - otherwise a successful run looks like the"
      "   command did nothing at all."
      ""
      "5. DICTIONARIES - where everything newer lives"
      "   (namedobjdict)                             the root dictionary"
      "   (dictsearch (namedobjdict) \"ACAD_LAYOUT\")   the layouts"
      "   (dictnext ...)  walk it   (dictadd ...) / (dictremove ...)"
      "   Groups, layouts, layer states, multileader and table styles"
      "   live here, and so does anything of your own you store as an"
      "   XRECORD.  This is the place for data belonging to the DRAWING"
      "   rather than to one object."
      ""
      "6. EXTENDED DATA - your tag riding on someone else's object"
      "   (regapp \"CALOFIN\")            once per drawing"
      "   (entget e '(\"CALOFIN\"))       now the list carries a -3 group"
      "   Attach it by entmod-ing a pair shaped like"
      "     (-3 (\"CALOFIN\" (1000 . \"step 3\") (1040 . 12.5)))"
      "   1000 string, 1040 real, 1070 integer, 1010 point.  The check"
      "   tools in this repo use xdata to remember which entities they"
      "   have already looked at."
      ""
      "7. HEADER VARIABLES, AND ACTIVEX WHEN DXF GETS PAINFUL"
      "   (getvar \"CLAYER\")  (getvar \"OSMODE\")  (getvar \"EXTMIN\")"
      "   Save what you change and put it back - lab:syssave and"
      "   lab:sysrestore in this file are the pattern the whole repo"
      "   uses, and they restore OSMODE first because that is the"
      "   setting a user misses most when a run is cut short."
      ""
      "   (vl-load-com) once at the top of the file, then:"
      "     (vlax-ename->vla-object e)   (vla-get-Area obj)"
      "     (vlax-curve-getPointAtDist e d)   works on an ename direct"
      "     (vlax-curve-getClosestPointTo e p)"
      "   ActiveX reads properties DXF would make you compute - area,"
      "   length, closed - but each call costs more than an entget, so"
      "   a loop over a thousand objects is still faster in DXF."
      ""
      "   Both are read-only until you write: entmod + entupd for DXF,"
      "   (vla-put-Radius obj 12.5) for ActiveX.")))

;;; -------------------- the calls, for real -----------------------------

;; One DXF group value off an entity list.  Every "read a property"
;; line in the repo is this, written out: (cdr (assoc <code> ed)).
(defun lab:dxf (code ed)
  (cdr (assoc code ed)))

;; Every graphical object created after MARK, in database order.  MARK
;; nil means from the front of the drawing.  Note the guard: (entnext)
;; with NO argument is "the first object", while (entnext nil) is an
;; error - they are not the same call.
(defun lab:walk-since (mark / e out)
  (setq e   (if mark (entnext mark) (entnext))
        out nil)
  (while e
    (setq out (cons e out)
          e   (entnext e)))
  (reverse out))

;; Every graphical object in the drawing, with no selection set
;; involved: entnext from the front until it returns nil.
(defun lab:walk-db ( / )
  (lab:walk-since nil))

;; The members of ENTS that sit on layer LAY - the by-hand version of
;; what ssget's '((8 . "LAY")) filter does inside AutoCAD.
(defun lab:on-layer (ents lay / out e)
  (setq out nil)
  (foreach e ents
    (if (= lay (lab:dxf 8 (entget e)))
      (setq out (cons e out))))
  (reverse out))

;; One record per CIRCLE in ENTS: (radius layer x y).  Nothing here
;; knows what was drawn - it all comes back out of the database.
(defun lab:records (ents / out ed ctr e)
  (setq out nil)
  (foreach e ents
    (setq ed (entget e))
    (if (= "CIRCLE" (lab:dxf 0 ed))
      (progn
        (setq ctr (lab:dxf 10 ed))
        (setq out (cons (list (lab:dxf 40 ed) (lab:dxf 8 ed)
                              (car ctr) (cadr ctr))
                        out)))))
  (reverse out))

;; Named accessors beat car/cadr/caddr scattered through the code: when
;; the record grows a fifth field, only these four lines change.
(defun lab:rad (r) (car r))
(defun lab:lay (r) (cadr r))
(defun lab:cx  (r) (caddr r))
(defun lab:cy  (r) (cadddr r))

;;; ======================================================================
;;; LESSON 2 -- putting a list in order
;;; ======================================================================

;;; -------------------- the notes ---------------------------------------

(defun lab:sort-notes-1 ()
  (lab:say
    '("====================================================================="
      " LESSON 2 - PUTTING A LIST IN ORDER"
      "====================================================================="
      "Every sort needs two things: the list, and a rule for \"does a"
      "come before b\".  That rule is a FUNCTION of two items - a"
      "comparator - and keeping it out of the algorithm is what lets one"
      "sort handle numbers, strings, points and records alike."
      ""
      "  '<          numbers, and strings too: \"A\" comes before \"B\""
      "  '>          the same order, backwards"
      "  (function (lambda (a b) (< (car a) (car b))))   by first field"
      ""
      "  (apply less (list a b))   <- how a routine CALLS a comparator"
      "                               it was handed."
      ""
      "  NOT (less a b).  AutoLISP looks a name in head position up as a"
      "  FUNCTION, and here less is a variable holding one, so (less a b)"
      "  dies with \"no function definition: LESS\".  Everybody writes it"
      "  the wrong way once.  apply, or (eval (list less a b))."
      ""
      "0. THE ONE YOU SHOULD ACTUALLY SHIP - vl-sort"
      "   (vl-sort '(6 3 9 3 12 5 8) '<)   ->   (3 5 6 8 9 12)"
      "   Built in and compiled: fine for anything you will meet in a"
      "   drawing.  Write your own to learn, or when you need something"
      "   vl-sort will not do."
      ""
      "   TRAP, and it is a big one: vl-sort DROPS DUPLICATES.  Seven"
      "   items went in above and six came out, because the two 3s"
      "   compared equal in both directions.  Two ways round it:"
      "     (vl-sort-i lst '<)   the INDEXES in sorted order, nothing"
      "                          lost - then nth them back out"
      "     sort RECORDS, not bare numbers: two circles with the same"
      "     radius still differ somewhere, so neither compares equal"
      "   The demo runs into this on purpose so you see it happen."
      ""
      "1. BUBBLE SORT - n^2, the one everybody is taught first"
      "   Compare each item with its neighbour, swap the pair when it is"
      "   the wrong way round, and repeat the whole pass until a pass"
      "   changes nothing.  Easiest to picture, slowest to run.  Its one"
      "   real virtue: it stops after a single pass on a list that is"
      "   already in order."
      "     lab:bubble-pass   one left-to-right pass"
      "     lab:bubble        passes until nothing moves"
      ""
      "2. SELECTION SORT - n^2, but the fewest MOVES"
      "   Find the smallest item, pull it to the front, repeat on what"
      "   is left.  Always n^2 comparisons, ordered input or not - but"
      "   it moves each item exactly once, which mattered when a move"
      "   was the expensive part."
      "     lab:select-min    the smallest item in a list"
      "     lab:remove1       drop the FIRST match only.  vl-remove"
      "                       drops EVERY match and would quietly lose"
      "                       your duplicates."
      ""
      "3. INSERTION SORT - n^2 worst, n best, and one line of Lisp"
      "   Take items one at a time and slot each into an already-sorted"
      "   list.  On a nearly-ordered list - objects read back roughly in"
      "   the order they were drawn - this beats the other two easily."
      "     lab:insert     put one item into a sorted list"
      "     lab:insertion  fold lab:insert over the input"
      "   It is also the way to KEEP a list sorted as it grows, instead"
      "   of sorting it again after every addition.")))

(defun lab:sort-notes-2 ()
  (lab:say
    '("4. MERGE SORT - n log n, STABLE, and it never degrades"
      "   Split the list in half, sort each half, then merge the two"
      "   sorted halves by repeatedly taking the smaller head.  n log n"
      "   whatever the input looks like - no bad case."
      "     lab:halve   front half / back half"
      "     lab:merge   two sorted lists into one"
      "     lab:msort   the recursion"
      ""
      "   STABLE means items that compare equal come out in the order"
      "   they went in.  lab:merge is stable because it takes from the"
      "   LEFT half on a tie.  That one line is what lets you sort by"
      "   radius, then sort THAT by layer, and finish with layers in"
      "   order and radii in order inside each layer."
      ""
      "5. QUICKSORT - n log n on average, n^2 when you are unlucky"
      "   Take the first item as the pivot, split the rest into \"before"
      "   the pivot\" and \"not before\", sort each side, glue them back"
      "   with the pivot in the middle.  Shorter than merge sort and"
      "   usually quicker."
      "     lab:qsort"
      "   Hand it a list that is ALREADY sorted and the first item is"
      "   the worst possible pivot: every split is one-and-the-rest and"
      "   you are back to n^2.  Real quicksorts take the pivot from the"
      "   middle, or at random, for exactly this reason."
      ""
      "6. SORTING BY A KEY YOU HAVE TO WORK OUT"
      "   Sorting circles by area means computing the area inside the"
      "   comparator - and a comparator runs about 2 n log n times, not"
      "   n.  Work the key out ONCE per item, sort the (key . item)"
      "   pairs, then throw the keys away:"
      "     (lab:sort-by lst keyfn less)"
      "   The old name for the trick is decorate - sort - undecorate."
      ""
      "   Read lab:sort-by in this file before you write your own.  It"
      "   parks the comparator in lab-keycmp instead of using less"
      "   directly, and that is not tidiness.  AutoLISP has no closures"
      "   and its scoping is DYNAMIC: a lambda sees the variables of"
      "   whoever CALLS it, not of whoever wrote it.  That lambda runs"
      "   inside lab:merge, whose own argument is also called less - so"
      "   (apply less ...) inside it would find merge's less, which is"
      "   the lambda itself, and recurse until it died.  Give anything"
      "   a lambda has to carry a name nothing else uses."
      ""
      "7. TWO KEYS AT ONCE"
      "   Either build the tie-break into the comparator ..."
      "     (cond ((/= (lab:lay p) (lab:lay q))"
      "            (< (lab:lay p) (lab:lay q)))"
      "           (t (< (lab:rad p) (lab:rad q))))"
      "   ... or, with a STABLE sort, sort by the LAST key first and"
      "   work forward: sort by radius, then sort THAT by layer.  Both"
      "   are in the demo, and both give the same answer."
      ""
      "8. WHICH ONE DO I USE?"
      "   vl-sort, unless it drops duplicates you need - then vl-sort-i,"
      "   or sort records.  Write one of the above when you want the"
      "   comparator to do something vl-sort cannot, when you want the"
      "   sort to stay stable and want to be sure of it, or when you are"
      "   learning - which is what this file is for.")))

;;; -------------------- the algorithms ----------------------------------
;;; All six take the comparator LESS as an argument and call it with
;;; apply.  All six leave the input list alone and return a new one.

;; One left-to-right pass: every pair that is out of order is swapped.
;; Bubble sort is nothing but this, repeated.
(defun lab:bubble-pass (lst less / a b)
  (cond
    ((or (null lst) (null (cdr lst))) lst)
    (t
     (setq a (car lst) b (cadr lst))
     (if (apply less (list b a))
       (cons b (lab:bubble-pass (cons a (cddr lst)) less))
       (cons a (lab:bubble-pass (cdr lst) less))))))

;; Pass until a pass changes nothing.  That is also the early exit: an
;; already-sorted list costs one pass and stops.
(defun lab:bubble (lst less / prev)
  (while (not (equal lst prev))
    (setq prev lst
          lst  (lab:bubble-pass lst less)))
  lst)

;; The smallest item in LST, by LESS.
(defun lab:select-min (lst less / best x)
  (setq best (car lst))
  (foreach x (cdr lst)
    (if (apply less (list x best)) (setq best x)))
  best)

;; LST without the FIRST item equal to X.  vl-remove would take every
;; match, which is how a selection sort quietly loses duplicates.
(defun lab:remove1 (x lst / out done v)
  (setq out nil done nil)
  (foreach v lst
    (if (and (not done) (equal v x))
      (setq done T)
      (setq out (cons v out))))
  (reverse out))

;; Pull the smallest to the front, repeat on the rest.
(defun lab:selection (lst less / best out)
  (setq out nil)
  (while lst
    (setq best (lab:select-min lst less)
          lst  (lab:remove1 best lst)
          out  (cons best out)))
  (reverse out))

;; Put X into the already-sorted list SORTED.  X goes AFTER anything it
;; ties with, which is what makes insertion sort stable.
(defun lab:insert (x sorted less)
  (cond
    ((null sorted) (list x))
    ((apply less (list x (car sorted))) (cons x sorted))
    (t (cons (car sorted) (lab:insert x (cdr sorted) less)))))

;; Insertion sort is lab:insert folded over the input.
(defun lab:insertion (lst less / out x)
  (setq out nil)
  (foreach x lst (setq out (lab:insert x out less)))
  out)

;; Front half and back half, as (left right).  A front/back split -
;; not an alternating one - is what keeps merge sort stable.
(defun lab:halve (lst / n i l)
  (setq n (fix (/ (float (length lst)) 2.0))
        i 0
        l nil)
  (while (< i n)
    (setq l (cons (nth i lst) l)
          i (1+ i)))
  (list (reverse l) (lab:nthcdr n lst)))

;; Two sorted lists into one.  Taking from A whenever the heads tie is
;; the whole of merge sort's stability.
(defun lab:merge (a b less)
  (cond
    ((null a) b)
    ((null b) a)
    ((apply less (list (car b) (car a)))
     (cons (car b) (lab:merge a (cdr b) less)))
    (t (cons (car a) (lab:merge (cdr a) b less)))))

;; Split, sort each half, merge.  n log n on any input.
(defun lab:msort (lst less / h)
  (if (or (null lst) (null (cdr lst)))
    lst
    (progn
      (setq h (lab:halve lst))
      (lab:merge (lab:msort (car h) less)
                 (lab:msort (cadr h) less)
                 less))))

;; Pivot on the first item, split the rest, sort each side, glue.  The
;; reverses keep each side in its original relative order, so this list
;; quicksort is stable - the in-place array version is not.
(defun lab:qsort (lst less / p lo hi x)
  (if (or (null lst) (null (cdr lst)))
    lst
    (progn
      (setq p (car lst) lo nil hi nil)
      (foreach x (cdr lst)
        (if (apply less (list x p))
          (setq lo (cons x lo))
          (setq hi (cons x hi))))
      (append (lab:qsort (reverse lo) less)
              (list p)
              (lab:qsort (reverse hi) less)))))

;; Decorate - sort - undecorate.  KEYFN runs once per item instead of
;; twice per comparison; LESS then compares the keys, not the items.
(defun lab:sort-by (lst keyfn less / tagged lab-keycmp)
  ;; lab-keycmp is not tidiness.  AutoLISP has no closures and its
  ;; scoping is DYNAMIC: the lambda below is not run here, it is run
  ;; deep inside lab:merge - whose own argument is ALSO called less.
  ;; A lambda saying (apply less ...) would therefore pick up merge's
  ;; less, which is the lambda itself, and recurse until it died.
  ;; Parking the comparator under a name nothing else uses is how you
  ;; hand a value to a lambda in a language without closures.
  (setq lab-keycmp less)
  (setq tagged (mapcar '(lambda (x) (cons (apply keyfn (list x)) x)) lst))
  (mapcar 'cdr
          (lab:msort tagged
                     (function (lambda (a b)
                                 (apply lab-keycmp
                                        (list (car a) (car b))))))))

;;; -------------------- comparators used by the demo --------------------

(defun lab:by-radius (p q)
  (< (lab:rad p) (lab:rad q)))

;; Two keys in one comparator: layer first, radius inside a layer.
(defun lab:by-layer-then-radius (p q)
  (cond ((/= (lab:lay p) (lab:lay q)) (< (lab:lay p) (lab:lay q)))
        (t (< (lab:rad p) (lab:rad q)))))

;;; ======================================================================
;;; The demo drawing
;;; ======================================================================

(defun lab:circle (ctr r lay)
  (entmake (list '(0 . "CIRCLE") (cons 8 lay)
                 (list 10 (car ctr) (cadr ctr) 0.0)
                 (cons 40 r))))

;; Draw the sample: one circle per entry of lab:*sample*, left to
;; right, each labelled with its radius.  Returns the row's width.
(defun lab:draw-sample (base u / step rmax i ent lay r ctr)
  (setq rmax (* u 12.0)
        step (* rmax 2.2)
        i    0)
  (foreach ent lab:*sample*
    (setq r   (* u (float (car ent)))
          lay (if (= 0 (cadr ent)) lab:*laya* lab:*layb*)
          ctr (list (+ (car base) (* step (+ i 0.5)))
                    (cadr base)))
    (lab:circle ctr r lay)
    (lab:text (list (- (car ctr) u) (- (cadr base) (* 1.4 rmax)))
              u (lab:num r) lab:*laytxt*)
    (setq i (1+ i)))
  (* step (float (length lab:*sample*))))

;; Draw a row of records in the order they are given, so a sorted list
;; can be looked at rather than read.
(defun lab:draw-row (recs base u label / step rmax i ctr r)
  (setq rmax (* u 12.0)
        step (* rmax 2.2)
        i    0)
  (lab:text (list (car base) (+ (cadr base) (* 1.4 rmax)))
            (* u 1.6) label lab:*laytxt*)
  (foreach r recs
    (setq ctr (list (+ (car base) (* step (+ i 0.5))) (cadr base)))
    (lab:circle ctr (lab:rad r) (lab:lay r))
    (lab:text (list (- (car ctr) u) (- (cadr base) (* 1.4 rmax)))
              u (lab:num (lab:rad r)) lab:*laytxt*)
    (setq i (1+ i))))

;; Find the demo again the way lesson 1 finds anything: walk the
;; database and keep what is on the demo's own layers.
(defun lab:erase-demo ( / n e lay)
  (setq n 0)
  (foreach e (lab:walk-db)
    (setq lay (lab:dxf 8 (entget e)))
    (if (member lay (list lab:*laya* lab:*layb* lab:*laytxt*))
      (progn (entdel e) (setq n (1+ n)))))
  n)

;;; -------------------- lesson 1, running -------------------------------

;; Draw the sample and read it straight back out of the drawing.
;; Returns the records, so lesson 2 has something real to sort.
(defun lab:db-demo (base u / mark all mine ss recs r)
  (lab:ensure-layer lab:*laya*   lab:*cola*)
  (lab:ensure-layer lab:*layb*   lab:*colb*)
  (lab:ensure-layer lab:*laytxt* lab:*coltxt*)

  ;; (entlast) BEFORE drawing anything is the mark that answers
  ;; "which of these did I just make?" - nil in an empty drawing.
  (setq mark (entlast))
  (lab:draw-sample base u)
  (lab:say (list
    "---------------------------------------------------------------------"
    " DEMO 1 - the sample is drawn.  Now we read it back."
    "---------------------------------------------------------------------"
    (strcat "Drawn: " (itoa (length lab:*sample*))
            " circles on layers " lab:*laya* " and " lab:*layb* ",")
    "each with its radius written under it.  Nothing below remembers"
    "what was drawn - every number comes back out of the database."
    ""
    "(a) entnext from the front, to nil - every object in the drawing:"
    "      (setq e (entnext))"
    "      (while e (setq e (entnext e)))"))
  (setq all  (lab:walk-db)
        mine (lab:walk-since mark))
  (lab:say (list
    (strcat "    -> " (itoa (length all)) " objects in the drawing")
    ""
    "    ... and to pick out just the ones YOU drew, remember"
    "    (entlast) before you start and walk on from there:"
    "      (setq mark (entlast))   ; before"
    "      (entnext mark)          ; the first one you made"
    (strcat "    -> " (itoa (length mine)) " drawn by this demo")))
  (lab:pause)

  (setq mine (lab:on-layer (lab:walk-since mark) lab:*laya*))
  (lab:say (list
    ""
    "(b) keeping the ones on one layer, by hand:"
    (strcat "      (= \"" lab:*laya* "\" (cdr (assoc 8 (entget e))))")
    (strcat "    -> " (itoa (length mine)) " on " lab:*laya*)
    ""
    "(c) the same grab, done by AutoCAD instead of by your loop:"
    (strcat "      (ssget \"_X\" '((0 . \"CIRCLE\") (8 . \"" lab:*laya*
            "\")))")))
  (setq ss (ssget "_X" (list '(0 . "CIRCLE") (cons 8 lab:*laya*))))
  (lab:say (list (strcat "    -> "
                         (if ss (itoa (sslength ss)) "0")
                         " circles"
                         (if ss "" "  (nil, remember - not an empty set)"))))
  (lab:pause)

  (setq recs (lab:records (lab:walk-since mark)))
  (lab:say (list
    ""
    "(d) one record per circle: (radius layer x y), pulled out with"
    "    assoc.  This is the list lesson 2 sorts."
    ""
    (strcat "    " (lab:pad "radius" 10) (lab:pad "layer" 16)
            (lab:pad "centre x" 12) "centre y")
    "    --------------------------------------------------"))
  (foreach r recs
    (lab:say (list (strcat "    "
                           (lab:pad (lab:num (lab:rad r)) 10)
                           (lab:pad (lab:lay r) 16)
                           (lab:pad (lab:num (lab:cx r)) 12)
                           (lab:num (lab:cy r))))))
  (lab:say (list
    ""
    "    Note the order: it is the order the objects were CREATED in,"
    "    which is the order entnext hands them over.  A drawing gives"
    "    you no order but that one - which is the whole of lesson 2."
    ""
    "(e) the non-graphical database, and the header:"
    (strcat "      (tblsearch \"LAYER\" \"" lab:*laya* "\")  ->  "
            (if (tblsearch "LAYER" lab:*laya*) "found" "nil"))
    (strcat "      (getvar \"CLAYER\")  ->  \"" (getvar "CLAYER") "\"")))
  recs)

;;; -------------------- lesson 2, running -------------------------------

;; The bare numbers the sorting demo starts on, before it graduates to
;; the records lesson 1 read out of the drawing.
(defun lab:demo-numbers ( / out x)
  (setq out nil)
  (foreach x lab:*sample* (setq out (cons (float (car x)) out)))
  (reverse out))

(defun lab:sort-demo-1 (nums / sorted prev pass)
  (lab:say (list
    "---------------------------------------------------------------------"
    " DEMO 2 - the same seven numbers, sorted six ways"
    "---------------------------------------------------------------------"
    (strcat "  start:  " (lab:fmt nums))
    ""
    "(0) vl-sort - the built-in, and the duplicate trap:"
    (strcat "      (vl-sort lst '<)  ->  " (lab:fmt (vl-sort nums '<)))))
  (setq sorted (vl-sort nums '<))
  (lab:say (list
    (strcat "    " (itoa (length nums)) " in, " (itoa (length sorted))
            " out"
            (if (< (length sorted) (length nums))
              " - there is the dropped duplicate."
              "."))
    (strcat "      (vl-sort-i lst '<) keeps them: "
            (lab:fmt (vl-sort-i nums '<)))
    "    ... those are INDEXES; nth them back out of the original."))
  (lab:pause)

  (lab:say (list
    ""
    "(1) bubble sort - one pass at a time, until a pass changes nothing:"))
  (setq sorted nums prev nil pass 0)
  (while (not (equal sorted prev))
    (setq prev   sorted
          sorted (lab:bubble-pass sorted '<)
          pass   (1+ pass))
    (lab:say (list (strcat "      pass " (itoa pass) ":  "
                           (lab:fmt sorted)))))
  (lab:say (list
    (strcat "    " (itoa pass) " passes, and the last one only proved"
            " nothing was left to do.")
    (strcat "    (lab:bubble lst '<)  ->  " (lab:fmt (lab:bubble nums '<)))))
  (lab:pause)
  sorted)

(defun lab:sort-demo-2 (nums / rest out best)
  (lab:say (list
    ""
    "(2) selection sort - pull the smallest out, over and over:"))
  (setq rest nums out nil)
  (while rest
    (setq best (lab:select-min rest '<)
          rest (lab:remove1 best rest)
          out  (append out (list best)))
    (lab:say (list (strcat "      took " (lab:num best) ":  "
                           (lab:fmt out) "  left " (lab:fmt rest)))))
  (lab:say (list
    "    Both 3s survived, because lab:remove1 takes the first match"
    "    only.  vl-remove would have taken both and the list would"
    "    have come out an item short."
    (strcat "      (lab:selection lst '<)  ->  "
            (lab:fmt (lab:selection nums '<)))))
  (lab:pause)

  (lab:say (list
    ""
    "(3) insertion sort - slot each item into an already-sorted list:"))
  (setq out nil)
  (foreach best nums
    (setq out (lab:insert best out '<))
    (lab:say (list (strcat "      +" (lab:pad (lab:num best) 4) " -> "
                           (lab:fmt out)))))
  (lab:say (list
    "    Each line is one call to lab:insert.  Feed it a list that is"
    "    nearly in order already and it barely moves anything - which"
    "    is why it is the fastest of the three on real drawing data."
    (strcat "      (lab:insertion lst '<)  ->  "
            (lab:fmt (lab:insertion nums '<)))))
  (lab:pause)
  out)

(defun lab:sort-demo-3 (nums / h)
  (lab:say (list
    ""
    "(4) merge sort - halve, sort each half, merge the two:"))
  (setq h (lab:halve nums))
  (lab:say (list
    (strcat "      halve:  " (lab:fmt (car h)) "  +  " (lab:fmt (cadr h)))
    (strcat "      each sorted:  " (lab:fmt (lab:msort (car h) '<))
            "  +  " (lab:fmt (lab:msort (cadr h) '<)))
    (strcat "      merged:  "
            (lab:fmt (lab:merge (lab:msort (car h) '<)
                                (lab:msort (cadr h) '<) '<)))
    "    ... and each half got there the same way, one level down."
    "    Both 3s are still here: a merge sort never drops anything."))
  (lab:pause)

  (lab:say (list
    ""
    "(5) quicksort - pivot on the first item, split, sort, glue:"
    (strcat "      pivot:  " (lab:num (car nums)))
    (strcat "      before it:  "
            (lab:fmt (lab:qsort-side nums '< T))
            "   not before:  "
            (lab:fmt (lab:qsort-side nums '< nil)))
    (strcat "      result:  " (lab:fmt (lab:qsort nums '<)))
    "    Hand quicksort a list that is already sorted and that first"
    "    item is the worst pivot there is: every split becomes one"
    "    item and the rest, and n log n turns back into n^2."))
  (lab:pause)
  (lab:msort nums '<))

;; The two sides of one quicksort partition, so the demo can show them
;; without re-implementing the split.  BEFORE T gives the low side.
(defun lab:qsort-side (lst less before / p out x)
  (setq p (car lst) out nil)
  (foreach x (cdr lst)
    (if (equal before (if (apply less (list x p)) T nil))
      (setq out (cons x out))))
  (reverse out))

(defun lab:sort-demo-4 (recs base u / byrad bylay bytwo)
  (lab:say (list
    ""
    "(6) sorting records by a key, and by two keys"
    "---------------------------------------------------------------------"))
  (if (null recs)
    (lab:say (list
      "    (the database demo was not run, so there are no records to"
      "     sort here - run LISPLAB again and take Both to see it)"))
    (progn
      (setq byrad (lab:sort-by recs 'lab:rad '<))
      (lab:say (list
        "    by radius, with lab:sort-by - the key worked out once per"
        "    record instead of twice per comparison:"
        (strcat "      (lab:sort-by recs 'lab:rad '<)")
        (strcat "      -> " (lab:fmt (mapcar 'lab:rad byrad)))))
      (setq bytwo (lab:msort recs 'lab:by-layer-then-radius))
      (lab:say (list
        ""
        "    by layer, then radius inside each layer - one comparator"
        "    with the tie-break built in (layer by its last letter):"
        (strcat "      -> " (lab:fmt-recs bytwo))))
      (setq bylay (lab:msort (lab:msort recs 'lab:by-radius)
                             (function (lambda (p q)
                                         (< (lab:lay p) (lab:lay q))))))
      (lab:say (list
        ""
        "    the same answer the other way: sort by the LAST key first,"
        "    then by the first.  It only works because lab:msort is"
        "    STABLE - an unstable sort would scramble the radii again."
        (strcat "      -> " (lab:fmt-recs bylay))
        (strcat "      same as the one-comparator answer? "
                (if (equal bylay bytwo) "yes" "NO"))))
      (if base
        (progn
          (lab:draw-row byrad
                        (list (car base) (- (cadr base) (* u 31.0))) u
                        "sorted by radius")
          (lab:draw-row bytwo
                        (list (car base) (- (cadr base) (* u 62.0))) u
                        "sorted by layer, then radius")
          (lab:say (list
            ""
            "    Both orders are drawn under the sample, so the sort can"
            "    be looked at instead of read.")))))))

;;; ======================================================================
;;; The command
;;; ======================================================================

(defun c:LISPLAB (/ *error* undo-open lesson mode base u recs nums drew n)

  (defun *error* (msg)
    ;; user settings come back FIRST so nothing below can skip them
    (lab:sysrestore)
    (if undo-open (vl-catch-all-apply 'command-s (list "_.UNDO" "_End")))
    (if (and msg (not (wcmatch (strcase msg)
                               "*BREAK*,*CANCEL*,*QUIT*,*EXIT*")))
      (princ (strcat "\nLISPLAB error: " msg)))
    (princ))

  (lab:syssave '("OSMODE" "CMDECHO" "CLAYER"))
  (setvar "CMDECHO" 0)
  ;; only when undo is recording - _Begin in a drawing with UNDO
  ;; off (bit 1 of UNDOCTL clear) errors out of the command
  (if (= 1 (logand 1 (getvar "UNDOCTL")))
    (progn
      (command "_.UNDO" "_Begin")
      (setq undo-open T)))
  (setq 
        drew      nil)

  (lab:say (list
    "====================================================================="
    (strcat " LISPLAB " *lisplab-version*
            " - two AutoLISP lessons, outline and worked example")
    "====================================================================="
    "  Database - how to get at what is already in the drawing:"
    "             entsel, entget, entnext, ssget, the symbol tables,"
    "             dictionaries, xdata, getvar, and where ActiveX helps"
    "  Sorting  - how to put a list in the order you want: vl-sort and"
    "             its duplicate trap, then bubble, selection, insertion,"
    "             merge and quick sort written out, plus sorting by a"
    "             computed key and by two keys at once"))

  (setq lesson (lab:askkw "Which lesson?" "Database Sorting Both"
                          "Database/Sorting/Both" "Both" nil))
  (setq mode (lab:askkw
               (strcat "Checks prints the outline, Demo runs it."
                       "  Which?")
               "Checks Demo Both" "Checks/Demo/Both" "Both" nil))

  ;; ---- lesson 1 ------------------------------------------------------
  (if (member lesson '("Database" "Both"))
    (progn
      (if (member mode '("Checks" "Both"))
        (progn (lab:db-notes-1) (lab:pause)
               (lab:db-notes-2) (lab:pause)))
      (if (member mode '("Demo" "Both"))
        (progn
          (setq base (getpoint (strcat "\nPick a clear spot for the demo"
                                       " (about 1000 x 500 needed)"
                                       " <0,0>: ")))
          (if (null base) (setq base '(0.0 0.0 0.0)))
          (initget 6)
          (setq u (getdist base "\nDemo size unit <5.0>: "))
          (if (null u) (setq u 5.0))
          (setq recs (lab:db-demo base u)
                drew T)
          (lab:pause)))))

  ;; ---- lesson 2 ------------------------------------------------------
  (if (member lesson '("Sorting" "Both"))
    (progn
      (if (member mode '("Checks" "Both"))
        (progn (lab:sort-notes-1) (lab:pause)
               (lab:sort-notes-2) (lab:pause)))
      (if (member mode '("Demo" "Both"))
        (progn
          (setq nums (lab:demo-numbers))
          (lab:sort-demo-1 nums)
          (lab:sort-demo-2 nums)
          (lab:sort-demo-3 nums)
          (lab:sort-demo-4 recs base u)
          (lab:pause)))))

  ;; ---- out -----------------------------------------------------------
  (if drew
    (progn
      (if (= "Erase" (lab:askkw "Keep the demo drawing?" "Keep Erase"
                                "Keep/Erase" "Keep" nil))
        (progn
          (setq n (lab:erase-demo))
          (lab:say (list (strcat "LISPLAB: erased " (itoa n)
                                 " demo objects.")))))))

  (lab:say (list
    ""
    "LISPLAB done.  The routines it just used are in this file and are"
    "meant to be copied: lab:walk-db, lab:on-layer, lab:records for"
    "lesson 1, and lab:bubble, lab:selection, lab:insertion, lab:msort,"
    "lab:qsort, lab:sort-by for lesson 2.  Every sort takes its"
    "comparator as an argument, so they work on anything."
    ""))
  (command "_.UNDO" "_End")
  (setq undo-open nil)
  (lab:sysrestore)
  (princ))

(defun c:LISPLABVER ()
  (princ (strcat "\nLISPLAB " *lisplab-version*))
  (princ))

(princ (strcat "\nLISPLAB " *lisplab-version*
               " loaded.  Type LISPLAB to run."))
(princ)
