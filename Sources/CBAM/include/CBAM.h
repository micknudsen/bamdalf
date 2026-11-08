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
typedef struct bamdalf_query bamdalf_query;
bamdalf_query *bamdalf_query_open(bamdalf_bam *bam, const char *reference, int64_t start, int64_t end);
void bamdalf_query_close(bamdalf_query *query);
int bamdalf_query_next(bamdalf_query *query);
uint64_t bamdalf_record_id(const bamdalf_query *query);
const char *bamdalf_record_name(const bamdalf_query *query);
int bamdalf_record_read_group(const bamdalf_query *query, const char **read_group);
uint16_t bamdalf_record_flags(const bamdalf_query *query);
int64_t bamdalf_record_start(const bamdalf_query *query);
uint32_t bamdalf_record_cigar_count(const bamdalf_query *query);
uint32_t bamdalf_record_cigar(const bamdalf_query *query, uint32_t operation);
int32_t bamdalf_record_sequence_length(const bamdalf_query *query);
char bamdalf_record_base(const bamdalf_query *query, int32_t base);
#endif
