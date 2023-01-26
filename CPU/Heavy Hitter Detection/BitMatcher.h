#ifndef _BitMatcher_H
#define _BitMatcher_H

#include <iostream>
#include <stdio.h>
#include <algorithm>
#include <cstring>
#include <string.h>
#include <stdlib.h>
#include "BOBHash.h"
#include <stdint.h>
#define NDEBUG
#include <cassert>
#include <unordered_map>

#define ENABLE_CM_SKETCH 0
/* the bucket type macro */
#define FINGERPRINT_LENGTH 8
#define TYPE_ID_LENGTH 4

typedef struct {
	uint8_t type_id:4;
	uint8_t skip:4;
	uint8_t skip2[2];
	uint8_t fingerprint5;
	uint8_t fingerprint4;
	uint8_t fingerprint3;
	uint8_t fingerprint2;
	uint8_t fingerprint1;
} ec_bucket_type_origin;
#define define_type_5_fingerprint(type_index, c1, c2, c3, c4, c5)  typedef struct { \
		uint64_t type_id: TYPE_ID_LENGTH; \
		uint64_t count1: c1; \
		uint64_t count2: c2; \
		uint64_t count3: c3; \
		uint64_t count4: c4; \
		uint64_t count5: c5; \
		uint64_t fingerprint1: FINGERPRINT_LENGTH; \
		uint64_t fingerprint2: FINGERPRINT_LENGTH; \
		uint64_t fingerprint3: FINGERPRINT_LENGTH; \
		uint64_t fingerprint4: FINGERPRINT_LENGTH; \
		uint64_t fingerprint5: FINGERPRINT_LENGTH; \
	} ec_bucket_type##type_index;

#define define_type_4_fingerprint(type_index, c1, c2, c3, c4)  typedef struct { \
		uint64_t type_id: TYPE_ID_LENGTH; \
		uint64_t count1: c1; \
		uint64_t count2: c2; \
		uint64_t count3: c3; \
		uint64_t count4: c4; \
		uint64_t fingerprint1: FINGERPRINT_LENGTH; \
		uint64_t fingerprint2: FINGERPRINT_LENGTH; \
		uint64_t fingerprint3: FINGERPRINT_LENGTH; \
		uint64_t fingerprint4: FINGERPRINT_LENGTH; \
	} ec_bucket_type##type_index;

#define define_type_3_fingerprint(type_index, c1, c2, c3)  typedef struct { \
		uint64_t type_id: TYPE_ID_LENGTH; \
		uint64_t count1: c1; \
		uint64_t count2: c2; \
		uint64_t count3: c3; \
		uint64_t fingerprint1: FINGERPRINT_LENGTH; \
		uint64_t fingerprint2: FINGERPRINT_LENGTH; \
		uint64_t fingerprint3: FINGERPRINT_LENGTH; \
	} ec_bucket_type##type_index;

/* Each type struct */
// Store the bucket item size, each BUCKET_ITEM_SIZE[i] is a type of bucket
// BUCKET_ITEM_SIZE[0]:
//       0: bucket_type_index, i.e. the type_id of the bucket
//       5: bucket_fingerprint_size, i.e. how many fingerprints are in the bucket
//       2, 3, 4, 5, 6: the each item bit size
#define BUCKET_TYPE_NUM 12
#define FINGERPRINT_MAX_NUM 5
#define CONFIG_LENGTH (2+FINGERPRINT_MAX_NUM)
const uint8_t BUCKET_ITEM_SIZE[BUCKET_TYPE_NUM][CONFIG_LENGTH] = {
	{0, 5, 2, 3, 4, 5, 6},
	{1, 4, 3, 4, 5, 16, 0},
	{2, 4, 4, 5, 6, 13, 0},
	{3, 4, 5, 6, 7, 10, 0},
	{4, 3, 4, 5, 27, 0, 0},
	{5, 3, 5, 6, 25, 0, 0},
	{6, 3, 6, 7, 23, 0, 0},
	{7, 3, 7, 8, 21, 0, 0},
	{8, 3, 8, 9, 19, 0, 0},
	{9, 3, 9, 10, 17, 0, 0},
	{10, 3, 10, 11, 15, 0, 0},
	{11, 3, 11, 12, 13, 0, 0}
};

define_type_5_fingerprint(0, 2, 3, 4, 5, 6);
typedef union {
	uint64_t value;
	ec_bucket_type0 type_0;
	ec_bucket_type_origin type0;
} ec_bucket;

