/* Independent HTSlib decoding, preparation audit, depths, and indexed counts. */
#include <CommonCrypto/CommonDigest.h>
#include <htslib/sam.h>
#include <htslib/khash.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

KHASH_MAP_INIT_STR(groups, uint64_t)
#define COUNT 9
#define EXCLUDED (BAM_FUNMAP | BAM_FSECONDARY | BAM_FQCFAIL | BAM_FDUP)
static const hts_pos_t starts[COUNT] = {9830400, 19988480, 29818880, 10024500, 10020000, 20049500, 20045000, 29892100, 29887600};
static const hts_pos_t ends[COUNT] = {10354688, 20119552, 30081024, 10025500, 10030000, 20050500, 20055000, 29893100, 29897600};

static void big_endian(uint8_t *output, uint64_t value) {
    for (int i = 7; i >= 0; i--) { output[i] = value & 255; value >>= 8; }
}

static int retain(const bam1_t *record, uint64_t source_offset) {
    const char *name = bam_get_qname(record);
    uint8_t *tag = bam_aux_get(record, "RG");
    if (tag && *tag != 'Z') return -1;
    const char *rg = tag ? bam_aux2Z(tag) : NULL;
    size_t name_length = strlen(name), rg_length = rg ? strlen(rg) : 0;
    size_t capacity = 8 + 1 + 8 + rg_length + 8 + name_length;
    uint8_t *bytes = malloc(capacity), *cursor = bytes;
    if (!bytes) return -1;
    big_endian(cursor, 20261108); cursor += 8;
    if (strcmp(name, "*") == 0) {
        *cursor++ = 0; big_endian(cursor, source_offset); cursor += 8;
    } else {
        *cursor++ = rg ? 2 : 1;
        if (rg) { big_endian(cursor, rg_length); cursor += 8; memcpy(cursor, rg, rg_length); cursor += rg_length; }
        big_endian(cursor, name_length); cursor += 8; memcpy(cursor, name, name_length); cursor += name_length;
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes, (CC_LONG)(cursor - bytes), digest);
    free(bytes);
    uint64_t value = 0;
    for (int i = 0; i < 8; i++) value = (value << 8) | digest[i];
    return value < UINT64_C(6148914691236517205);
}

static char *group_key(const bam1_t *record, uint64_t ordinal) {
    const char *name = bam_get_qname(record);
    uint8_t *tag = bam_aux_get(record, "RG");
    const char *rg = tag ? bam_aux2Z(tag) : NULL;
    char *key = NULL;
    if (strcmp(name, "*") == 0) asprintf(&key, "U%llu", (unsigned long long)ordinal);
    else if (rg) asprintf(&key, "R%zu:%s%zu:%s", strlen(rg), rg, strlen(name), name);
    else asprintf(&key, "A%zu:%s", strlen(name), name);
    return key;
}

static int same_record(const bam1_t *a, const bam1_t *b) {
    return a->core.tid == b->core.tid && a->core.pos == b->core.pos && a->core.qual == b->core.qual &&
        a->core.flag == b->core.flag && a->core.n_cigar == b->core.n_cigar && a->core.l_qseq == b->core.l_qseq &&
        a->core.mtid == b->core.mtid && a->core.mpos == b->core.mpos && a->core.isize == b->core.isize &&
        a->l_data == b->l_data && memcmp(a->data, b->data, a->l_data) == 0;
}

static int audit(const char *source, const char *derived, const char *offset_path) {
    samFile *first = sam_open(source, "rb"), *second = sam_open(derived, "rb");
    FILE *offsets = fopen(offset_path, "r");
    if (!first || !second || !offsets) return 2;
    sam_hdr_t *h1 = sam_hdr_read(first), *h2 = sam_hdr_read(second);
    bam1_t *a = bam_init1(), *b = bam_init1();
    if (!h1 || !h2 || !a || !b || sam_hdr_nref(h1) != sam_hdr_nref(h2)) return 3;
    for (int i = 0; i < sam_hdr_nref(h1); i++) {
        if (strcmp(sam_hdr_tid2name(h1, i), sam_hdr_tid2name(h2, i)) || sam_hdr_tid2len(h1, i) != sam_hdr_tid2len(h2, i)) return 3;
    }
    int status; uint64_t total = 0, selected = 0;
    while ((status = sam_read1(first, h1, a)) >= 0) {
        unsigned long long source_offset;
        if (fscanf(offsets, "%llu", &source_offset) != 1) return 4;
        int keep = retain(a, (uint64_t)source_offset);
        if (keep < 0) return 5;
        total++;
        if (keep) {
            if (sam_read1(second, h2, b) < 0 || !same_record(a, b)) return 6;
            selected++;
        }
    }
    unsigned long long unexpected;
    if (status != -1 || sam_read1(second, h2, b) != -1 || fscanf(offsets, "%llu", &unexpected) != EOF) return 7;
    printf("preparation_audit_source_records %llu\npreparation_audit_selected_records %llu\npreparation_audit_exact_record_match true\n",
           (unsigned long long)total, (unsigned long long)selected);
    fclose(offsets); bam_destroy1(a); bam_destroy1(b); sam_hdr_destroy(h1); sam_hdr_destroy(h2); sam_close(first); sam_close(second);
    return 0;
}

