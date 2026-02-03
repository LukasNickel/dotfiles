;;; ../../../../var/home/lnickel/.config/doom/citar.el -*- lexical-binding: t; -*-

(use-package! citar
  :no-require
  :custom
  (org-cite-global-bibliography '("/home/lnickel/org/references/zotero_export.bib"))
  (org-cite-insert-processor 'citar)
  (org-cite-follow-processor 'citar)
  (org-cite-activate-processor 'citar)
  (citar-bibliography org-cite-global-bibliography)
  (citar-notes-source 'orb-citar-source)
  (citar-at-point-function 'embark-act)
  (citar-register-notes-source
   'orb-citar-source (list :name "Org-Roam Notes"
                           :category 'org-roam-node
                           :items #'citar-org-roam--get-candidates
                           :hasitems #'citar-org-roam-has-notes
                           :open #'citar-org-roam-open-note
                           :create #'orb-citar-edit-note
                           :annotate #'citar-org-roam--annotate))

  ;; optional: org-cite-insert is also bound to C-c C-x C-@
  :bind
  (:map org-mode-map :package org ("C-c b" . #'org-cite-insert))
  :hook
  (LaTeX-mode . citar-capf-setup)
  (org-mode . citar-capf-setup)
  )
(use-package! citar-embark
  :after (citar embark)
  :no-require
  :config (citar-embark-mode))


(use-package! citar-org-roam
  :after (citar org-roam)
  :config (citar-org-roam-mode)
  (setq citar-org-roam-capture-template-key "n")
  )

                                        ; Cooler ui when searching for refs
(defvar citar-indicator-notes-icons
  (citar-indicator-create
   :symbol (nerd-icons-mdicon
            "nf-md-notebook"
            :face 'nerd-icons-blue
            :v-adjust -0.3)
   :function #'citar-has-notes
   :padding "  "
   :tag "has:notes"))

(defvar citar-indicator-links-icons
  (citar-indicator-create
   :symbol (nerd-icons-octicon
            "nf-oct-link"
            :face 'nerd-icons-orange
            :v-adjust -0.1)
   :function #'citar-has-links
   :padding "  "
   :tag "has:links"))

(defvar citar-indicator-files-icons
  (citar-indicator-create
   :symbol (nerd-icons-faicon
            "nf-fa-file"
            :face 'nerd-icons-green
            :v-adjust -0.1)
   :function #'citar-has-files
   :padding "  "
   :tag "has:files"))

(setq citar-indicators
      (list citar-indicator-files-icons
            citar-indicator-notes-icons
            citar-indicator-links-icons))
