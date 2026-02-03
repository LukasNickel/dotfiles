;;; ../../../../var/home/lnickel/.config/doom/org_roam.el -*- lexical-binding: t; -*-
;;;
;;;
;;;
;;;
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
  (setq orb-preformat-keywords
        '("citekey" "title" "url" "file" "author-or-editor" "keywords" "pdf" "doi" "author" "tags" "year" "author-bbrev")))


(use-package! org-roam
  :after org
  :config
  (setq org-roam-node-display-template (concat "${title:*} " (propertize "${tags:10}" 'face 'org-tag)))
  (org-roam-db-autosync-enable))

;; TODO: The templates could go in extra files
(after! org-roam
  (setq org-beamer-header "#+title: ${title}
#+filetags: presentation
#+AUTHOR: Lukas Nickel
#+OPTIONS: H:1 toc:nil num:t
#+LATEX_CLASS: beamer
#+LATEX_CLASS_OPTIONS: [presentation, 10pt]
#+LATEX_HEADER: \\usepackage{amsmath}
#+LATEX_HEADER: \\usepackage{amssymb}
#+LATEX_HEADER: \\usepackage{mathtools}
#+LATEX_HEADER: \\usepackage{csquotes}
#+LATEX_HEADER: \\usepackage{unicode-math}")
  (setq org-roam-capture-templates
        `(("s" "standard" plain "%?"
           :if-new
           (file+head "standard/%<%Y>/%<%Y%m%d%H%M%S>-${slug}.org"
                      "#+title: ${title}\n#+filetags: \n\n ")
           :unnarrowed t)
          ("e" "emacs" plain "%?"
           :if-new
           (file+head "standard/%<%Y>/%<%Y%m%d%H%M%S>-${slug}.org"
                      "#+title: ${title}\n#+filetags: :emacs:software: \n\n ")
           :unnarrowed t)

          ("n" "literature note" plain
           "%?"
           :target
           (file+head
            "%(expand-file-name (or citar-org-roam-subdir \"\") org-roam-directory)/${citar-citekey}.org"
            "#+title: ${citar-citekey} (${citar-date}). ${note-title}.\n#+created: %U\n#+last_modified: %U\n\n")
           :unnarrowed t)
          ("p" "presentation" plain "%?"
           :if-new
           (file+head
            "presentations/%<%Y>/%<%Y%m%d%H%M%S>-${slug}.org"
            "#+title: ${title}
#+filetags: presentation
#+BEAMER_THEME: metropolis
#+EXPORT_FILE_NAME: ~/Desktop/build/${title}.pdf
#+AUTHOR: Lukas Nickel
#+OPTIONS: H:1 toc:nil num:t
#+LATEX_CLASS: beamer
#+LATEX_CLASS_OPTIONS: [presentation, 10pt]
#+LATEX_HEADER: \\usepackage{amsmath}
#+LATEX_HEADER: \\usepackage{amssymb}
#+LATEX_HEADER: \\usepackage{mathtools}
#+LATEX_HEADER: \\usepackage{csquotes}
#+LATEX_HEADER: \\usepackage{unicode-math}"
            )
           :unnarrowed t)
          ("a" "ianus presentation" plain "%?"
           :if-new
           (file+head
            "ianus_presentations/%<%Y>/%<%Y%m%d%H%M%S>-${slug}.org"
            "#+title: ${title}
#+filetags: presentation
#+AUTHOR: Lukas Nickel
#+OPTIONS: H:1 toc:nil num:t
#+LATEX_HEADER: \\usepackage[german]{datetime2}
#+BEAMER_THEME: ianusbeamer
#+EXPORT_FILE_NAME: ~/Desktop/build/${title}.pdf
#+LATEX_CLASS: beamer
#+LATEX_CLASS_OPTIONS: [presentation, 10pt]
#+LATEX_HEADER: \\usepackage{amsmath}
#+LATEX_HEADER: \\usepackage{amssymb}
#+LATEX_HEADER: \\usepackage{mathtools}
#+LATEX_HEADER: \\usepackage{csquotes}
#+LATEX_HEADER: \\usepackage{unicode-math}"
            )
           :unnarrowed t)
          )))



(setq citar-org-roam-capture-template-key "n")

(use-package! org-ref)
(after! org-ref
  (setopt
   bibtex-completion-bibliography '("/home/lnickel/Documents/zotero.bib")
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
    ":END:\n\nSee [[cite:&${=key=}]]\n")))


                                        ; roam ui
(use-package! websocket
  :after org-roam)

(use-package! org-roam-ui
  :after org-roam ;; or :after org
  ;;         normally we'd recommend hooking orui after org-roam, but since org-roam does not have
  ;;         a hookable mode anymore, you're advised to pick something yourself
  ;;         if you don't care about startup time, use
  ;;  :hook (after-init . org-roam-ui-mode)
  :config
  (setq org-roam-ui-sync-theme t
        org-roam-ui-follow t
        org-roam-ui-update-on-save t
        org-roam-ui-open-on-start t))