/* The item localation and  */
// const uint64_t TYPE_ID_LOC = 0; 
// const uint64_t TYPE_ID_BITMASK = (1UL << TYPE_ID_LENGTH) - 1;
#define TYPE_ID_LOC (0)
#define TYPE_ID_BITMASK ((1UL << TYPE_ID_LENGTH) - 1)
// fingerprint_loc: the start bit index of the fingerprint, [x, x+FINGERPRINT_LENGTH]
// fingerprint_loc_mask: the mask for the fingerprint
uint8_t FINGERPRINT_LOC[FINGERPRINT_MAX_NUM];
// uint64_t FINGERPRINT_BITMASK = (1UL << FINGERPRINT_LENGTH) - 1; // The mask is 0xFF (8 bits)
#define FINGERPRINT_BITMASK ((1UL << FINGERPRINT_LENGTH) - 1)

uint8_t COUNT_LEN[BUCKET_TYPE_NUM][FINGERPRINT_MAX_NUM];
uint8_t _align1[4];
uint8_t COUNT_LOC[BUCKET_TYPE_NUM][FINGERPRINT_MAX_NUM];
uint8_t _align2[4];

#define get_bucket_type(bucket) (bucket.type0.type_id)
#define set_bucket_type(bucket, type) ((bucket).type0.type_id = (type))

static inline void init_bucket_parameters() {
	// Check the config is correct!
	assert(sizeof(ec_bucket) == 8);
	for (int i = 0; i < BUCKET_TYPE_NUM; i++) {
		const int fingerprint_num = BUCKET_ITEM_SIZE[i][1];
		int total_bit = 0;
		total_bit += TYPE_ID_LENGTH;
		total_bit += FINGERPRINT_LENGTH * fingerprint_num;
		for (int j = 2; j < 2+fingerprint_num; j++) {
			total_bit += BUCKET_ITEM_SIZE[i][j];
		}
		assert(total_bit == 8 * sizeof(ec_bucket));
		for (int j = 2+fingerprint_num; j < CONFIG_LENGTH; j++) {
			assert(BUCKET_ITEM_SIZE[i][j] == 0);
		}
	}

	for(int i = 0; i < FINGERPRINT_MAX_NUM; i++) {
		FINGERPRINT_LOC[i] = i * FINGERPRINT_LENGTH + TYPE_ID_LENGTH;
		// FINGERPRINT_LOC[i] = 64 - (i+1) * FINGERPRINT_LENGTH; // 0-4, from the highest to smallest
	}

	for(int i = 0; i < BUCKET_TYPE_NUM; i++) {
		const int fingerprint_num = BUCKET_ITEM_SIZE[i][1];
		for (int j = 2; j < 2 + fingerprint_num; j++) {
			const int count_idx = j - 2;
			COUNT_LEN[i][count_idx] = BUCKET_ITEM_SIZE[i][j];
			if ( count_idx == 0 ) {
				COUNT_LOC[i][count_idx] = TYPE_ID_LENGTH + FINGERPRINT_LENGTH * fingerprint_num;
			} else {
				COUNT_LOC[i][count_idx] = COUNT_LOC[i][count_idx-1] + COUNT_LEN[i][count_idx-1];
			}
		}
	}
}

static inline __attribute__((always_inline)) uint32_t get_bucket_type_id(ec_bucket* bkt) {
	return (bkt->value & (TYPE_ID_BITMASK));
}

static inline __attribute__((always_inline)) void set_bucket_type_id(ec_bucket* bkt, uint64_t type_id) {
	bkt->value = (bkt->value & ~(TYPE_ID_BITMASK)) | (type_id & TYPE_ID_BITMASK);
}

static inline __attribute__((always_inline)) uint8_t get_item_num_in_bucket_type(uint32_t type_id) {
	// return BUCKET_ITEM_SIZE[type_id][1];
	switch(type_id) {
		case 0: return 5;
		case 1 ... 3: return 4;
		case 4 ... 11: return 3;
		default: assert(0);
	}
}

static inline __attribute__((always_inline)) uint8_t get_bucket_fingerprint(ec_bucket* bkt, int fingerprint_index) {
	return ((bkt->value >> FINGERPRINT_LOC[fingerprint_index]) & FINGERPRINT_BITMASK);
	// switch (fingerprint_index) {
	// 	case 0: return (bkt->type0.fingerprint1);
	// 	case 1: return (bkt->type0.fingerprint2);
	// 	case 2: return (bkt->type0.fingerprint3);
	// 	case 3: return (bkt->type0.fingerprint4);
	// 	case 4: return (bkt->type0.fingerprint5);
	// 	default: assert(0);
	// }
}

