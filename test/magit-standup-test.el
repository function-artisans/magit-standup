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
  (it "formats repo with commits as org headings"
    (expect (magit-standup--format-org
             '(("my-repo" . ("abc123 Fix bug"
                              "def456 Add feature"))))
            :to-equal
            "* my-repo\n- abc123 Fix bug\n- def456 Add feature\n"))

  (it "shows placeholder when repo has no commits"
    (expect (magit-standup--format-org
             '(("empty-repo")))
            :to-equal
            "* empty-repo\n- (no commits)\n"))

  (it "separates multiple repos with blank lines"
    (expect (magit-standup--format-org
             '(("repo-a" . ("abc Fix thing"))
               ("repo-b" . ("def Other thing"))))
            :to-equal
            (concat "* repo-a\n- abc Fix thing\n"
                    "\n"
                    "* repo-b\n- def Other thing\n"))))

;;; magit-standup-test.el ends here
