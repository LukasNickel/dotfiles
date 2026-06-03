;;; ../../../../var/home/lnickel/.config/doom/azure.el -*- lexical-binding: t; -*-
(require 'json)
(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'url)
(require 'url-parse)
(require 'url-expand)
(require 'url-util)
(require 'ox)
(require 'org-attach)

(declare-function request "request")
(declare-function request-response-data "request")

                                        ; I hacked together an initial version myself and then refined it later on
                                        ; using codex because I wasn't motivated to learn everything I needed to know lol


                                        ; Change to whereever you have az installed
(setq my-azure-work-item-fields
      '("System.Description"
        "System.AssignedTo"
        "System.Title"
        "System.State"
        "System.TeamProject"
        "System.WorkItemType"))
(setq my-azure-az-command "az boards query --only-show-errors --output json --id")
(setq my-azure-work-item-command
      (concat "az boards work-item show --only-show-errors --output json --expand none --fields "
              (mapconcat #'identity my-azure-work-item-fields ",")
              " --id"))
(setq my-azure-work-items-batch-command
      "az devops invoke --only-show-errors --output json --area wit --resource workitemsbatch --api-version 7.1 --http-method POST")
(setq my-azure-comments-command
      "az devops invoke --only-show-errors --output json --area wit --resource comments --api-version 7.1-preview")
(setq my-azure-attachment-download-command
      "az devops invoke --only-show-errors --output none --area wit --resource attachments --api-version 7.1 --http-method GET --accept-media-type application/octet-stream")
(defvar my-azure-comment-fetch-concurrency 4
  "Maximum number of concurrent Azure comment fetch processes.")
(defvar my-azure-cache-images-as-attachments t
  "When non-nil, cache Azure work item images as Org attachments.")
(defvar my-azure-content-image-max-width "640px"
  "Maximum HTML export width for images from Azure descriptions and comments.")

                                        ; TODO: How does visibility of queries work?
                                        ; TODO: Theses can only be flat queries!! https://github.com/Azure/azure-devops-cli-extension/issues/911
(setq my-azure-queries (make-hash-table :test 'equal))
(puthash "My current sprint" "0fad1317-603d-4704-af26-406bd1b99aa5" my-azure-queries)
(puthash "Web-action needed" "a9239ea5-aa6f-4b0b-a40a-6887ceb8f54c" my-azure-queries)

                                        ;(puthash "My previous sprint" "fd6312e9-5941-4df4-9ddb-9f7ec774c6cd" my-azure-queries)
                                        ;(puthash "ImplantIQ: This sprint" "87b5e166-2f34-456c-b0c0-1cbc911bf831" my-azure-queries)
                                        ;(puthash "ImplantIQ: 30 days" "c3f52164-8a3f-443d-880f-8eb43fea4fa0" my-azure-queries)
                                        ;(puthash "ImplantIQ: All" "c08aa1-2431-49ff-8751-344d5191f751" my-azure-queries)
                                        ;(puthash "Smartworld: All" "b4d98850-5a6c-4ccd-a954-f1d27165c1ab" my-azure-queries)
                                        ;(puthash "Hepos: All" "155c12a2-8754-4714-a286-5944fa6dfdab" my-azure-queries)

                                        ; TODO: Think about a better mapping
(setq my-azure-org-states (make-hash-table :test 'equal))
(puthash "Done" "DONE" my-azure-org-states)
(puthash "Removed" "REMOVED" my-azure-org-states)
(puthash "In Progress" "TODO" my-azure-org-states)
(puthash "Active" "TODO" my-azure-org-states)
(puthash "Committed" "TODO" my-azure-org-states)
(puthash "New" "TODO" my-azure-org-states)
(puthash "To Do" "TODO" my-azure-org-states)
(puthash "Closed" "DONE" my-azure-org-states)
(puthash "Needs Feedback" "WAIT" my-azure-org-states)


(defun azure--normalize-state-name (state)
  "Return a forgiving comparison form for Azure STATE."
  (string-trim
   (replace-regexp-in-string
    "[-_[:space:]]+" " "
    (downcase (or state "")))))

(defun azure--mapped-org-state (azure-state)
  "Return the semantic Org TODO state for AZURE-STATE."
  (or (gethash azure-state my-azure-org-states)
      (let ((normalized-state (azure--normalize-state-name azure-state)))
        (catch 'found
          (maphash
           (lambda (key value)
             (when (string= normalized-state
                            (azure--normalize-state-name key))
               (throw 'found value)))
           my-azure-org-states)
          nil))
      (let ((normalized-state (azure--normalize-state-name azure-state)))
        (cond
         ((string-match-p "\\b\\(removed\\|deleted\\|rejected\\)\\b"
                          normalized-state)
          "REMOVED")
         ((string-match-p "\\b\\(done\\|closed\\|complete\\|completed\\)\\b"
                          normalized-state)
          "DONE")
         ((string-match-p "\\b\\(blocked\\|feedback\\|hold\\|pending\\|waiting\\)\\b"
                          normalized-state)
          "WAIT")
         (t
          "TODO")))))

(defun azure--string-or (value default)
  "Return VALUE if it is a non-empty string, otherwise DEFAULT."
  (if (and (stringp value)
           (> (length value) 0))
      value
    default))

(defun azure--org-link (url label)
  "Return an Org link if URL is present, otherwise LABEL."
  (if (and (stringp url)
           (> (length url) 0))
      (format "[[%s][%s]]" url label)
    label))

(defun azure--html-attribute-escape (text)
  "Return TEXT escaped for an HTML attribute."
  (let ((escaped text))
    (setq escaped (replace-regexp-in-string "&" "&amp;" escaped t t))
    (setq escaped (replace-regexp-in-string "\"" "&quot;" escaped t t))
    (setq escaped (replace-regexp-in-string "<" "&lt;" escaped t t))
    (setq escaped (replace-regexp-in-string ">" "&gt;" escaped t t))
    escaped))

(defconst azure--avatar-url-marker "#.azure-avatar.png"
  "URL fragment marker used to identify Azure avatar image links.")

(defun azure--avatar-marked-url (url)
  "Return URL marked as an Azure avatar image link."
  (concat (replace-regexp-in-string "#.*\\'" "" url)
          azure--avatar-url-marker))

(defun azure--avatar-unmarked-url (url)
  "Return URL without the Azure avatar marker."
  (if (string-suffix-p azure--avatar-url-marker url)
      (substring url 0 (- (length azure--avatar-url-marker)))
    url))

(defun azure--avatar-marked-url-p (url)
  "Return non-nil when URL has the Azure avatar marker."
  (and (stringp url)
       (string-suffix-p azure--avatar-url-marker url)))

(defun azure--org-avatar-image (url)
  "Return an Org avatar image link for URL, or an empty string."
  (if (azure--string-or url nil)
      (format " [[%s]]" (azure--avatar-marked-url url))
    ""))

(defun azure--org-image-url (url)
  "Return URL in a form Org recognizes as an image link."
  (if (string-match-p
       "\\.\\(png\\|jpe?g\\|gif\\|svg\\|webp\\)\\($\\|[?#]\\)"
       url)
      url
    (concat url "#.png")))

(defun azure--org-image-link (url)
  "Return a bare Org image link for URL, or an empty string."
  (if (azure--string-or url nil)
      (format "[[%s]]" (azure--org-image-url url))
    ""))

(defun azure--content-image-attr-html ()
  "Return Org HTML attributes for Azure content images."
  (if (azure--string-or my-azure-content-image-max-width nil)
      (format "#+attr_html: :class azure-content-image :style max-width:min(100%%,%s);height:auto;\n"
              my-azure-content-image-max-width)
    "#+attr_html: :class azure-content-image\n"))

(defvar azure--image-attachment-context nil
  "Dynamic context used while converting Azure HTML image tags.")

(defvar azure--image-attachment-used nil
  "Dynamic flag set when an Azure content image is cached as an attachment.")

(defun azure--org-id (id)
  "Return a stable Org ID for Azure work item ID."
  (when (azure--string-or id nil)
    (format "azure-work-item-%s" id)))

(defun azure--comments-org-id (id)
  "Return a stable Org ID for Azure work item ID's comments subtree."
  (when (azure--string-or id nil)
    (format "%s-comments" (azure--org-id id))))

(defun azure--url-without-fragment (url)
  "Return URL without its fragment part."
  (replace-regexp-in-string "#.*\\'" "" url))

(defun azure--absolute-url (url base-url)
  "Return URL resolved against BASE-URL when it is relative."
  (cond
   ((not (azure--string-or url nil))
    "")
   ((string-match-p "\\`https?://" url)
    url)
   ((and (azure--string-or base-url nil)
         (string-prefix-p "/" url))
    (let* ((parsed-base (url-generic-parse-url base-url))
           (scheme (url-type parsed-base))
           (host (url-host parsed-base))
           (port (url-port parsed-base)))
      (concat scheme
              "://"
              host
              (if port (format ":%s" port) "")
              url)))
   ((azure--string-or base-url nil)
    (url-expand-file-name url base-url))
   (t
    url)))

(defun azure--url-path-and-query (url)
  "Return a cons cell of URL's path and query string."
  (let* ((parsed-url (url-generic-parse-url (azure--url-without-fragment url)))
         (filename (or (url-filename parsed-url) ""))
         (query-start (string-match-p "\\?" filename)))
    (if query-start
        (cons (substring filename 0 query-start)
              (substring filename (1+ query-start)))
      (cons filename nil))))

(defun azure--url-query-value (url name)
  "Return query parameter NAME from URL."
  (let ((query (cdr (azure--url-path-and-query url))))
    (when query
      (cadr (assoc-string name (url-parse-query-string query) t)))))

(defun azure--url-path-segments (url)
  "Return decoded path segments from URL."
  (mapcar #'url-unhex-string
          (split-string (car (azure--url-path-and-query url)) "/" t)))

(defun azure--attachment-route-from-url (url)
  "Return an Azure attachment route plist parsed from URL."
  (when (string-match-p "\\`https?://" url)
    (let* ((parsed-url (url-generic-parse-url url))
           (scheme (url-type parsed-url))
           (host (url-host parsed-url))
           (host-lower (downcase (or host "")))
           (segments (azure--url-path-segments url))
           (file-name (azure--url-query-value url "fileName")))
      (cond
       ((and (string= host-lower "dev.azure.com")
             (>= (length segments) 6)
             (string= (nth 2 segments) "_apis")
             (string= (nth 3 segments) "wit")
             (string= (nth 4 segments) "attachments"))
        (list :org (format "%s://%s/%s" scheme host (nth 0 segments))
              :project (nth 1 segments)
              :id (nth 5 segments)
              :file-name file-name))
       ((and (string-suffix-p ".visualstudio.com" host-lower)
             (>= (length segments) 5)
             (string= (nth 1 segments) "_apis")
             (string= (nth 2 segments) "wit")
             (string= (nth 3 segments) "attachments"))
        (list :org (format "%s://%s" scheme host)
              :project (nth 0 segments)
              :id (nth 4 segments)
              :file-name file-name))
       (t
        nil)))))

(defun azure--image-extension-from-url (url)
  "Return a likely image file extension for URL."
  (let* ((file-name (or (azure--url-query-value url "fileName")
                        (file-name-nondirectory
                         (car (azure--url-path-and-query url)))
                        ""))
         (case-fold-search t))
    (if (string-match "\\.\\(png\\|jpe?g\\|gif\\|svg\\|webp\\)\\'" file-name)
        (downcase (match-string 1 file-name))
      "png")))

(defun azure--attachment-file-name (url)
  "Return a deterministic attachment file name for image URL."
  (format "azure-image-%s.%s"
          (substring (secure-hash 'sha1 url) 0 16)
          (azure--image-extension-from-url url)))

(defun azure--file-nonempty-p (file)
  "Return non-nil when FILE exists and has content."
  (and (file-exists-p file)
       (> (file-attribute-size (file-attributes file)) 0)))

(defun azure--attachment-dir-for-id (org-id buffer)
  "Return the Org attachment directory for ORG-ID in BUFFER."
  (when (and (azure--string-or org-id nil)
             (or (file-name-absolute-p org-attach-id-dir)
                 (and (buffer-live-p buffer)
                      (buffer-file-name buffer))))
    (with-current-buffer buffer
      (org-attach-dir-from-id org-id))))

(defun azure--download-attachment-command (route output-file)
  "Return Azure CLI command to download attachment ROUTE to OUTPUT-FILE."
  (concat my-azure-attachment-download-command
          " --org "
          (shell-quote-argument (plist-get route :org))
          " --route-parameters "
          (shell-quote-argument
           (concat "project=" (plist-get route :project)))
          " "
          (shell-quote-argument
           (concat "id=" (plist-get route :id)))
          " --query-parameters "
          (shell-quote-argument "download=true")
          (if (azure--string-or (plist-get route :file-name) nil)
              (concat " "
                      (shell-quote-argument
                       (concat "fileName=" (plist-get route :file-name))))
            "")
          " --out-file "
          (shell-quote-argument output-file)))

(defun azure--download-attachment (route output-file)
  "Download Azure attachment ROUTE into OUTPUT-FILE."
  (when (and (file-exists-p output-file)
             (not (azure--file-nonempty-p output-file)))
    (delete-file output-file))
  (if (azure--file-nonempty-p output-file)
      t
    (with-temp-buffer
      (let ((exit-code
             (call-process-shell-command
              (azure--download-attachment-command route output-file)
              nil t nil)))
        (if (and (integerp exit-code)
                 (= exit-code 0)
                 (azure--file-nonempty-p output-file))
            t
          (when (file-exists-p output-file)
            (delete-file output-file))
          (message "Could not cache Azure image attachment: %s"
                   (string-trim (buffer-string)))
          nil)))))

(defun azure--cache-image-as-attachment (url)
  "Cache Azure image URL as an Org attachment and return its file name."
  (when (and my-azure-cache-images-as-attachments
             azure--image-attachment-context)
    (let* ((absolute-url
            (azure--absolute-url
             url
             (plist-get azure--image-attachment-context :base-url)))
           (route (azure--attachment-route-from-url absolute-url))
           (org-id (plist-get azure--image-attachment-context :org-id))
           (buffer (plist-get azure--image-attachment-context :buffer))
           (attach-dir (and route
                            (azure--attachment-dir-for-id org-id buffer))))
      (when attach-dir
        (let* ((file-name (azure--attachment-file-name absolute-url))
               (output-file (expand-file-name file-name attach-dir)))
          (make-directory attach-dir t)
          (when (azure--download-attachment route output-file)
            (setq azure--image-attachment-used t)
            (run-hook-with-args 'org-attach-after-change-hook attach-dir)
            file-name))))))

(defun azure--org-content-image-link (url)
  "Return an Org image link for content image URL."
  (let* ((absolute-url
          (azure--absolute-url
           url
           (plist-get azure--image-attachment-context :base-url)))
         (attachment (azure--cache-image-as-attachment absolute-url))
         (link (if attachment
                   (format "[[attachment:%s]]" attachment)
                 (azure--org-image-link absolute-url))))
    (if (azure--string-or link nil)
        (format "\n\n%s%s\n\n"
                (azure--content-image-attr-html)
                link)
      "")))

(defun azure--avatar-export-snippet (url backend)
  "Return export snippet for avatar URL and BACKEND."
  (cond
   ((org-export-derived-backend-p backend 'html)
    (format "<img src=\"%s\" width=\"24\" height=\"24\" style=\"vertical-align:middle;border-radius:50%%\">"
            (azure--html-attribute-escape url)))
   ((org-export-derived-backend-p backend 'latex)
    "")
   (t
    "")))

(defun azure--backend-name (backend)
  "Return BACKEND as an Org export snippet backend name."
  (if (symbolp backend)
      (symbol-name backend)
    (format "%s" backend)))

(defun azure--rewrite-link-as-export-snippet (link backend value)
  "Rewrite LINK element as a raw export snippet for BACKEND with VALUE."
  (let ((properties (list :back-end (azure--backend-name backend)
                          :value value
                          :begin (org-element-property :begin link)
                          :end (org-element-property :end link)
                          :post-blank (org-element-property :post-blank link)
                          :parent (org-element-property :parent link))))
    (setcar link 'export-snippet)
    (setcdr link (list properties))))

(defun azure--avatar-export-filter (tree backend _info)
  "Rewrite marked avatar image links in TREE for BACKEND export."
  (org-element-map tree 'link
    (lambda (link)
      (let ((raw-link (org-element-property :raw-link link)))
        (when (azure--avatar-marked-url-p raw-link)
          (azure--rewrite-link-as-export-snippet
           link
           backend
           (azure--avatar-export-snippet
            (azure--avatar-unmarked-url raw-link)
            backend))))))
  tree)

(add-to-list 'org-export-filter-parse-tree-functions
             #'azure--avatar-export-filter)

(defun azure--normalize-query-choice (choice)
  "Return a forgiving comparison form for Azure query CHOICE."
  (string-trim
   (replace-regexp-in-string
    "[-_[:space:]]+" " "
    (downcase (or choice "")))))

(defun azure--query-id (choice)
  "Return the predefined Azure query id for CHOICE."
  (or (gethash choice my-azure-queries)
      (let ((normalized-choice (azure--normalize-query-choice choice)))
        (catch 'found
          (maphash
           (lambda (key value)
             (when (string= normalized-choice
                            (azure--normalize-query-choice key))
               (throw 'found value)))
           my-azure-queries)
          nil))
      (user-error "Unknown Azure query: %s" choice)))

(defconst azure--missing (make-symbol "azure-missing"))

(defun azure--get-in (data path &optional default)
  "Return nested value from DATA following PATH, or DEFAULT if missing."
  (let ((current data)
        (missing nil))
    (dolist (key path)
      (if (hash-table-p current)
          (let ((value (gethash key current azure--missing)))
            (if (eq value azure--missing)
                (setq missing t
                      current nil)
              (setq current value)))
        (setq missing t
              current nil)))
    (if missing default current)))

(defun azure--get-first-in (data paths &optional default)
  "Return the first present nested value in DATA from PATHS, or DEFAULT."
  (catch 'found
    (dolist (path paths)
      (let ((value (azure--get-in data path azure--missing)))
        (unless (eq value azure--missing)
          (throw 'found value))))
    default))

(defun azure--get-first-string-in (data paths &optional default)
  "Return the first non-empty string in DATA from PATHS, or DEFAULT."
  (catch 'found
    (dolist (path paths)
      (let ((value (azure--get-in data path nil)))
        (when (azure--string-or value nil)
          (throw 'found value))))
    default))

(defun azure--field-paths (field-name &optional subpath)
  "Return possible JSON paths for FIELD-NAME followed by SUBPATH."
  (let* ((flat-name (replace-regexp-in-string "\\." "_" field-name))
         (names (if (string= field-name flat-name)
                    (list field-name)
                  (list field-name flat-name))))
    (append
     (mapcar (lambda (name)
               (append (list "fields" name) subpath))
             names)
     (mapcar (lambda (name)
               (append (list name) subpath))
             names))))

(defun azure--field (item-data field-name &optional default)
  "Return FIELD-NAME from ITEM-DATA, accepting nested and flattened keys."
  (azure--get-first-in item-data (azure--field-paths field-name) default))

(defun azure--field-in (item-data field-name subpath &optional default)
  "Return SUBPATH below FIELD-NAME, accepting nested and flattened keys."
  (azure--get-first-in item-data
                       (azure--field-paths field-name subpath)
                       default))

(defun azure--assigned-to-name (item-data &optional default)
  "Return the display name for ITEM-DATA's assigned user."
  (let ((assigned-to (azure--field item-data "System.AssignedTo" azure--missing))
        (fallback (or default "Unassigned")))
    (cond
     ((hash-table-p assigned-to)
      (azure--string-or
       (azure--get-in assigned-to '("displayName") nil)
       fallback))
     ((stringp assigned-to)
      (azure--string-or assigned-to fallback))
     (t
      fallback))))

(defun azure--assigned-to-avatar (item-data)
  "Return the avatar URL for ITEM-DATA's assigned user."
  (let ((assigned-to (azure--field item-data "System.AssignedTo" nil)))
    (if (hash-table-p assigned-to)
        (azure--get-in assigned-to '("_links" "avatar" "href") "")
      "")))

(defun azure--work-item-id (item-data)
  "Return a work item id from ITEM-DATA."
  (cond
   ((hash-table-p item-data)
    (let ((id (azure--get-in item-data '("id") nil)))
      (cond
       ((numberp id) (number-to-string id))
       ((stringp id) id)
       (t nil))))
   ((and (stringp item-data)
         (string-match "/workItems/\\([0-9]+\\)" item-data))
    (match-string 1 item-data))
   (t
    nil)))

(defun azure--work-item-url (item-data)
  "Return a detail URL from ITEM-DATA when present."
  (cond
   ((hash-table-p item-data)
    (azure--get-in item-data '("url") ""))
   ((stringp item-data)
    item-data)
   (t
    "")))

(defun azure--work-item-web-url (item-data)
  "Return an Azure DevOps web UI URL for ITEM-DATA."
  (let* ((url (azure--work-item-url item-data))
         (id (azure--work-item-id item-data))
         (html-url (and (hash-table-p item-data)
                        (azure--get-in item-data '("_links" "html" "href") nil))))
    (cond
     ((azure--string-or html-url nil)
      html-url)
     ((and (azure--string-or url nil)
           (azure--string-or id nil)
           (string-match "\\(https://[^/]+/[^?]+?\\)/_apis/wit/workItems/[0-9]+" url))
      (format "%s/_workitems/edit/%s" (match-string 1 url) id))
     ((and (azure--string-or url nil)
           (azure--string-or id nil)
           (string-match "\\(https://[^/]+/[^?]+?\\)/_workitems/edit/[0-9]+" url))
      url)
     (t
      url))))

(defun azure--work-item-candidate-urls (item-data)
  "Return URLs from ITEM-DATA that can identify the Azure DevOps org."
  (delq nil
        (list
         (and (hash-table-p item-data)
              (azure--get-in item-data '("commentVersionRef" "url") nil))
         (azure--work-item-url item-data))))

(defun azure--work-item-org-url (item-data)
  "Return the Azure DevOps org URL for ITEM-DATA."
  (catch 'found
    (dolist (url (azure--work-item-candidate-urls item-data))
      (when (and (azure--string-or url nil)
                 (string-match "\\(https://[^/]+/[^/?]+\\)\\(?:/.*\\)?$" url))
        (throw 'found (match-string 1 url))))
    nil))

(defun azure--work-item-route (item-data)
  "Return plist with Azure DevOps org, project, and work item id for ITEM-DATA."
  (let ((team-project (azure--field item-data "System.TeamProject" nil))
        (id (azure--work-item-id item-data)))
    (or
     (catch 'found
       (dolist (url (azure--work-item-candidate-urls item-data))
         (when (and (azure--string-or url nil)
                    (string-match
                     "\\(https://[^/]+/[^/]+\\)/\\([^/?]+\\)/_apis/wit/workItems/\\([0-9]+\\)"
                     url))
           (let ((org (match-string 1 url))
                 (project (match-string 2 url))
                 (work-item-id (match-string 3 url)))
             (throw 'found
                    (list :org org
                          :project (url-unhex-string project)
                          :id work-item-id)))))
       nil)
     (let ((org (azure--work-item-org-url item-data)))
       (when (and (azure--string-or org nil)
                  (azure--string-or team-project nil)
                  (azure--string-or id nil))
         (list :org org
               :project team-project
               :id id))))))

(defun azure--parse-json-string (json-text)
  "Parse JSON-TEXT, allowing non-JSON text before the JSON payload."
  (let* ((trimmed (string-trim-left json-text))
         (start (or (string-match-p "[[{]" trimmed) 0)))
    (json-parse-string (substring trimmed start)
                       :object-type 'hash-table
                       :array-type 'list)))

(defun azure--parse-json-buffer ()
  "Parse JSON from the current buffer, skipping HTTP headers if present."
  (let ((start (save-excursion
                 (goto-char (point-min))
                 (if (looking-at-p "HTTP/")
                     (if (re-search-forward "\r?\n\r?\n" nil t)
                         (point)
                       (point-min))
                   (point-min)))))
    (azure--parse-json-string
     (buffer-substring-no-properties start (point-max)))))

(defun azure--fetch-json (url)
  "Fetch URL and return parsed JSON data."
  (if (require 'request nil t)
      (request-response-data
       (request
         url
         :auth "basic"
         :sync t
         :parser #'azure--parse-json-buffer))
    (let ((buffer (url-retrieve-synchronously url t t)))
      (unless buffer
        (error "No response from %s" url))
      (unwind-protect
          (with-current-buffer buffer
            (azure--parse-json-buffer))
        (kill-buffer buffer)))))

(defun azure--fetch-work-item-details (id)
  "Fetch work item ID through the Azure CLI and return parsed JSON."
  (let* ((command (concat my-azure-work-item-command " "
                          (shell-quote-argument id)))
         (json-output (shell-command-to-string command)))
    (azure--mark-work-item-details
     (azure--parse-json-string json-output))))

(defun azure--mark-work-item-details (item-data)
  "Mark ITEM-DATA as already containing detailed work item fields."
  (when (hash-table-p item-data)
    (puthash "__azure_details_loaded" t item-data))
  item-data)

(defun azure--work-item-details-loaded-p (item-data)
  "Return non-nil when ITEM-DATA already has detailed work item fields."
  (and (hash-table-p item-data)
       (gethash "__azure_details_loaded" item-data nil)))

(defun azure--work-item-org-url-from-items (items)
  "Return the first Azure DevOps org URL found in ITEMS."
  (catch 'found
    (dolist (item items)
      (let ((org (azure--work-item-org-url item)))
        (when (azure--string-or org nil)
          (throw 'found org))))
    nil))

(defun azure--number-id (id)
  "Return ID as a number, or nil if it is not numeric."
  (cond
   ((numberp id) id)
   ((and (stringp id)
         (string-match-p "\\`[0-9]+\\'" id))
    (string-to-number id))
   (t nil)))

(defun azure--chunks (items size)
  "Return ITEMS split into chunks of SIZE."
  (let ((chunks nil)
        (rest items))
    (while rest
      (let ((chunk nil)
            (count 0))
        (while (and rest (< count size))
          (push (car rest) chunk)
          (setq rest (cdr rest)
                count (1+ count)))
        (push (nreverse chunk) chunks)))
    (nreverse chunks)))

(defun azure--batch-request-json (ids)
  "Return JSON request body for a work item batch request over IDS."
  (json-encode
   `(("ids" . ,(vconcat ids))
     ("fields" . ,(vconcat my-azure-work-item-fields))
     ("$expand" . "None")
     ("errorPolicy" . "Omit"))))

(defun azure--parse-work-items-response (response)
  "Return a list of work items from batch RESPONSE."
  (cond
   ((listp response)
    response)
   ((hash-table-p response)
    (or (azure--get-in response '("value") nil)
        (azure--get-in response '("items") nil)
        nil))
   (t nil)))

(defun azure--fetch-work-item-details-batch-chunk (org ids)
  "Fetch detailed work item data for IDS from ORG."
  (let ((body-file (make-temp-file "azure-workitems-batch-" nil ".json")))
    (unwind-protect
        (progn
          (with-temp-file body-file
            (insert (azure--batch-request-json ids)))
          (let* ((command (concat my-azure-work-items-batch-command
                                  " --org "
                                  (shell-quote-argument org)
                                  " --in-file "
                                  (shell-quote-argument body-file)))
                 (json-output (shell-command-to-string command)))
            (azure--parse-work-items-response
             (azure--parse-json-string json-output))))
      (when (file-exists-p body-file)
        (delete-file body-file)))))

(defun azure--fetch-work-item-details-batch (items)
  "Return a hash table of detailed work items for ITEMS, keyed by id string."
  (let ((details-by-id (make-hash-table :test 'equal))
        (org (azure--work-item-org-url-from-items items))
        (ids (delq nil
                   (mapcar (lambda (item)
                             (azure--number-id (azure--work-item-id item)))
                           items))))
    (when (and (azure--string-or org nil)
               ids)
      (condition-case err
          (dolist (chunk (azure--chunks ids 200))
            (dolist (detail (azure--fetch-work-item-details-batch-chunk org chunk))
              (azure--mark-work-item-details detail)
              (let ((id (azure--work-item-id detail)))
                (when id
                  (puthash id detail details-by-id)))))
        (error
         (message "Could not batch fetch Azure work item details: %S" err))))
    details-by-id))

(defun azure--fetch-comments (route)
  "Fetch comments for work item ROUTE through Azure DevOps CLI auth."
  (let* ((command (azure--comments-command route))
         (json-output (shell-command-to-string command)))
    (azure--parse-json-string json-output)))

(defun azure--comments-command (route)
  "Return the Azure CLI command to fetch comments for ROUTE."
  (concat my-azure-comments-command
          " --org "
          (shell-quote-argument (plist-get route :org))
          " --route-parameters "
          (shell-quote-argument
           (concat "project=" (plist-get route :project)))
          " "
          (shell-quote-argument
           (concat "workItemId=" (plist-get route :id)))))

(defun azure--comment-fetch-concurrency ()
  "Return the effective Azure comment fetch concurrency."
  (max 1
       (if (and (integerp my-azure-comment-fetch-concurrency)
                (> my-azure-comment-fetch-concurrency 0))
           my-azure-comment-fetch-concurrency
         4)))

(defconst azure--html-block-tags
  '(address article aside blockquote dd div dl dt fieldset figcaption figure
    footer form h1 h2 h3 h4 h5 h6 header hr li main nav ol p pre
    section table tbody td tfoot th thead tr ul)
  "HTML tags that should create paragraph boundaries in Org text.")

(defun azure--html-node-attr (node attr)
  "Return ATTR from libxml HTML NODE."
  (cdr (assq attr (cadr node))))

(defun azure--org-verbatim (text)
  "Return TEXT wrapped as Org verbatim markup when safe."
  (let ((text (replace-regexp-in-string "[ \t\r\n]+" " " (string-trim text))))
    (if (and (azure--string-or text nil)
             (not (string-match-p "=" text)))
        (format "=%s=" text)
      text)))

(defun azure--html-mention-link-p (node text)
  "Return non-nil when NODE is an Azure mention link containing TEXT."
  (and (eq (car node) 'a)
       (let ((class (azure--html-node-attr node 'class))
             (href (azure--html-node-attr node 'href)))
         (or (azure--html-node-attr node 'data-vss-mention)
             (and (azure--string-or class nil)
                  (string-match-p "\\bmention\\b" class))
             (and (azure--string-or href nil)
                  (string-prefix-p "@" (string-trim-left text)))))))

(defun azure--html-node-text (node)
  "Return plain text from a libxml HTML NODE."
  (cond
   ((stringp node)
    node)
   ((not (consp node))
    "")
   ((eq (car node) 'br)
    "\n")
   ((eq (car node) 'img)
    (azure--org-content-image-link (azure--html-node-attr node 'src)))
   ((eq (car node) 'a)
    (let ((text (mapconcat #'azure--html-node-text (cddr node) "")))
      (if (azure--html-mention-link-p node text)
          (azure--org-verbatim text)
        text)))
   ((memq (car node) azure--html-block-tags)
    (concat (mapconcat #'azure--html-node-text (cddr node) "") "\n\n"))
   (t
    (mapconcat #'azure--html-node-text (cddr node) ""))))

(defun azure--codepoint-to-string (codepoint)
  "Return the Unicode character for CODEPOINT as a string, or nil."
  (let ((char (decode-char 'ucs codepoint)))
    (and char (char-to-string char))))

(defun azure--decode-html-entities-fallback (text)
  "Decode common HTML entities in TEXT without libxml."
  (let ((entities '(("nbsp" . " ")
                    ("amp" . "&")
                    ("lt" . "<")
                    ("gt" . ">")
                    ("quot" . "\"")
                    ("apos" . "'")
                    ("ndash" . "-")
                    ("mdash" . "-")))
        (case-fold-search t))
    (setq text
          (replace-regexp-in-string
           "&#x\\([[:xdigit:]]+\\);"
           (lambda (match)
             (or (azure--codepoint-to-string
                  (string-to-number (match-string 1 match) 16))
                 match))
           text t))
    (setq text
          (replace-regexp-in-string
           "&#\\([0-9]+\\);"
           (lambda (match)
             (or (azure--codepoint-to-string
                  (string-to-number (match-string 1 match)))
                 match))
           text t))
    (replace-regexp-in-string
     "&\\([[:alpha:]][[:alnum:]]*\\);"
     (lambda (match)
       (or (cdr (assoc-string (match-string 1 match) entities t))
           match))
     text t)))

(defun azure--html-wrap-mention-links-fallback (html)
  "Wrap simple mention links in HTML as Org verbatim text."
  (let ((case-fold-search t))
    (replace-regexp-in-string
     "<a\\b\\([^>]*\\)>\\([^<]*\\)</a>"
     (lambda (match)
       (save-match-data
         (if (string-match "\\`<a\\b\\([^>]*\\)>\\([^<]*\\)</a>\\'" match)
             (let* ((attrs (match-string 1 match))
                    (body (match-string 2 match))
                    (decoded-body (azure--decode-html-entities-fallback body)))
               (if (or (string-match-p "\\bdata-vss-mention\\b" attrs)
                       (string-match-p "\\bclass=[\"'][^\"']*\\bmention\\b" attrs)
                       (and (string-match-p "\\bhref=" attrs)
                            (string-prefix-p "@" (string-trim-left decoded-body))))
                   (azure--org-verbatim body)
                 body))
           match)))
     html t)))

(defun azure--html-attribute-value-fallback (attrs attr)
  "Return ATTR value from an HTML attribute string ATTRS."
  (let ((case-fold-search t))
    (when (string-match
           (concat "\\b" (regexp-quote attr)
                   "[ \t\r\n]*=[ \t\r\n]*\\(?:\"\\([^\"]*\\)\"\\|'\\([^']*\\)'\\|\\([^ \t\r\n>]+\\)\\)")
           attrs)
      (or (match-string 1 attrs)
          (match-string 2 attrs)
          (match-string 3 attrs)))))

(defun azure--html-wrap-images-fallback (html)
  "Replace simple HTML image tags in HTML with Org image links."
  (let ((case-fold-search t))
    (replace-regexp-in-string
     "<[ \t\r\n]*img\\b\\([^>]*\\)>"
     (lambda (match)
       (save-match-data
         (if (string-match "\\`<[ \t\r\n]*img\\b\\([^>]*\\)>\\'" match)
             (let* ((attrs (match-string 1 match))
                    (src (azure--html-attribute-value-fallback attrs "src")))
               (azure--org-content-image-link
                (azure--decode-html-entities-fallback (or src ""))))
           match)))
     html t)))

(defun azure--html-to-text-fallback (html)
  "Return plain text from HTML when libxml is unavailable."
  (let ((case-fold-search t)
        (text (azure--html-wrap-images-fallback
               (azure--html-wrap-mention-links-fallback html))))
    (setq text (replace-regexp-in-string "<br\\(?:[ \t\r\n][^>]*\\)?/?>" "\n" text))
    (setq text (replace-regexp-in-string "</\\(?:p\\|div\\|li\\|h[1-6]\\|tr\\|blockquote\\|pre\\)>" "\n" text))
    (setq text (replace-regexp-in-string "<[^>]+>" "" text))
    (azure--decode-html-entities-fallback text)))

(defun azure--normalize-plain-text (text)
  "Normalize whitespace in plain TEXT after HTML parsing."
  (let ((nbsp (char-to-string #xa0)))
    (setq text (replace-regexp-in-string "\r\n?" "\n" text))
    (setq text (replace-regexp-in-string nbsp " " text t t))
    (setq text (replace-regexp-in-string "[ \t]+\n" "\n" text))
    (setq text (replace-regexp-in-string "\n[ \t]+" "\n" text))
    (setq text (replace-regexp-in-string "\n\\{3,\\}" "\n\n" text))
    (string-trim text)))

(defun azure--escaped-char-p (text index)
  "Return non-nil if character at INDEX in TEXT is escaped."
  (let ((slashes 0)
        (pos (1- index)))
    (while (and (>= pos 0)
                (= (aref text pos) ?\\))
      (setq slashes (1+ slashes)
            pos (1- pos)))
    (= (mod slashes 2) 1)))

(defun azure--org-keyword-line-p (line)
  "Return non-nil when LINE is an Org keyword line."
  (string-match-p "\\`[ \t]*#\\+[[:alpha:]_]+:" line))

(defun azure--org-escape-subscript-markers-line (text)
  "Protect Org subscript markers in one TEXT line."
  (let ((index 0)
        (length (length text))
        (delimiter nil)
        (result nil))
    (while (< index length)
      (let ((char (aref text index)))
        (cond
         ((and (= char ?\[)
               (not delimiter)
               (< (1+ index) length)
               (= (aref text (1+ index)) ?\[))
          (let ((end (string-match "\\]\\]" text index)))
            (if end
                (progn
                  (push (substring text index (match-end 0)) result)
                  (setq index (1- (match-end 0))))
              (push (char-to-string char) result))))
         ((and (= char ?\\)
               (not delimiter)
               (< (1+ index) length)
               (= (aref text (1+ index)) ?_))
          nil)
         ((and (memq char '(?= ?~))
               (not (azure--escaped-char-p text index)))
          (setq delimiter
                (cond
                 ((eq delimiter char) nil)
                 ((not delimiter) char)
                 (t delimiter)))
          (push (char-to-string char) result))
         ((and (= char ?_)
               (not delimiter))
          (push "\\under{}" result))
         (t
          (push (char-to-string char) result))))
      (setq index (1+ index)))
    (apply #'concat (nreverse result))))

(defun azure--org-escape-subscript-markers (text)
  "Protect Org subscript markers in TEXT outside generated Org syntax."
  (mapconcat
   (lambda (line)
     (if (azure--org-keyword-line-p line)
         line
       (azure--org-escape-subscript-markers-line line)))
   (split-string text "\n")
   "\n"))

(defun azure--clean-text (text)
  "Return TEXT as Org-safe Unicode text with HTML entities decoded."
  (if (azure--string-or text nil)
      (azure--org-escape-subscript-markers
       (azure--normalize-plain-text
        (if (fboundp 'libxml-parse-html-region)
            (with-temp-buffer
              (insert text)
              (azure--html-node-text
               (libxml-parse-html-region (point-min) (point-max))))
          (azure--html-to-text-fallback text))))
    ""))

(defun azure--clean-description (description)
  "Return a safe plain-ish description string."
  (azure--string-or (azure--clean-text description) "No description"))

(defun azure--org-link-line-p (line)
  "Return non-nil when LINE starts with an Org link."
  (string-match-p "\\`[ \t]*\\[\\[" line))

(defun azure--org-syntax-paragraph-p (paragraph)
  "Return non-nil when PARAGRAPH contains generated Org syntax."
  (seq-some
   (lambda (line)
     (or (azure--org-keyword-line-p line)
         (azure--org-link-line-p line)))
   (split-string paragraph "\n")))

(defun azure--fill-plain-paragraph (paragraph)
  "Return plain PARAGRAPH filled like an Emacs paragraph."
  (with-temp-buffer
    (insert paragraph)
    (goto-char (point-min))
    (fill-paragraph)
    (string-trim (buffer-string))))

(defun azure--fill-text (text)
  "Return TEXT filled while preserving generated Org syntax."
  (string-trim
   (mapconcat
    (lambda (paragraph)
      (if (azure--org-syntax-paragraph-p paragraph)
          paragraph
        (azure--fill-plain-paragraph paragraph)))
    (split-string text "\n\n")
    "\n\n")))

(defun azure--org-quote-block (text &optional html-class)
  "Return TEXT as a filled Org quote block.
When HTML-CLASS is non-nil, attach it as an Org HTML attribute."
  (concat
   (if (azure--string-or html-class nil)
       (format "#+attr_html: :class %s\n" html-class)
     "")
   (format "#+begin_quote\n%s\n#+end_quote"
           (azure--fill-text text))))

(defun azure--org-property-value (value)
  "Return VALUE as a single-line Org property value."
  (replace-regexp-in-string
   "[\r\n]+"
   " "
   (string-trim (format "%s" (or value "")))))

(defun azure--org-property-drawer (properties)
  "Return an Org property drawer for non-empty PROPERTIES.
PROPERTIES is a list of (NAME . VALUE) pairs."
  (let ((lines
         (delq nil
               (mapcar
                (lambda (property)
                  (let ((value (azure--org-property-value (cdr property))))
                    (when (azure--string-or value nil)
                      (format ":%s: %s" (car property) value))))
                properties))))
    (if lines
        (concat "\n:PROPERTIES:\n"
                (mapconcat #'identity lines "\n")
                "\n:END:")
      "")))

(defun azure--format-comment-date (date)
  "Return DATE in a compact display form."
  (if (azure--string-or date nil)
      (condition-case nil
          (format-time-string "%Y-%m-%d %H:%M" (date-to-time date) t)
        (error date))
    ""))

(defun azure--format-comment (comment)
  "Return COMMENT as Org text."
  (let* ((author (azure--get-in comment '("createdBy" "displayName") "Unknown"))
         (date (azure--format-comment-date
                (azure--get-in comment '("createdDate") "")))
         (text (azure--clean-description
                (azure--get-first-string-in comment
                                            '(("text")
                                              ("renderedText"))
                                            "")))
         (metadata (if (azure--string-or date nil)
                       (format "/%s/ · %s" author date)
                     (format "/%s/" author))))
    (concat "#+attr_html: :class azure-comment-meta\n"
            metadata
            "\n"
            (azure--org-quote-block text "azure-comment"))))

(defun azure--comments-data-to-org (comments-data)
  "Return Org text for COMMENTS-DATA from Azure DevOps."
  (let ((comments (or (azure--get-in comments-data '("comments") nil)
                      (azure--get-in comments-data '("value") nil))))
    (if comments
        (let* ((comments-context
                (when (and azure--image-attachment-context
                           (plist-get azure--image-attachment-context
                                      :comments-org-id))
                  (let ((context (copy-sequence azure--image-attachment-context)))
                    (plist-put context
                               :org-id
                               (plist-get azure--image-attachment-context
                                          :comments-org-id))
                    context)))
               (comments-id (plist-get comments-context :org-id)))
          (let ((azure--image-attachment-context
                 (or comments-context azure--image-attachment-context))
                (azure--image-attachment-used nil))
            (let ((comment-body
                   (mapconcat #'azure--format-comment comments "\n\n")))
              (concat
               "** Comments"
               (if (and comments-id azure--image-attachment-used)
                   (azure--org-property-drawer `(("ID" . ,comments-id)))
                 "")
               "\n"
               comment-body))))
      "")))

(defun azure--comments-output-to-org (json-output)
  "Return Org text for Azure comments JSON-OUTPUT."
  (azure--comments-data-to-org
   (azure--parse-json-string json-output)))

(defun azure-to-org-item-get-comments (route)
  "Return Org text for comments from work item ROUTE."
  (if (not route)
      ""
    (condition-case err
        (azure--comments-data-to-org
         (azure--fetch-comments route))
      (error
       (format "Could not fetch comments: %S" err)))))

(defun azure--fetch-comments-concurrently (jobs results)
  "Fetch comment JOBS concurrently and store comment data in RESULTS.
JOBS is a list of (ID . ROUTE) pairs.  RESULTS is a hash table keyed by
work item id strings."
  (let ((pending jobs)
        (active 0)
        (remaining (length jobs))
        (limit (azure--comment-fetch-concurrency))
        (buffers nil))
    (cl-labels
        ((store-result
          (id text)
          (puthash id text results))
         (finish-job
          (id buffer status)
          (unwind-protect
              (let ((output (if (buffer-live-p buffer)
                                (with-current-buffer buffer
                                  (buffer-string))
                              "")))
                (store-result
                 id
                 (if (= status 0)
                     (condition-case err
                         (azure--parse-json-string output)
                       (error
                        (format "Could not fetch comments: %S" err)))
                   (format "Could not fetch comments: process exited with status %s"
                           status))))
            (setq active (1- active)
                  remaining (1- remaining))))
         (start-job
          (job)
          (let* ((id (car job))
                 (route (cdr job))
                 (buffer (generate-new-buffer
                          (format " *azure-comments-%s*" id)))
                 (command (azure--comments-command route))
                 (process-connection-type nil))
            (condition-case err
                (let ((process
                       (start-process-shell-command
                        (format "azure-comments-%s" id)
                        buffer
                        command)))
                  (push buffer buffers)
                  (setq active (1+ active))
                  (set-process-query-on-exit-flag process nil)
                  (set-process-sentinel
                   process
                   (lambda (process _event)
                     (when (memq (process-status process) '(exit signal))
                       (finish-job id
                                   (process-buffer process)
                                   (process-exit-status process))
                       (start-next)))))
              (error
               (when (buffer-live-p buffer)
                 (kill-buffer buffer))
               (store-result
                id
                (format "Could not fetch comments: %S" err))
               (setq remaining (1- remaining))))))
         (start-next
          ()
          (while (and pending (< active limit))
            (start-job (pop pending)))))
      (unwind-protect
          (progn
            (start-next)
            (while (> remaining 0)
              (accept-process-output nil 0.1)))
        (dolist (buffer buffers)
          (when (buffer-live-p buffer)
            (kill-buffer buffer))))))
  results)

(defun azure--fetch-comments-for-items (items details-by-id)
  "Fetch comments for ITEMS concurrently, using DETAILS-BY-ID for routes."
  (let ((results (make-hash-table :test 'equal))
        (jobs nil))
    (seq-doseq (item items)
      (let* ((id (azure--work-item-id item))
             (details (and id details-by-id
                           (gethash id details-by-id nil)))
             (route (or (and details
                             (azure--work-item-route details))
                        (azure--work-item-route item))))
        (when id
          (if route
              (push (cons id route) jobs)
            (puthash id "" results)))))
    (azure--fetch-comments-concurrently (nreverse jobs) results)))

(defun azure--field-with-fallback (item-data fallback-item-data field-name &optional default)
  "Return FIELD-NAME from ITEM-DATA or FALLBACK-ITEM-DATA."
  (or (azure--field item-data field-name nil)
      (and fallback-item-data
           (azure--field fallback-item-data field-name nil))
      default))

(defun azure-to-org-item-to-org
    (item-data &optional get-api-details include-comments fallback-item-data prefetched-comments)
  (let* ((web-url (azure--string-or
                   (azure--work-item-web-url item-data)
                   (and fallback-item-data
                        (azure--work-item-web-url fallback-item-data))))
         (id (or (azure--work-item-id item-data)
                 (and fallback-item-data
                      (azure--work-item-id fallback-item-data))))
         (azure-type (azure--field-with-fallback
                      item-data fallback-item-data "System.WorkItemType" ""))
         (azure-state (azure--field-with-fallback
                       item-data fallback-item-data "System.State" ""))
         (state (azure--mapped-org-state azure-state))
         (org-id (and get-api-details
                      (azure--org-id id)))
         (title (azure--string-or
                 (azure--clean-text
                  (azure--field-with-fallback
                   item-data fallback-item-data "System.Title" nil))
                 "Untitled"))
         (headline (format "* %s %s"
                           state
                           (azure--org-link web-url title)))
         (properties (azure--org-property-drawer
                      `(("ID" . ,org-id)
                        ("AZURE_ID" . ,id)
                        ("AZURE_TYPE" . ,azure-type)
                        ("AZURE_STATE" . ,azure-state))))
         (description (if get-api-details
                          (azure-to-org-item-description
                           item-data include-comments fallback-item-data prefetched-comments)
                        "")))
    (concat headline properties description)))
                                        ; TODO: Try to integrate some secrets managing
                                        ; TODO: Use this to get proper urls etc for the entries
                                        ; So this works, but you have to specify the token once on first run
                                        ; user is empty, pw is the pat token

(defun azure-to-org-item-description
    (item-data &optional include-comments fallback-item-data prefetched-comments)
  (let ((url (azure--string-or
              (azure--work-item-url item-data)
              (and fallback-item-data
                   (azure--work-item-url fallback-item-data))))
        (id (or (azure--work-item-id item-data)
                (and fallback-item-data
                     (azure--work-item-id fallback-item-data)))))
    (if (and (not (azure--string-or url nil))
             (not (azure--string-or id nil)))
        "\nNo detail URL available.\n"
      (condition-case err
          (let* ((fallback-item-data (or fallback-item-data
                                         (and (hash-table-p item-data)
                                              item-data)))
                 (azure-item-data (cond
                                   ((azure--work-item-details-loaded-p item-data)
                                    item-data)
                                   ((azure--string-or id nil)
                                    (azure--fetch-work-item-details id))
                                   (t
                                    item-data)))
                 (azure-description
                  (or (azure--field azure-item-data "System.Description" nil)
                      (and fallback-item-data
                           (azure--field fallback-item-data "System.Description" nil))
                      ""))

                 (azure-assigned-name
                  (azure--assigned-to-name
                   azure-item-data
                   (and fallback-item-data
                        (azure--assigned-to-name fallback-item-data "Unassigned"))))

                 (azure-assigned-avatar
                  (azure--string-or
                   (azure--assigned-to-avatar azure-item-data)
                   (if fallback-item-data
                       (azure--assigned-to-avatar fallback-item-data)
                     "")))

                 (attachment-context
                  (list :org-id (azure--org-id id)
                        :comments-org-id (azure--comments-org-id id)
                        :base-url url
                        :buffer (current-buffer))))

            (let ((azure--image-attachment-context attachment-context))
              (let* ((description-text
                      (azure--clean-description azure-description))
                     (comments
                      (cond
                       ((not include-comments)
                        "")
                       ((stringp prefetched-comments)
                        prefetched-comments)
                       ((hash-table-p prefetched-comments)
                        (azure--comments-data-to-org prefetched-comments))
                       (t
                        (let ((azure-comments-route
                               (or (azure--work-item-route azure-item-data)
                                   (and fallback-item-data
                                        (azure--work-item-route fallback-item-data)))))
                          (if azure-comments-route
                              (azure-to-org-item-get-comments azure-comments-route)
                            ""))))))

                (concat
                 "\n"
                 "#+attr_html: :class azure-assigned\n"
                 "Assigned to: "
                 azure-assigned-name
                 (azure--org-avatar-image azure-assigned-avatar)
                 "\n\n"
                 (azure--org-quote-block description-text "azure-description")
                 (if (azure--string-or comments nil)
                     (concat "\n\n" comments)
                   "")))))

        (error
         (format "\nCould not fetch item details: %S\n" err))))))
                                        ;(azure-to-org-item-description "https://dev.azure.com/mgeveler/_apis/wit/workItems/19350")
                                        ;(azure-to-org-item-description "https://dev.azure.com/mgeveler/_apis/wit/workItems/19351")


(defun azure-to-org (queryid &optional get-api-details include-comments)
  (unless (azure--string-or queryid nil)
    (user-error "Missing Azure query id"))
  (let* ((command (concat my-azure-az-command " " (shell-quote-argument queryid)))
         (json-output (shell-command-to-string command)))
    (condition-case err
        (let ((items (azure--parse-json-string json-output)))
          (let ((details-by-id (if get-api-details
                                   (azure--fetch-work-item-details-batch items)
                                 nil))
                (comments-by-id nil))
            (when (and get-api-details include-comments)
              (setq comments-by-id
                    (azure--fetch-comments-for-items items details-by-id)))
          (seq-doseq (item items)
            (let* ((id (azure--work-item-id item))
                   (details (and details-by-id
                                 id
                                 (gethash id details-by-id nil)))
                   (render-item (or details item))
                   (comments (and comments-by-id
                                  id
                                  (gethash id comments-by-id nil))))
              (insert
               (concat
                (azure-to-org-item-to-org
                 render-item get-api-details include-comments item comments)
                "\n"))))))
      (json-parse-error
       (message "Could not parse Azure CLI output as JSON: %S\nOutput was:\n%s"
                err json-output)))))


(defun get-azure-items (choice)
  "Perform a predefined flat query and map to org headlines"
  (interactive
   (let ((completion-ignore-case  t))
     (list (completing-read "Choose: " (hash-table-keys my-azure-queries) nil t))))
  (azure-to-org (azure--query-id choice) nil)
  choice)

(defun get-azure-items-detailed (choice)
  "Perform a predefined flat query and map to Org headlines plus details."
  (interactive
   (let ((completion-ignore-case  t))
     (list (completing-read "Choose: " (hash-table-keys my-azure-queries) nil t))))
  (azure-to-org (azure--query-id choice) t nil)
  choice)

(defun get-azure-items-detailed-with-comments (choice)
  "Perform a predefined flat query and map to Org headlines, details, and comments."
  (interactive
   (let ((completion-ignore-case  t))
     (list (completing-read "Choose: " (hash-table-keys my-azure-queries) nil t))))
  (azure-to-org (azure--query-id choice) t t)
  choice)