static inline __attribute__((always_inline)) void set_bucket_fingerprint(ec_bucket* bkt, int fingerprint_index, uint64_t fingerprint) {
	bkt->value = (bkt->value & ~(FINGERPRINT_BITMASK << FINGERPRINT_LOC[fingerprint_index])) | ((fingerprint & FINGERPRINT_BITMASK) << FINGERPRINT_LOC[fingerprint_index]);
	// switch (fingerprint_index) {
	// 	case 0: bkt->type0.fingerprint1 = (fingerprint & FINGERPRINT_BITMASK); break;
	// 	case 1: bkt->type0.fingerprint2 = (fingerprint & FINGERPRINT_BITMASK); break;
	// 	case 2: bkt->type0.fingerprint3 = (fingerprint & FINGERPRINT_BITMASK); break;
	// 	case 3: bkt->type0.fingerprint4 = (fingerprint & FINGERPRINT_BITMASK); break;
	// 	case 4: bkt->type0.fingerprint5 = (fingerprint & FINGERPRINT_BITMASK); break;
	// 	default: assert(0);
	// }
}

static inline __attribute__((always_inline)) uint64_t get_bucket_count(ec_bucket* bkt, int count_index, const uint32_t type_id) {
	return (bkt->value >> COUNT_LOC[type_id][count_index]) & ((1UL << COUNT_LEN[type_id][count_index]) - 1UL);
}

static inline __attribute__((always_inline)) void set_bucket_count(ec_bucket* bkt, int count_index, uint64_t count_value, const uint32_t type_id) {
	bkt->value = (bkt->value & ~(((1UL << COUNT_LEN[type_id][count_index]) - 1UL) << COUNT_LOC[type_id][count_index])) | ((count_value & ((1UL << COUNT_LEN[type_id][count_index]) - 1UL)) << COUNT_LOC[type_id][count_index]);
}

/* Hash operations */
#define GET_HASH_VALUE_SENTENCE(key) int16_t final_key_len = (key_len == 0)? strlen(key): key_len;\
		h1 = (bobhash[0]->run(key, final_key_len)); \
		char s1 = (char) (h1 >> 24); \
		char s2 = (char) (h1 >> 16); \
		char s3 = (char) (h1 >> 8); \ 
		char s4 = (char) (h1); \
		uint8_t fp = (bobhash[1]->run(key, final_key_len));  /*(uint8_t) (s1 ^ s2 ^ s3 ^ s4);*/ \
		if (fp == NULL) { \
			if ( ( s1 | s2 ) != NULL ) { fp = (s1 | s2); } \
			else if ( (s3 | s4 ) != NULL) {fp = (s3 | s4);} \
			else {fp = 1;} \
			}\
		h1 = h1 % bucket_num; \
		assert( (h1^(fp)) <= bucket_num - 1 );\
		h2 = ( h1 ^ (fp) ) % bucket_num; \
		uint hash[2] = {h1, h2};


using namespace std;
class BitMatcher
{
private:
	uint bucket_num, maxloop, h1, h2;	//bucket_num indicates the number of buckets in each array
	ec_bucket *bucket[2];		//two arrays
	BOBHash * bobhash[2];		//Bob hash function

	// cm sketch
	#define CM_SKETCH_WIDTH 2
	#define CM_MAX_CNT 3
	uint cm_sketch_num;
	uint8_t *cm_sketch[CM_SKETCH_WIDTH];
	BOBHash *cm_hash[CM_SKETCH_WIDTH];

public:
	BitMatcher(uint _bucket) {
		bucket_num = _bucket;
		for (int i = 0; i < 2; i++) {
			bobhash[i] = new BOBHash(i + 1000);
		}
		for (int i = 0; i < 2; i++) {	//initialize two arrays 
			bucket[i] = new ec_bucket[bucket_num];
			memset(bucket[i], 0, sizeof(ec_bucket) * bucket_num);
		}
		init_bucket_parameters();
		// init the CM sketch
		cm_sketch_num = bucket_num * (1<<8);
		assert(cm_sketch_num > bucket_num);
		for (int i = 0; i < CM_SKETCH_WIDTH; i++) {
			cm_hash[i] = new BOBHash(i + 500);
			cm_sketch[i] = new uint8_t[cm_sketch_num];
			memset(cm_sketch[i], 0, sizeof(uint8_t) * cm_sketch_num);
		}

	}
	
	// Insert the key into the counter
	inline int CM_insert(const char *key, const int16_t key_len = 0) {
		uint cm_idx[CM_SKETCH_WIDTH];
		for (int i = 0; i < CM_SKETCH_WIDTH; i++) {
			cm_idx[i] = (cm_hash[i]->run(key, key_len)) % cm_sketch_num;
			if ( cm_sketch[i][cm_idx[i]] != CM_MAX_CNT ) {
				cm_sketch[i][cm_idx[i]]++;
			}
		}
		return 0;
	}

