# daum-dict.el

A **minimalists'** Emacs extension to search http://dic.daum.net/
Support English to Korean and Korean to English.

It's originated from [bing-dict.el](https://github.com/cute-jumper/bing-dict.el)

## Setup

If installing this package manually:

    (add-to-list 'load-path "/path/to/daum-dict.el")
    (require 'daum-dict)

## Usage
You can call `daum-dict-brief` to get the explanations of you query. The results
will be shown in the echo area.

You should probably give this command a key binding:

    (global-set-key (kbd "C-c d") 'daum-dict-brief)

## Customization
You can set the value of `daum-dict-add-to-kill-ring` to control whether the
result should be added to the `kill-ring` or not. By default, the value is
`nil`. If set to `t`, the result will be added to the `kill-ring` and you are
able to use `C-y` to paste the result.

You can also build your own vocabulary by saving all your queries and their
results into `daum-dict-org-file` (which points to
`~/.emacs.d/daum-dict/vocabulary.org` by default):

    (setq daum-dict-save-search-result t)

By setting `daum-dict-org-file`, you can change where all the queries and
results are saved:

    (setq daum-dict-org-file "/path/to/your_vocabulary.org")
