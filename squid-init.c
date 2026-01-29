// squid-init.c
#define _GNU_SOURCE
#include <errno.h>
#include <getopt.h>
#include <grp.h>
#include <limits.h>
#include <pwd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static int mkdir_p(const char *path, mode_t mode) {
    struct stat st;

    if (!path || !*path) return -1;

    // Optimization: Check if path exists and is a directory first
    if (stat(path, &st) == 0) {
        if (S_ISDIR(st.st_mode)) return 0;
        errno = ENOTDIR;
        return -1;
    }

    // Enforce PATH_MAX limit
    size_t len = strnlen(path, PATH_MAX);
    if (len >= PATH_MAX) {
        errno = ENAMETOOLONG;
        return -1;
    }

    // Use heap allocation for path manipulation to avoid stack limitations
    char *copy = strdup(path);
    if (!copy) return -1; // errno set by strdup (ENOMEM)

    // Strip trailing slashes
    char *p = copy + len - 1;
    while (p > copy && *p == '/') {
        *p = '\0';
        p--;
    }

    // Iterate over path components
    for (p = copy; *p; p++) {
        if (*p == '/') {
            if (p == copy) continue; // Skip root slash

            *p = '\0';
            if (mkdir(copy, mode) != 0 && errno != EEXIST) {
                int saved_errno = errno;
                free(copy);
                errno = saved_errno;
                return -1;
            }
            *p = '/';
        }
    }

    // Create the final component
    if (mkdir(copy, mode) != 0 && errno != EEXIST) {
        int saved_errno = errno;
        free(copy);
        errno = saved_errno;
        return -1;
    }

    free(copy);
    return 0;
}

static int run_squid_z(const char *squid, const char *conf) {
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        execl(squid, squid, "-N", "-z", "-f", conf, (char *)NULL);
        fprintf(stderr, "execl failed: %s\n", strerror(errno));
        _exit(127);
    }
    int status = 0;
    while (waitpid(pid, &status, 0) < 0) {
        if (errno != EINTR) return -1;
    }
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    return -1;
}

static void print_help(const char *prog) {
    fprintf(stderr, "Usage: %s [options]\n", prog);
    fprintf(stderr, "Options:\n");
    fprintf(stderr, "  -b, --bin <path>    Path to squid binary\n");
    fprintf(stderr, "  -f, --conf <path>   Path to squid config\n");
    fprintf(stderr, "  -c, --cache <path>  Path to cache dir\n");
    fprintf(stderr, "  -h, --help          Show this help\n");
}

int main(int argc, char *argv[]) {
    const char *squid = NULL;
    const char *conf = NULL;
    const char *cache = NULL;

    static struct option long_options[] = {
        {"bin",   required_argument, 0, 'b'},
        {"conf",  required_argument, 0, 'f'},
        {"cache", required_argument, 0, 'c'},
        {"help",  no_argument,       0, 'h'},
        {0, 0, 0, 0}
    };

    int opt;
    while ((opt = getopt_long(argc, argv, "b:f:c:h", long_options, NULL)) != -1) {
        switch (opt) {
            case 'b': squid = optarg; break;
            case 'f': conf = optarg; break;
            case 'c': cache = optarg; break;
            case 'h': print_help(argv[0]); return 0;
            default: print_help(argv[0]); return 1;
        }
    }

    // Precedence: CLI > Environment > Default
    if (!squid || !*squid) squid = getenv("SQUID_BIN");
    if (!squid || !*squid) squid = "/usr/sbin/squid";

    if (!conf || !*conf) conf = getenv("SQUID_CONF");
    if (!conf || !*conf) conf = "/etc/squid/squid.conf";

    if (!cache || !*cache) cache = getenv("SQUID_CACHE_DIR");
    if (!cache || !*cache) cache = "/var/cache/squid";

    fprintf(stderr, "squid-init: Configuration:\n");
    fprintf(stderr, "  Binary: %s\n", squid);
    fprintf(stderr, "  Config: %s\n", conf);
    fprintf(stderr, "  Cache : %s\n", cache);

    if (access(squid, X_OK) != 0) {
        fprintf(stderr, "Error: Cannot execute %s: %s\n", squid, strerror(errno));
        return 1;
    }

    if (mkdir_p(cache, 0755) != 0) {
        fprintf(stderr, "Error: mkdir_p(%s) failed: %s\n", cache, strerror(errno));
        return 1;
    }

    fprintf(stderr, "squid-init: Initializing cache...\n");
    int zrc = run_squid_z(squid, conf);
    if (zrc != 0) {
        fprintf(stderr, "Error: 'squid -z' failed with code %d\n", zrc);
        return zrc < 0 ? 1 : zrc;
    }

    fprintf(stderr, "squid-init: Starting squid...\n");
    execl(squid, squid, "-N", "-f", conf, (char *)NULL);
    fprintf(stderr, "Error: exec squid failed: %s\n", strerror(errno));
    return 127;
}
