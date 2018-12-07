# Proj2

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
* Chord ring is creates with 2 nodes first with finger tables and successor and predeccesor pointers
* After that, each node is added
* fix_fingers and stabilize run periodically fixing fingers and messages
* notify is called when a successor in some node is updated
* The number of messages stored is arbitrarily chosen and is printed 
* Each message will have an id that hashes to a particular node in the ring
* After this, we planned to search within the ring and while randomly failing nodes until only two nodes remain in the ring

## What is working

* Creating a chord ring as per input
* Dynamically adding nodes to the ring
* Finger tables and succ and pred pointers being fixed on the fly
* Facing errors while running into a loop checking for succ
