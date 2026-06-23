(def janet-home (os/getenv "JANET_BUILD_HOME" "C:/Users/Administrator/scoop/apps/janet/1.40.1"))

(put root-env :syspath (string janet-home "/lib/janet"))

(import jpm/cli)

(cli/main
 ;["--use-batch-shell"
   (string "--headerpath=" janet-home "/C")
   (string "--libpath=" janet-home "/C")
   "build"])
