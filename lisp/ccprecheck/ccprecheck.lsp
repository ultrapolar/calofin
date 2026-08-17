;;; ===================================================================
;;; CCPRECHECK.LSP - Tech drawing checklist walker
;;;
;;; Interactive AutoLISP routine that walks the "Tech Flow Chart"
;;; decision tree for pool/spa products.  Load with APPLOAD (or
;;; (load "ccprecheck.lsp")) and run the CCPRECHECK command.  The routine asks
;;; the user to answer / confirm each item along the flowchart until
;;; every branch it enters reaches its end, then prints a summary of
;;; every note and confirmation that was collected on the way.
;;;
;;; Flow (top level):
;;;   Product Type
;;;     +- Liner      -> Pool | Spa
;;;     +- Pool Cover -> Freeform | Rectangle
;;;     +- Spa Cover  -> Safety Cover | Hard Cover | ThermoLight Cover
;;; ===================================================================

;;; ------------------------------------------------------------------
;;; Helpers
;;; ------------------------------------------------------------------

(setq *chk:log* nil)   ; collected checklist lines for the summary

;; Record a line for the final summary.
(defun chk:log (msg)
  (setq *chk:log* (append *chk:log* (list msg)))
  msg
)

;; Print an instruction/note to the command line and log it.
(defun chk:note (msg)
  (princ (strcat "\n  >> " msg))
  (chk:log (strcat "NOTE: " msg))
  msg
)

;; Ask the user to pick one keyword out of a list.
;; kwlist  - initget-style keyword string, e.g. "Yes No"
;; prompt  - question text (keywords appended automatically)
;; Returns the chosen keyword string (loops until a choice is made).
(defun chk:ask (prompt kwlist / ans)
  (while (not ans)
    (initget 1 kwlist)
    (setq ans (getkword (strcat "\n" prompt " [" (vl-string-translate " " "/" kwlist) "]: ")))
  )
  (chk:log (strcat prompt " -> " ans))
  ans
)

;; Yes/No convenience wrapper.  Returns T for Yes, nil for No.
(defun chk:yesno (prompt)
  (= (chk:ask prompt "Yes No") "Yes")
)

;; Ask the user to confirm an item; optionally record a typed-in value.
(defun chk:confirm (item / val)
  (setq val (getstring T (strcat "\nConfirm " item " (type value/notes or press Enter): ")))
  (if (= val "")
    (chk:log (strcat "CONFIRMED: " item))
    (chk:log (strcat "CONFIRMED: " item " = " val))
  )
  val
)

;;; ------------------------------------------------------------------
;;; Liner branch
;;; ------------------------------------------------------------------

;; Steps? sub-flow (shared by Liner->Pool and Liner->Spa)
(defun chk:steps (/ kind)
  (if (chk:yesno "Steps?")
    (progn
      (setq kind (chk:ask "Step type" "Fiberglass VinylOver"))
      (if (= kind "Fiberglass")
        (progn
          (chk:confirm "the step face is either straight or radius")
          (chk:note "Show the location of the step always")
          (chk:confirm "the size of the step (especially for radius steps)")
        )
        (progn ; Vinyl over step
          (chk:note "Show Step Attachment & Risers")
          (chk:confirm "sum of Step Risers equals Wall Height")
          (chk:confirm "Step Back Corners")
        )
      )
    )
    (chk:note "No need to show any step info")
  )
)

(defun chk:liner-pool ()
  (chk:confirm "Liner Pattern")
  (chk:confirm "Pool Corners")
  (chk:confirm "Depth / Wall Height")
  (chk:steps)
)

(defun chk:liner-spa ()
  (chk:confirm "Liner Pattern")
  (chk:confirm "the corners")
  (chk:confirm "Depth / Wall Height")
  (if (chk:yesno "Spillway?")
    (progn
      (chk:note "Show Spillway Detail confirming Bead location")
      (chk:confirm "Spillway Dimensions and location")
    )
    (chk:note "Show nothing for the spillway")
  )
  (chk:steps)
)

