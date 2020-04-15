(defconst ads-encode-alist
  '(("\"" . "%22")
    (" " . "%20")
    ("," . "%2C")
    ("$" . "%24")
    ("^" . "%5E")
    (":" . "%3A")
    ("{" . "%7B")
    ("}" . "%7D")
    ("=" . "%3D")
    ))

(setq ads-encode-re (concat "[" (mapconcat 'car ads-encode-alist "") "]"))
(setq ads-decode-re (concat "" (mapconcat 'cdr ads-encode-alist "\\|") ""))



(defun ads-encode-region (beg end)
  (interactive "r")
  (goto-char end)
  (while (re-search-backward ads-encode-re beg t)
    (replace-match (cdr (assoc (match-string 0) ads-encode-alist)) t t)))

(defun ads-decode-region (beg end)
  (interactive "r")
  (goto-char end)
  (while (re-search-backward ads-decode-re beg t)
    (replace-match (car (rassoc (match-string 0) ads-encode-alist)) t t)))




; https://ui.adsabs.harvard.edu/search/q= author:"dominik,c"&sort=date desc, bibcode desc&p_=0

; https://ui.adsabs.harvard.edu/search/filter_database_fq_database=AND&filter_database_fq_database=database:"astronomy"&fq={!type=aqp v=$fq_database}&fq_database=(database:"astronomy")&q= author:"dominik,c"&sort=date desc, bibcode desc&p_=0


;  https://ui.adsabs.harvard.edu/search/filter_database_fq_database=OR&filter_database_fq_database=database:"physics"&filter_database_fq_database=database:"astronomy"&fq={!type=aqp v=$fq_database}&fq_database=(database:"physics" OR database:"astronomy")&p_=0&q= author:"dominik,c"&sort=date desc, bibcode desc
