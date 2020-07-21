module privatedub.work;

import sumtype;
import std.typecons : Nullable;

// a partially implemented double linked list
struct List(T) {
  import std.typecons : Nullable;

  struct Node {
    T t;
    Node* prev, next;
  }

  private Node* head, tail;
  Nullable!T front() {
    if (head is null)
      return typeof(return).init;
    return typeof(return)(head.t);
  }

  Nullable!T popFront() {
    auto f = front();
    if (f.isNull)
      return f;
    head = head.next;
    if (head)
      head.prev = null;
    return f;
  }

  typeof(this) insertBack(T t) {
    if (head is null) {
      head = tail = new Node(t, null, null);
      return this;
    }
    tail.next = new Node(t, tail, null);
    tail = tail.next;
    return this;
  }
}

struct WorkQueue(Ts...) {
  import std.typecons : Nullable;
  import std.array : array;
  import std.exception : enforce;

  // first drain one queue, then the next, etc.
  struct SerialWork {
    WorkQueue!(Ts)[] queues;
  }

  struct ParallelWork {
    WorkQueue!Ts[] queue; // have to use an array else it will refer to itself in a loop
  }

  ParallelWork parallel(W)(W[] ws) {
    import std.algorithm : each;

    List!Item items;
    ws.each!(w => items.insertBack(Item(w)));
    return ParallelWork([WorkQueue!Ts(items)]);
  }

  ParallelWork parallel(Ws...)(auto ref Ws ws) {
    import std.range : iota;
    import std.algorithm : map, joiner, each;
    import std.conv : text, to;

    enum code = iota(0, Ws.length).map!(i => "Item(ws[" ~ i.to!string ~ "])").joiner(",").text();
    mixin("auto arr = [" ~ code ~ "];");
    List!Item items;
    arr.each!(item => items.insertBack(item));
    return ParallelWork([WorkQueue!Ts(items)]);
  }

  alias Item = SumType!(SerialWork, ParallelWork, Ts);

  private List!Item items;

  void enqueue(T)(T t) {
    items.insertBack(Item(t));
  }

  SerialWork serial(Ws...)(auto ref Ws ws) {
    import std.range : iota;
    import std.algorithm : map, joiner;
    import std.conv : text, to;
    import std.array : array;

    enum code = iota(0, Ws.length).map!(i => "Item(ws[" ~ i.to!string ~ "])").joiner(",").text();
    mixin("auto items = [" ~ code ~ "];");
    return SerialWork(items.map!(item => WorkQueue!Ts(List!Item().insertBack(item))).array);
  }

  Nullable!Item dequeue() {
    return items.popFront();
  }
}

struct Scheduler(Queue) {
  Queue queue;
  void drain(Runner, Args...)(auto ref Runner runner, auto ref Args args) {
    drainQueue(queue, runner, args);
  }

  void drainQueue(Runner, Args...)(ref Queue queue, auto ref Runner runner, auto ref Args args) {
    import std.traits : hasMember;
    import std.algorithm : each;
    import privatedub.gitlab.crawler;

    auto task = queue.dequeue();
    while (!task.isNull) {
      task.get.match!((Queue.SerialWork serial) {
        serial.queues.each!((ref q) => this.drainQueue(q, runner, args));
      }, (Queue.ParallelWork parallel) {
        parallel.queue.each!((ref q) => this.drainQueue(q, runner, args));
      }, (ref FetchProjectSubPackage t) {
        static if (__traits(compiles, runner.notify(t)))
          runner.notify(t);
        static if (hasMember!(typeof(t), "run")) {
          import std.traits : Parameters;
          import std.meta : AliasSeq;

          alias Params = Parameters!(t.run!Queue)[1 .. $];
          auto selectedArgs = filterByType!(AliasSeq!(Params))(args);
          t.run(queue, selectedArgs.expand);
        }
      }, (ref t) {
        static if (__traits(compiles, runner.notify(t)))
          runner.notify(t);
        static if (hasMember!(typeof(t), "run")) {
          import std.traits : Parameters;
          import std.meta : AliasSeq;

          alias Params = Parameters!(t.run!Queue)[1 .. $];
          auto selectedArgs = filterByType!(AliasSeq!(Params))(args);
          t.run(queue, selectedArgs.expand);
        }
      });
      task = queue.dequeue();
    }
  }
}

template filterByType(Types...) {
  auto filterByType(Args...)(auto ref Args args) {
    import std.meta;
    import std.traits;
    import std.typecons;
    import std.range : iota;
    import std.algorithm : map, joiner;
    import std.conv : text, to;

    alias selectIndex = ApplyRight!(staticIndexOf, Args);
    alias indexes = staticMap!(selectIndex, Types);

    enum code = [indexes].map!(i => "args[" ~ i.to!string ~ "]").joiner(",").text();
    mixin("return tuple(" ~ code ~ ");");
  }
}

unittest {
  import std.stdio;
  import std.meta : AliasSeq;

  static assert(is(typeof(filterByType!(AliasSeq!(string))(5, "bla")[0]) == string));
}

unittest {
  import std.stdio;
  import std.meta : AliasSeq;

  auto args = filterByType!(AliasSeq!(int, string))(5, "bla");
  void fun(int a, string b) {
  }

  fun(args.expand);
}