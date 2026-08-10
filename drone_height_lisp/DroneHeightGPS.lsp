;;; ============================================================================
;;;  Drone Height from GPS + Ground Elevation                (DroneHeightGPS.lsp)
;;; ----------------------------------------------------------------------------
;;;  Companion to DroneDistortion.lsp. Instead of guessing the drone height
;;;  above grade (the office default of "100 ft"), DDGPS works it out from the
;;;  photo itself:
;;;
;;;     1. File picker  - pick the ORIGINAL drone image (starts on H:, then
;;;                       remembers the last folder you used).
;;;     2. Read the GPS - latitude / longitude / AbsoluteAltitude /
;;;                       RelativeAltitude straight out of the file. The DJI
;;;                       XMP text packet is tried first; if it is missing the
;;;                       binary EXIF GPS block is parsed instead.
;;;     3. Elevation    - ask a free online elevation service for the ground
;;;                       elevation at that latitude / longitude (HTTP request
;;;                       via the Windows MSXML2.XMLHTTP ActiveX object).
;;;     4. The delta    - drone height above grade:
;;;
;;;              H  =  AbsoluteAltitude(ft)  -  ground elevation(ft)
;;;
;;;  H is saved to the SAME per-drawing store DroneDistortion.lsp uses, so
;;;  DDFIX immediately offers it as its default. This file also works on its
;;;  own - DroneDistortion.lsp does not need to be loaded.
;;;
;;;  FILE TYPES
;;;  ----------
;;;  PNG, JPG/JPEG and TIFF are all understood. The reader does not trust the
;;;  file extension - it looks for the metadata containers themselves:
;;;    * XMP text packet   - JPEG APP1, PNG iTXt chunk, or anywhere else the
;;;                          "<x:xmpmeta" packet appears; both DJI's normal
;;;                          attribute form (Tag="...") and the element form
;;;                          (<ns:Tag>...</ns:Tag>) some converters re-write.
;;;    * binary EXIF GPS   - JPEG "Exif\0\0" APP1 block, PNG eXIf chunk, or a
;;;                          bare TIFF header (a .TIF file), either byte order.
;;;  The first 256 KB of the file is scanned; if nothing is found there the
;;;  LAST 256 KB is scanned too (PNG writers may park metadata after the image
;;;  data). A converted file only works if the converter carried the metadata
;;;  over - screenshots and "export/share" copies usually strip it, and DDGPS
;;;  will say so rather than guess.
;;;
;;;  ELEVATION SERVICES (tried in order until one answers; no API keys)
;;;  ------------------
;;;    1. USGS EPQS      - 3DEP ~1-10 m bare-earth model, answers in FEET
;;;                        (NAVD88). US only, public domain, no rate limits
;;;                        that matter at office volumes.
;;;    2. OpenTopoData   - NED 10 m dataset, metres. US only.
;;;    3. Open-Elevation - SRTM ~30 m grid, metres. Worldwide fallback.
;;;
;;;  ACCURACY - READ THIS ONCE
;;;  -------------------------
;;;  * The ground elevation is solid (USGS bare-earth is good to a couple of
;;;    feet). The weak link is the drone's ABSOLUTE altitude: consumer GPS
;;;    vertical error is routinely 10-30 ft, and DJI's sea-level reference
;;;    does not exactly match the USGS datum (a few more feet).
;;;  * That is still far better than a blind 100 ft guess, and the error is
;;;    VISIBLE: DDGPS cross-checks against the barometric RelativeAltitude
;;;    (accurate to inches, but referenced to the TAKE-OFF point). If the tech
;;;    launched at deck level and the two methods agree, trust either. If they
;;;    disagree, the difference IS the GPS error - prefer Relative.
;;;  * The GPS method shines exactly where the guess fails hardest: hillside
;;;    lots where the drone launched well above or below the pool deck.
;;;  * Remember 1/H: at H = 100 ft, 10 ft of H error changes a correction
;;;    that is itself only ~1% per foot of feature height - for a 2 ft raised
;;;    spa that is a 0.2% size difference. H does not need to be perfect.
;;;  * For a hard number, DDCAL (in DroneDistortion.lsp) back-solves H from
;;;    one feature of known true size.
;;;
;;;  REQUIREMENTS
;;;  ------------
;;;  Windows AutoCAD (uses ADODB.Stream + MSXML2.XMLHTTP ActiveX), internet
;;;  access for the elevation lookup, and an image that still carries the
;;;  camera metadata (see FILE TYPES above).
;;;  If the elevation services cannot be reached the command lets you type a
;;;  known site elevation instead (e.g. from the survey).
;;;
;;;  NOTE: the HTTP request is synchronous - AutoCAD sits for a second or two
;;;  while the service answers. If the network is down it can take ~30 s to
;;;  give up; Esc cannot interrupt an in-flight request.
;;;
;;;  COMMANDS
;;;  --------
;;;     DDGPS   - pick the drone image, compute H, save it for DDFIX
;;;     DDELEV  - type a latitude / longitude, print the ground elevation
;;;               (handy as an internet-connectivity test)
;;;
;;;  UNITS
;;;  -----
;;;  Altitudes in the file are metres (DJI writes metres); everything is
;;;  reported and saved in FEET to match DroneDistortion.lsp.
;;; ============================================================================

