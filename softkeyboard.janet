# 模拟软键盘 - 纯 Janet + Win32 原生 FFI
# 由于 Janet 的 ffi/trampoline 无法作为 WNDPROC 使用，这里采用：
#   - 系统内置 STATIC 类创建子窗口
#   - 主窗口 WNDPROC 使用 DefWindowProcW
#   - 主循环中轮询鼠标状态来检测点击

# -----------------------------------------------------------------------------
# 常量

(def CP_UTF8 65001)

(def KEYEVENTF_KEYUP 0x0002)
(def WM_SETFONT 0x0030)

(def WS_CAPTION 0x00C00000)
(def WS_SYSMENU 0x00080000)
(def WS_MINIMIZEBOX 0x00020000)
(def WS_VISIBLE 0x10000000)
(def WS_CHILD 0x40000000)
(def WS_CLIPSIBLINGS 0x04000000)
(def WS_BORDER 0x00800000)

# 改用 STATIC 控件，避免 BUTTON 抢焦点或发送点击命令。
(def SS_CENTER 0x00000001)
(def SS_NOTIFY 0x00000100)
(def SS_CENTERIMAGE 0x00000200)
(def STATIC-STYLE
  (+ WS_CHILD WS_VISIBLE WS_CLIPSIBLINGS WS_BORDER SS_CENTER SS_CENTERIMAGE SS_NOTIFY))

(def MAIN-WINDOW-STYLE
  (+ WS_CAPTION WS_SYSMENU WS_MINIMIZEBOX))

(def WS_EX_TOPMOST 0x00000008)
(def WS_EX_NOACTIVATE 0x08000000)
(def WS_EX_TOOLWINDOW 0x00000080)
(def WS_EX_STATICEDGE 0x00020000)

(def SW_SHOWNA 8)

# 长按阈值（秒）
(def LONG-PRESS-THRESHOLD 0.4)
(def GRIPPER-SIZE 18)
(def WINDOW-TITLE "SCADA")
(def DEFAULT-WINDOW-RECT [100 100 850 340])
(def WINDOW-STATE-DIR "scada-keyboard")
(def WINDOW-STATE-FILE "window.txt")
(def DEFAULT-LANGUAGE-CODE "zh_cn")
(def IME-LABELS
  {"zh_cn" "输入法"
   "en_gb" "Input Method"
   "ja_jp" "入力方式"
   "ar_eg" "طريقة الإدخال"
   "az_az" "Daxiletmə üsulu"
   "bn_bd" "ইনপুট পদ্ধতি"
   "ru_ru" "Метод ввода"
   "ca_es" "Mètode d'entrada"
   "cs_cz" "Metoda vstupu"
   "da_dk" "Inputmetode"
   "de_de" "Eingabemethode"
   "el_gr" "Μέθοδος εισόδου"
   "es_es" "Método de entrada"
   "eu_es" "Sarrera metodoa"})

(def GWL_STYLE -16)
(def SS_SUNKEN 0x00001000)
(def SWP_NOMOVE 0x0002)
(def SWP_NOSIZE 0x0001)
(def SWP_NOACTIVATE 0x0010)
(def SWP_NOZORDER 0x0004)
(def SWP_FRAMECHANGED 0x0020)

(def VK_LBUTTON 0x01)
(def VK_ESCAPE 0x1B)
(def VK_SHIFT 0x10)
(def VK_BACK 0x08)
(def VK_RETURN 0x0D)
(def VK_SPACE 0x20)
(def VK_TAB 0x09)

(def VK_0 0x30) (def VK_1 0x31) (def VK_2 0x32) (def VK_3 0x33) (def VK_4 0x34)
(def VK_5 0x35) (def VK_6 0x36) (def VK_7 0x37) (def VK_8 0x38) (def VK_9 0x39)

(def VK_A 0x41) (def VK_B 0x42) (def VK_C 0x43) (def VK_D 0x44) (def VK_E 0x45)
(def VK_F 0x46) (def VK_G 0x47) (def VK_H 0x48) (def VK_I 0x49) (def VK_J 0x4A)
(def VK_K 0x4B) (def VK_L 0x4C) (def VK_M 0x4D) (def VK_N 0x4E) (def VK_O 0x4F)
(def VK_P 0x50) (def VK_Q 0x51) (def VK_R 0x52) (def VK_S 0x53) (def VK_T 0x54)
(def VK_U 0x55) (def VK_V 0x56) (def VK_W 0x57) (def VK_X 0x58) (def VK_Y 0x59)
(def VK_Z 0x5A)

