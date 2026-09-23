#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

#ifndef NQ_NCI_DEV
#define NQ_NCI_DEV "/dev/nq-nci"
#endif

#define NCI_HEADER_SIZE 3U
#define NCI_MAX_PAYLOAD 255U
#define NCI_MAX_PACKET (NCI_HEADER_SIZE + NCI_MAX_PAYLOAD)
#define COMMAND_MAX 1024U
#define RESPONSE_MAX (NCI_MAX_PACKET * 4U + 32U)
#define INIT_TIMEOUT_SECONDS 2

static volatile sig_atomic_t stop_requested;
static volatile sig_atomic_t read_timed_out;
static int nci_fd = -1;
static int listener_fd = -1;
static char socket_path[sizeof(((struct sockaddr_un *)0)->sun_path)];

static void on_stop_signal(int signal_number)
{
    (void)signal_number;
    stop_requested = 1;
}

static void on_alarm(int signal_number)
{
    (void)signal_number;
    read_timed_out = 1;
}

static int install_signal_handlers(void)
{
    struct sigaction action;

    memset(&action, 0, sizeof(action));
    action.sa_handler = on_stop_signal;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGINT, &action, NULL) < 0 ||
        sigaction(SIGTERM, &action, NULL) < 0) {
        perror("sigaction");
        return -1;
    }
    action.sa_handler = on_alarm;
    if (sigaction(SIGALRM, &action, NULL) < 0) {
        perror("sigaction SIGALRM");
        return -1;
    }
    signal(SIGPIPE, SIG_IGN);
    return 0;
}

static int nci_open(void)
{
    nci_fd = open(NQ_NCI_DEV, O_RDWR | O_CLOEXEC);
    if (nci_fd < 0) {
        perror("open " NQ_NCI_DEV);
        return -1;
    }
    return 0;
}

static void nci_close(void)
{
    if (nci_fd >= 0) {
        close(nci_fd);
        nci_fd = -1;
    }
}

static int hex_digit(char value)
{
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    if (value >= 'A' && value <= 'F') return value - 'A' + 10;
    return -1;
}

static int hex_to_bytes(const char *hex, unsigned char *out, size_t capacity)
{
    size_t len = strlen(hex);

    if (len == 0 || (len % 2) != 0 || len / 2 > capacity) return -1;
    for (size_t i = 0; i < len / 2; i++) {
        int high = hex_digit(hex[2 * i]);
        int low = hex_digit(hex[2 * i + 1]);
        if (high < 0 || low < 0) return -1;
        out[i] = (unsigned char)((high << 4) | low);
    }
    return (int)(len / 2);
}

static void bytes_to_hex(const unsigned char *bytes, size_t len,
                         char *out, size_t capacity)
{
    static const char digits[] = "0123456789abcdef";
    size_t needed = len * 2 + 1;

    if (capacity < needed) {
        if (capacity) out[0] = '\0';
        return;
    }
    for (size_t i = 0; i < len; i++) {
        out[2 * i] = digits[bytes[i] >> 4];
        out[2 * i + 1] = digits[bytes[i] & 0x0f];
    }
    out[2 * len] = '\0';
}

static int validate_frame(const unsigned char *frame, size_t len)
{
    if (len < NCI_HEADER_SIZE || len > NCI_MAX_PACKET) return -1;
    return len == NCI_HEADER_SIZE + frame[2] ? 0 : -1;
}

static int nci_write_frame(const unsigned char *frame, size_t len)
{
    ssize_t written;

    if (validate_frame(frame, len) < 0) {
        errno = EPROTO;
        return -1;
    }
    written = write(nci_fd, frame, len);
    if (written < 0 || (size_t)written != len) {
        if (written >= 0) errno = EIO;
        perror("write NCI frame");
        return -1;
    }
    return 0;
}