	inline uint64_t CM_query(const char *key, const int16_t key_len = 0) {
		uint cm_idx[CM_SKETCH_WIDTH];
		int min_value = CM_MAX_CNT;
		for (int i = 0; i < CM_SKETCH_WIDTH; i++) {
			cm_idx[i] = (cm_hash[i]->run(key, key_len)) % cm_sketch_num;
			if (cm_sketch[i][cm_idx[i]] < min_value) {
				min_value = cm_sketch[i][cm_idx[i]];
			}
		}
		return (min_value < CM_MAX_CNT)? min_value: ((1L<<60));
	}

	// Copy a[0] --> b[0], a[1] --> b[1], ..., a[item_num-1] --> b[item_num-1]
	inline void copy_items_one_by_one(ec_bucket *dst, ec_bucket *src) {
		const uint32_t src_type_id = get_bucket_type_id(src);
		const uint32_t dst_type_id = get_bucket_type_id(dst);
		const uint32_t item_num = get_item_num_in_bucket_type(dst_type_id);
		for (int idx = 0; idx < item_num; idx++) {
			set_bucket_fingerprint(dst, idx, get_bucket_fingerprint(src, idx));
			set_bucket_count(dst, idx, get_bucket_count(src, idx, src_type_id), dst_type_id); 
			// Guarantee the copy is self
			if ( (1UL << COUNT_LEN[dst_type_id][idx]) - 1 < get_bucket_count(src, idx, src_type_id) ) {
				printf("The dst_type_id is %d, the idx is %d, the src_type_id is %d\n", dst_type_id, idx, src_type_id);
				assert(false);
			}
		}
	}

	// Copy a[1] --> b[0], a[2] --> b[1], ..., a[item_num] --> b[item_num-1]
	inline void copy_items_upflow(ec_bucket *dst, ec_bucket *src) {
		const uint32_t src_type_id = get_bucket_type_id(src);
		const uint32_t dst_type_id = get_bucket_type_id(dst);
		const uint32_t item_num = get_item_num_in_bucket_type(dst_type_id);
		for (int idx = 0; idx < item_num; idx++) {
			set_bucket_fingerprint(dst, idx, get_bucket_fingerprint(src, 1+idx));
			set_bucket_count(dst, idx, get_bucket_count(src, 1+idx, src_type_id), dst_type_id);

			if ( COUNT_LEN[dst_type_id][idx] < COUNT_LEN[src_type_id][idx + 1] ) {
				printf("The dst_type_id is %d, the idx is %d, the src_type_id is %d\n", dst_type_id, idx, src_type_id);
				assert(false);
			}
		}
	}

	inline bool kick_to(int origin_hash_table_idx, uint32_t origin_bucket_item_idx, uint8_t fingerprint_value, uint64_t count_value) {
		if (fingerprint_value == NULL) {
			return true; // The kick out is NULL
		}
		// printf("kick: origin_hash_table_idx is %d, origin_bucket_item_idx is %d, fingerprint_value is %d, count_value is %d\n", origin_hash_table_idx, origin_bucket_item_idx, fingerprint_value, count_value);
		//kickout the entry_j in the bucket
		ec_bucket *origin_bucket = &bucket[origin_hash_table_idx][origin_bucket_item_idx];
		uint32_t new_bucket_idx = ( origin_bucket_item_idx ^ (fingerprint_value) ) % bucket_num;
		ec_bucket *dst_bucket = &bucket[1 - origin_hash_table_idx][new_bucket_idx];

		if (maxloop == 1) {
			maxloop--;
			uint32_t new_bucket_type_id = get_bucket_type_id(dst_bucket);
			uint8_t slot_num = get_item_num_in_bucket_type(new_bucket_type_id);
			for (int i = 0; i < slot_num; i++) {
				if (get_bucket_fingerprint(dst_bucket, i) == NULL &&  ( 1UL << COUNT_LEN[new_bucket_type_id][i]) - 1 > count_value) {
					set_bucket_count(dst_bucket, i, count_value, new_bucket_type_id);
					set_bucket_fingerprint(dst_bucket, i, fingerprint_value);
					return true;
				}
			}
		}
		return false; // The kicking fails
	}