# 符号键虚拟键码
(def VK_OEM_3 0xC0)   # ` ~
(def VK_OEM_MINUS 0xBD) # - _
(def VK_OEM_PLUS 0xBB)  # = +
(def VK_OEM_4 0xDB)   # [ {
(def VK_OEM_6 0xDD)   # ] }
(def VK_OEM_5 0xDC)   # \ |
(def VK_OEM_1 0xBA)   # ; :
(def VK_OEM_7 0xDE)   # ' "
(def VK_OEM_COMMA 0xBC) # , <
(def VK_OEM_PERIOD 0xBE) # . >
(def VK_OEM_2 0xBF)   # / ?

(def HWND_TOPMOST -1)

(def PM_REMOVE 1)

(def IDI_APPLICATION 32512)
(def IDC_ARROW 32512)
(def COLOR_BTNFACE 15)

# -----------------------------------------------------------------------------
# FFI 基础设施

(var cc :none)
(def fns @{})
(def structs @{})

(defn- bind! [lib name ret & args]
  (put fns name {:ptr (ffi/lookup lib name)
                 :ret ret
                 :args args}))

(defn- call [name & args]
  (let [f (fns name)
        sig (ffi/signature cc (f :ret) ;(f :args))]
    (ffi/call (f :ptr) sig ;args)))

(defn- ensure-ffi! []
  (when (empty? fns)
    (def user32 (ffi/native "user32.dll"))
    (def kernel32 (ffi/native "kernel32.dll"))
    (def gdi32 (ffi/native "gdi32.dll"))
    (set cc
      (let [ccs (ffi/calling-conventions)]
        (if (and ccs (> (length ccs) 0))
          (in ccs 0)
          :none)))

    # kernel32
    (bind! kernel32 "GetModuleHandleW" :ptr :ptr)
    (bind! kernel32 "MultiByteToWideChar" :int32 :uint32 :uint32 :ptr :int32 :ptr :int32)
    (bind! kernel32 "GetLastError" :uint32)

    # user32
    (bind! user32 "RegisterClassExW" :uint16 :ptr)
    (bind! user32 "UnregisterClassW" :int32 :ptr :ptr)
    (bind! user32 "CreateWindowExW" :ptr :uint32 :ptr :ptr :uint32 :int32 :int32 :int32 :int32 :ptr :ptr :ptr :ptr)
    (bind! user32 "DestroyWindow" :int32 :ptr)
    (bind! user32 "DefWindowProcW" :ptr :ptr :uint32 :ptr :ptr)
    (bind! user32 "ShowWindow" :int32 :ptr :int32)
    (bind! user32 "UpdateWindow" :int32 :ptr)
    (bind! user32 "PeekMessageW" :int32 :ptr :ptr :uint32 :uint32 :uint32)
    (bind! user32 "TranslateMessage" :int32 :ptr)
    (bind! user32 "DispatchMessageW" :ptr :ptr)
    (bind! user32 "GetAsyncKeyState" :int16 :int32)
    (bind! user32 "GetCursorPos" :int32 :ptr)
    (bind! user32 "GetWindowRect" :int32 :ptr :ptr)
    (bind! user32 "GetClientRect" :int32 :ptr :ptr)
    (bind! user32 "SetWindowTextW" :int32 :ptr :ptr)
    (bind! user32 "IsWindow" :int32 :ptr)
    (bind! user32 "SetWindowPos" :int32 :ptr :ptr :int32 :int32 :int32 :int32 :uint32)
    (bind! user32 "GetWindowLongPtrW" :ssize :ptr :int32)
    (bind! user32 "SetWindowLongPtrW" :ssize :ptr :int32 :ssize)
    (bind! user32 "SetForegroundWindow" :int32 :ptr)
    (bind! user32 "SendMessageW" :ptr :ptr :uint32 :ptr :ptr)
    (bind! user32 "InvalidateRect" :int32 :ptr :ptr :int32)
    (bind! user32 "PostQuitMessage" :void :int32)

    # gdi32
    (bind! gdi32 "CreateFontW" :ptr :int32 :int32 :int32 :int32 :int32 :uint32 :uint32 :uint32 :uint32 :uint32 :uint32 :uint32 :uint32 :ptr)
    (bind! gdi32 "DeleteObject" :int32 :ptr)
    (bind! user32 "keybd_event" :void :uint8 :uint8 :uint32 :ptr)
    (bind! user32 "LoadIconW" :ptr :ptr :ptr)
    (bind! user32 "LoadCursorW" :ptr :ptr :ptr)
    (bind! user32 "GetSysColorBrush" :ptr :int32)
    (bind! user32 "GetForegroundWindow" :ptr)

    # 数据结构定义
    (put structs :wndclassexw
         (ffi/struct :uint32 :uint32 :ptr :int32 :int32 :ptr :ptr :ptr :ptr :ptr :ptr :ptr))
    (put structs :rect
         (ffi/struct :int32 :int32 :int32 :int32))
    (put structs :point
         (ffi/struct :int32 :int32))))

