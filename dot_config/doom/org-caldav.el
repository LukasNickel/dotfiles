(use-package! org-caldav)

;; URL of the caldav server
(setopt org-caldav-url "http://192.168.178.24:30028/remote.php/dav/calendars/admin")
;; calendar ID on server
(setopt org-caldav-calendar-id "test")

;; Org filename where new entries from calendar stored
(setopt org-caldav-inbox "~/org/calendar/inbox.org")

;; Additional Org files to check for calendar events
(setopt org-caldav-files (directory-files-recursively "~/org/calendar" ""))

;; Usually a good idea to set the timezone manually
(setopt org-icalendar-timezone "Europe/Berlin")