static int profile(const char *path) {
    samFile *file = sam_open(path, "rb");
    if (!file) return 2;
    sam_hdr_t *header = sam_hdr_read(file);
    bam1_t *record = bam_init1();
    if (!header || !record) return 3;
    int tid = sam_hdr_name2tid(header, "chr20"), status;
    uint64_t total = 0, eligible = 0, paired = 0, length148 = 0, supplementary = 0, region_counts[COUNT] = {0};
    hts_pos_t previous = -1;
    int *depth[COUNT]; khash_t(groups) *groups[COUNT];
    khash_t(groups) *all_groups = kh_init(groups);
    for (int i = 0; i < COUNT; i++) { depth[i] = calloc(ends[i] - starts[i], sizeof(int)); groups[i] = kh_init(groups); if (!depth[i] || !groups[i]) return 3; }
    while ((status = sam_read1(file, header, record)) >= 0) {
        if (record->core.tid != tid || record->core.pos < previous) return 4;
        previous = record->core.pos;
        total++; paired += !!(record->core.flag & BAM_FPAIRED); length148 += record->core.l_qseq == 148;
        if (record->core.flag & EXCLUDED) continue;
        eligible++; supplementary += !!(record->core.flag & BAM_FSUPPLEMENTARY);
        char *key = group_key(record, total); int inserted;
        khiter_t position = kh_put(groups, all_groups, key, &inserted);
        if (inserted < 0) return 3;
        if (inserted) kh_value(all_groups, position) = 1;
        else { kh_value(all_groups, position)++; free(key); key = (char *)kh_key(all_groups, position); }
        for (int i = 0; i < COUNT; i++) {
            if (record->core.pos < ends[i] && bam_endpos(record) > starts[i]) {
                region_counts[i]++;
                position = kh_put(groups, groups[i], key, &inserted);
                if (inserted < 0) return 3;
                if (inserted) kh_value(groups[i], position) = 1;
                else kh_value(groups[i], position)++;
            }
        }
        hts_pos_t reference = record->core.pos;
        uint32_t *cigar = bam_get_cigar(record);
        for (uint32_t j = 0; j < record->core.n_cigar; j++) {
            int operation = bam_cigar_op(cigar[j]), length = bam_cigar_oplen(cigar[j]);
            if (operation == BAM_CMATCH || operation == BAM_CEQUAL || operation == BAM_CDIFF) {
                for (int i = 0; i < COUNT; i++) {
                    hts_pos_t low = reference > starts[i] ? reference : starts[i];
                    hts_pos_t high = reference + length < ends[i] ? reference + length : ends[i];
                    for (hts_pos_t base = low; base < high; base++) depth[i][base - starts[i]]++;
                }
            }
            if (bam_cigar_type(operation) & 2) reference += length;
        }
    }
    if (status != -1) return 5;
    uint64_t max_group = 0;
    for (khiter_t k = kh_begin(all_groups); k != kh_end(all_groups); k++) if (kh_exist(all_groups, k) && kh_value(all_groups, k) > max_group) max_group = kh_value(all_groups, k);
    printf("HTSlib %s\nreferences %d\ntotal_records %llu\neligible_records %llu\npaired_records %llu\nstored_length148_records %llu\nsupplementary_eligible %llu\neligible_groups %u\nmax_eligible_group_records %llu\n",
           hts_version(), sam_hdr_nref(header), (unsigned long long)total, (unsigned long long)eligible, (unsigned long long)paired,
           (unsigned long long)length148, (unsigned long long)supplementary, kh_size(all_groups), (unsigned long long)max_group);
    for (int i = 0; i < COUNT; i++) {
        uint64_t sum = 0, max_records = 0; int minimum = INT32_MAX, maximum = 0;
        for (hts_pos_t base = 0; base < ends[i] - starts[i]; base++) { int value = depth[i][base]; sum += value; if (value < minimum) minimum = value; if (value > maximum) maximum = value; }
        for (khiter_t k = kh_begin(groups[i]); k != kh_end(groups[i]); k++) if (kh_exist(groups[i], k) && kh_value(groups[i], k) > max_records) max_records = kh_value(groups[i], k);
        printf("region chr20:%lld-%lld eligible_records %llu groups %u max_group_records %llu mean_aligned_base_depth %.6f min %d max %d\n",
               (long long)starts[i] + 1, (long long)ends[i], (unsigned long long)region_counts[i], kh_size(groups[i]),
               (unsigned long long)max_records, (double)sum / (ends[i] - starts[i]), minimum, maximum);
        free(depth[i]); kh_destroy(groups, groups[i]);
    }
    for (khiter_t k = kh_begin(all_groups); k != kh_end(all_groups); k++) if (kh_exist(all_groups, k)) free((char *)kh_key(all_groups, k));
    kh_destroy(groups, all_groups); bam_destroy1(record); sam_hdr_destroy(header); sam_close(file);
    if (sam_index_build(path, 0) != 0) return 6;
    file = sam_open(path, "rb");
    if (!file) return 7;
    header = sam_hdr_read(file); record = bam_init1();
    hts_idx_t *index = sam_index_load(file, path);
    if (!file || !header || !record || !index) return 7;
    for (int i = 0; i < COUNT; i++) {
        hts_itr_t *iterator = sam_itr_queryi(index, tid, starts[i], ends[i]);
        if (!iterator) return 8;
        uint64_t count = 0;
        while ((status = sam_itr_next(file, iterator, record)) >= 0) if (!(record->core.flag & EXCLUDED)) count++;
        hts_itr_destroy(iterator);
        if (status != -1 || count != region_counts[i]) return 8;
        printf("indexed_sequential_count_match region%d %llu\n", i, (unsigned long long)count);
    }
    hts_idx_destroy(index); bam_destroy1(record); sam_hdr_destroy(header); sam_close(file);
    return 0;
}

int main(int argc, char **argv) {
    if (argc == 2) return profile(argv[1]);
    if (argc == 4) return audit(argv[1], argv[2], argv[3]);
    fprintf(stderr, "usage: qualification-profile BAM | SOURCE_BAM DERIVED_BAM SOURCE_OFFSETS\n");
    return 1;
}