# -----------------------------------------------------------------------------
# 数据类型

# MSG 在 x64 上实际大小约 48 字节，分配 64 字节足够
(def MSG-BUF-SIZE 64)

# -----------------------------------------------------------------------------
# UTF-16 转换

(defn- to-utf16
  "把 UTF-8 字符串转成 UTF-16LE buffer。"
  [s]
  (let [count (call "MultiByteToWideChar" CP_UTF8 0 s -1 nil 0)
        buf (buffer/new (* 2 count))]
    (call "MultiByteToWideChar" CP_UTF8 0 s -1 buf count)
    buf))

(defn- path-join [parent child]
  (string parent "\\" child))

(defn- window-state-path []
  (let [appdata (os/getenv "APPDATA")]
    (if appdata
      (path-join (path-join appdata WINDOW-STATE-DIR) WINDOW-STATE-FILE)
      WINDOW-STATE-FILE)))

(defn- ensure-window-state-dir! []
  (when-let [appdata (os/getenv "APPDATA")]
    (let [dir (path-join appdata WINDOW-STATE-DIR)]
      (when (nil? (os/stat dir))
        (try
          (os/mkdir dir)
          ([err] nil))))))

(defn- valid-window-rect? [rect]
  (and (= 4 (length rect))
       (number? (rect 0))
       (number? (rect 1))
       (number? (rect 2))
       (number? (rect 3))
       (> (rect 2) 0)
       (> (rect 3) 0)))

(defn- parse-window-rect [text]
  (let [parts (string/split " " (string/trim text))]
    (when (= 4 (length parts))
      (let [rect (map scan-number parts)]
        (when (valid-window-rect? rect)
          rect)))))

(defn- load-window-rect []
  (let [[ok? text] (protect (slurp (window-state-path)))]
    (or (when ok?
          (parse-window-rect text))
        DEFAULT-WINDOW-RECT)))

(defn- save-window-rect [rect]
  (when (valid-window-rect? rect)
    (ensure-window-state-dir!)
    (let [text (string (rect 0) " " (rect 1) " " (rect 2) " " (rect 3))]
      (try
        (spit (window-state-path) text)
        ([err] nil)))))

# -----------------------------------------------------------------------------
# 窗口类与窗口创建

(defn- register-class! [class-name16]
  (let [hinstance (call "GetModuleHandleW" nil)
        bg (call "GetSysColorBrush" COLOR_BTNFACE)
        wc (ffi/write (structs :wndclassexw)
                      [(ffi/size (structs :wndclassexw))
                       0
                       (ffi/lookup (ffi/native "user32.dll") "DefWindowProcW")
                       0
                       0
                       hinstance
                       nil
                       nil
                       bg
                       nil
                       class-name16
                       nil])]
    (call "RegisterClassExW" wc)))

(defn- create-main-window [class-name16 title16 x y w h]
  (let [hinstance (call "GetModuleHandleW" nil)
        hwnd (call "CreateWindowExW"
                   (+ WS_EX_TOPMOST WS_EX_NOACTIVATE WS_EX_TOOLWINDOW)
                   class-name16
                   title16
                   MAIN-WINDOW-STYLE
                   x y w h
                   nil nil hinstance nil)]
    (when (nil? hwnd)
      (error (string "CreateWindowExW failed, error=" (call "GetLastError"))))
    hwnd))

(defn- create-key [parent label16 x y w h]
  (let [hinstance (call "GetModuleHandleW" nil)
        hwnd (call "CreateWindowExW"
                   (+ WS_EX_NOACTIVATE WS_EX_STATICEDGE)
                   (to-utf16 "STATIC")
                   label16
                   STATIC-STYLE
                   x y w h
                   parent nil hinstance nil)]
    (when (nil? hwnd)
      (error (string "CreateWindowExW(static) failed, error=" (call "GetLastError"))))
    hwnd))

