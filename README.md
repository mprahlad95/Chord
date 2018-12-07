# Proj3

## Group members

* Prahlad Misra [UFID: 00489999]
* Saranya Vatti [UFID: 29842706]

## Instructions

* Project was developed and tested in windows 8; 4 core
* Unzip prahlad_saranya.zip 

```sh
> unzip prahlad_saranya.zip
> cd prahlad_saranya
>  mix run proj3.exs 20000 10
m = 15
number of messages stored in ring = 60000
Average hops for 20000 nodes each making 10 requests is 8
> mix run proj3.exs 50000 10
m = 16
number of messages stored in ring = 150000
Average hops for 50000 nodes each making 10 requests is 8
```

## The implementation

* Chord protocol has been implemented as per https://pdos.csail.mit.edu/papers/ton:chord/paper-ton.pdf
* "m", the number of bits in the key/node identifiers is chosen and printed.
* Number of nodes on the ring is taken as input and the chord ring is created
* Messages are generated randomly and stored
* The number of messages stored is arbitrarily chosen and is printed 
* Each message will have an id that hashes to a particular node in the ring
* After this, we start searching for random messages from each node until each node has done numRequests (input) number of requests
* The average number of hops taken for all the searches is printed

## What is working

* Creating a chord ring as per input
* Storing random number of messages
* Making as many random searches within ring as per input
* Counting the average hops

## Largest network we managed to deal with

* numNodes = 100000
* numRequests = 10
* number of messages = 300000
* Average hops = 9

## Observations

* As the number of nodes increases, we can see that the growth of the hops is in the same order as the growth of log(numNodes) as is shown in the paper.

|    numNodes      |     numRequests    |  Average hops |  log(numNodes) |         m      |
| ---------------- |:------------------:|:-------------:|:--------------:|:--------------:|
|      100         |        10          |       4       |      6.64385   |         7      |
|      100         |       100          |       4       |      6.64385   |         7      |
|      500         |        10          |       5       |      8.96578   |         9      |
|      500         |       100          |       5       |      8.96578   |         9      |
|     1000         |        10          |       5       |      9.96578   |        10      |
|     1000         |       100          |       5       |      9.96578   |        10      |
|     5000         |       100          |       7       |     12.28771   |        13      |
|     10000        |        10          |       7       |     13.28771   |        13      |
|     10000        |       100          |       7       |     13.28771   |        15      |
|     20000        |        10          |       8       |     14.28771   |        15      |
|     50000        |        10          |       8       |     15.60964   |        16      |
|    100000        |        10          |       9       |     16.60964   |        17      |

