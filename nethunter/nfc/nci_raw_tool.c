#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/ioctl.h>
#include <errno.h>
#include <time.h>
#include <signal.h>

#define NQ_NCI_DEV "/dev/nq-nci"

static int nci_fd = -1;
static volatile int capturing = 1;

static void sighandler(int sig) {
    (void)sig;
    capturing = 0;
}

static int nci_open(void) {
    nci_fd = open(NQ_NCI_DEV, O_RDWR);
    if (nci_fd < 0) {
        perror("open " NQ_NCI_DEV);
        return -1;
    }
    return 0;
}

static void nci_close(void) {
    if (nci_fd >= 0) {
        close(nci_fd);
        nci_fd = -1;
    }
}

static int nci_write(const unsigned char *buf, size_t len) {
    ssize_t w = write(nci_fd, buf, len);
    if (w < 0 || (size_t)w != len) {
        perror("write");
        return -1;
    }
    return 0;
}

static int nci_read(unsigned char *buf, size_t maxlen, size_t *out_len) {
    ssize_t r = read(nci_fd, buf, maxlen);
    if (r < 0) {
        perror("read");
        return -1;
    }
    *out_len = (size_t)r;
    return 0;
}

static int hex_to_bytes(const char *hex, unsigned char *out, size_t max) {
    size_t len = strlen(hex);
    if (len % 2 != 0 || len / 2 > max) return -1;
    for (size_t i = 0; i < len / 2; i++) {
        unsigned int byte;
        if (sscanf(hex + 2 * i, "%2x", &byte) != 1) return -1;
        out[i] = (unsigned char)byte;
    }
    return (int)(len / 2);
}

static void print_hex(const unsigned char *buf, size_t len) {
    for (size_t i = 0; i < len; i++) printf("%02x ", buf[i]);
    printf("\n");
}

static int cmd_init(void) {
    unsigned char reset[] = {0x20, 0x00, 0x01, 0x00};
    if (nci_write(reset, sizeof(reset)) < 0) return -1;
    usleep(100000);

    unsigned char resp[256];
    size_t rlen;
    if (nci_read(resp, sizeof(resp), &rlen) < 0) return -1;
    printf("CORE_RESET_RSP (%zu bytes): ", rlen);
    print_hex(resp, rlen);

    unsigned char init[] = {0x20, 0x01, 0x00};
    if (nci_write(init, sizeof(init)) < 0) return -1;
    usleep(100000);

    if (nci_read(resp, sizeof(resp), &rlen) < 0) return -1;
    printf("CORE_INIT_RSP (%zu bytes): ", rlen);
    print_hex(resp, rlen);

    return 0;
}

static int cmd_capture(int duration_sec) {
    signal(SIGINT, sighandler);
    signal(SIGTERM, sighandler);

    unsigned char buf[1024];
    size_t len;
    time_t start = time(NULL);
    while (capturing && (duration_sec <= 0 || time(NULL) - start < duration_sec)) {
        if (nci_read(buf, sizeof(buf), &len) == 0 && len > 0) {
            printf("[%ld] ", (long)(time(NULL) - start));
            print_hex(buf, len);
            fflush(stdout);
        }
    }
    return 0;
}

static int cmd_send(const char *hex) {
    unsigned char buf[256];
    int len = hex_to_bytes(hex, buf, sizeof(buf));
    if (len < 0) {
        fprintf(stderr, "Invalid hex: %s\n", hex);
        return -1;
    }
    if (nci_write(buf, (size_t)len) < 0) return -1;
    printf("Sent %d bytes\n", len);

    unsigned char resp[256];
    size_t rlen;
    usleep(100000);
    if (nci_read(resp, sizeof(resp), &rlen) == 0 && rlen > 0) {
        printf("Response (%zu bytes): ", rlen);
        print_hex(resp, rlen);
    }
    return 0;
}

int main(int argc, char *argv[]) {
    if (argc < 2) {
        fprintf(stderr, "Usage: %s <init|capture <sec>|send <hex>|probe>\n", argv[0]);
        return 1;
    }

    if (strcmp(argv[1], "probe") == 0) {
        if (nci_open() < 0) return 1;
        printf("OK: %s opened\n", NQ_NCI_DEV);
        nci_close();
        return 0;
    }

    if (nci_open() < 0) return 1;

    int ret = 0;
    if (strcmp(argv[1], "init") == 0) {
        ret = cmd_init();
    } else if (strcmp(argv[1], "capture") == 0) {
        int dur = argc > 2 ? atoi(argv[2]) : 10;
        ret = cmd_capture(dur);
    } else if (strcmp(argv[1], "send") == 0) {
        if (argc < 3) {
            fprintf(stderr, "send requires hex argument\n");
            ret = 1;
        } else {
            ret = cmd_send(argv[2]);
        }
    } else {
        fprintf(stderr, "Unknown command: %s\n", argv[1]);
        ret = 1;
    }

    nci_close();
    return ret;
}
