#ifndef BAMDALF_CBAM_H
#define BAMDALF_CBAM_H
#include <stdint.h>
#include <stddef.h>

typedef struct bamdalf_bam bamdalf_bam;
bamdalf_bam *bamdalf_bam_open(const char *bam_path, const char *index_path,
                             char *error, size_t error_capacity, int *index_failed);
void bamdalf_bam_close(bamdalf_bam *bam);
int bamdalf_reference_count(const bamdalf_bam *bam);
const char *bamdalf_reference_name(const bamdalf_bam *bam, int reference);
int64_t bamdalf_reference_length(const bamdalf_bam *bam, int reference);
#endif
