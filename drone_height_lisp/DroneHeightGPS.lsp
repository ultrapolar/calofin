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
;;;  PNG, JPG/JPEG, TIFF and DJI .SRT flight logs are all understood. The
;;;  reader does not trust the file extension - it looks for the metadata
;;;  containers themselves:
;;;    * XMP text packet   - JPEG APP1, PNG iTXt chunk, or anywhere else the
;;;                          "<x:xmpmeta" packet appears; both DJI's normal
;;;                          attribute form (Tag="...") and the element form
;;;                          (<ns:Tag>...</ns:Tag>) some converters re-write.
;;;    * binary EXIF GPS   - JPEG "Exif\0\0" APP1 block, PNG eXIf chunk, or a
;;;                          bare TIFF header (a .TIF file), either byte order.
;;;    * hex text profiles - ImageMagick-converted files ("Raw profile type
;;;                          exif/xmp/APP1" chunks) are hex-decoded and parsed.
;;;    * DJI flight log    - .SRT subtitle files written next to videos:
;;;                          [latitude: ...] [longitude: ...] [rel_alt: ...
;;;                          abs_alt: ...] from the first video frame.
;;;  The first 256 KB of the file is scanned; if nothing is found there the
;;;  LAST 256 KB is scanned too (PNG writers may park metadata after the image
;;;  data).
;;;
;;;  VIDEO FRAME GRABS / SCREENSHOTS - files with NO metadata at all
;;;  ---------------------------------------------------------------
;;;  A 1080p/4K frame saved out of a video, or a screenshot, carries nothing
;;;  to read. DDGPS says so - loudly - and then CONTINUES instead of giving
;;;  up: paste the pool's coordinates (right-click the pool in Google Maps
;;;  and click the coordinates line to copy them), the ground elevation is
;;;  still fetched automatically, and the flight height is typed from the
;;;  DJI app / flight log / the H value burned into the video's on-screen
;;;  display (accepts feet, or metres with a trailing m: "30.5m").
;;;  If captions were on, the video's .SRT file has it all - pick that
;;;  instead of the frame grab and everything is automatic.
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
;;;  FAILURE REPORTING
;;;  -----------------
;;;  Every failure is LOUD: a dialog box pops up saying exactly WHAT failed
;;;  and HOW - "no camera metadata in this file", "no GPS data found",
;;;  "no GPS fix (position is 0,0)", "no altitude data", or which elevation
;;;  service failed and why (no answer / HTTP error / outside coverage) -
;;;  and the same detail is printed on the command line for the record.
;;;  The only quiet exits are the ones you choose yourself (cancelling the
;;;  file dialog or pressing Enter at an abort prompt).
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
  (list lat lon altm (if tif T)))     ; 4th: was an EXIF block found at all?

;; hex digit byte -> value, nil if not hex
(defun ddg-hexval (b)
  (cond ((and (>= b 48) (<= b 57))  (- b 48))     ; 0-9
        ((and (>= b 97) (<= b 102)) (- b 87))     ; a-f
        ((and (>= b 65) (<= b 70))  (- b 55))))   ; A-F