(vl-load-com)

(setq *DDG-STORE* "DRONE_DISTORTION")  ; same per-drawing LDATA dictionary as
                                       ; DroneDistortion.lsp, so DDFIX sees H
(setq ddg-m->ft 3.280839895)

;; -- persistent storage helpers ---------------------------------------------
(defun ddg-get (key)     (vlax-ldata-get *DDG-STORE* key))
(defun ddg-put (key val) (vlax-ldata-put *DDG-STORE* key val))

;; -- formatting helpers -----------------------------------------------------
(defun ddg-n1 (x) (rtos x 2 1))        ; feet, 1 decimal
(defun ddg-n7 (x) (rtos x 2 7))        ; lat/long, 7 decimals (~1/2 inch)

;; ===========================================================================
;;  Binary file access (Windows ADODB.Stream - same technique as DDALT;
;;  plain (open ... "r") is text mode and stops at the first 0x1A byte)
;; ===========================================================================

;; read up to CNT bytes of FILE as a list of ints, or nil if unreadable.
;; TAIL nil = from the start of the file; TAIL non-nil = the LAST cnt bytes
;; (PNG writers may park the metadata chunks after the image data).
(defun ddg-file-bytes (file cnt tail / stm out err)
  (setq err
    (vl-catch-all-apply
      '(lambda ( / raw sa tmp pos)
         (setq stm (vlax-create-object "ADODB.Stream"))
         (vlax-invoke-method stm 'Open)
         (vlax-put-property  stm 'Type 1)              ; 1 = adTypeBinary
         (vlax-invoke-method stm 'LoadFromFile file)
         (if tail
           (progn
             (setq pos (- (vlax-get-property stm 'Size) cnt))
             (if (< pos 0) (setq pos 0))
             (vlax-put-property stm 'Position pos)))
         (setq raw (vlax-invoke-method stm 'Read cnt))
         (vlax-invoke-method stm 'Close)
         (cond
           ((listp raw) (setq out raw))                ; some builds return a list
           (t
            (setq tmp (vl-catch-all-apply 'vlax-variant-value (list raw)))
            (setq sa  (if (vl-catch-all-error-p tmp) raw tmp))
            (setq out (vlax-safearray->list sa)))))
      '()))
  (if stm (vl-catch-all-apply 'vlax-release-object (list stm)))
  (if (vl-catch-all-error-p err) nil out))

;; walk LST until the byte pattern TGT has just been matched;
;; return the remainder of the list AFTER the pattern, or nil if never found
(defun ddg-scan-to (lst tgt / tlen m b)
  (setq tlen (length tgt) m 0)
  (while (and lst (< m tlen))
    (setq b (car lst) lst (cdr lst))
    (if (< b 0) (setq b (+ b 256)))                    ; normalise if signed
    (if (= b (nth m tgt))
      (setq m (1+ m))
      (setq m (if (= b (car tgt)) 1 0))))
  (if (= m tlen) lst))

;; take up to N bytes off LST as a plain string (non-printables become spaces)
(defun ddg-grab-text (lst n / out chunk b)
  (setq out '() chunk "")
  (while (and lst (> n 0))
    (setq b (car lst) lst (cdr lst) n (1- n))
    (if (< b 0) (setq b (+ b 256)))
    (setq chunk (strcat chunk (if (and (> b 31) (< b 127)) (chr b) " ")))
    (if (>= (strlen chunk) 128)                        ; chunked to keep strcat cheap
      (setq out (cons chunk out) chunk "")))
  (apply 'strcat (reverse (cons chunk out))))

;; ===========================================================================
;;  XMP route (all modern DJI aircraft) - the image carries a text packet like
;;    drone-dji:AbsoluteAltitude="+247.66" drone-dji:RelativeAltitude="+98.40"
;;    drone-dji:GpsLatitude="+32.7157380"  drone-dji:GpsLongtitude="-117.16..."
;;  ("GpsLongtitude" is DJI's own long-standing typo; newer firmware also
;;   writes the correctly-spelt tag - both are checked.)
;;  The packet is found by content, not by container, so JPEG APP1 and PNG
;;  iTXt chunks both work: anchor on "<x:xmpmeta" (any container), then the
;;  JPEG APP1 signature, then the DJI namespace itself as a last resort.
;; ===========================================================================

;; the XMP packet (as one printable string), or "" if the file has none
(defun ddg-xmp-text (lst / rest)
  (setq rest (ddg-scan-to lst (vl-string->list "<x:xmpmeta")))
  (if (null rest)
    (setq rest (ddg-scan-to lst (vl-string->list "ns.adobe.com/xap/1.0/"))))
  (if (null rest)
    (setq rest (ddg-scan-to lst (vl-string->list "drone-dji:"))))
  (if rest (ddg-grab-text rest 6144) ""))

;; value of   TAG="..."   (DJI's attribute form) or   <ns:TAG>...</ns:TAG>
;; (the element form some converters re-write XMP into), or nil
(defun ddg-xmp-attr (txt tag / pos rest end)
  (setq pos (vl-string-search (strcat tag "=\"") txt))
  (if pos
    (progn
      (setq rest (substr txt (+ pos (strlen tag) 3)))  ; just past the ="
      (setq end (vl-string-search "\"" rest))
      (if end (substr rest 1 end)))
    (progn
      (setq pos (vl-string-search (strcat tag ">") txt))
      (if pos
        (progn
          (setq rest (substr txt (+ pos (strlen tag) 2)))   ; just past the >
          (setq end (vl-string-search "<" rest))
          (if end (substr rest 1 end)))))))

;; "+18.90" / "-117.16" / "18.90" -> real, or nil
(defun ddg-numstr (s)
  (setq s (vl-string-trim " " s))
  (if (and (> (strlen s) 0) (= "+" (substr s 1 1))) (setq s (substr s 2)))
  (if (> (strlen s) 0) (distof s 2)))

(defun ddg-xmp-num (txt tag / s)
  (if (setq s (ddg-xmp-attr txt tag)) (ddg-numstr s)))

;; ===========================================================================
;;  EXIF route (fallback) - parse the binary GPS IFD out of the APP1 segment.
;;  Handles both byte orders; every read is nil-safe so a truncated or odd
;;  file just returns nils instead of crashing.
;; ===========================================================================

;; byte at OFF (0-255), or nil past the end
(defun ddg-b (lst off / b)
  (if (setq b (nth off lst))
    (if (< b 0) (+ b 256) b)))

(defun ddg-u16 (lst off le / a b)
  (setq a (ddg-b lst off) b (ddg-b lst (1+ off)))
  (if (and a b) (if le (+ a (* 256 b)) (+ (* 256 a) b))))

;; 32-bit value as a REAL (AutoLISP ints are 32-bit signed - a raw u32 can overflow)
(defun ddg-u32 (lst off le / a b c d)
  (setq a (ddg-b lst off)       b (ddg-b lst (+ off 1))
        c (ddg-b lst (+ off 2)) d (ddg-b lst (+ off 3)))
  (if (and a b c d)
    (if le
      (+ a (* 256.0 b) (* 65536.0 c) (* 16777216.0 d))
      (+ d (* 256.0 c) (* 65536.0 b) (* 16777216.0 a)))))

;; 32-bit value as an INT for use as an offset; nil if missing or absurd
(defun ddg-u32i (lst off le / r)
  (if (and (setq r (ddg-u32 lst off le)) (< r 1.0e9)) (fix r)))

;; unsigned rational (u32 numerator, u32 denominator) -> real, or nil
(defun ddg-rat (lst off le / n d)
  (if off
    (progn
      (setq n (ddg-u32 lst off le) d (ddg-u32 lst (+ off 4) le))
      (if (and n d (/= d 0.0)) (/ n d)))))

;; find TAG in the IFD at offset IFD; return the offset of its 12-byte entry
(defun ddg-ifd-find (lst ifd le tag / n i e r)
  (if (setq n (ddg-u16 lst ifd le))
    (progn
      (setq i 0)
      (while (and (< i n) (null r))
        (setq e (+ ifd 2 (* 12 i)))
        (if (equal (ddg-u16 lst e le) tag) (setq r e))
        (setq i (1+ i)))))
  r)

;; GPS coordinate entry (3 rationals: deg min sec) -> decimal degrees
(defun ddg-gps-coord (lst ent le / off d m s)
  (if (setq off (ddg-u32i lst (+ ent 8) le))
    (progn
      (setq d (ddg-rat lst off le)
            m (ddg-rat lst (+ off 8) le)
            s (ddg-rat lst (+ off 16) le))
      (if (and d m s) (+ d (/ m 60.0) (/ s 3600.0))))))

;; does REST start with a TIFF header?  ("II" 42 0  /  "MM" 0 42) -> REST or nil
(defun ddg-tiff-at (rest / b0 b1)
  (setq b0 (ddg-b rest 0) b1 (ddg-b rest 1))
  (cond
    ((and (equal b0 73) (equal b1 73)
          (equal (ddg-b rest 2) 42) (equal (ddg-b rest 3) 0)) rest)
    ((and (equal b0 77) (equal b1 77)
          (equal (ddg-b rest 2) 0) (equal (ddg-b rest 3) 42)) rest)))

;; find the EXIF TIFF block whatever the container:
;;   * a bare .TIF file        - TIFF header at byte 0
;;   * JPEG (and HEIC) style   - "Exif" 0 0, then the TIFF header
;;   * PNG eXIf chunk          - the TIFF header directly follows the type
;; A match is only accepted if a valid TIFF magic follows, so a stray "Exif"
;; inside compressed image data is skipped and the scan continues.
(defun ddg-find-tiff (lst / tif rest)
  (setq tif (ddg-tiff-at lst))
  (setq rest lst)
  (while (and (null tif)
              (setq rest (ddg-scan-to rest (vl-string->list "Exif"))))
    (if (and (equal (ddg-b rest 0) 0) (equal (ddg-b rest 1) 0))
      (setq tif (ddg-tiff-at (cddr rest)))))
  (setq rest lst)
  (while (and (null tif)
              (setq rest (ddg-scan-to rest (vl-string->list "eXIf"))))
    (setq tif (ddg-tiff-at rest)))
  tif)

;; TIFF header -> IFD0 -> GPS IFD; returns (lat lon alt-metres), any may be nil
(defun ddg-exif-gps (lst / tif le ifd0 ent gps lat lon altm)
  (setq tif (ddg-find-tiff lst))
  (if tif
    (progn
      (setq le (equal (ddg-b tif 0) 73))       ; "II" little / "MM" big endian
      (setq ifd0 (ddg-u32i tif 4 le))
      (if ifd0 (setq ent (ddg-ifd-find tif ifd0 le 34853)))  ; 0x8825 GPS IFD
      (if ent  (setq gps (ddg-u32i tif (+ ent 8) le)))
      (if gps
        (progn
          (if (setq ent (ddg-ifd-find tif gps le 2))         ; GPSLatitude
            (setq lat (ddg-gps-coord tif ent le)))
          (if (and lat (setq ent (ddg-ifd-find tif gps le 1))
                   (equal (ddg-b tif (+ ent 8)) 83))         ; ref "S"
            (setq lat (- lat)))
          (if (setq ent (ddg-ifd-find tif gps le 4))         ; GPSLongitude
            (setq lon (ddg-gps-coord tif ent le)))
          (if (and lon (setq ent (ddg-ifd-find tif gps le 3))
                   (equal (ddg-b tif (+ ent 8)) 87))         ; ref "W"
            (setq lon (- lon)))
          (if (setq ent (ddg-ifd-find tif gps le 6))         ; GPSAltitude
            (setq altm (ddg-rat tif (ddg-u32i tif (+ ent 8) le) le)))
          (if (and altm (setq ent (ddg-ifd-find tif gps le 5))
                   (equal (ddg-b tif (+ ent 8)) 1))          ; below sea level
            (setq altm (- altm)))))))
  (list lat lon altm))

;; everything the file tells us: (absalt-m relalt-m lat lon) - XMP first,
;; the binary EXIF GPS block filling any gaps
(defun ddg-read-meta (lst / xtxt exif absm relm lat lon)
  (setq xtxt (ddg-xmp-text lst))
  (setq absm (ddg-xmp-num xtxt "AbsoluteAltitude")
        relm (ddg-xmp-num xtxt "RelativeAltitude")
        lat  (ddg-xmp-num xtxt "GpsLatitude")
        lon  (ddg-xmp-num xtxt "GpsLongitude"))
  (if (null lon) (setq lon (ddg-xmp-num xtxt "GpsLongtitude")))
  (if (or (null lat) (null lon) (null absm))
    (progn
      (setq exif (ddg-exif-gps lst))
      (if (null lat)  (setq lat  (car exif)))
      (if (null lon)  (setq lon  (cadr exif)))
      (if (null absm) (setq absm (caddr exif)))))
  (list absm relm lat lon))

;; ===========================================================================
;;  HTTP + JSON (MSXML2.XMLHTTP ActiveX; synchronous GET)
;; ===========================================================================

;; one attempt with a given ProgID; returns the response text on HTTP 200
(defun ddg-http-try (prog url / xh err txt sts ok)
  (setq err
    (vl-catch-all-apply
      '(lambda ()
         (setq xh (vlax-create-object prog))
         (vlax-invoke-method xh 'Open "GET" url :vlax-false)
         ;; some builds want (Send) bare, some want an (empty) body argument
         (if (vl-catch-all-error-p
               (vl-catch-all-apply '(lambda () (vlax-invoke-method xh 'Send))))
           (vlax-invoke-method xh 'Send ""))
         (setq sts (vlax-get-property xh 'Status))
         (setq txt (vlax-get-property xh 'ResponseText))
         (setq ok t))))
  (if xh (vl-catch-all-apply 'vlax-release-object (list xh)))
  (if (and ok (not (vl-catch-all-error-p err))
           (equal sts 200) txt (> (strlen txt) 0))
    txt))

;; XMLHTTP first (follows the office/IE proxy settings), ServerXMLHTTP last
(defun ddg-http-get (url / txt)
  (foreach prog '("MSXML2.XMLHTTP.6.0" "MSXML2.XMLHTTP" "MSXML2.ServerXMLHTTP.6.0")
    (if (null txt) (setq txt (ddg-http-try prog url))))
  txt)

;; first number that follows "KEY" in a JSON text - tolerant of quoting and
;; whitespace ("value":"296.61" and "elevation": 251.3 both work); nil on null
(defun ddg-json-num (txt key / pos rest len i c numstr)
  (setq pos (vl-string-search (strcat "\"" key "\"") txt))
  (if pos
    (progn
      (setq rest (substr txt (+ pos (strlen key) 3))   ; just past the closing quote
            len  (strlen rest)
            i    1)
      (while (and (<= i len)
                  (member (substr rest i 1) '(" " ":" "\"" "\t")))
        (setq i (1+ i)))
      (setq numstr "")
      (while (and (<= i len)
                  (member (substr rest i 1)
                          '("-" "+" "." "0" "1" "2" "3" "4"
                            "5" "6" "7" "8" "9" "e" "E")))
        (setq numstr (strcat numstr (substr rest i 1)))
        (setq i (1+ i)))
      (if (> (strlen numstr) 0) (ddg-numstr numstr)))))

;; ground elevation in FEET at LAT/LON -> (feet . "source"), or nil.
;; Services tried in order; each answer is sanity-ranged before being trusted.
(defun ddg-ground-elev (lat lon / la lo txt v res)
  (setq la (ddg-n7 lat) lo (ddg-n7 lon))
  ;; 1) USGS EPQS - 3DEP bare earth, NAVD88, answers in FEET. US only.
  (setq txt (ddg-http-get (strcat "https://epqs.nationalmap.gov/v1/json?x=" lo
                                  "&y=" la "&wkid=4326&units=Feet")))
  (setq v (if txt (ddg-json-num txt "value")))
  (if (and v (> v -1500.0) (< v 25000.0))              ; feet; filters the
    (setq res (cons v "USGS 3DEP")))                   ; -1000000 no-data flag
  ;; 2) OpenTopoData NED 10 m - metres. US only.
  (if (null res)
    (progn
      (setq txt (ddg-http-get (strcat "https://api.opentopodata.org/v1/ned10m?locations="
                                      la "," lo)))
      (setq v (if txt (ddg-json-num txt "elevation")))
      (if (and v (> v -500.0) (< v 7000.0))
        (setq res (cons (* v ddg-m->ft) "OpenTopoData NED10m")))))
  ;; 3) Open-Elevation - SRTM ~30 m, metres. Worldwide fallback.
  (if (null res)
    (progn
      (setq txt (ddg-http-get (strcat "https://api.open-elevation.com/api/v1/lookup?locations="
                                      la "," lo)))
      (setq v (if txt (ddg-json-num txt "elevation")))
      (if (and v (> v -500.0) (< v 7000.0))
        (setq res (cons (* v ddg-m->ft) "Open-Elevation SRTM")))))
  res)

;; ---------------------------------------------------------------------------
;;  DDGPS : pick the drone image -> read GPS -> look up ground -> save H
;; ---------------------------------------------------------------------------
(defun c:DDGPS ( / *error* def c file lst meta fsize absm relm lat lon g gft gsrc
                   absft relft hgps hrel diff ans hsel)
  (defun *error* (m)
    (if (and m (not (wcmatch (strcase m) "*CANCEL*,*QUIT*,*ABORT*")))
      (princ (strcat "\nError: " m)))
    (princ))

  ;; 1) pick the photo - start in the last-used folder, else the H: drive
  (setq def (getenv "DDGPS_LastDir"))
  (if (or (null def) (= def "") (not (vl-file-directory-p def)))
    (setq def (if (vl-file-directory-p "H:/") "H:/" "")))
  (if (> (strlen def) 0)
    (progn
      (setq c (substr def (strlen def) 1))
      (if (and (/= c "/") (/= c "\\")) (setq def (strcat def "\\")))))
  (setq file (getfiled "Select the ORIGINAL drone image (PNG / JPG / TIF)" def
                       "png;jpg;jpeg;tif;tiff" 20))    ; 16 path-only + 4 any ext
  (cond
    ((null file) (princ "\nNo file selected."))
    (t
     (if (vl-filename-directory file)
       (setenv "DDGPS_LastDir" (vl-filename-directory file)))
     (princ "\nReading the photo ...")
     (setq lst (ddg-file-bytes file 262144 nil))       ; metadata usually up front
     (cond
       ((null lst)
        (princ "\nCould not read that file (is it on a dead network path?)."))
       (t
        ;; 2) XMP first (every modern DJI), binary EXIF GPS block as fallback
        (setq meta (ddg-read-meta lst)
              absm (nth 0 meta) relm (nth 1 meta)
              lat  (nth 2 meta) lon  (nth 3 meta))
        ;; some PNG writers park the metadata after the image data - if the
        ;; front window came up short, scan the tail of the file too
        (if (and (or (null lat) (null lon) (null absm))
                 (setq fsize (vl-file-size file))
                 (> fsize 262144)
                 (setq lst (ddg-file-bytes file 262144 T)))
          (progn
            (setq meta (ddg-read-meta lst))
            (if (null absm) (setq absm (nth 0 meta)))
            (if (null relm) (setq relm (nth 1 meta)))
            (if (null lat)  (setq lat  (nth 2 meta)))
            (if (null lon)  (setq lon  (nth 3 meta)))))
        (cond
          ((or (null lat) (null lon)
               (and (equal lat 0.0 1e-9) (equal lon 0.0 1e-9))   ; "no fix"
               (> (abs lat) 90.0) (> (abs lon) 180.0))
           (princ "\nNo usable GPS position in that file.")
           (princ "\n  Is it the ORIGINAL camera file?  Screenshots and most edited /")
           (princ "\n  emailed / re-exported copies (JPG or PNG) strip the GPS metadata."))
          (t
           (princ "\n--- from the photo -----------------------------------------")
           (princ (strcat "\n  GPS position     : " (ddg-n7 lat) ", " (ddg-n7 lon)))
           (if absm
             (princ (strcat "\n  AbsoluteAltitude : " (ddg-n1 (* absm ddg-m->ft))
                            " ft above sea level   (" (ddg-n1 absm) " m)")))
           (if relm
             (princ (strcat "\n  RelativeAltitude : " (ddg-n1 (* relm ddg-m->ft))
                            " ft above the take-off point   (" (ddg-n1 relm) " m)")))
           (if (null absm)
             (princ "\n  No absolute altitude in the file - only the barometric method is available."))
           ;; 3) ground elevation at the photo position
           (princ "\nLooking up ground elevation (internet, a few seconds) ...")
           (setq g (ddg-ground-elev lat lon))
           (if g
             (setq gft (car g) gsrc (cdr g))
             (progn
               (princ "\nElevation lookup FAILED - no internet, or the services are down/blocked.")
               (setq gft  (getreal "\nGround elevation at the site in FEET, if you know it (Enter to abort): ")
                     gsrc "entered by hand")))
           (cond
             ((null gft) (princ "\nAborted - H unchanged."))
             (t
              (princ (strcat "\n  Ground elevation : " (ddg-n1 gft) " ft   [" gsrc "]"))
              (if absm (setq absft (* absm ddg-m->ft) hgps (- absft gft)))
              (if relm (setq relft (* relm ddg-m->ft) hrel relft))
              ;; 4) the delta, plus the barometric cross-check
              (princ "\n--- drone height above grade -------------------------------")
              (if hgps
                (princ (strcat "\n  GPS method       : " (ddg-n1 absft) " - " (ddg-n1 gft)
                               "  ->  H = " (ddg-n1 hgps) " ft")))
              (if hrel
                (princ (strcat "\n  Barometer method : H = " (ddg-n1 hrel)
                               " ft   (true only if the take-off point was at deck grade)")))
              (if (and hgps hrel)
                (progn
                  (setq diff (- (- absft relft) gft))  ; take-off elev vs grade
                  (princ (strcat "\n  Cross-check      : the take-off point computes to "
                                 (ddg-n1 (abs diff)) " ft "
                                 (if (>= diff 0.0) "ABOVE" "BELOW")
                                 " the grade at the photo spot."))
                  (princ (if (< (abs diff) 6.0)
                           "\n                     Small -> the methods agree; either value is good."
                           "\n                     If the tech actually launched at deck level, that IS the GPS error -> prefer Relative."))))
              (if (and hgps (or (<= hgps 0.0) (> hgps 400.0)))
                (princ (strcat "\n  WARNING: H = " (ddg-n1 hgps)
                               " ft from GPS is outside the sane 0-400 ft flying range - GPS error likely.")))
              ;; 5) choose + save (only positive heights are offered)
              (setq hgps (if (and hgps (> hgps 0.0)) hgps)
                    hrel (if (and hrel (> hrel 0.0)) hrel))
              (cond
                ((and hgps hrel)
                 (initget "Gps Relative No")
                 (setq ans (getkword (strcat "\nSave which as the drone height H?  Gps="
                                             (ddg-n1 hgps) "  Relative=" (ddg-n1 hrel)
                                             "  [Gps/Relative/No] <Gps>: ")))
                 (if (null ans) (setq ans "Gps"))
                 (setq hsel (cond ((= ans "Gps") hgps)
                                  ((= ans "Relative") hrel))))
                (hgps
                 (initget "Yes No")
                 (setq ans (getkword (strcat "\nSave H = " (ddg-n1 hgps)
                                             " ft (GPS method)? [Yes/No] <Yes>: ")))
                 (if (null ans) (setq ans "Yes"))
                 (if (= ans "Yes") (setq hsel hgps)))
                (hrel
                 (initget "Yes No")
                 (setq ans (getkword (strcat "\nNo usable GPS altitude - save H = " (ddg-n1 hrel)
                                             " ft (RelativeAltitude)? [Yes/No] <Yes>: ")))
                 (if (null ans) (setq ans "Yes"))
                 (if (= ans "Yes") (setq hsel hrel)))
                (t (princ "\nNo positive height could be computed - nothing to save.")))
              (if hsel
                (progn
                  (ddg-put "H" hsel)
                  (ddg-put "GPS_LAT" lat)              ; kept for reference
                  (ddg-put "GPS_LON" lon)
                  (ddg-put "GPS_GROUND" gft)
                  (ddg-put "GPS_SRC" gsrc)
                  (princ (strcat "\nSaved drone height  H = " (ddg-n1 hsel)
                                 " ft   (DDFIX now offers it as the default)"))
                  (princ (strcat "\nDistortion rate: ~" (rtos (/ 100.0 hsel) 2 3)
                                 "% size change per unit of height.")))
                (princ "\nH unchanged."))))))))))
  (princ))

;; ---------------------------------------------------------------------------
;;  DDELEV : ground elevation at a typed latitude / longitude
;; ---------------------------------------------------------------------------
(defun c:DDELEV ( / lat lon g)
  (setq lat (getreal "\nLatitude  (decimal degrees, negative = South): "))
  (setq lon (getreal "\nLongitude (decimal degrees, negative = West): "))
  (cond
    ((or (null lat) (null lon)) (princ "\nNeed both numbers."))
    ((or (> (abs lat) 90.0) (> (abs lon) 180.0))
     (princ "\nThat is not a valid latitude / longitude."))
    (t
     (princ "\nLooking up ground elevation ...")
     (setq g (ddg-ground-elev lat lon))
     (if g
       (princ (strcat "\nGround elevation: " (ddg-n1 (car g)) " ft   ("
                      (ddg-n1 (/ (car g) ddg-m->ft)) " m)   [" (cdr g) "]"))
       (princ "\nLookup failed - check the internet connection (or the coordinate)."))))
  (princ))

(princ "\nDrone Height from GPS v1.1 loaded  (reads PNG / JPG / TIF; elevation lookup needs internet).")
(princ "\n  Commands: DDGPS  (pick drone image -> compute + save H)   DDELEV  (elevation at a typed lat/long)")
(princ)