/* NXP driver's blocking read is interruptible; alarm bounds reset/init waits. */
static ssize_t nci_read_frame(unsigned char *frame, size_t capacity,
                              unsigned int timeout_seconds)
{
    ssize_t received;

    if (capacity < NCI_MAX_PACKET) {
        errno = EMSGSIZE;
        return -1;
    }
    read_timed_out = 0;
    alarm(timeout_seconds);
    received = read(nci_fd, frame, capacity);
    alarm(0);
    if (received < 0) {
        if (errno == EINTR && read_timed_out) errno = ETIMEDOUT;
        return -1;
    }
    if (validate_frame(frame, (size_t)received) < 0) {
        errno = EPROTO;
        return -1;
    }
    return received;
}

static int write_all(int fd, const void *data, size_t len)
{
    const unsigned char *cursor = data;

    while (len) {
        ssize_t written = write(fd, cursor, len);
        if (written < 0) {
            if (errno == EINTR && !stop_requested) continue;
            return -1;
        }
        if (written == 0) {
            errno = EIO;
            return -1;
        }
        cursor += (size_t)written;
        len -= (size_t)written;
    }
    return 0;
}

static int send_line(int fd, const char *line)
{
    return write_all(fd, line, strlen(line));
}

static int read_line(int fd, char *line, size_t capacity)
{
    size_t used = 0;

    while (used + 1 < capacity) {
        char ch;
        ssize_t n = read(fd, &ch, 1);
        if (n == 0) return used ? (line[used] = '\0', (int)used) : 0;
        if (n < 0) {
            if (errno == EINTR && !stop_requested) continue;
            return -1;
        }
        if (ch == '\n') {
            line[used] = '\0';
            return (int)used;
        }
        line[used++] = ch;
    }
    errno = EMSGSIZE;
    return -1;
}

static int response_frame(unsigned char *frame, ssize_t *len)
{
    *len = nci_read_frame(frame, NCI_MAX_PACKET, INIT_TIMEOUT_SECONDS);
    if (*len < 0) {
        if (errno != ETIMEDOUT && errno != EINTR) perror("read NCI response");
        return -1;
    }
    return 0;
}

static int handle_init(int client_fd)
{
    const unsigned char reset[] = {0x20, 0x00, 0x01, 0x00};
    const unsigned char init[] = {0x20, 0x01, 0x00};
    unsigned char reset_rsp[NCI_MAX_PACKET], init_rsp[NCI_MAX_PACKET];
    char reset_hex[NCI_MAX_PACKET * 2 + 1], init_hex[NCI_MAX_PACKET * 2 + 1];
    char response[RESPONSE_MAX];
    ssize_t reset_len, init_len;

    if (nci_write_frame(reset, sizeof(reset)) < 0 ||
        response_frame(reset_rsp, &reset_len) < 0) {
        snprintf(response, sizeof(response), "ERROR reset failed: %s\n", strerror(errno));
        send_line(client_fd, response);
        return -1;
    }
    if (nci_write_frame(init, sizeof(init)) < 0 ||
        response_frame(init_rsp, &init_len) < 0) {
        snprintf(response, sizeof(response), "ERROR init failed: %s\n", strerror(errno));
        send_line(client_fd, response);
        return -1;
    }
    bytes_to_hex(reset_rsp, (size_t)reset_len, reset_hex, sizeof(reset_hex));
    bytes_to_hex(init_rsp, (size_t)init_len, init_hex, sizeof(init_hex));
    snprintf(response, sizeof(response), "OK INIT %s %s\n", reset_hex, init_hex);
    return send_line(client_fd, response);
}