;; ImageMagick-style hex profile. Some converters re-write the metadata into
;; a PNG tEXt chunk called "Raw profile type exif" / "xmp" / "APP1" holding
;;   \0 \n <name> \n <length> \n <hex, 72 chars per line>
;; Skips the header lines, hex-decodes the body (up to 64 KB) and returns the
;; decoded bytes as a list, or nil if the profile is not in the file.
(defun ddg-hex-after (lst anchor / rest nl b v hi acc cnt done)
  (setq rest (ddg-scan-to lst (vl-string->list anchor)))
  (if rest
    (progn
      (setq nl 0)                                  ; skip to past the 3rd \n
      (while (and rest (< nl 3))
        (setq b (car rest) rest (cdr rest))
        (if (= b 10) (setq nl (1+ nl))))
      (setq acc '() cnt 0 hi nil done nil)
      (while (and rest (not done) (< cnt 65536))
        (setq b (car rest) rest (cdr rest))
        (if (< b 0) (setq b (+ b 256)))
        (cond
          ((or (= b 10) (= b 13) (= b 32)))        ; skip line breaks / blanks
          ((setq v (ddg-hexval b))
           (if hi
             (setq acc (cons (+ (* 16 hi) v) acc) hi nil cnt (1+ cnt))
             (setq hi v)))
          (t (setq done t))))                      ; first non-hex byte = end
      (if acc (reverse acc)))))

;; everything the file tells us: (absalt-m relalt-m lat lon xmp-found exif-found)
;; Tried in order, each later step filling whatever is still missing:
;;   1. XMP text packet          (JPEG APP1 / PNG iTXt)
;;   2. binary EXIF GPS block    (JPEG APP1 / PNG eXIf / bare TIFF)
;;   3. ImageMagick hex profiles ("Raw profile type ..." tEXt chunks)
;;   4. DJI flight-log text      (.SRT subtitle files: [latitude: ...] tags)
;; The last two flags say whether an XMP packet / EXIF block was present at
;; all - failure reporting uses them to tell "stripped file" apart from
;; "metadata without GPS".
(defun ddg-read-meta (lst / xtxt exif blob rest txt absm relm lat lon xmpf tiff)
  (setq xtxt (ddg-xmp-text lst))
  (setq xmpf (> (strlen xtxt) 0))
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
      (if (null absm) (setq absm (caddr exif)))
      (setq tiff (cadddr exif))))
  (if (or (null lat) (null lon) (null absm))
    (progn
      (setq blob (ddg-hex-after lst "Raw profile type exif"))
      (if (null blob) (setq blob (ddg-hex-after lst "Raw profile type APP1")))
      (if blob
        (progn
          (setq exif (ddg-exif-gps blob))
          (if (null lat)  (setq lat  (car exif)))
          (if (null lon)  (setq lon  (cadr exif)))
          (if (null absm) (setq absm (caddr exif)))
          (if (cadddr exif) (setq tiff T))))
      (setq blob (ddg-hex-after lst "Raw profile type xmp"))
      (if blob
        (progn
          (setq xtxt (ddg-grab-text blob 6144))
          (setq xmpf T)
          (if (null absm) (setq absm (ddg-xmp-num xtxt "AbsoluteAltitude")))
          (if (null relm) (setq relm (ddg-xmp-num xtxt "RelativeAltitude")))
          (if (null lat)  (setq lat  (ddg-xmp-num xtxt "GpsLatitude")))
          (if (null lon)  (setq lon  (ddg-xmp-num xtxt "GpsLongitude")))
          (if (null lon)  (setq lon  (ddg-xmp-num xtxt "GpsLongtitude")))))))
  (if (or (null lat) (null lon))
    (progn
      (setq rest (ddg-scan-to lst (vl-string->list "latitude")))
      (if rest
        (progn
          (setq txt (strcat "latitude" (ddg-grab-text rest 2048)))
          (if (null lat)  (setq lat  (ddg-num-after txt "latitude")))
          (if (null lon)  (setq lon  (ddg-num-after txt "longitude")))
          (if (null absm) (setq absm (ddg-num-after txt "abs_alt")))
          (if (null relm) (setq relm (ddg-num-after txt "rel_alt")))))))
  (list absm relm lat lon xmpf tiff))

;; is the position unusable?  (missing / 0,0 "no fix" / out of range)
(defun ddg-badpos (lat lon)
  (or (null lat) (null lon)
      (and (equal lat 0.0 1e-9) (equal lon 0.0 1e-9))
      (> (abs lat) 90.0) (> (abs lon) 180.0)))

