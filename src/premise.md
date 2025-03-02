# Premise

Would it make sense to try and compute fundamental interactions of elementary particles, not basing it on some fixed space initially, but rather basing it on relationships using [graphs](https://en.m.wikipedia.org/wiki/Graph_theory)?

> I say "initially" cause space would then be a construct in a "viewport" for the system

Each particle would be a node, a collection of the intrinsic properties of that type of particle. And the edges determine the order and kind of fundamental interaction that will happen between two particles in a cycle

The end goal is to simply provide a system that has a minimum set of rules and objects that can in some way interact at a given time and let it loop. Trying to do some emergent behavior kind of simulation

My idea for this was to abstract time itself in a way, the program doesn't have a notion of time, but the user would see iterations; the iterations describe a state of the system. By the end of an iteration the state may have mutated based on the interactions between pairs or orders of particles in the adjacency set

The basic structure is always the graph I mentioned (more akin to a list in a practical sense though). The graph can have any number of nodes:

```rs
Vertices: {
  Particle 1: ...
  ...
  Particle N: ...
}
```

Where each node is a data structure with:

```rs
Particle: {
  data: T
  adj_set: Set
  inc_set: Set
}
```

`T` denotes a generic type
And the `adj_set` and `inc_set` are simply sets of numbers which refer to particle indexes from the `Vertices` hashmap

this way, I iterate over the vertices and have, in order, particle 1 interact with all it's adj_set particles, updating the data according to the interaction function.
then move on to particle 1+1 and do the same, for each particle until no more remain to be updated in that iteration

the iteration starts over and the same process repeats, now with possibly more or less particles

I think I'll start out by defining some basic structure for generic particles and simply introduce interactions based on Feynman diagrams in some function format that

- mutates
- emits
- annihilates
- absorbs
particles in a random fashion

interactions are going to be 1:1 for a single iteration in the simulation, so the full computational complexity will be T(n) with n being the amount of particles in the system. I'll initially limit the amount of particles in a way that if they start emitting too often no more allocations will be made