(defun chk:liner ()
  (if (= (chk:ask "Liner for" "Pool Spa") "Pool")
    (chk:liner-pool)
    (chk:liner-spa)
  )
)

;;; ------------------------------------------------------------------
;;; Pool Cover branch
;;; ------------------------------------------------------------------

;; Obstruction sub-flow (also referenced from Spa Cover -> Safety Cover)
(defun chk:obstruction (/ prox)
  (setq prox (chk:ask
    "Proximity to water's edge"
    "MoreThan3ft OverlapTo3ft ZeroToOverlap InsidePerimeter"))
  (cond
    ((= prox "MoreThan3ft")
     (chk:note "Treatment not necessary")
    )
    ((= prox "OverlapTo3ft")
     (chk:note "Avoid strap")
    )
    ((= prox "ZeroToOverlap")
     ;; 0" meaning the obstruction defines the pool perimeter
     (chk:note "0\" means the obstruction defines the pool perimeter")
     (if (chk:yesno "Can the cover be secured to the obstruction?")
       (chk:note "Most of the time Cable, unless stated otherwise")
       (if (chk:yesno "Is the obstruction larger than 36\"?")
         (if (chk:yesno "Able to go over the obstruction?")
           (progn
             (chk:note "Up and Over")
             (chk:note "3x3 padding over obstacle & step riser where necessary")
           )
           (chk:note "Reduced overlap and/or shortened springs")
         )
         (chk:note (strcat "CutOut if it is a viable solution - "
                           "if not, then reduced overlap and/or shortened springs"))
       )
     )
    )
    (T ; obstruction resides completely inside pool perimeter
     (if (chk:yesno "Able to go over the obstruction?")
       (progn
         (chk:note "Up and Over")
         (chk:note "3x3 padding over obstacle")
       )
       (chk:note "Boot CutOut")
     )
    )
  )
)

(defun chk:decking (/ mat gap)
  (setq mat (chk:ask "Decking material" "Concrete Paver Grass Wood"))
  (cond
    ((= mat "Concrete")
     (chk:note "Standard Anchors / Tubes")
    )
    ((= mat "Paver")
     (chk:note "9\" Tubes / 15\" Tubes")
    )
    ((= mat "Grass") ; grass / planter / rocks
     (chk:note "Tubes / Lawn Stakes / 2x2 Stakes")
    )
    (T ; Wood deck
     (chk:note "Wood Deck Anchors")
     (if (chk:yesno "Is the decking raised?")
       (if (chk:yesno "Are you able to secure the cover to the edge of the deck?")
         (chk:note "On Ground Bracket Clamps / Wood Deck Anchors")
         (progn
           (chk:note "Wood Deck Anchors")
           (if (= (chk:ask "Strap type" "ExtendedStraps ExtensionStraps") "ExtendedStraps")
             (chk:note "Extended Straps: attached to the pool cover, can be any length")
             (progn
               (chk:note "Extension Straps: connect to the straps on the cover")
               (chk:note "Extension Straps come in 2'-0\", 4'-0\" and 6'-0\"")
             )
           )
         )
       )
       (chk:note "Wood Deck Anchors")
     )
    )
  )
  ;; Deck space and springs
  (setq gap (chk:ask "Deck space (for springs)"
                     "GreaterThan18in 9to18in 6to9in LessThan4in"))
  (cond
    ((= gap "GreaterThan18in") (chk:note "Standard Springs"))
    ((= gap "9to18in")         (chk:note "Short Springs"))
    ((= gap "6to9in")          (chk:note "Special Deck Mount"))
    (T                         (chk:note "D-Ring"))
  )
)

(defun chk:pool-cover ()
  (if (= (chk:ask "Pool shape" "Freeform Rectangle") "Freeform")
    (chk:note "18\" overlap, 3x3 spacing unless stated otherwise")
    (chk:note "12\" overlap, 5x5 spacing unless stated otherwise")
  )
  (chk:confirm "Overlap and Spacing")
  (chk:note "Pad sharp corners")
  (if (chk:yesno "Are there obstacles?")
    (progn
      (chk:note "Treat obstacles accordingly")
      (chk:obstruction)
    )
  )
  (chk:decking)
)

