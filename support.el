;; These are just some functions I use to deconstruct ADS queries that
;; have been created by the Webform interface, to understnad the API
;; better.  This file is not needed to run `ads'.

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
