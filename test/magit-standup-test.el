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

(describe "magit-standup--format-org"
  (it "formats branch commits with subheadings"
    (expect (magit-standup--format-org
             '(("my-repo" . (("main" . ("abc123 Fix bug"
                                         "def456 Add feature"))))))
            :to-equal
            "* my-repo\n** ~main~\n- abc123 Fix bug\n- def456 Add feature\n"))

  (it "shows placeholder when all branches have no commits"
    (expect (magit-standup--format-org
             '(("empty-repo" . (("main") ("develop")))))
            :to-equal
            "* empty-repo\n- (no commits)\n"))

  (it "skips branches with no commits"
    (expect (magit-standup--format-org
             '(("my-repo" . (("main" . ("abc Fix thing"))
                              ("stale-branch")))))
            :to-equal
            "* my-repo\n** ~main~\n- abc Fix thing\n"))

  (it "shows multiple branches under one repo"
    (expect (magit-standup--format-org
             '(("my-repo" . (("main" . ("abc Fix thing"))
                              ("feature" . ("def Add thing"))))))
            :to-equal
            (concat "* my-repo\n** ~main~\n- abc Fix thing\n"
                    "\n** ~feature~\n- def Add thing\n")))

  (it "separates multiple repos with blank lines"
    (expect (magit-standup--format-org
             '(("repo-a" . (("main" . ("abc Fix thing"))))
               ("repo-b" . (("develop" . ("def Other thing"))))))
            :to-equal
            (concat "* repo-a\n** ~main~\n- abc Fix thing\n"
                    "\n"
                    "* repo-b\n** ~develop~\n- def Other thing\n"))))

;;; magit-standup-test.el ends here