static int handle_send(int client_fd, const char *hex)
{
    unsigned char frame[NCI_MAX_PACKET], response_frame_buf[NCI_MAX_PACKET];
    char response[RESPONSE_MAX], normalized[NCI_MAX_PACKET * 2 + 1];
    char response_hex[NCI_MAX_PACKET * 2 + 1];
    ssize_t response_len;
    int len = hex_to_bytes(hex, frame, sizeof(frame));

    if (len < 0 || validate_frame(frame, (size_t)len) < 0)
        return send_line(client_fd, "ERROR invalid NCI frame\n");
    if (nci_write_frame(frame, (size_t)len) < 0) {
        snprintf(response, sizeof(response), "ERROR write failed: %s\n", strerror(errno));
        return send_line(client_fd, response);
    }
    bytes_to_hex(frame, (size_t)len, normalized, sizeof(normalized));
    if (response_frame(response_frame_buf, &response_len) == 0) {
        bytes_to_hex(response_frame_buf, (size_t)response_len,
                     response_hex, sizeof(response_hex));
        snprintf(response, sizeof(response), "OK %s RESPONSE %s\n",
                 normalized, response_hex);
    } else if (errno == ETIMEDOUT) {
        snprintf(response, sizeof(response), "OK %s NO_RESPONSE\n", normalized);
    } else {
        snprintf(response, sizeof(response), "ERROR response read failed: %s\n",
                 strerror(errno));
        return send_line(client_fd, response);
    }
    return send_line(client_fd, response);
}

static int handle_capture(int client_fd, const char *seconds_text)
{
    char *end = NULL;
    long seconds = strtol(seconds_text, &end, 10);
    time_t deadline;
    unsigned char frame[NCI_MAX_PACKET];
    char frame_hex[NCI_MAX_PACKET * 2 + 1], response[RESPONSE_MAX];

    if (!end || *end != '\0' || seconds < 1 || seconds > 86400)
        return send_line(client_fd, "ERROR duration must be 1..86400 seconds\n");
    deadline = time(NULL) + seconds;
    while (!stop_requested && time(NULL) < deadline) {
        unsigned int remaining = (unsigned int)(deadline - time(NULL));
        ssize_t len = nci_read_frame(frame, sizeof(frame), remaining ? remaining : 1);
        if (len < 0) {
            if (errno == ETIMEDOUT || (errno == EINTR && stop_requested)) break;
            snprintf(response, sizeof(response), "ERROR capture failed: %s\n", strerror(errno));
            send_line(client_fd, response);
            return -1;
        }
        bytes_to_hex(frame, (size_t)len, frame_hex, sizeof(frame_hex));
        snprintf(response, sizeof(response), "FRAME %s\n", frame_hex);
        if (send_line(client_fd, response) < 0) return -1;
    }
    return send_line(client_fd, "END\n");
}

static int handle_client(int client_fd)
{
    char line[COMMAND_MAX];

    while (!stop_requested) {
        int len = read_line(client_fd, line, sizeof(line));
        if (len == 0) return 0;
        if (len < 0) return stop_requested ? 0 : -1;
        if (!strcmp(line, "INIT")) {
            if (handle_init(client_fd) < 0) return -1;
        } else if (!strncmp(line, "SEND ", 5)) {
            if (handle_send(client_fd, line + 5) < 0) return -1;
        } else if (!strncmp(line, "CAPTURE ", 8)) {
            return handle_capture(client_fd, line + 8);
        } else {
            if (send_line(client_fd, "ERROR malformed command\n") < 0) return -1;
        }
    }
    return 0;
}

static int create_listener(const char *path)
{
    struct sockaddr_un address;
    struct stat st;

    if (strlen(path) >= sizeof(address.sun_path)) {
        errno = ENAMETOOLONG;
        perror("socket path");
        return -1;
    }
    if (lstat(path, &st) == 0) {
        fprintf(stderr, "socket path already exists: %s\n", path);
        return -1;
    }
    if (errno != ENOENT) {
        perror("lstat socket path");
        return -1;
    }
    listener_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (listener_fd < 0) {
        perror("socket");
        return -1;
    }
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    memcpy(address.sun_path, path, strlen(path) + 1);
    if (bind(listener_fd, (struct sockaddr *)&address, sizeof(address)) < 0 ||
        chmod(path, S_IRUSR | S_IWUSR) < 0 || listen(listener_fd, 1) < 0) {
        perror("prepare session socket");
        close(listener_fd);
        listener_fd = -1;
        unlink(path);
        return -1;
    }
    memcpy(socket_path, path, strlen(path) + 1);
    return 0;
}