;;; ------------------------------------------------------------------
;;; Spa Cover branch
;;; ------------------------------------------------------------------

(defun chk:spa-safety ()
  (if (chk:yesno "Spillway?")
    (chk:note "Pad & dimension the spillway")
  )
  (if (chk:yesno "Obstructions?")
    (progn
      (chk:note "See obstruction flow in Pool Covers")
      (chk:obstruction)
    )
    (chk:note "No obstructions - do nothing")
  )
  (if (chk:yesno "Raised?")
    (progn
      (chk:confirm "the height of the spa (state it on the drawing)")
      (if (chk:yesno "Attaching to pool cover?")
        (chk:note "Note: loose clips will attach to the pool cover")
        (if (chk:yesno "Drum style cover?")
          (chk:note "Add drum style note")
          (chk:note "Spa might need extension straps")
        )
      )
    )
    (if (chk:yesno "Joined wall for spa and pool?")
      (chk:note "Pad the wall")
    )
  )
)

;; Hard cover spillway sub-flow
(defun chk:spa-hard-spillway ()
  (if (chk:yesno "Spillway?")
    (progn
      (chk:note "Go through gap filler and custom block rules to determine")
      (chk:note "Draw the Gap Filler / Custom Block on the spa cover on the cover layer")
      (chk:note "Make sure the inside and outside spillway dims are shown")
      (chk:note (strcat "Make sure the spillway is shown on the bottom or right hand "
                        "side; dimensions and notes go on the dimension itself"))
      (chk:note (strcat "If using a custom block, draw a 3D custom block detail off "
                        "to the side dimensioning the custom block showing LxWxH"))
    )
    (chk:note "No need to show anything for the spillway")
  )
)

(defun chk:spa-hard ()
  (if (= (chk:ask "Spa type" "AboveGround InGround") "AboveGround")
    (progn
      (chk:confirm "pieces are no more than 48\"")
      (chk:confirm "Hinges")
      (chk:confirm "Spa Cover Size")
    )
    (progn
      (chk:note "Heavy Duty Bottom / Hold Down Kit")
      (chk:note "6\" overlap might be required")
      (chk:note "Show overlap dimension")
      (chk:note "Show water's edge / overlap if given")
      (chk:confirm "pieces are no more than 48\"")
      (chk:confirm "Hinges")
      (chk:confirm "Spa Cover Size")
    )
  )
  (chk:spa-hard-spillway)
)

(defun chk:spa-thermolight ()
  (chk:confirm "Cover Size is for water's edge")
  (chk:note "All Velcro hinges - pieces can be up to 53\" but are typically at most 48\"")
  (chk:note "No need to worry about spillways")
  (chk:note "Cover size dimensions should be shown")
)

(defun chk:spa-cover (/ kind)
  (setq kind (chk:ask "Spa cover type" "SafetyCover HardCover ThermoLight"))
  (cond
    ((= kind "SafetyCover") (chk:spa-safety))
    ((= kind "HardCover")   (chk:spa-hard))
    (T                      (chk:spa-thermolight))
  )
)

;;; ------------------------------------------------------------------
;;; Main command
;;; ------------------------------------------------------------------

(defun c:CCPRECHECK (/ product)
  (setq *chk:log* nil)
  (princ "\n--- Tech Flow Chart checklist ---")
  (setq product (chk:ask "Product type" "Liner PoolCover SpaCover"))
  (cond
    ((= product "Liner")     (chk:liner))
    ((= product "PoolCover") (chk:pool-cover))
    (T                       (chk:spa-cover))
  )
  ;; Summary of everything answered / noted along the way
  (princ "\n\n--- Checklist summary ---")
  (foreach line *chk:log*
    (princ (strcat "\n  " line))
  )
  (princ "\n--- End of checklist ---\n")
  (princ)
)

(princ "\nCCPRECHECK.LSP loaded. Type CCPRECHECK to run the tech flow chart checklist.")
(princ)
