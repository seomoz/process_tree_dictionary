defmodule ProcessTreeDictionaryTest do
  use ExUnit.Case
  doctest ProcessTreeDictionary
  import ExUnit.CaptureIO
  import ExUnit.CaptureLog
  require Logger

  setup_all do
    Application.ensure_all_started(:logger)
    :ok
  end

  test "stores data that can be retrieved later" do
    ProcessTreeDictionary.ensure_started
    ProcessTreeDictionary.put(:foo, 17)
    assert ProcessTreeDictionary.get(:foo) == 17
  end

  test "`get` accepts a default (which defaults to `nil`)" do
    ProcessTreeDictionary.ensure_started
    assert ProcessTreeDictionary.get(:foo, :default) == :default
    assert ProcessTreeDictionary.get(:foo) == nil
  end

  test "`get` returns the default value when the process tree dictionary has not been started" do
    assert ProcessTreeDictionary.get(:foo, :default) == :default
    assert ProcessTreeDictionary.get(:foo) == nil
  end

  test "`get` returns the default value and logs when the group leader process is down" do
    ProcessTreeDictionary.ensure_started()
    ProcessTreeDictionary.put(:bar, 17)

    stop_process_tree_dictionary(:bar)

    logged = capture_log fn ->
      assert ProcessTreeDictionary.get(:bar, :fallback_value) == :fallback_value
    end

    assert logged =~ "Attempting to use the process tree dictionary process after it has already exited"
  end

  test "`put` raises a clear error when the process tree dictionary has not been started yet" do
    assert_raise ProcessTreeDictionary.NotRunningError, fn ->
      assert ProcessTreeDictionary.put(:foo, 17)
    end
  end

  test "`update!` updates an entry in the dictionary" do
    ProcessTreeDictionary.ensure_started
    ProcessTreeDictionary.put(:foo, 17)
    ProcessTreeDictionary.update!(:foo, &(&1 + 2))

    assert ProcessTreeDictionary.get(:foo) == 19
  end

  test "`update! raises an error if the key is not in the dictionary" do
    ProcessTreeDictionary.ensure_started

    assert_raise KeyError, fn ->
      ProcessTreeDictionary.update!(:foo, &(&1 + 2))
    end
  end

  test "error from `update!` does not crash dictionary" do
    ProcessTreeDictionary.ensure_started
    ProcessTreeDictionary.put(:bar, 3)

    try do
      ProcessTreeDictionary.update!(:foo, &(&1 + 2))
    rescue
      _ -> :ok
    end

    assert ProcessTreeDictionary.get(:bar) == 3
  end

  test "`update!` raises a clear error when the process tree dictionary has not been started yet" do
    assert_raise ProcessTreeDictionary.NotRunningError, fn ->
      assert ProcessTreeDictionary.update!(:foo, &(&1 + 1))
    end
  end

  test "allows key paths to be used in place of keys so that you can easily scope your use of the dictionary" do
    ProcessTreeDictionary.ensure_started

    ProcessTreeDictionary.put([:scoped, :a, :b], 10)
    ProcessTreeDictionary.put([:scoped, :a, :c], 11)
    assert ProcessTreeDictionary.get([:scoped, :a, :b]) == 10
    assert ProcessTreeDictionary.get([:scoped, :a]) == %{b: 10, c: 11}

    ProcessTreeDictionary.update!([:scoped, :a, :b], &(&1 * 2))
    assert ProcessTreeDictionary.get([:scoped, :a, :b]) == 20
  end

  test "`update!` with a key path does not crash dictionary when the path is not in dictionary" do
    ProcessTreeDictionary.ensure_started
    ProcessTreeDictionary.put(:bar, 5)

    assert_raise KeyError, fn ->
      ProcessTreeDictionary.update!([:foo, :bar, :baz], &(&1 + 2))
    end

    assert ProcessTreeDictionary.get(:bar) == 5
  end

  test "`ensure_started` is idempotent when called multiple times from the same process" do
    ProcessTreeDictionary.ensure_started
    ProcessTreeDictionary.put(:foo, 17)
    ProcessTreeDictionary.ensure_started
    ProcessTreeDictionary.put(:bar, 23)

    assert ProcessTreeDictionary.get(:foo) == 17
    assert ProcessTreeDictionary.get(:bar) == 23
  end

  test "`ensure_started` is idempotent when called from a process and a child process" do
    ProcessTreeDictionary.ensure_started
    ProcessTreeDictionary.put(:foo, 17)
    test_pid = self()

    spawn_link fn ->
      ProcessTreeDictionary.ensure_started
      ProcessTreeDictionary.put(:bar, 23)
      unblock(test_pid)
    end

    sync()
    assert ProcessTreeDictionary.get(:foo) == 17
    assert ProcessTreeDictionary.get(:bar) == 23
  end

  test "`ensure_started` starts the dictionary when it has previously exited" do
    ProcessTreeDictionary.ensure_started
    ProcessTreeDictionary.put(:foo, 17)

    stop_process_tree_dictionary(:foo)
    ProcessTreeDictionary.ensure_started

    assert ProcessTreeDictionary.get(:foo, :fallback) == :fallback
    ProcessTreeDictionary.put(:foo, 17)
    assert ProcessTreeDictionary.get(:foo, :fallback) == 17
  end

  test "isolates its data from other processes which start their own ProcessTreeDictionary" do
    test_pid = self()

    pid_1 = spawn_link fn ->
      ProcessTreeDictionary.ensure_started
      ProcessTreeDictionary.put(:foo, 17)
      unblock(test_pid)
      sync()
      send(test_pid, {:value_1, ProcessTreeDictionary.get(:foo)})
    end

    pid_2 = spawn_link fn ->
      ProcessTreeDictionary.ensure_started
      ProcessTreeDictionary.put(:foo, 27)
      unblock(test_pid)
      sync()
      send(test_pid, {:value_2, ProcessTreeDictionary.get(:foo)})
    end

    # Wait until both processes have put their values
    sync(); sync()

    unblock(pid_1)
    unblock(pid_2)

    assert_receive {:value_1, 17}
    assert_receive {:value_2, 27}
  end

  test "makes the data accessible to spawned processes" do
    test_pid = self()
    ProcessTreeDictionary.ensure_started

    pid = spawn_link fn ->
      sync()
      send(test_pid, {:value, ProcessTreeDictionary.get(:foo)})
    end

    ProcessTreeDictionary.put(:foo, 14)
    unblock(pid)
    assert_receive {:value, 14}
  end

  test "allows IO to work properly" do
    io = capture_io fn ->
      IO.puts "before ensure_started"
      ProcessTreeDictionary.ensure_started
      IO.puts "after ensure_started"

      test_pid = self()
      spawn_link fn ->
        IO.puts "in spawned process"
        unblock(test_pid)
      end

      sync()
    end

    assert io |> String.strip |> String.split("\n") == [
      "before ensure_started",
      "after ensure_started",
      "in spawned process",
    ]
  end

  test "allows logging to work properly" do
    logs = capture_log fn ->
      Logger.info "before ensure_started"
      ProcessTreeDictionary.ensure_started
      Logger.info "after ensure_started"

      test_pid = self()
      spawn_link fn ->
        Logger.info "in spawned process"
        unblock(test_pid)
      end

      sync()
    end

    assert logs =~ "before ensure_started"
    assert logs =~ "after ensure_started"
    assert logs =~ "in spawned process"
  end

  test "correctly forwards call messages to the group leader" do
    {:ok, pid} = GenServer.start_link(__MODULE__.EchoGenServer, nil)

    :erlang.group_leader(pid, self())
    ProcessTreeDictionary.ensure_started

    assert GenServer.call(:erlang.group_leader, {:some, :message}) == {:echo, {:some, :message}}
  end

  test "correctly forwards cast messages to the group leader" do
    test_pid = self()

    {:ok, pid} = GenServer.start_link(__MODULE__.EchoGenServer, nil)

    :erlang.group_leader(pid, test_pid)
    ProcessTreeDictionary.ensure_started

    GenServer.cast(:erlang.group_leader, {:from, test_pid})
    assert_receive {:echo, {:from, ^test_pid}}
  end

  test "uses carefully named call messages for its client/server protocol to " <>
       "avoid conflicting with messages the existing group leader may handle" do
    {:ok, pid} = GenServer.start_link(__MODULE__.EchoGenServer, nil)

    :erlang.group_leader(pid, self())
    ProcessTreeDictionary.ensure_started

    assert GenServer.call(:erlang.group_leader, {:put, :key, :value}) == {:echo, {:put, :key, :value}}
    assert GenServer.call(:erlang.group_leader, {:get, :key}) == {:echo, {:get, :key}}
  end

  test "when forwarding call messages, does not wait for a reply" do
    {:ok, echo_pid} = GenServer.start_link(__MODULE__.EchoGenServer, nil)
    test_pid = self()

    :erlang.group_leader(echo_pid, test_pid)
    ProcessTreeDictionary.ensure_started

    spawned_pid = spawn_link fn ->
      sync() # block until the `server_fun` is running in our echo gen server

      # For these calls to succeed, our ProcessTreeDictionary process must service
      # messages, and must therefore not be blocked waiting on a reply for a forwarded
      # GenServer call.
      ProcessTreeDictionary.put(:foo, 12)
      assert ProcessTreeDictionary.get(:foo) == 12

      unblock(echo_pid) # now let the `server_fun` proceed
    end

    server_fun = fn ->
      unblock(spawned_pid)
      sync() # wait until our `spawned_pid` process finishes its work
      :server_fun_complete
    end

    assert GenServer.call(:erlang.group_leader, {:run_fun, server_fun}) == :server_fun_complete
  end

  defp sync do
    receive do
      :proceed -> :ok
    after 500 ->
      raise "Did not receive a :proceed message in 500 ms"
    end
  end

  def unblock(pid) do
    send(pid, :proceed)
  end

  defp stop_process_tree_dictionary(key) do
    test_pid = self()

    ProcessTreeDictionary.update!(key, fn val ->
      send(test_pid, {:process_tree_dict_pid, self()})
      val
    end)

    assert_received {:process_tree_dict_pid, process_tree_dict_pid}

    Process.flag(:trap_exit, true)
    Process.exit(process_tree_dict_pid, :crash!)
    assert_receive {:EXIT, ^process_tree_dict_pid, :crash!}
  end

  defmodule EchoGenServer do
    use GenServer

    def handle_call({:run_fun, fun}, _from, state) do
      {:reply, fun.(), state}
    end
    def handle_call(msg, _from, state) do
      {:reply, {:echo, msg}, state}
    end

    def handle_cast({:from, pid}, state) do
      send(pid, {:echo, {:from, pid}})
      {:noreply, state}
    end
  end
end
