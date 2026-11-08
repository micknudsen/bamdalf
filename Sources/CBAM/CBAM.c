#include "CBAM.h"
#include <htslib/sam.h>
#include <htslib/bgzf.h>
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
    if (hts_idx_nseq(result->index) != sam_hdr_nref(result->header)) {
        snprintf(error, capacity, "The selected BAM index has a different reference count than the BAM header.");
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

struct bamdalf_query {
    bamdalf_bam *bam;
    hts_itr_t *iterator;
    bam1_t *record;
};

bamdalf_query *bamdalf_query_open(bamdalf_bam *bam, const char *reference, int64_t start, int64_t end) {
    bamdalf_query *query = calloc(1, sizeof(*query));
    if (!query) return NULL;
    query->bam = bam;
    query->iterator = sam_itr_queryi(bam->index, sam_hdr_name2tid(bam->header, reference), start, end);
    query->record = bam_init1();
    if (!query->iterator || !query->record) {
        bamdalf_query_close(query);
        return NULL;
    }
    return query;
}

void bamdalf_query_close(bamdalf_query *query) {
    if (!query) return;
    hts_itr_destroy(query->iterator);
    bam_destroy1(query->record);
    free(query);
}

int bamdalf_query_next(bamdalf_query *query) {
    return sam_itr_next(query->bam->file, query->iterator, query->record);
}
uint64_t bamdalf_record_id(const bamdalf_query *query) { return bgzf_tell(query->bam->file->fp.bgzf); }
const char *bamdalf_record_name(const bamdalf_query *query) { return bam_get_qname(query->record); }
int bamdalf_record_read_group(const bamdalf_query *query, const char **read_group) {
    uint8_t *tag = bam_aux_get(query->record, "RG");
    *read_group = NULL;
    if (!tag) return 0;
    if (*tag != 'Z') return -1;
    *read_group = bam_aux2Z(tag);
    return *read_group ? 0 : -1;
}
uint16_t bamdalf_record_flags(const bamdalf_query *query) { return query->record->core.flag; }
int64_t bamdalf_record_start(const bamdalf_query *query) { return query->record->core.pos; }
uint32_t bamdalf_record_cigar_count(const bamdalf_query *query) { return query->record->core.n_cigar; }
uint32_t bamdalf_record_cigar(const bamdalf_query *query, uint32_t operation) { return bam_get_cigar(query->record)[operation]; }
int32_t bamdalf_record_sequence_length(const bamdalf_query *query) { return query->record->core.l_qseq; }
char bamdalf_record_base(const bamdalf_query *query, int32_t base) { return seq_nt16_str[bam_seqi(bam_get_seq(query->record), base)]; }