(defn- create-gripper [parent x y]
  (let [hinstance (call "GetModuleHandleW" nil)
        hwnd (call "CreateWindowExW"
                   WS_EX_NOACTIVATE
                   (to-utf16 "STATIC")
                   (to-utf16 "◢")
                   (+ WS_CHILD WS_VISIBLE WS_CLIPSIBLINGS WS_BORDER SS_CENTER SS_CENTERIMAGE)
                   x y GRIPPER-SIZE GRIPPER-SIZE
                   parent nil hinstance nil)]
    (when (nil? hwnd)
      (error (string "CreateWindowExW(gripper) failed, error=" (call "GetLastError"))))
    hwnd))

# -----------------------------------------------------------------------------
# 输入发送

(defn- key-event [vk up?]
  (call "keybd_event" vk 0 (if up? KEYEVENTF_KEYUP 0) nil))

(defn- send-key [vk shift?]
  (when shift?
    (key-event VK_SHIFT false))
  (key-event vk false)
  (key-event vk true)
  (when shift?
    (key-event VK_SHIFT true)))

(defn- toggle-ime
  "发送一个单独的 Shift 键事件，供输入法切换中/英模式。"
  []
  (key-event VK_SHIFT false)
  (key-event VK_SHIFT true))

# -----------------------------------------------------------------------------
# 键盘布局

(def normal-key-width 50)
(def key-height 45)
(def key-gap 5)
(def row-height 55)
(def keyboard-margin-x 10)
(def keyboard-margin-y 10)
(def keyboard-width 810)

(defn- row-width [keys]
  (var total 0)
  (each key keys
    (set total (+ total (key :width))))
  (+ total (* (dec (length keys)) key-gap)))

(defn- justified-row [keys]
  (let [extra (- keyboard-width (row-width keys))
        count (length keys)
        row @[]]
    (var x keyboard-margin-x)
    (var prev-extra 0)
    (each [idx key] (pairs keys)
      (let [next-extra (math/floor (/ (* extra (inc idx)) count))
            add-width (- next-extra prev-extra)
            w (+ (key :width) add-width)]
        (array/push row [key x w])
        (set x (+ x w key-gap))
        (set prev-extra next-extra)))
    row))

(defn- make-key [label vk &opt width toggle? ime? shift-label]
  (default width normal-key-width)
  {:label label
   :vk vk
   :width width
   :toggle? (or toggle? false)
   :ime? (or ime? false)
   :shift-label (or shift-label label)})

(defn- make-keyboard-rows [ime-label]
  [[(make-key "`" VK_OEM_3 nil nil nil "~")
    (make-key "1" VK_1 nil nil nil "!")
    (make-key "2" VK_2 nil nil nil "@")
    (make-key "3" VK_3 nil nil nil "#")
    (make-key "4" VK_4 nil nil nil "$")
    (make-key "5" VK_5 nil nil nil "%")
    (make-key "6" VK_6 nil nil nil "^")
    (make-key "7" VK_7 nil nil nil "&")
    (make-key "8" VK_8 nil nil nil "*")
    (make-key "9" VK_9 nil nil nil "(")
    (make-key "0" VK_0 nil nil nil ")")
    (make-key "-" VK_OEM_MINUS nil nil nil "_")
    (make-key "=" VK_OEM_PLUS nil nil nil "+")
    (make-key "Backspace" VK_BACK 95)]
   [(make-key "q" VK_Q nil nil nil "Q")
    (make-key "w" VK_W nil nil nil "W")
    (make-key "e" VK_E nil nil nil "E")
    (make-key "r" VK_R nil nil nil "R")
    (make-key "t" VK_T nil nil nil "T")
    (make-key "y" VK_Y nil nil nil "Y")
    (make-key "u" VK_U nil nil nil "U")
    (make-key "i" VK_I nil nil nil "I")
    (make-key "o" VK_O nil nil nil "O")
    (make-key "p" VK_P nil nil nil "P")
    (make-key "[" VK_OEM_4 nil nil nil "{")
    (make-key "]" VK_OEM_6 nil nil nil "}")
    (make-key "\\" VK_OEM_5 nil nil nil "|")]
   [(make-key "a" VK_A nil nil nil "A")
    (make-key "s" VK_S nil nil nil "S")
    (make-key "d" VK_D nil nil nil "D")
    (make-key "f" VK_F nil nil nil "F")
    (make-key "g" VK_G nil nil nil "G")
    (make-key "h" VK_H nil nil nil "H")
    (make-key "j" VK_J nil nil nil "J")
    (make-key "k" VK_K nil nil nil "K")
    (make-key "l" VK_L nil nil nil "L")
    (make-key ";" VK_OEM_1 nil nil nil ":")
    (make-key "'" VK_OEM_7 nil nil nil "\"")
    (make-key "Enter" VK_RETURN 95)]
   [(make-key "Shift" VK_SHIFT 80 true)
    (make-key "z" VK_Z nil nil nil "Z")
    (make-key "x" VK_X nil nil nil "X")
    (make-key "c" VK_C nil nil nil "C")
    (make-key "v" VK_V nil nil nil "V")
    (make-key "b" VK_B nil nil nil "B")
    (make-key "n" VK_N nil nil nil "N")
    (make-key "m" VK_M nil nil nil "M")
    (make-key "," VK_OEM_COMMA nil nil nil "<")
    (make-key "." VK_OEM_PERIOD nil nil nil ">")
    (make-key "/" VK_OEM_2 nil nil nil "?")
    (make-key "Shift" VK_SHIFT 80 true)]
   [(make-key "Space" VK_SPACE 705)
    (make-key ime-label VK_SHIFT 85 false true)]])

