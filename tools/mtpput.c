// Copies a file to a Garmin watch over MTP (macOS Finder cannot see MTP devices).
// Build: clang -O1 -o bin/mtpput tools/mtpput.c $(pkg-config --cflags --libs libmtp)
// Usage: mtpput <local file> <folder path, e.g. GARMIN/Apps> <remote name>
#include <libmtp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <strings.h>

// Walks a slash-separated path (case-insensitive) through the folder tree.
static uint32_t find_folder(LIBMTP_folder_t *root, const char *path) {
    char buf[512]; strncpy(buf, path, sizeof buf - 1); buf[sizeof buf - 1] = 0;
    LIBMTP_folder_t *level = root; uint32_t id = 0;
    for (char *part = strtok(buf, "/"); part; part = strtok(NULL, "/")) {
        LIBMTP_folder_t *f = level;
        while (f && strcasecmp(f->name, part) != 0) f = f->sibling;
        if (!f) return 0;
        id = f->folder_id; level = f->child;
    }
    return id;
}
int main(int argc, char **argv) {
    if (argc != 4) { fprintf(stderr, "usage: mtpput <local> <folder path> <name>\n"); return 2; }
    struct stat st; if (stat(argv[1], &st) != 0) { perror("stat"); return 2; }
    LIBMTP_Init();
    LIBMTP_mtpdevice_t *dev = LIBMTP_Get_First_Device();
    if (!dev) { fprintf(stderr, "no device\n"); return 1; }
    LIBMTP_Get_Storage(dev, LIBMTP_STORAGE_SORTBY_NOTSORTED);
    LIBMTP_folder_t *folders = LIBMTP_Get_Folder_List(dev);
    uint32_t parent = find_folder(folders, argv[2]);
    LIBMTP_destroy_folder_t(folders);
    if (!parent) { fprintf(stderr, "folder %s not found on device\n", argv[2]); LIBMTP_Release_Device(dev); return 1; }
    // remove an existing file with the same name in that folder
    LIBMTP_file_t *files = LIBMTP_Get_Filelisting_With_Callback(dev, NULL, NULL);
    for (LIBMTP_file_t *f = files; f; ) {
        LIBMTP_file_t *n = f->next;
        if (f->parent_id == parent && f->filename && strcasecmp(f->filename, argv[3]) == 0) {
            if (LIBMTP_Delete_Object(dev, f->item_id) == 0) {
                printf("removed old %s (id %u)\n", f->filename, f->item_id);
            } else {
                fprintf(stderr, "WARNING: could not remove old %s (id %u)\n", f->filename, f->item_id);
                LIBMTP_Dump_Errorstack(dev); LIBMTP_Clear_Errorstack(dev);
            }
        }
        LIBMTP_destroy_file_t(f); f = n;
    }
    LIBMTP_file_t *nf = LIBMTP_new_file_t();
    nf->filename = strdup(argv[3]);
    nf->filesize = st.st_size;
    nf->filetype = LIBMTP_FILETYPE_UNKNOWN;
    nf->parent_id = parent;
    nf->storage_id = dev->storage->id;
    int r = LIBMTP_Send_File_From_File(dev, argv[1], nf, NULL, NULL);
    if (r != 0) { LIBMTP_Dump_Errorstack(dev); LIBMTP_Clear_Errorstack(dev); fprintf(stderr, "FAILED\n"); }
    else printf("OK: %s -> folder %u as %s (id %u, storage 0x%08x)\n", argv[1], parent, argv[3], nf->item_id, nf->storage_id);
    LIBMTP_destroy_file_t(nf);
    LIBMTP_Release_Device(dev);
    return r == 0 ? 0 : 1;
}
