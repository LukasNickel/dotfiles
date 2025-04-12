;;; org-roam.el -*- lexical-binding: t; -*-

                                        ; org roam bindings
(map! :leader
      (:prefix-map ("r" . "regular")
       :desc "find file"            "f"   #'org-roam-node-find
       :desc "find ref"             "F"   #'org-roam-ref-find
       :desc "center scroll"        "s"   #'prot/scroll-center-cursor-mode
       :desc "start taking notes"   "S"   #'org-noter
       :desc "toggle buffer"        "b"   #'org-roam-buffer-toggle
       :desc "insert note"          "i"   #'org-roam-node-insert
       :desc "quit notes"           "q"   #'org-noter-kill-session
       :desc "tag (roam)"           "t"   #'org-roam-tag-add
       :desc "tag (org)"            "T"   #'org-set-tags-command
       :desc "rebuid db"            "d"   #'org-roam-db-build-cache
       :desc "cite"                 "c"   #'org-ref-insert-cite-link
       )
      )

;; Why not
(use-package! org-roam-bibtex
  :after org-roam
  :hook (org-mode . org-roam-bibtex-mode)
  :config
  (require 'org-ref)
  (setq orb-preformat-keywords
        '("citekey" "title" "url" "file" "author-or-editor" "keywords" "pdf" "doi" "author" "tags" "year" "author-bbrev")))


(use-package! org-roam
  :after org
  :config
  (setq org-roam-mode-sections
        (list #'org-roam-backlinks-insert-section
              #'org-roam-reflinks-insert-section
              #'org-roam-unlinked-references-insert-section))
  (org-roam-db-autosync-enable))

;; TODO: The templates could go in extra files
(after! org-roam
  (setq org-roam-capture-templates
        `(("s" "standard" plain "%?"
           :if-new
           (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                      "#+title: ${title}\n#+filetags: \n\n ")
           :unnarrowed t)
          ("d" "definition" plain
           "%?"
           :if-new
           (file+head "${slug}.org" "#+title: ${title}\n#+filetags: definition \n\n* Definition\n\n\n* Examples\n")
           :unnarrowed t)
          ("r" "ref" plain "%?"
           :if-new
           (file+head "references/notes/${citekey}.org"
                      "#+title: ${title}
\n#+filetags: reference ${keywords}
\n* Summary \n
\n* Notes
:PROPERTIES:
:NOTER_DOCUMENT: ${file}
:NOTER_PAGE:
:END:\n")
           :unnarrowed t
           :jump-to-captured t)
          ("p" "presentation" plain "%?"
           :if-new
           (file+head "${slug}.org"
                      "#+title: ${title}
#+filetags: presentation
#+AUTHOR: Lukas Nickel
#+OPTIONS: H:2 toc:t num:t
#+LATEX_CLASS: beamer
#+LATEX_CLASS_OPTIONS: [presentation, 10pt]
#+BEAMER_THEME: metropolis
#+LATEX_HEADER: \\usepackage{amsmath}
#+LATEX_HEADER: \\usepackage{amssymb}
")
           :unnarrowed t))))
