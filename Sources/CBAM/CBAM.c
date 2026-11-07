#include "CBAM.h"
#include <htslib/sam.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

struct bamdalf_bam {
    samFile *file;
    sam_hdr_t *header;
    hts_idx_t *index;
};

static void describe_error(char *output, size_t capacity, const char *operation, int cause) {
    if (cause) snprintf(output, capacity, "%s: %s", operation, strerror(cause));
    else snprintf(output, capacity, "%s. HTSlib did not report a more specific cause.", operation);
}

void bamdalf_bam_close(bamdalf_bam *bam) {
    if (!bam) return;
    hts_idx_destroy(bam->index);
    sam_hdr_destroy(bam->header);
    if (bam->file) sam_close(bam->file);
    free(bam);
}

bamdalf_bam *bamdalf_bam_open(const char *bam_path, const char *index_path,
                             char *error, size_t capacity, int *index_failed) {
    *index_failed = 0;
    bamdalf_bam *result = calloc(1, sizeof(*result));
    if (!result) {
        describe_error(error, capacity, "Could not allocate BAM reader", ENOMEM);
        return NULL;
    }
    errno = 0;
    result->file = sam_open(bam_path, "rb");
    if (!result->file) {
        describe_error(error, capacity, "Could not open BAM", errno);
        goto failed;
    }
    if (hts_get_format(result->file)->format != bam) {
        snprintf(error, capacity, "The selected file is not in BAM format.");
        goto failed;
    }
    errno = 0;
    result->header = sam_hdr_read(result->file);
    if (!result->header) {
        describe_error(error, capacity, "Could not read BAM header", errno);
        goto failed;
    }
    *index_failed = 1;
    errno = 0;
    /* Explicit fnidx avoids HTSlib's automatic filename search and fallback. */
    result->index = sam_index_load3(result->file, bam_path, index_path, 0);
    if (!result->index) {
        describe_error(error, capacity, "Could not load the selected BAM index", errno);
        goto failed;
    }
    return result;

failed:
    bamdalf_bam_close(result);
    return NULL;
}

int bamdalf_reference_count(const bamdalf_bam *bam) { return sam_hdr_nref(bam->header); }
const char *bamdalf_reference_name(const bamdalf_bam *bam, int reference) {
    return sam_hdr_tid2name(bam->header, reference);
}
int64_t bamdalf_reference_length(const bamdalf_bam *bam, int reference) {
    return sam_hdr_tid2len(bam->header, reference);
}