(defn- build-layout [hwnd ime-label]
  (let [buttons @[]]
    (each [row-idx keys] (pairs (make-keyboard-rows ime-label))
      (let [y (+ keyboard-margin-y (* row-idx row-height))
            row (justified-row keys)]
        (each [key x w] row
          (let [label16 (to-utf16 (key :label))
                btn-hwnd (create-key hwnd label16 x y w key-height)
                btn (merge key {:hwnd btn-hwnd
                                :row row-idx
                                :base-x x
                                :base-y y
                                :base-w w
                                :base-h key-height})]
            (array/push buttons btn)))))
    buttons))

# -----------------------------------------------------------------------------
# 主循环

(defn- point-in-rect? [px py rect]
  (let [[l t r b] rect]
    (and (>= px l) (< px r) (>= py t) (< py b))))

(defn- point-in-gripper? [px py gripper]
  (let [buf (buffer/new-filled (ffi/size (structs :rect)))]
    (call "GetWindowRect" gripper buf)
    (point-in-rect? px py (ffi/read (structs :rect) buf))))

(defn- find-hit-button [px py buttons]
  (def rect-buf (buffer/new-filled (ffi/size (structs :rect))))
  (find
    (fn [btn]
      (call "GetWindowRect" (btn :hwnd) rect-buf)
      (point-in-rect? px py (ffi/read (structs :rect) rect-buf)))
    buttons))

(defn- update-shift-labels [shift-btns shift?]
  (each btn shift-btns
    (call "SetWindowTextW" (btn :hwnd)
          (to-utf16 (if shift? "SHIFT(ON)" "Shift")))))

(defn- letter? [vk]
  (and (>= vk VK_A) (<= vk VK_Z)))

(defn- update-key-labels [buttons shift?]
  (each btn buttons
    (when (not (or (btn :toggle?) (btn :ime?)))
      (call "SetWindowTextW" (btn :hwnd)
            (to-utf16 (if shift? (btn :shift-label) (btn :label)))))))

(defn- set-key-pressed [btn pressed?]
  (let [style (call "GetWindowLongPtrW" (btn :hwnd) GWL_STYLE)
        new-style (if pressed?
                    (bor style SS_SUNKEN)
                    (band style (bnot SS_SUNKEN)))]
    (call "SetWindowLongPtrW" (btn :hwnd) GWL_STYLE new-style)
    (call "SetWindowPos" (btn :hwnd) nil 0 0 0 0
          (+ SWP_NOMOVE SWP_NOSIZE SWP_NOACTIVATE SWP_FRAMECHANGED SWP_NOZORDER))))

(defn- create-font [height]
  (call "CreateFontW" height 0 0 0 400 0 0 0 0 0 0 0 0 nil))