static int cmd_session(const char *path)
{
    int result = 0;

    stop_requested = 0;
    if (install_signal_handlers() < 0 || create_listener(path) < 0) return 1;
    if (nci_open() < 0) {
        unlink(socket_path);
        close(listener_fd);
        listener_fd = -1;
        return 1;
    }
    while (!stop_requested) {
        int client_fd = accept(listener_fd, NULL, NULL);
        if (client_fd < 0) {
            if (errno == EINTR && stop_requested) break;
            if (errno == EINTR) continue;
            perror("accept");
            result = 1;
            break;
        }
        if (handle_client(client_fd) < 0 && !stop_requested) result = 1;
        close(client_fd);
    }
    nci_close();
    close(listener_fd);
    listener_fd = -1;
    unlink(socket_path);
    return result;
}

static int connect_socket(const char *path)
{
    int fd;
    struct sockaddr_un address;

    if (strlen(path) >= sizeof(address.sun_path)) {
        errno = ENAMETOOLONG;
        return -1;
    }
    fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return -1;
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    memcpy(address.sun_path, path, strlen(path) + 1);
    if (connect(fd, (struct sockaddr *)&address, sizeof(address)) < 0) {
        close(fd);
        return -1;
    }
    return fd;
}

static int client_command(const char *path, const char *command, bool stream)
{
    int fd = connect_socket(path);
    char response[COMMAND_MAX];

    if (fd < 0) {
        perror("connect session socket");
        return 1;
    }
    if (send_line(fd, command) < 0 || send_line(fd, "\n") < 0) {
        perror("send session command");
        close(fd);
        return 1;
    }
    for (;;) {
        int len = read_line(fd, response, sizeof(response));
        if (len <= 0) {
            close(fd);
            return len == 0 && stream ? 0 : 1;
        }
        puts(response);
        if (!strncmp(response, "ERROR", 5)) {
            close(fd);
            return 1;
        }
        if (!strcmp(response, "END")) {
            close(fd);
            return 0;
        }
        if (!stream) {
            close(fd);
            return 0;
        }
    }
}

static int usage(const char *name)
{
    fprintf(stderr,
            "Usage: %s probe\n"
            "       %s session --socket <path>\n"
            "       %s init --socket <path>\n"
            "       %s send --socket <path> <nci-hex>\n"
            "       %s capture --socket <path> <seconds>\n",
            name, name, name, name, name);
    return 2;
}

int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "probe")) {
        struct stat st;
        if (stat(NQ_NCI_DEV, &st) < 0 || access(NQ_NCI_DEV, R_OK | W_OK) < 0) {
            perror("probe " NQ_NCI_DEV);
            return 1;
        }
        if (nci_open() < 0) return 1;
        nci_close();
        printf("OK: %s opened and closed\n", NQ_NCI_DEV);
        return 0;
    }
    if (argc == 4 && !strcmp(argv[1], "session") && !strcmp(argv[2], "--socket"))
        return cmd_session(argv[3]);
    if (argc == 4 && !strcmp(argv[1], "init") && !strcmp(argv[2], "--socket"))
        return client_command(argv[3], "INIT", false);
    if (argc == 5 && !strcmp(argv[1], "send") && !strcmp(argv[2], "--socket")) {
        unsigned char frame[NCI_MAX_PACKET];
        int len = hex_to_bytes(argv[4], frame, sizeof(frame));
        if (len < 0 || validate_frame(frame, (size_t)len) < 0) {
            fprintf(stderr, "Invalid NCI frame hex\n");
            return 1;
        }
        char command[NCI_MAX_PACKET * 2 + 8];
        snprintf(command, sizeof(command), "SEND %s", argv[4]);
        return client_command(argv[3], command, false);
    }
    if (argc == 5 && !strcmp(argv[1], "capture") && !strcmp(argv[2], "--socket")) {
        char *end = NULL;
        long seconds = strtol(argv[4], &end, 10);
        if (!end || *end || seconds < 1 || seconds > 86400) {
            fprintf(stderr, "Invalid capture duration; use 1..86400 seconds\n");
            return 1;
        }
        char command[64];
        snprintf(command, sizeof(command), "CAPTURE %ld", seconds);
        return client_command(argv[3], command, true);
    }
    return usage(argv[0]);
}
