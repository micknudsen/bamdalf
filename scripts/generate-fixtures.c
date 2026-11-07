#include <htslib/sam.h>
#include <stdio.h>

/* Rebuild the checked-in fixture from its independently readable SAM source. */
int main(int argc, char **argv) {
    if (argc != 3) return 1;
    samFile *input = sam_open(argv[1], "r");
    samFile *output = sam_open(argv[2], "wb");
    if (!input || !output) return 1;
    sam_hdr_t *header = sam_hdr_read(input);
    bam1_t *record = bam_init1();
    if (!header || !record || sam_hdr_write(output, header) < 0) return 1;
    int result;
    while ((result = sam_read1(input, header, record)) >= 0) {
        if (sam_write1(output, header, record) < 0) return 1;
    }
    bam_destroy1(record);
    sam_hdr_destroy(header);
    if (result < -1 || sam_close(input) < 0 || sam_close(output) < 0) return 1;
    if (sam_index_build3(argv[2], NULL, 0, 0) < 0) return 1;
    if (sam_index_build3(argv[2], NULL, 14, 0) < 0) return 1;
    return 0;
}