(defn- reposition-buttons [hwnd buttons gripper base-client-w base-client-h new-client-w new-client-h old-font]
  (let [scale-x (/ new-client-w base-client-w)
        scale-y (/ new-client-h base-client-h)
        font-height (math/round (* key-height 0.4 scale-y))
        new-font (create-font (max 8 font-height))]
    (each btn buttons
      (let [btn-w (math/round (* (btn :base-w) scale-x))
            btn-h (math/round (* (btn :base-h) scale-y))]
        (call "SetWindowPos" (btn :hwnd) nil
              (math/round (* (btn :base-x) scale-x))
              (math/round (* (btn :base-y) scale-y))
              btn-w
              btn-h
              (+ SWP_NOZORDER SWP_NOACTIVATE))
        (call "SendMessageW" (btn :hwnd) WM_SETFONT new-font nil)))
    (call "SetWindowPos" gripper nil
          (- new-client-w GRIPPER-SIZE)
          (- new-client-h GRIPPER-SIZE)
          GRIPPER-SIZE GRIPPER-SIZE
          (+ SWP_NOZORDER SWP_NOACTIVATE))
    (call "SendMessageW" gripper WM_SETFONT new-font nil)
    (when (not (nil? old-font))
      (call "DeleteObject" old-font))
    (call "InvalidateRect" hwnd nil 1)
    new-font))

(defn- run-loop [hwnd buttons gripper base-client-w base-client-h]
  (var current-font nil)
  (var last-window-rect nil)
  (let [msg-buf (buffer/new-filled MSG-BUF-SIZE)
        pt-buf (buffer/new-filled (ffi/size (structs :point)))
        shift-btns (filter |($ :toggle?) buttons)
        # 非客户区尺寸，用于把客户区大小换算成完整窗口大小
        win-buf (buffer/new-filled (ffi/size (structs :rect)))
        client-buf (buffer/new-filled (ffi/size (structs :rect)))
        _ (call "GetWindowRect" hwnd win-buf)
        _ (call "GetClientRect" hwnd client-buf)
        [wl wt wr wb] (ffi/read (structs :rect) win-buf)
        [cl ct cr cb] (ffi/read (structs :rect) client-buf)
        nc-w (- (- wr wl) (- cr cl))
        nc-h (- (- wb wt) (- cb ct))
        base-ratio (/ base-client-w base-client-h)]
    (set last-window-rect [wl wt (- wr wl) (- wb wt)])
    (set current-font (reposition-buttons hwnd buttons gripper base-client-w base-client-h base-client-w base-client-h nil))
    (update-key-labels buttons false)
    (var running true)
    (var prev-lbutton false)
    (var shift? false)
    (var pressed-btn nil)
    (var pressed-at 0)
    (var dragging-gripper false)
    (var drag-start-x 0)
    (var drag-start-y 0)
    (var drag-start-w 0)
    (var drag-start-h 0)
    (while running
      # 处理所有待处理消息
      (var has-msg true)
      (while has-msg
        (set has-msg (not= 0 (call "PeekMessageW" msg-buf nil 0 0 PM_REMOVE)))
        (when has-msg
          (call "TranslateMessage" msg-buf)
          (call "DispatchMessageW" msg-buf)))

      # 检查窗口是否还存在
      (when (= 0 (call "IsWindow" hwnd))
        (set running false)
        (break))

      (call "GetWindowRect" hwnd win-buf)
      (let [[l t r b] (ffi/read (structs :rect) win-buf)]
        (set last-window-rect [l t (- r l) (- b t)]))

      # 鼠标左键轮询
      (let [state (call "GetAsyncKeyState" VK_LBUTTON)
            down? (not= 0 (band state 0x8000))]
        (when (and down? (not prev-lbutton))
          # 刚按下
          (call "GetCursorPos" pt-buf)
          (let [[cx cy] (ffi/read (structs :point) pt-buf)
                hit (find-hit-button cx cy buttons)
                gripper-hit (point-in-gripper? cx cy gripper)]
            (cond
              gripper-hit
              (do
                (set dragging-gripper true)
                (set drag-start-x cx)
                (set drag-start-y cy)
                (call "GetWindowRect" hwnd win-buf)
                (let [[l t r b] (ffi/read (structs :rect) win-buf)]
                  (set drag-start-w (- r l))
                  (set drag-start-h (- b t))))

              hit
              (do
                (print "点击: " (hit :label))
                (flush)
                (set pressed-btn hit)
                (set pressed-at (os/clock))
                (set-key-pressed hit true)
                # 输入法按钮直接切换输入法；普通按键直接发送；Shift 的长/短按在松开时判断
                (cond
                  (hit :ime?)
                  (do
                    (print "切换输入法")
                    (flush)
                    (toggle-ime))
                  (not (hit :toggle?))
                  (send-key (hit :vk) shift?))))))
        (when (and down? dragging-gripper)
          # 拖动中：根据鼠标位移调整窗口大小，保持宽高比
          (call "GetCursorPos" pt-buf)
          (let [[cx cy] (ffi/read (structs :point) pt-buf)
                delta-x (- cx drag-start-x)
                delta-y (- cy drag-start-y)
                raw-w (+ drag-start-w delta-x)
                raw-h (+ drag-start-h delta-y)
                # 保持客户区宽高比
                client-w (max 400 (- raw-w nc-w))
                client-h (max 200 (- raw-h nc-h))
                ratio (/ client-w client-h)
                [final-client-w final-client-h]
                (if (> ratio base-ratio)
                  [(math/round (* client-h base-ratio)) client-h]
                  [client-w (math/round (/ client-w base-ratio))])
                final-w (+ final-client-w nc-w)
                final-h (+ final-client-h nc-h)]
            (call "SetWindowPos" hwnd nil 0 0 final-w final-h
                  (+ SWP_NOMOVE SWP_NOZORDER SWP_NOACTIVATE))
            (set current-font (reposition-buttons hwnd buttons gripper base-client-w base-client-h final-client-w final-client-h current-font))))
        (when (and (not down?) prev-lbutton)
          # 刚松开
          (set dragging-gripper false)
          (when pressed-btn
            (set-key-pressed pressed-btn false)
            (when (pressed-btn :toggle?)
              (let [duration (- (os/clock) pressed-at)]
                (if (>= duration LONG-PRESS-THRESHOLD)
                  (do
                    (print "长按 Shift：切换输入法中/英")
                    (flush)
                    (toggle-ime))
                  (do
                    (set shift? (not shift?))
                    (update-shift-labels shift-btns shift?)
                    (update-key-labels buttons shift?)))))
            (set pressed-btn nil)))
        (set prev-lbutton down?))

      (ev/sleep 0.01))
    (save-window-rect last-window-rect)
    current-font))

