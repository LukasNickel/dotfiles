;;; org-ref.el -*- lexical-binding: t; -*-

;; Hype
(use-package! org-ref
  :after org bibtex-completion bibtex-actions
                                        ;:after org-roam
  :config
  (setq
   org-cite-global-bibliography "~/org/references/library.bib"
   org-ref-completion-library 'org-ref-ivy-cite
   org-ref-get-pdf-filename-function 'org-ref-get-pdf-filename-helm-bibtex
   org-ref-note-title-format "* %y - %t\n :PROPERTIES:\n  :Custom_ID: %k\n  :NOTER_DOCUMENT: %F\n :ROAM_KEY: cite:%k\n  :AUTHOR: %9a\n  :JOURNAL: %j\n  :YEAR: %y\n  :VOLUME: %v\n  :PAGES: %p\n  :DOI: %D\n  :URL: %U\n :END:\n\n"
   org-ref-notes-directory "~/org/references/notes/"
   org-ref-notes-function 'orb-edit-notes
   org-ref-default-ref-type "cref"
   org-ref-pdf-directory "~/org/references/"))
(setq ivy-bibtex-default-action 'ivy-bibtex-insert-citation)

(after! org-ref
  (setq
   bibtex-completion-library-path "~/org/references/"
   bibtex-completion-notes-path "~/org/references/notes/"
   bibtex-completion-bibliography '("~/org/references/library.bib")
   bibtex-completion-pdf-field "file"
   bibtex-completion-notes-template-multiple-files
   (concat
    "#+TITLE: ${title}\n"
    "#+ROAM_KEY: cite:${=key=}\n"
    "* TODO Notes\n"
    ":PROPERTIES:\n"
    ":Custom_ID: ${=key=}\n"
    ":NOTER_DOCUMENT: %(orb-process-file-field \"${=key=}\")\n"
    ":AUTHOR: ${author-abbrev}\n"
    ":JOURNAL: ${journaltitle}\n"
    ":DATE: ${date}\n"
    ":YEAR: ${year}\n"
    ":DOI: ${doi}\n"
    ":URL: ${url}\n"
    ":END:\n\n")))