	inline bool solve_overflow_locally(ec_bucket* b, const int finger_idx, const uint32_t type_id, const uint32_t table_idx, const uint32_t slot_idx) { //overflow occur in entry_j in the bucket
		for ( int i = finger_idx + 1; i < get_item_num_in_bucket_type(type_id); i++ ) {
			// Try to find an empty entry with more bits
			if ( get_bucket_fingerprint(b, i) == NULL ) {
				// Find an empty entry: move the data and do not change the type
				set_bucket_fingerprint(b, i, get_bucket_fingerprint(b, finger_idx));
				set_bucket_count(b, i, get_bucket_count(b, finger_idx, type_id), type_id);
				set_bucket_fingerprint(b, finger_idx, NULL);
				set_bucket_count(b, finger_idx, 0, type_id);
				return true;
			}
		}
		// Try to exchange with other slot in the same bucket
		uint64_t src_count = get_bucket_count(b, finger_idx, type_id);
		uint8_t src_fingerprint = get_bucket_fingerprint(b, finger_idx);
		for ( int dst_idx = finger_idx + 1; dst_idx < get_item_num_in_bucket_type(type_id); dst_idx++ ) {
			if ( get_bucket_count(b, dst_idx, type_id) < src_count - 1 ) {
				// Upper slot can be exchanged
				uint8_t dst_fingerprint = get_bucket_fingerprint(b, dst_idx);
				uint64_t dst_count = get_bucket_count(b, dst_idx, type_id);
				// Exchange
				set_bucket_fingerprint(b, dst_idx, src_fingerprint );
				set_bucket_count(b, dst_idx, src_count, type_id);
				set_bucket_fingerprint(b, finger_idx, dst_fingerprint);
				set_bucket_count(b, finger_idx, dst_count, type_id);
				return true;
			}
		}
		// No empty entry found, we try to change it to other type of bucket
		ec_bucket new_bkt; new_bkt.value = 0;
		uint8_t least_finger; uint64_t least_count;
		switch (type_id) {
			case 0:
			case 3:
			{
				bool flag_need_up = false;
				uint32_t next_type_id;
				if ( finger_idx != 0 ) {
					flag_need_up = true;
					if ( type_id == 0 ) {
						next_type_id = (finger_idx == 4)? 1 : 2; // [origin_type: 0, overflow_idx: 4] --> 1
					} else {
						next_type_id = (finger_idx == 3)? 6 : 7; // [origin_type: 3, overflow_idx: 3] --> 6
					}
				}
				// It is the bottom type! We only kick out the least entry
				least_finger = get_bucket_fingerprint(b, 0);
				least_count = get_bucket_count(b, 0, type_id);
				if (flag_need_up) {
					// Go right
					set_bucket_type_id(&new_bkt, next_type_id);
					copy_items_upflow(&new_bkt, b);
					b->value = new_bkt.value;
				} else {
					// Keep the same type if finger_idx == 0
					set_bucket_fingerprint(b, 0, NULL);
					set_bucket_count(b, 0, 0, type_id); // Clear the least slot
					assert(least_count == 3 || least_count == 31);
				}
				if ( kick_to(table_idx, slot_idx, least_finger, least_count) ) {
					return true;
				} else if ( !flag_need_up ) {
					// Keep the previous value
					set_bucket_fingerprint(b, 0, least_finger);
					set_bucket_count(b, 0, least_count, type_id);
					return false;
				} else {
					#ifdef ENABLE_CM_SKETCH
					char cm_key[10];
					uint new_slot_idx = slot_idx;
					if (table_idx == 1) {
						new_slot_idx = new_slot_idx ^ ((uint) least_finger);
					} 
					memset(cm_key, 0, sizeof(char) * 10);
					memcpy(cm_key, &new_slot_idx, sizeof(uint));
					memcpy(cm_key+sizeof(uint), &least_finger, sizeof(least_finger));
					uint64_t cm_value = CM_query(cm_key, sizeof(uint)+sizeof(char));
					#endif
				}
				break;
			}
			case 1:
			case 2:
			{
				// We have 4 entries here and we need to move to next type
				if (finger_idx == 3) {
					// The biggest entry is overflowed, kick out the least entry and go right
					set_bucket_type_id(&new_bkt, (type_id == 1)? 4 : 5);
					least_finger = get_bucket_fingerprint(b, 0);
					least_count = get_bucket_count(b, 0, type_id);
					copy_items_upflow(&new_bkt, b);
					b->value = new_bkt.value;
					bool res = kick_to(table_idx, slot_idx, least_finger, least_count);
					if (res) {
						return true;
					} else {
						#ifdef ENABLE_CM_SKETCH
						char cm_key[10];
						uint new_slot_idx = slot_idx;
						if (table_idx == 1) {
							new_slot_idx = new_slot_idx ^ ((uint) least_finger);
						} 
						memset(cm_key, 0, sizeof(char) * 10);
						memcpy(cm_key, &new_slot_idx, sizeof(uint));
						memcpy(cm_key+sizeof(uint), &least_finger, sizeof(least_finger));
						uint64_t cm_value = CM_query(cm_key, sizeof(uint)+sizeof(char));
						#endif
						return false;
					}
				} else {
					// Go down
					uint32_t possible_next_type_id = (type_id == 1)? 2 : 3;
					set_bucket_type_id(&new_bkt, possible_next_type_id);
					uint32_t MAX_LEN_FOR_NEXT_TYPE = COUNT_LEN[possible_next_type_id][3];
					assert(MAX_LEN_FOR_NEXT_TYPE >= 10);
					assert(MAX_LEN_FOR_NEXT_TYPE <= 16);
					uint64_t MAX_COUNT_VALUE_FOR_NEXT = ((1ULL << MAX_LEN_FOR_NEXT_TYPE) - 2);
					if ( get_bucket_count(b, 3, type_id) <= MAX_COUNT_VALUE_FOR_NEXT ) {
						copy_items_one_by_one(&new_bkt, b);
						b->value = new_bkt.value;
						return true;
					} else {
						uint8_t out_finger = get_bucket_fingerprint(b, finger_idx);
						uint64_t out_count = get_bucket_count(b, finger_idx, type_id);
						set_bucket_fingerprint(b, finger_idx, NULL);
						set_bucket_count(b, finger_idx, 0, type_id);
						bool res = kick_to(table_idx, slot_idx, out_finger, out_count);
						if (res) {
							return true;
						} else {
							#ifdef ENABLE_CM_SKETCH
							char cm_key[10];
							uint new_slot_idx = slot_idx;
							if (table_idx == 1) {
								new_slot_idx = new_slot_idx ^ ((uint) out_finger);
							} 
							memset(cm_key, 0, sizeof(char) * 10);
							memcpy(cm_key, &new_slot_idx, sizeof(uint));
							memcpy(cm_key+sizeof(uint), &out_finger, sizeof(out_finger));
							uint64_t cm_value = CM_query(cm_key, sizeof(uint)+sizeof(char));
							#endif
							return false;
						}
					}
				}
				break;
			}
			case 4 ... 10: 
			{
				// For type 4->10, and they are the rightest column types; we can only go down or keep
				bool go_down_enable = false;
				int possible_next_type_id = type_id + 1;
				uint32_t MAX_LEN_FOR_NEXT_TYPE = COUNT_LEN[possible_next_type_id][2];
				assert(MAX_LEN_FOR_NEXT_TYPE >= 13);
				assert(MAX_LEN_FOR_NEXT_TYPE <= 27);
				uint64_t MAX_COUNT_VALUE_FOR_NEXT = ((1ULL << MAX_LEN_FOR_NEXT_TYPE) - 2);
				if (finger_idx < 2 && get_bucket_count(b, 2, type_id) <= MAX_COUNT_VALUE_FOR_NEXT ) {
					// 1st or 2nd slot is overflowed; and the largest slow is able to go down
					go_down_enable = true;
					set_bucket_type_id(&new_bkt, possible_next_type_id);
					copy_items_one_by_one(&new_bkt, b);
					b->value = new_bkt.value;
					return true;
				} else {
					// We can not go down, but the value is overflowed; so we try to kick it out; assert(finger_idx != 2);
					uint8_t out_finger = get_bucket_fingerprint(b, finger_idx);
					uint64_t out_count = get_bucket_count(b, finger_idx, type_id);
					set_bucket_fingerprint(b, finger_idx, NULL);
					set_bucket_count(b, finger_idx, 0, type_id);
					bool kick_res =  kick_to(table_idx, slot_idx, out_finger, out_count);
					if (kick_res) {
						return true;
					} else {
						// Kick fails, we keep the value (The kick keeps)
						set_bucket_fingerprint(b, finger_idx, out_finger);
						set_bucket_count(b, finger_idx, 0, out_count);
						return false;
					}
				}
				break;
			}
			case 11:
			{
				// The last type! We can go nowhere, so just keep the value
				// uint64_t original_val = get_bucket_count(b, finger_idx, type_id);
				// original_val--;
				// set_bucket_count(b, finger_idx, original_val, type_id);
				return false;
			}
			default:
			 	assert(false);
		}
		return false;
	}
	
