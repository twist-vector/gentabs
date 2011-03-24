#
#
#            Nimrod's Runtime Library
#        (c) Copyright 2010 Andreas Rumpf
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#

## The ``gentabs`` module implements an efficient hash table that is a key-value
## mapping.  The keys are required to be strings, but the values may be any Nimrod
## or user defined type.  This module supports matching of keys in case-sensitive, 
## case-insensitive and style-insensitive modes.

import
  os, hashes, strutils

type
  TGenTableMode* = enum    ## describes the table's key matching mode
    modeCaseSensitive,     ## case sensitive matching of keys
    modeCaseInsensitive,   ## case insensitive matching of keys
    modeStyleInsensitive   ## style sensitive matching of keys
    
  TGenKeyValuePair[T] = tuple[key: string, val: T]
  TGenKeyValuePairSeq[T] = seq[TGenKeyValuePair[T]]
  TGenTable*[T] = object of TObject
    counter: int
    data: TGenKeyValuePairSeq[T]
    mode: TGenTableMode

  PGenTable*[T] = ref TGenTable[T]     ## use this type to declare hash tables


const
  growthFactor = 2
  startSize = 64


proc len*[T](tbl: PGenTable[T]): int =
  ## returns the number of keys in `tbl`.
  result = tbl.counter


iterator pairs*[T](tbl: PGenTable[T]): tuple[key: string, value: T] =
  ## iterates over any (key, value) pair in the table `tbl`.
  for h in 0..high(tbl.data):
    if not isNil(tbl.data[h].key):
      yield (tbl.data[h].key, tbl.data[h].val)


proc myhash[T](tbl: PGenTable[T], key: string): THash =
  case tbl.mode
  of modeCaseSensitive: result = hashes.hash(key)
  of modeCaseInsensitive: result = hashes.hashIgnoreCase(key)
  of modeStyleInsensitive: result = hashes.hashIgnoreStyle(key)


proc myCmp[T](tbl: PGenTable[T], a, b: string): bool =
  case tbl.mode
  of modeCaseSensitive: result = cmp(a, b) == 0
  of modeCaseInsensitive: result = cmpIgnoreCase(a, b) == 0
  of modeStyleInsensitive: result = cmpIgnoreStyle(a, b) == 0


proc mustRehash(length, counter: int): bool =
  assert(length > counter)
  result = (length * 2 < counter * 3) or (length - counter < 4)


proc newGenTable*[T](mode: TGenTableMode): PGenTable[T] =
  ## creates a new generic hash table that is empty.
  new(result)
  result.mode = mode
  result.counter = 0
  newSeq(result.data, startSize)



proc nextTry(h, maxHash: THash): THash {.inline.} =
  result = ((5 * h) + 1) and maxHash


proc RawGet[T](tbl: PGenTable[T], key: string): int =
  var h: THash
  h = myhash(tbl, key) and high(tbl.data) # start with real hash value
  while not isNil(tbl.data[h].key):
    if mycmp(tbl, tbl.data[h].key, key):
      return h
    h = nextTry(h, high(tbl.data))
  result = - 1


proc RawInsert[T](tbl: PGenTable[T], data: var TGenKeyValuePairSeq[T], key: string, val: T) =
  var h: THash
  h = myhash(tbl, key) and high(data)
  while not isNil(data[h].key):
    h = nextTry(h, high(data))
  data[h].key = key
  data[h].val = val


proc Enlarge[T](tbl: PGenTable[T]) =
  var n: TGenKeyValuePairSeq[T]
  newSeq(n, len(tbl.data) * growthFactor)
  for i in countup(0, high(tbl.data)):
    if not isNil(tbl.data[i].key): RawInsert[T](tbl, n, tbl.data[i].key, tbl.data[i].val)
  swap(tbl.data, n)


proc hasKey*[T](tbl: PGenTable[T], key: string): bool =
  ## returns true iff `key` is in the table `tbl`.
  result = rawGet(tbl, key) >= 0


proc `[]`*[T](tbl: PGenTable[T], key: string): T =
  ## retrieves the value at ``tbl[key]``. If `key` is not in `tbl`, "" is returned
  ## and no exception is raised. One can check with ``hasKey`` whether the key
  ## exists.
  var index: int
  index = RawGet(tbl, key)
  if index >= 0: result = tbl.data[index].val
  #else: result = ""   ### Not sure what to do here

proc `[]=`*[T](tbl: PGenTable[T], key: string, val: T) =
  ## puts a (key, value)-pair into `tbl`.
  var index = RawGet(tbl, key)
  if index >= 0:
    tbl.data[index].val = val
  else:
    if mustRehash(len(tbl.data), tbl.counter): Enlarge(tbl)
    RawInsert(tbl, tbl.data, key, val)
    inc(tbl.counter)


when isMainModule:
  #
  # Verify a table of integer values (string keys)
  #
  stdout.write("Verify tables of integer values (string keys)... ")
  var x = newGenTable[int](modeCaseInsensitive)
  x["one"]   = 1
  x["two"]   = 2
  x["three"] = 3
  x["four"]  = 4
  x["five"]  = 5
  assert(len(x) == 5)             # length procedure works
  assert(x["one"] == 1)           # case-sensitive lookup works
  assert(x["ONE"] == 1)           # case-insensitive should work for this table
  assert(x["one"]+x["two"] == 3)  # make sure we're getting back ints
  assert(x.hasKey("one"))         # hasKey should return 'true' for a key of "one"...
  assert(not x.hasKey("NOPE"))    # ...but key "NOPE" is not in the table.
  for k,v in pairs(x):            # make sure the 'pairs' iterator works
    assert(x[k]==v)
  stdout.write("OK\n")
  
  #
  # Verify a table of user-defined types
  #
  stdout.write("Verify a table of user-defined types... ")
  type
    TMyType = tuple[first, second: string] # a pair of strings
  
  var y = newGenTable[TMyType](modeCaseInsensitive) # hash table where each value is TMyType tuple
  
  # Strangeness!  If we don';t declare at least one object of our new type we fail!
  var junk: TMyType = ("One", "Two")
  
  y["Hello"] = ("Hello", "World")
  y["Goodbye"] = ("Goodbye", "Everyone")
  assert( y["Hello"].first == "Hello" )
  assert( y["Hello"].second == "World" )
  stdout.write("OK\n")
  
  
  #
  # Verify table of tables
  #
  stdout.write("Verify table of tables... ")
  var z: PGenTable[ PGenTable[int] ] # hash table where each value is a hash table of ints
  
  z = newGenTable[PGenTable[int]](modeCaseInsensitive)
  z["first"] = newGenTable[int](modeCaseInsensitive)
  z["first"]["one"] = 1
  z["first"]["two"] = 2
  z["first"]["three"] = 3
  
  z["second"] = newGenTable[int](modeCaseInsensitive)
  z["second"]["red"] = 10
  z["second"]["blue"] = 20
  
  assert(len(z) == 2)               # length of outer table
  assert(len(z["first"]) == 3)      # length of "first" table
  assert(len(z["second"]) == 2)     # length of "second" table
  assert( z["first"]["one"] == 1)   # retrieve from first inner table
  assert( z["second"]["red"] == 10) # retrieve from second inner table
  
  # z is a table-of-tables.  We should be able to pull out the table for each 
  # key of the "outer" table with pairs, the each entry in the "inner" tables
  # with pairs.  This doesn't seem to compile though.
  #for k,v in pairs(z):
  #  for k2,v2 in pairs(v):
  #    echo( "$#: $# <-> $#" % [k, k2,$v2] )
  
  stdout.write("OK\n")
  
    
