/* Independently read, profile, index, and query the derived BAM using HTSlib. */
#include <htslib/sam.h>
#include <stdio.h>
#include <stdlib.h>

#define REGION_COUNT 2
#define EXCLUDED_FLAGS (BAM_FUNMAP | BAM_FSECONDARY | BAM_FQCFAIL | BAM_FDUP)
static const int region_start[REGION_COUNT] = {9994240, 29884416};
static const int region_end[REGION_COUNT] = {10059776, 29900800};

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: profile REGIONAL_BAM\n");
        return 2;
    }
    samFile *file = sam_open(argv[1], "rb");
    if (!file) return 3;
    sam_hdr_t *header = sam_hdr_read(file);
    bam1_t *record = bam_init1();
    if (!header || !record) return 4;
    int reference_id = sam_hdr_name2tid(header, "chr20");
    int status;
    hts_pos_t previous_position = -1;
    long total = 0, eligible = 0, paired = 0, supplementary = 0;
    long mapq_zero = 0, soft_clipped = 0;
    long operations[10] = {0}, lengths[10000] = {0};
    long region_counts[REGION_COUNT] = {0};
    int *depth[REGION_COUNT];
    for (int region = 0; region < REGION_COUNT; region++) {
        depth[region] = calloc(region_end[region] - region_start[region], sizeof(int));
        if (!depth[region]) return 4;
    }

    while ((status = sam_read1(file, header, record)) >= 0) {
        if (record->core.tid != reference_id || record->core.pos < previous_position) {
            fprintf(stderr, "sort/reference invalid\n");
            return 5;
        }
        previous_position = record->core.pos;
        total++;
        if (record->core.l_qseq < 10000) lengths[record->core.l_qseq]++;
        if (record->core.flag & BAM_FPAIRED) paired++;
        if (record->core.flag & EXCLUDED_FLAGS) continue;
        eligible++;
        if (record->core.flag & BAM_FSUPPLEMENTARY) supplementary++;
        if (record->core.qual == 0) mapq_zero++;
        for (int region = 0; region < REGION_COUNT; region++) {
            if (record->core.pos < region_end[region] && bam_endpos(record) > region_start[region]) {
                region_counts[region]++;
            }
        }
        hts_pos_t position = record->core.pos;
        int has_soft_clip = 0;
        uint32_t *cigar = bam_get_cigar(record);
        for (uint32_t index = 0; index < record->core.n_cigar; index++) {
            int operation = bam_cigar_op(cigar[index]);
            int length = bam_cigar_oplen(cigar[index]);
            if (operation >= 10) return 6;
            operations[operation]++;
            if (operation == BAM_CSOFT_CLIP) has_soft_clip = 1;
            if (operation == BAM_CMATCH || operation == BAM_CEQUAL || operation == BAM_CDIFF) {
                for (int region = 0; region < REGION_COUNT; region++) {
                    hts_pos_t start = position > region_start[region] ? position : region_start[region];
                    hts_pos_t end = position + length < region_end[region] ? position + length : region_end[region];
                    for (hts_pos_t base = start; base < end; base++) depth[region][base - region_start[region]]++;
                }
            }
            if (bam_cigar_type(operation) & 2) position += length;
        }
        soft_clipped += has_soft_clip;
    }
    if (status != -1) {
        fprintf(stderr, "read failure %d\n", status);
        return 6;
    }
    printf("HTSlib %s\nreferences %d\ntotal_records %ld\neligible_records %ld\npaired_records %ld\n"
           "supplementary_eligible %ld\nmapq0_eligible %ld\nsoftclipped_eligible %ld\n",
           hts_version(), sam_hdr_nref(header), total, eligible, paired, supplementary, mapq_zero, soft_clipped);
    for (int length = 0; length < 10000; length++) {
        if (lengths[length]) printf("stored_length %d %ld\n", length, lengths[length]);
    }
    for (int operation = 0; operation < 9; operation++) {
        if (operations[operation]) printf("cigar_operation %c %ld\n", BAM_CIGAR_STR[operation], operations[operation]);
    }
    for (int region = 0; region < REGION_COUNT; region++) {
        long sum = 0;
        int minimum = 10000000, maximum = 0;
        int width = region_end[region] - region_start[region];
        for (int base = 0; base < width; base++) {
            int value = depth[region][base];
            sum += value;
            if (value < minimum) minimum = value;
            if (value > maximum) maximum = value;
        }
        printf("region chr20:%d-%d eligible_records %ld mean_aligned_base_depth %.6f min %d max %d\n",
               region_start[region] + 1, region_end[region], region_counts[region],
               (double)sum / width, minimum, maximum);
        free(depth[region]);
    }
    bam_destroy1(record);
    sam_hdr_destroy(header);
    sam_close(file);

    if (sam_index_build(argv[1], 0) != 0) return 7;
    file = sam_open(argv[1], "rb");
    if (!file) return 8;
    header = sam_hdr_read(file);
    record = bam_init1();
    hts_idx_t *index = sam_index_load(file, argv[1]);
    if (!header || !record || !index) return 8;
    for (int region = 0; region < REGION_COUNT; region++) {
        hts_itr_t *iterator = sam_itr_queryi(index, reference_id, region_start[region], region_end[region]);
        if (!iterator) return 9;
        long count = 0;
        while ((status = sam_itr_next(file, iterator, record)) >= 0) {
            if (!(record->core.flag & EXCLUDED_FLAGS)) count++;
        }
        hts_itr_destroy(iterator);
        if (status != -1 || count != region_counts[region]) return 9;
        printf("indexed_sequential_count_match region%d %ld\n", region, count);
    }
    hts_idx_destroy(index);
    bam_destroy1(record);
    sam_hdr_destroy(header);
    sam_close(file);
    return 0;
}