;; "32.715738, -117.161084" (comma or space separated) -> (lat lon), or nil
(defun ddg-parse-latlon (s / pos lat lon)
  (setq s (vl-string-trim " \t" s))
  (setq pos (vl-string-search "," s))
  (if (null pos) (setq pos (vl-string-search " " s)))
  (if pos
    (setq lat (ddg-numstr (substr s 1 pos))
          lon (ddg-numstr (vl-string-trim " ," (substr s (+ pos 2))))))
  (if (and lat lon (<= (abs lat) 90.0) (<= (abs lon) 180.0)
           (not (and (equal lat 0.0 1e-9) (equal lon 0.0 1e-9))))
    (list lat lon)))

;; height string -> FEET: plain number = feet, trailing m/M = metres (30.5m)
(defun ddg-parse-ft (s / v)
  (setq s (vl-string-trim " \t" s))
  (cond
    ((= s "") nil)
    ((= (strcase (substr s (strlen s) 1)) "M")
     (setq v (ddg-numstr (vl-string-trim " " (substr s 1 (1- (strlen s))))))
     (if v (* v ddg-m->ft)))
    (t (ddg-numstr s))))

;; ask for coordinates pasted as one line; alerts (loud) on unreadable input
(defun ddg-ask-coords ( / s pt)
  (setq s (getstring T "\nPool coordinates as  lat, long  (paste from Google Maps; Enter to abort): "))
  (if (= (vl-string-trim " \t" s) "")
    nil
    (progn
      (setq pt (ddg-parse-latlon s))
      (if (null pt)
        (ddg-fail "BAD COORDINATES"
          (list (strcat "Could not read a latitude / longitude out of:  " s)
                ""
                "Paste them like:  32.715738, -117.161084"
                "(Google Maps: right-click the pool, then click the"
                "coordinates on the top line to copy them.)")))
      pt)))

;; ask for a height in feet (trailing m = metres); nil if left blank
(defun ddg-ask-ft (prompt)
  (ddg-parse-ft (getstring T prompt)))

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
;; between; shared by the JSON answers and the DJI flight-log text; nil on
;; null / absent
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

