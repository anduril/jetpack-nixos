#include <stdio.h>
#include <dlfcn.h>
#include <stdlib.h>

typedef void (*hello_func)();

int main() {
    void *lib_handle;
    hello_func hello_lib;
    char *error;

    // Hard coded dlopen to lib1.so
    lib_handle = dlopen("./lib1.so", RTLD_LAZY);
    if (!lib_handle) {
        fprintf(stderr, "%s\n", dlerror());
        exit(EXIT_FAILURE);
    }
    dlerror(); // Clear any existing error

    // Load the symbol for lib
    hello_lib = (hello_func)  dlsym(lib_handle, "hello_lib");
    if ((error = dlerror()) != NULL)  {
        fprintf(stderr, "%s\n", error);
        exit(EXIT_FAILURE);
    }

    hello_lib();

    dlclose(lib_handle);

    return 0;
}