# -----------------------------------------------------------------------------
# 入口

(defn- arg-value [args prefix]
  (when-let [arg (find |(string/has-prefix? prefix $) args)]
    (string/slice arg (length prefix))))

(defn- normalize-language-code [code]
  (if (has-key? IME-LABELS code)
    code
    DEFAULT-LANGUAGE-CODE))

(defn- language-code [args]
  (normalize-language-code
    (or (arg-value args "--code=")
        (find |(has-key? IME-LABELS $) args)
        DEFAULT-LANGUAGE-CODE)))

(defn- ime-label-for-code [code]
  (or (IME-LABELS code)
      (IME-LABELS DEFAULT-LANGUAGE-CODE)))

(defn main [& args]
  (ensure-ffi!)
  (let [ime-label (ime-label-for-code (language-code args))
        class-name16 (to-utf16 "JanetSoftKeyboardClass")
        title16 (to-utf16 WINDOW-TITLE)
        [x y w h] (load-window-rect)
        _ (register-class! class-name16)
        hwnd (create-main-window class-name16 title16 x y w h)
        client-buf (buffer/new-filled (ffi/size (structs :rect)))
        _ (call "GetClientRect" hwnd client-buf)
        [_ _ base-client-w base-client-h] (ffi/read (structs :rect) client-buf)
        buttons (build-layout hwnd ime-label)
        gripper (create-gripper hwnd (- base-client-w GRIPPER-SIZE) (- base-client-h GRIPPER-SIZE))]
    (call "ShowWindow" hwnd SW_SHOWNA)
    (call "UpdateWindow" hwnd)
    (print "软键盘已启动。点击按键发送输入，拖动右下角调整大小，关闭窗口退出。")
    (let [final-font (run-loop hwnd buttons gripper base-client-w base-client-h)]
      (when (not (nil? final-font))
        (call "DeleteObject" final-font)))
    # 清理
    (call "UnregisterClassW" class-name16 (call "GetModuleHandleW" nil))))

# 仅在直接运行源码时执行 main；jpm build 会 dofile 本文件收集 main，不能在加载阶段启动窗口。
(when (or (find |(= $ "--run") (dyn :args))
          (and (first (dyn :args))
               (string/has-suffix? "softkeyboard.janet" (first (dyn :args)))))
  (main))
