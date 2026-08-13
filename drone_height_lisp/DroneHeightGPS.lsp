;;; ============================================================================
;;;  Drone Height from GPS + Ground Elevation                (DroneHeightGPS.lsp)
;;; ----------------------------------------------------------------------------
;;;  Companion to DroneDistortion.lsp. Instead of guessing the drone height
;;;  above grade (the office default of "100 ft"), DDGPS works it out from the
;;;  photo itself:
;;;
;;;     1. File picker   - pick the ORIGINAL drone photo (starts on H:, then
;;;                        remembers the last folder you used).
;;;     2. Read the GPS  - latitude / longitude / AbsoluteAltitude straight
;;;                        out of the file. The DJI XMP text packet is tried
;;;                        first; if it is missing the binary EXIF GPS block
;;;                        is parsed instead.
;;;     3. Click a point - pick where in the drawing to place the result.
;;;     4. Elevation     - ask a free online elevation service for the ground
;;;                        elevation at that latitude / longitude (HTTP
;;;                        request via the Windows MSXML2.XMLHTTP object).
;;;     5. The delta     - drone height above grade:
;;;
;;;              H  =  AbsoluteAltitude(ft)  -  ground elevation(ft)
;;;
;;;        rounded to the nearest foot, written as text at the picked point,
;;;        AND saved to the SAME per-drawing store DroneDistortion.lsp uses,
;;;        so DDFIX immediately offers it as its default. This file also
;;;        works on its own - DroneDistortion.lsp does not need to be loaded.
;;;
;;;  FILE TYPES
;;;  ----------
;;;  PNG, JPG/JPEG and TIFF are all understood, PROVIDED the file still
;;;  carries its original camera metadata - this only works on an original
;;;  drone photo, not a video frame grab, screenshot, or an export that
;;;  stripped it. The reader does not trust the file extension - it looks for
;;;  the metadata containers themselves:
;;;    * XMP text packet   - JPEG APP1, PNG iTXt chunk, or anywhere else the
;;;                          "<x:xmpmeta" packet appears; both DJI's normal
;;;                          attribute form (Tag="...") and the element form
;;;                          (<ns:Tag>...</ns:Tag>) some converters re-write.
;;;    * binary EXIF GPS   - JPEG "Exif\0\0" APP1 block, PNG eXIf chunk, or a
;;;                          bare TIFF header (a .TIF file), either byte order.
;;;  The first 256 KB of the file is scanned; if nothing is found there the
;;;  LAST 256 KB is scanned too (PNG writers may park metadata after the
;;;  image data). If neither container has a usable GPS position and
;;;  altitude, DDGPS fails loudly and stops - use the file exactly as it
;;;  came off the drone.
;;;
;;;  ANNOTATION
;;;  ----------
;;;  After you click a point, DDGPS drops 5 lines of plain single-line TEXT
;;;  at that point (GPS position, drone altitude, ground elevation + source,
;;;  the subtraction, and the final rounded height) on the current layer, in
;;;  the current text style. Text height defaults to the drawing's current
;;;  TEXTSIZE the first time; after that it is remembered per drawing (same
;;;  store as H below) and offered as the default - press Enter to keep it,
;;;  or type a new height to change it.
;;;
;;;  ELEVATION SERVICES (tried in order until one answers; no API keys)
;;;  ------------------
;;;    1. USGS EPQS      - 3DEP ~1-10 m bare-earth model, answers in FEET
;;;                        (NAVD88). US only, public domain, no rate limits
;;;                        that matter at office volumes.
;;;    2. OpenTopoData   - NED 10 m dataset, metres. US only.
;;;    3. Open-Elevation - SRTM ~30 m grid, metres. Worldwide fallback.
;;;  If none can be reached, DDGPS lets you type a known site elevation
;;;  instead (e.g. from the survey) rather than losing the whole run.
;;;
;;;  ACCURACY - READ THIS ONCE
;;;  -------------------------
;;;  * The ground elevation is solid (USGS bare-earth is good to a couple of
;;;    feet). The weak link is the drone's ABSOLUTE altitude: consumer GPS
;;;    vertical error is routinely 10-30 ft, and DJI's sea-level reference
;;;    does not exactly match the USGS datum (a few more feet).
;;;  * That is still far better than a blind 100 ft guess.
;;;  * The GPS method shines exactly where the guess fails hardest: hillside
;;;    lots where the drone launched well above or below the pool deck.
;;;  * Remember 1/H: at H = 100 ft, 10 ft of H error changes a correction
;;;    that is itself only ~1% per foot of feature height - for a 2 ft raised
;;;    spa that is a 0.2% size difference. H does not need to be perfect.
;;;  * For a hard number, DDCAL (in DroneDistortion.lsp) back-solves H from
;;;    one feature of known true size. DDALT (also in DroneDistortion.lsp)
;;;    remains available as a no-internet, barometric-only alternative.
;;;
;;;  FAILURE REPORTING
;;;  -----------------
;;;  Every failure is LOUD: a dialog box pops up saying exactly WHAT failed
;;;  and HOW - "no camera metadata in this file", "no GPS data found",
;;;  "no GPS fix (position is 0,0)", "no altitude data", or which elevation
;;;  service failed and why (no answer / HTTP error / outside coverage) -
;;;  and the same detail is printed on the command line for the record.
;;;  The only quiet exits are the ones you choose yourself (cancelling the
;;;  file dialog, declining a point, or pressing Enter at an abort prompt).
;;;
;;;  REQUIREMENTS
;;;  ------------
;;;  Windows AutoCAD (uses ADODB.Stream + MSXML2.XMLHTTP ActiveX), internet
;;;  access for the elevation lookup, and an ORIGINAL drone photo that still
;;;  carries the camera metadata (see FILE TYPES above).
;;;
;;;  NOTE: the HTTP request is synchronous - AutoCAD sits for a second or two
;;;  while the service answers. If the network is down it can take ~30 s to
;;;  give up; Esc cannot interrupt an in-flight request.
;;;
;;;  COMMANDS
;;;  --------
;;;     DDGPS   - pick the drone photo, click a point, place the height
;;;               report there, and save H for DDFIX
;;;     DDELEV  - type a latitude / longitude, print the ground elevation
;;;               (handy as an internet-connectivity test)
;;;
;;;  UNITS
;;;  -----
;;;  Altitude in the file is metres (DJI writes metres); everything is
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

