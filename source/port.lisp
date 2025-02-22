;;; class to abstractly handle differences between platform ports

(in-package :next)

;; TODO: Function-values for slots are not a good idea: should the value change,
;; we have no way to access the old value.

(defclass port ()
  ((name :initarg :name :accessor name
         :documentation "Basename of the executable.")
   (path :initarg :path :initform #'derive-path-from-name
         :documentation "Full path to the executable.
It can also be a function that takes NAME as argument and returns the path as a
string.")
   (args :initarg :args :initform nil
         :documentation "List of strings passed as argument to the executable.")
   (log-file :initarg :log-file :initform #'derive-logfile-from-name
             :documentation "Log file for the platform port.
It can also be a function that takes NAME as argument and returns the log file
as a string.")
   (running-process :accessor running-process
                    :initform nil)))

(defun port-accessor (port slot &rest args)
  (if (functionp (slot-value port slot))
      (apply (slot-value port slot) args)
      (slot-value port slot)))

(defmethod path ((port port))
  (let ((p (port-accessor port 'path (name port))))
    (if (probe-file p)
        (truename p)
        p)))

(defmethod args ((port port))
  (port-accessor port 'args))

(defmethod log-file ((port port))
  (port-accessor port 'log-file (name port)))

(defun derive-path-from-name (name)
  "Find platform port binary with base path NAME.
First NAME is looked up relative to current directory.
If not found, then it is looked in the ports/ subfolder corresponding the NAME (e.g. \"gtk-webkit\").
If still not found, NAME is used as is and will be looked for in PATH.

This is an acceptable value for the PATH slot of the PORT class."
  (or
   (when (probe-file name) (truename name))
   (let* ((port-name (file-namestring name))
          (port-prefix "next-")
          (port-name (if (string= (subseq port-name 0 (length port-prefix))
                                  port-prefix)
                         (subseq port-name (length port-prefix))
                         port-name)))
     (probe-file (merge-pathnames (file-namestring name)
                                  (merge-pathnames (format nil "ports/~a/" port-name)
                                                   *default-pathname-defaults*))))
   name))

(defun derive-logfile-from-name (name)
  "This is an acceptable value for the LOG-FILE slot of the PORT class."
  (let ((xdg-data (or (uiop:getenv "XDG_DATA_HOME")
                      (merge-pathnames ".local/share/" (format nil "~a/" (uiop:getenv "HOME"))))))
    (merge-pathnames (format nil "next/~a.log" name) xdg-data)))

(defmethod run-loop ((port port))
  (if (running-process port)
      (uiop:wait-process (running-process port))
      (log:error "Platform port was started externally, kill the process and try again.")))

(defmethod run-program ((port port))
  (let ((port-path (path port))
        (port-args (args port))
        (port-log-file (log-file port)))
    (log:info "Current directory: ~a" *default-pathname-defaults*)
    (log:info "Platform port path: ~a" port-path)
    (log:info "Platform port arguments: ~a" port-args)
    (log:info "Platform port log file: ~a" port-log-file)
    (ensure-directories-exist (directory-namestring port-log-file))
    (setf (running-process port)
          (uiop:launch-program (cons port-path port-args)
                               :output port-log-file
                               :error-output :output))))

(defmethod kill-program ((port port))
  (uiop:run-program
   (list "kill" "-15"
         (write-to-string
          (uiop/launch-program:process-info-pid
           (running-process port))))))