	inline bool plus(ec_bucket* b, const int finger_idx, const uint32_t type_id, const uint32_t table_idx, const uint32_t slot_idx) { //try to plus entry_j in the bucket, return true if no overflow happens
		uint64_t original_val = get_bucket_count(b, finger_idx, type_id);
		const uint64_t max_cnt_val = (1UL << COUNT_LEN[type_id][finger_idx]);
		if ( 1 + original_val == max_cnt_val ) { 
			return false; // Overflow happens and we cannot solve it before
		}
		original_val++;
		set_bucket_count(b, finger_idx, original_val, type_id);
		if ( 1 + original_val == max_cnt_val ) {
			// Overflow happens, we try to move the counter to other location
			bool res = solve_overflow_locally(b, finger_idx, type_id, table_idx, slot_idx);
			return res;
		}
		return true;
	}
	
	void Insert(const char *key, const int16_t key_len = 0) {
		maxloop = 1;		
		GET_HASH_VALUE_SENTENCE(key);
		bool flag = 0;
		int empty_jj, empty_type_id;
		ec_bucket* empty_bucket;
		for (int i = 0; i < 2; i++) {
			ec_bucket *b = bucket[i] + hash[i];
			uint32_t type_id = get_bucket_type_id(b);
			uint8_t fingerprint_num = get_item_num_in_bucket_type(type_id);
			for (int j = fingerprint_num-1; j >= 0; j--) {
			// for (int j = 0; j < fingerprint_num; j++) {
				if ( get_bucket_fingerprint(b, j) == fp ) {
					// Get the correct bucket, plus it and deal with the kickout
					bool res = plus(b, j, type_id, i, hash[i]);
					return;
				} else if ( !flag && get_bucket_fingerprint(b, j) == NULL) {
					empty_bucket = b;
					empty_jj = j;
					empty_type_id = type_id;
					flag = 1; // We have an empty bucket
				}
			}
		}
		if (flag) {
			// Insert the key into the empty bucket
			set_bucket_fingerprint(empty_bucket, empty_jj, fp);
			set_bucket_count(empty_bucket, empty_jj, 1, empty_type_id);
			return;
		} else {
			static int error_num = 0;
			error_num++; // For web2.data, we find 258K/8M times here!
			// if(error_num % 1 == 0) printf("Error %d\n", error_num);

			// Here, we store the value to the CM sketch
			/*char cm_key[10];
			memset(cm_key, 0, sizeof(char) * 10);
			memcpy(cm_key, &hash[0], sizeof(hash[0]));
			memcpy(cm_key+sizeof(hash[0]), &fp, sizeof(fp));
		 	CM_insert(cm_key, sizeof(hash[0])+sizeof(fp));
			return;*/

			int i = fp & 0x1;
			ec_bucket *b = bucket[i] + hash[i];
			uint32_t type_id = get_bucket_type_id(b);
			uint32_t count = get_bucket_count(b, 0, type_id);
			//if ( count == 1 && (fp & 0x2) == ((error_num & 0x1) << 1) ) {
				// Random replace
				set_bucket_fingerprint(b, 0, fp);
				set_bucket_count(b, 0, 1, type_id);
			//} else {
			//	set_bucket_count(b, 0, count - 1, type_id);
			//}
		}
	}

