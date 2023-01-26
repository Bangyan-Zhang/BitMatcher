#ifndef _SALSA_H
#define _SALSA_H

#include "params.h"
#include <string.h>
#include <iostream>
//#include "MurmurHash.h"
#include "BOBHash.h"
#include <random>
#include <mmintrin.h>
#include <algorithm>
#define Min(a,b) 	((a) < (b) ? (a) : (b))
#define THR		(0x0f)
using namespace std;
class SalsaCM {
private:
	const int step=31;
	char  hash_size;
    unsigned char*counter;
    bool *flag;
	uint64_t w, d, hash_seed,
		bias_range, bias_mask,
		index_range, index_mask;
	//uint64_t (*hash_func)(const void*, int32_t, uint32_t);
	BOBHash * bobhash[4];
public:
	SalsaCM(uint32_t _w, uint32_t _d, uint32_t _hash_seed = 1000) {
		d             	= _d;
		hash_size	= (d == 2) ? 0x20 : 0x40;
		//hash_func	= (d == 2) ? MurmurHash32 : MurmurHash64B;
		for (int i = 0; i < d; i++) {
			bobhash[i] = new BOBHash(i + 750);
		}
		bias_range	= Min((hash_size - ceil(log2(_w))) / (d - 1),0x08);
        w = _w/8*7;
        w=w/d;
        index_range	= Min(hash_size - bias_range * d, ceil(log2(w)) - bias_range);
        bias_mask	= (((uint64_t)1) << bias_range) - 1;
		index_mask	= (((uint64_t)1) << index_range) - 1;
		hash_seed	= _hash_seed;		
		counter		= new unsigned char[w*d]();
        flag        = new bool[w*d]();
	}
    void update(uint32_t pos,uint32_t r,unsigned int now,unsigned char*counter,bool*flag){
        uint32_t len=r-pos+1;
        if (len>=32) return;
        uint32_t tpos=(pos|len)-len,tr=tpos+(len<<1)-1;
        if(tr>=w)return;
        while(pos>tpos){
            pos--;
            if(!flag[pos]){
                now+=Ask(pos,counter,flag);
            }
        }
        while(r<tr){
            r++;
            if(!flag[r]){
                now+=Ask(r,counter,flag);
            }
        }
        while(r>pos){
            counter[r]=(now&0xff);
            now>>=8;
            flag[r]=1;
            r--;
        }
        counter[r]=(now&0xff);
    }
    void Add(uint32_t pos,unsigned char*counter,bool*flag){
        // printf("add %d\n",pos);
        uint32_t l=pos,r=pos+1;
        while(flag[l]==1)l--;
        while(flag[r]==1)r++;r--;
        unsigned now=counter[l];
        pos=l;
        for(l++;l<=r;l++){
            now<<=8;
            now+=counter[l];
        }
        now++;
        l=(r-pos+1)*8;
        l=(1<<l);
        if(now>=l){
            update(pos,r,now,counter,flag);
            return;
        }
        while(r>pos){
            counter[r]=(now&0xff);
            now>>=8;
            r--;
        }
        counter[r]=(now&0xff);
        return;
    }
    unsigned int Ask(uint32_t pos,unsigned char*counter,bool*flag){
        uint32_t l=pos,r=pos+1;
        while(flag[l]==1)l--;
        while(flag[r]==1)r++;r--;
        unsigned int re=counter[l];
        for(l++;l<=r;l++){
            re<<=8;
            re+=counter[l];
        }
        return re;
    }
	void Insert(const char* str) {
        uint32_t h_s=hash_seed;
        for(uint32_t i=0;i<d;i++){
            h_s=h_s*hash_seed+i;
            //uint32_t hash_value=hash_func(str, KEY_LEN, h_s);
			uint32_t hash_value = bobhash[i]->run(str, strlen(str));
            Add(hash_value%w,counter+(i*w),flag+(i*w));
        }
	}
	double Query(const char* str) {
		unsigned int query=(1<<29),kk;
        uint32_t h_s=hash_seed;
		for(uint32_t i=0;i<d;i++){
            h_s=h_s*hash_seed+i;
            //uint32_t hash_value=hash_func(str, KEY_LEN, h_s);
			uint32_t hash_value = bobhash[i]->run(str, strlen(str));
            kk=Ask(hash_value%w,counter+(i*w),flag+(i*w));
            query=Min(kk,query);
		}
		return query;
	}
    void check(){
        for(int i=0;i<w;i++)
        printf("%u ",counter[i]);
        puts("");
        for(int i=0;i<w;i++)
        printf("%d ",flag[i]);
        puts("");
    }
};
#endif//_SALSA_H