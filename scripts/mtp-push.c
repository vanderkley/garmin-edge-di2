// mtp-push <local file> <remote folder path> [remote name]
// Copies a file to a Garmin device over MTP (macOS has no built-in MTP support).
// Example: mtp-push bin/Di2.prg Garmin/Apps DI2.PRG
// Build:   clang -O2 -o mtp-push mtp-push.c $(pkg-config --cflags --libs libmtp)
#include <libmtp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>

static uint32_t find_child(LIBMTP_mtpdevice_t *dev, uint32_t storage, uint32_t parent,
                           const char *name, int folder_only) {
    uint32_t found = 0;
    LIBMTP_file_t *f = LIBMTP_Get_Files_And_Folders(dev, storage, parent);
    while (f) {
        if (!found && f->filename && strcasecmp(f->filename, name) == 0 &&
            (!folder_only || f->filetype == LIBMTP_FILETYPE_FOLDER)) {
            found = f->item_id;
        }
        LIBMTP_file_t *n = f->next;
        LIBMTP_destroy_file_t(f);
        f = n;
    }
    return found;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: mtp-push <local file> <remote folder> [remote name]\n");
        return 2;
    }
    const char *local = argv[1];
    const char *name = argc > 3 ? argv[3] : strrchr(local, '/') ? strrchr(local, '/') + 1 : local;
    struct stat st;
    if (stat(local, &st) != 0) { perror(local); return 1; }

    LIBMTP_Init();
    LIBMTP_raw_device_t *raw; int n = 0;
    if (LIBMTP_Detect_Raw_Devices(&raw, &n) != 0 || n < 1) {
        fprintf(stderr, "No MTP device found. Connect the Edge and close Garmin Express.\n");
        return 1;
    }
    LIBMTP_mtpdevice_t *dev = LIBMTP_Open_Raw_Device_Uncached(&raw[0]);
    if (!dev) { fprintf(stderr, "Cannot open device (is Garmin Express running?)\n"); return 1; }
    uint32_t storage = dev->storage->id;

    // walk the folder path
    uint32_t parent = LIBMTP_FILES_AND_FOLDERS_ROOT;
    char path[1024]; snprintf(path, sizeof path, "%s", argv[2]);
    for (char *part = strtok(path, "/"); part; part = strtok(NULL, "/")) {
        uint32_t id = find_child(dev, storage, parent, part, 1);
        if (!id) { fprintf(stderr, "Folder not found on device: %s\n", part); return 1; }
        parent = id;
    }

    // replace an existing file with the same name
    uint32_t old = find_child(dev, storage, parent, name, 0);
    if (old) { LIBMTP_Delete_Object(dev, old); }

    LIBMTP_file_t *nf = LIBMTP_new_file_t();
    nf->filename = strdup(name);
    nf->filesize = st.st_size;
    nf->filetype = LIBMTP_FILETYPE_UNKNOWN;
    nf->parent_id = parent;
    nf->storage_id = storage;
    int r = LIBMTP_Send_File_From_File(dev, local, nf, NULL, NULL);
    if (r != 0) { LIBMTP_Dump_Errorstack(dev); fprintf(stderr, "Upload failed\n"); }
    else printf("Copied %s -> %s/%s\n", local, argv[2], name);
    LIBMTP_Release_Device(dev);
    free(raw);
    return r != 0;
}
