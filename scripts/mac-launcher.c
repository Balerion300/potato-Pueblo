/* Native bundle entry point using the pinned, statically linked Tcl/Tk runtime. */
#include <tk.h>
#include <mach-o/dyld.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int app_init(Tcl_Interp *interp) {
    if (Tcl_Init(interp) != TCL_OK || Tk_Init(interp) != TCL_OK) return TCL_ERROR;
    Tcl_StaticPackage(interp, "Tk", Tk_Init, Tk_SafeInit);
    return TCL_OK;
}

int main(int argc, char **argv) {
    char executable[PATH_MAX], resources[PATH_MAX], path[PATH_MAX];
    uint32_t size = sizeof(executable);
    if (_NSGetExecutablePath(executable, &size) || !realpath(executable, path)) return 1;
    char *slash = strrchr(path, '/');
    if (!slash) return 1;
    *slash = '\0';
    slash = strrchr(path, '/');
    if (!slash) return 1;
    *slash = '\0';
    if (snprintf(resources, sizeof(resources), "%s/Resources", path) >= sizeof(resources)) return 1;
    if (snprintf(path, sizeof(path), "%s/runtime/lib/tcl8.6", resources) >= sizeof(path)) return 1;
    setenv("TCL_LIBRARY", path, 1);
    if (snprintf(path, sizeof(path), "%s/runtime/lib/tk8.6", resources) >= sizeof(path)) return 1;
    setenv("TK_LIBRARY", path, 1);
    if (!getenv("POTATO_HOME")) {
        const char *home = getenv("HOME");
        if (!home || snprintf(path, sizeof(path), "%s/Library/Application Support/Potato-Pueblo-Preview", home) >= sizeof(path)) return 1;
        setenv("POTATO_HOME", path, 1);
    }
    char *default_args[] = {argv[0], path, NULL};
    if (argc == 1) {
        if (snprintf(path, sizeof(path), "%s/potato.vfs/main.tcl", resources) >= sizeof(path)) return 1;
        argc = 2;
        argv = default_args;
    }
    Tk_Main(argc, argv, app_init);
    return 0;
}