;; file name without the folder, for messages
(defun ddg-fname (f / e)
  (setq e (vl-filename-extension f))
  (strcat (vl-filename-base f) (if e e "")))

;; -- loud failure -----------------------------------------------------------
;; Pops a modal alert box saying WHAT failed (title) and HOW (lines), and
;; prints the same detail on the command line for the record.
(defun ddg-fail (title lines / msg)
  (setq msg title)
  (foreach l lines (setq msg (strcat msg "\n" l)))
  (princ (strcat "\n*** " title " ***"))
  (foreach l lines (if (/= l "") (princ (strcat "\n  " l))))
  (alert msg)
  (princ))

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
;;    drone-dji:AbsoluteAltitude="+247.66"
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
  (list lat lon altm (if tif T)))     ; 4th: was an EXIF block found at all?

;; everything the file tells us: (absalt-m lat lon xmp-found exif-found)
;; XMP text packet first (JPEG APP1 / PNG iTXt), the binary EXIF GPS block
;; filling any gaps (JPEG APP1 / PNG eXIf / bare TIFF). The last two flags
;; say whether an XMP packet / EXIF block was present at all - failure
;; reporting uses them to tell "stripped file" apart from "metadata without
;; GPS".
(defun ddg-read-meta (lst / xtxt exif absm lat lon xmpf tiff)
  (setq xtxt (ddg-xmp-text lst))
  (setq xmpf (> (strlen xtxt) 0))
  (setq absm (ddg-xmp-num xtxt "AbsoluteAltitude")
        lat  (ddg-xmp-num xtxt "GpsLatitude")
        lon  (ddg-xmp-num xtxt "GpsLongitude"))
  (if (null lon) (setq lon (ddg-xmp-num xtxt "GpsLongtitude")))
  (if (or (null lat) (null lon) (null absm))
    (progn
      (setq exif (ddg-exif-gps lst))
      (if (null lat)  (setq lat  (car exif)))
      (if (null lon)  (setq lon  (cadr exif)))
      (if (null absm) (setq absm (caddr exif)))
      (setq tiff (cadddr exif))))
  (list absm lat lon xmpf tiff))

;; ===========================================================================
;;  HTTP + JSON (MSXML2.XMLHTTP ActiveX; synchronous GET)
;; ===========================================================================

