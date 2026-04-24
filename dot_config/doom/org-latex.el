;;; orglatex.el -*- lexical-binding: t; -*-
(map! :map cdlatex-mode-map :i "TAB" #'cdlatex-tab)
(add-to-list 'org-latex-packages-alist '("" "cleveref"))

(with-eval-after-load 'org
  (plist-put org-format-latex-options :background 'auto)
  (setq org-export-allow-bind-keywords t))

(use-package! engrave-faces
  :after ox-latex
  :config
  (add-to-list 'org-latex-engraved-options '("linenos" "true"))
  (setq org-latex-engraved-theme "t")
  )
(setq org-latex-src-block-backend 'engraved)

(setq org-latex-compiler "lualatex")
                                        ; TODO: This needs to be available from whereever emacs is installed.
                                        ; If emacs is in a toolbox, install latex there. Otherwise install latex in a distrobox container and use distrobox-export to expose latexmk etc
(setq org-latex-pdf-process (list "latexmk -f %f -output-directory=%o"))

(defun org-export-output-file-name-modified (orig-fun extension &optional subtreep pub-dir)
  (unless pub-dir
    (setq pub-dir "build")
    (unless (file-directory-p pub-dir)
      (make-directory pub-dir)))
  (apply orig-fun extension subtreep pub-dir nil))
(advice-add 'org-export-output-file-name :around #'org-export-output-file-name-modified)

(add-to-list 'org-latex-classes
             '("scrbook"
               "\\documentclass{scrbook}"
               ("\\section{%s}" . "\\section*{%s}")
               ("\\subsection{%s}" . "\\subsection*{%s}")
               ("\\subsubsection{%s}" . "\\subsubsection*{%s}")
               ("\\paragraph{%s}" . "\\paragraph*{%s}")
               ("\\subparagraph{%s}" . "\\subparagraph*{%s}"))
             )

(add-to-list 'org-latex-classes
             '("ianusarticle"
               "\\documentclass{ianusarticle}"
               ("\\section{%s}" . "\\section*{%s}")
               ("\\subsection{%s}" . "\\subsection*{%s}")
               ("\\subsubsection{%s}" . "\\subsubsection*{%s}")))

