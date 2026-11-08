#include <htslib/sam.h>
#include <stdio.h>
#include <stdint.h>
int main(int argc, char **argv) {
    if (argc != 3) return 2;
    samFile *file = sam_open(argv[1], "rb");
    if (!file) return 3;
    sam_hdr_t *header = sam_hdr_read(file);
    hts_idx_t *index = sam_index_load(file, argv[1]);
    if (!header || !index) return 4;
    hts_itr_t *query = sam_itr_querys(index, header, argv[2]);
    bam1_t *record = bam_init1();
    if (!query || !record) return 5;
    int status;
    long decoded = 0, eligible = 0;
    while ((status = sam_itr_next(file, query, record)) >= 0) {
        decoded++;
        if (record->core.flag & (BAM_FUNMAP | BAM_FSECONDARY | BAM_FQCFAIL | BAM_FDUP)) continue;
        eligible++;
        uint8_t *tag = bam_aux_get(record, "RG");
        const char *rg = tag ? bam_aux2Z(tag) : NULL;
        printf("%s\t%s\t%lld\t%lld\t%u\n", rg ? rg : "<absent>", bam_get_qname(record), (long long)record->core.pos + 1, (long long)bam_endpos(record), record->core.flag);
    }
    fprintf(stderr, "decoded_records %ld\neligible_records %ld\n", decoded, eligible);
    bam_destroy1(record);
    hts_itr_destroy(query);
    hts_idx_destroy(index);
    sam_hdr_destroy(header);
    sam_close(file);
    return status == -1 ? 0 : 6;
}
