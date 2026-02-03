;;; ../../../../var/home/lnickel/.config/doom/azure.el -*- lexical-binding: t; -*-

(require 'json)

                                        ; Change to whereever you have az installed
(setq my-azure-az-command "toolbox run -c az az boards query --org \"https://dev.azure.com/mgeveler\" --project \"TECH%20Portfolio\" --id")

                                        ; TODO: How does visibility of queries work?
                                        ; TODO: Theses can only be flat queries!! https://github.com/Azure/azure-devops-cli-extension/issues/911
(setq my-azure-queries (make-hash-table :test 'equal))
(puthash "My current sprint" "8688c13c-ed01-4932-b073-740e919e9680" my-azure-queries)
(puthash "My previous sprint" "fd6312e9-5941-4df4-9ddb-9f7ec774c6cd" my-azure-queries)
(puthash "ImplantIQ: This sprint" "87b5e166-2f34-456c-b0c0-1cbc911bf831" my-azure-queries)
(puthash "ImplantIQ: 30 days" "c3f52164-8a3f-443d-880f-8eb43fea4fa0" my-azure-queries)
(puthash "ImplantIQ: All" "c08aa1-2431-49ff-8751-344d5191f751" my-azure-queries)
(puthash "Smartworld: All" "b4d98850-5a6c-4ccd-a954-f1d27165c1ab" my-azure-queries)
(puthash "Hepos: All" "155c12a2-8754-4714-a286-5944fa6dfdab" my-azure-queries)

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

(defun azure-to-org-json-string-to-org (item-json-str &optional get-api-details)
  (let*(
        (item-data (json-parse-string item-json-str))
        (url (gethash "url" item-data))
        (id (gethash "id" item-data))
        (fields (gethash "fields" item-data))
        (state (gethash (gethash "System.State" fields) my-azure-org-states "???"))
        (title (gethash "System.Title" fields))
        (headline (concat "* " state " " "[[" url "][" (number-to-string id) ": " title "]]"))
        (description (if get-api-details (azure-to-org-item-description url) nil))
        )
    (concat headline description)
    )
  )


                                        ; TODO: Try to integrate some secrets managing
                                        ; TODO: Use this to get proper urls etc for the entries
                                        ; So this works, but you have to specify the token once on first run
                                        ; user is empty, pw is the pat token

                                        ; TODO Make comments optional as its even more calls then
(defun azure-to-org-item-description (url)
  (let*
      (
       (azure-item-response
        (request
          url
          :auth "basic"
          :sync t
          :parser 'json-parse-buffer
          ))
       (azure-item-data (request-response-data azure-item-response))
       (azure-item-data-fields (gethash "fields" azure-item-data))
       (azure-item-data-links (gethash "_links" azure-item-data))
       (azure-html-link (gethash "href" (gethash "html" azure-item-data-links)))
       (azure-description (gethash "System.Description" azure-item-data-fields))
       (test (if (> (length azure-description) 10) (substring azure-description 5 -6) "No description" ))
       (azure-assigned (gethash "System.AssignedTo" azure-item-data-fields))
       (azure-assigned-name (gethash "displayName" azure-assigned))
       (azure-assigned-avatar (gethash "href" (gethash "avatar" (gethash "_links" azure-assigned))))
       (azure-comments-url (gethash "href" (gethash "workItemComments" azure-item-data-links)))
       (test2 (azure-to-org-item-get-comments azure-comments-url))
       )
    (concat "\n[[" azure-html-link "][Link]]\n" test "\n Assigned to: [[" azure-assigned-avatar "][" azure-assigned-name "]]")
    )
  )

;(azure-to-org-item-description "https://dev.azure.com/mgeveler/_apis/wit/workItems/19350")
;(azure-to-org-item-description "https://dev.azure.com/mgeveler/_apis/wit/workItems/19351")


(defun azure-to-org-item-get-comments (url)
  (let*
      (
       (azure-item-response
        (request
          url
          :auth "basic"
          :sync t
          :parser 'json-parse-buffer
          ))
       (comments (gethash "comments" (request-response-data azure-item-response)))
       )
    (if (> (length comments) 0)
        (seq-doseq (p comments) (message (gethash "text" p)))
      (message "no comments"))
    )
  )
;(azure-to-org-item-get-comments "https://dev.azure.com/mgeveler/_apis/wit/workItems/19350/comments")
;(azure-to-org-item-get-comments "https://dev.azure.com/mgeveler/_apis/wit/workItems/19335/comments")




(defun azure-to-org (queryid &optional get-api-details)
  (let* (
         (command (concat my-azure-az-command " " queryid))
         (items (shell-command-to-string command))
         )
    (setq items (substring items 1 -2))
    (dolist (x (cdr (split-string items "^  {"))) ; first element is empty str
      (let* (
             (item-json-str (string-trim-right (string-trim (concat "{" x) ) ","))
             (item-org-str (azure-to-org-json-string-to-org item-json-str get-api-details))
             )
        (insert (concat item-org-str "\n"))
        ))))


(defun get-azure-items (choice)
  "Perform a predefined flat query and map to org headlines"
  (interactive
   (let ((completion-ignore-case  t))
     (list (completing-read "Choose: " (hash-table-keys my-azure-queries) nil t))))
  (azure-to-org (gethash choice my-azure-queries) nil)
  choice)

(defun get-azure-items-detailed (choice)
  "Perform a predefined flat query and map to org headlines plus more info from api"
  (interactive
   (let ((completion-ignore-case  t))
     (list (completing-read "Choose: " (hash-table-keys my-azure-queries) nil t))))
  (azure-to-org (gethash choice my-azure-queries) t)
  choice)
