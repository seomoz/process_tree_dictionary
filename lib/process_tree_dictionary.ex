defmodule ProcessTreeDictionary do
  require Logger

  @moduledoc """
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
  > spawning process.

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
  see the [Erlang docs](http://erlang.org/doc/apps/kernel/application.html#start-1).
  """

  @type simple_key :: String.t | atom | integer
  @type key :: simple_key | [simple_key]

  @doc """
  Starts a `ProcessTreeDictionary` if this process does not already have access
  to one.

  If a `ProcessTreeDictionary` has already been started in this process or in a
  parent process (prior to this process being spawned), this will be a no-op.

  ### Examples

      iex> ProcessTreeDictionary.ensure_started()
      :ok
  """
  @spec ensure_started() :: :ok
  def ensure_started do
    case get_existing_group_leader() do
      {:already_a_dict, _} -> :ok

      :dict_has_exited ->
        gl_pid = Process.get(:__process_tree_dictionary_original_group_leader)
        {:ok, new_pid} = GenServer.start_link(__MODULE__.Server, {gl_pid, %{}})
        :erlang.group_leader(new_pid, self())
        :ok

      {:not_a_dict, gl_pid} ->
        {:ok, new_pid} = GenServer.start_link(__MODULE__.Server, {gl_pid, %{}})
        Process.put(:__process_tree_dictionary_original_group_leader, gl_pid)
        :erlang.group_leader(new_pid, self())
        :ok
    end
  end

  @doc """
  Puts the given `value` into the dictionary under the given `key`.

  The `key` can be a simple key (such as a string, atom, or integer)
  or a key path, expressed as a list.

  Raises an error if a `ProcessTreeDictionary` has not been started.

  ### Examples

      iex> ProcessTreeDictionary.ensure_started()
      iex> ProcessTreeDictionary.put(:language, "Elixir")
      :ok

      iex> ProcessTreeDictionary.ensure_started()
      iex> ProcessTreeDictionary.put([MyApp, :meta, :language], "Elixir")
      :ok
  """
  @spec put(key :: key, value :: any) :: :ok
  def put(key, value) do
    call_server(:put, [key, value])
  end

  @doc """
  Gets the value for the given `key` from the dictionary.

  Returns the `default` value if the `ProcessTreeDictionary` has not been started
  or if the dictionary does not contain `key`. The `key` can be a simple key
  (such as a string, atom, or integer) or a key path, expressed as a list.

  ### Examples

      iex> ProcessTreeDictionary.ensure_started()
      iex> ProcessTreeDictionary.put(:language, "Elixir")
      iex> ProcessTreeDictionary.get(:language)
      "Elixir"

      iex> ProcessTreeDictionary.ensure_started()
      iex> ProcessTreeDictionary.put([MyApp, :meta, :language], "Elixir")
      iex> ProcessTreeDictionary.get([MyApp, :meta, :language])
      "Elixir"
  """
  @spec get(key :: key, default :: any) :: any
  def get(key, default \\ nil) do
    call_server(:get, [key, default], fn -> default end)
  end

  @doc """
  Updates the `key` in the dictionary using the given function.

  The `key` can be a simple key (such as a string, atom, or integer) or a key
  path, expressed as a list.

  If the key does not exist, raises a `KeyError`.

  ### Examples

      iex> ProcessTreeDictionary.ensure_started()
      iex> ProcessTreeDictionary.put(:language, "Elixir")
      iex> ProcessTreeDictionary.update!(:language, &String.downcase/1)
      iex> ProcessTreeDictionary.get(:language)
      "elixir"

      iex> ProcessTreeDictionary.ensure_started()
      iex> ProcessTreeDictionary.put([MyApp, :meta, :language], "Elixir")
      iex> ProcessTreeDictionary.update!([MyApp, :meta, :language], &String.downcase/1)
      iex> ProcessTreeDictionary.get([MyApp, :meta, :language])
      "elixir"
  """
  @spec update!(key :: key, ((any) -> any)) :: any
  def update!(key, fun) do
    call_server(:update!, [key, fun])
  end

  defp call_server(message_name, args,
    fallback \\ fn -> raise __MODULE__.NotRunningError end
  ) do
    case get_existing_group_leader() do
      :dict_has_exited ->
        Logger.warn "Attempting to use the process tree dictionary process after it " <>
                    "has already exited for message: #{inspect message_name}, #{inspect args}. " <>
                    "The fallback callback will be used."
        fallback.()

      {:not_a_dict, _} -> fallback.()

      {:already_a_dict, gl_pid} ->
        message = [__MODULE__.Server, message_name | args] |> List.to_tuple
        case GenServer.call(gl_pid, message) do
          {__MODULE__.Server, :run_fun, fun} -> fun.()
          other_response -> other_response
        end
    end
  end

  defp get_existing_group_leader do
    group_leader = :erlang.group_leader

    case Process.info(group_leader, :dictionary) do
      {:dictionary, dict} ->
        case Keyword.get(dict, :"$initial_call") do
          {__MODULE__.Server, _fun, _args} -> {:already_a_dict, group_leader}
          _otherwise -> {:not_a_dict, group_leader}
        end

      nil -> :dict_has_exited
    end
  end

  defmodule Server do
    use GenServer

    @moduledoc false

    def handle_call({__MODULE__, :put, key, value}, _from, {gl, dict}) do
      updated = put_in(dict, to_key_path(key), value)
      {:reply, :ok, {gl, updated}}
    end
    def handle_call({__MODULE__, :get, key, default}, _from, {gl, dict}) do
      key_path = to_key_path_with_last_default(key, default)
      value = get_in(dict, key_path)
      {:reply, value, {gl, dict}}
    end
    def handle_call({__MODULE__, :update!, key, fun}, _from, {gl, dict}) do
      key_not_found_ref = make_ref()
      get_path = to_key_path_with_last_default(key, key_not_found_ref)
      if get_in(dict, get_path) == key_not_found_ref do
        client_fun = fn -> raise KeyError, key: key end
        {:reply, {__MODULE__, :run_fun, client_fun}, {gl, dict}}
      else
        updated = update_in(dict, to_key_path(key), fun)
        {:reply, :ok, {gl, updated}}
      end
    end
    def handle_call(unrecognized_message, from, state) do
      forward_message({:"$gen_call", from, unrecognized_message}, state)
    end

    def handle_cast(unrecognized_message, state) do
      forward_message({:"$gen_cast", unrecognized_message}, state)
    end

    def handle_info(message, state) do
      forward_message(message, state)
    end

    defp to_key_path(key, fallback \\ %{})
    defp to_key_path(key, fallback) when not is_list(key) do
      key |> List.wrap |> to_key_path(fallback)
    end
    defp to_key_path(list, fallback) do
      Enum.map(list, &Access.key(&1, fallback))
    end

    defp to_key_path_with_last_default(key, default) do
      [last_key | rest] = key |> List.wrap |> Enum.reverse
      [Access.key(last_key, default) | to_key_path(rest)] |> Enum.reverse
    end

    defp forward_message(message, {original_group_leader, _} = state) do
      send(original_group_leader, message)
      {:noreply, state}
    end
  end

  defmodule NotRunningError do
    @moduledoc """
    Raised when attempting to write to a `ProcessTreeDictionary`
    before it has been started or after it has exited.
    """

    defexception message: "Must start a ProcessTreeDictionary before writing to it (and must still be up)"
  end
end