	double zero(){
		double cnt[2]={0.0, 0.0};
		for (int i=0; i<2; i++) {
			for (int j=0; j<bucket_num; j++) {
				ec_bucket* b = bucket[i] + j;
				const uint64_t type_id = get_bucket_type_id(b);
				const uint8_t fingerprint_num = get_item_num_in_bucket_type(type_id);
				int flag = 1;
				for (int k=0; k< fingerprint_num; k++) {
					if ( get_bucket_fingerprint(b, k) != NULL ) { flag = 0; break; }
				}
				if (1 == flag) cnt[i]+=1; // The bucket is empty
			}
		}
		return (bucket_num-cnt[0])/bucket_num * (bucket_num-cnt[1])/bucket_num;
	}	
	
	double Query(const char *key, const int16_t key_len = 0) {
		GET_HASH_VALUE_SENTENCE(key);

		bool flag=0;
		uint64_t min_value = UINT64_MAX; uint64_t table_min[2];
		__builtin_prefetch(bucket[0] + hash[0], 0, 2);
		__builtin_prefetch(bucket[1] + hash[1], 0, 2);
		for (uint8_t i = 0; i < 2; i++) {
			ec_bucket* b = bucket[i] + hash[i];
			const uint32_t type_id = get_bucket_type_id(b);
			const uint8_t fingerprint_num = get_item_num_in_bucket_type(type_id);
			table_min[i] = get_bucket_count(b, 0, type_id);
			for (uint8_t fpt_idx = 0; fpt_idx < fingerprint_num; fpt_idx++) {
				const uint8_t stored_fingerprint = get_bucket_fingerprint(b, fpt_idx);
				const uint64_t stored_count = get_bucket_count(b, fpt_idx, type_id);
				if ( stored_fingerprint == fp ) {
					return stored_count;
				}
				if (!flag && stored_fingerprint == NULL) {
					flag = 1;
				}
				if (flag) {continue;}  
				if (stored_fingerprint != NULL && min_value > stored_count) { min_value = stored_count;}
			}
		}
		// min_value = min(table_min[0], table_min[1]);
		if (flag) { return 0; } 
		else {
			return min_value;
			#ifdef ENABLE_CM_SKETCH
			char cm_key[10];
			memset(cm_key, 0, sizeof(char) * 10);
			memcpy(cm_key, &hash[0], sizeof(hash[0]));
			memcpy(cm_key+sizeof(hash[0]), &fp, sizeof(fp));
		 	uint64_t cm_value = CM_query(cm_key, sizeof(hash[0])+sizeof(fp));
			assert(cm_value == 0 || cm_value == 1 || cm_value == 2 || cm_value == ((1L<<60)));
			#else
			uint64_t cm_value = (1L<<63);
			#endif
			if (cm_value == 0) {
				// return min_value;
				return 0;
			} else {
				return min(min_value, cm_value);
			}
		}
	}
	
