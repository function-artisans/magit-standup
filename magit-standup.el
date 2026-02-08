;;; magit-standup.el --- Collect recent git commits for standup notes -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Function Artisans, Ltd.

;; Author: István Karaszi <ikaraszi@gmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (magit "4.5.0"))
;; Keywords: tools, vc
;; URL: https://github.com/function-artisans/magit-standup

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Collect recent git commits across multiple repositories and format
;; them as org-mode standup notes.  On weekends and Mondays it
;; automatically looks back to Friday; on other weekdays it looks back
;; to the previous day.  The list of repositories and the lookback
;; behavior are configurable.
;;
;; Usage:
;;   M-x magit-standup
;;
;; Customize `magit-standup-repos' to specify which repositories to
;; scan.  When nil, only the current repository is used.

;;; Code:

(require 'magit)

(defgroup magit-standup nil
  "Collect recent git commits for standup notes."
  :group 'magit
  :prefix "magit-standup-")

(defcustom magit-standup-repos nil
  "List of directory paths to collect commits from.
When nil, only the current repository is used.  Entries that are
not git repositories are searched recursively for nested repos,
up to `magit-standup-repos-max-depth' levels deep."
  :type '(repeat directory)
  :group 'magit-standup)

(defcustom magit-standup-repos-max-depth 1
  "Maximum depth to search for git repositories in non-repo directories.
When nil, search with unlimited depth."
  :type '(choice (const :tag "Unlimited" nil)
          (integer :tag "Max depth"))
  :group 'magit-standup)

(defcustom magit-standup-author nil
  "Author name or email to filter commits by.
When nil, the result of `git config user.email' is used."
  :type '(choice (const :tag "From git config" nil)
          (string :tag "Author name/email"))
  :group 'magit-standup)

(defcustom magit-standup-link-package nil
  "Package to use for linking commit hashes in org output.
When nil, auto-detect by checking if `orgit' or `org-git-link'
is loaded.  When `orgit', use orgit-rev links.  When
`org-git-link', use git links.  When `none', plain text
without links."
  :type '(choice (const :tag "Auto-detect" nil)
          (const :tag "orgit" orgit)
          (const :tag "org-git-link" org-git-link)
          (const :tag "Plain text" none))
  :group 'magit-standup)

(defcustom magit-standup-since-days-ago nil
  "Override for how many days back to look.
When nil, automatic weekday-aware logic is used: on Monday look
back to Friday (3 days), otherwise look back 1 day."
  :type '(choice (const :tag "Automatic" nil)
          (integer :tag "Days ago"))
  :group 'magit-standup)

(defun magit-standup--since-date ()
  "Return the \"since\" date string for filtering commits.
If `magit-standup-since-days-ago' is set, use it.  Otherwise,
on weekends look back to Friday; on Monday look back to Friday
\(3 days); on other weekdays look back 1 day."
  (let* ((now (current-time))
         (day (string-to-number (format-time-string "%u" now)))
         (days-ago (cond (magit-standup-since-days-ago magit-standup-since-days-ago)
                         ((<= 6 day) (- day 5))
                         ((= 1 day) 3)
                         (t 1))))
    (format-time-string "%Y-%m-%d"
                        (time-subtract now
                                       (days-to-time days-ago)))))

(defun magit-standup--find-repos (dir depth)
  "Recursively find git repositories under DIR up to DEPTH levels.
When DEPTH is nil, search with unlimited depth.  Hidden
directories are skipped."
  (cond
   ((magit-git-repo-p dir) (list dir))
   ((and depth (<= depth 0)) nil)
   (t (mapcan (lambda (child)
                (when (and (file-directory-p child)
                           (not (string-prefix-p "." (file-name-nondirectory child))))
                  (magit-standup--find-repos child (and depth (1- depth)))))
              (directory-files dir t nil t)))))

(defun magit-standup--resolve-repos (dirs)
  "Expand DIRS to a list of git repository paths.
Entries that are already git repos are kept as-is.  Others are
searched recursively up to `magit-standup-repos-max-depth'."
  (mapcan (lambda (dir)
            (magit-standup--find-repos dir magit-standup-repos-max-depth))
          dirs))

