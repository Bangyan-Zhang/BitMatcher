from asyncio import wait_for
from multiprocessing.connection import wait
import os
from random import random, randint
import re
from statistics import variance
import numpy as np
import matplotlib.pyplot as plt
import pickle
from scipy.stats import wasserstein_distance, energy_distance
import time
from multiprocessing import Process, Pool

def get_traffic_count(filename, KEY_LEN=13, SKIP_LEN=0):
    res = {}
    key_seq = []
    with open(filename, "rb") as f:
        abytes = f.read()
        for i in range(len(abytes) // (KEY_LEN+SKIP_LEN)):
            start_idx = i*(KEY_LEN+SKIP_LEN)
            the_key = abytes[start_idx:start_idx+KEY_LEN]
            key_seq.append(the_key)
            if the_key in res:
                res[the_key] += 1
            else:
                res[the_key] = 1
    return res, key_seq

PROCESSING_CLK = 40
PARALLEL_NUM = 1
TABLE_SIZE = (1<<12)
def run_fpga_sim(file_name):
    cnt_map, key_seq = get_traffic_count(file_name)
    # hash the keys
    key_seq = [ (hash(key) % TABLE_SIZE) for key in key_seq ]
    clk = 0
    insert_idx = 0
    in_processing = {}
    wait_for_enq = [] # list of keys waiting for enqueue
    max_queue = 0
    max_merge = 0
    total_merge = 0
    merge_time = {}
    TOTAL_KEY = len(key_seq)
    while True:
        clk += 1
        read_time = int(randint(1, 100) <= 95) # have traffic with probability
        for i in range(read_time):
            if insert_idx < TOTAL_KEY:        
                key = key_seq[insert_idx]
                insert_idx += 1
                # Try to enqueue a key and merge it if there is a key in the wait_for_enq
                MAX_CMP = min(len(wait_for_enq), 20)
                if key not in wait_for_enq[0:MAX_CMP]:
                    wait_for_enq.append(key)
                else:
                    if key in merge_time:
                        merge_time[key] += 1
                        max_merge = max(max_merge, merge_time[key])
                    else:
                        merge_time[key] = 1
                    total_merge += 1
                max_queue = max(max_queue, len(wait_for_enq))
                if max_queue > 1000:
                    print("Queue is too long with running clock as %d!" % (clk) )
                    return
        if len(wait_for_enq) == 0 and insert_idx >= TOTAL_KEY:
            print("The total clk is %d for %d keys, avg throughput: %.4f clk/request" % (clk, TOTAL_KEY, ((float)(clk))/TOTAL_KEY) )
            print("The max queue length is %d" % max_queue)
            print("The max merge time is %d and total merge is %d (%.4f)" % (max_merge, total_merge, (float)(total_merge)/TOTAL_KEY))
            return
        for _ in range(PARALLEL_NUM):
            if len(wait_for_enq) > 0:
                # Case 1: From the key list, get a key which can be enqueued
                # for key in wait_for_enq:
                #     if not (key in in_processing):
                #         in_processing[key] = clk
                #         wait_for_enq.remove(key)
                #         if key not in wait_for_enq:
                #             merge_time[key] = 0 # when key leaves, clear
                #         break
                #     else:
                #         wait_for_enq.append(wait_for_enq.pop(0))

                # Case 2: Only check the top key; if it can not be enqueued, remove it to the end
                for _ in range(1):
                    key = wait_for_enq[0]
                    if not (key in in_processing):
                        in_processing[key] = clk
                        wait_for_enq.pop(0)
                        if key not in wait_for_enq:
                            merge_time[key] = 0
                        break
                    else:
                        wait_for_enq.append(wait_for_enq.pop(0))
                
            # Check whether all keys are dealt
            if len(in_processing) > 0:
                pop_list = []
                for key in in_processing:
                    if in_processing[key] + PROCESSING_CLK <= clk:
                        pop_list.append(key)
                assert(len(pop_list) <= 1) # At most 1 key is processed
                for key in pop_list:
                    in_processing.pop(key)
        if clk % 1e6 == 0:
            print("clk: %d;" % clk)
            print("in_processing: %d;" % len(in_processing))
            print("wait_for_enq: %d;" % len(wait_for_enq))
            print("max_queue: %d;" % max_queue)
            print("\n")
def main():
    pool = Pool(15)
    pool.close()
    pool.join()
    print("Done!")

if __name__ == "__main__":
    print("********CAIDA*******")
    run_fpga_sim("./../data/1.dat")
    print("******** Web *******")
    run_fpga_sim("./../data/web1.dat")