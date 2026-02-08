((emacs-lisp-mode
  . ((eval . (progn
               (require 'package)
               (add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/") t)
               (unless (assoc "magit" package-archive-contents)
                 (package-refresh-contents)))))))
