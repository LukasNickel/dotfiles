;;; org-attach-cleanup.el -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'org)
(require 'org-element)

(defvar my/org-attach-cleanup-candidates nil)

(defun my/org-attach-cleanup--attach-root ()
  (file-truename
   (expand-file-name org-attach-id-dir)))

(defun my/org-attach-cleanup--roam-root ()
  (file-name-as-directory
   (file-truename
    (expand-file-name org-roam-directory))))

(defun my/org-attach-cleanup--file-sha256 (file)
  "Return SHA256 hash of FILE contents."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (secure-hash 'sha256 (current-buffer))))

(defun my/org-attach-cleanup--same-content-p (a b)
  "Return non-nil if files A and B have identical contents."
  (and
   (= (file-attribute-size (file-attributes a))
      (file-attribute-size (file-attributes b)))
   (string=
    (my/org-attach-cleanup--file-sha256 a)
    (my/org-attach-cleanup--file-sha256 b))))

(defun my/org-attach-cleanup--remaining-file-links ()
  "Return (FILES . DIRS) still referenced by file: links."
  (let (files dirs)
    (dolist (org-file
             (directory-files-recursively
              (my/org-attach-cleanup--roam-root)
              "\\.org\\(?:\\.gpg\\)?\\'"))

      (with-temp-buffer
        (let ((buffer-file-name org-file)
              (default-directory
               (file-name-directory org-file)))
          (insert-file-contents org-file)

          (delay-mode-hooks
            (org-mode))

          (set-buffer-modified-p nil)

          (org-element-map
              (org-element-parse-buffer)
              'link
            (lambda (link)
              (when
                  (string=
                   (org-element-property :type link)
                   "file")
                (let ((path
                       (org-element-property :path link)))
                  (when (and (stringp path)
                             (not (string-empty-p path)))
                    (let ((target
                           (condition-case nil
                               (expand-file-name
                                (org-link-unescape path)
                                default-directory)
                             (error nil))))
                      (when (and target
                                 (not (file-remote-p target))
                                 (file-exists-p target))
                        (condition-case nil
                            (if (file-directory-p target)
                                (push (file-truename target)
                                      dirs)
                              (when (file-regular-p target)
                                (push (file-truename target)
                                      files)))
                          (error nil))))))))))))

    (cons (delete-dups files)
          (delete-dups dirs))))

(defun my/org-attach-cleanup--inside-any-p (file dirs)
  (cl-some
   (lambda (dir)
     (file-in-directory-p file dir))
   dirs))

(defun my/org-attach-cleanup--attachment-index ()
  "Return attachment files grouped by basename."
  (let ((root (my/org-attach-cleanup--attach-root))
        result)

    (dolist (file
             (directory-files-recursively root ".*"))
      (when (file-regular-p file)
        (let* ((basename
                (file-name-nondirectory file))
               (entry
                (assoc basename result)))
          (if entry
              (push file (cdr entry))
            (push (list basename file)
                  result)))))

    result))

(defun my/org-attach-cleanup-audit ()
  "Find old files that appear safely duplicated in .attach.

Makes no filesystem changes."
  (interactive)

  (let* ((roam-root
          (my/org-attach-cleanup--roam-root))
         (attach-root
          (my/org-attach-cleanup--attach-root))
         (references
          (my/org-attach-cleanup--remaining-file-links))
         (referenced-files (car references))
         (referenced-dirs (cdr references))
         (attachment-index
          (my/org-attach-cleanup--attachment-index))
         candidates
         results)

    (dolist (file
             (directory-files-recursively roam-root ".*"))
      (when
          (and
           (file-regular-p file)

           ;; Never inspect the attachment tree itself.
           (not (file-in-directory-p
                 (file-truename file)
                 attach-root))

           ;; Ignore quarantine from previous runs.
           (not
            (string-match-p
             "/\\.attach-cleanup-quarantine/"
             file))

           ;; Never treat Org notes as cleanup candidates.
           (not
            (string-match-p
             "\\.org\\(?:\\.gpg\\)?\\'"
             file)))

        (let* ((canonical
                (file-truename file))
               (basename
                (file-name-nondirectory canonical))
               (possible-attachments
                (cdr
                 (assoc basename
                        attachment-index)))
               identical)

          (cond
           ((member canonical referenced-files)
            (push
             (list 'keep-referenced canonical)
             results))

           ((my/org-attach-cleanup--inside-any-p
             canonical referenced-dirs)
            (push
             (list 'keep-linked-directory canonical)
             results))

           ((setq identical
                  (cl-find-if
                   (lambda (attachment)
                     (my/org-attach-cleanup--same-content-p
                      canonical attachment))
                   possible-attachments))
            (push canonical candidates)
            (push
             (list 'cleanup-candidate
                   canonical
                   identical)
             results))))))

    (setq my/org-attach-cleanup-candidates
          (nreverse candidates))

    (with-current-buffer
        (get-buffer-create "*Org Attach Cleanup*")
      (setq buffer-read-only nil)
      (erase-buffer)

      (insert
       (format "Cleanup candidates: %d\n\n"
               (length
                my/org-attach-cleanup-candidates)))

      (dolist (result (nreverse results))
        (pcase result
          (`(cleanup-candidate ,file ,attachment)
           (insert
            (format
             "CLEANUP-CANDIDATE\n  %s\n  identical: %s\n\n"
             file attachment)))

          (`(keep-referenced ,file)
           (insert
            (format
             "KEEP-REFERENCED\n  %s\n\n"
             file)))

          (`(keep-linked-directory ,file)
           (insert
            (format
             "KEEP-LINKED-DIRECTORY\n  %s\n\n"
             file)))))

      (goto-char (point-min))
      (special-mode)
      (pop-to-buffer (current-buffer)))))

(defun my/org-attach-cleanup-quarantine ()
  "Move last audit's candidates into a quarantine directory."
  (interactive)

  (unless my/org-attach-cleanup-candidates
    (user-error
     "No candidates; run my/org-attach-cleanup-audit first"))

  (let* ((root
          (my/org-attach-cleanup--roam-root))
         (quarantine
          (expand-file-name
           (format
            ".attach-cleanup-quarantine/%s/"
            (format-time-string "%Y%m%d-%H%M%S"))
           root))
         (count 0))

    (unless
        (yes-or-no-p
         (format
          "Move %d files to quarantine? "
          (length my/org-attach-cleanup-candidates)))
      (user-error "Cancelled"))

    (dolist (file my/org-attach-cleanup-candidates)
      (let* ((relative
              (file-relative-name file root))
             (destination
              (expand-file-name relative quarantine)))

        (make-directory
         (file-name-directory destination)
         t)

        (rename-file file destination nil)
        (setq count (1+ count))))

    (setq my/org-attach-cleanup-candidates nil)

    (message
     "Moved %d files to %s"
     count quarantine)))
