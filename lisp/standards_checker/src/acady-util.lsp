;;; acady-util.lsp
;;; Math helpers, list helpers, formatting, logging, safe COM wrappers.
;;; Pure functions only (no editor state), except acady-log which prints.
;;; Portable: AutoCAD 2018+ / BricsCAD. No acet-* functions anywhere.

(vl-load-com)

;; ---------------------------------------------------------------- constants

(setq *acady-pi2*     (* 2.0 pi))
(setq *acady-eps-len* 1e-4)   ; endpoint / zero-length fuzz (drawing units)
(setq *acady-eps-ang* 1e-6)   ; bulge ~ zero fuzz
(setq *acady-merge-ang* 1e-4) ; collinear / co-circular merge fuzz (radians)

;; ---------------------------------------------------------------- alist

(defun acady-aget (key alist) (cdr (assoc key alist)))

(defun acady-aput (key val alist)
  ;; return alist with key set to val (replace or prepend)
  (if (assoc key alist)
    (subst (cons key val) (assoc key alist) alist)
    (cons (cons key val) alist)))

;; ---------------------------------------------------------------- math

(defun acady-norm-ang (a)
  ;; normalize angle into (-pi, pi]
  (while (> a pi)        (setq a (- a *acady-pi2*)))
  (while (<= a (- 0 pi)) (setq a (+ a *acady-pi2*)))
  a)

(defun acady-fuzzeq (a b eps) (<= (abs (- a b)) eps))

(defun acady-clamp-dev (v lo hi)
  ;; deviation of v outside band [lo,hi]; 0.0 if inside
  (cond ((< v lo) (- lo v))
        ((> v hi) (- v hi))
        (t 0.0)))

(defun acady-band-center-dev (v lo hi)
  ;; |v - band center| / half-width, for scoring; 0 if band degenerate
  (if (> (- hi lo) 1e-12)
    (/ (abs (- v (/ (+ lo hi) 2.0))) (/ (- hi lo) 2.0))
    0.0))

;; ---------------------------------------------------------------- lists

(defun acady-rotate-list (lst n / i)
  ;; rotate lst left by n (cyclic)
  (setq n (rem n (length lst)))
  (repeat n (setq lst (append (cdr lst) (list (car lst)))))
  lst)

(defun acady-sort-desc (lst) (vl-sort lst '>))

(defun acady-sum (lst / s)
  (setq s 0.0)
  (foreach x lst (setq s (+ s x)))
  s)

(defun acady-range (n / i out)
  (setq i 0)
  (while (< i n) (setq out (cons i out) i (1+ i)))
  (reverse out))

;; ---------------------------------------------------------------- strings

(defun acady-fmt-len (v)
  ;; architectural: 102.0 -> 8'-6"
  (rtos v 4 4))

(defun acady-fmt-pct (v)
  (strcat (itoa (fix (+ 0.5 (* 100.0 (max 0.0 (min 1.0 v)))))) "%"))

(defun acady-pad (s w)
  ;; left-justify string to width w
  (while (< (strlen s) w) (setq s (strcat s " ")))
  s)

(defun acady-str-join (lst sep / out)
  (setq out "")
  (foreach s lst
    (setq out (if (= out "") s (strcat out sep s))))
  out)

(defun acady-basename-noext (path / f dot)
  ;; "C:/std/pacific.dwg" -> "PACIFIC"
  (setq f (strcase (vl-filename-base path)))
  f)

;; ---------------------------------------------------------------- logging

(setq *acady-verbose* nil) ; set T for debug chatter

(defun acady-log (msg)
  (princ (strcat "\n[acady] " msg))
  (princ))

(defun acady-dbg (msg)
  (if *acady-verbose* (acady-log (strcat "dbg: " msg))))

;; ---------------------------------------------------------------- safe COM

(defun acady-catch (fn args / r)
  ;; vl-catch-all-apply; on error return nil and stash message
  (setq *acady-last-err* nil)
  (setq r (vl-catch-all-apply fn args))
  (if (vl-catch-all-error-p r)
    (progn (setq *acady-last-err* (vl-catch-all-error-message r)) nil)
    r))

(defun acady-release (obj)
  ;; release a COM object, swallowing errors
  (if (and obj (not (vl-catch-all-error-p obj)))
    (vl-catch-all-apply 'vlax-release-object (list obj)))
  nil)

;; ---------------------------------------------------------------- platform

(defun acady-platform ()
  ;; 'ACAD or 'BRICS, from the PROGRAM sysvar semantics
  (if (wcmatch (strcase (getvar "PROGRAM")) "*BRICS*") 'BRICS 'ACAD))

(princ "\n[acady] util loaded.")
(princ)
