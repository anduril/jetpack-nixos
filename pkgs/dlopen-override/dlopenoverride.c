#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

// List of paths to replace
const char *old_paths[] = { "@oldpaths@" };
const char *new_paths[] = { "@newpaths@" };
const int num_paths = sizeof(old_paths) / sizeof(old_paths[0]);

void *__dlopen(const char *filename, int flag) {
    if (filename) {
        for (int i = 0; i < num_paths; i++) {
            if (strcmp(filename, old_paths[i]) == 0) {
                fprintf(stderr, "Redirecting %s to %s\n", filename, new_paths[i]);
                filename = new_paths[i];
                break;
            }
        }
    }

    return dlopen(filename, flag);
}