	//memeory access
	int Mem(const char *key, const int16_t key_len = 0) {
		GET_HASH_VALUE_SENTENCE(key);
		for (uint8_t i = 0; i < 2; i++) {
			ec_bucket* b = bucket[i] + hash[i];
			const uint64_t type_id = get_bucket_type_id(b);
			const uint8_t fingerprint_num = get_item_num_in_bucket_type(type_id);
			for (uint8_t j = 0; j < fingerprint_num; j++) {
				const uint8_t stored_fingerprint = get_bucket_fingerprint(b, j);
				if (stored_fingerprint == fp) { return 1;}
			}
		}
		return 2;
	}

	// the use ratio of the bucket
	double Ratio() {
		int used_num = 0;
		int total_slot = 0;
		unordered_map<uint16_t, uint64_t> type_count;
		type_count.clear();
		for (int i = 0; i < 2; i++) {
			for (int j = 0; j < bucket_num; j++) {
				ec_bucket* b = bucket[i] + j;
				const uint32_t type_id = get_bucket_type_id(b);

				if (type_count.find(type_id) == type_count.end()) {
					type_count[type_id] = 1;
				} else {
					type_count[type_id]++;
				}

				const uint32_t slot_num = get_item_num_in_bucket_type(type_id);
				total_slot += slot_num;
				const uint8_t fingerprint_num = get_item_num_in_bucket_type(type_id);
				for (int k = 0; k < fingerprint_num; k++) {
					if ( get_bucket_count(b, k, type_id) != 0 ) { used_num++; }
				}
			}
		}

		printf("The bucket number is %d\n", 2*bucket_num);

		for (int i = 0;  i < 12; i++) {
			if (type_count.find(i) != type_count.end()) {
				printf("type %d: %d with ratio %.2f\%\n", i, type_count[i], ((double) type_count[i] ) * 100 / 2.0 / bucket_num);
			}
		}

		return used_num / (total_slot * 1.0);
	}

	void dump_to_file(FILE* fp) {
		// Write the result to fp
		unordered_map<uint16_t, uint64_t> type_count;
		type_count.clear();
		for (int i = 0; i < 2; i++) {
			for (int j = 0; j < bucket_num; j++) {
				ec_bucket* b = bucket[i] + j;
				const uint32_t type_id = get_bucket_type_id(b);
				const uint8_t fingerprint_num = get_item_num_in_bucket_type(type_id);
				// Group_id, bucket_addr, bucket_type, fingerprint_num, fingerprint_1, count_1, fingerprint_2, count_2, ..., fingerprint_n, count_n
				fprintf(fp, "%d\t%d\t%d\t%d\t", i, j, type_id, fingerprint_num);
				for (int k = 0; k < fingerprint_num; k++) {
					uint32_t fingerprint = get_bucket_fingerprint(b, k);
					uint64_t cnt = get_bucket_count(b, k, type_id);
					// write to the file
					fprintf(fp, "%d\t%d\t", fingerprint, cnt);
				}
				fprintf(fp, "\n");
			}
		}
	}


	//delete the bucket
	void Delete(char *key, const int16_t key_len = 0) {
		GET_HASH_VALUE_SENTENCE(key);
		for (int i = 0; i < 2; i++) {
			ec_bucket* b = bucket[i] + hash[i];
			const uint32_t type_id = get_bucket_type_id(b);
			const uint8_t fingerprint_num = get_item_num_in_bucket_type(type_id);
			for (int j = 0; j < fingerprint_num; j++) {
				const uint8_t stored_fingerprint = get_bucket_fingerprint(b, j);
				if (stored_fingerprint == fp) {
					uint64_t origin_value = get_bucket_count(b, j, type_id);
					set_bucket_count(b, j, origin_value - 1, type_id);
					if ( origin_value == 1 ) {
						set_bucket_fingerprint(b, j, NULL);
					}
					return;
				}
			}
		}
	}

	~BitMatcher() {
		// for (int i = 0; i < 2; i++) {
		// 	delete[]bucket[i];
		// }
		// for (int i = 0; i < 1; i++) {
		// 	delete bobhash[i];
		// }
	}
};
#endif//_BitMatcher_H
