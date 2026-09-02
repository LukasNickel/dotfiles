;;; org-attach-migrate-v4.el --- Conservative file-link -> org-attach migration -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'subr-x)
(require 'org)
(require 'org-element)
(require 'org-attach)
(require 'ol)

(defconst my/org-attach-migration-version "2026-09-01-4"
  "Version marker for the migration script.")

(defgroup my/org-attach-migration nil
  "Migration of local Org file links to org-attach."
  :group 'org-attach)

(defcustom my/org-attach-migration-root nil
  "Absolute root for generated DIR-based attachment directories.

When nil, use `org-attach-id-dir'.  If `org-attach-id-dir' is
relative, set this explicitly to the absolute .attach directory."
  :type '(choice (const :tag "Use org-attach-id-dir" nil)
          directory))

(defcustom my/org-attach-migration-subdirectory "migrated"
  "Subdirectory below the attachment root used for generated DIR properties."
  :type 'string)

(defcustom my/org-attach-migration-source-regexp "\\.org\\'"
  "Regexp identifying Org files to scan below `org-roam-directory'."
  :type 'regexp)

(defcustom my/org-attach-migration-org-target-regexp
  "\\.org\\(?:\\.gpg\\)?\\'"
  "Regexp identifying file-link targets that should stay normal file links."
  :type 'regexp)


;;;; Paths and small helpers

(defun my/org-attach-migration--root ()
  "Return the absolute root used for generated attachment directories."
  (let ((root (or my/org-attach-migration-root org-attach-id-dir)))
    (unless root
      (user-error "Neither my/org-attach-migration-root nor org-attach-id-dir is set"))
    (unless (or (file-name-absolute-p root)
                (string-prefix-p "~/" root))
      (user-error
       "Attachment root is relative (%S); set my/org-attach-migration-root explicitly"
       root))
    (file-name-as-directory (expand-file-name root))))

(defun my/org-attach-migration--roam-root ()
  "Return `org-roam-directory' as an absolute directory."
  (unless (and (boundp 'org-roam-directory) org-roam-directory)
    (user-error "org-roam-directory is not set"))
  (file-name-as-directory (expand-file-name org-roam-directory)))

(defun my/org-attach-migration--org-files ()
  "Return Org files below `org-roam-directory'."
  (directory-files-recursively
   (my/org-attach-migration--roam-root)
   my/org-attach-migration-source-regexp))

(defun my/org-attach-migration--resolve-path (path)
  "Resolve Org file-link PATH relative to the current Org file.
Return nil if PATH cannot be resolved."
  (when (and (stringp path) (not (string-empty-p path)))
    (condition-case nil
        (expand-file-name
         (substitute-in-file-name (org-link-unescape path))
         (file-name-directory buffer-file-name))
      (error nil))))

(defun my/org-attach-migration--org-target-p (file)
  "Return non-nil when FILE looks like another Org note."
  (and (stringp file)
       (let ((case-fold-search t))
         (string-match-p my/org-attach-migration-org-target-regexp file))))

(defun my/org-attach-migration--link-in-heading-p (link)
  "Return non-nil if LINK occurs on an Org headline line."
  (let ((beg (org-element-property :begin link)))
    (and beg
         (save-excursion
           (goto-char beg)
           (beginning-of-line)
           (org-at-heading-p)))))

(defun my/org-attach-migration--heading-beginning (pos)
  "Return the beginning of the heading owning POS, or nil."
  (save-excursion
    (goto-char pos)
    (unless (org-before-first-heading-p)
      (org-back-to-heading t)
      (point))))

(defun my/org-attach-migration--heading-title (heading-beg)
  "Return plain heading title at HEADING-BEG, or nil."
  (when heading-beg
    (condition-case nil
        (save-excursion
          (goto-char heading-beg)
          (org-get-heading t t t t))
      (error nil))))

(defun my/org-attach-migration--attachment-dir-at-heading (heading-beg)
  "Return current attachment directory at HEADING-BEG, without creating it."
  (when heading-beg
    (save-excursion
      (goto-char heading-beg)
      (org-back-to-heading t)
      (let ((org-attach-use-inheritance nil))
        (org-attach-dir nil 'no-fs-check)))))

(defun my/org-attach-migration--file-sha256 (file)
  "Return SHA256 of FILE."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally file)
    (secure-hash 'sha256 (current-buffer))))

(defun my/org-attach-migration--same-content-p (a b)
  "Return non-nil if existing regular files A and B have identical content."
  (and (file-regular-p a)
       (file-regular-p b)
       (condition-case nil
           (or (file-equal-p a b)
               (let ((aa (file-attributes a 'string))
                     (bb (file-attributes b 'string)))
                 (and (= (file-attribute-size aa)
                         (file-attribute-size bb))
                      (string=
                       (my/org-attach-migration--file-sha256 a)
                       (my/org-attach-migration--file-sha256 b)))))
         (error nil))))

(defun my/org-attach-migration--new-dir ()
  "Create and return a unique directory beneath the migration root."
  (let ((base (expand-file-name
               (file-name-as-directory my/org-attach-migration-subdirectory)
               (my/org-attach-migration--root)))
        dir)
    (make-directory base t)
    (while
        (progn
          (setq dir
                (expand-file-name
                 (substring
                  (secure-hash
                   'sha256
                   (format "%s:%s:%s:%s"
                           (or buffer-file-name "")
                           (point)
                           (float-time)
                           (random)))
                  0 24)
                 base))
          (file-exists-p dir)))
    (make-directory dir t)
    dir))


;;;; Small alist helpers -- deliberately no hash tables in this script

(defun my/org-attach-migration--alist-push (key value alist test)
  "Push VALUE into the list stored under KEY in ALIST using TEST.
Return the possibly new ALIST."
  (let ((cell (cl-assoc key alist :test test)))
    (if cell
        (progn
          (setcdr cell (cons value (cdr cell)))
          alist)
      (cons (cons key (list value)) alist))))

(defun my/org-attach-migration--alist-set (key value alist test)
  "Set KEY to VALUE in ALIST using TEST and return ALIST."
  (let ((cell (cl-assoc key alist :test test)))
    (if cell
        (progn
          (setcdr cell value)
          alist)
      (cons (cons key value) alist))))

(defun my/org-attach-migration--alist-get (key alist test)
  "Return value for KEY in ALIST using TEST, or nil."
  (cdr (cl-assoc key alist :test test)))


;;;; Classification and scanning

(defun my/org-attach-migration--classify-target (link path source heading-beg)
  "Classify file LINK before attachment-specific processing.
Return (STATUS . REASON)."
  (cond
   ((my/org-attach-migration--link-in-heading-p link)
    (cons 'skip-heading "file link occurs in headline text"))
   ((not heading-beg)
    (cons 'skip-no-heading "link is outside any heading"))
   ((not (stringp path))
    (cons 'skip-malformed
          (format "file link has non-string path: %S" path)))
   ((string-empty-p path)
    (cons 'skip-malformed "file link has an empty path"))
   ((not source)
    (cons 'broken "could not resolve link target"))
   ((file-remote-p source)
    (cons 'skip-remote "remote/TRAMP target"))
   ((not (file-exists-p source))
    (cons 'broken "target does not exist"))
   ((file-directory-p source)
    (cons 'skip-directory "target is a directory"))
   ((not (file-regular-p source))
    (cons 'skip-nonregular "target is not a regular file"))
   ((my/org-attach-migration--org-target-p source)
    (cons 'skip-org "target looks like an Org note"))
   (t
    (cons 'migrate nil))))

(defun my/org-attach-migration--scan-buffer ()
  "Scan current Org buffer and return a list describing all file: links."
  (let ((tree (org-element-parse-buffer))
        items)
    (org-element-map tree 'link
      (lambda (link)
        (when (equal (org-element-property :type link) "file")
          (condition-case err
              (let* ((beg (org-element-property :begin link))
                     (end (org-element-property :end link))
                     (path (org-element-property :path link))
                     (raw-link (org-element-property :raw-link link))
                     (search (org-element-property :search-option link))
                     (line (and beg (line-number-at-pos beg t)))
                     (heading-beg
                      (and beg
                           (my/org-attach-migration--heading-beginning beg)))
                     (heading
                      (my/org-attach-migration--heading-title heading-beg))
                     (source (my/org-attach-migration--resolve-path path))
                     (classification
                      (my/org-attach-migration--classify-target
                       link path source heading-beg))
                     (status (car classification))
                     (reason (cdr classification))
                     (basename
                      (and (eq status 'migrate)
                           (file-name-nondirectory source)))
                     (attach-dir
                      (and (eq status 'migrate)
                           (my/org-attach-migration--attachment-dir-at-heading
                            heading-beg))))
                (push
                 (list :file buffer-file-name
                       :line line
                       :beg beg
                       :end end
                       :raw-link raw-link
                       :search search
                       :heading-beg heading-beg
                       :heading heading
                       :attach-dir attach-dir
                       :source source
                       :basename basename
                       :status status
                       :reason reason)
                 items))
            (error
             (let ((beg (org-element-property :begin link)))
               (push
                (list :file buffer-file-name
                      :line (and beg (line-number-at-pos beg t))
                      :beg beg
                      :end (org-element-property :end link)
                      :raw-link (org-element-property :raw-link link)
                      :status 'link-error
                      :reason (error-message-string err))
                items)))))))
    (setq items (nreverse items))
    (my/org-attach-migration--mark-collisions items)
    items))

(defun my/org-attach-migration--mark-collisions (items)
  "Mark unsafe basename collisions among migration ITEMS."
  (let (groups)
    (dolist (item items)
      (when (eq (plist-get item :status) 'migrate)
        (setq groups
              (my/org-attach-migration--alist-push
               (cons (plist-get item :heading-beg)
                     (plist-get item :basename))
               item groups #'equal))))

    (dolist (cell groups)
      (let* ((group (cdr cell))
             (sources
              (delete-dups
               (mapcar
                (lambda (item)
                  (condition-case nil
                      (file-truename (plist-get item :source))
                    (error (plist-get item :source))))
                group)))
             (item (car group))
             (source (plist-get item :source))
             (attach-dir (plist-get item :attach-dir))
             (basename (plist-get item :basename))
             (destination
              (and attach-dir
                   (expand-file-name basename attach-dir))))
        (cond
         ((> (length sources) 1)
          (dolist (x group)
            (plist-put x :status 'collision)
            (plist-put x :reason
                       "different source files share this basename under one heading")))
         ((and destination (file-exists-p destination))
          (if (my/org-attach-migration--same-content-p source destination)
              (dolist (x group)
                (plist-put x :status 'rewrite-existing)
                (plist-put x :reason
                           "identical file already exists in attachment directory"))
            (dolist (x group)
              (plist-put x :status 'collision)
              (plist-put x :reason
                         (format "attachment basename already exists: %s"
                                 destination))))))))
    items))

(defun my/org-attach-migration--scan-file (file)
  "Scan FILE in a temporary buffer without running file-visiting hooks."
  (with-temp-buffer
    (let ((buffer-file-name file)
          (default-directory (file-name-directory file)))
      (insert-file-contents file)
      (delay-mode-hooks
        (org-mode))
      (set-buffer-modified-p nil)
      (save-restriction
        (widen)
        (my/org-attach-migration--scan-buffer)))))


;;;; Report

(defun my/org-attach-migration--increment-count (status counts)
  "Increment STATUS in COUNTS alist and return COUNTS."
  (let ((cell (assq status counts)))
    (if cell
        (progn
          (setcdr cell (1+ (cdr cell)))
          counts)
      (cons (cons status 1) counts))))

(defun my/org-attach-migration--report (items title)
  "Display ITEMS in the migration report buffer using TITLE."
  (let ((buffer (get-buffer-create "*Org Attach Migration*"))
        counts
        (roam-root (my/org-attach-migration--roam-root)))
    (dolist (item items)
      (setq counts
            (my/org-attach-migration--increment-count
             (plist-get item :status) counts)))

    (with-current-buffer buffer
      (setq buffer-read-only nil)
      (erase-buffer)
      (insert title "\n")
      (insert (make-string (length title) ?=) "\n\n")
      (insert (format "Org-roam directory: %s\n" roam-root))
      (insert (format "Attachment root:    %s\n"
                      (my/org-attach-migration--root)))
      (insert "Migration method:   copy; source files are never deleted\n\n")

      (setq counts
            (sort counts
                  (lambda (a b)
                    (string< (symbol-name (car a))
                             (symbol-name (car b))))))
      (dolist (entry counts)
        (insert (format "%-22s %d\n"
                        (upcase (symbol-name (car entry)))
                        (cdr entry))))

      (insert "\n")
      (dolist (item items)
        (let* ((file (plist-get item :file))
               (relative
                (if file
                    (file-relative-name file roam-root)
                  "<unknown>")))
          (insert
           (format "%-22s %s:%s\n"
                   (upcase (symbol-name (plist-get item :status)))
                   relative
                   (or (plist-get item :line) "?")))
          (when-let ((heading (plist-get item :heading)))
            (insert (format "  heading: %s\n" heading)))
          (when-let ((raw (plist-get item :raw-link)))
            (insert (format "  link:    %s\n" raw)))
          (when-let ((source (plist-get item :source)))
            (insert (format "  source:  %s\n" source)))
          (when-let ((reason (plist-get item :reason)))
            (insert (format "  reason:  %s\n" reason)))
          (insert "\n")))

      (goto-char (point-min))
      (special-mode))
    (pop-to-buffer buffer)))


;;;; Audit commands

;;;###autoload
(defun my/org-attach-migration-audit-current-buffer ()
  "Audit file: links in the current Org buffer only."
  (interactive)
  (unless (derived-mode-p 'org-mode)
    (user-error "Current buffer is not an Org buffer"))
  (unless buffer-file-name
    (user-error "Current Org buffer is not visiting a file"))
  (my/org-attach-migration--report
   (my/org-attach-migration--scan-buffer)
   "Org attachment migration audit -- current file"))

;;;###autoload
(defun my/org-attach-migration-audit ()
  "Audit all file: links beneath `org-roam-directory'.
This command makes no changes."
  (interactive)
  (my/org-attach-migration--root)
  (let* ((files (my/org-attach-migration--org-files))
         (total (length files))
         (n 0)
         items)
    (dolist (file files)
      (setq n (1+ n))
      (message "Org attach audit: %d/%d %s"
               n total
               (file-relative-name file
                                   (my/org-attach-migration--roam-root)))
      (condition-case err
          (setq items
                (nconc items
                       (my/org-attach-migration--scan-file file)))
        (error
         (push (list :file file
                     :status 'scan-error
                     :reason (error-message-string err))
               items))))
    (my/org-attach-migration--report
     items
     "Org attachment migration audit")
    items))


;;;; Apply helpers

(defun my/org-attach-migration--ensure-dir (heading-marker)
  "Return/create attachment directory for HEADING-MARKER without creating an ID."
  (save-excursion
    (goto-char heading-marker)
    (org-back-to-heading t)
    (let* ((org-attach-use-inheritance nil)
           (id (org-entry-get nil "ID" nil))
           (dir (org-attach-dir nil 'no-fs-check)))
      (cond
       (dir
        (make-directory dir t)
        dir)
       (id
        (error "Could not resolve org-attach directory for existing ID %s" id))
       (t
        (setq dir (my/org-attach-migration--new-dir))
        (org-entry-put nil "DIR" (directory-file-name dir))
        dir)))))

(defun my/org-attach-migration--replacement-target (item)
  "Return attachment: target text for ITEM."
  (concat "attachment:"
          (org-link-escape (plist-get item :basename))
          (when-let ((search (plist-get item :search)))
            (concat "::" search))))

(defun my/org-attach-migration--rewrite-link (item)
  "Rewrite ITEM's raw file: target while preserving its description."
  (let ((beg-marker (plist-get item :beg-marker))
        (end-marker (plist-get item :end-marker))
        (raw-link (plist-get item :raw-link))
        (replacement (my/org-attach-migration--replacement-target item)))
    (unless (and (markerp beg-marker)
                 (marker-position beg-marker)
                 (markerp end-marker)
                 (marker-position end-marker)
                 (stringp raw-link))
      (error "Missing rewrite markers or raw link"))
    (save-excursion
      (goto-char beg-marker)
      (unless (search-forward raw-link (marker-position end-marker) t)
        (error "Could not relocate original link text"))
      (replace-match replacement t t))))

(defun my/org-attach-migration--apply-group (group)
  "Apply migration to one heading's GROUP of links."
  (let* ((representative (car group))
         (heading-marker (plist-get representative :heading-marker))
         (attach-dir (my/org-attach-migration--ensure-dir heading-marker))
         by-basename
         successful)

    ;; Several links may point to the same source file. Copy once.
    (dolist (item group)
      (setq by-basename
            (my/org-attach-migration--alist-push
             (plist-get item :basename) item by-basename #'equal)))

    (dolist (cell by-basename)
      (let* ((basename (car cell))
             (same-name-items (cdr cell))
             (item (car same-name-items))
             (source (plist-get item :source))
             (destination (expand-file-name basename attach-dir)))
        (cond
         ((not (and (stringp source) (file-regular-p source)))
          (dolist (x same-name-items)
            (plist-put x :status 'copy-error)
            (plist-put x :reason
                       "source stopped being an existing regular file")))

         ((file-exists-p destination)
          (if (my/org-attach-migration--same-content-p source destination)
              (setq successful
                    (my/org-attach-migration--alist-set
                     basename 'existing successful #'equal))
            (dolist (x same-name-items)
              (plist-put x :status 'collision)
              (plist-put x :reason
                         (format "different destination already exists: %s"
                                 destination)))))

         (t
          (condition-case err
              (progn
                (copy-file source destination nil)
                (setq successful
                      (my/org-attach-migration--alist-set
                       basename 'copied successful #'equal)))
            (error
             (dolist (x same-name-items)
               (plist-put x :status 'copy-error)
               (plist-put x :reason (error-message-string err)))))))))

    ;; Rewrite bottom-up so earlier edits do not invalidate later positions.
    (dolist (item
             (sort (copy-sequence group)
                   (lambda (a b)
                     (> (marker-position (plist-get a :beg-marker))
                        (marker-position (plist-get b :beg-marker))))))
      (let ((kind
             (my/org-attach-migration--alist-get
              (plist-get item :basename) successful #'equal)))
        (when kind
          (condition-case err
              (progn
                (my/org-attach-migration--rewrite-link item)
                (plist-put item :status
                           (if (eq kind 'copied)
                               'migrated
                             'rewritten-existing))
                (plist-put item :reason nil))
            (error
             (plist-put item :status 'rewrite-error)
             (plist-put item :reason
                        (format
                         "attachment present, but link rewrite failed: %s"
                         (error-message-string err))))))))))

(defun my/org-attach-migration--write-buffer-atomically (file)
  "Replace FILE atomically with the current buffer contents."
  (when (file-symlink-p file)
    (error "Refusing atomic rewrite of symlinked Org file: %s" file))
  (let* ((dir (file-name-directory file))
         (mode (file-modes file))
         (tmp (make-temp-file
               (expand-file-name ".org-attach-migrate-" dir)))
         (coding-system-for-write buffer-file-coding-system))
    (unwind-protect
        (progn
          (write-region (point-min) (point-max) tmp nil 'silent)
          (when mode
            (set-file-modes tmp mode))
          (rename-file tmp file t)
          (setq tmp nil))
      (when (and tmp (file-exists-p tmp))
        (delete-file tmp)))))

(defun my/org-attach-migration--apply-file (file)
  "Apply migration to FILE in a temporary buffer and return report items."
  (cond
   ((file-symlink-p file)
    (list (list :file file
                :status 'skip-symlink-org-file
                :reason "Org file itself is a symlink")))

   ;; Avoid rewriting the file behind an existing editor buffer.
   ((get-file-buffer file)
    (list (list :file file
                :status 'skip-open-org-file
                :reason "Org file is currently open in Emacs")))

   (t
    (with-temp-buffer
      (let ((buffer-file-name file)
            (default-directory (file-name-directory file)))
        (insert-file-contents file)
        (delay-mode-hooks
          (org-mode))
        (set-buffer-modified-p nil)

        (let ((items (my/org-attach-migration--scan-buffer))
              groups
              changed)

          ;; Install all markers before modifying the buffer, and group links
          ;; by their owning heading.  The alist key is the heading position.
          (dolist (item items)
            (when (memq (plist-get item :status)
                        '(migrate rewrite-existing))
              (plist-put item :beg-marker
                         (copy-marker (plist-get item :beg)))
              (plist-put item :end-marker
                         (copy-marker (plist-get item :end) t))
              (plist-put item :heading-marker
                         (copy-marker (plist-get item :heading-beg)))
              (setq groups
                    (my/org-attach-migration--alist-push
                     (plist-get item :heading-beg)
                     item groups #'eql))))

          (dolist (cell groups)
            (my/org-attach-migration--apply-group (cdr cell)))

          (setq changed
                (cl-some
                 (lambda (item)
                   (memq (plist-get item :status)
                         '(migrated rewritten-existing rewrite-error)))
                 items))

          ;; DIR insertion also marks the buffer modified.  Write whenever
          ;; anything in the apply phase changed the temporary buffer.
          (when (or changed (buffer-modified-p))
            (my/org-attach-migration--write-buffer-atomically file)
            (set-buffer-modified-p nil))

          (dolist (item items)
            (dolist (key '(:beg-marker :end-marker :heading-marker))
              (when-let ((marker (plist-get item key)))
                (set-marker marker nil)
                (plist-put item key nil))))

          items))))))


;;;; Apply command

;;;###autoload
(defun my/org-attach-migration-apply ()
  "Migrate valid local file: links below `org-roam-directory'."
  (interactive)
  (my/org-attach-migration--root)
  (unless (yes-or-no-p
           "Copy valid local files into org-attach and rewrite their links? ")
    (user-error "Migration cancelled"))

  (let* ((files (my/org-attach-migration--org-files))
         (total (length files))
         (n 0)
         items)
    (dolist (file files)
      (setq n (1+ n))
      (message "Org attach migration: %d/%d %s"
               n total
               (file-relative-name file
                                   (my/org-attach-migration--roam-root)))
      (condition-case err
          (setq items
                (nconc items
                       (my/org-attach-migration--apply-file file)))
        (error
         (push (list :file file
                     :status 'apply-error
                     :reason (error-message-string err))
               items))))

    (my/org-attach-migration--report
     items
     "Org attachment migration result")
    (message
     "Org attachment migration finished. Consider running org-roam-db-sync once.")
    items))

(defun my/org-attach-migration-show-version ()
  "Display the loaded migration script version."
  (interactive)
  (message "org-attach-migrate version %s"
           my/org-attach-migration-version))

(provide 'org-attach-migrate-v4)

;;; org-attach-migrate-v4.el ends here
