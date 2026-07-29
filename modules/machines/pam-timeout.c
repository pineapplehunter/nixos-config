#define _GNU_SOURCE

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pwd.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define TIMEOUT_DIR "pam-timeout"
#define STAMP_FILE "password_login_time"
#define MAX_AGE_SECONDS (12ULL * 60ULL * 60ULL)

static bool secure_directory(int fd, bool private)
{
    struct stat st;

    if (fstat(fd, &st) < 0 || !S_ISDIR(st.st_mode) || st.st_uid != 0)
        return false;

    /* /run may be world-readable, but it must not be writable by non-root. */
    return (st.st_mode & (private ? 0077 : 0022)) == 0;
}

static bool valid_user(const char *user)
{
    const unsigned char *p;
    struct passwd *pw;
    size_t len;

    if (user == NULL || user[0] == '\0')
        return false;

    len = strlen(user);
    if (len > NAME_MAX || strcmp(user, ".") == 0 || strcmp(user, "..") == 0)
        return false;

    for (p = (const unsigned char *)user; *p != '\0'; p++) {
        if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
              (*p >= '0' && *p <= '9') || *p == '_' || *p == '-' || *p == '.'))
            return false;
    }

    /* Reject unknown users and aliases whose canonical name differs. */
    pw = getpwnam(user);
    return pw != NULL && strcmp(pw->pw_name, user) == 0;
}

static int open_timeout_dir(bool create)
{
    int run_fd = -1, timeout_fd = -1;

    run_fd = open("/run", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (run_fd < 0 || !secure_directory(run_fd, false))
        goto out;

    if (create && mkdirat(run_fd, TIMEOUT_DIR, 0700) < 0 && errno != EEXIST)
        goto out;

    timeout_fd = openat(run_fd, TIMEOUT_DIR,
                        O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (timeout_fd < 0 || !secure_directory(timeout_fd, true)) {
        if (timeout_fd >= 0)
            close(timeout_fd);
        timeout_fd = -1;
    }

out:
    if (run_fd >= 0)
        close(run_fd);
    return timeout_fd;
}

static int open_user_dir(const char *user, bool create)
{
    int timeout_fd = -1, user_fd = -1;

    timeout_fd = open_timeout_dir(create);
    if (timeout_fd < 0)
        return -1;

    if (create && mkdirat(timeout_fd, user, 0700) < 0 && errno != EEXIST)
        goto out;

    user_fd = openat(timeout_fd, user,
                     O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    if (user_fd < 0 || !secure_directory(user_fd, true)) {
        if (user_fd >= 0)
            close(user_fd);
        user_fd = -1;
    }

out:
    close(timeout_fd);
    return user_fd;
}

static bool boot_time(uint64_t *seconds)
{
    struct timespec ts;

    if (clock_gettime(CLOCK_BOOTTIME, &ts) < 0 || ts.tv_sec < 0)
        return false;
    *seconds = (uint64_t)ts.tv_sec;
    return true;
}

static int check_stamp(const char *user)
{
    char buf[32], *end;
    struct stat st;
    uint64_t now, stamp;
    unsigned long long parsed;
    ssize_t len, extra;
    int user_fd = -1, stamp_fd = -1;
    int result = EXIT_FAILURE;

    user_fd = open_user_dir(user, false);
    if (user_fd < 0)
        goto out;

    stamp_fd = openat(user_fd, STAMP_FILE, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (stamp_fd < 0 || fstat(stamp_fd, &st) < 0 || !S_ISREG(st.st_mode) ||
        st.st_uid != 0 || (st.st_mode & 0077) != 0 || st.st_nlink != 1)
        goto out;

    len = read(stamp_fd, buf, sizeof(buf) - 1);
    if (len <= 0)
        goto out;
    extra = read(stamp_fd, buf + len, 1);
    if (extra != 0)
        goto out;
    buf[len] = '\0';

    errno = 0;
    end = NULL;
    parsed = strtoull(buf, &end, 10);
    if (errno != 0 || end == buf ||
        !(*end == '\0' || (*end == '\n' && end[1] == '\0')))
        goto out;

    stamp = (uint64_t)parsed;
    if (!boot_time(&now) || stamp > now || now - stamp >= MAX_AGE_SECONDS)
        goto out;

    result = EXIT_SUCCESS;

out:
    if (stamp_fd >= 0)
        close(stamp_fd);
    if (user_fd >= 0)
        close(user_fd);
    return result;
}

static int clear_stamp(const char *user)
{
    int user_fd;
    int result = EXIT_FAILURE;

    user_fd = open_user_dir(user, false);
    if (user_fd < 0)
        return EXIT_SUCCESS; /* A missing or unsafe stamp cannot authorize. */

    if (unlinkat(user_fd, STAMP_FILE, 0) == 0) {
        if (fsync(user_fd) == 0)
            result = EXIT_SUCCESS;
    } else if (errno == ENOENT) {
        result = EXIT_SUCCESS;
    }

    close(user_fd);
    return result;
}

static int update_stamp(const char *user)
{
    char value[32], temporary[64];
    uint64_t now;
    int user_fd = -1, stamp_fd = -1;
    int result = EXIT_FAILURE;
    int length;
    unsigned int attempt;

    if (!boot_time(&now))
        return EXIT_FAILURE;

    user_fd = open_user_dir(user, true);
    if (user_fd < 0)
        goto out;

    for (attempt = 0; attempt < 100; attempt++) {
        snprintf(temporary, sizeof(temporary), ".stamp.%ld.%u",
                 (long)getpid(), attempt);
        stamp_fd = openat(user_fd, temporary,
                          O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                          0600);
        if (stamp_fd >= 0)
            break;
        if (errno != EEXIST)
            goto out;
    }
    if (stamp_fd < 0)
        goto out;

    length = snprintf(value, sizeof(value), "%llu\n",
                      (unsigned long long)now);
    if (length <= 0 || (size_t)length >= sizeof(value) ||
        write(stamp_fd, value, (size_t)length) != length || fsync(stamp_fd) < 0)
        goto remove_temporary;

    if (close(stamp_fd) < 0) {
        stamp_fd = -1;
        goto remove_temporary;
    }
    stamp_fd = -1;

    if (renameat(user_fd, temporary, user_fd, STAMP_FILE) < 0 ||
        fsync(user_fd) < 0)
        goto remove_temporary;

    result = EXIT_SUCCESS;
    goto out;

remove_temporary:
    unlinkat(user_fd, temporary, 0);
out:
    if (stamp_fd >= 0)
        close(stamp_fd);
    if (user_fd >= 0)
        close(user_fd);
    return result;
}

int main(int argc, char **argv)
{
    const char *user;

    /* PAM callers using this authorization state must execute us as root. */
    if (geteuid() != 0 || argc != 2)
        return EXIT_FAILURE;

    user = getenv("PAM_USER");
    if (!valid_user(user))
        return EXIT_FAILURE;

    if (strcmp(argv[1], "check") == 0)
        return check_stamp(user);
    if (strcmp(argv[1], "update") == 0)
        return update_stamp(user);
    if (strcmp(argv[1], "clear-on-close") == 0) {
        const char *pam_type = getenv("PAM_TYPE");

        if (pam_type == NULL || strcmp(pam_type, "close_session") != 0)
            return EXIT_SUCCESS;
        return clear_stamp(user);
    }
    return EXIT_FAILURE;
}
