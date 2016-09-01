# ProcessTreeDictionary

Implements a dictionary that is scoped to a process tree by replacing
the group leader with a process that:

  - Maintains a dictionary of state
  - Forwards all unrecognized messages to the original group leader so
    that IO still works

Any process can be the root of its own process tree by starting a
`ProcessTreeDictionary`.

The [Erlang docs](http://erlang.org/doc/man/erlang.html#group_leader-0)
provide a summary of what a group leader is:

> Every process is a member of some process group and all groups have a
> group leader. All I/O from the group is channeled to the group leader.
> When a new process is spawned, it gets the same group leader as the
> spawning process. Initially, at system start-up, init is both its own
> group leader and the group leader of all processes.

Since every new process inherits the group leader from its parent, a process
can start a `ProcessTreeDictionary` in place of its existing group leader, and
*every* descendant process will inherit it, allowing them to access the state
of the same `ProcessTreeDictionary`.

Note that _all_ functions provided by this module rely upon side effects.
Since referential transparency is a primary value of Elixir, Erlang, and
functional programming in general, and _none_ of the functions provided
by this module are referentially transparent, we recommend you limit your
usage of this module to specialized situations, such as for building test
fakes to stand-in for stateful modules.

Important caveat: if any processes in your tree start an application with
`Application.start`, `Application.ensure_started`, or
`Application.ensure_all_started`, the started application processes will _not_
be a part of the process tree, because OTP manages application starts for you.
If you need to access the `ProcessTreeDictionary` from the started processes,
you'll need to start the supervisor of the application yourself. For more info,
see the [Erlang docs](http://erlang.org/doc/apps/kernel/application.html#start0).

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `process_tree_dictionary` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:process_tree_dictionary, "~> 0.1.0"}]
    end
    ```

## Example Usage

We use this library primarily to implement test fakes to stand in for
_stateful modules_. A stateful module exports functions that operate
on additional state that is not present in any of the arguments. For
example, consider a theoretical Amazon S3 client for our application
that provides the following interface:

``` elixir
defmodule MyApp.S3 do
  def get(bucket, key) do
    # get the object at the provided key
  end

  def put(bucket, key, object) do
    # put the object at the provided key
  end
end
```

In our test environment, we would like to use an alternate
implementation of this module's interface. Before we built
`ProcessTreeDictionary`, there were two common approaches we
used for building stateful test fakes in this kind of situation:

  1. **Using the process dictionary**: in our fake implementations of
     `get/2` and `put/3`, we would simply delegate to `Process.get/2`
     and `Process.put/2`. This has the advantage of working
     correctly for `async: true` tests, but fails if any of the code you
     are testing spawns processes and uses your fake S3 module in a
     spawned process (since it's process dictionary is different).
  2. **Using a global agent**: we would start a globally named agent
     and then use `Agent.get/2` and `Agent.update/2` to manage the
     state. This has the advantage of working correctly for tests
     that use the fake S3 module in a spawned process, but is not
     compatible with `async: false` tests. Even worse, if you forget
     to change `async: true` to `async: false`, it can lead to
     flickering tests.

`ProcessTreeDictionary` provides an alternate approach that does not
suffer from these problems:

  * Each test defines its own isolated process tree, which allows you
    to safely use `ProcessTreeDictionary` in `async: true` tests.
  * Since spawned processes belong to the same process tree as their
    parent process, tests that spawn processes are supported.

Here's what a fake implementation of our S3 client looks like using
`ProcessTreeDictionary`:

``` elixir
defmodule MyApp.S3.TestFake do
  def get(bucket, key) do
    key_path(bucket, key)
    |> ProcessTreeDictionary.get(:not_found)
    |> case do
         :not_found -> {:error, :not_found}
         object -> {:ok, object}
       end
  end

  def put(bucket, key, object) do
    # Start the ProcessTreeDictionary if it's not already started
    # so we can write to it.
    ProcessTreeDictionary.ensure_started()

    key_path(bucket, key)
    |> ProcessTreeDictionary.put(object)
  end

  defp key_path(bucket, key) do
    # Scope our dictionary keys using our module name to prevent
    # key conflicts with other uses of ProcessTreeDictionary.
    [__MODULE__, bucket, key]
  end
end
```
