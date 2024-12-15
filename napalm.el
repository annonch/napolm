(require 'url)
(require 'json)

(defvar audio-api-port 3000
  "The port number on which the audio API will listen.")

(defvar audio-storage-directory "/tmp/audio-storage/"
  "The directory where uploaded audio files are stored.")

(defun ensure-audio-storage-directory ()
  "Ensure the audio storage directory exists."
  (unless (file-directory-p audio-storage-directory)
    (make-directory audio-storage-directory t)))

(defun audio-api-play-file (file-path)
  "Play the audio file at FILE-PATH.
Supports macOS, GNU/Linux, and Windows systems."
  (cond
   ;; macOS: Use `afplay`
   ((string-equal system-type "darwin")
    (start-process "play-audio" "*play-audio-output*" "afplay" file-path))
   ;; GNU/Linux: Use `mpv`
   ((string-equal system-type "gnu/linux")
    (start-process "play-audio" "*play-audio-output*" "mpv" "--no-video" file-path))
   ;; Windows: Use `powershell`
   ((string-equal system-type "windows-nt")
    (start-process "play-audio" "*play-audio-output*" "powershell" 
                   "-c" (format "Start-SoundPlayer -FilePath '%s'" file-path)))
   (t
    (error "Unsupported operating system"))))

(defun audio-api-handle-get (request-line)
  "Handle GET requests based on REQUEST-LINE."
  (if (string-match "GET /play\\?file=\\([^ ]+\\)" request-line)
      (let* ((encoded-file-path (match-string 1 request-line))
             (file-path (url-unhex-string encoded-file-path)))
        (if (file-exists-p file-path)
            (progn
              (audio-api-play-file file-path)
              (json-encode `((status . "success")
                            (message . "Playing audio file.")
                            (file . ,file-path))))
          (json-encode `((status . "error")
                         (message . "File not found.")
                         (file . ,file-path)))))
    ;; Invalid endpoint
    (json-encode `((status . "error")
                   (message . "Invalid GET endpoint.")))))

(defun audio-api-handle-post (request-body)
  "Handle POST requests for file upload.
REQUEST-BODY is the raw POST data."
  (ensure-audio-storage-directory)
  (let* ((boundary (if (string-match "boundary=\\([^; \r\n]+\\)" request-body)
                       (match-string 1 request-body)
                     nil))
         (file-content (when boundary
                         (replace-regexp-in-string
                          (concat "--" boundary ".*\r\n\r\n\\(.*\\)\\(--" boundary "--\\)")
                          "\\1" request-body nil nil 1)))
         (file-name (concat audio-storage-directory (format-time-string "audio-%Y%m%d-%H%M%S.mp3"))))
    (if (and file-content boundary)
        (progn
          (with-temp-file file-name
            (insert file-content))
          (json-encode `((status . "success")
                         (message . "File uploaded successfully.")
                         (file . ,file-name))))
      (json-encode `((status . "error")
                     (message . "Invalid POST request."))))))

(defun audio-api-handler (process request)
  "Handle incoming HTTP requests.
PROCESS is the network process, REQUEST is the raw request string."
  (let* ((request-lines (split-string request "\r\n"))
         (request-line (car request-lines))
         (request-body (car (last request-lines))) ;; POST body is at the end
         (response "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\r\n")
         (response-body ""))
    ;; Handle GET requests
    (cond
     ((string-prefix-p "GET" request-line)
      (setq response-body (audio-api-handle-get request-line)))
     ;; Handle POST requests
     ((string-prefix-p "POST" request-line)
      (setq response-body (audio-api-handle-post request-body)))
     (t
      (setq response-body (json-encode `((status . "error")
                                        (message . "Unsupported HTTP method."))))))
    ;; Send response
    (process-send-string process (concat response response-body))
    (delete-process process)))

(defun start-audio-api-server ()
  "Start an HTTP server that listens on `audio-api-port` for audio playback and upload requests."
  (interactive)
  (ensure-audio-storage-directory)
  (make-network-process
   :name "audio-api-server"
   :service audio-api-port
   :server t
   :filter (lambda (process request)
             (audio-api-handler process request)))
  (message "Audio API server started on port %d" audio-api-port))

(defun stop-audio-api-server ()
  "Stop the running audio API server."
  (interactive)
  (let ((server (get-process "audio-api-server")))
    (when server
      (delete-process server)
      (message "Audio API server stopped."))))

(start-audio-api-server)
(sit-for 300)

