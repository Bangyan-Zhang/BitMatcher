#include <stdio.h>
#include <iostream>
#include <fstream>
#include <unordered_map>
#include <map>
#include <string>
#include <string.h>
#include <ctime>
#include <time.h>
#include <iterator>
#include <math.h>
#include <vector>

#include "ElasticSketch.h"
#include "BitMatcher.h"
#include "dms4.h"

using namespace std;


char * filename_stream = "../../data/";


char insert[30000000 + 1000000 / 5][105];
char query[30000000 + 1000000 / 5][105];


unordered_map<string, int> unmp;

#define testcycles 1

int main(int argc, char** argv)
{
    double memory = 0.1;
    if(argc >= 2)
    {
        filename_stream = argv[1];
    }
    if (argc >= 3)
    {
    	memory = stod(argv[2]);
    }
    
    unmp.clear();
    int val;

    //const double memory = 0.4;// MB
    int memory_ = memory * 1000;//KB
    int word_size = 64;


    int w = memory_ * 1024 * 8.0 / COUNTER_SIZE;	//how many counter;
    int w_p = memory * 1024 * 1024 * 8.0 / (word_size * 2);
    int m1 = memory * 1024 * 1024 * 1.0/4 / 8 / 8;
    int m2 = memory * 1024 * 1024 * 3.0/4 / 2 / 1;
    int m2_mv = memory * 1024 * 1024 / 8 / 4;
    int w_dhs = memory * 1000 * 1024 / 16;

    printf("\n******************************************************************************\n");
    printf("Evaluation starts!\n\n");

    Elasticsketch *elasticsketch;
    BitMatcher *bmatcher;
    DHS *dhs;

    char _temp[200], temp2[200];
    int t = 0;
    int package_num = 0;

    FILE *file_stream = fopen(filename_stream, "r");

    while (fread(insert[package_num], 1, KEY_LEN, file_stream)==KEY_LEN)
    {
        unmp[string(insert[package_num])]++;
        package_num++;

        if(package_num == MAX_INSERT_PACKAGE)
            break;
    }
    fclose(file_stream);
   
    printf("memory = %dKB\n", memory_);
    printf("dataset name: %s\n", filename_stream);
    printf("total stream size = %d\n", package_num);
    printf("distinct item number = %d\n", unmp.size());
  
    int max_freq = 0;
    unordered_map<string, int>::iterator it = unmp.begin();

    for(int i = 0; i < unmp.size(); i++, it++)
    {
        strcpy(query[i], it->first.c_str());

        int temp2 = it->second;
        max_freq = max_freq > temp2 ? max_freq : temp2;
    }
    printf("max_freq = %d\n", max_freq);
    
    printf("*************************************\n");

/********************************insert*********************************/

    timespec time1, time2;
    long long resns;

	clock_gettime(CLOCK_MONOTONIC, &time1);
	for (int t = 0; t < testcycles; t++)
	{
		elasticsketch = new Elasticsketch(m1, m2);
		for (int i = 0; i < package_num; i++)
		{
			elasticsketch->Insert(insert[i]);
		}
	}
	clock_gettime(CLOCK_MONOTONIC, &time2);
	resns = (long long)(time2.tv_sec - time1.tv_sec) * 1000000000LL + (time2.tv_nsec - time1.tv_nsec);
	double throughput_elastic = (double)1000.0 * testcycles * package_num / resns;
	//printf("throughput of EL (insert): %.6lf Mips\n", throughput_elastic);


    for (int t = 0; t < testcycles; t++)
    {
        bmatcher = new BitMatcher(memory * 1024 *1024 / 8 / 2);
        clock_gettime(CLOCK_MONOTONIC, &time1);
        for (int i = 0; i < package_num; i++)
        {
            bmatcher->Insert(insert[i]);
        }
        clock_gettime(CLOCK_MONOTONIC, &time2);
        resns += (long long)(time2.tv_sec - time1.tv_sec) * 1000000000LL + (time2.tv_nsec - time1.tv_nsec);
    }
    double throughput_bm = (double)1000.0 * testcycles * package_num / resns;
    //printf("throughput of BM (insert): %.6lf Mips\n", throughput_bm);


    for (int t = 0; t < testcycles; t++)
    {
        dhs = new DHS(w_dhs);
        
        clock_gettime(CLOCK_MONOTONIC, &time1);
        for (int i = 0; i < package_num; i++)
        {
                dhs->Insert(insert[i]);
        }
        clock_gettime(CLOCK_MONOTONIC, &time2);
        resns += (long long)(time2.tv_sec - time1.tv_sec) * 1000000000LL + (time2.tv_nsec - time1.tv_nsec);
    }
    double throughput_dhs = (double)1000.0 * testcycles * package_num / resns;
    //printf("throughput of DHS (insert): %.6lf Mips\n", throughput_dhs);	

 
/********************************************************************************************/


    //avoid the over-optimize of the compiler! 
    double sum = 0;

    if(sum == (1 << 30))
        return 0;

    char temp[105];

    int val_elastic=0, val_bm=0, val_dhs=0;
    
    unordered_map<int, double> real_dist;
    unordered_map<int, double> el_dist;
    unordered_map<int, double> bm_dist;
    unordered_map<int, double> dhs_dist;
    

    for(unordered_map<string, int>::iterator it = unmp.begin(); it != unmp.end(); it++)
    {
        strcpy(temp, (it->first).c_str());
        val = it->second;

        real_dist[val]++;
        
	
	    val_elastic = elasticsketch->Query(temp);
        val_bm = bmatcher->Query(temp);
        val_dhs = dhs->Query(temp);

        el_dist[val_elastic]++;
        bm_dist[val_bm]++;
        dhs_dist[val_dhs]++;
    }

    double zi_el=0.0, zi_bm=0.0, zi_dhs=0.0;
    double mu_el=0.0, mu_bm=0.0, mu_dhs=0.0;

    for (int i=1; i<=max_freq; i++){
        zi_el += fabs(real_dist[i] - el_dist[i]);   //fen zi
        zi_bm += fabs(real_dist[i] - bm_dist[i]);
        zi_dhs += fabs(real_dist[i] - dhs_dist[i]);
        
        mu_el += (real_dist[i] + el_dist[i]) / 2.0;   //fen mu
        mu_bm += (real_dist[i] + bm_dist[i]) / 2.0;
        mu_dhs += (real_dist[i] + dhs_dist[i]) / 2.0;
    }

    printf("WMRE_EL = %lf\n", zi_el/mu_el);
    printf("WMRE_DHS = %lf\n", zi_dhs/mu_dhs);
    printf("WMRE_BM = %lf\n", zi_bm/mu_bm);
	
    printf("******************************************************************************\n");
    printf("Evaluation Ends!\n\n");

    return 0;
}
