;;; daum-dict.el --- Minimalists' English-Korean DAUM dictionary

;; Copyright (C) 2015  Junpeng Qiu

;; Author: Junpeng Qiu <qjpchmail@gmail.com>
;; URL: https://github.com/cute-jumper/bing-dict.el
;; Keywords: extensions

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; A **minimalists'** Emacs extension to search http://dic.daum.net/
;; Support English to Korean and Korean to English.

;; ## Setup

;; If installing this package manually:

;;     (add-to-list 'load-path "/path/to/daum-dict.el")
;;     (require 'daum-dict)

;; ## Usage
;; You can call `daum-dict-brief` to get the explanations of you query. The results
;; will be shown in the echo area.

;; You should probably give this command a key binding:

;;     (global-set-key (kbd "C-c d") 'daum-dict-brief)

;; ## Customization
;; You can set the value of `daum-dict-add-to-kill-ring` to control whether the
;; result should be added to the `kill-ring` or not. By default, the value is
;; `nil`. If set to `t`, the result will be added to the `kill-ring` and you are
;; able to use `C-y` to paste the result.

;; You can also build your own vocabulary by saving all your queries and their
;; results into `daum-dict-org-file` (which points to
;; `~/.emacs.d/daum-dict/vocabulary.org` by default):

;;     (setq daum-dict-save-search-result t)

;; By setting `daum-dict-org-file`, you can change where all the queries and
;; results are saved:

;;     (setq daum-dict-org-file "/path/to/your_vocabulary.org")


;;; Code:

(require 'thingatpt)

(defvar daum-dict-pronunciation-style 'us
  "Pronuciation style.
If the value is set to be `us', use the US-style pronuciation.
Otherwise, use the UK-style.")

(defvar daum-dict-show-thesaurus nil
  "Whether to show synonyms, antonyms or not.
The value could be `synonym', `antonym', `both', or nil.")

(defvar daum-dict-add-to-kill-ring nil
  "Whether the result should be added to `kill-ring'.")

(defvar daum-dict-org-file (expand-file-name "daum-dict/vocabulary.org" user-emacs-directory)
  "The file where store the vocabulary.")

(defvar daum-dict-org-file-title "Vocabulary"
  "The title of the vocabulary org file.")

(defvar daum-dict-save-search-result nil
  "Save daum dict search result or not.")

(defvar daum-dict-word-def-separator ": "
  "Seperator used between the word and the definition.")

(eval-when-compile
  (declare-function org-insert-heading "org")
  (declare-function org-insert-subheading "org"))

(defvar daum-dict-history nil)

(defvar daum-dict--base-url "http://dic.daum.net/search.do?q=")
(defvar daum-dict--no-resul-text (propertize "No results"
                                             'face
                                             'font-lock-warning-face))
(defvar daum-dict--machine-translation-text (propertize "Machine translation"
                                                        'face
                                                        'font-lock-builtin-face))
(defvar daum-dict--sounds-like-text (propertize "Sounds like"
                                                'face
                                                'font-lock-builtin-face))
(defvar daum-dict--separator (propertize " | "
                                         'face
                                         'font-lock-builtin-face))

(defun daum-dict--tidy-headlines ()
  "Remove extra spaces between stars and the headline text."
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward "^\\*+\\([[:space:]][[:space:]]+\\)" nil t)
      (replace-match " " nil nil nil 1))))

(defun daum-dict--save-word (word definition)
  "Save WORD and DEFINITION in org file.  If there is already the same WORD, ignore it."
  (let ((dir (file-name-directory daum-dict-org-file)))
    (unless (file-exists-p dir)
      (make-directory dir t)))
  (with-temp-buffer
    (when (file-exists-p daum-dict-org-file)
      (insert-file-contents daum-dict-org-file))
    (org-mode)
    (goto-char (point-min))
    (unless (re-search-forward (concat "^\\* " daum-dict-org-file-title) nil t)
      (beginning-of-line)
      (org-insert-heading)
      (insert daum-dict-org-file-title)
      (goto-char (point-min)))
    (unless (re-search-forward (concat "^\\*+ \\b" (car (split-string word)) "\\b") nil t)
      (end-of-line)
      (org-insert-subheading t)
      (insert word)
      (newline)
      (insert definition))
    (write-region nil nil daum-dict-org-file)))

(defun daum-dict--message (format-string &rest args)
  (let ((result (apply #'format format-string args)))
    (when daum-dict-save-search-result
      (let ((plain-result (substring-no-properties result)))
        (unless (or (string-match daum-dict--sounds-like-text plain-result)
                    (string-match daum-dict--no-resul-text plain-result))
          (let ((word (car (split-string plain-result
                                         daum-dict-word-def-separator)))
                (definition (nth 1 (split-string plain-result
                                                 daum-dict-word-def-separator))))
            (and word
                 definition
                 (daum-dict--save-word word definition))))))
    (when daum-dict-add-to-kill-ring
      (kill-new result))
    (message result)))

(defun daum-dict--replace-html-entities (str)
  (let ((retval str)
        (pair-list
         '(("&amp;" . "&")
           ("&hellip;" . "...")
           ("&quot;" . "\"")
           ("&#[0-9]*;" .
            (lambda (match)
              (format "%c" (string-to-number (substring match 2 -1))))))))
    (dolist (elt pair-list retval)
      (setq retval (replace-regexp-in-string (car elt) (cdr elt) retval)))))

(defun daum-dict--delete-response-header ()
  (ignore-errors
    (goto-char (point-min))
    (delete-region (point-min)
                   (1+ (re-search-forward "^$" nil t)))
    (goto-char (point-min))))

(defun daum-dict--pronunciation ()
  (let ((pron-regexp (concat "<div class=\"desc_listen"
                             (and (eq daum-dict-pronunciation-style 'us)
                                  "")
                             "\"")))
    (propertize
     (daum-dict--replace-html-entities
      (or
       (progn
         (goto-char (point-min))
         (if (re-search-forward pron-regexp nil t)
             (progn
               (goto-char (point-min))
               (when (re-search-forward (concat pron-regexp "[^[]*\\(\\[.*?\\]\\)") nil t)
                 (match-string-no-properties 1)))
           (when (re-search-forward "hd_p1_1\" lang=\"en\">\\(.*?\\)</div" nil t)
             (match-string-no-properties 1))))
       ""))
     'face
     'font-lock-comment-face)))

(defsubst daum-dict--clean-inner-html (html)
  (replace-regexp-in-string "<.*?>" "" html))

(defun daum-dict--definitions ()
  (let (defs)
    (goto-char (point-min))
    (while (re-search-forward
            "span class=\"num_search\">\\(.*?\\)</span>.*?<span class=\"txt_search\">\\(.*?\\)</span></li>"
            nil
            t)
      (let ((pos (propertize (match-string-no-properties 1)
                             'face
                             'font-lock-doc-face))
            (def (match-string-no-properties 2)))
        (push (format "%s %s" pos def) defs)))
    (goto-char (point-min))
    (when (re-search-forward
           "span class=\"pos web\">\\(.*?\\)</span>.*?<span class=\"def\">\\(.*?\\)</span></li>"
           nil
           t)
      (let ((pos (propertize (match-string-no-properties 1)
                             'face
                             'font-lock-doc-face))
            (def (match-string-no-properties 2)))
        (push (format "%s %s" pos def) defs)))
    (mapcar 'daum-dict--clean-inner-html defs)))

(defun daum-dict--thesaurus (header starting-regexp)
  (let (thesaurus)
    (goto-char (point-min))
    (when (re-search-forward starting-regexp nil t)
      (catch 'break
        (while t
          (re-search-forward
           "div class=\"de_title1\">\\(.*?\\)</div><div class=\"col_fl\">\\(.*?\\)</div>"
           nil t)
          (push (format "%s %s"
                        (propertize (match-string-no-properties 1) 'face 'font-lock-string-face)
                        (daum-dict--clean-inner-html
                         (match-string-no-properties 2)))
                thesaurus)
          (goto-char (match-end 0))
          (unless (looking-at "</div><div class=\"df_div2\">")
            (throw 'break t))))
      (format "%s %s"
              (propertize header 'face 'font-lock-doc-face)
              (mapconcat #'identity thesaurus " ")))))

(defun daum-dict--synonyms ()
  (daum-dict--thesaurus "Synonym" "div id=\"synoid\""))

(defun daum-dict--antonyms ()
  (daum-dict--thesaurus "Antonym" "div id=\"antoid\""))

(defun daum-dict--has-machine-translation-p ()
  (goto-char (point-min))
  (re-search-forward "div class=\"smt_hw\"" nil t))

(defun daum-dict--machine-translation ()
  (goto-char (point-min))
  (when (re-search-forward "div class=\"p1-11\">\\(.*?\\)</div>" nil t)
    (propertize
     (daum-dict--clean-inner-html (match-string-no-properties 1))
     'face
     'font-lock-doc-face)))

(defun daum-dict--get-sounds-like-words ()
  (goto-char (point-min))
  (when (re-search-forward "div class=\"web_div\">\\(.*?\\)<div class=\"\\(dym_area\\|dymp_sm_top\\)\"" nil t)
    (let ((similar-words "")
          (content (match-string-no-properties 1)))
      (with-temp-buffer
        (insert content)
        (goto-char (point-min))
        (while (re-search-forward "<a.*?>\\(.*?\\)</a><div.*?>\\(.*?\\)</div>" nil t)
          (setq similar-words (concat similar-words
                                      (propertize (match-string-no-properties 1)
                                                  'face
                                                  'font-lock-keyword-face)
                                      " "
                                      (match-string-no-properties 2)
                                      "; ")))
        similar-words))))

(defun daum-dict-brief-cb (status keyword)
  (set-buffer-multibyte t)
  (daum-dict--delete-response-header)
  (setq keyword (propertize keyword
                            'face
                            'font-lock-keyword-face))
  (condition-case nil
      (if (daum-dict--has-machine-translation-p)
          (daum-dict--message "%s%s%s -> %s"
                              daum-dict--machine-translation-text
                              daum-dict-word-def-separator
                              keyword
                              (daum-dict--machine-translation))
        (let ((defs (daum-dict--definitions))
              extra-defs
              pronunciation
              short-defstr)
          (if defs
              (progn
                (cond
                 ((eq daum-dict-show-thesaurus 'synonym)
                  (when (setq extra-defs (daum-dict--synonyms))
                    (push extra-defs defs)))
                 ((eq daum-dict-show-thesaurus 'antonym)
                  (when (setq extra-defs (daum-dict--antonyms))
                    (push extra-defs defs)))
                 ((eq daum-dict-show-thesaurus 'both)
                  (dolist (func '(daum-dict--synonyms daum-dict--antonyms))
                    (when (setq extra-defs (funcall func))
                      (push extra-defs defs)))))
                (setq
                 pronunciation (daum-dict--pronunciation)
                 short-defstr (mapconcat 'identity (nreverse defs)
                                         daum-dict--separator))
                (daum-dict--message "%s %s%s%s"
                                    keyword
                                    pronunciation
                                    daum-dict-word-def-separator
                                    short-defstr))
            (let ((sounds-like-words (daum-dict--get-sounds-like-words)))
              (if sounds-like-words
                  (daum-dict--message "%s%s%s"
                                      daum-dict--sounds-like-text
                                      daum-dict-word-def-separator
                                      sounds-like-words)
                (daum-dict--message daum-dict--no-resul-text))))))
    (error (daum-dict--message daum-dict--no-resul-text))))

;;;###autoload
(defun daum-dict-brief (word)
  "Show the explanation of WORD from Daum in the echo area."
  (interactive
   (let* ((default (if (use-region-p)
                       (buffer-substring-no-properties
                        (region-beginning) (region-end))
                     (let ((text (thing-at-point 'word)))
                       (if text (substring-no-properties text)))))
          (prompt (if (stringp default)
                      (format "Search Daum dict (default \"%s\"): " default)
                    "Search Daum dict: "))
          (string (read-string prompt nil 'daum-dict-history default)))
     (list string)))
  (save-match-data
    (url-retrieve (concat daum-dict--base-url
                          (url-hexify-string word))
                  'daum-dict-brief-cb
                  `(,(decode-coding-string word 'utf-8))
                  t
                  t)))

(provide 'daum-dict)
;;; daum-dict.el ends here
