;;; ../../../../var/home/lnickel/.config/doom/org.el -*- lexical-binding: t; -*-

(setq org-directory "~/org"
      org-roam-directory "~/org"
      org-agenda-files '("~/org/agenda.org" "~/org/20240917112409-dailies.org" "~/org/todo.org")
      org-roam-db-location "~/org-roam.db"
      org-noter-notes-search-path '("~/org/references/notes")
      )

(setopt diary-file "~/org/20250422112923-diary.org")
(after! org (setq org-hide-emphasis-markers nil))

;; latex
(setq org-latex-compiler "lualatex")
(setq org-latex-pdf-process (list "toolbox -c latex run latexmk -f %f -output-directory=%o"))
(setq latex-run-command "toolbox -c latex run latexmk")
(setq tex-start-commands"")
(setq +latex-viewers '(pdf-tools))

(setq org-babel-python-command "toolbox -c python run python")
(setq org-preview-latex-process-alist
      '((dvipng :programs ("latex" "dvipng")
         :description "dvi > png"
         :message "You need to install the programs: latex and dvipng."
         :image-input-type "dvi"
         :image-output-type "png"
         :image-size-adjust (1.0 . 1.0)
         :latex-compiler ("toolbox -c latex run dvilualatex -interaction nonstopmode -output-directory %o %f")
         :image-converter ("toolbox -c latex run dvipng -D %D -T tight -o %o/%b.png %o/%b.dvi")))) ;; this is the only modified line

                                        ; Put the exported tex files etc into the build/ dir
(defun org-export-output-file-name-modified (orig-fun extension &optional subtreep pub-dir)
  (unless pub-dir
    (setq pub-dir "build")
    (unless (file-directory-p pub-dir)
      (make-directory pub-dir)))
  (apply orig-fun extension subtreep pub-dir nil))
                                        ; This puts the tex/typ file in build/, but that seems to break the file path workarounds in ox-typst
;;(advice-add 'org-export-output-file-name :around #'org-export-output-file-name-modified)

(setq org-latex-src-block-backend 'engraved)
;;\\AddToHook{cmd/section/before}{\\clearpage}

(with-eval-after-load 'ox-latex
  (add-to-list 'org-latex-classes
               '("ianusarticle" "\\documentclass[a4paper, 11pt]{ianusarticle}"
                 ("\\section{%s}" . "\\section*{%s}")
                 ("\\subsection{%s}" . "\\subsection*{%s}")
                 ("\\subsubsection*{%s}" . "\\subsubsection*{%s}")
                 )
               )
  (setq org-latex-packages-alist
        (quote (("" "color" t)
                ("" "parskip" t)
                ("" "tikz" t))))
  )


(eval-after-load "org-present"
  '(progn
     (add-hook 'org-present-mode-hook
               (lambda ()
                 (org-present-big)
                 (org-display-inline-images)
                 (org-present-hide-cursor)
                 (org-present-read-only)))
     (add-hook 'org-present-mode-quit-hook
               (lambda ()
                 (org-present-small)
                 (org-remove-inline-images)
                 (org-present-show-cursor)
                 (org-present-read-write)))))

(require 'org-alert)
(setq org-alert-interval 300
      org-alert-notify-cutoff 10
      org-alert-notify-after-event-cutoff 10)
(setq alert-default-style 'libnotify)


(use-package ox-typst
  :after org)
(setq org-typst-from-latex-environment #'org-typst-from-latex-with-naive
      org-typst-from-latex-fragment #'org-typst-from-latex-with-naive
      )

(with-eval-after-load "org-tree-slide"
  (define-key org-tree-slide-mode-map (kbd "<f9>") 'org-tree-slide-move-previous-tree)
  (define-key org-tree-slide-mode-map (kbd "<f10>") 'org-tree-slide-move-next-tree)
  )
;; 5 is way too much imo
(setq +org-present-text-scale 3)



