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
;; them as org-mode standup notes.  On Mondays it automatically looks
;; back to Friday; otherwise it looks back to the previous day.  The
;; list of repositories and the lookback behavior are configurable.
;;
;; Usage:
;;   M-x magit-standup
;;
;; Customize `magit-standup-repos' to specify which repositories to
;; scan.  When nil, only the current repository is used.

;;; Code:

(require 'magit)
(require 'seq)

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

(defcustom magit-standup-since-days-ago nil
  "Override for how many days back to look.
When nil, automatic weekday-aware logic is used: on Monday look
back to Friday (3 days), otherwise look back 1 day."
  :type '(choice (const :tag "Automatic" nil)
          (integer :tag "Days ago"))
  :group 'magit-standup)

(defun magit-standup--since-date ()
  "Return the \"since\" date string for filtering commits.
If `magit-standup-since-days-ago' is set, use it.  Otherwise, if
today is Monday use last Friday; else use yesterday."
  (let* ((now (current-time))
         (day (string-to-number (format-time-string "%u" now)))
         (days-ago (cond (magit-standup-since-days-ago magit-standup-since-days-ago)
                         ((<= 6 day) (- day 5))
                         ((= 1 day) 3)
                         (t 1))))
    (format-time-string "%Y-%m-%d"
                        (time-subtract now
                                       (days-to-time days-ago)))))

(defun magit-standup--git-repo-p (dir)
  "Return non-nil if DIR contains a `.git' directory or file."
  (file-directory-p (expand-file-name ".git" dir)))

(defun magit-standup--find-repos (dir depth)
  "Recursively find git repositories under DIR up to DEPTH levels.
When DEPTH is nil, search with unlimited depth.  Hidden
directories are skipped."
  (cond
   ((magit-standup--git-repo-p dir) (list dir))
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

(defun magit-standup--collect-commits (repo-path since-date author)
  "Collect commits from REPO-PATH since SINCE-DATE by AUTHOR.
Returns an alist of (BRANCH-NAME . COMMITS) where COMMITS is a
list of commit message strings."
  (let* ((default-directory (file-name-as-directory repo-path))
         (branches (magit-git-lines "branch" "--format=%(refname:short)")))
    (mapcar (lambda (branch)
              (cons branch
                    (magit-git-lines "log" "--oneline"
                                     (concat "--after=" since-date)
                                     (concat "--author=" author)
                                     branch)))
            branches)))

(defun magit-standup--format-org (repo-commits)
  "Format REPO-COMMITS as `org-mode' text.
REPO-COMMITS is an alist of (REPO-NAME . BRANCH-COMMITS) where
BRANCH-COMMITS is an alist of (BRANCH-NAME . COMMITS)."
  (mapconcat
   (lambda (entry)
     (let* ((repo-name (car entry))
            (branch-commits (cdr entry))
            (active (seq-filter #'cdr branch-commits)))
       (if active
           (concat "* " repo-name "\n"
                   (mapconcat
                    (lambda (bc)
                      (concat "** ~" (car bc) "~\n"
                              (mapconcat (lambda (c) (concat "- " c))
                                         (cdr bc) "\n")
                              "\n"))
                    active
                    "\n"))
         (concat "* " repo-name "\n- (no commits)\n"))))
   repo-commits
   "\n"))

(defun magit-standup--gather ()
  "Gather recent commits across all configured repositories.
Returns an alist of (REPO-NAME . BRANCH-COMMITS) suitable for
`magit-standup--format-org'."
  (let* ((since-date (magit-standup--since-date))
         (author (or magit-standup-author
                     (magit-git-string "config" "user.email")
                     (user-error "Cannot determine author; set `magit-standup-author' or git config user.email")))
         (repos (or (magit-standup--resolve-repos magit-standup-repos)
                    (list (magit-toplevel)))))
    (mapcar (lambda (repo)
              (cons (file-name-nondirectory
                     (directory-file-name repo))
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
         (buf (get-buffer-create "*magit-standup*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (magit-standup--format-org repo-commits)))
      (goto-char (point-min))
      (org-mode))
    (pop-to-buffer buf)))

(provide 'magit-standup)

;;; magit-standup.el ends here