;; ---------------------------------------------------------------------------
;;  DDGPS : pick the drone image -> read GPS -> look up ground -> save H
;; ---------------------------------------------------------------------------
(defun c:DDGPS ( / *error* def c file lst meta fsize absm relm lat lon xmpf tiff
                   pt man askedh g gft gsrc absft relft hgps hrel diff ans hsel)
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
  (setq file (getfiled "Select the drone image (PNG / JPG / TIF) or its .SRT flight log" def
                       "png;jpg;jpeg;tif;tiff;srt" 20)) ; 16 path-only + 4 any ext
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
              absm (nth 0 meta) relm (nth 1 meta)
              lat  (nth 2 meta) lon  (nth 3 meta)
              xmpf (nth 4 meta) tiff (nth 5 meta))
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
            (if (null lon)  (setq lon  (nth 3 meta)))
            (if (nth 4 meta) (setq xmpf T))
            (if (nth 5 meta) (setq tiff T))))
        ;; 2b) say EXACTLY what is wrong if the file cannot be used
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
                   "steps strip it."
                   ""
                   "You can still continue: paste the pool's coordinates at"
                   "the next prompt (Google Maps: right-click the pool and"
                   "click the coordinates to copy them), or re-run DDGPS on"
                   "the video's .SRT flight log if there is one.")))
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
                   "metadata."
                   ""
                   "You can still continue: paste the pool's coordinates at"
                   "the next prompt (Google Maps: right-click the pool and"
                   "click the coordinates to copy them).")))
          ((and (equal lat 0.0 1e-9) (equal lon 0.0 1e-9))
           (ddg-fail "NO GPS FIX"
             (list (strcat "File: " (ddg-fname file))
                   ""
                   "The GPS position stored in the file is 0, 0 - the drone"
                   "had no satellite fix when this shot was taken."
                   ""
                   "Pick a different shot from the same flight, or continue"
                   "by pasting the pool's coordinates at the next prompt"
                   "(Google Maps: right-click the pool to copy them).")))
          ((or (> (abs lat) 90.0) (> (abs lon) 180.0))
           (ddg-fail "BAD GPS DATA"
             (list (strcat "File: " (ddg-fname file))
                   ""
                   (strcat "The stored GPS position (" (ddg-n7 lat) ", "
                           (ddg-n7 lon) ")")
                   "is not a valid latitude / longitude - corrupt metadata."
                   ""
                   "You can still continue: paste the pool's coordinates at"
                   "the next prompt (Google Maps: right-click the pool and"
                   "click the coordinates to copy them).")))
          ((and (null absm) (null relm))
           (ddg-fail "NO ALTITUDE DATA"
             (list (strcat "File: " (ddg-fname file))
                   ""
                   (strcat "GPS position found (" (ddg-n7 lat) ", "
                           (ddg-n7 lon) "), but the file holds NO altitude:")
                   "XMP AbsoluteAltitude, XMP RelativeAltitude and EXIF"
                   "GPSAltitude are all missing."
                   ""
                   "DDGPS will continue: it looks up the ground elevation,"
                   "then asks you for the flight height (the DJI app / log"
                   "shows it; on video frames it is burned into the display)."))))
        ;; 2c) manual rescue - no usable position in the file, so ask for one
        (if (ddg-badpos lat lon)
          (progn
            (setq pt (ddg-ask-coords))
            (if pt (setq lat (car pt) lon (cadr pt) man T))))
        ;; 2d) proceed only with a usable position
        (cond
          ((ddg-badpos lat lon)
           (princ "\nDDGPS aborted - no usable position."))
          (t
           (princ "\n--- position & altitude ------------------------------------")
           (princ (strcat "\n  GPS position     : " (ddg-n7 lat) ", " (ddg-n7 lon)
                          (if man "   (typed by hand)" "   (from the file)")))
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
              (if absm (setq absft (* absm ddg-m->ft) hgps (- absft gft)))
              (if relm (setq relft (* relm ddg-m->ft)))
              ;; nothing usable came from the file? type the flight height
              (if (and (null absft) (null relft))
                (progn
                  (princ "\nNo altitude came from the file - type the flight height instead.")
                  (princ "\n  The DJI app / flight log shows it; on video frame grabs it is")
                  (princ "\n  burned into the on-screen display (e.g. \"H 30.5m\").")
                  (setq relft  (ddg-ask-ft "\nDrone height above TAKE-OFF, in FEET (add m for metres, e.g. 30.5m; Enter to abort): ")
                        askedh T)))
              (if relft (setq hrel relft))
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
                (t
                 (if askedh
                   (princ "\nNo height given - H unchanged.")     ; user's abort
                   (ddg-fail "NO USABLE HEIGHT"
                     (list
                       (if absft
                         (strcat "GPS method:  " (ddg-n1 absft) " - " (ddg-n1 gft)
                                 " = " (ddg-n1 (- absft gft)) " ft")
                         "GPS method:  no absolute altitude in the file")
                       (if relft
                         (strcat "Barometer method:  " (ddg-n1 relft) " ft")
                         "Barometer method:  no RelativeAltitude in the file")
                       ""
                       "Neither method gave a height above 0 ft - a big GPS"
                       "error, or a wrong ground elevation. Nothing was saved."
                       "Set H with DDSET, or back-solve it with DDCAL.")))))
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

(princ "\nDrone Height from GPS v1.3 loaded  (PNG / JPG / TIF / DJI .SRT logs; metadata-free frame grabs")
(princ "\n  continue with typed coordinates instead of failing).")
(princ "\n  Commands: DDGPS  (pick drone image -> compute + save H)   DDELEV  (elevation at a typed lat/long)")
(princ)
