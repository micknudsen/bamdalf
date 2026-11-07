#include <htslib/sam.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* Deliberately malformed BAM records cannot be round-tripped through SAM.
   Write the index alongside the raw record so index construction does not have
   to decode/reject the defect before the application can exercise it. */
int main(int argc, char **argv) {
    if (argc != 3) return 1;
    sam_hdr_t *header = sam_hdr_parse(0, "@HD\tVN:1.6\tSO:coordinate\n@SQ\tSN:tiny\tLN:20000\n");
    samFile *output = sam_open(argv[1], "wb");
    bam1_t *record = bam_init1();
    char *index = malloc(strlen(argv[1]) + 5);
    sprintf(index, "%s.bai", argv[1]);
    if (!header || !output || !record || sam_hdr_write(output, header) < 0 || sam_idx_init(output, header, 0, index) < 0) return 1;
    uint32_t cigar = bam_cigar_gen(10, BAM_CMATCH);
    if (bam_set1(record, 4, "good", 0, 0, 100, 60, 1, &cigar, -1, -1, 0, 10, "AAAAAAAAAA", NULL, 0) < 0 || sam_write1(output, header, record) < 0) return 1;
    if (bam_set1(record, 6, "defect", 0, 0, 17000, 60, 1, &cigar, -1, -1, 0, 10, "AAAAAAAAAA", NULL, 0) < 0) return 1;
    if (strcmp(argv[2], "missing") == 0) {
        /* Remove the CIGAR and sequence, preserving a mapped POS. */
        record->core.n_cigar = 0;
        record->core.l_qseq = 0;
        record->l_data = record->core.l_qname;
    } else if (strcmp(argv[2], "inconsistent") == 0) {
        bam_get_cigar(record)[0] = bam_cigar_gen(11, BAM_CMATCH);
    } else return 1;
    if (sam_write1(output, header, record) < 0 || sam_idx_save(output) < 0 || sam_close(output) < 0) return 1;
    bam_destroy1(record);
    sam_hdr_destroy(header);
    free(index);
    return 0;
}