;; one attempt with a given ProgID.  Returns (list rank payload):
;;   rank 2 - HTTP 200, payload = the response text
;;   rank 1 - reached a server but got a bad answer (payload = how it failed)
;;   rank 0 - the request never completed        (payload = how it failed)
(defun ddg-http-try (prog url / xh err txt sts)
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
         (setq txt (vlax-get-property xh 'ResponseText)))))
  (if xh (vl-catch-all-apply 'vlax-release-object (list xh)))
  (cond
    ((vl-catch-all-error-p err)
     (list 0 (if xh
               "no answer (no internet / DNS / firewall / timeout)"
               (strcat prog " is not available on this PC"))))
    ((not (and (numberp sts) (= sts 200)))
     (list 1 (strcat "server answered HTTP "
                     (if (numberp sts) (itoa (fix sts)) "?")
                     " instead of 200")))
    ((or (null txt) (= (strlen txt) 0))
     (list 1 "server sent back an empty response"))
    (t (list 2 txt))))

;; GET URL trying several ProgIDs (XMLHTTP follows the office/IE proxy
;; settings; ServerXMLHTTP is the last resort).
;; Returns (list T text) on success, else (list nil how-it-failed) - the
;; reason kept is from the attempt that got the furthest.
(defun ddg-http-get (url / best r)
  (foreach prog '("MSXML2.XMLHTTP.6.0" "MSXML2.XMLHTTP" "MSXML2.ServerXMLHTTP.6.0")
    (if (or (null best) (< (car best) 2))
      (progn
        (setq r (ddg-http-try prog url))
        (if (or (null best) (> (car r) (car best)))
          (setq best r)))))
  (if (= (car best) 2)
    (list T (cadr best))
    (list nil (cadr best))))

;; first number that follows KEY in TXT - skips :, =, [, quotes and blanks in
;; between; nil on null / absent
(defun ddg-num-after (txt key / pos rest len i numstr)
  (setq pos (vl-string-search key txt))
  (if pos
    (progn
      (setq rest (substr txt (+ pos (strlen key) 1))   ; just past the key
            len  (strlen rest)
            i    1)
      (while (and (<= i len)
                  (member (substr rest i 1) '(" " ":" "=" "[" "\"" "\t")))
        (setq i (1+ i)))
      (setq numstr "")
      (while (and (<= i len)
                  (member (substr rest i 1)
                          '("-" "+" "." "0" "1" "2" "3" "4"
                            "5" "6" "7" "8" "9" "e" "E")))
        (setq numstr (strcat numstr (substr rest i 1)))
        (setq i (1+ i)))
      (if (> (strlen numstr) 0) (ddg-numstr numstr)))))

;; JSON flavour: the key sits in quotes ("value":"296.61" / "elevation": 251.3)
(defun ddg-json-num (txt key)
  (ddg-num-after txt (strcat "\"" key "\"")))

;; ground elevation in FEET at LAT/LON. Services tried in order; each answer
;; is sanity-ranged before being trusted.
;;   success -> (list feet source-name)
;;   failure -> (list nil notes)   notes = one "service: how it failed" line
;;                                 for every service that was tried
(defun ddg-ground-elev (lat lon / la lo r v res notes)
  (setq la (ddg-n7 lat) lo (ddg-n7 lon) notes '())
  ;; 1) USGS EPQS - 3DEP bare earth, NAVD88, answers in FEET. US only.
  (setq r (ddg-http-get (strcat "https://epqs.nationalmap.gov/v1/json?x=" lo
                                "&y=" la "&wkid=4326&units=Feet")))
  (if (car r)
    (progn
      (setq v (ddg-json-num (cadr r) "value"))
      (if (and v (> v -1500.0) (< v 25000.0))          ; filters the -1000000
        (setq res (list v "USGS 3DEP"))                ; no-data flag
        (setq notes (cons "USGS EPQS: answered, but has no elevation for this spot (outside US coverage?)"
                          notes))))
    (setq notes (cons (strcat "USGS EPQS: " (cadr r)) notes)))
  ;; 2) OpenTopoData NED 10 m - metres. US only.
  (if (null res)
    (progn
      (setq r (ddg-http-get (strcat "https://api.opentopodata.org/v1/ned10m?locations="
                                    la "," lo)))
      (if (car r)
        (progn
          (setq v (ddg-json-num (cadr r) "elevation"))
          (if (and v (> v -500.0) (< v 7000.0))
            (setq res (list (* v ddg-m->ft) "OpenTopoData NED10m"))
            (setq notes (cons "OpenTopoData: answered, but has no elevation for this spot (outside US coverage?)"
                              notes))))
        (setq notes (cons (strcat "OpenTopoData: " (cadr r)) notes)))))
  ;; 3) Open-Elevation - SRTM ~30 m, metres. Worldwide fallback.
  (if (null res)
    (progn
      (setq r (ddg-http-get (strcat "https://api.open-elevation.com/api/v1/lookup?locations="
                                    la "," lo)))
      (if (car r)
        (progn
          (setq v (ddg-json-num (cadr r) "elevation"))
          (if (and v (> v -500.0) (< v 7000.0))
            (setq res (list (* v ddg-m->ft) "Open-Elevation SRTM"))
            (setq notes (cons "Open-Elevation: answered without a usable elevation"
                              notes))))
        (setq notes (cons (strcat "Open-Elevation: " (cadr r)) notes)))))
  (if res res (list nil (reverse notes))))

;; ===========================================================================
;;  Drawing annotation helpers
;; ===========================================================================

;; round-half-away-from-zero (AutoLISP has no built-in ROUND; FIX truncates
;; toward zero, so nudge by +/- 0.5 first)
(defun ddg-round (x) (fix (+ x (if (>= x 0.0) 0.5 -0.5))))

;; annotation text height: defaults to the drawing's current TEXTSIZE, then
;; remembers a per-drawing override under the same store as H - same
;; "current value in <brackets>, Enter keeps it" idiom as DDSET/DDFIX/DDALT
(defun ddg-txt-height ( / cur ht)
  (setq cur (ddg-get "TXTHT"))
  (if (null cur) (setq cur (getvar "TEXTSIZE")))
  (if (or (null cur) (<= cur 0.0)) (setq cur 1.0))   ; TEXTSIZE can legitimately be 0
  (setq ht (getreal (strcat "\nAnnotation text height <" (ddg-n1 cur) ">: ")))
  (if (or (null ht) (<= ht 0.0)) (setq ht cur))
  (ddg-put "TXTHT" ht)
  ht)

;; place LINES (strings, top to bottom) as stacked single-line TEXT entities
;; starting at BASEPT-UCS (a point in the CURRENT UCS, e.g. straight out of
;; getpoint). Each point is converted UCS -> WCS right before entmake (entity
;; data needs WCS; mirrors the (trans base 0 1) idiom DroneDistortion.lsp
;; uses the other way around before feeding a point to a command). Returns T
;; if every line was created.
(defun ddg-place-text (basept-ucs lines height layer style / y pt ok)
  (setq y 0.0 ok T)
  (foreach ln lines
    (setq pt (list (car basept-ucs) (- (cadr basept-ucs) y) (caddr basept-ucs)))
    (if (null (entmake (list '(0 . "TEXT")
                              (cons 8 layer)
                              (cons 10 (trans pt 1 0))     ; UCS -> WCS
                              (cons 40 height)
                              (cons 1 ln)
                              (cons 7 style))))
      (setq ok nil))
    (setq y (+ y (* height 1.667))))   ; AutoCAD's standard single-line spacing
  ok)

;; ---------------------------------------------------------------------------
;;  DDGPS : pick the drone photo -> read GPS -> click a point -> look up
;;          ground elevation -> place the height report -> save H
;; ---------------------------------------------------------------------------
(defun c:DDGPS ( / *error* def c file lst meta fsize absm lat lon xmpf tiff
                   pt g gft gsrc absft hraw hsel ht lines placed ans)
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
  (setq file (getfiled "Select the ORIGINAL drone photo (PNG / JPG / TIF)" def
                       "png;jpg;jpeg;tif;tiff" 16))
  (cond
    ((null file) (princ "\nNo file selected."))
    (t
     (if (vl-filename-directory file)
       (setenv "DDGPS_LastDir" (vl-filename-directory file)))
     (princ "\nReading the photo ...")
     (setq lst (ddg-file-bytes file 262144 nil))       ; metadata usually up front
     (cond
       ((null lst)
        (ddg-fail "COULD NOT READ THE FILE"
          (list (strcat "File: " file)
                ""
                "The file could not be opened for reading - dead network"
                "path, file locked by another program, or no permission.")))
       (t
        ;; 2) XMP first (every modern DJI), binary EXIF GPS block as fallback
        (setq meta (ddg-read-meta lst)
              absm (nth 0 meta) lat  (nth 1 meta) lon  (nth 2 meta)
              xmpf (nth 3 meta) tiff (nth 4 meta))
        ;; some PNG writers park the metadata after the image data - if the
        ;; front window came up short, scan the tail of the file too
        (if (and (or (null lat) (null lon) (null absm))
                 (setq fsize (vl-file-size file))
                 (> fsize 262144)
                 (setq lst (ddg-file-bytes file 262144 T)))
          (progn
            (setq meta (ddg-read-meta lst))
            (if (null absm) (setq absm (nth 0 meta)))
            (if (null lat)  (setq lat  (nth 1 meta)))
            (if (null lon)  (setq lon  (nth 2 meta)))
            (if (nth 3 meta) (setq xmpf T))
            (if (nth 4 meta) (setq tiff T))))
        ;; 2b) say EXACTLY what is wrong if the file cannot be used - this is
        ;; a hard stop, no rescue: use the file exactly as it came off the
        ;; drone. Everything past this point lives in the final (t ...)
        ;; branch below, so a failure here truly stops the command.
        (cond
          ((and (or (null lat) (null lon)) (not xmpf) (not tiff))
           (ddg-fail "NO CAMERA METADATA IN THIS FILE"
             (list (strcat "File: " (ddg-fname file))
                   ""
                   "No XMP packet and no EXIF block anywhere in the file"
                   "(searched the first 256 KB and the last 256 KB)."
                   ""
                   "This copy was saved WITHOUT metadata - screenshots,"
                   "video frame grabs and most export / share / convert"
                   "steps strip it. Use the file exactly as it came off"
                   "the drone.")))
          ((or (null lat) (null lon))
           (ddg-fail "NO GPS DATA FOUND"
             (list (strcat "File: " (ddg-fname file))
                   ""
                   (strcat "The file DOES contain camera metadata ("
                           (cond ((and xmpf tiff) "an XMP packet and an EXIF block")
                                 (xmpf "an XMP packet")
                                 (t "an EXIF block"))
                           ")")
                   "but there is no GPS position in it."
                   ""
                   "Either the drone had no GPS fix recorded, or the"
                   "conversion that made this file kept only part of the"
                   "metadata. Use the file exactly as it came off the drone.")))
          ((and (equal lat 0.0 1e-9) (equal lon 0.0 1e-9))
           (ddg-fail "NO GPS FIX"
             (list (strcat "File: " (ddg-fname file))
                   ""
                   "The GPS position stored in the file is 0, 0 - the drone"
                   "had no satellite fix when this shot was taken."
                   ""
                   "Pick a different shot from the same flight.")))
          ((or (> (abs lat) 90.0) (> (abs lon) 180.0))
           (ddg-fail "BAD GPS DATA"
             (list (strcat "File: " (ddg-fname file))
                   ""
                   (strcat "The stored GPS position (" (ddg-n7 lat) ", "
                           (ddg-n7 lon) ")")
                   "is not a valid latitude / longitude - corrupt metadata.")))
          ((null absm)
           (ddg-fail "NO ALTITUDE DATA"
             (list (strcat "File: " (ddg-fname file))
                   ""
                   (strcat "GPS position found (" (ddg-n7 lat) ", "
                           (ddg-n7 lon) "), but the file holds no")
                   "AbsoluteAltitude / EXIF GPSAltitude."
                   ""
                   "Use the file exactly as it came off the drone, or set H"
                   "manually with DDSET.")))
          (t
           ;; 2c) all good - show what came from the file
           (princ "\n--- position & altitude ------------------------------------")
           (princ (strcat "\n  GPS position     : " (ddg-n7 lat) ", " (ddg-n7 lon)))
           (princ (strcat "\n  AbsoluteAltitude : " (ddg-n1 (* absm ddg-m->ft))
                          " ft above sea level   (" (ddg-n1 absm) " m)"))
           ;; 3) click a point in the drawing for the report
           (setq pt (getpoint "\nPick a point in the drawing for the height report: "))
           (cond
             ((null pt) (princ "\nAborted - no point picked."))
             (t
              ;; 4) ground elevation at the photo position
              (princ "\nLooking up ground elevation (internet, a few seconds) ...")
              (setq g (ddg-ground-elev lat lon))
              (if (car g)
                (setq gft (car g) gsrc (cadr g))
                (progn
                  (ddg-fail "ELEVATION LOOKUP FAILED"
                    (append
                      (list (strcat "No ground elevation could be fetched for "
                                    (ddg-n7 lat) ", " (ddg-n7 lon) ":")
                            "")
                      (cadr g)
                      (list ""
                            "Check the internet connection (DDELEV is a quick"
                            "test), or type the site elevation by hand at the"
                            "next prompt.")))
                  (setq gft  (getreal "\nGround elevation at the site in FEET, if you know it (Enter to abort): ")
                        gsrc "entered by hand")))
              (cond
                ((null gft) (princ "\nAborted - H unchanged."))
                (t
                 (princ (strcat "\n  Ground elevation : " (ddg-n1 gft) " ft   [" gsrc "]"))
                 ;; 5) the delta, rounded to the nearest foot
                 (setq absft (* absm ddg-m->ft)
                       hraw  (- absft gft)
                       hsel  (float (ddg-round hraw)))
                 (cond
                   ((<= hsel 0.0)
                    (ddg-fail "NON-PHYSICAL HEIGHT"
                      (list (strcat (ddg-n1 absft) " - " (ddg-n1 gft) " = "
                                    (ddg-n1 hraw) " ft")
                            ""
                            "That is not above ground - a big GPS error, or a"
                            "wrong ground elevation. Nothing was saved or"
                            "drawn. Set H with DDSET, or back-solve it with"
                            "DDCAL.")))
                   (t
                    (if (> hsel 400.0)
                      (princ (strcat "\n  WARNING: H = " (ddg-n1 hsel)
                                     " ft is outside the sane 0-400 ft flying range - GPS error likely.")))
                    (princ (strcat "\n  " (ddg-n1 absft) " - " (ddg-n1 gft) " = "
                                   (ddg-n1 hraw) " ft  ->  H = " (ddg-n1 hsel) " ft"))
                    ;; 6) place the report in the drawing
                    (setq ht (ddg-txt-height))
                    (setq lines
                      (list
                        (strcat "GPS position: " (ddg-n7 lat) ", " (ddg-n7 lon))
                        (strcat "Drone altitude (MSL): " (ddg-n1 absft) " ft")
                        (strcat "Ground elevation (MSL): " (ddg-n1 gft) " ft   [" gsrc "]")
                        (strcat (ddg-n1 absft) " - " (ddg-n1 gft) " = " (ddg-n1 hraw) " ft")
                        (strcat "Height above grade: " (itoa (fix hsel)) " ft")))
                    (setq placed (ddg-place-text pt lines ht (getvar "CLAYER") (getvar "TEXTSTYLE")))
                    (if (null placed)
                      (ddg-fail "COULD NOT CREATE THE ANNOTATION TEXT"
                        (list "entmake failed partway through - check whether"
                              "the current layer is locked or frozen, or the"
                              "current text style is invalid."
                              ""
                              "H is still valid below - you can still save it.")))
                    ;; 7) save H for DDFIX
                    (initget "Yes No")
                    (setq ans (getkword (strcat "\nSave H = " (ddg-n1 hsel)
                                                " ft for DDFIX? [Yes/No] <Yes>: ")))
                    (if (null ans) (setq ans "Yes"))
                    (if (= ans "Yes")
                      (progn
                        (ddg-put "H" hsel)
                        (ddg-put "GPS_LAT" lat)
                        (ddg-put "GPS_LON" lon)
                        (ddg-put "GPS_GROUND" gft)
                        (ddg-put "GPS_SRC" gsrc)
                        (princ (strcat "\nSaved drone height  H = " (ddg-n1 hsel)
                                       " ft   (DDFIX now offers it as the default)"))
                        (princ (strcat "\nDistortion rate: ~" (rtos (/ 100.0 hsel) 2 3)
                                       "% size change per unit of height.")))
                      (princ "\nH unchanged."))))))))))))))
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
     (if (car g)
       (princ (strcat "\nGround elevation: " (ddg-n1 (car g)) " ft   ("
                      (ddg-n1 (/ (car g) ddg-m->ft)) " m)   [" (cadr g) "]"))
       (ddg-fail "ELEVATION LOOKUP FAILED"
         (append
           (list (strcat "No ground elevation could be fetched for "
                         (ddg-n7 lat) ", " (ddg-n7 lon) ":")
                 "")
           (cadr g)
           (list ""
                 "Check the internet connection / firewall, then try again."))))))
  (princ))

(princ "\nDrone Height from GPS v2.0 loaded  (pick a photo, click a point, place the height report).")
(princ "\n  Commands: DDGPS  (pick drone photo -> compute + place + save H)   DDELEV  (elevation at a typed lat/long)")
(princ)
