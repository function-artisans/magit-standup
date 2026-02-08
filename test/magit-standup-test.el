;;; magit-standup-test.el --- Tests for magit-standup -*- lexical-binding: t; -*-

;;; Commentary:

;; Buttercup tests for magit-standup.

;;; Code:

(require 'buttercup)
(require 'magit-standup)

(describe "magit-standup--since-date"
  (it "looks back 3 days on Monday (to Friday)"
    ;; Monday 2026-01-05 12:00:00 UTC — %u = 1
    (let ((magit-standup-since-days-ago nil))
      (cl-letf (((symbol-function 'current-time)
                 (lambda () (encode-time 0 0 12 5 1 2026))))
        (expect (magit-standup--since-date) :to-equal "2026-01-02"))))

  (it "looks back 1 day on Tuesday"
    ;; Tuesday 2026-01-06 12:00:00 UTC — %u = 2
    (let ((magit-standup-since-days-ago nil))
      (cl-letf (((symbol-function 'current-time)
                 (lambda () (encode-time 0 0 12 6 1 2026))))
        (expect (magit-standup--since-date) :to-equal "2026-01-05"))))

  (it "looks back 1 day on Wednesday"
    ;; Wednesday 2026-01-07 12:00:00 UTC — %u = 3
    (let ((magit-standup-since-days-ago nil))
      (cl-letf (((symbol-function 'current-time)
                 (lambda () (encode-time 0 0 12 7 1 2026))))
        (expect (magit-standup--since-date) :to-equal "2026-01-06"))))

  (it "looks back to Friday on Saturday (1 day)"
    ;; Saturday 2026-01-10 12:00:00 UTC — %u = 6
    (let ((magit-standup-since-days-ago nil))
      (cl-letf (((symbol-function 'current-time)
                 (lambda () (encode-time 0 0 12 10 1 2026))))
        (expect (magit-standup--since-date) :to-equal "2026-01-09"))))

  (it "looks back to Friday on Sunday (2 days)"
    ;; Sunday 2026-01-11 12:00:00 UTC — %u = 7
    (let ((magit-standup-since-days-ago nil))
      (cl-letf (((symbol-function 'current-time)
                 (lambda () (encode-time 0 0 12 11 1 2026))))
        (expect (magit-standup--since-date) :to-equal "2026-01-09"))))

  (it "uses custom override when magit-standup-since-days-ago is set"
    ;; Wednesday 2026-01-07 — would normally be 1 day back
    (let ((magit-standup-since-days-ago 7))
      (cl-letf (((symbol-function 'current-time)
                 (lambda () (encode-time 0 0 12 7 1 2026))))
        (expect (magit-standup--since-date) :to-equal "2025-12-31")))))

(describe "magit-standup--detect-link-package"
  (it "returns orgit when orgit is loaded"
    (cl-letf (((symbol-function 'featurep)
               (lambda (f) (eq f 'orgit))))
      (expect (magit-standup--detect-link-package) :to-be 'orgit)))

  (it "returns org-git-link when org-git-link is loaded"
    (cl-letf (((symbol-function 'featurep)
               (lambda (f) (eq f 'org-git-link))))
      (expect (magit-standup--detect-link-package) :to-be 'org-git-link)))

  (it "returns nil when nothing is loaded"
    (cl-letf (((symbol-function 'featurep)
               (lambda (_) nil)))
      (expect (magit-standup--detect-link-package) :to-be nil))))

(describe "magit-standup--link-prefix"
  (it "returns orgit-rev for orgit"
    (expect (magit-standup--link-prefix 'orgit) :to-equal "orgit-rev"))

  (it "returns git for org-git-link"
    (expect (magit-standup--link-prefix 'org-git-link) :to-equal "git"))

  (it "returns nil for none"
    (expect (magit-standup--link-prefix 'none) :to-be nil))

  (it "returns nil for nil"
    (expect (magit-standup--link-prefix nil) :to-be nil)))

(describe "magit-standup--format-commit"
  (it "formats with orgit-rev link"
    (expect (magit-standup--format-commit "/home/user/repo" "abc123\0Fix bug <2026-01-05> Alice" "orgit-rev")
            :to-equal "[[orgit-rev:/home/user/repo::abc123][abc123]] Fix bug <2026-01-05> Alice"))

  (it "formats with git link"
    (expect (magit-standup--format-commit "/home/user/repo" "abc123\0Fix bug <2026-01-05> Alice" "git")
            :to-equal "[[git:/home/user/repo::abc123][abc123]] Fix bug <2026-01-05> Alice"))

  (it "formats as plain text when link-type is omitted"
    (expect (magit-standup--format-commit "/home/user/repo" "abc123\0Fix bug <2026-01-05> Alice")
            :to-equal "abc123 Fix bug <2026-01-05> Alice")))

(describe "magit-standup--collect-commits"
  (it "sets default-directory to the repo path"
    (let (captured-dirs)
      (spy-on 'magit-git-lines :and-call-fake
              (lambda (&rest _)
                (push default-directory captured-dirs)
                nil))
      (magit-standup--collect-commits "/tmp/my-repo" "2026-01-05" "alice")
      (expect captured-dirs :not :to-be nil)
      (dolist (dir captured-dirs)
        (expect dir :to-equal "/tmp/my-repo/")))))

(describe "magit-standup--resolve-repos"
  :var (tmpdir)

  (before-each
    (setq tmpdir (make-temp-file "standup-test-" t))
    ;; Create a git repo at tmpdir/repo-a
    (let ((repo-a (expand-file-name "repo-a" tmpdir)))
      (make-directory repo-a)
      (make-directory (expand-file-name ".git" repo-a)))
    ;; Create a git repo at tmpdir/repo-b
    (let ((repo-b (expand-file-name "repo-b" tmpdir)))
      (make-directory repo-b)
      (make-directory (expand-file-name ".git" repo-b)))
    ;; Create a non-repo dir with a nested repo at tmpdir/parent/nested
    (let ((nested (expand-file-name "parent/nested" tmpdir)))
      (make-directory nested t)
      (make-directory (expand-file-name ".git" nested)))
    ;; Create a hidden dir with a repo inside (should be skipped)
    (let ((hidden (expand-file-name ".hidden/secret-repo" tmpdir)))
      (make-directory hidden t)
      (make-directory (expand-file-name ".git" hidden))))

  (after-each
    (delete-directory tmpdir t))

  (it "returns nil for nil input"
    (let ((magit-standup-repos-max-depth 1))
      (expect (magit-standup--resolve-repos nil) :to-be nil)))

  (it "returns a git repo directory as-is"
    (let ((magit-standup-repos-max-depth 1)
          (repo-a (expand-file-name "repo-a" tmpdir)))
      (expect (magit-standup--resolve-repos (list repo-a))
              :to-equal (list repo-a))))

  (it "discovers repos in immediate subdirectories"
    (let ((magit-standup-repos-max-depth 1))
      (let ((result (sort (magit-standup--resolve-repos (list tmpdir)) #'string<)))
        (expect result :to-equal
                (sort (list (expand-file-name "repo-a" tmpdir)
                            (expand-file-name "repo-b" tmpdir))
                      #'string<)))))

  (it "discovers nested repos with sufficient depth"
    (let ((magit-standup-repos-max-depth 2))
      (let ((result (sort (magit-standup--resolve-repos (list tmpdir)) #'string<)))
        (expect result :to-contain
                (expand-file-name "parent/nested" tmpdir)))))

  (it "stops at depth 0"
    (let ((magit-standup-repos-max-depth 0))
      (expect (magit-standup--resolve-repos (list tmpdir)) :to-be nil)))

  (it "searches unlimited depth when max-depth is nil"
    (let ((magit-standup-repos-max-depth nil))
      (let ((result (magit-standup--resolve-repos (list tmpdir))))
        (expect result :to-contain
                (expand-file-name "parent/nested" tmpdir)))))

  (it "skips hidden directories"
    (let ((magit-standup-repos-max-depth nil))
      (let ((result (magit-standup--resolve-repos (list tmpdir))))
        (expect result :not :to-contain
                (expand-file-name ".hidden/secret-repo" tmpdir))))))

(describe "magit-standup--format-org"
  (it "formats branch commits with subheadings"
    (expect (magit-standup--format-org
             '(("/home/user/my-repo" . (("main" . ("abc123\0Fix bug"
                                                   "def456\0Add feature")))))
             nil)
            :to-equal
            "* my-repo\n** ~main~\n- abc123 Fix bug\n- def456 Add feature\n"))

  (it "shows placeholder when all branches have no commits"
    (expect (magit-standup--format-org
             '(("/home/user/empty-repo" . (("main") ("develop"))))
             nil)
            :to-equal
            "* empty-repo\n- (no commits)\n"))

  (it "skips branches with no commits"
    (expect (magit-standup--format-org
             '(("/home/user/my-repo" . (("main" . ("abc\0Fix thing"))
                                        ("stale-branch"))))
             nil)
            :to-equal
            "* my-repo\n** ~main~\n- abc Fix thing\n"))

  (it "shows multiple branches under one repo"
    (expect (magit-standup--format-org
             '(("/home/user/my-repo" . (("main" . ("abc\0Fix thing"))
                                        ("feature" . ("def\0Add thing")))))
             nil)
            :to-equal
            (concat "* my-repo\n** ~main~\n- abc Fix thing\n"
                    "\n** ~feature~\n- def Add thing\n")))

  (it "separates multiple repos with blank lines"
    (expect (magit-standup--format-org
             '(("/home/user/repo-a" . (("main" . ("abc\0Fix thing"))))
               ("/home/user/repo-b" . (("develop" . ("def\0Other thing")))))
             nil)
            :to-equal
            (concat "* repo-a\n** ~main~\n- abc Fix thing\n"
                    "\n"
                    "* repo-b\n** ~develop~\n- def Other thing\n")))

  (it "applies link-package to commits"
    (expect (magit-standup--format-org
             '(("/home/user/my-repo" . (("main" . ("abc\0Fix thing")))))
             "orgit-rev")
            :to-equal
            "* my-repo\n** ~main~\n- [[orgit-rev:/home/user/my-repo::abc][abc]] Fix thing\n")))

(describe "magit-standup--gather"
  (before-each
    (spy-on 'magit-standup--since-date :and-return-value "2026-01-05")
    (spy-on 'magit-standup--collect-commits :and-return-value
            '(("main" . ("abc Fix thing"))))
    (spy-on 'magit-standup--resolve-repos :and-call-fake #'identity))

  (it "uses magit-standup-author when set"
    (let ((magit-standup-repos '("/tmp/repo")))
      (spy-on 'magit-git-string)
      (let ((magit-standup-author "alice"))
        (magit-standup--gather))
      (expect 'magit-standup--collect-commits
              :to-have-been-called-with "/tmp/repo" "2026-01-05" "alice")
      (expect 'magit-git-string :not :to-have-been-called)))

  (it "falls back to git config user.email"
    (let ((magit-standup-repos '("/tmp/repo"))
          (magit-standup-author nil))
      (spy-on 'magit-git-string :and-return-value "bob@example.com")
      (magit-standup--gather)
      (expect 'magit-standup--collect-commits
              :to-have-been-called-with "/tmp/repo" "2026-01-05" "bob@example.com")))

  (it "signals error when no author can be determined"
    (let ((magit-standup-repos '("/tmp/repo"))
          (magit-standup-author nil))
      (spy-on 'magit-git-string :and-return-value nil)
      (expect (magit-standup--gather) :to-throw 'user-error)))

  (it "uses magit-standup-repos when set"
    (let ((magit-standup-repos '("/tmp/a" "/tmp/b"))
          (magit-standup-author "alice"))
      (let ((result (magit-standup--gather)))
        (expect (mapcar #'car result) :to-equal '("/tmp/a" "/tmp/b")))))

  (it "falls back to magit-toplevel when repos is nil"
    (let ((magit-standup-repos nil)
          (magit-standup-author "alice"))
      (spy-on 'magit-toplevel :and-return-value "/home/user/my-project")
      (let ((result (magit-standup--gather)))
        (expect (mapcar #'car result) :to-equal '("/home/user/my-project"))))))

;;; magit-standup-test.el ends here