(defun magit-standup--detect-link-package ()
  "Detect which git-link package is available.
Returns `orgit' if orgit is loaded, `org-git-link' if
org-git-link is loaded, or nil if neither is available."
  (cond
   ((featurep 'orgit) 'orgit)
   ((featurep 'org-git-link) 'org-git-link)
   (t nil)))

(defun magit-standup--link-prefix (package)
  "Return the org link type string for PACKAGE.
PACKAGE should be `orgit', `org-git-link', or nil."
  (pcase package
    ('orgit "orgit-rev")
    ('org-git-link "git")
    (_ nil)))

(defun magit-standup--format-commit (repo-path line &optional link-prefix)
  "Format a commit LINE, optionally as an org link.
REPO-PATH is the repository directory.  LINE is expected to have
the hash separated from the rest by a null byte.  LINK-PREFIX is
the org link prefix string, or nil for plain text."
  (let* ((parts (split-string line "\0"))
         (hash (car parts))
         (rest (cadr parts)))
    (if link-prefix
        (concat "[[" link-prefix ":" repo-path "::" hash "][" hash "]]"
                " " rest)
      (concat hash " " rest))))

(defun magit-standup--collect-commits (repo-path since-date author)
  "Collect commits from REPO-PATH since SINCE-DATE by AUTHOR.
Returns an alist of (BRANCH-NAME . COMMITS) where COMMITS is a
list of raw commit strings with hash and message separated by a
null byte."
  (let* ((default-directory (file-name-as-directory repo-path))
         (branches (magit-git-lines "branch" "--format=%(refname:short)")))
    (mapcar (lambda (branch)
              (cons branch
                    (magit-git-lines "log"
                                     "--no-merges"
                                     "--format=%h%x00%s <%ai> - %aN"
                                     (concat "--after=" since-date)
                                     (concat "--author=" author)
                                     branch)))
            branches)))

(defun magit-standup--format-branch-commits (repo-path branch-commits &optional link-prefix)
  "Format BRANCH-COMMITS for REPO-PATH as org text.
BRANCH-COMMITS is a cons of (BRANCH-NAME . COMMITS).
LINK-PREFIX is the org link prefix string, or nil for plain text.
Returns nil when BRANCH-COMMITS has no commits."
  (when (cdr branch-commits)
    (concat "** ~" (car branch-commits) "~\n"
            (mapconcat
             (lambda (c)
               (concat "- " (magit-standup--format-commit
                             repo-path c link-prefix)))
             (cdr branch-commits) "\n")
            "\n")))

(defun magit-standup--format-org (repo-commits &optional link-prefix)
  "Format REPO-COMMITS as `org-mode' text.
REPO-COMMITS is an alist of (REPO-PATH . BRANCH-COMMITS) where
BRANCH-COMMITS is an alist of (BRANCH-NAME . COMMITS).
LINK-PREFIX is the org link prefix string, or nil for plain text."
  (mapconcat
   (lambda (entry)
     (let* ((repo-path (car entry))
            (repo-name (file-name-nondirectory
                        (directory-file-name repo-path)))
            (formatted (delq nil
                             (mapcar
                              (lambda (bc)
                                (magit-standup--format-branch-commits
                                 repo-path bc link-prefix))
                              (cdr entry)))))
       (if formatted
           (concat "* " repo-name "\n"
                   (mapconcat #'identity formatted "\n"))
         (concat "* " repo-name "\n- (no commits)\n"))))
   repo-commits
   "\n"))

(defun magit-standup--gather ()
  "Gather recent commits across all configured repositories.
Returns an alist of (REPO-PATH . BRANCH-COMMITS) suitable for
`magit-standup--format-org'."
  (let* ((since-date (magit-standup--since-date))
         (author (or magit-standup-author
                     (magit-git-string "config" "user.email")
                     (user-error "Cannot determine author; set `magit-standup-author' or git config user.email")))
         (repos (or (magit-standup--resolve-repos magit-standup-repos)
                    (list (magit-toplevel)))))
    (mapcar (lambda (repo)
              (cons repo
                    (magit-standup--collect-commits repo since-date author)))
            repos)))

;;;###autoload
(defun magit-standup ()
  "Display recent git commits as `org-mode' standup notes.
Collects commits from all repos in `magit-standup-repos' (or the
current repo if that is nil) and displays them in a
`*magit-standup*' buffer."
  (interactive)
  (let* ((repo-commits (magit-standup--gather))
         (link-package (or magit-standup-link-package
                           (magit-standup--detect-link-package)))
         (buf (get-buffer-create "*magit-standup*"))
         (link-prefix (magit-standup--link-prefix link-package)))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (magit-standup--format-org repo-commits link-prefix)))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buf)))

(provide 'magit-standup)

;;; magit-standup.el ends here
